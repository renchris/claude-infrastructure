#!/usr/bin/env bats
# Tier G (B1 load harness §9.11): the reconciler's real run_pass on a virtual clock, no real child.
# Load invariance, the first-spawn and retry bounds, our timeout never a verdict, restart neutrality,
# and one dying mutant per rule (lr_recon/tests/test_guarantee_sim.py). ONE python process (F18):
# setup_file runs the module once; each case reads its own line from that run.

setup_file() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd -P)"
  export HOME="$BATS_FILE_TMPDIR/home" TMPDIR="$BATS_FILE_TMPDIR/tmp"
  export LR_STATE_DIR="$BATS_FILE_TMPDIR/lr" LR_RECON_ROOT="$BATS_FILE_TMPDIR/lr/recon"
  mkdir -p "$HOME" "$TMPDIR"
  (cd "$REPO/scripts/limit-recover" && /usr/bin/python3 -m unittest -v lr_recon.tests.test_guarantee_sim > "$BATS_FILE_TMPDIR/out" 2>&1) || true
}

setup() {
  export HOME="$BATS_TEST_TMPDIR/home" TMPDIR="$BATS_TEST_TMPDIR"
  export LR_STATE_DIR="$BATS_TEST_TMPDIR/lr" LR_RECON_ROOT="$BATS_TEST_TMPDIR/lr/recon"
}

has() {
  grep -Eq "$1" "$BATS_FILE_TMPDIR/out" || { cat "$BATS_FILE_TMPDIR/out"; false; }
}
ok() {
  has "^$1 \(lr_recon\.tests\.test_guarantee_sim\.$2\) \.\.\. ${3:-ok}$"
}

@test "F2 no lr_recon default holds os.getloadavg outside the allow set" {
  ok test_f2_no_load_default_outside_the_allow_set GuaranteeSim
}

@test "F3 the simulated pass starts no real child" {
  ok test_f3_no_real_child GuaranteeSim
}

@test "S1 the decision trace is identical at load1 5..1000 on 10 cpus" {
  ok test_s1_load_invariance GuaranteeSim
}

@test "S2 first spawn within 2P + ceil(k_r/6) T_att, boots.limit 6 every pass" {
  ok test_s2_first_spawn_bound GuaranteeSim
}

@test "S2b over the restore budget, each member comes in through the drip in bound" {
  ok test_s2b_restore_budget_drip_bound GuaranteeSim
}

@test "S3 retries back off 10..240 then 300, never more" {
  ok test_s3_retry_bound GuaranteeSim
}

@test "S4 our own timeout is never a verdict" {
  ok test_s4_our_timeout_is_not_a_verdict GuaranteeSim
}

@test "S5a a restart keeps t_detect and starts no second spawn" {
  ok test_s5a_restart_neutrality GuaranteeSim
}

@test "S5b (owner W2) the claim stays with the live actuator: expected failure" {
  ok test_s5b_claim_stays_with_the_live_actuator GuaranteeSim "expected failure"
}

@test "every named mutant turns its checker red" {
  for t in f2_planted_load_default f3_composer_read_reaches_kitty s1_pace_requires_load_below_20_per_core \
    s1_pace_requires_load_below_2_per_core s2_aimd_wired_to_slow_boots s2_one_boot_slot s2b_drip_100x_slower \
    s3_backoff_cap_900 s4_place_timeout_is_a_verdict s5a_restart_forgets_the_live_actuator; do
    ok "test_$t" MutantsDie
  done
}

@test "the module run ends OK" {
  has '^OK( \(expected failures=1\))?$'
}
