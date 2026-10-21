#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031  # each @test is its own subshell
# W11 (B3 lever 4): slot priority, subject-relative. The move lane's swap slots and the reconciler's
# boot slots are one pool (locks/swap-slots, BootSlots' shared store). With the lane holding 4 of 6,
# an overdue limited record had 2 (D_eff 2; 7 `boot-slots` refusals on 10-18). While an overdue A/R
# waits on a boot slot the reconciler leases locks/slot-priority ("until=<epoch>", "pid=<its pid>"),
# and lr_swap_slot_acquire (lr-move-lib.sh) caps the lane at 1 slot while `until` is ahead.
# WHAT IS PINNED:
#   · the lane takes <= 1 slot while `until` is in the future (before W11: 4), the reconciler's own
#     slots not counted against it;
#   · a file whose `until` has passed is ignored (4), and so is the lease under locks/slot-yield.off;
#   · a 300 s pass whose lease is refreshed from clock.step keeps the cap; the same pass with the
#     hook unbound lets the lease lapse (the control that proves the refresh is what holds it).
# Hermetic: every slot holder is a `sleep` this suite started and kills.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd -P)"
  LRD="$REPO/scripts/limit-recover"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export TMPDIR="$BATS_TEST_TMPDIR/tmp"; mkdir -p "$TMPDIR"
  export LR_STATE_DIR="$BATS_TEST_TMPDIR/lr"
  export LR_RECON_ROOT="$LR_STATE_DIR/recon"
  mkdir -p "$LR_STATE_DIR/locks/swap-slots"
  PIDS="$BATS_TEST_TMPDIR/holders.pids"; : > "$PIDS"
}
teardown() { reap; }
# Every holder's pid goes to a file: `take` runs inside $(…), whose array writes are lost.
reap() {
  local p
  while IFS= read -r p; do
    [ -z "$p" ] || kill "$p" 2>/dev/null || true  # a `none` taker has already exited
  done < "$PIDS"
  : > "$PIDS"
}

# One move-lane worker: acquire at width 4, then hold the slot (exec keeps $$ = the stamped pid).
# Its stdout is detached, or the $(take …) that started it would wait out the sleep.
take() { # $1=tag → prints took|none
  local out="$BATS_TEST_TMPDIR/take.$1"
  bash -c '. "$1/lr-lib.sh"; . "$1/lr-move-lib.sh"
    if lr_swap_slot_acquire 4; then echo took > "$2"; exec sleep 120; else echo none > "$2"; fi' \
    _ "$LRD" "$out" > /dev/null 2>&1 &
  echo "$!" >> "$PIDS"
  local i=0
  while [ ! -s "$out" ] && [ "$i" -lt 200 ]; do sleep 0.05; i=$((i + 1)); done
  cat "$out"
}
four() { local n=0 i; for i in 1 2 3 4; do [ "$(take "$1$i")" = took ] && n=$((n + 1)); done; echo "$n"; }
lease() { # $1=until epoch $2=pid → the reconciler's file
  printf 'until=%s\npid=%s\nwhy=test\n' "$1" "$2" > "$LR_STATE_DIR/locks/slot-priority"
}
# A stand-in reconciler: a live process whose pid the lease names, holding slot-5 and slot-6.
reconciler() {
  sleep 120 > /dev/null 2>&1 & RP=$!; echo "$RP" >> "$PIDS"
  local s
  for s in 5 6; do
    mkdir -p "$LR_STATE_DIR/locks/swap-slots/slot-$s"
    bash -c '. "$1/lr-lib.sh"; lr_pidlock_stamp "$2" "$3"' _ "$LRD" "$LR_STATE_DIR/locks/swap-slots/slot-$s" "$RP"
  done
}

@test "1 [RED] the move lane takes at most 1 slot while the lease's until is in the future" {
  reconciler
  lease "$(( $(date +%s) + 300 ))" "$RP"
  n="$(four a)"
  echo "took=$n"
  [ "$n" -eq 1 ]
}

@test "2 CONTROL with no lease the lane takes its full width of 4" {
  reconciler
  n="$(four b)"
  echo "took=$n"
  [ "$n" -eq 4 ]
}

@test "3 a lease whose until has passed is ignored" {
  reconciler
  lease "$(( $(date +%s) - 5 ))" "$RP"
  n="$(four c)"
  echo "took=$n"
  [ "$n" -eq 4 ]
}

@test "4 the kill switch locks/slot-yield.off ignores a standing lease" {
  reconciler
  lease "$(( $(date +%s) + 300 ))" "$RP"
  touch "$LR_STATE_DIR/locks/slot-yield.off"
  n="$(four d)"
  echo "took=$n"
  [ "$n" -eq 4 ]
}

# A 300 s pass on a fake clock that ends at the real now: the lease written at its start (until =
# start + 180) has lapsed by its end unless clock.step refreshed it. $1 = bind|unbound.
long_pass() {
  (cd "$LRD" && PYTHONDONTWRITEBYTECODE=1 /usr/bin/python3 -c '
import sys, time
from unittest import mock
from lr_recon import __main__ as M, clock, types as T
real = time.time()
t = [real - 300.0]
paths = T.Paths.from_env(root=sys.argv[2])
ctx = M.Ctx(paths, None, sys.argv[3])
with mock.patch.object(time, "time", lambda: t[0]):
    ctx.last_pass_s = 10.0
    ctx.slot_priority_want = "overdue test waits on boot slots"
    M._slot_priority(ctx)
    if sys.argv[1] == "bind":
        clock.bind_step_hook(lambda: M._slot_priority_refresh(ctx))
    for _ in range(30):
        t[0] += 10.0
        clock.step()
    clock.bind_step_hook(None)
' "$1" "$LR_RECON_ROOT" "$HOME")
}

@test "5 [RED] a 300 s pass refreshed from clock.step keeps the cap; unbound, the lease lapses" {
  run long_pass bind
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  until_="$(sed -n 's/^until=//p' "$LR_STATE_DIR/locks/slot-priority")"
  echo "until=$until_ now=$(date +%s)"
  [ "$until_" -gt "$(date +%s)" ]
  n="$(four e)"
  echo "took=$n"
  [ "$n" -le 1 ]
  # the control: the same pass with the hook unbound leaves a lapsed lease, and the lane its 4
  reap
  rm -rf "$LR_STATE_DIR/locks/swap-slots"; mkdir -p "$LR_STATE_DIR/locks/swap-slots"
  run long_pass unbound
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  until_="$(sed -n 's/^until=//p' "$LR_STATE_DIR/locks/slot-priority")"
  echo "unbound until=$until_ now=$(date +%s)"
  [ "$until_" -le "$(date +%s)" ]
  n="$(four f)"
  echo "unbound took=$n"
  [ "$n" -eq 4 ]
}
