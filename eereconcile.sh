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
# Name: eereconcile.sh
#
# reconcile script for Spectrum Archive EE to be used with launcher
# - reconciles file systems, tapes and pools in conjuction with Spectrum Archive EE
#
# Invokation: eereconcile.sh reconcile-options
#             reconcile-options are the options in accordance to the eeadm tape reconcile command. 
#
# Output: all output is logged to STDOUT
#
# Author: Nils Haustein
# 
# Change History
# --------------
# 12/30/20: first implementation
# 
#******************************************************************************************************** 
#
#
# User defined variables
# -------------------------
# The following options for the reconcile command can be preset in this script or they are passed from launcher as second argument
# If there is no second argument passed by launcher then these options are considered, otherwise the second argument is used
# For reconcile options see: https://www.ibm.com/support/knowledgecenter/en/ST9MBR_1.3.1/ee_eeadm_tape_reconcile.html
# For example: reconcileOpts="-p poolname -l libname -g fspath [--commit-to-tape]"
reconcileOpts=""


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
# assign reconcile options. If they are not given by launcher then use the preset options
if [[ -z $reconcileOpts ]];
then 
  reconcileOpts=$*
fi

# present banner
echo "$(date) RECONCILE: reconcile operation started on $(hostname) with options: $reconcileOpts"

# if there are not options for reconcile defined then exit
if [[ -z $reconcileOpts ]];
then
  echo "RECONCILE: ERROR, no reconcile options specified, exit code $rcErr."
  exit $rcErr
fi


#start reconcile
echo "$(date) RECONCILE: Starting reconcile with these options: $reconcileOpts"
echo "DEBUG: $eeCmd tape reconcile $reconcileOpts"
$eeCmd tape reconcile $reconcileOpts
rc=$?

# present ending banner
echo "$(date) RECONCILE: Finished relamation with return code $rc"
if (( rc == 0 )); then
  exit $rcGood
elif (( rc == 1 )); then 
  exit $rcWarn
else 
  exit $rcErr
fi
