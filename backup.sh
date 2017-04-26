#!/bin/bash
#
# backup script, does the following
# - create snapshot when required
# - perform mmbackup 
# - delete snapshot when required
#
# Invokation: backup.sh [file system name]
#             file system name is optional, can also be passed through an exported variable
#
# Output: all output is logged to STDOUT
#
# Author: Nils Haustein
#
#******************************************************************************************************** 
#
# Global definitions
#--------------------
# file system name is either given with $1 or it is exported as fsName or we initialize it with a default
if [[ -z $1 ]];
then
   if [[ -z $fsName ]];
   then
     # initialize fsName with default name which is only applied if $1 is empty and fsName has not been exported
	 fsName=""
   fi
else
   fsName="$1"
fi

# name of TSM server to be used with mmbackup, if not set then we used the default server
tsmServ=""

# directory for temp files during mmbackup (-s parameter with mmbackup), if not set we use the default (/tmp)
workDir=""

# name of global snapshot for mmbackup, if this is not set then mmbackup will not backup from snapshot
snapName=""

# mmbackup parameters to be used with mmbackup, adjust if necessary
mmbackupOpts="-N nsdNodes -v --max-backup-count 4096 --max-backup-size 80M --backup-threads 1 --expire-threads 1"

#define return codes
rcGood=0  # successful run
rcWarn=1  # run was ok, some warnings however
rcErr=2   # failed


#*************************** Main ***************************
# present banner
echo "$(date) BACKUP: backup operation for file system $fsName started on $(hostname)."

# check if file system is initialized
if [[ -z $fsName ]];
then 
  echo "ERROR: file system name is not initialized, exit"
  exit $rcErr
fi

# check if snapshot is required and if so check if one exist already and if so exit, otherwise, create snapshot
if [[ ! -z $snapName ]];
then 
  # check if snapshot exists and if so exit with ERROR
  echo "$(date) BACKUP: checking if snapshots $snapName exist on $fsName"
  snaps=""
  snaps=$(mmlssnapshot $fsName -Y | grep -v ":HEADER:" | cut -d':' -f 8)
  for s in $snaps
  do
    if [[ "$s" == "$snapName" ]];
	then 
	  echo "BACKUP: ERROR a snapshot $snapName exists already. Delete snapshot and try again."
      exit $rcErr
    fi
  done
  # create snapshot and if this fails exit with ERROR
  echo "$(date) BACKUP: Creating snapshot $snapName"
  #echo "DEBUG: mmcrsnapshot $fsName $snapName"
  mmcrsnapshot $fsName $snapName
  rc=$?
  if (( rc > 0 ));
  then
    echo "BACKUP: ERROR create snapshot failed with rc=$rc"
    exit $rcErr
  fi
fi


#start mmbackup 
echo "$(date) BACKUP: Starting mmbackup for file system $fsName"

# ignore include list with mmbackup because they should only contain mgmt-class bindings
# echo "DEBUG: Exporting MMBACKUP_IGNORE_INCLUDE=1"
# export MMBACKUP_IGNORE_INCLUDE=1
#run mmbackup with -q every other day when scheduled before 12:00 noon

# perform shadow DB sync every Sunday
rebuild=""
d=$(date +%u)
if (( d == 7 )); 
then
  rebuild="-q"
fi

# assign mmbackup options (snapshot when required, tsmserver, rebuild)
bOpts=""
if [[ ! -z $snapName ]];
then
  bOpts="-S $snapName"
fi
if [[ ! -z $tsmServ ]];
then 
  bOpts="$bOpts --tsm-servers $tsmServ"
fi
if [[ ! -z $rebuild ]];
then
  bOpts="$bOpts -q"
fi 
if [[ ! -z $workDir ]];
then
  bOpts="$bOpts -s $workDir"
fi

echo "DEBUG: mmbackup $fsName $bOpts $mmbackupOpts"
mmbackup_rc=0
mmbackup $fsName $bOpts $mmbackupOpts
mmbackup_rc=$?
#examine mmbackup return code: 0 good, 1 warning, 2 error
if (( mmbackup_rc > 0 ));
then
  if (( mmbackup_rc > 1 ));
  then 
    echo "BACKUP: ERROR mmbackup failed with rc=$mmbackup_rc, deleting snapshot and exiting"
    mmbackup_rc=2
  else
    echo "BACKUP: WARNING mmbackup ended with rc=$mmbackup_rc, deleting snapshot and exiting."
  fi
fi

#delete snapshot when required
if [[ ! -z $snapName ]];
then
  echo "$(date) BACKUP: Deleting snapshot $snapName"
  # echo "DEBUG: mmdelsnapshot $fsName $snapName"
  mmdelsnapshot $fsName $snapName
  rc=$?
  if (( rc > 0 )); 
  then 
    echo "BACKUP: ERROR deleting snapshot $snapName failed with rc=$rc"
  fi
fi


# evaluate return codes and exit according to defined return codes
if (( mmbackup_rc > 1 ));
then 
  echo "$(date) BACKUP: operation for file system $fsName ended with ERRORS"
  exit $rcErr
elif (( mmbackup_rc == 1 || rc > 0 ));
then 
  echo "$(date) BACKUP: operation for file system $fsName ended with WARNINGS"
  exit $rcWarn
else
  echo "$(date) BACKUP: operation for file system $fsName ended with SUCCESS"
  exit $rcGood
fi
