#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031  # each @test is its own subshell
# One driver per session: the reconciler takes runs/by-sid/<sid>.active before the token
# (lr-wake 2026-10-18, REPORT §4 Wave G "One driver per session").
#
# 3e929a81 was driven at once by drain batch 072521Z (`cc-lr move`, which takes the claim), the
# poller's REQUEST at 07:47Z and reconciler cohort next4-7d-1792314000, and ended a guarded husk for
# ~10 h: the reconciler's own claim (_own_and_charge) logged `held` and dispatched anyway.
# WHAT IS PINNED (lr_recon/tests/test_wave_g.py OneDriverPerSession):
#   · two lr-handoff drivers on one session, 2 s apart: the second (the reconciler) gets claim-held,
#     mints no admission token and spawns nothing, and says so once;
#   · once the first driver is gone, the reconciler takes the claim and drives it (CONTROL);
#   · a bash lane (lr_claim_take) arriving 2 s after the reconciler is refused (rc 1).
# [RED] cases fail on the tree before the fix.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd -P)"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
}
py() { (cd "$REPO/scripts/limit-recover" && python3 -m unittest "lr_recon.tests.test_wave_g.OneDriverPerSession.$1" 2>&1); }

@test "1 [RED] a second driver 2 s later gets claim-held: no token minted, nothing spawned" {
  run py test_a_second_driver_2s_later_gets_claim_held_and_no_token
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "2 CONTROL once the first driver is gone, the reconciler takes the claim and drives it" {
  run py test_once_the_first_driver_is_gone_the_reconciler_takes_the_claim
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "3 [RED] a bash lane 2 s after the reconciler's dispatch is refused by the claim" {
  run py test_a_bash_lane_two_seconds_after_the_reconciler_is_refused
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}
