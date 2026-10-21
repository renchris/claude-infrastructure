#!/usr/bin/env bats
# lr-recon-now-audit.bats — wave W8 of docs/plans/LR_SUSTAINED_LOAD_IMPL.md: the right clock per
# decision (B7), retry instead of escalate (C2-lite), no actuator load term (G1), every hold reason
# mapped (G5). Designs: docs/research/lr-sustained-load-2026-10-20/impl/B7-now-audit.md and
# impl/C2-socket-prompt.md (efficacy review E2, E5).
#
# The controls are lr_recon/tests/test_now_audit.py; this wrapper runs them under /usr/bin/python3
# (3.9.6, the plist's interpreter) with the COUNT asserted ("Gate refusal ≠ gate result"), runs the
# suites W8 edited, and kills one mutant per new rule: each @test copies lr_recon (and the two hold
# emitters the enumeration test greps) into BATS_TEST_TMPDIR, makes ONE source replacement that must
# match exactly once, and requires the named control to FAIL there. An unmutated copy is green first,
# so a red mutant is the mutation's doing.
#
# HERMETIC: HOME, LR_STATE_DIR, LR_RECON_ROOT and TMPDIR live in BATS_TEST_TMPDIR. Nothing reads
# the live box, types anywhere, signals anything or loads a job.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home" TMPDIR="$BATS_TEST_TMPDIR/tmp"
  export LR_STATE_DIR="$BATS_TEST_TMPDIR/lr" LR_RECON_ROOT="$BATS_TEST_TMPDIR/lr/recon"
  export PYTHONDONTWRITEBYTECODE=1
  # nothing here runs handoff-fire (the copy is only grepped for its HELD literals); pinned anyway,
  # so no fire or accounts sensor could ever read the live box or its /tmp state
  export CC_FIRE_CAPACITY_GATE=off
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/handoff-account-sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/claude-accounts-heal-"
  mkdir -p "$HOME" "$TMPDIR" "$LR_RECON_ROOT"
  M="$BATS_TEST_TMPDIR/m"
}

ut() { # <tree> <unittest args…>: the suite as the plist runs it
  local tree="$1"
  shift
  (cd "$tree/scripts/limit-recover" && /usr/bin/python3 -m unittest "$@" 2>&1)
}

ran() { printf '%s\n' "$1" | sed -n 's/^Ran \([0-9][0-9]*\) tests* in .*/\1/p'; }

copy_tree() {
  mkdir -p "$M/scripts/limit-recover"
  cp -R "$REPO/scripts/limit-recover/lr_recon" "$M/scripts/limit-recover/lr_recon"
  cp "$REPO/scripts/limit-recover/lr_predicate.py" "$M/scripts/limit-recover/lr_predicate.py"
  mkdir -p "$M/tests/fixtures/lr-recon"
  cp -R "$REPO/tests/fixtures/lr-recon/jsonl" "$M/tests/fixtures/lr-recon/jsonl"
  cp "$REPO/scripts/handoff-fire.sh" "$M/scripts/handoff-fire.sh"
  cp "$REPO/scripts/limit-recover/lr-handoff.sh" "$M/scripts/limit-recover/lr-handoff.sh"
}

mutate() { # <module under lr_recon/> <old> <new>: exactly one occurrence, or the mutant is void
  /usr/bin/python3 -I -c '
import sys
p, old, new = sys.argv[1:4]
s = open(p, encoding="utf-8").read()
n = s.count(old)
if n != 1:
    sys.exit("mutant void: %d matches of %r in %s" % (n, old, p))
open(p, "w", encoding="utf-8").write(s.replace(old, new))
' "$M/scripts/limit-recover/lr_recon/$1" "$2" "$3"
}

# kills <module> <old> <new> <TestClass.test_name>: the mutant turns that control red
kills() {
  copy_tree
  mutate "$1" "$2" "$3"
  run ut "$M" "lr_recon.tests.test_now_audit.$4"
  [ "$(ran "$output")" = 1 ] || { printf '%s\n' "$output"; false; }
  [ "$status" -ne 0 ] || { printf 'mutant SURVIVED: %s\n%s\n' "$4" "$output"; false; }
  # a kill is the control's own failure, never the copy failing to import (a vacuous red)
  if printf '%s\n' "$output" | grep -qE '_FailedTest|ImportError|ModuleNotFoundError|SyntaxError'; then
    printf 'mutant VOID (the copy did not load): %s\n%s\n' "$4" "$output"
    false
  fi
  printf '%s\n' "$output" | grep -qE '^FAILED \((failures|errors)='
}

@test "the W8 controls pass under /usr/bin/python3 (3.9), count asserted" {
  /usr/bin/python3 -c 'import sys; assert sys.version_info[:2] == (3, 9), sys.version'
  run ut "$REPO" lr_recon.tests.test_now_audit
  [ "$status" -eq 0 ] || { printf '%s\n' "$output"; false; }
  [ "$(ran "$output")" -ge 41 ]
  printf '%s\n' "$output" | grep -qx 'OK'
}

@test "the suites W8 edited stay green, count asserted" {
  run ut "$REPO" lr_recon.tests.test_classify lr_recon.tests.test_report lr_recon.tests.test_main \
    lr_recon.tests.test_rollback lr_recon.tests.test_clock lr_recon.tests.test_unprompted_c \
    lr_recon.tests.test_holder_gone lr_recon.tests.test_admit lr_recon.tests.test_settle \
    lr_recon.tests.test_act lr_recon.tests.test_guarantee_sim
  [ "$status" -eq 0 ] || { printf '%s\n' "$output"; false; }
  [ "$(ran "$output")" -ge 300 ]
  printf '%s\n' "$output" | grep -qx 'OK'
}

@test "CONTROL: the unmutated copy is green, so each red below is its mutation's" {
  copy_tree
  run ut "$M" lr_recon.tests.test_now_audit
  [ "$status" -eq 0 ] || { printf '%s\n' "$output"; false; }
  [ "$(ran "$output")" -ge 41 ]
}

# ── B7 ──────────────────────────────────────────────────────────────────────────────────────────
@test "mutant: C's grace on t_dec, not the census instant (M1's opposite), dies" {
  kills __main__.py 'settle.quiet_for(rec, "typer", now) < C_GRACE_S' \
    'settle.quiet_for(rec, "typer", t_dec) < C_GRACE_S' \
    CGraceIsAnEvidenceWait.test_C_waits_60s_after_the_first_census_that_did_not_see_the_typer
}

@test "mutant: the same, against the hazard control, dies" {
  kills __main__.py 'settle.quiet_for(rec, "typer", now) < C_GRACE_S' \
    'settle.quiet_for(rec, "typer", t_dec) < C_GRACE_S' CGraceIsAnEvidenceWait.test_b7_review_hazard
}

@test "mutant: the quiet anchor reverts to the last-seen census (M2), dies" {
  kills settle.py 'rec.close[quiet] = now if first_unseen else float(rec.close.get(at) or 0.0)' \
    'rec.close[quiet] = float(rec.close.get(at) or 0.0)' \
    CGraceIsAnEvidenceWait.test_C_waits_60s_after_the_first_census_that_did_not_see_the_typer
}

@test "mutant: submitted read from the previous pass again (correctness 2), dies" {
  kills evidence.py 'ev.submitted = True' 'pass' \
    SubmittedIsReadAfterThisCensus.test_token_visible_at_census_plus_70_sends_no_C
}

@test "mutant: the activity stamp skipped (read before stamp, correctness 4), dies" {
  kills __main__.py '_note_activity(ctx, rec, snap, now)' 'pass' \
    HolderGoneSeesThisCensus.test_a_launcher_booting_the_sid_in_this_census_keeps_the_record_open
}

@test "mutant: every relay of the sid is busy again (efficacy 2), dies" {
  kills settle.py 'if t is None or t > float(start):' 'if True:' \
    RollbackUnderARelay.test_relay_strand_at_120s_and_10s_pass_gaps
}

@test "mutant: a relay started after the move no longer counts, dies" {
  kills settle.py 'if t is None or t > float(start):' 'if t is None:' \
    RollbackUnderARelay.test_a_launcher_started_after_the_move_holds_the_rollback_retry
}

@test "mutant: this attempt's open launcher no longer counts, dies" {
  kills settle.py 'return _attempt_launcher_open(home, rec, now)' 'return False' \
    RollbackUnderARelay.test_an_open_launcher_of_this_attempt_counts_whatever_its_start
}

@test "mutant: IN-FLIGHT expires while the watcher lives (efficacy 3), dies" {
  kills __main__.py 'and settle.quiet_for(rec, "typer", now) >= 0' 'and True' \
    InFlightAnchor.test_a_watcher_live_for_1195s_is_never_deterministic
}

@test "mutant: _invariant ages IN-FLIGHT from updated_at again (D4), dies" {
  kills __main__.py 'r.close.get("in_flight_at")' 'r.updated_at' \
    InFlightAnchor.test_in_flight_without_a_confirm_stamp_is_paged
}

@test "mutant: the pacer back on the pass now (D3), dies" {
  kills admit.py 'return max(now, self.wall()) if self.pacer_on_wall else now' 'return now' \
    PacerOnWall.test_the_3_per_account_cap_frees_inside_one_long_pass
}

@test "mutant: the pacer slot stamped before the probe (efficacy 6), dies" {
  kills admit.py 'self.pacer_take(sid, acct, t_dec)' 'self.pacer_take(sid, acct, now)' \
    PacerOnWall.test_the_slot_is_stamped_after_the_probe
}

@test "mutant: spawns stamped at the pass start (D2), dies" {
  kills act.py 't = max(now, time.time())' 't = now' \
    LongPassStamps.test_a_whole_long_pass_stamps_its_spawn_at_the_spawn
}

@test "mutant: the report fallback anchored on updated_at (D4b), dies" {
  kills report.py 'return rec.timeline.detected or rec.updated_at' 'return rec.updated_at' \
    ReportAnchors.test_a_hold_with_no_wait_ages_from_detection_not_updated_at
}

# ── C2-lite ─────────────────────────────────────────────────────────────────────────────────────
@test "mutant: cc-tui's could-not-tell lines DETERMINISTIC again (E2), dies" {
  kills classify.py 'if not SWITCHES["c_rc5_transient"]:' 'if True:' \
    CRpcUncertaintyIsTransient.test_a_C_rc5_line_is_transient_and_never_reaches_impossible
}

@test "mutant: the double-prompt guard removed, dies" {
  kills __main__.py 'if _c_rc5_landed(ctx, rec, which, t_dec):' 'if False:' \
    CRpcUncertaintyIsTransient.test_rc5_with_the_token_landing_during_the_backoff_skips_the_retry
}

@test "mutant: no UNPROMPTED max age (E5), dies" {
  kills types.py '"UNPROMPTED": 1800,' '' UnpromptedPages.test_the_unprompted_page_at_1800s
}

@test "mutant: unprompted_since never stamped, dies" {
  kills __main__.py 'rec.close.setdefault("unprompted_since", now)' 'pass' \
    UnpromptedPages.test_derive_stamps_it_once_and_clears_it_on_the_way_out
}

@test "mutant: no kitty-degraded event (E5 T4), dies" {
  kills __main__.py 'if key is not None and key != _own(ctx, "kitty_degraded", None):' 'if False:' \
    KittyDegradedEvent.test_one_event_per_outage_while_a_continue_is_owed
}

# ── G1 / G5 ─────────────────────────────────────────────────────────────────────────────────────
@test "mutant: actuators inherit the library's load term again (G1), dies" {
  kills act.py '"CC_ADMIT_LOAD_TERM": "off",' '' \
    ActuatorEnvLoadTermOff.test_actuator_env_sets_the_load_term_off_for_every_actuator_letter
}

@test "mutant: the hold map bypassed (G5), dies" {
  kills classify.py 'if SWITCHES["hold_map"]:' 'if False:' \
    EveryHoldReasonIsMapped.test_every_HELD_literal_maps_to_a_non_deterministic_class
}

@test "mutant: HELD:load falls to DETERMINISTIC again, dies" {
  kills classify.py '"load": ("HOLD", "HOLD-LOAD"),' '' \
    EveryHoldReasonIsMapped.test_map_notmoved_load_is_hold_load
}

@test "mutant: lr-handoff's wake-guard line no longer reaches the map, dies" {
  kills settle.py '|lr-handoff: (?=HELD:wake-guard\b)' '' \
    EveryHoldReasonIsMapped.test_each_emitted_line_reaches_its_row
}
