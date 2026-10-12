#!/usr/bin/env bats
# lr-reset-poller.sh § 2a — THE REROUTE LOOP HAS A CAP, AND ITS GIVE-UP IS PAGED ONCE (decision 1dc45a0d583c).
#
# THE INCIDENT. reroute_parked had only a 15-minute mark file: no attempt counter and no give-up.
# 46bc0436 was dispatched 119 times, 116 of them ending the same way ("recycle-in-place/FAILED —
# lr-handoff rc=2"); 492a787a parked 103 times on "CWD-GONE". Every verdict went to `--role desk`,
# which has no claimant, so none reached anyone. The fix counts each sid's tries per REFUSAL REASON
# (verdict + mechanism + first cause token of the last run's verdict.txt); after LR_REROUTE_MAX_SAME
# (3) tries ending the same reason the rail stops rerouting it and pages ONCE through lr-page —
# fact-only, sid and evidence path in the first 200 characters, no ask, no retry claim. The page
# marker is written only after lr-page returns 0. The clear paths are in lr-reset-poller-reroute-cap-clear.bats.
# One tick for the file; fixture and the off-box reasoning: lr-reset-poller-reroute-cap-helpers.bash.

load lr-reset-poller-reroute-cap-helpers

setup_file() {
  export HOME="$BATS_FILE_TMPDIR/home"; mkdir -p "$HOME"
  cap_env
  export GIVEUP=1dc45a01-0000-4000-8000-000000000001   # 2 tries + a 3rd ending the same reason
  export MIXED=1dc45a02-0000-4000-8000-000000000002    # 2 tries + a 3rd ending a DIFFERENT reason
  export PAGED=1dc45a03-0000-4000-8000-000000000003    # already gave up and paged this reason
  export PAGEFAIL=1dc45a07-0000-4000-8000-000000000007 # gives up, but lr-page does not post
  for s in "$GIVEUP" "$MIXED" "$PAGED" "$PAGEFAIL"; do park_rec "$s"; done
  seed "$GIVEUP" 2 "$R_FAIL"; last_run "$GIVEUP" "$V_FAIL"
  seed "$MIXED" 2 "$R_FAIL"; last_run "$MIXED" "$V_PARK"
  last_run "$PAGED" "$V_FAIL"; printf '3\t%s\t%s\n' "$RUNS/$PAGED" "$R_FAIL" > "$STATE/reroute/$PAGED.tries"
  printf '%s\n' "$R_FAIL" > "$STATE/reroute/$PAGED.paged"
  seed "$PAGEFAIL" 2 "$R_FAIL"; last_run "$PAGEFAIL" "$V_FAIL"
  run_tick
}
setup() { export HOME="$BATS_FILE_TMPDIR/home"; }
teardown_file() { cap_teardown; }

@test "the tick exits 0 under /bin/bash" {
  [ "$(cat "$BATS_FILE_TMPDIR/tick.rc")" -eq 0 ] || { cat "$BATS_FILE_TMPDIR/tick.out"; plog; false; }
}

@test "[RED] 1dc45a0d583c: a 3rd try ending the same reason stops the reroute and pages ONCE" {
  [ "$(dispatched "$GIVEUP")" -eq 0 ] || { cat "$FLEET_LOG"; plog; false; }
  grep -q "REROUTE-GAVE-UP $GIVEUP (next4) — 3 tries in a row ended: $R_FAIL" "$STATE/poller.log" || { plog; false; }
  [ "$(pages_for "$GIVEUP")" -eq 1 ] || { cat "$PAGE_ARGV"; false; }
  [ "$(cat "$STATE/reroute/$GIVEUP.paged")" = "$R_FAIL" ]
  [ -f "$STATE/parked/$GIVEUP.json" ]                      # the record stays: § 2 owns its reset
}

@test "[RED] 1dc45a0d583c: the page states the fact — sid and evidence in the first 200 chars, no ask, no retry claim" {
  line="$(grep "^- reroute stopped Session ${GIVEUP:0:8} " "$PAGE_ARGV" | head -1)"
  msg="${line#- reroute stopped }"                         # osascript argv: "-" <title> <text>
  [[ "${msg:0:200}" == *"${GIVEUP:0:8}"* ]] || { echo "$msg"; false; }
  [[ "${msg:0:200}" == *"$RUNS/$GIVEUP"* ]] || { echo "$msg"; false; }
  [[ "$msg" == *"lr-handoff rc=2"* ]] || { echo "$msg"; false; }
  [[ "$msg" != *retr* ]] || { echo "$msg"; false; }
  [[ "$msg" != *"cc-lr recover"* && "$msg" != *"Run "* && "$msg" != *please* ]] || { echo "$msg"; false; }
}

@test "1dc45a0d583c CONTROL: a 3rd try ending a DIFFERENT reason restarts the count and is rerouted" {
  [ "$(dispatched "$MIXED")" -eq 1 ] || { cat "$FLEET_LOG"; plog; false; }
  [ "$(cut -f1 "$STATE/reroute/$MIXED.tries")" = 1 ] || { cat "$STATE/reroute/$MIXED.tries"; false; }
  [ "$(pages_for "$MIXED")" -eq 0 ]
}

@test "1dc45a0d583c: a give-up already paged for that reason is neither rerouted nor paged again" {
  [ "$(dispatched "$PAGED")" -eq 0 ] || { cat "$FLEET_LOG"; false; }
  [ "$(pages_for "$PAGED")" -eq 0 ] || { cat "$PAGE_ARGV"; false; }
}

@test "1dc45a0d583c: a page lr-page did not post writes no marker, so the next tick pages again" {
  [ "$(pages_for "$PAGEFAIL")" -eq 1 ] || { cat "$PAGE_ARGV"; false; }
  [ ! -e "$STATE/reroute/$PAGEFAIL.paged" ] || { cat "$STATE/reroute/$PAGEFAIL.paged"; false; }
  [ "$(dispatched "$PAGEFAIL")" -eq 0 ]
}
