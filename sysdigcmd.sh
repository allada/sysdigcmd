#!/bin/bash
# Copyright (c) 2009 Nathan (Blaise) Bruer
#
# MIT LICENSE
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

set -eo pipefail

if [[ "$1" == "" || "$1" == "-h" || "$2" == "" ]]; then
   echo "This script will log all files opened during runtime of another program into a file."
   echo ""
   echo "usage: sudo $(basename $0) {OUTPUT_FILE_PATH} {EXECUTABLE} [{ARGS} ...]"
   echo ""
   echo "  OUTPUT_FILE_PATH - The file to log the opened files to."
   echo "  EXECUTABLE  - The executable to capture."
   echo "  ARGS             - [optional] Arguments to apss to executable."
   echo ""
   echo "Note: This program requires sudo, but the EXECUTABLE will be run under normal user."
   echo ""
   exit 1
fi

OUTPUT_FILE_PATH=$(realpath $1)
shift  # Shift all the arguments to the left (remove first argument).

if [[ -z ${SUDO_GID} ]]; then
   echo "This script must be run with sudo." 
   exit 1
fi

PARENT_PID=$(exec sh -c 'echo "$PPID"')
NOFICATION_OF_SHUTDOWN_FILE="/tmp/$PARENT_PID.$RANDOM$RANDOM"

# Used to communicate between the two shell processes.
exec {TO_CHILD_FD}<> <(:)
exec {FROM_CHILD_FD}<> <(:)

run_sysdig () {
  # The first line sent across processes will be the PID to latch to.
  read PID_TO_LATCH <&$TO_CHILD_FD

  READY_FILE="/tmp/$(exec sh -c 'echo "$PPID"').$RANDOM$RANDOM"
  exec {SYSDIG_FD}< <(sysdig -p "%fd.name" "(fd.name=$NOFICATION_OF_SHUTDOWN_FILE or fd.name=$READY_FILE or proc.apid=$PID_TO_LATCH) and (evt.type=open or evt.type=openat)" 2>&1)
  # Close the file desciptor as we are done with it.
  exec {TO_CHILD_FD}>&-

  while ! read -t .01 -u $SYSDIG_FD; do
    touch "$READY_FILE"
    rm "$READY_FILE"
  done
  while read -t .01 -u $SYSDIG_FD; do
    # Drain the READY_FILE touches, there will likely be a bunch in queue.
    true
  done
  echo "1" >&$FROM_CHILD_FD

  # Now that we know sysdig started sniff out the process id so we know how to kill it later.
  SELF_PID=$(exec sh -c 'echo "$PPID"')
  SYSDIG_CMD_PID=$(ps -o pid,comm --forest -g -p $SELF_PID | grep -E " sysdig$" | sed -e 's/^\s*\([0-9]\+\)\s.*$/\1/g')

  # Create file (if not exist) with outside user permissions.
  sudo -u "#$SUDO_UID" -g "#$SUDO_GID" cp /dev/null "$OUTPUT_FILE_PATH"

  while read -r LINE <&$SYSDIG_FD; do
    if [ "$LINE" == "$NOFICATION_OF_SHUTDOWN_FILE" ]; then
      kill $SYSDIG_CMD_PID 2>&1 >/dev/null
      continue
    elif [ "$LINE" == "$READY_FILE" ]; then
      # Sometimes we have some stragglers from our READY_FILE, safe to just ignore them.
      continue
    fi
    echo "$LINE" >>"$OUTPUT_FILE_PATH"
  done
  exec {SYSDIG_FD}>&-
  exit 0
}

run_command () {
  # Send our subshell's PID.
  parent_pid=$(exec sh -c 'echo "$PPID"')
  echo "$parent_pid" >&$TO_CHILD_FD

  # Wait for sysdig to be ready.
  read <&$FROM_CHILD_FD

  # Execute command.
  exec sudo -u "#$SUDO_UID" -g "#$SUDO_GID" "$@"
}

# Run sysdig and all the stuff needed to log the data to disk.
run_sysdig &
SYSDIG_PID=$!

# We want the sub command to be in its own process.
run_command $@ &
RUNCMD_PID=$!

# Wait for run command to finish.
wait $RUNCMD_PID
RETURN_CODE=$?

# Notify our sysdig process that we are done and can stop sniffing.
touch "$NOFICATION_OF_SHUTDOWN_FILE"
rm "$NOFICATION_OF_SHUTDOWN_FILE"

# Wait for our sysdig process to finish.
wait $SYSDIG_PID
SYSDIG_RETURN_CODE=$?

exit $SYSDIG_RETURN_CODE || $RETURN_CODE
