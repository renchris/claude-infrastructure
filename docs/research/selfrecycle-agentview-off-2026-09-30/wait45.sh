#!/bin/bash
# stands in for `bash handoff-fire.sh --recycle`: a foreground tool call that is still running at /exit
echo "wait45 started"
i=0
while [ "$i" -lt 45 ]; do /bin/sleep 1; i=$((i + 1)); done
echo "wait45 done"
