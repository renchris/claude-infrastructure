#!/bin/bash
T="$HOME/.claude-next/projects/-private-tmp-lrw0-scratch/73cc276b-ee3c-400e-81c6-10d71226fa4e.jsonl"; OUT=/tmp/lrw0/m2-samples.txt
s(){ printf '%s t+%ss mtime=%s lines=%s bytes=%s claude_alive=%s\n' "$(date -u +%H:%M:%S)" "$1" "$(stat -f %m "$T")" "$(wc -l < "$T" | tr -d ' ')" "$(stat -f %z "$T")" "$(/bin/ps -axo command= | grep -c -- '[r]esume 73cc276b')"; }
: > $OUT; s pre >> $OUT
# shellcheck disable=SC2016  # $HOME must expand in the pane's shell, not in this one
/tmp/lrw0/k send-text --match id:970 'clear; $HOME/.claude-284/node_modules/.bin/claude --model claude-haiku-4-5-20251001 --resume 73cc276b-ee3c-400e-81c6-10d71226fa4e'$'\r'
t0=$(date +%s)
for off in 5 15 30 60 120 180 300 450 600 660; do while [ $(( $(date +%s)-t0 )) -lt $off ]; do /bin/sleep 1; done; s $off >> $OUT; done
echo DONE >> $OUT
