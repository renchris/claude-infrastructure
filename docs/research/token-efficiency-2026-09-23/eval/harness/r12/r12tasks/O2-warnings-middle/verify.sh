#!/bin/bash
# verify.sh <answer-file> — PASS when all three warnings are named with their file and line (any layout on one line).
ok=1
for w in "socket.c 88" "buffer.c 214" "window.c 31"; do f=${w% *}; l=${w#* }; grep -F "$f" "$1" | grep -qw "$l" || { echo "missing $f:$l"; ok=0; }; done
if [ "$ok" = 1 ]; then echo PASS; else echo FAIL; fi
