#!/bin/bash

################################################################################
# The MIT License (MIT)                                                        #
#                                                                              #
# Copyright (c) 2020 Nils Haustein                             				   #
#                                                                              #
# Permission is hereby granted, free of charge, to any person obtaining a copy #
# of this software and associated documentation files (the "Software"), to deal#
# in the Software without restriction, including without limitation the rights #
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell    #
# copies of the Software, and to permit persons to whom the Software is        #
# furnished to do so, subject to the following conditions:                     #
#                                                                              #
# The above copyright notice and this permission notice shall be included in   #
# all copies or substantial portions of the Software.                          #
#                                                                              #
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR   #
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,     #
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE  #
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER       #
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,#
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE#
# SOFTWARE.                                                                    #
################################################################################
# 
# Name: backup.sh
#
# backup script, does the following
# - create snapshot when required
# - perform mmbackup 
# - delete snapshot when required
#
# Invokation: backup.sh file-system-name [fileset-name] [backup type]
#             file-system-name is the name of the file system to be backed up
#             file-set-name (optional) name of the independent fileset to backup from
#			  backup-type (optional) can be full or incremental (incremental is default)
#
#             Note, the order of the command line parameters matters
#
# Output: all output is logged to STDOUT
#
# Author: Nils Haustein
#
# Version: 1.2
#
# Change History
# --------------
# 2017: first implementation for client project
# 10/18/19: added license for github
# 11/14/19: add GPFS path for GPFS commands
# 11/15/19: added the option to backup from fileset, fileset name is given with the call
# 06/10/20: add config parameter $weekday defining when to run mmbackup -q (version 1.1)
# 06/11/20: NYU: for fileset level backup check if .mmbackupShadow* exists in the path and if not then run full backup
# 08/14/20: streamlined return message, added hint to rebuild shadow DB if mmbackup rc > 1 (version 1.2)
##################################################################################

#
# User defined parameters
# -----------------------
#
# name of TSM server to be used with mmbackup, if not set then we used the default server
tsmServ=""

# mmbackup parameters to be used with mmbackup, adjust if necessary
backupOpts="-N g8_node3 -v --max-backup-count 4096 --max-backup-size 80M --backup-threads 2 --expire-threads 2"

# name of global snapshot for mmbackup, if this is not set then mmbackup will not backup from snapshot
snapName=""

# specify the day of the week when to run mmbackup -q
# 0=skip, 1=monday, 2=tuesday, ... 7=sunday
weekDay=0

# Constants
# ----------
# version of the program
ver=1.2

# specifies the path for the GPFS binaries
gpfsPath="/usr/lpp/mmfs/bin"

#define return codes
rcGood=0  # successful run
rcWarn=1  # run was ok, some warnings however
rcErr=2   # failed

# Assign command line parameter
# ------------------------------
# assign file system name
fsName="$1"

# assign file set name
fsetName="$2"


#*************************** Main ***************************
# present banner
echo "$(date) BACKUP: backup operation version $ver for file system $fsName started on $(hostname)."

# check if file system is initialized
if [[ -z $fsName ]];
then 
  echo "BACKUP: ERROR file system name is not initialized, exit"
  exit $rcErr
fi

# if fileset name is given then check if fileset exists
if [[ ! -z $fsetName ]];
then
  fsetPath=$($gpfsPath/mmlsfileset $fsName $fsetName | grep "$fsetName" | grep "Linked" | awk '{print $3}')
  if [[ -z $fsetPath ]];
  then 
    echo "BACKUP: ERROR fileset $fsetName does not exist in filesystem $fsName or is not linked"
	exit $rcErr
  else
    echo "BACKUP: fileset $fsetName is on path $fsetPath"
  fi
fi

# check if snapshot is required and if so check if one exist already and if so exit, otherwise, create snapshot
if [[ ! -z $snapName ]];
then 
  # assign special options if this is a file set level snapshot
  if [[ ! -z $fsetName ]];
  then 
    snapOpts="-j $fsetName"
  else
    snapOpts=""
  fi
  # check if snapshot exists and if so exit with ERROR
  echo "BACKUP: checking if snapshot $snapName exist on $fsName $snapOpts"
  snaps=""
  snaps=$($gpfsPath/mmlssnapshot $fsName $snapOpts -Y | grep -v ":HEADER:" | cut -d':' -f 8)
  for s in $snaps
  do
    if [[ "$s" == "$snapName" ]];
	then 
	  echo "BACKUP: ERROR a snapshot $snapName exists already. Delete snapshot and try again."
      exit $rcErr
    fi
  done
  # create snapshot and if this fails exit with ERROR
  if [[ ! -z $fsetName ]];
  then 
    snapOpts="$fsetName:$snapName"
  else
    snapOpts="$snapName"
  fi
  echo "$(date) BACKUP: Creating snapshot $snapOpts for file system $fsName"
  echo "BACKUP: DEBUG mmcrsnapshot $fsName $snapOpts"
  $gpfsPath/mmcrsnapshot $fsName $snapOpts
  rc=$?
  if (( rc > 0 ));
  then
    echo "BACKUP: ERROR create snapshot $snapOpts failed with rc=$rc"
    exit $rcErr
  fi
fi


#start mmbackup 
echo "$(date) BACKUP: Starting mmbackup for file system $fsName"

# ignore include list with mmbackup because they should only contain mgmt-class bindings
# echo "DEBUG: Exporting MMBACKUP_IGNORE_INCLUDE=1"
# export MMBACKUP_IGNORE_INCLUDE=1
#run mmbackup with -q every other day when scheduled before 12:00 noon

# perform shadow DB sync on the weekday specified: 1=monday, 2=tuesday, ... 7=sunday
# if weekDay=0 then skip query
rebuild=""
if (( weekDay > 0 ));
then 
  d=$(date +%u)
  if (( d == $weekDay )); 
  then
    rebuild="-q"
  fi
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
if [[ ! -z $fsetName ]];
then
   fsDev=$fsetPath
   bOpts="$bOpts --scope inodespace"
   
   # the first backup of a fileset must be full, therefore check if the shadow DB exists and if not then run -t full
   fName="/ibm/auditfs/test/.mmbackupshadow*"
   ls $fsetPath/.mmbackupShadow* > /dev/null 2>&1
   rc=$?
   if (( rc != 0 ));
   then
     bOpts="$bOpts -t full"
   fi
else
   fsDev=$fsName
fi


echo "BACKUP: DEBUG $gpfsPath/mmbackup $fsDev $bOpts $backupOpts"
mmbackup_rc=0
$gpfsPath/mmbackup $fsDev $bOpts $backupOpts
mmbackup_rc=$?


#delete snapshot when required
rc=0
if [[ ! -z $snapName ]];
then
  if [[ ! -z $fsetName ]];
  then 
    snapOpts="$fsetName:$snapName"
  else
    snapOpts="$snapName"
  fi
  echo "$(date) BACKUP: Deleting snapshot $snapName"
  echo "BACKUP: DEBUG mmdelsnapshot $fsName $snapOpts"
  $gpfsPath/mmdelsnapshot $fsName $snapOpts
  rc=$?
  if (( rc > 0 )); 
  then 
    echo "BACKUP: ERROR deleting snapshot $snapOpts failed with rc=$rc"
  fi
fi

# evaluate return codes and exit according to defined return codes
if (( mmbackup_rc > 1 ));
then 
  echo "$(date) BACKUP: ERROR running backup for $fsDev (rc=$mmbackup_rc)"
  echo "BACKUP HINT: investigate the log file. Consider resynchronizing or rebuilding the shadow data base (mmbackup options -q or --rebuild)."
  exit $rcErr
elif (( mmbackup_rc == 1 || rc > 0 ));
then 
  echo "$(date) BACKUP: WARNING running backup for $fsDev. "
  if (( mmbackup_rc == 1 )); then
    echo "BACKUP HINT: investigate the mmbackup log file and the SP server log. Run backup in debug mode (mmbackup option -L)."
  elif (( rc > 0 )); then
    echo "BACKUP HINT: delete the snapshot and try again."
  fi	
  exit $rcWarn
else
  echo "$(date) BACKUP: SUCESS running backup for $fsDev."
  exit $rcGood
fi
