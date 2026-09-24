#!/bin/bash
# probe.sh <arm> <task> <first-rep> <last-rep> <config-dir> — run a post-gate mechanism probe:
# reps run one after another (never two reps of one task at once), each collected by collect.py.
# Probe reps are numbered above the gate's 1-10 so they never overwrite a gate run.
set -u
H=$(cd "$(dirname "$0")" && pwd)
ARM=$1; TASK=$2; A=$3; B=$4; CCD=$5
for rep in $(seq "$A" "$B"); do
  "$H/run.sh" "$ARM" "$TASK" "$rep" "$CCD"
  python3 "$H/collect.py" "${GATE_ROOT:-/tmp/tokeff-gate}/runs/$TASK/r$rep" "$TASK"
done
