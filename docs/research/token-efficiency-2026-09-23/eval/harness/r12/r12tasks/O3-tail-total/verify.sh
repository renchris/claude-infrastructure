#!/bin/bash
# verify.sh <answer-file> — PASS when the answer carries the real total.
want="$(./report.sh | tail -1 | sed "s/[^0-9]//g")"
if tr -d ",." < "$1" | grep -qw "$want"; then echo PASS; else echo "want $want"; echo FAIL; fi
