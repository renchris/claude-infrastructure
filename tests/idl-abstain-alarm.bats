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

@test "selftest is green and runs all 25 checks (a zero-check suite must not 'pass')" {
  run "$S" --selftest
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | grep -c '^  ok ')" -eq 25 ]
  ! printf '%s' "$output" | grep -q '^  FAIL'
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
