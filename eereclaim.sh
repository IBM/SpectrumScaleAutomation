#!/bin/bash
#
################################################################################
# The MIT License (MIT)                                                        #
#                                                                              #
# Copyright (c) 2020 Nils Haustein                             				   #
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
# Name: eereclaim.sh
#
# reclaim script for Spectrum Archive EE when used with launcher
# - reclaims tapes in accordance to the arguments given
#
# Invokation: eereclaim.sh reclaim-options
#             reclaim-options are the options in accordance to the eeadm tape reclaim command. 
#
# Output: all output is logged to STDOUT
#
# Author: Nils Haustein
# 
# Change History
# --------------
# 12/29/20: first implementation
# 
#******************************************************************************************************** 
#
#
# User defined variables
# -------------------------
# The following options for the reclaim command can be preset in this script or they are passed from launcher as second argument
# If there is no second argument passed by launcher then these options are considered, otherwise the second argument is used
# For reclaim options see: https://www.ibm.com/support/knowledgecenter/en/ST9MBR_1.3.1/ee_eeadm_tape_reclaim.html
# For example: reclaimOpts="-p poolname -l libname -U 70 -G 90 [-m 2 -C -n 2]"
reclaimOpts=""


# Constants
# -----------
# do not adjust these settings
# eeadm command
eeCmd="/opt/ibm/ltfsee/bin/eeadm"

#define return codes
rcGood=0  # successful run
rcWarn=1  # run was ok, some warnings however
rcErr=2   # failed
# global return code
globalRC=0


#**************************** Main ************************************
# assign reclaim options. If they are not given by launcher then use the preset options
if [[ -z $reclaimOpts ]];
then 
  reclaimOpts=$*
fi

# present banner
echo "$(date) RECLAIM: reclaim operation started on $(hostname) with options: $reclaimOpts"

# if there are not options for reclaim defined then exit
if [[ -z $reclaimOpts ]];
then
  echo "RECLAIM: ERROR, no reclaim options specified, exit."
  exit $rcErr
fi


#start reclamation
echo "$(date) RECLAIM: Starting reclaim with these options: $reclaimOpts"
echo "DEBUG: $eeCmd tape reclaim $reclaimOpts"
$eeCmd tape reclaim $reclaimOpts
rc=$?

# present ending banner
echo "$(date) RECLAIM: Finished relamation with return code $rc"
if (( rc == 0 )); then
  exit $rcGood
elif (( rc == 1 )); then 
  exit $rcWarn
else 
  exit $rcErr
fi
