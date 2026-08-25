#!/usr/bin/env bats
# idl-abstain-alarm (T-P6-4 / "abstain-alarm D9") — the IDL abstention monitor. The script's own
# --selftest RED-proves the blind-vs-dormant discriminator internally; these bats add INDEPENDENT
# CLI-level coverage via CC_IDL fixtures and lock the load-bearing contract: a 100%-DORMANT hook
# must NOT page (the boundary-handoff:41-49 false-positive), only a 100%-BLIND hook does.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  S="$REPO/scripts/idl-abstain-alarm.sh"
  IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  LOG="$BATS_TEST_TMPDIR/abstain.log"
  NOW=1752900000
  TS="$(date -u -r "$NOW" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo 2026-07-19T04:00:00Z)"
}

emit() { # <n> <hook> <disposition> <reason>
  local i
  for ((i = 0; i < $1; i++)); do
    printf '{"ts":"%s","hook":"%s","sid":"s%d","disposition":"%s","reason":"%s"}\n' \
      "$TS" "$2" "$i" "$3" "$4" >> "$IDL"
  done
}
alarm() { env CC_IDL="$IDL" CC_ABSTAIN_NOW="$NOW" CC_ABSTAIN_LOG="$LOG" CC_ABSTAIN_NMIN=10 "$S" "${1:---run}"; }

# FLOOR + TALLY, never `-eq N` (2026-08-08). This asserted `-eq 25` and went RED the moment the
# selftest GREW by 4 checks (cases M/N, the non-evaluation-denominator fix) — an exact-count
# assertion over a growing subject can only ever catch its own growth, never a regression: the
# vacuous-suite risk it exists for is "checks went to ZERO", which a FLOOR states directly. The
# tally half keeps it honest — every `ok` is accounted for and no `FAIL` is present, so a suite
# that silently stopped running checks still reds. memory: exact-count-assertion-tripwires-its-own-subject
@test "selftest is green and runs its full check set (a zero-check suite must not 'pass')" {
  run "$S" --selftest
  [ "$status" -eq 0 ]
  # FLOOR RAISED 25 → 44 (2026-08-09), the measured count on this tree (44 okp/badp sites, 44
  # rendered). The floor+tally shape above is right and is left alone; only the NUMBER was stale.
  # A floor is only as strong as its slack: left at 25 while the suite grew to 44, it could not have
  # caught NINETEEN deleted checks — and catching a deletion is the entire downward half of the
  # ratchet (memory: downward-ratchet-catches-the-over-scoped-marker). Raise it when checks are
  # added; lowering it must stay a deliberate edit.
  local n_ok; n_ok="$(printf '%s' "$output" | grep -c '^  ok ')"
  [ "$n_ok" -ge 44 ]
  ! printf '%s' "$output" | grep -q '^  FAIL' || false
  printf '%s' "$output" | grep -q "selftest: ${n_ok} passed, 0 failed"
}

@test "100%-BLIND hook over N>=10 → RED (exit 1) naming the inert hook" {
  emit 12 dead-hook abstained no-telemetry
  run alarm
  [ "$status" -ne 0 ]
  printf '%s' "$output" | grep -q 'dead-hook'
  printf '%s' "$output" | grep -q 'INERT'
}

@test "100%-DORMANT hook → GREEN, reported DORMANT-100, NOT paged (the boundary-handoff false-positive guard)" {
  emit 20 dormant-hook abstained below-threshold
  run alarm
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'DORMANT-100'
  ! printf '%s' "$output" | grep -q 'INERT'
}

@test "mixed — a single DORMANT among BLINDs proves observability → suppressed" {
  emit 11 mixed-hook abstained no-telemetry
  emit 1  mixed-hook abstained below-threshold
  run alarm
  [ "$status" -eq 0 ]
  ! printf '%s' "$output" | grep -q 'INERT'
}

@test "sub-threshold — fewer than N_MIN blind evals → GREEN (insufficient evidence)" {
  emit 5 rare-hook abstained not-a-repo
  run alarm
  [ "$status" -eq 0 ]
  ! printf '%s' "$output" | grep -q 'INERT'
}

@test "a hook that has ever FIRED is never inert" {
  emit 4 live-hook fired ok
  emit 9 live-hook abstained no-telemetry
  run alarm
  [ "$status" -eq 0 ]
  ! printf '%s' "$output" | grep -q 'INERT'
}

@test "non-abstention-schema IDL lines (supervisor/checkpoint) are ignored" {
  local i
  for ((i = 0; i < 15; i++)); do
    printf '{"ts":"%s","actor":"lead-supervisor","kind":"checkpoint","sid":"s%d"}\n' "$TS" "$i" >> "$IDL"
  done
  run alarm
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'hooks=0'
}

@test "--report NEVER fails, even with an inert hook, but still shows it" {
  emit 12 dead-hook abstained no-transcript-path
  run alarm --report
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'dead-hook'
  printf '%s' "$output" | grep -q 'INERT'
}

@test "one summary line is appended to CC_ABSTAIN_LOG" {
  emit 12 dormant-hook abstained not-armed
  alarm >/dev/null
  [ -f "$LOG" ]
  grep -q 'idl-abstain-alarm:' "$LOG"
  grep -q 'dormant-hook' "$LOG"
}

@test "CC_ABSTAIN_BLIND_REASONS override reclassifies a reason as blind → RED" {
  emit 12 custom-hook abstained gizmo-absent
  run env CC_IDL="$IDL" CC_ABSTAIN_NOW="$NOW" CC_ABSTAIN_LOG="$LOG" CC_ABSTAIN_NMIN=10 \
        CC_ABSTAIN_BLIND_REASONS="gizmo-absent" "$S" --run
  [ "$status" -ne 0 ]
  printf '%s' "$output" | grep -q 'custom-hook'
}

@test "missing IDL → GREEN (no data, nothing to conclude)" {
  run env CC_IDL="$BATS_TEST_TMPDIR/nope.jsonl" CC_ABSTAIN_NOW="$NOW" CC_ABSTAIN_LOG="$LOG" "$S" --run
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'no IDL'
}

# ══ the cc-backlog reap enrollment (backlog 420b9cb2166c) ═══════════════════════════════════════
# reap's UNRESOLVED keeps are the "could not observe my guard" class §3i pages on, but its journal
# rows are {actor, action}-shaped, so the {hook, disposition} selector never saw them. The alarm now
# PROJECTS them (see the script header for why at the reader, not the writer). Two things need
# independent proof here: that the projection is real in BOTH polarities, and that it is calibrated
# against the vocabulary the LIVE producer actually emits.

emit_reap() { # <n> <verdict> <reason> <acted> — the actor-shaped row, as bin/cc-backlog writes it
  local i
  for ((i = 0; i < $1; i++)); do
    printf '{"ts":"%s","actor":"cc-backlog-reap","action":"verdict","id":"i%d","verdict":"%s","reason":"%s","acted":%s,"claim_by":"h-1","claim_age_s":9000,"attempts":1,"fast_fail":0,"claimer_rc":2,"worktree":null,"detail":"d"}\n' \
      "$TS" "$i" "$2" "$3" "$4" >> "$IDL"
  done
}

@test "reap: 100% UNRESOLVED keeps → INERT, paged under the hook name cc-backlog-reap" {
  emit_reap 12 keep claimer-unresolved false
  run alarm
  [ "$status" -ne 0 ]
  printf '%s' "$output" | grep -q 'cc-backlog-reap'
  printf '%s' "$output" | grep -q 'INERT'
}

@test "reap: 100% ANSWERED keeps (owned-wait) → DORMANT-100, never paged" {
  emit_reap 12 keep owned-wait false
  run alarm
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'DORMANT-100'
  ! printf '%s' "$output" | grep -q 'INERT'
}

@test "reap: one ANSWERED keep among blind ones proves observability → suppressed" {
  emit_reap 11 keep claimer-unresolved false
  emit_reap 1  keep claimer-live false
  run alarm
  [ "$status" -eq 0 ]
  ! printf '%s' "$output" | grep -q 'INERT'
}

@test "reap: a BLOCK is the check acting → productive, breaks abstained==total (the documented seam)" {
  # A starvation that reaches CC_BACKLOG_UNRESOLVED_MAX_S escalates to `block …-unresolvable-…`,
  # which parks the item in front of a human. That half announces itself, so it must NOT also page
  # here — this alarm is the backstop for the blindness nobody else announces.
  emit_reap 11 keep claimer-unresolved false
  emit_reap 1  block unresolvable-claimer true
  run alarm
  [ "$status" -eq 0 ]
  ! printf '%s' "$output" | grep -q 'INERT'
}

@test "reap: a REFUSED transition (acted:false) counts as failed, not as an abstention" {
  # The ledger refusing a reopen is a failure of the ACTION; reap still reached its guard. Folding it
  # into `abstained` would let a run of refused reopens read as 100%-blind and manufacture a page.
  emit_reap 11 keep claimer-unresolved false
  emit_reap 1  reopen dead-worker false
  run alarm
  [ "$status" -eq 0 ]
  ! printf '%s' "$output" | grep -q 'INERT'
}

# ── REAL-PRODUCER PARITY ───────────────────────────────────────────────────────────────────────
# The five cases above are hand-typed rows, and a hand-typed approximation passes VACUOUSLY if the
# producer's real shape has drifted (memory: control-must-replay-the-real-artifact). These two drive
# `bin/cc-backlog reap` itself and feed the alarm ITS OWN journal — one per polarity, because a
# parity test that only proves "a reap row pages" would still pass if the projection paged on
# everything.
reap_producer() { # <n-items> <mode: unresolved|owned> → writes $IDL via the real reap
  local n="$1" mode="$2" i
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_BACKLOG_IDL="$IDL"
  export CC_BACKLOG_WT_ROOT="$BATS_TEST_TMPDIR/wtroot"; mkdir -p "$CC_BACKLOG_WT_ROOT"
  export CC_BACKLOG_NOW; CC_BACKLOG_NOW="$(jq -n '"2026-01-01T02:00:00Z"|fromdateiso8601')"
  # EMPTY registry output — not `[]`. `[]` is the registry ANSWERING "not listed" (rc 1, a real
  # not-live verdict); no output at all is rc 2, the UNRESOLVED non-verdict this enrollment is about.
  printf '#!/bin/bash\nexit 0\n' > "$BATS_TEST_TMPDIR/emptysess"; chmod +x "$BATS_TEST_TMPDIR/emptysess"
  export CC_BACKLOG_SESSIONS_BIN="$BATS_TEST_TMPDIR/emptysess"
  # The occupancy probe is asked ONCE PER ITEM and answers about the whole machine, so `owned` mode
  # needs a cwd line for EVERY worktree — naming only the last one leaves the other n-1 items with an
  # empty `owned` and lands them on claimer-unresolved instead, i.e. the wrong polarity under the
  # right-looking name. The precondition in each test is what makes that visible rather than silent.
  local out="$BATS_TEST_TMPDIR/lsof-out"; : > "$out"
  for ((i = 0; i < n; i++)); do
    local id; id="$(printf 'reapreal%04d' "$i")"
    if [ "$mode" = owned ]; then
      mkdir -p "$CC_BACKLOG_WT_ROOT/wt-$id"
      printf 'p%d\nn%s\n' "$((i + 1))" "$CC_BACKLOG_WT_ROOT/wt-$id" >> "$out"
    fi
    printf '{"id":"%s","ts":"2026-01-01T00:00:00Z","event":"add","project":"/r","title":"R"}\n' "$id" >> "$CC_BACKLOG_FILE"
    # A SESSION-SHAPED claimer: a `<host>-<pid>` one is settled by `kill -0` and never reaches the
    # registry, so it can never produce the rc-2 non-verdict.
    printf '{"id":"%s","ts":"2026-01-01T00:00:00Z","event":"claim","by":"6c135981-cacf-4527-acd2-%012d"}\n' "$id" "$i" >> "$CC_BACKLOG_FILE"
  done
  # `unresolved` mode: the probe RAN and found nobody — a real answer, outside every worktree. That
  # is what keeps the claimer-unresolved branch (one oracle silent) reachable at all.
  [ "$mode" = owned ] || printf 'p1\nn/\n' > "$out"
  # Hermetic, load-immune occupancy probe emitting the producer's own `-F pn` stream.
  printf '#!/bin/bash\ncat %s\n' "$out" > "$BATS_TEST_TMPDIR/stublsof"
  chmod +x "$BATS_TEST_TMPDIR/stublsof"
  export CC_BACKLOG_LSOF_BIN="$BATS_TEST_TMPDIR/stublsof"
  bash "$REPO/bin/cc-backlog" reap >/dev/null
}

@test "reap PARITY: rows written by the real cc-backlog reap are seen, and blind ones page" {
  reap_producer 12 unresolved
  # The producer really did emit the blind token — if this drifts, the case below would go vacuous.
  [ "$(jq -s '[.[]|select(.reason=="claimer-unresolved")]|length' "$IDL")" -eq 12 ]
  # No CC_ABSTAIN_NOW: reap stamps rows with the REAL clock, so the window must be the real one too.
  run env CC_IDL="$IDL" CC_ABSTAIN_LOG="$LOG" CC_ABSTAIN_NMIN=10 "$S" --run
  [ "$status" -ne 0 ]
  printf '%s' "$output" | grep -q 'cc-backlog-reap'
  printf '%s' "$output" | grep -q 'INERT'
}

@test "reap PARITY: real ANSWERED keeps stay quiet — the projection is not paging on any reap row" {
  reap_producer 12 owned
  [ "$(jq -s '[.[]|select(.reason=="owned-wait")]|length' "$IDL")" -eq 12 ]
  run env CC_IDL="$IDL" CC_ABSTAIN_LOG="$LOG" CC_ABSTAIN_NMIN=10 "$S" --run
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'DORMANT-100'
  ! printf '%s' "$output" | grep -q 'INERT'
}

# ── --vocab-lint: the completeness guard for the calibration ────────────────────────────────────
# "Unclassified ⇒ DORMANT" is the right global bias and a FAIL-OPEN for this enrollment: a future
# blind keep-reason would be classified quiet, with a green suite. The lint pins the classification
# to the producer's real vocabulary in both directions.

@test "vocab-lint: the classification matches the live bin/cc-backlog keep-vocabulary" {
  run "$S" --vocab-lint
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'GREEN'
}

@test "vocab-lint MUTANT: a keep reason neither array classifies → RED, naming it" {
  local m="$BATS_TEST_TMPDIR/mutant-new"
  { printf 'idl_verdict "$id" keep claimer-live false "$by"\n'
    printf 'idl_verdict "$id" keep owned-wait false "$by"\n'
    printf 'idl_verdict "$id" keep claimer-unresolved false "$by"\n'
    printf 'idl_verdict "$id" keep worktree-unresolved false "$by"\n'
    printf 'idl_verdict "$id" keep registry-half-answered false "$by"\n'; } > "$m"
  run "$S" --vocab-lint "$m"
  [ "$status" -ne 0 ]
  printf '%s' "$output" | grep -q 'registry-half-answered'
}

@test "vocab-lint MUTANT: a classified token the producer no longer emits → RED (the downward half)" {
  # A rename drops the old spelling and adds a new one. Catching only the ADD direction would leave
  # the stale classification in place and the new spelling silently DORMANT.
  local m="$BATS_TEST_TMPDIR/mutant-renamed"
  { printf 'idl_verdict "$id" keep claimer-live false "$by"\n'
    printf 'idl_verdict "$id" keep owned-wait false "$by"\n'
    printf 'idl_verdict "$id" keep claimer-unresolved false "$by"\n'; } > "$m"
  run "$S" --vocab-lint "$m"
  [ "$status" -ne 0 ]
  printf '%s' "$output" | grep -q 'worktree-unresolved'
}

@test "vocab-lint: zero matched call sites is RED, not a vacuous all-clear" {
  # The extractor going blind must never read as the subject coming up clean — with no keep sites to
  # classify, every assertion above would pass over nothing.
  : > "$BATS_TEST_TMPDIR/no-sites"
  run "$S" --vocab-lint "$BATS_TEST_TMPDIR/no-sites"
  [ "$status" -ne 0 ]
  printf '%s' "$output" | grep -q '0 .*keep'
}

@test "vocab-lint: a keep reason passed as a VARIABLE is RED — it cannot be classified from source" {
  local m="$BATS_TEST_TMPDIR/mutant-var"
  { printf 'idl_verdict "$id" keep claimer-live false "$by"\n'
    printf 'idl_verdict "$id" keep owned-wait false "$by"\n'
    printf 'idl_verdict "$id" keep claimer-unresolved false "$by"\n'
    printf 'idl_verdict "$id" keep worktree-unresolved false "$by"\n'
    printf 'idl_verdict "$id" keep "$ktoken" false "$by"\n'; } > "$m"
  run "$S" --vocab-lint "$m"
  [ "$status" -ne 0 ]
  printf '%s' "$output" | grep -q 'not a literal token'
}

# ── MALFORMED-LINE ACCOUNTING ───────────────────────────────────────────────────────────────
# The script's own selftest arm H is named "a malformed line does not crash the sweep" and its
# fixture is a MIXED file — valid rows alongside broken ones. That is the ONE regime in which the
# accounting worked, so arm H stayed green while the accounting was wrong in two opposite ways:
#
#   partial corruption → `parsed` counted jq's PRETTY-PRINTED output LINES rather than records,
#                        so `raw - parsed` went negative and the clamp rewrote it to 0. Silent.
#   total corruption   → `grep -c` exits 1 on its own legitimate zero, so `|| echo 0` appended a
#                        second zero and the arithmetic died, taking the whole sweep with it.
#
# These four cases pin both regimes plus the control. memory: control-fixture-must-reach-the-bugs-regime
badline() { printf '%s\n' "$1" >> "$IDL"; }

@test "malformed accounting: a PARTIALLY corrupt IDL reports the EXACT malformed count" {
  # Pre-fix this printed no malformed= at all: parsed(12) exceeded raw(4), the difference went
  # negative, and the clamp turned the silent-drop this block forbids into a permanent zero.
  emit 2 partial-hook passed ok
  badline 'THIS IS NOT JSON AT ALL'
  badline '{broken json'
  run alarm --report
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'malformed=2'
}

@test "malformed accounting: an IDL where EVERY line is unparseable does not crash the sweep" {
  # The regime arm H is named after and never reaches. Pre-fix: bash died at the `$(( ))` with
  # "syntax error in expression", stdout was EMPTY and the exit was 1 — and 1 is ALSO this
  # alarm's genuine "RED — inert check(s)" verdict, so a caller could not tell a crash from a page.
  badline 'NOT JSON ONE'
  badline 'NOT JSON TWO'
  badline '{still broken'
  run alarm --report
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  printf '%s' "$output" | grep -q 'malformed=3'
  [ "$(printf '%s' "$output" | grep -c 'syntax error')" -eq 0 ]
}

@test "malformed accounting: a whitespace-only IDL is non-empty but counts zero, without crashing" {
  # `[ ! -s "$IDL" ]` lets this through as non-empty, but it holds zero NON-BLANK lines, so `raw`
  # took the same grep -c exit-1 path that killed the parsed side.
  printf '   \n\t\n   \n' > "$IDL"
  run alarm --report
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | grep -c 'syntax error')" -eq 0 ]
  [ "$(printf '%s' "$output" | grep -c 'malformed=')" -eq 0 ]
}

@test "malformed accounting CONTROL: a fully valid IDL reports NO malformed count" {
  # Without this the three assertions above are satisfiable by a sweep that reports a malformed
  # count unconditionally. This is the arm that must go RED if the counter ever becomes a constant.
  emit 3 clean-hook passed ok
  run alarm --report
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | grep -c 'malformed=')" -eq 0 ]
}
