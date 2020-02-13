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
# Version 2.3
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
# 02/05/19: added bulk recall
#           add check if this is an active control node instead of manager using singleton variable set to archive
# 02/12/20: fix problem with host name with and without dots, some streamlining (version 2.3)
#******************************************************************************************************** 

# Export the path including the linux and GPFS binaries in case this script is invoked from a schedule
export PATH=$PATH:/usr/bin:/usr/sbin:/usr/lpp/mmfs/bin
#
# User defined variables
# -------------------------

# default file system name, if this is set and $2 is empty this name is used. If $2 is given then it is being used.
def_fsName=""

# path where the automation scripts are located, 
# !!! does not tolerate blanks in the path name !!!
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

# set default singleton to control if the node is manager or active control node with Spectrum Archive
singleton="manager"


# define constants
# ----------------
# version of the launcher program
ver="2.3"

# path for the GPFS binaries
gpfsPath="/usr/lpp/mmfs/bin"

# eeadm command fully qualified
eeCmd="/opt/ibm/ltfsee/bin/eeadm"

# jq tool fully qualified
JQ_TOOL="/usr/local/bin/jq"

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
# assign the full node name, mmlsnode shows node name with dots: ltfs1.ltfs.net
# we remove the dot later when required
localNode=$($gpfsPath/mmlsnode -N localhost)
errMsg=""
errCode=""
logF=""

#********************************************** MAIN *********************************

# check operation and assign command
# new operations can be added here
case $op in
"backup") 
  # runs DR-Backup
  cmd=$scriptPath"/backup.sh $fsName $secArg";;  

"migrate") 
  # runs selective migration (scheduled)
  cmd=$scriptPath"/migrate.sh $fsName $secArg";;
  
"premigrate") 
  # runs selective pre-migration (scheduled)
  cmd=$scriptPath"/premigrate.sh $fsName $secArg";;

"check")
  # runs check
  cmd=$checkScript" $secArg"
  # has to run on an EE node
  singleton="archive";;

"bulkrecall")
  # runs bulk recall, does not get any input
  cmd=$scriptPath/bulkRecall.sh
  # for bulk recall we should run a Spectrum Archive node, so we check if this is the active control node
  singleton="archive";;

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
echo "$(date) LAUNCH: launcher version $ver started operation $op $fsName $secArg on node $localNode" > $logF
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
  if [[ -z $fsName ]]; then fsName=UNKNOWN; fi
  if [[ -z $op ]]; then op=UNKNOWN; fi
  if [[ -z $localNode ]]; then localNode=UNKNOWN; fi  
  if (( sendEvent == 1 )); 
  then 
    $gpfsPath/mmsysmonc event custom $eventErr "$fsName,$op,$localNode,$logF" >> $logF 2>&1
  fi
  exit $errCode
fi

#check that localNode initialized above is not empty
if [[ -z $localNode ]];
then
  echo "LAUNCH: ERROR local node name could not be initialized, node may be down." >> $logF
  if (( sendEvent == 1 )); 
  then 
    $gpfsPath/mmsysmonc event custom $eventErr "$fsName,$op,"UNKNOWN",$logF" >> $logF 2>&1
  fi
  exit $rcErr
fi

# check if command scripts executing the storage operation exist on this node
scriptName=$(echo $cmd | awk '{print $1}')
if [[ ! -a $scriptName ]];
then
  echo "LAUNCH: ERROR script $scriptName does not exists. Make sure that the script path is set and the scripts are placed in this path (current script path: $scriptPath)" >> $logF
  if (( sendEvent == 1 )); 
  then 
    $gpfsPath/mmsysmonc event custom $eventErr "$fsName,$op,$localNode,$logF" >> $logF 2>&1
  fi
  exit $rcErr
fi

#check and assign file system name. If $2 is set then use this, if not use the default name (def_fsName). If this is empty then terminate
echo "LAUNCH: assigning and checking file system name ($fsName)" >> $logF
if [[ -z $fsName ]];
then 
  if [[ ! -z $def_fsName ]];
  then 
    fsName=$def_fsName
  else
    echo "LAUNCH: ERROR file system name not defined. Either pass it as parameter to this script. Or initialized the global variable fsName" >> $logF
    if (( sendEvent == 1 )); 
    then 
      $gpfsPath/mmsysmonc event custom $eventErr "$fsName,$op,$localNode,$logF" >> $logF 2>&1
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
    $gpfsPath/mmsysmonc event custom $eventErr "$fsName,$op,$localNode,$logF" >> $logF 2>&1
  fi
  exit $rcErr
fi
# now export the parameter $fsName which could be used by scripts being launched
export fsName=$fsName

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


# if singleton is manager we check if we run on a manager node, if singleton is archive we check if we run on a archive node
if [[ "$singleton" == "archive" ]]; 
then
  if [[ ! -a $eeCmd  || ! -a $JQ_TOOL ]]; 
  then
    echo "LAUNCH: ERROR: required tool $eeCmd or $JQ_TOOL does not exist on this node. Cannot check if this node is active control node. Exiting." >> $logF
	if (( sendEvent == 1 )); 
    then 
      $gpfsPath/mmsysmonc event custom $eventErr "$fsName,$op,$localNode,$logF" >> $logF 2>&1
    fi
    exit $rcErr	
  fi
  found=0
  out=""
  #check if node is active control node 
  echo "LAUNCH: checking if this node is active control node." >> $logF
  out=$($eeCmd node list --json |  $JQ_TOOL -r '.payload[] | [.hostname, .active_control_node] | @csv' 2>&1)
  rc=$?
  if [[ ! -z $out && $rc == 0 ]] ; then
    while read line ; do
      hn=$(echo $line | cut -d',' -f1 | cut -d'"' -f2)	# hostname
      ac=$(echo $line | cut -d',' -f2)					# active control node ?

      # localNode comes from mmlsnode and has node name with dots: ltfs1.ltfs.net
	  # $hn comes from eeadm drive list and has dots: ltfs1.ltfs.net
      if [[ $localNode == $hn && $ac == "true" ]] ; then
        found=1
        break
      fi
    done <<< "$(echo -e "$out")"
  else 
    echo "LAUNCH: WARNING unable to determine if this is active control node. Assuming it is not." >> $logF
	echo "LAUNCH: DEBUG out string from eeadm node list: $out, return code = $rc." >> $logF
  fi
  if (( $found == 0 )) ; then
    echo "LAUNCH: INFO this node is not active control node, exiting." >> $logF
    echo "LAUNCH: DEBUG localNode=$localNode  activeNode=$hn" >> $logF
    exit $rcGood
  fi
else
  #check if node is cluster manager
  echo "LAUNCH: checking if this node is cluster manager" >> $logF
  # have to cut of the dots from local node because mmlsmgr shows node name without dots: Cluster manager node: 192.168.100.2 (ltfs2)
  localNodeWithoutDot=$(echo "$localNode" | cut -d'.' -f 1)
  clusterMgr=$($gpfsPath/mmlsmgr -c | sed 's|.*(||' | sed 's|)||')
  if [ "$localNodeWithoutDot" != "$clusterMgr" ]; 
  then
    echo "LAUNCH: INFO this node is not cluster manager, exiting." >> $logF
    echo "LAUNCH: DEBUG localNode=$localNodeWithoutDot  clusterMgr=$clusterMgr" >> $logF
    exit $rcGood
  fi
fi

#-------------------------------
# determine the node to run this command based on node class and node and file system state
echo "LAUNCH: INFO local node is: $localNode" >> $logF
allNodes=""
sortNodes=""
# if node class is set up determine node names in node class
if [[ ! -z $nodeClass ]];
then
   # mmlsnodeclass shows nodes with dots: ltfs2.ltfs.net,ltfs1.ltfs.net
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
# determine file system state on node
# mmlsmount shows nodes without dots: mmlsmount::0:1:::ltfscache:ltfscache:ltfs.net:2:192.168.100.2:ltfs2:ltfs.net:RW:
mNodes=$($gpfsPath/mmlsmount $fsName -Y | grep -v HEADER | grep -E ":RW:" | cut -d':' -f 12)
for n in $sortNodes;
do
  # determine node state
  # mmgetstate shows node with dots: mmgetstate::0:1:::ltfs1.ltfs.net:1:active:1*:2:2:quorum node:(undefined):
  state=$($gpfsPath/mmgetstate -N $n -Y | grep -v ":HEADER:" | cut -d':' -f 9)
  if [[ "$state" == "active" ]];
  then
	for m in $mNodes;
	do
	  # $n comes from mmlsnodeclass where node name is with dot: ltfs2.ltfs.net
	  # $m comes from mmlsmount where node name is without dots: ltfs2
	  # have to remove the dot from $n
	  n=$(echo "$n" | cut -d'.' -f1)
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
