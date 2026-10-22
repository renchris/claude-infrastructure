#!/bin/bash
# Round-7 real-pty check (fix3): the cells this round changes, in parallel arms.
#   live 30 / 45  the column form at 20-21 columns: terse on a 10-row band, labelled on a 17-row one
#   fx 30         split lanes on one row at 80x30 (round 6: next3 under the fold)
#   live 30 stale a board already stale when the session starts now reaches the band (P3)
D=/Users/chrisren/Development/.worktrees/wt-cc-232819-69438/docs/research/accounts-narrow-2026-10-22
PY=/tmp/acct-probe/venv/bin/python
L=/tmp/narrow-fix3/probe/logs; mkdir -p "$L"
cd "$D" || exit 1
run() {  # <tag> <data> <rows> <widths> <stale_s> <out>
  NARROW_TAG="-f3r7-$1" NARROW_START_S=900 NARROW_STALE_S="$5" \
    "$PY" narrow-probe.py band "$2" "captures/$6" --rows "$3" --widths "$4" > "$L/$6.log" 2>&1
}
run live30 live 30 80,30,27,22,21,20,17,80 86400 r7-live-rows30 &
run live45 live 45 80,22,21,20,17,80 86400 r7-live-rows45 &
run fx30 fx 30 80,40,27,80 86400 r7-fx-rows30 &
run stale30 live 30 27,22,80 1 r7-live-rows30-stale &
wait
echo ALL-DONE
