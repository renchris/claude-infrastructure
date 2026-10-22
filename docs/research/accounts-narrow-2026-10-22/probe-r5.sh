#!/bin/bash
# Round-5 real-pty sweep (fixer-1): the bar cells after the round-2 fixes.
D=/Users/chrisren/Development/.worktrees/wt-cc-232819-69438/docs/research/accounts-narrow-2026-10-22
PY=/tmp/acct-probe/venv/bin/python
L=/tmp/narrow-fix/fixer-1/probe-logs; mkdir -p "$L"
W=80,40,34,30,27,22,20,17,16,15,13,12,80
cd "$D" || exit 1
for spec in "live 30" "live 45" "fx 45"; do
  # shellcheck disable=SC2086  # "<dataset> <rows>": splitting it is the point
  set -- $spec
  NARROW_TAG=-r5-$2 NARROW_START_S=600 NARROW_STALE_S=86400 \
    "$PY" narrow-probe.py band "$1" "captures/r5-$1-rows$2" --rows "$2" --widths "$W" \
    > "$L/r5-$1-rows$2.log" 2>&1 &
done
NARROW_TAG=-r5-aged30 NARROW_START_S=600 NARROW_IDLE_S=330 \
  "$PY" narrow-probe.py band live captures/r5-live-rows30-aged --rows 30 --widths 80,27,22,20,17,80 \
  > "$L/r5-live-rows30-aged.log" 2>&1 &
NARROW_TAG=-r5-aged45fx NARROW_START_S=600 NARROW_IDLE_S=330 \
  "$PY" narrow-probe.py band fx captures/r5-fx-rows45-aged --rows 45 --widths 80,40,32,27,22,80 \
  > "$L/r5-fx-rows45-aged.log" 2>&1 &
wait
echo ALL-DONE
