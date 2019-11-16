#!/bin/bash

################################################################################
# The MIT License (MIT)                                                        #
#                                                                              #
# Copyright (c) 2019 Nils Haustein                             				   #
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
# Invokation: backup.sh file-system-name [fileset-name]
#             file-system-name is the name of the file system to be backed up
#             file-set-name (optional) name of the independent fileset to backup from
#
# Output: all output is logged to STDOUT
#
# Author: Nils Haustein
#
# 
# Change History
# --------------
# 2017: first implementation for client project
# 10/18/19: added license for github
# 11/14/19: add GPFS path for GPFS commands
# 11/15/19; added the option to backup from fileset, fileset name is given with the call
##################################################################################

#
# User defined parameters
# -----------------------
#
# name of TSM server to be used with mmbackup, if not set then we used the default server
tsmServ=""

# name of global snapshot for mmbackup, if this is not set then mmbackup will not backup from snapshot
snapName=""

# mmbackup parameters to be used with mmbackup, adjust if necessary
backupOpts="-N nsdNodes -v --max-backup-count 4096 --max-backup-size 80M --backup-threads 2 --expire-threads 2"

# Constants
# ----------
# specifies the path for the GPFS binaries
gpfsPath="/usr/lpp/mmfs/bin"

#define return codes
rcGood=0  # successful run
rcWarn=1  # run was ok, some warnings however
rcErr=2   # failed

# default file system name
fsName="$1"
fsetName="$2"

#*************************** Main ***************************
# present banner
echo "$(date) BACKUP: backup operation for file system $fsName started on $(hostname)."

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
if [[ ! -z $fsetName ]];
then
   fsDev=$fsetPath
   bOpts="$bOpts --scope inodespace"
else
   fsDev=$fsName
fi

echo "BACKUP: DEBUG mmbackup $fsDev $bOpts $backupOpts"
mmbackup_rc=0
$gpfsPath/mmbackup $fsDev $bOpts $backupOpts
mmbackup_rc=$?
#examine mmbackup return code: 0 good, 1 warning, 2 error
if (( mmbackup_rc > 0 ));
then
  if (( mmbackup_rc > 1 ));
  then 
    echo "BACKUP: ERROR mmbackup for $fsDev failed with rc=$mmbackup_rc."
    mmbackup_rc=2
  else
    echo "BACKUP: WARNING mmbackup for $fsDev ended with rc=$mmbackup_rc."
  fi
fi

#delete snapshot when required
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
