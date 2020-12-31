
# Introduction

IBM Spectrum Scale™ is a software-defined scalable parallel file system storage providing a comprehensive set of storage services. Some of the differentiating storage services are the integrated backup function and storage tiering. These services typically run in the background according to pre-defined schedules. This project presents a flexible framework for automating storage services in IBM Spectrum Scale or other software. 

The framework includes the following components:

**Control components:**
- The control component [launcher](launcher.sh) selects the appropriate cluster node initiating the storage service operation, starts the storage service if the node state is appropriate, manages logging, log-files and return codes and sends events in accordance to the result of the storage server. The control component is typically invoked by the scheduler and the storage services being started might be backup or storage tiering.
- The scheduler that invokes the control component. An example is the `cron` daemon. This component is not included in this framework

**Storage services components:** 
- The backup component [backup](backup.sh) performs the backup using the mmbackup-command 
- The storage tiering component [migrate](migrate.sh) performs pre-migration or migration using the mmapplypolicy-command
- The check component performs checks of a certain component. It relies on a check script such as check_spectrumarchive. The check_spectrumarchive script can be obtained from this repo: [check_spectrumarchive](https://github.com/nhaustein/check_spectrumarchive).  
- The bulkrecall component [bulkrecall](bulkRecall.sh) performs bulk recalls of files that are stored in a file list. The path and file name of the file list is configured within the bulkrecall program
- The reclaim component [reclaim](eereclaim.sh) performs tape reclamation with IBM Spectrum Archive EE. The options for the reclaim command can be provided when the launcher script is invoked. 
- The reconcile component [reconcile](eereconcile.sh) performs reconcilation for tape pools managed by IBM Spectrum Archive EE. The options for the reconcile command can be provided when the launcher script invoked. 

There is also a test component that just tests the launcher script. 
All components are futher detailed below.

## Disclaimer and license
This project is under [MIT license](LICENSE).

--------------------------------------------------------------------------------

# Installation

In general the launcher component is scheduled on all cluster nodes with manager and / or quorum role to run at the same time. The launcher component will launch the storage service only from the cluster manager node. On all nodes that are not cluster manager the launcher will exit after determining that this node is not the cluster manager. 

The launcher can launch the storage service on a different cluster node using ssh. There is a configuration parameter (`nodeClass`) in the launcher script that allows to define the node class defining the set of node to run a storage service should run. The launcher will select one node from the this node class and prefers the node where it is running on. In other words if the active cluster manager is in the node class where the storage service should run then it will run on this node. 

There are some storage service components that are specific to IBM Spectrum Archive EE, like check and bulkrecall. Since Spectrum Archive nodes may not be manager or quorum nodes in a cluster the launcher can also be configured to check if the node where it was started in the active control node. Only the active control node will launch the storage service. There is a configuration parameter (`singleton`) in the launcher script that allows to control if the launcher looks for the active cluster manager or the active control node. 

Hence the components of this framework have to be installed on different nodes, including:
- all manager and / or quorum nodes OR Spectrum Archive EE nodes. The launcher and the required storage service components have to be installed on these nodes. 
- all nodes that are in the predefined node class to run the storage service. Only the required storage service components have to be installed on these nodes. 

Note, only the components that are required have to be installed on these nodes. For example if you just want to automate check and bulkrecall you only have to install the launcher and the respective components. 

The components have to be installed in the same path on all nodes. The path is configurable with a parameter (`scriptPath`) in the launcher script. 

Perform the following steps for installation:
- identify the nodes where the components have to installed, see guidance above
- on each node create a directory referenced by the parameter `scriptPath`
- copy the required components (files) to the respective nodes into the appropriate directory
- install the custom events file (more information below). 
- adjust parameters in the launcher, backup and migrate script (more information below)
- test the launcher and the operations. Note that launcher does not write output the the console (STDOUT) but into a log file located in `/var/log/automation`
- schedule the launcher using a scheduler, e.g. cron 



Find below further guidance to adjust and configure this framework.

--------------------------------------------------------------------------------

# Components
This project includes the following scripts:

Note, the appropriate scripts from the selection below must be installed on all Spectrum Scale nodes with a manager role. 


## [launcher](launcher.sh): 
This is the control component that is invoked by the scheduler. It checks if the node it is running on is the cluster manager. If this is the case it selects a node from a pre-defined node class for running the storage service and thereby prefers the local node if this is member of the node class or the node class is not defined. After selecting the node it checks if the node and file system state is appropriate, assigns and manages logfiles, starts the storage service (backup or migrate) through ssh. Upon completion of the storage service operation the launcher can also raise events with the Spectrum Scale system monitor. All output (STDOUT and STDERR) is written to a unique logfile located in `/var/log/automation`.  


### Invokation and processing

    # launcher.sh operation file-sytem-name [second-argument]
	operation:			is the storage service to be performed: backup, migrate, check, bulkrecall, reclaim, reconcile or test 
	file-system-name: 	is the name of the file system which is in scope of the storage service
	second-argument: 	is a second argument passed to the storage service script (optional)
		for backup: 	it can specify the fileset name when required
		for migrate: 	it can specify the policy file name
		for check: 	it can specify the component, such as -e for all checks
		for bulkrecall: this argument is not required
		for reclaim: 	it can specify the options for the reclaim command. 
		for reconcile: 	it can specify the options for the reconcile command. 
		for test: 	it can specify the text string which is written to the log file. 

The file system name can also be defined within the launcher.sh script. In this case the file system name does not have to be given with call. If the file system name is given with the call then it takes precedence over the define file system name within the scrip. The file system name must either be given with the call or it must be defined within launcher script-

The second-argument depends on the operation that is started by the launcher. 
- For backup the second argument can be the name of an independent fileset. If the fileset name is given as second argument then the backup operation will be performed for this fileset. 
- For storage tiering (migrate) the second argument can be the fully qualified path and file name of the policy file. If the policy file name is specified as second parameter is must not include blanks in the base file name. Altenatively the policy file name can be defined within the migrate.sh script.
- For check the second argument can be the name of the component to be checked. For the check_spectrumarchive script the second argument should be set to "-e".
- For reclaim the second argument can specify options for the `eeadm tape reclaim` command.
- For reconcile the second argument can specify options for the `eeadm tape reconcile` command.
- For test the second argument can specify a text string which is written to the log file. 


The following parameters can be adjusted within the launcher script:

| Parameter | Description |
| ----------|-------------|
| def_fsName | default file system name, if this is set and $2 is empty this name is used. If $2 is given then this parameter is being ignored. Best practice is to not set this parameter. |
| scriptPath | specifies the path where the automation scripts are located. The scripts must be stored in the same directory on all relevant nodes. The script path must not contain blanks. |
| checkScript | specifies the fully qualified path and file name of the check script to run. The check script, like check_spectrumarchive.sh must be in the same directory on all nodes where this operation can run on |
| nodeClass | defines the node class including the node names where the storage service is executed. For backup these are the nodes that have the backup client installed. For migration these are the node where the HSM component (like Spectrum Archive EE) is installed. Since these nodes must not be manager nodes the launcher script executes the storage service on a node in this node class. If the node class is not defined then the storage service is executed on the local node. This requires that all manager nodes have the backup client or the HSM component installed. |
| logDir | specifies the directory where the log files are stored. The launcher creates one logfile for every run. The log file name is includes the operation (backup, migrate or check) and the time stamp (e.g. backup_YYYYMMDDhhmmss.log. It is good practice to store the log files in a subdirectory of /var/log. |
| verKeep | specifies the number of log files to keep per operation. If the number of log files exceeds this number then the oldest logfile is compressed. |
| verComp | specifies the number of compressed log files to keep per operation. If the number of compressed log files exceeds this number then the oldest compressed log file is deleted. | 
| singleton | specifies the default check to be performed in order to decide whether the program continues to run on the node where it is executed. If set to `manager` it will check if the node is the cluster manager, if not then the script will exit. If set to `archive` it checks if the node is active control node, if not then the script will exit. If set to `none` it will not check any role of the node and the script will continue to run on the node where it is executed. The default value is `manager` in case this parameter is not set. The parameter `singleton` can also be adjusted within the script, for example in the code section where the operation code is checked and the associated script is assigned. |


### Logging

For each run the script `launcher.sh` creates a unique log file. The log files are stored in the path specified by the script parameter `logDir`. The naming of the log file depends on the operation and the additional arguments provided. The table below explains the log file naming:


| Operation | Log file name | Note |
| ----------| --------------| -----|
| Backup | backup_fsname-fsetname_date.log | Token `fsname` is the file system name given for the backup. If the fileset name is given as second paramter for the backup operation it is included in the log file name as token `fsetname`. |
| Migration | migrate_fsname-policyfile_date.log | Token `fsname` is the file system name given for the migration operation. If the policy file name is given as second parameter it is included in the log file name as token `policyfile` (the token `policyfile` is the base name of the policy file name without dot). |
| Check | check_fsname-option_date.log | Token `fsname` is the file system name given for the check operation. If the check option is given as second paramter it is included in the log file name as token `option`. |
| Bulkrecall | bulkrecall_fsname_date.log | Token `fsname` is the file system name given for the migration. |
| Reclaim | reclaim_fsname-poolname_date.log | Token `fsname` is the file system name and `poolname` is the name of the tape pool given with the invokation. |
| Reconcile| reconcile_fsname-poolname_date.log | Token `fsname` is the file system name and `poolname` is the name of the tape pool given with the invokation. |
| Test | test_fsname_date.log | Token `fsname` is the file system name given with the invokation. |

The token `date` in the log file name is the current time stamp in format: YYYYMMDDhhmmss.

The script `launcher.sh` manages log files based on the number of logs stored for a particular operation. The number of log file kept uncompressed is specified with parameter `verKeep`. The number of log files kept in a compressed manner (gzip) is specified by paramter `verComp`. Additional (older compressed) log files are deleted automatically. 



### Examples for running storage services

To run backup for file system `gpfs0` and for fileset `test01` run this launcher command:

	# launcher.sh backup gpfs0 test01

The log file name will be `backup_gpfs0-test01_date.log`. 


To run migration for file system `gpfs0` and with policy file `/hone/shared/mig_policy.txt` run this launcher command

	# launcher.sh migrate gpfs0 /hone/shared/mig_policy.txt

The log file name will be `migrate_gpfs0-mig_policy_date.log`. 


To run check for IBM Spectrum Archive EE run this launcher command (the file system name which is enabled for space management must be given with the command, in this example `gpfs0`):

	# launcher.sh check gpfs0 -e
	
The log file name will be `check_gpfs0-e_date.log`. 


To run bulkrecall for file system `gpfs0` on a IBM Spectrum Archive EE node run this launcher command.

	# launcher.sh bulkrecall gpfs0 

The log file name will be `bulkrecall_gpfs0_date.log`. 


To run reclamation for a Spectrum Archive EE pool the options for the reclaim command must be specified after the file system (e.g. `gpfs0`). Use the following command: 

	# launcher.sh reclaim gpfs0 -p poolname -l lib-name -U min-used-percentage -G min-reclaimable-percentage -n num-tapes


All parameters given after the file system name (gpfs0) are interpreted by the Spectrum Archive command: `eeadm tape reclaim` ([More Information](https://www.ibm.com/support/knowledgecenter/en/ST9MBR_1.3.1/ee_eeadm_tape_reclaim.html)). For example, you want to reclaim tapes in a given pool (parameter `-p poolname -l libname`) that have more than 80 % used capacity (parameter `-U 80`) and more than 50 % reclaimable space (paramter `-G 50`). You can also specify to only reclaim 2 tapes with one reclaim process (parameter `-n 2`).
	
	
	# launcher.sh reclaim gpfs0 -p poolname -l lib-name -U 80 -G 50 -n 2

The log file name will be `reclaim_gpfs0-poolname_date.log`. 


To run reconcilation for a file system and a Spectrum Archive EE pool the options for the reconcile command must be specified after the file system (e.g. `gpfs0`). Use the following command: 


	# launcher.sh reconcile gpfs0 -p poolname -l libname -g fspath [--commit-to-tape]

All parameters given after the file system name (gpfs0) are interpreted by the Spectrum Archive command: `eeadm tape reconcile` ([More Information](https://www.ibm.com/support/knowledgecenter/en/ST9MBR_1.3.1/ee_eeadm_tape_reconcile.html)). For example, you want to reconcile tapes in a given pool (parameter `-p poolname -l libname`) that are used by file system `gpfs0` mounted on path `/ibm/gpfs0` then you can specify the reconcile options like this: 

	
	# launcher.sh reconcile gpfs0 -p poolname -l lib-name -g /ibm/gpfs0

The log file name will be `reconcile_gpfs0-poolname_date.log`. 


Upon completion of the storage service the launcher component can raise custom events. The custom events are defined in the file [custom.json](custom.json). This file must be copied to /usr/lpp/mmfs/lib/mmsysmon. If this file exists then the script will automatically raise events. If a custom.json exist for another reason and it is not desired to raise events the parameter sendEvent within the launcher script can be manually adjusted to a value of 0. 

Note again, the launcher component does not write output the the console (STDOUT) but into a log file located in `/var/log/automation`. All other components write to STDOUT which is redirected into the log file by launcher. 


Return codes:

0 -  Operation completed SUCCESSFUL

1 -  Operation completed with WARNING

2 -  Operation completed with ERRORS

The return code is iherited from the storage service. If custom events are enabled and configured the program will send one event in accordance with the return code of the storage service operation. 


For testing the test option can be used: 


	# launcher.sh test gpfs0 "Text-String"

This tests the launcher logic and eventually writes the `Text-String` into the log file. The test includes validation of cluster manager and file system state. 

The log file name will be `reconcile_gpfs0-poolname_date.log`. 


Upon completion of the storage service the launcher component can raise custom events. The custom events are defined in the file [custom.json](custom.json). This file must be copied to /usr/lpp/mmfs/lib/mmsysmon. If this file exists then the script will automatically raise events. If a custom.json exist for another reason and it is not desired to raise events the parameter sendEvent within the launcher script can be manually adjusted to a value of 0. 

Note again, the launcher component does not write output the the console (STDOUT) but into a log file located in `/var/log/automation`. All other components write to STDOUT which is redirected into the log file by launcher. 


Return codes:

0 -  Operation completed SUCCESSFUL

1 -  Operation completed with WARNING

2 -  Operation completed with ERRORS

The return code is iherited from the storage service. If custom events are enabled and configured the program will send one event in accordance with the return code of the storage service operation. 


### Enabling [custom events](custom.json)

The launcher script can raise events in accordance to the return code of the storage service. The file [custom.json](custom.json) has three events defined:

To integrate this utility with the IBM Spectrum Scale event monitoring framework custom events need to be defined and configured. The file [custom.json](custom.json) included predefined custom events. The following events are pre-defined:

| Event name | Event Code | Event description |
|------------|------------|-------------------|
| cron_info | 888331 | is send if the operation ended successful (return code 0) |
| cron_warning | 888332 | is send if the operation ended with WARNINGS (return code 1). |
| checkee_error | 888333 | is send if the operatio ended with ERRORS (return code 2). |

The script will automatically determine if the custom event have been installed and configured in  `/usr/lpp/mmfs/lib/mmsysmon/custom.json`. 

Find below an example for an cron_error event:

	2019-11-15 06:33:12.307057 EST        cron_error                ERROR      Process backup for file system fs1 ended with ERRORS on node spectrumscale. See log-file /var/log/automation/debug.log and determine the root cause before running the process again

This [custom.json](custom.json) file must be installed in directory `/usr/lpp/mmfs/lib/mmsysmon` on each node that can runs the launcher (manager nodes). First check if a custom.json file is already installed in this directory. If this is the case then add this custom.json to the existing file. Ensure the the event_id tags are unique. It is recommended to copy the file to /var/mmfs/mmsysmon/custom.json and create a symlink to this file under /usr/lpp/mmfs/lib/mmsysmon/. 

Once the custom.json file is copied the system monitor componented needs to be restarted

	# systemctl restart mmsysmon.service

Now test if the custom even definition has been loaded:

	# mmhealth event show 888331

You are good to go if the event definition is shown. Otherwise investigate the issue in the /var/adm/ras/mmsysmon*.log files.

More information [IBM Spectrum Scale Knowledge Center](https://www.ibm.com/support/knowledgecenter/STXKQY_5.0.3/com.ibm.spectrum.scale.v5r03.doc/bl1adv_createuserdefinedevents.htm) 


--------------------------------------------------------------------------------

# Storage services scripts

In accordance to the operations the launcher script is invoked for, one of the following storage services scripts is executed. These scripts are located in this repository. 


## [backup](backup.sh)
This is the backup component and performs the backup by executing the mmbackup command. It may optionally run the backup from a snapshot. It can also run the backup for a particular independent fileset if the fileset name is given with the call. 


Invokation by the launcher:

    # backup.sh file system name [fileset-name]
	file system name: 	the name of the file system for the backup
	fileset name: 		the name of the independent fileset (optional)

The launcher component typically invokes the backup components with the file system name and optionally with the fileset name. Prior to this the launcher components checks if the file system is online and invokes the backup component with the file system name to be backed up and optionally with the name of the fileset. 

If a fileset name is given then the backup component checks if the fileset exists and is linked. 

If the parameter `$snapName` is set then the backup component creates a snapshot and performs the subsequent backup operation from the snapshot. For fileset level backups the snapshot name is `$snapName_$fsetName`. For file system level backups the snapshot name is `$snapName`. 

After the backup operation has finished and was performed from a snapshot then the snapshot is deleted. The backup component returns the status of the mmbackup operation.  

The following parameters can be adjusted within the backup script:

| Parameter | Description |
| ----------|-------------|
| tsmServ | specifies the name of TSM server to be used with mmbackup. If not set then the default server is used. |
| snapName | specifies the name of snapshot for mmbackup. If this parameter is not set then mmbackup will not backup from snapshot. if this parameter has a value then the backup will be done from a snapshot and the snapshot will be created and deleted after the backup. For file system level backups the snapshot name will be identical to the value of `$snapName`. For fileset level backups the snapshot name will be set to `$snapName_$fsetName`. If the snapshot name is given then the backup script will check if a snapshot with this name exists. If this is the case it will exit with an error. If not then the backup script creates a snapshot. If the fileset name is specified then the backup script creates a snapshot for the fileset only. After the mmbackup run the snapshot is deleted by the backup script. |
| backupOpts | specifies special parameters to be used with mmbackup command. Consider the following example as guidance: "-N nsdNodes -v --max-backup-count 4096 --max-backup-size 80M --backup-threads 2 --expire-threads 2" |

All output is written to STDOUT which the launcher redirects to a log file named `var/log/automation/backup_timestamp.log`.

Return codes:

0 -  Operation completed SUCCESSFUL

1 -  Operation completed with WARNING (mmbackup return code = 1)

2 -  Operation completed with ERRORS (mmbackup return code > 1)


--------------------------------------------------------------------------------

## [migrate](migrate.sh)

This is the migration component and performs the migration by executing the mmapplypolicy command. The policy file name can be passed via the call of this script. Alternatively, the policy file name can be hard-coded within this scriipt. 


Invokation by launcher:

    # migrate.sh file-system-name [policy-file-name]
	file-system-name: 	the name of the file system for the backup
	policy-file-name: 	the fully qualified path and file name of the policy file. The policy file name (base name) must not include blanks (optional)

The launcher component typically invokes the migrate components with the file system name and optionally with the polciy file  name. Priot to this the launcher components checks if the file system is online. 

If a policy file name is given then the migrate component checks if the policy file exists. If this is the case then the migrate operation is performed. If migration needs to be done for particular filesets then this can be specified within the policy file. 

The following parameters can be adjusted within the migrate script:

| Parameter | Description |
| ----------|-------------|
| def_polName | default name of the policy file. This name is used if the policy file name is not given with the call. |
| workDir | directory path name for temporary files created by the policy engine. This parameter is passed to the mmapplypolicy command via the -s parameter, the default (/tmp). |
| mmapplyOpts | additional parameters for the mmapplypolicy command. Consider at least these parameters: "-N nsdNodes -m 1 -B 1000 --single-instance" | 

All output is written to STDOUT which the launcher redirects to a log file named `var/log/automation/migrate_timestamp.log`.

Return codes:

0 -  Operation completed SUCCESSFUL

1 -  Operation completed with WARNING

2 -  Operation completed with ERRORS


### [migrate_policy.txt](migrate_policy.txt)


Example policy that migrates files older than 30 days from system pool to IBM Spectrum Protect. A policy like this has to be used with the migrate.sh script where it is referenced with parameter $polName. It is an example and might need adjustments.

The name of the policy file should be provide via the launcher script. This allows for more flexibility. It can also be defined as parameter in the migrate script, this would be a static definition. 


--------------------------------------------------------------------------------

## [check](https://github.com/nhaustein/check_spectrumarchive)

The check operation can be selectively plugged into this framework. As an example I have included the execution of check_spectrumarchive that performs a check of all IBM Spectrum Archive EE components. The script [check_spectrumarchive.sh](https://github.com/nhaustein/check_spectrumarchive) has to be installed separately. The script constant `checkScript` defines the location of this script. 

Invokation: 

    # check_spectrumarchive.sh -e
	-e:                checks all components

The check_spectrumarchive script must run on nodes that have Spectrum Archive EE installed. 

As with all other components it must be installed in the defined directory on all nodes.

The check_spectrumarchive script can also be configured to send custom events to the Spectrum Scale monitoring framework. If events are enabled with check_spectrumarchive then both components (launcher and check_spectrumarchive) will send events. 

All output is written to STDOUT which the launcher redirects to a log file named `var/log/automation/check_timestamp.log`.


Return codes:

0 -  Operation completed SUCCESSFUL

1 -  Operation completed with WARNING

2 -  Operation completed with ERRORS



--------------------------------------------------------------------------------

## [bulkrecall](bulkRecall.sh)

This is the bulkrecall component that recalls files with their name specified in a file list. This implementation is based on IBM Spectrum Archive EE (version 1.3.0.6 and above) and uses the Spectrum Archive command: `eeadm recall *filelist*`. The path and file name of the file list is defined with the parameter `fList` in the script. The file list contains fully qualilfied path and file names of files to be recalled using the bulk or tape optimized recall. There must be one path and file name per line. 

Invokation by launcher:

    # bulkRecall.sh 

The launcher component typically invokes the bulkrecall components with the file system name. Prior to this the launcher components checks if the file system is online. 

The following parameters can be adjusted within the migrate script:

| Parameter | Description |
| ----------|-------------|
| hName | specifies the name of the host that creates the file list including the files to be recalled. This name is used to differentiate file list generated by different hosts. |
| fListDir | specifies the path name where the file list will be stored |
| fListName | specifies the file name of the file list. | 
| minEntries | specifies the minimum number entries in file list required to start a bulk recall, should be at least 1 | 

The current implementation builds the path and file name of the file list by: `$fListDir/$fListName.$hName`. This allows different file lists in the directory provided by different host ($hName)

**Note:** 
If the recall fails then the current processing file list is not removed from the directory `$fListDir`. The next run of bulkrecall will fail if this current processing file list still exists. This is done on purpose because we do not want to miss a recall. So we keep this list for later manual processing. In this case, perform a manual recall using this file list and if this runs with success then delete it manually. If the manual recall is not successfull then determine the root cause and fix the problem. 

All output is written to STDOUT which the launcher redirects to a log file named `var/log/automation/bulkrecall_timestamp.log`.

Return codes:

0 - Successfull operation

1 - Return code not used

2 - Spectrum Archive EE is not running on this node

3 - Recall failed

4 - Processing file lists exist, a bulkrecall operation may be running or completed with error


--------------------------------------------------------------------------------

## [reclaim](eereclaim.sh)

This is the tape reclaim services that reclaims tapes in a pool managed by IBM Spectrum Archive EE. This implementation is based on IBM Spectrum Archive EE (version 1.3.0.7 and above). The pool name, the library name and the further reclaim options can be given with the launcher component. Optionally, the reclaim options can be defined within this script. 

Invokation by launcher:

	# eereclaim.sh [eeadm tape reclaim options]
	
	
The reclaim options are in accordance with the `eeadm tape reclaim` command [More Information]( https://www.ibm.com/support/knowledgecenter/en/ST9MBR_1.3.1/ee_eeadm_tape_reclaim.html). A typical scenario may be to reclaim tapes in a given pool (parameter `-p poolname -l libname`) that have more than 80 % used capacity (parameter `-U 80`) and more than 50 % reclaimable space (paramter `-G 50`). You can also specify to only reclaim 2 tapes with one reclaim process (parameter `-n 2`). When sufficient tape drives are available you can specify the number of parallel reclaim threads (parameter `-m 2`), this however requires Spectrum Archive EE version 1.3.1. Be aware that each reclaim thread needs at least two tape drives to be availeble. With this example the invokation of the launcher looks like this: 

	
	# launcher.sh reclaim gpfs0 -p poolname -l lib-name -U 80 -G 50 -n 2


The launcher component typically invokes the reclaim components with the file system name which is not used in the reclaim script. The launcher components checks if the file system is online prior to invoking the reclaim component. 

The following parameters can be adjusted within the reclaim script:

| Parameter | Description |
| ----------|-------------|
| reclaimOpts | defines the command parameters and options for the `eeadm tape reclaim` command. The default value is "" (undefined). Normally the parameters for the reclaim command are passed with the `eereclaim.sh` invokation. If there are no parameters passed with the `eereclaim.sh` invokation, then the value of this parameter (`reclaimOpts`) is examined. If this parameter has values defined (within the script), then these values are used as command parameters for the `eeadm tape reconcile` command. For example, a valid options string is: `-p poolname -l libname -U 70 -G 80`. This reclaims all tapes in the pool that are have a used percentage of 70% and a minimum reclaimable percentage of 80%. Further reclaim options can be used. |

All output is written to STDOUT which the launcher redirects to a log file named `var/log/automation/reclaim_fsname-poolname_timestamp.log`.

Return codes:

0 - Successfull operation

1 - reclaim command returned 1 (happens on syntax errrors)

2 - reclaim command failed

--------------------------------------------------------------------------------

## [reconcile](eereconcile.sh)

This is the tape reconcile services that reconsiles tape pools that are use by file systems. This implementation is based on IBM Spectrum Archive EE (version 1.3.0.7 and above). The pool name, the library name and the further reconcile options can be given with the launcher component. Optionally, the reclaim options can be defined within this script. 

Invokation by launcher:

	# eereconcile.sh [eeadm tape reconcile options]
	
	
The reconcile options are in accordance with the `eeadm tape reconcile` command [More Information]( https://www.ibm.com/support/knowledgecenter/en/ST9MBR_1.3.1/ee_eeadm_tape_reclaim.html). A typical scenario may be to reconcile all tapes given pool (parameter `-p poolname -l libname`) that are used by file system `/ibm/gpfs0`. With this example the invokation of the launcher looks like this: 

	
	# launcher.sh reconcile gpfs0 -p poolname -l lib-name -g /ibm/gpfs0


The launcher component typically invokes the reconcile components with the file system name which is not used in the reclaim script. The launcher components checks if the file system is online prior to invoking the reconcile component. 

The following parameters can be adjusted within the reclaim script:

| Parameter | Description |
| ----------|-------------|
| reconcileOpts | defines the command parameters and options for the `eeadm tape reconcile` command. The default value is "" (undefined). Normally the parameters for the reconcile command are passed with the `eereconcile.sh` invokation. If there are no parameters passed with the `eereconcile.sh` invokation, then the value of this parameter (`reconcileOpts`) is examined. If this parameter has values defined (within the script), then these values are used as command parameters for the `eeadm tape reconcile` command. |

All output is written to STDOUT which the launcher redirects to a log file named `var/log/automation/reconcile_fsname-poolname_timestamp.log`.

Return codes:

0 - Successfull operation

1 - reconcile command returned 1 (happens on syntax errrors)

2 - reconcile command failed


--------------------------------------------------------------------------------

## Configuring cron

The `launcher.sh` with the appropriate operation is executed periodically. One way to schedule the periodic execution of the launcher is by using cron.

As explained above the relevant components of this framework like `launcher.sh` and the storage services like `backup.sh`, `migrate.sh`, check and `bulkrecall.sh` must be installed on a subset of ndoes within the Spectrum Scale and Spectrum Archive cluster. The launcher is either scheduled to run at the same point of time on all manager and / or quorum nodes or on all Spectrum Archive nodes. To schedule the launcher with the appropriate storage operation the cron daemon can be used.

In a normal environments the launcher and the storage services must run as root user because IBM Spectrum Scale and Spectrum Archive administration requires root privileges. Consequently the cron entries are setup for the root user. The cron entries can either be edited in `crontab` or they can be written a file and stored in `/etc/cron.d/`. Find below an example of the cron entries that start the launcher for migration every day at 18:00, bulkrecall at every bottom of the hour and check every day at 6:00 in the morning:

	SHELL=/bin/bash
	PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/lpp/mmfs/bin:/opt/ibm/ltfsee/bin/eeadm
	MAILTO=root
	# For details see man 4 crontabs

	# Example of job definition:
	# .---------------- minute (0 - 59)
	# |  .------------- hour (0 - 23)
	# |  |  .---------- day of month (1 - 31)
	# |  |  |  .------- month (1 - 12) OR jan,feb,mar,apr ...
	# |  |  |  |  .---- day of week (0 - 6) (Sunday=0 or 7) OR sun,mon,tue,wed,thu,fri,sat
	# |  |  |  |  |
	# *  *  *  *  * user-name  command to be executed

	# run check_spectrumarchive.sh at 6 AM
	 00 06  *  *  * root /root/silo/automation/launcher.sh check fs1 -e
	# run migrate once a day at 18:00
	 00  18  *  *  * root /root/silo/automation/launcher.sh migrate fs1 /root/silo/automation/migrate_policy.txt
	# run bulkrecall at the bottom of the hour
	 30  *  *  *  * root /root/silo/automation/launcher.sh bulkrecall fs1


It is also possible to run the launcher and storage services by a non-root user. This requires the implementation of sudo-wrapper in IBM Spectrum Scale. The non-root user must be authorized to run the launcher and storage services scripts as root via /etc/sodoers. The launcher must be invoked in the following way:

	# run check_spectrumarchive.sh at 6 AM
	 00 06  *  *  * user /usr/bin/sudo /home/user/silo/automation/launcher.sh check fs1 -e




