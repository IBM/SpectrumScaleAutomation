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
logDir="/var/log/automation"

# define the node class where the operation has to run on, if not set it runs on the local node
# if the local node is part of the node class it will be preferred
nodeClass=""

# log files for this type of operation to keep including this process - keep the $verKeep latest version
verKeep=3

# log files for this type of operation to compress - compress the $verKeep + $verComp version
verComp=3

#define return codes
rcGood=0  # successful run
rcWarn=1  # run was ok, some warnings however
rcErr=2   # failed

# current date
curDate="$(date +%Y%m%d%H%M%S)"

# operation code is in $1
op="$1"


#********************************************** MAIN *********************************

# check operation and assign command
# new operations can be added here
case $op in
"backup") 
  # runs DR-Backup
  cmd=$scriptPath"/backup.sh";;  
"migrate") 
  # runs selective migration (scheduled)
  cmd=$scriptPath"/migrate.sh";;
"premigrate") 
  # runs premigration
  cmd=$scriptPath"/premigrate.sh";;
"check")
  # runs premigration
  cmd=$scriptPath"/check_hsm.sh";;
"test")
  # just a simple test using ls
  cmd="/usr/bin/ls";;
*) echo "ERROR: wrong operation code: $op"
   echo "SYNTAX: $0 operation [file system name]"
   echo "        operation: backup | migrate | premigrate | check"
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
  echo "CHECK: ERROR file system name not defined. Either pass it as parameter to this script. Or initialized the global variable fsName" >> $logF
  exit $rcErr
fi
mmlsfs $fsName > /dev/null 2>&1
rc=$?
if (( rc > 0 ));
then
  echo "CHECK: ERROR file system $fsName does not exist." >> $logF
  exit $rcErr
fi
# now export the parameter $fsName which could be used by scripts being launched
export $fsName


#check that localNode initialized above is not empty
#perform this check prior deleting the log files to keep the previous one.
localNode=$(mmlsnode -N localhost | cut -d'.' -f1)
if [[ -z $localNode ]];
then
  echo "CHECK: ERROR local node name could not be initialized, node may be down." >> $logF
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
clusterMgr=$(mmlsmgr -c | sed 's|.*(||' | sed 's|)||')
if [ "$localNode" != "$clusterMgr" ]; 
then
  echo "INFO: this node is not cluster manager, exiting." >> $logF
  echo "DEBUG: localNode=$localNode  clusterMgr=$clusterMgr" >> $logF
  exit $rcGood
fi

#-------------------------------
# determine the node to run this command based on node class and node and file system state
localNode=$(mmlsnode -N localhost | cut -d'.' -f1)
echo "INFO: local node is: $localNode" >> $logF
allNodes=""
sortNodes=""
# if node class is set up determine node names in node class
if [[ ! -z $nodeClass ]];
then
   echo "INFO: node class to select the node from is: $nodeClass" >> $logF
   allNodes=$(mmlsnodeclass $nodeClass -Y | grep -v HEADER | cut -d':' -f 10 | sed 's|,| |g')
   if [[ -z $allNodes ]]
   then
     echo "CHECK: WARNING node class $nodeClass is empty, using local node" >> $logF
     sortNodes=$localNode
   else
     # reorder allNodes to have localNode first, if it exists
     for n in $allNodes;
     do
       if [[ "$n" == "$localNode" ]];
       then
         sortNodes=$localNode" "$sortNodes
       else
         sortNodes=$sortNodes" "$n
       fi
     done
   fi
else
   # if no node class is defined set the local node 
   sortNodes=$localNode
fi

# select the node to execute the command based on state 
echo "INFO: The following nodes are checked to run the operation: $sortNodes" >> $logF
execNode=""
for n in $sortNodes;
do
  # determine node state
  state=$(mmgetstate -N $n -Y | grep -v ":HEADER:" | cut -d':' -f 9)
  if [[ "$state" != "active" ]];
  then
	continue
  else 
	# determine file system state on node
	mNodes=$(mmlsmount $fsName -Y | grep -v HEADER | grep -E ":RW:" | cut -d':' -f 12)
	for m in $mNodes;
	do
	  if [[ "$m" == "$n" ]];
	  then
		execNode=$m
      fi		
	done
	if [[ ! -z "$execNode" ]];
	then
	  break
	fi
  fi
done

if [[ -z "$execNode" ]];
then
  echo "$(date) CHECK: ERROR no node is in appropriate state to run the job, exiting." >> $logF
  exit $rcErr
fi

#now run the command according to the operation code assigned above and evaluate the result
echo "$(date) CHECK: INFO Running command for $op on node $execNode" >> $logF
ssh $execNode "$cmd" >> $logF 2>&1
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

