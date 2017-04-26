#!/bin/bash
#
# migrate script, does the following
# - migrates files according to pre-defined policy
#
# Invokation: migrate.sh [file system name]
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
     # ADJUST: initialize fsName with default name which is only applied if $1 is empty and fsName has not been exported
	 fsName=""
   fi
else
   fsName="$1"
fi

# ADJUST: name of the policy file used for migration, such as migrate_policy.txt
polName=""

# ADJUST: directory for temp files of policy engine (-s parameter), the default (/tmp)
workDir=""

# ADJUST: mmapplypolicy parameters 
mmapplyOpts="-N nsdNodes -m 1 -B 256"

#define return codes
rcGood=0  # successful run
rcWarn=1  # run was ok, some warnings however
rcErr=2   # failed

# global return code
globalRC=0


#**************************** Main ************************************
# present banner
echo "$(date) MIGRATE: migration operation started on $(hostname)."

# check if file system is initialized
if [[ -z $fsName ]];
then 
  echo "ERROR: file system name is not initialized, exit"
  exit $rcErr
fi

# check if policy file exists
if [[ ! -a $polName ]]; 
then
  echo "ERROR: policy file $polName does not exist. Exit."
  exit $rcErr
fi

# check if workdir is to be used and if so add it to the options
if [[ ! -z $workDir ]];
then
  mmapplyOpts="$mmapplyOpts -s $workDir"
fi

#start migration
echo "$(date) MIGRATE: Starting  migration"
echo "DEBUG: mmapplypolicy $fsName -P $polName $mmapplyOpts"
mmapplypolicy $fsName -P $polName $mmapplyOpts
rc=$?
echo "$(date) MIGRATE: Finished migration (rc=$rc)"
if (( rc > 0 ));
then
  echo "ERROR: Migration failed with return code $rc"
  (( globalRC=globalRC+1 ))
fi


# present ending banner
echo "$(date) MIGRATE: operation ended on $(hostname) with gobalRC=$globalRC."
if (( globalRC > 0 ));
then
  exit $rcErr
else 
  exit $rcGood
fi
