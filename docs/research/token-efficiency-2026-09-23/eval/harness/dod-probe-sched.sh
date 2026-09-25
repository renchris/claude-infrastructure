#!/bin/bash
# dod-probe-sched.sh <cell> <config-dir> — run one cell of the CC_DOD_LINEAGE_ONLY probe:
# 6 reps in ABBAAB order (default = A), one after another, each collected by collect.py.
#   cells: U-T07 (unrelated, T07) · U-T10 (unrelated, T10) · L-T10 (legit, T10) · L-T18 (legit, T18)
# Reps are numbered per cell (U 1-6, L 11-16) so the two T10 cells never share a run dir.
set -u
[ $# -eq 2 ] || { echo "usage: dod-probe-sched.sh <cell> <config-dir>" >&2; exit 2; }
H=$(cd "$(dirname "$0")" && pwd)
G=${GATE_ROOT:-/private/tmp/tokeff-dodprobe}
case "$1" in
  U-T07) SCEN=unrelated TASK=T07-close-unpushed BASE=0 ;;
  U-T10) SCEN=unrelated TASK=T10-status-plan BASE=0 ;;
  L-T10) SCEN=legit TASK=T10-status-plan BASE=10 ;;
  L-T18) SCEN=legit TASK=T18-plan-mark-done BASE=10 ;;
  *) echo "bad cell: $1" >&2; exit 2 ;;
esac
i=0
for ARM in default lineage lineage default default lineage; do
  i=$((i + 1)); REP=$((BASE + i))
  GATE_ROOT="$G" "$H/dod-probe.sh" "$ARM" "$SCEN" "$TASK" "$REP" "$2"
  GATE_ROOT="$G" python3 "$H/collect.py" "$G/runs/$TASK/r$REP" "$TASK"
  printf '%s %s %s r%s %s\n' "$(date +%T)" "$1" "$ARM" "$REP" "$(cat "$G/runs/$TASK/r$REP/out/rc" 2>/dev/null)" >> "$G/sched.log"
done
