#!/bin/bash
# Final round (probe3): the full grid on the round-7 code. Pane heights 30/45/70, widths
# 80 40 34 30 27 22 20 17 15 13 12 then 80, live-shaped and fixture rows, a fresh board
# (NARROW_STALE_S=86400) and a board already stale at session start (NARROW_STALE_S=1).
# The live x 45 arm also runs the /accounts readout at 40 27 20 15 12.
# Staggered: ten sessions started at once all blocked >10 min in the same keychain read
# (SecItemCopyMatching -> securityd, load ~250), so each arm starts only after the previous one
# has drawn its first frame (or 600 s pass).
D=/Users/chrisren/Development/.worktrees/wt-cc-232819-69438/docs/research/accounts-narrow-2026-10-22
PY=/tmp/acct-probe/venv/bin/python
L=/tmp/narrow-fix3/probe3/logs; mkdir -p "$L"; : > "$L/done.txt"
W=80,40,34,30,27,22,20,17,15,13,12,80
cd "$D" || exit 1
run() {  # <data> <rows> <stale_s> <out> [extra args...]
  local data=$1 rows=$2 stale=$3 out=$4; shift 4
  NARROW_TAG="-p3fin-$out" NARROW_START_S=900 NARROW_STALE_S="$stale" \
    "$PY" narrow-probe.py band "$data" "captures/$out" --rows "$rows" --widths "$W" "$@" \
    > "$L/$out.log" 2>&1
  echo "done $out rc=$?" >> "$L/done.txt"
}
stagger() {  # wait until <out>'s first frame exists, its arm ended, or 600 s
  local out=$1 t=0
  until [ -f "captures/$out/band-00-80.txt" ] || grep -q "done $out " "$L/done.txt" || [ $t -ge 600 ]; do
    sleep 5; t=$((t+5)); done
  echo "started $out after ${t}s" >> "$L/done.txt"
}
arm() { run "$@" & stagger "$4"; }
arm live 30 86400 fin-live-rows30
arm live 45 86400 fin-live-rows45 --readout --readout-widths 40,27,20,15,12
arm fx 45 86400 fin-fx-rows45
arm live 30 1 fin-live-rows30-stale
arm live 70 86400 fin-live-rows70
arm fx 30 86400 fin-fx-rows30
arm fx 70 86400 fin-fx-rows70
arm live 45 1 fin-live-rows45-stale
arm live 70 1 fin-live-rows70-stale
arm fx 45 1 fin-fx-rows45-stale
wait
echo ALL-DONE
