#!/bin/bash
#
# launcher script, checks if this is the cluster manager, performs some other checks, manages log files and launches the operation
#
# Invokation: launcher.sh operation [file system name]
#
# Output: all output is logged to $logF
#
# Author: Nils Haustein
#
#******************************************************************************************************** 
# Export the path including the linux and GPFS binaries in case this script is invoked from a schedule
export PATH=$PATH:/usr/bin:/usr/sbin:/usr/lpp/mmfs/bin
#
# define global variables
# -------------------------
# file system name, if this is set and $2 is empty this name is used. Otherwise it will terminate
fsName="gpfs0"

# path where the scripts are located
scriptPath="/root/silo"

# log file directory
logDir="/var/log/hsm"

# log files for this type of operation to keep including this process - keep the $verKeep latest version
verKeep=3

# log files for this type of operation to compress - compress the $verKeep + $verComp version
verComp=3

#define return codes
rcGood=0  # successful run
rcWarn=1  # run was ok, some warnings however
rcErr=2   # failed

# initialize the local node 
localNode=$(/usr/lpp/mmfs/bin/mmlsnode -N localhost | cut -d'.' -f1)

# current date
curDate="$(date +%Y%m%d%H%M%S)"

# operation code is in $1
op="$1"


#********************************************** MAIN *********************************

# check operation and assign command
case $op in
"backup") 
  # runs DR-Backup
  cmd=$scriptPath"/backup.sh";;  
"migrate") 
  # runs selective migration (scheduled)
  cmd=$scriptPath"/migrate.sh";;
*) echo "ERROR: wrong operation code: $op"
   echo "SYNTAX: $0 operation [file system name]"
   echo "        operation: backup | migrate"
   echo "        file system name is optional, default is $fsName"
   exit $rcErr;;
esac

# create logfile dir if not exist
if [[ ! -d $logDir ]];
then
  mkdir -p $logDir
fi

# assing logfile name
logF=$logDir"/"$op"_"$curDate".log"


#present banner and initialize log file
echo "$(date) CHECK: started with operation $op on $(hostname)" > $logF

#assign and check file system name. If $2 is set then use this, if not use the pre-defined parameter. If this is empty then terminate
echo "$(date) CHECK: assigning and checking file system name" >> $logF
if [[ ! -z $2 ]];
then 
  fsName=$2
fi
if [[ -z $fsName ]];
then
  echo "ERROR: file system name not defined. Either pass it as parameter to this script. Or initialized the global variable fsName" >> $logF
  exit $rcErr
fi
mmlsfs $fsName > /dev/null 2>&1
rc=$?
if (( rc > 0 ));
then
  echo "ERROR: file system $fsName does not exist." >> $logF
  exit $rcErr
fi
# now export the parameter $fsName which could be used by scripts being launched
export $fsName


#check that localNode initialized above is not empty
#perform this check prior deleting the log files to keep the previous one.
if [[ -z $localNode ]];
then
  echo "ERROR: local node name could not be initialized, node may be down." >> $logF
  exit $rcErr
fi


# delete and compress older  logfiles prior to logging anything
echo "$(date) CHECK: cleaning up log files  $op" >> $logF
lFiles=$(ls -r $logDir/$op*)
i=1
#echo "DEBUG: files=$lFiles"
for f in $lFiles;
do
  if (( i > verKeep ));
  then
    if (( i > (verComp+verKeep) ));
    then
      rm -f $f >> $logF 2>&1
    else
      gzip $f >> $logF 2>&1
    fi
  fi
  (( i=i+1 ))
done


#check if node is cluster manager
echo "$(date) CHECK: checking if this node is cluster manager" >> $logF
clusterMgr=$(/usr/lpp/mmfs/bin/mmlsmgr -c | sed 's|.*(||' | sed 's|)||')
if [ "$localNode" != "$clusterMgr" ]; 
then
  echo "INFO: this node is not cluster manager, exiting." >> $logF
  echo "DEBUG: localNode=$localNode  clusterMgr=$clusterMgr" >> $logF
  exit $rcGood
fi

# check if node is active
echo "$(date) CHECK: checking if this node is active" >> $logF
state=0
state=$(mmgetstate | grep "$localNode" | awk '{print $3}')
if [[ ! "$state" == "active" ]];
then
  echo "ERROR: node $localNode is not active (state=$state), exiting." >> $logF
  exit $rcErr
fi

# check if file system is mounted
echo "$(date) CHECK: checking if this node has file system $fsName mounted" >> $logF
mounted=0
mounted=$(mmlsmount $fsName -L | grep "$localNode" | wc -l)
if (( mounted == 0 ));
then 
  echo "ERROR: file system $fsName is not mounted on node $localNode, exiting." >> $logF
  exit $rcErr
fi


#now run the command according to the operation code assigned above and evaluate the result
eval $cmd >> $logF 2>&1
rc=$?
if (( rc == 0 ));
then 
  echo "$(date) CHECK: command $cmd finished with status=GOOD" >> $logF
elif (( rc == 1 ));
then
  echo "$(date) CHECK: command $cmd finished with status=WARNING" >> $logF
  # send WARNING event ...
else
  echo "$(date) CHECK: command $cmd finished with status=ERROR (rc=$rc)" >> $logF
  rc=2
  # send ERROR event ...
fi
exit $rc
