#!/bin/bash
# Round-6 real-pty sweep (probe-2): every height x width x dataset, plus the /accounts readout.
D=/Users/chrisren/Development/.worktrees/wt-cc-232819-69438/docs/research/accounts-narrow-2026-10-22
PY=/tmp/acct-probe/venv/bin/python
L=/tmp/narrow-fix/probe-2/logs; mkdir -p "$L"
W=80,40,34,30,27,22,20,17,16,15,13,12,80
cd "$D" || exit 1
for spec in "live 30" "live 45" "live 70" "fx 30" "fx 45" "fx 70"; do
  # shellcheck disable=SC2086  # "<dataset> <rows>": splitting it is the point
  set -- $spec
  extra=()
  [ "$1 $2" = "live 45" ] && extra=(--readout --readout-widths "40,20")
  NARROW_TAG=-p2r6-$1-$2 NARROW_START_S=900 NARROW_STALE_S=86400 \
    "$PY" narrow-probe.py band "$1" "captures/r6-$1-rows$2" --rows "$2" --widths "$W" "${extra[@]}" \
    > "$L/r6-$1-rows$2.log" 2>&1 &
done
NARROW_TAG=-p2r6-fx-100ro NARROW_START_S=900 NARROW_STALE_S=86400 \
  "$PY" narrow-probe.py band fx captures/r6-fx-rows100-readout --rows 100 --widths 80 \
  --readout --readout-widths 40,20 > "$L/r6-fx-rows100-readout.log" 2>&1 &
wait
echo ALL-DONE
