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
# Name: launcher.sh
#
# Version 2.1
#
# launcher script, checks if this is the cluster manager, performs some other checks, manages log files and launches the operation
#
# Invokation: launcher.sh operation [file system name] [second argument]
#             file-system-name is the name of the file system for the operation (mandatory)
#             second-argument is a second argument passed to the service script (optional)
#               for backup: it can specify the fileset name
#               for migrate: it can specify the policy file name
#               for check: it can specify the component
#
#
# Output: all output is logged to $logF
#
# Author: Nils Haustein
#
#
# Change History:
# ----------------
# 2017: first implementation in client project
# 10/18/19: added licenses for github
# 11/14/19: export PARM does not work since we use ssh, pass PARM to the service script (fsName)
#           add GPFS command path to all GPFS commands   
#           add sending events if the custom json exists
# 11/15/19: add second argument for the service script (optional)
# 12/11/19: implement check option with check_spectrumarchive.sh
#           define event codes as constants and check if they are defined in the custom event file
#
#******************************************************************************************************** 

# Export the path including the linux and GPFS binaries in case this script is invoked from a schedule
export PATH=$PATH:/usr/bin:/usr/sbin:/usr/lpp/mmfs/bin
#
# User defined variables
# -------------------------

# default file system name, if this is set and $2 is empty this name is used. If $2 is given then it is being used.
def_fsName=""

# path where the automation scripts are located
scriptPath="/root/silo/automation"

# path and file name of the check program to be executed with the check option
checkScript="/root/silo/automation/check_spectrumarchive.sh"

# defined the node class where the operation has to run on, if not set it runs on the local node
# if local node is not the cluster manager then it will not run on local node
nodeClass=""

# log file directory for the automation scripts 
logDir="/var/log/automation"

# log files for this type of operation to keep including this process - keep the $verKeep latest version
verKeep=3

# log files for this type of operation to compress - compress the $verKeep + $verComp version
verComp=3


# define constants
# ----------------
# version of the launcher program
ver="2.1"
# path for the GPFS binaries
gpfsPath="/usr/lpp/mmfs/bin"

# current date
curDate="$(date +%Y%m%d%H%M%S)"

# define the custom event IDs as they are defined in the custom.json example
# if the event IDs are changed in the custom.json, it must be adjusted here. 
eventGood=888331
eventWarn=888332
eventErr=888333

# custom event definition file
customJson="/usr/lpp/mmfs/lib/mmsysmon/custom.json"

# send events = 1 means we will send events if the custom.json file with the event codes exists
sendEvent=0


# define return codes
# ------------------
rcGood=0  # successful run
rcWarn=1  # run was ok, some warnings however
rcErr=2   # failed


# assign the arguments passed to the launcher
# -------------------------------------------

# operation code is in $1
op="$1"

# file system name is $2
fsName="$2"

# optional argument $3 depends on operation
#  for backup: it can specify the fileset name
#  for migrate: it can specify the policy file name
#  for check: it can specify the component
secArg="$3"

# other global variables
localNode=$($gpfsPath/mmlsnode -N localhost | cut -d'.' -f1)
fsetName=""
polFileName=""
compName=""
errMsg=""
errCode=""
# temporarily set execNode to localnode
execNode=$localNode
logF=""

#********************************************** MAIN *********************************

# check operation and assign command
# new operations can be added here
case $op in
"backup") 
  # runs DR-Backup
  cmd=$scriptPath"/backup.sh"
  if [[ ! -z $secArg ]]; 
  then
    fsetName=$secArg
  fi;;  

"migrate") 
  # runs selective migration (scheduled)
  cmd=$scriptPath"/migrate.sh"
  if [[ ! -z $secArg ]]; 
  then
    polFileName=$secArg
  fi ;;  

"premigrate") 
  # runs selective pre-migration (scheduled)
  cmd=$scriptPath"/premigrate.sh"
  if [[ ! -z $secArg ]]; 
  then
    polFileName=$secArg
  fi ;;  

"check")
  # runs check
  cmd=$checkScript
  if [[ ! -z $secArg ]]; 
  then
    compName=$secArg
  fi;;

"test")
  # just a simple test using ls
  cmd="/usr/bin/ls";;

*) errMsg=$errMsg"LAUNCH: ERROR: wrong operation code: $op\n \
   SYNTAX: $0 operation [file system name] [second-argumen]\n \
   \t operation: backup | migrate | premigrate | check\n \
   \t file system is the name of the file system in scope for the storage service \n \
   \t second argument is an optional argument passed to the storage serice script \n" 
   errCode=$rcErr;;
esac

# create logfile dir if not exist
if [[ ! -d $logDir ]];
then
  mkdir -p $logDir
fi

# assing logfile name
# if operation is not given set it to Unknown
if [[ -z $op ]];
then 
  op=UNKNOWN
fi
logF=$logDir"/"$op"_"$curDate".log"
#### debugging, remove this
# logF=$logDir"/"debug.log

#present banner and initialize log file
echo "$(date) LAUNCH: launcher version $ver started with operation $op $secArg on node $(hostname)" > $logF
echo >> $logF

# check if events are enabled and set sendEvent accordingly
out=""
notExist=0
sendEvent=0
# check if custom event file exists
if [[ -a $customJson ]];
then
  # now check if the eventCodes are included
  for e in $eventGood $eventWarn $eventErr; 
  do
	out=""
	out=$(grep $e $customJson)
	if [[ -z $out ]]; then notExist=1; break; fi
  done
  if (( $notExist == 0 )); then sendEvent=1; fi
fi
echo "LAUNCH: send Event is set to $sendEvent" >> $logF

 
#if there was an error before write it to the log and exit
if [[ ! -z $errMsg ]];
then
  echo -e $errMsg >> $logF
  if [[ -z $2 ]]; then fsName=UNKNOWN; fi
  execNode=$($gpfsPath/mmlsnode -N localhost | cut -d'.' -f1)
  if [[ -z $op ]]; then op=UNKNOWN; fi
  if (( sendEvent == 1 )); 
  then 
    $gpfsPath/mmsysmonc event custom $eventErr "$fsName,$op,$execNode,$logF" >> $logF 2>&1
  fi
  exit $errCode
fi


# check if command scripts executing the storage operation exist on this node
if [[ ! -a $cmd ]];
then
  echo "LAUNCH: ERROR command $cmd does not exists. Make sure that the script path is set and the scripts are placed in this path (current script path: $scriptPath, check script: $checkScript" >> $logF
  if (( sendEvent == 1 )); 
  then 
    $gpfsPath/mmsysmonc event custom $eventErr "$fsName,$op,$execNode,$logF" >> $logF 2>&1
  fi
  exit $rcErr
fi
  

#assign and check file system name. If $2 is set then use this, if not use the default name (def_fsName). If this is empty then terminate
echo "LAUNCH: assigning and checking file system name" >> $logF
if [[ -z $fsName ]];
then 
  if [[ ! -z $def_fsName ]];
  then 
    fsName=$def_fsName
  else
    echo "LAUNCH: ERROR file system name not defined. Either pass it as parameter to this script. Or initialized the global variable fsName" >> $logF
    if (( sendEvent == 1 )); 
    then 
      $gpfsPath/mmsysmonc event custom $eventErr "$fsName,$op,$execNode,$logF" >> $logF 2>&1
    fi
    exit $rcErr
  fi
fi

# check if the file system exists
$gpfsPath/mmlsfs $fsName > /dev/null 2>&1
rc=$?
if (( rc > 0 ));
then
  echo "LAUNCH: ERROR file system $fsName does not exist." >> $logF
  if (( sendEvent == 1 )); 
  then 
    $gpfsPath/mmsysmonc event custom $eventErr "$fsName,$op,$execNode,$logF" >> $logF 2>&1
  fi
  exit $rcErr
fi
# now export the parameter $fsName which could be used by scripts being launched
export fsName=$fsName


# compose the command (operation) to run
# if we run the check operation do not include the file system name
if [[ "$op" == "check" ]];
then 
  cmd=$cmd" $secArg"
else 
  cmd=$cmd" $fsName $secArg"
fi

#check that localNode initialized above is not empty
#perform this check prior deleting the log files to keep the previous one.
localNode=$($gpfsPath/mmlsnode -N localhost | cut -d'.' -f1)
if [[ -z $localNode ]];
then
  echo "LAUNCH: ERROR local node name could not be initialized, node may be down." >> $logF
  if (( sendEvent == 1 )); 
  then 
    $gpfsPath/mmsysmonc event custom $eventErr "$fsName,$op,$execNode,$logF" >> $logF 2>&1
  fi
  exit $rcErr
fi


# delete and compress older  logfiles prior to logging anything
echo "LAUNCH: cleaning up log files  $op" >> $logF
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
echo "LAUNCH: checking if this node is cluster manager" >> $logF
clusterMgr=$($gpfsPath/mmlsmgr -c | sed 's|.*(||' | sed 's|)||')
if [ "$localNode" != "$clusterMgr" ]; 
then
  echo "LAUNCH: INFO this node is not cluster manager, exiting." >> $logF
  echo "LAUNCH: DEBUG localNode=$localNode  clusterMgr=$clusterMgr" >> $logF
  exit $rcGood
fi

#-------------------------------
# determine the node to run this command based on node class and node and file system state
echo "LAUNCH: INFO local node is: $localNode" >> $logF
allNodes=""
sortNodes=""
# if node class is set up determine node names in node class
if [[ ! -z $nodeClass ]];
then
   echo "LAUNCH: INFO node class to select the node from is: $nodeClass" >> $logF
   allNodes=$($gpfsPath/mmlsnodeclass $nodeClass -Y | grep -v HEADER | cut -d':' -f 10 | sed 's|,| |g')
   if [[ -z $allNodes ]]
   then
     echo "LAUNCH: WARNING node class $nodeClass is empty, using local node" >> $logF
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
echo "LAUNCH: INFO The following nodes are checked to run the operation: $sortNodes" >> $logF
execNode=""
for n in $sortNodes;
do
  # determine node state
  state=$($gpfsPath/mmgetstate -N $n -Y | grep -v ":HEADER:" | cut -d':' -f 9)
  if [[ "$state" == "active" ]];
  then
	# determine file system state on node
	mNodes=$($gpfsPath/mmlsmount $fsName -Y | grep -v HEADER | grep -E ":RW:" | cut -d':' -f 12)
	for m in $mNodes;
	do
	  if [[ "$m" == "$n" ]];
	  then
		execNode=$m
      fi		
	done
	# if we found a node active with file system mounted then leave the loop
	if [[ ! -z "$execNode" ]];
	then
	  break
	fi
  fi
done

if [[ -z "$execNode" ]];
then
  echo "$(date) LAUNCH: ERROR no node is in appropriate state to run the job, exiting." >> $logF
  if (( sendEvent == 1 )); 
  then 
    $gpfsPath/mmsysmonc event custom $eventErr "$fsName,$op,$execNode,$logF" >> $logF 2>&1
  fi
  exit $rcErr
fi

#now run the command according to the operation code assigned above 
echo "$(date) LAUNCH: INFO Running command $cmd on node $execNode" >> $logF
ssh $execNode "$cmd" >> $logF 2>&1
rc=$?

# evaluate the result of the command and send the event if this is enabled
if (( rc == 0 ));
then 
  echo "$(date) LAUNCH: command $cmd finished with status=GOOD" >> $logF
  if (( sendEvent == 1 )); 
  then 
    $gpfsPath/mmsysmonc event custom $eventGood "$fsName,$op,$execNode" >> $logF 2>&1 
  fi
elif (( rc == 1 ));
then
  echo "$(date) LAUNCH: command $cmd finished with status=WARNING" >> $logF
  # send WARNING event ...
  if (( sendEvent == 1 )); 
  then 
    $gpfsPath/mmsysmonc event custom $eventWarn "$fsName,$op,$execNode,$logF" >> $logF 2>&1
  fi
else
  echo "$(date) LAUNCH: command $cmd finished with status=ERROR (rc=$rc)" >> $logF
  rc=2
  # send ERROR event ...
  if (( sendEvent == 1 )); 
  then 
    $gpfsPath/mmsysmonc event custom $eventErr "$fsName,$op,$execNode,$logF" >> $logF 2>&1
  fi
fi

# return the appropriate return code
exit $rc
