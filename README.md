
# Introduction

IBM Spectrum Scale™ is a software-defined scalable parallel file system storage providing a comprehensive set of storage services. Some of the differentiating storage services are the integrated backup function and storage tiering. These services typically run in the background according to pre-defined schedules. This project presents a flexible framework for automating storage services in IBM Spectrum Scale or other software. 

The framework includes the following components:

**Control components:**
- The control component [launcher](launcher.sh) selects the appropriate cluster node initiating the storage service operation, starts the storage service if the node state is appropriate, manages logging, log-files and return codes and sends events in accordance to the result of the storage server. The control component is typically invoked by the scheduler and the storage services being started might be backup or storage tiering.
- The scheduler that invokes the control component. An example is cron. This component is not included in this framework

**Storage services components:** 
- The backup component [backup](backup.sh) performs the backup using the mmbackup-command 
- The storage tiering component [migrate](migrate.sh) performs pre-migration or migration using the mmapplypolicy-command
- The check component performs checks of a certain component. It relies on a check script such as check_spectrumarchive. The check_spectrumarchive script can be obtained from this repo: [check_spectrumarchive](https://github.com/nhaustein/check_spectrumarchive).  
- The bulkrecall component [bulkrecall](bulkRecall.sh) performs bulk recalls of files that are stored in a file list. The path and file name of the file list is configured within the bulkrecall program

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
	operation:			is the storage service to be performed: backup, migrate, (check, test). 
	file-system-name: 	is the name of the file system which is in scope of the storage service
	second-argument: 	is a second argument passed to the storage service script (optional)
		for backup: it can specify the fileset name when required
		for migrate: it can specify the policy file name
		for check: it can specify the component, such as -e for all checks
		for bulkrecall: this argument is not required

The file system name can also be defined within the launcher.sh script. In this case the file system name does not have to be given with call. If the file system name is given with the call then it takes precedence over the define file system name within the scrip. The file system name must either be given with the call or it must be defined within launcher script-

The second-argument depends on the operation that is started by the launcher. 
- For backup the second argument can be the name of an independent fileset. If the fileset name is given as second argument then the backup operation will be performed for this fileset. 
- For storage tiering (migrate) the second argument can be the fully qualified path and file name of the policy file. Altenatively the policy file name can be defined within the migrate.sh script
- For check the second argument can be the name of the component to be checked. For the check_spectrumarchive script the second argument should be set to "-e". 


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
| singleton | specifies the default check to be performed in order to decide whether the program continues to run or not. If set to `manager` it will check if the node is the cluster manager. If set to `archive` it checks if the node is active control node. This parameter can also be adjusted within the script where the operation code is determed to derive the command to run. |



### Examples for running storage services

To run backup for file system `gpfs0` and for fileset `test01` run this launcher command:

	# launcher.sh backup gpfs0 test01

To run migration for file system `gpfs0` and with policy file `/hone/shared/mig_policy` run this launcher command

	# launcher.sh migrate gpfs0 /hone/shared/mig_policy

To run check for IBM Spectrum Archive EE run this launcher command (the file system name which is enabled for space management must be given with the command, in this example `gpfs0`):

	# launcher.sh check gpfs0 -e
	
To run bulkrecall for file system `gpfs0` on a IBM Spectrum Archive EE node run this launcher command.

	# launcher.sh bulkrecall gpfs0 

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

## [backup](backup.sh)
This is the backup component and performs the backup by executing the mmbackup command. It may optionally run the backup from a snapshot. It can also run the backup for a particular independent fileset if the fileset name is given with the call. 


Invokation by the launcher:

    # backup.sh file system name [fileset-name]
	file system name: 	the name of the file system for the backup
	fileset name: 		the name of the independent fileset (optional)

The launcher component typically invokes the backup components with the file system name and optionally with the fileset name. Priot to this the launcher components checks if the file system is online. 

If a fileset name is given then the backup component checks if the fileset exists and is linked. If this is the case the optional snapshot and backup operation is performed for this fileset. 

The following parameters can be adjusted within the backup script:

| Parameter | Description |
| ----------|-------------|
| tsmServ | specifies the name of TSM server to be used with mmbackup. If not set then the default server is used. |
| snapName | specifies the name of snapshot for mmbackup. If not set then mmbackup will not backup from snapshot. If the snapshot name is given then the backup script will check if a snapshot with this name exists. If this is the case it will exit with an error. If not then the backup script creates a snapshot. If the fileset name is specified then the backup script creates a snapshot for the fileset only. After the mmbackup run the snapshot is deleted by the backup script. |
| backupOpts | specifies special parameters to be used with mmbackup command. Consider the following example as guidance: "-N nsdNodes -v --max-backup-count 4096 --max-backup-size 80M --backup-threads 2 --expire-threads 2" |

All output is written to STDOUT which the launcher redirects to a log file named `var/log/automation/backup_timestamp.log`.

Return codes:

0 -  Operation completed SUCCESSFUL

1 -  Operation completed with WARNING

2 -  Operation completed with ERRORS


--------------------------------------------------------------------------------

## [migrate](migrate.sh)

This is the migration component and performs the migration by executing the mmapplypolicy command. The policy file name can be passed via the call of this script. Alternatively, the policy file name can be hard-coded within this scriipt. 


Invokation by launcher:

    # migrate.sh file-system-name [policy-file-name]
	file-system-name: 	the name of the file system for the backup
	policy-file-name: 	the fully qualified path and file name of the policy file (optional)

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

The launcher component typically invokes the bulkrecall components with the file system name. Priot to this the launcher components checks if the file system is online. 

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
