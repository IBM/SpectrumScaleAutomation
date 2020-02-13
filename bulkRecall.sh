#!/bin/bash
#
#---------------------------------------------------------------------------------------
#
# Program Name: bulkrecall.sh
#
# Purpose: Recall files in a file list that is provided by another program
#
# Authors: N. Haustein, IBM (haustein@de.ibm.com), M. Tridici, CMCC (mauro.tridici@cmcc.it)
#
# Invokation: bulkRecall.sh
#
# Input: 
# - None from the command line
# - the $fList file containing the files to be recalled. 
#
# Processing: 
# - check if Spectrum Archive EE is running and if not exit 3
# - check if the temp file list ($tList) or the out file list ($oList) exist and if so then exit 4. 
# - check if file list ($fList) exists and if not exit 0
# - check if the file list has >= $minEntries and if not exit 0
# - sort unique the file list ($fList) into temp list ($tList) and delete file list (fList) 
# - for each file in the temporary list ($tList): If file exist and blksize=0 and fsize>0 (use ls -ls) then put the file names in a output list ($oList)
# - delete temp list $tList
# - check if number of entries in output list ($oList) is <= $minEntries and if not then exit 0
# - recall the files in the output list using eeadm recall $oList 
# - if recall finished with rc=0 then delete the output list $oList, otherwise exit 3
# - exit 0
#
# Output: 
# - log processing to stdout and later log file
# - return code 
#   0: success
#   1: Not assigned
#   2: ee is not started 
#   3: recall failed
#   4: one of the processing files still exists (tList, oList or sList)
#
# Note: 
# If the recall fails then the output list used as input for the recall is not deleted. The next run of the program will fail. 
# This is done on purpose because we do not want to miss a recall. So we keep this list for later manual processing. 
# In this case, perform a manual recall of the sorted list and if this runs with success then delete the sorted list manually. 
# If the manual recall is not successfull then determine the root cause and fix the problem. 

#---------------------------------------------------------------------------------------
# Change History
# 02/04/20 first implementation
# 02/13/20 version 1.0: add bulkrecall to the output, streamlining
#
#
# Todo:
# - how to handle concurrent runs: if there is a ongoing recall we will have the output file list in the directory. However, also if a eeadm recall run fails, the output file list will be present and prevent the next recall to start.
# - if a recall fails we could copy the output file list to another directory. So it will not block the next run. We just need to make the admin aware that there recalls have failed and what the recall list is. 
#


##########################################################
# These parameters can be adjusted
##########################################################
# define host name that is origin of file list
hName="irods"

# define the directory where the file list is stored
fListDir="/gpfs/fs1/.recall"

# define name of the recall list
fListName="recall_input_list."$hName

# define minimum entries in $fList to start a bulk recall, should be at least 1
minEntries=1


#########################################################
# These parameters are used internally
#########################################################
# define version
ver=1.0

# define prefix name of file list
fList=$fListDir"/"$fListName

# define temp file list
tList=$fListDir"/recall_temp_list."$hname

# define output file list
oList=$fListDir"/recall_out_list."$hname

# define command for the space management component
eeCmd="/opt/ibm/ltfsee/bin/eeadm" 




##### MAIN ###############################################

# present banner
hostName=$(hostname)
echo 
echo "============================================================================="
echo "$(date) BULKRECALL: $0 version $ver started on $hostName."
echo "BULKRECALL INFO: Processing file list $fList"

# check if EE is running
echo "BULKRECALL INFO: checking Spectrum Archive status."
$eeCmd node list
rc=$?
if (( rc != 0 )); then
  echo "BULKRECALL ERROR: Spectrum Archive is not running. Start the cluster first."
  exit 2
fi 

# temp file list should have been deleted, if it exists then exit
if [[ -a $tList ]]; then
  echo "BULKRECALL ERROR: temporary file list $tList exists. Either a recall process is running or was aborted unexpectedly. Please cleanup and try again."
  exit 4
fi

# output file list should have been deleted, if it exists then exit
if [[ -a $oList ]]; then
  echo "BULKRECALL ERROR: output file list $oList exists. Either a recall process is running or was aborted unexpectedly. Please cleanup and try again."
  exit 4
fi

# sorted file list will be deleted if the recall is successful. If not then it will stay there and has to be manually cleaned.
# later on we can consider to add it to fList, delete it and do the processing
if [[ -a $sList ]]; then
  echo "BULKRECALL ERROR: Sorted file list $sList exists. A recall may be running or may have failed before. Perform the eeadm recall command with this list and deleted afterwards."
  # tbd: we could consider to run the recall command and if it finishes ok, we can continue. 
  exit 4
fi

# check if file list exists
echo "BULKRECALL INFO: Checking if $fList exists."
if [[ -a $fList ]]; then
  num=$(wc -l $fList | awk '{print $1}')
  if (( $num <= $minEntries )); then
    echo "BULKRECALL INFO: file list ($fList) exists, but has $num <= $minEntries candidates, exiting."
	# exit 0
  else
    # if file exists and we have entries, sort the file to a temp file
	echo "BULKRECALL INFO: sorting $fList and copying to $tList."
	sort -u $fList > $tList
	rc=$?
	if (( rc != 0 )); then
	  # if sort fails then keep fList and assign it to tList
	  echo "BULKRECALL WARNING: sorting $fList to $tList failed (rc=$rc). Keeping $fList"
	  rm -f $tList
	  tList="$fList"
	else
	  # if sort ok, then delete fList
	  rm -f $fList
	fi

#   for debugging log the $sList 
#	echo "-----------------------------------------------------------------------------" 
#	echo "DEBUG: Temporary file list: $tList"
#	cat $tList 
#	echo "-----------------------------------------------------------------------------"
	
    # process tList by check file names and add it to oList
	echo "BULKRECALL INFO: checking file names in file list $tList". 
	cat $tList | while read line; do
	  fls=$(ls -ls "$line")
	  if [[ ! -z $fls ]]; then
		fblk=$(echo $fls | awk '{print $1}')
		fsize=$(echo $fls | awk '{print $6}')
		if (( $fblk == 0 && $fsize > 0 )); then
		  echo "$line" >> $oList
		fi
	  fi
	done

    # delete the tempory file list because we have oList
	rm -f $tList

	# if we have a recall list then perform the recall
	if [[ -a $oList ]]; then
#     for debugging log the $sList 
#	  echo "-----------------------------------------------------------------------------" 
#	  echo "DEBUG: Output file list: $oList"
#	  cat $oList 
#	  echo "-----------------------------------------------------------------------------"

	  num=$(wc -l $oList | awk '{print $1}')
	  if (( $num >= $minEntries )); then
	    echo "BULKRECALL INFO: Recalling $num files in $oList."
	    $eeCmd recall $oList
		rc=$?
		if (( rc > 0 )); then
          echo "$(date) BULKRECALL ERROR: Recall of output file list $oList ended with error (rc=$rc)"		  
		  exit 3
		else
		  echo "BULKRECALL INFO: recall finished successfully."
		  rm -f $oList
		fi
	  else
	    echo "BULKRECALL INFO: Number of candidates in output file list $oList: $num < $minEntries, deferring recall."
	  fi # if (( num >= $minEntries )) in $oList
	else
	  echo "BULKRECALL INFO: no output list produced, no files to be recalled."
	fi # if [[ -a $oList ]]
  fi  #if (( num == $minEntries )) in $tList
else
  echo "BULKRECALL INFO: no file list ($fList) exists, exiting."
fi # if [[ -a $fList ]]

echo "$(date) BULKRECALL Program finished successfully."
echo "============================================================================="
echo

exit 0
