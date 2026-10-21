#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031  # each @test is its own subshell
# W11 (B3, rescoped): the per-record deadline (docs/plans/LR_SUSTAINED_LOAD_IMPL.md § W11).
# A limited record past detected + 600 s is OVERDUE: its first turn skips the soft gates (restore-r,
# pace and pacer — still charged — the probe and its drip) inside a lane of 6 un-ENGAGED deadline
# first turns, at most 3 per account, while an in-process hard stop reads clear. Every hard gate is
# untouched. The cases live in lr_recon/tests/test_deadline.py; this suite runs them one per @test
# under the deployment interpreter, with HOME, LR_STATE_DIR, LR_RECON_ROOT and TMPDIR under /tmp.
# [RED] cases fail on the W11 parent tree; CONTROL cases pass in both arms; MutantsDie proves each
# new rule's mutant dies.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd -P)"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export TMPDIR="$BATS_TEST_TMPDIR/tmp"; mkdir -p "$TMPDIR"
  export LR_STATE_DIR="$BATS_TEST_TMPDIR/lr"
  export LR_RECON_ROOT="$LR_STATE_DIR/recon"
}
py() {
  (cd "$REPO/scripts/limit-recover" && PYTHONDONTWRITEBYTECODE=1 /usr/bin/python3 -m unittest "lr_recon.tests.test_deadline.$1" 2>&1)
}
ok() { run py "$1"; [ "$status" -eq 0 ] || { echo "$output"; false; }; }

@test "D1 [RED] 30 overdue PLANNED on one account: the per-account cap, every one admit:deadline" { ok Lane.test_d1_overdue_cohort_on_one_account_is_admitted_by_the_deadline_lane; }
@test "D2 CONTROL a fresh cohort takes today's gates (mutant: overdue always true)" { ok Lane.test_d2_control_a_fresh_cohort_takes_todays_gates; }
@test "D3 [RED] a standing probe refusal does not hold overdue first turns; the probe is not called" { ok Lane.test_d3_standing_probe_refusal_does_not_hold_overdue_first_turns; }
@test "D4 decide: an overdue member skips the probe" { ok Lane.test_d4_decide_overdue_skips_the_probe; }
@test "D5 a 24-member cohort is admitted by its deadline plus one pass (today +690 s)" { ok Lane.test_d5_a_24_member_cohort_is_admitted_from_its_deadline; }
@test "D6 30 overdue C records on one account stay within the per-account cap over 5 passes" { ok Lane.test_d6_thirty_overdue_c_records_on_one_account_stay_within_the_cap; }
@test "D7 a first turn that never ENGAGES leaves the lane after T_att" { ok Lane.test_d7_a_first_turn_that_never_engages_leaves_the_lane_after_t_att; }
@test "bound: t_first within deadline + P + ceil(k_r/D_eff)·T_att, no move-lane slots held" { ok Bound.test_bound_with_no_move_lane_slots_held; }
@test "bound [RED] the same with the move lane holding 4 of 6 slots" { ok Bound.test_bound_with_four_move_lane_slots_held; }
@test "mint failed: no A/R spawn, an event, the charges kept, a retry next pass" { ok Lane.test_mint_failure_spawns_no_move_and_keeps_the_charges; }
@test "one probe call for two candidates in a pass" { ok Lane.test_one_probe_call_for_two_candidates; }
@test "the retry bound names the workers-cap as a wait" { ok Lane.test_workers_cap_is_a_named_wait_for_an_overdue_retry; }
@test "a re-offered reset wait does not jump a fresh detection" { ok Lane.test_a_reoffered_reset_wait_does_not_jump_a_fresh_detection; }
@test "H1 CONTROL team-live holds an overdue record" { ok HardGates.test_h1_team_live; }
@test "H2 CONTROL duplicate-risk holds an overdue record" { ok HardGates.test_h2_duplicate_risk; }
@test "H3 CONTROL a claim held by a live driver: no token, no spawn" { ok HardGates.test_h3_claim_held_by_a_live_driver; }
@test "H4 CONTROL process-live holds an overdue record" { ok HardGates.test_h4_process_live; }
@test "H5 CONTROL plan-only holds an overdue record" { ok HardGates.test_h5_plan_only; }
@test "H6 CONTROL C inside its quiet grace" { ok HardGates.test_h6_c_inside_its_quiet_grace; }
@test "H7 CONTROL census holds are never movers" { ok HardGates.test_h7_census_holds_are_never_movers; }
@test "H8 CONTROL an overdue record's env and argv equal a fresh one's" { ok HardGates.test_h8_env_and_argv_of_an_overdue_record_equal_a_fresh_ones; }
@test "H9 the hard stop trips on positive evidence; thermal 2 does not" { ok HardGates.test_h9_positive_evidence_trips_and_thermal_two_does_not; }
@test "H10 unknown is not a stop and says unknown" { ok HardGates.test_h10_unknown_is_not_a_stop_and_says_unknown; }
@test "H10b torn, blank, string and stale sentinel rows never raise" { ok HardGates.test_h10b_torn_blank_string_and_stale_rows_never_raise; }
@test "H11 a trip releases after two clear reads 30 s apart" { ok HardGates.test_h11_release_needs_two_clear_reads_30s_apart; }
@test "H11b tripped then unknown releases at 300 s" { ok HardGates.test_h11b_tripped_then_unknown_releases_at_300s; }
@test "W1 [RED] an overdue wake skips the pacer" { ok Wakes.test_w1_an_overdue_wake_skips_the_pacer; }
@test "W2 CONTROL a wake inside its window waits on the pacer" { ok Wakes.test_w2_control_inside_its_window_it_waits_on_the_pacer; }
@test "C1 [RED] a sleep shifts the deadline" { ok Durable.test_c1_a_sleep_shifts_the_deadline; }
@test "C2 [RED] a restart keeps the deadline" { ok Durable.test_c2_a_restart_keeps_the_deadline; }
@test "C3 set once, kept across a hop; the wake clock; idle has none" { ok Durable.test_c3_set_once_kept_across_a_hop_and_lanes; }
@test "P1 [RED] one DEADLINE page, then hourly" { ok Pages.test_p1_one_deadline_page_then_hourly; }
@test "P1b twenty members crossing W_hard: one page" { ok Pages.test_p1b_a_cohort_pages_once_for_twenty_members; }
@test "P2 CONTROL a cycling hold pages MAX-AGE only" { ok Pages.test_p2_control_a_cycling_hold_pages_max_age_only; }
@test "P3 [RED] a drip opening pages once per cohort" { ok Pages.test_p3_a_drip_opening_pages_once_per_cohort; }
@test "BACKOFF_PAGE, T_att and hard-stop pages are wired, once each" {
  ok Pages.test_backoff_page_is_wired
  ok Pages.test_an_actuator_past_t_att_pages_once_and_is_not_killed
  ok Pages.test_hard_stop_trip_past_w_hard_pages_once
}
@test "S1 CONTROL deadline.off is today's gates" { ok Switches.test_s1_control_deadline_off_is_todays_gates; }
@test "S2 deadline.shadow logs would-admit only" { ok Switches.test_s2_shadow_logs_would_admit_only; }
@test "the slot-priority lease is written while an overdue move waits and removed after" { ok SlotPriority; }
@test "unknown-exit resolution" { ok UnknownExit; }
@test "every new rule's mutant dies" { ok MutantsDie; }
