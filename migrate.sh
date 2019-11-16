#!/bin/bash
#
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
# Name: migrate.sh
#
# migrate script, does the following
# - migrates files according to pre-defined policy
#
# Invokation: migrate.sh file-system-name [policy-file-name]
#             file-system-name is the name of the file system to be backed up
#             policy-file-name (optional) name of the policyfile 
#
# Output: all output is logged to STDOUT
#
# Author: Nils Haustein
# 
# Change History
# --------------
# 2017: first implementation for client project
# 10/18/19: added license for github
# 11/14/19: add GPFS path for GPFS commands
# 11/15/19: add policy file name passed with the call
# 
#******************************************************************************************************** 
#
# Global definitions
#--------------------

# default fully qualified path and file name of the policy fie. This is used if the policy file name is not given with the call
def_polName="./migrate_policy.txt"

# ADJUST: directory for temp files of policy engine (-s parameter), the default (/tmp)
workDir=""

# ADJUST: mmapplypolicy parameters 
mmapplyOpts="-N nsdNodes -m 1 -B 1000 --single-instance"


# Constants
# -----------

# GPFS path to binaries
gpfsPath="/usr/lpp/mmfs/bin"

#define return codes
rcGood=0  # successful run
rcWarn=1  # run was ok, some warnings however
rcErr=2   # failed
# global return code
globalRC=0

# name of the file system for the operation
fsName="$1"

# name of the policy file used for migration, given with the call
polName="$2"


#**************************** Main ************************************
# present banner
echo "$(date) MIGRATE: migration operation started on $(hostname) for file system $fsName."

# check if file system is initialized
if [[ -z $fsName ]];
then 
  echo "MIGRATE: ERROR file system name is not initialized, exit"
  exit $rcErr
fi

# check if policy file exists
if [[ -z $polName ]];
then
  if [[ ! -z $def_polName ]];
  then
    polName=$def_polName
  else
    echo "MIGRATE: ERROR policy file name not specified, exiting."
    exit $rcErr
  fi
fi
if [[ ! -a $polName ]]; 
then
  echo "MIGRATE: ERROR policy file $polName does not exist. Exit."
  exit $rcErr
fi

# check if workdir is to be used and if so add it to the options
if [[ ! -z $workDir ]];
then
  mmapplyOpts="$mmapplyOpts -s $workDir"
fi

#start migration
echo "$(date) MIGRATE: Starting  migration for file system $fsName with policyfile $polName"
echo "DEBUG: mmapplypolicy $fsName -P $polName $mmapplyOpts"
$gpfsPath/mmapplypolicy $fsName -P $polName $mmapplyOpts
rc=$?
echo "$(date) MIGRATE: Finished migration (rc=$rc)"
if (( rc > 0 ));
then
  echo "MIGRATE: ERROR Migration failed with return code $rc"
  (( globalRC=globalRC+1 ))
fi


# present ending banner
echo "$(date) MIGRATE: operation ended on $(hostname) for file system $fsName with policy $polName with gobalRC=$globalRC."
if (( globalRC > 0 ));
then
  exit $rcErr
else 
  exit $rcGood
fi



