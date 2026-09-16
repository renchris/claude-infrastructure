#!/bin/bash
N=0
LOGF="/private/tmp/ktb-fallback/winch-$1.log"
: > "$LOGF"
trap 'N=$((N+1)); echo "WINCH $N rows=$(tput lines) cols=$(tput cols) at $(date +%H:%M:%S.%N)" >> "$LOGF"' WINCH
echo "PANE $1 start rows=$(tput lines) cols=$(tput cols)" >> "$LOGF"
while true; do sleep 0.3; done
