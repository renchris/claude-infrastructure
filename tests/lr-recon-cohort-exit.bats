#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031  # each @test is its own subshell
# Cohort expiry and the reset-aware drain (lr-wake 2026-10-18, Wave G; h defect 3, RC7).
#
# Cohort next4-7d-1792314000 still held 3e929a81 PRE-MOVE/IN-FLIGHT at 13:20, 11 h after it formed,
# with next4's weekly limit already reset (5% used): the cohort had no exit for "the source is healthy
# again". And the agent-installed drain rotated next4 "past its weekly reset", re-rotating healthy
# sessions every ~10 min, rc=1 each time.
# WHAT IS PINNED (lr_recon/tests/test_wave_g.py CohortExit, ResetAwareDrain):
#   · a member whose source reads 5% weekly is NOT_NEEDED and continued in place: its target seat is
#     voided, the stay wake types `continue` in its OWN pane, the census does not re-plan it, and the
#     fresh turn closes it NOT_NEEDED;
#   · past the cohort's reset with nothing in its pane it is NOT_NEEDED at once;
#   · CONTROLS: 100% weekly, no usage reading, or a confirmed transplant keep the record as it is;
#   · the drain: past the reset is not capped; a capped window drains until its first rc=1 and then
#     stops until a new window; a fresh usage row under 100 outranks an old fact; the CLI runs
#     nothing without --act.
# [RED] cases fail on the tree before the fix.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd -P)"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
}
py() { (cd "$REPO/scripts/limit-recover" && python3 -m unittest "lr_recon.tests.test_wave_g.$1" 2>&1); }

@test "1 [RED] cohort next4-7d: next4 at 5% weekly → NOT_NEEDED, continued in place, no move" {
  run py CohortExit.test_next4_at_5pct_weekly_member_is_not_needed_and_continued_in_place
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "2 [RED] past the cohort's reset with nothing in its pane → NOT_NEEDED at once" {
  run py CohortExit.test_past_the_cohort_reset_with_nothing_in_the_pane_closes_at_once
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "3 CONTROL a source still at 100%, no usage reading, or a confirmed transplant keep the record" {
  run py CohortExit.test_control_a_source_still_at_100pct_keeps_its_move
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  run py CohortExit.test_control_no_usage_reading_is_not_recovery
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  run py CohortExit.test_control_a_confirmed_transplant_is_the_phase_tables
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "4 [RED] drain: past the reset is not capped, and a fresh row under 100 outranks an old fact" {
  run py ResetAwareDrain.test_past_the_reset_is_not_capped
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  run py ResetAwareDrain.test_a_fresh_usage_row_under_100_outranks_an_old_fact
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "5 [RED] drain: a capped window stops after its first rc=1; a new window drains again" {
  run py ResetAwareDrain.test_a_capped_window_drains_until_its_first_rc_1_then_stops
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  run py ResetAwareDrain.test_the_cli_runs_nothing_without_act_and_latches_rc_1_with_it
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}
