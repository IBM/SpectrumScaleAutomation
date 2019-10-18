# Introduction

IBM Spectrum Scale™ is a software-defined scalable parallel file system storage 
providing a comprehensive set of storage services. Some of the differentiating 
storage services are the integrated backup function and storage tiering. These 
services typically run in the background according to pre-defined schedules. 
This project presents a flexible framework for automating Spectrum Scale storage
services. 

The framework relies on the following components:
- The control components (launcher.sh) selects the appropriate cluster node 
initiating the storage service operation, starts the storage service if the 
node state is appropriate, manages logging and log-files and return codes. 
The control component is typically invoked by the scheduler and the storage 
services being started might be backup (backup.sh) or storage tiering (migrate.sh)
- The backup component (backup.sh) performs the backup using the mmbackup-command
- The storage tiering component (migrate.sh) performs pre-migration or migration
using the mmapplypolicy-command
- The schedule that invokes the control component.

The framework requires that all cluster nodes with a manager role assigned must 
be able to run the automation components. These nodes must not necessarily be 
the nodes performing the storage service operation but must be able to launch it.

## Disclaimer and license
This project is under [MIT license](LICENSE).

--------------------------------------------------------------------------------

# Components
This project includes the following scripts:

Note, the appropriate scripts from the selection below must be installed on 
all Spectrum Scale nodes with a manager role. 


## launcher.sh: 
This is the control component that is invoked by the scheduler. It checks if
the node it is running on has the this is the cluster manager role. If this 
is the case it selects a node from a pre-defined node class for running the
storage service and thereby prefers the local node if this is member of the 
node class or the node class is not defined. After selecting the node it 
checks if the node and file system state is appropriate, assigns, manages 
logfiles and finally starts the storage service operation (backup or migrate)
using ssh. All output (STDOUT and STDERR) is written to the selected logfile. 


Invokation:

    # launcher.sh operation [file sytem name]

The operation needs to be adjusted according to the needs. Pre-defined 
operations are backup and migrate. The file system name is optional. 


Return codes:

0 -  Operation completed SUCCESSFUL

1 -  Operation completed with WARNING

2 -  Operation completed with ERRORS

When a storage service has been started its return code is inherited

--------------------------------------------------------------------------------

## backup.sh
This is the backup component and performs the backup by executing the mmbackup 
command. It may optionally create a snapshot, run mmbackup from there and 
subsequently delete the snapshot.


Invokation: 

    # backup.sh [file system name]

The file system name is optional. The file system name can be given explicitely
or it is exported by the control component (launcher.sh) or it is hard-code in 
this script. 


Return codes:

0 -  Operation completed SUCCESSFUL

1 -  Operation completed with WARNING

2 -  Operation completed with ERRORS

--------------------------------------------------------------------------------

## migrate.sh
This is the migration component and performs the migration by executing the 
mmapplypolicy command. The policy for the migration must be stored in a separate 
file referenced in this script (migrate_policy.txt).


Invokation: 

    # migrate.sh [file system name]

The file system name is optional. The file system name can be given explicitely
or it is exported by the control component (launcher.sh) or it is hard-code in 
this script.


Return codes:

0 -  Operation completed SUCCESSFUL

1 -  Operation completed with WARNING

2 -  Operation completed with ERRORS


### migrate_policy.txt


This policy migrates files older than 30 days from system pool to TSM. A policy
like this has to be used with the migrate.sh script where it is referenced with 
parameter $polName. It is an example and might need adjustments.

