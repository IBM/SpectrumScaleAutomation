
# Introduction


IBM Spectrum Scale™ is a software-defined scalable parallel file system storage providing a comprehensive set of storage services. Some of the differentiating storage services are the integrated backup function and storage tiering. These services typically run in the background according to pre-defined schedules. This project presents a flexible framework for automating storage services in IBM Spectrum Scale or other software. 

The framework includes the following components, which are further detailed below:
- The control components [launcher](launcher.sh) selects the appropriate cluster node initiating the storage service operation, starts the storage service if the node state is appropriate, manages logging, log-files and return codes and sends events in accordance to the result of the storage server. The control component is typically invoked by the scheduler and the storage services being started might be backup or storage tiering.
- The backup component [backup](backup.sh) performs the backup using the mmbackup-command 
- The storage tiering component [migrate] (migrate.sh) performs pre-migration or migration using the mmapplypolicy-command
- The scheduler that invokes the control component. An example is cron.

The framework requires that all cluster nodes with a manager role assigned must be able to run the automation components. These nodes must not necessarily be the nodes performing the storage service operation but must be able to launch it.


## Disclaimer and license
This project is under [MIT license](LICENSE).

--------------------------------------------------------------------------------

# Installation


Perform the following steps for installation:
- identify all manager nodes in your cluster (mmlscluster)
- copy the files all manager nodes. Place them in the same directory on all nodes
- install the custom events file (more information below). 
- adjust parameters in the launcher, backup and migrate script (more information below)
- test the launcher and the operations
- schedule the launcher using a scheduler, e.g. cron 


Find below further guidance to adjust and configure this framework.

--------------------------------------------------------------------------------

# Components
This project includes the following scripts:

Note, the appropriate scripts from the selection below must be installed on all Spectrum Scale nodes with a manager role. 


## [launcher](launcher.sh): 
This is the control component that is invoked by the scheduler. It checks if the node it is running on is the cluster manager. If this is the case it selects a node from a pre-defined node class for running the storage service and thereby prefers the local node if this is member of the node class or the node class is not defined. After selecting the node it checks if the node and file system state is appropriate, assigns and manages logfiles, starts the storage service (backup or migrate) through ssh. Upon completion of the storage sercie operation the launcher can also raise events with the Spectrum Scale system monitor. All output (STDOUT and STDERR) is written to a unique logfile.  


Invokation and processing

    # launcher.sh operation file-sytem-name [second-argument]
	operation:			is the storage service to be performed: backup, migrate, (check, test). 
	file-system-name: 	is the name of the file system which is in scope of the storage service
	second-argument: 	is a second argument passed to the storage service script (optional)
						for backup: it can specify the fileset name when required
						for migrate: it can specify the policy file name
						for check: it can specify the component

The file system name can also be defined within the launcher.sh script. In this case the file system name does not have to be given with call. If the file system name is given with the call then it takes precedence over the define file system name within the scrip. The file system name must either be given with the call or it must be defined within launcher script-

The second-argument depends on the operation that is started by the launcher. 
- For backup the second argument can be the name of an independent fileset. If the fileset name is given as second argument then the backup operation will be performed for this fileset. 
- For storage tiering (migrate) the second argument can be the fully qualified path and file name of the policy file. Altenatively the policy file name can be defined within the migrate.sh script
- For check the second argument can be the name of the component to be checked. 

The following parameters can be adjusted within the launcher script:
| Parameter | Description |
| ----------|-------------|
| def_fsName | default file system name, if this is set and $2 is empty this name is used. If $2 is given then this parameter is being ignored. Best practice is to not set this parameter. |
| scriptPath | specifies the path where the automation scripts are located. It is recommended to put the scripts in the same directory on all nodes where it is installed (manager nodes) |
| nodeClass | defines the node class including the node names where the storage service is executed. For backup these are the nodes that have the backup client installed. For migration these are the node where the HSM component (like Spectrum Archive EE) is installed. Since these nodes must not be manager nodes the launcher script executes the storage service on a node in this node class. If the node class is not defined then the storage service is executed on the local node. This requires that all manager nodes have the backup client or the HSM component installed. |
| logDir | specifies the directory where the log files are stored. The launcher creates one logfile for every run. The log file name is includes the operation (backup, migrate or check) and the time stamp (e.g. backup_YYYYMMDDhhmmss.log. It is good practice to store the log files in a subdirectory of /var/log. |
| verKeep | specifies the number of log files to keep per operation. If the number of log files exceeds this number then the oldest logfile is compressed. |
| verComp | specifies the number of compressed log files to keep per operation. If the number of compressed log files exceeds this number then the oldest compressed log file is deleted. | 

Upon completion of the storage service the launcher component can raise custom events. The custom events are defined in the file [custom.json](custom.json). This file must be copied to /usr/lpp/mmfs/lib/mmsysmon. If this file exists then the script will automatically raise events. If a custom.json exist for another reason and it is not desired to raise events the parameter sendEvent within the launcher script can be manually adjusted to a value of 0. 


Return codes:

0 -  Operation completed SUCCESSFUL

1 -  Operation completed with WARNING

2 -  Operation completed with ERRORS

The return code is iherited from the storage service. 


### [custom event](custom.json)

The launcher script can raise events in accordance to the return code of the storage service. The file [custom.json](custom.json) has three events defined:
- cron_info: is raised when the operation completed with return 0 (Success)
- cron_warning: is raised when the operation completed with return 1 (Warning)
- cron_error: is raised when the operation completed with return 2 (Error)

Find below an example for an cron_error event:
	2019-11-15 06:33:12.307057 EST        cron_error                ERROR      Process backup for file system fs1 ended with ERRORS on node spectrumscale. See log-file /var/log/automation/debug.log and determine the root cause before running the process again

This file must be installed in directory /usr/lpp/mmfs/lib/mmsysmon on each node that can runs the launcher (manager nodes). First check if a custom.json file is already installed in this directory. If this is the case then add this custom.json to the existing file. Ensure the the event_id tags are unique. It is recommended to copy the file to /var/mmfs/mmsysmon/custom.json and create a symlink to this file under /usr/lpp/mmfs/lib/mmsysmon/. 

Once the custom.json file is copied the system monitor componented needs to be restarted
	# systemctl restart mmsysmon.service

Now test if the custom even definition has been loaded:
	# mmhealth event show 888331

You are good to go if the event definition is shown. Otherwise investigate the issue in the /var/adm/ras/mmsysmon*.log files.

More information [IBM Spectrum Scale Knowledge Center](https://www.ibm.com/support/knowledgecenter/STXKQY_5.0.3/com.ibm.spectrum.scale.v5r03.doc/bl1adv_createuserdefinedevents.htm) 


--------------------------------------------------------------------------------

## [backup](backup.sh)
This is the backup component and performs the backup by executing the mmbackup command. It may optionally run the backup from a snapshot. It can also run the backup for a particular independent fileset if the fileset name is given with the call. 


Invokation: 

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
| backupOpts | specifies special parameters to be used with mmbackup command. Consider the following example as guidance: 
"-N nsdNodes -v --max-backup-count 4096 --max-backup-size 80M --backup-threads 2 --expire-threads 2" |


Return codes:

0 -  Operation completed SUCCESSFUL

1 -  Operation completed with WARNING

2 -  Operation completed with ERRORS


--------------------------------------------------------------------------------

## [migrate](migrate.sh)
This is the migration component and performs the migration by executing the mmapplypolicy command. The policy file name can be passed via the call of this script. Alternatively, the policy file name can be hard-coded within this scriipt. 


Invokation: 

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


Return codes:

0 -  Operation completed SUCCESSFUL

1 -  Operation completed with WARNING

2 -  Operation completed with ERRORS


### migrate_policy.txt


Example policy that migrates files older than 30 days from system pool to IBM Spectrum Protect. A policy like this has to be used with the migrate.sh script where it is referenced with parameter $polName. It is an example and might need adjustments.

The name of the policy file should be provide via the launcher script. This allows for more flexibility. It can also be defined as parameter in the migrate script, this would be a static definition. 



