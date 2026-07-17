#!/usr/bin/env bats
# kimi-frontend-ab.sh — the burn-in A/B harness. Its `selftest` RED-proves the scaffold/fairness/
# key-guard invariants; these bats add CLI-level regression on the command surface.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  T="$REPO/scripts/kimi-frontend-ab.sh"
  export KIMI_BURNIN_DIR="$BATS_TEST_TMPDIR/burnin"
}

@test "selftest passes and runs all 9 RED-proof checks (a zero-check suite must not 'pass')" {
  run "$T" selftest
  [ "$status" -eq 0 ]
  n_ok="$(printf '%s' "$output" | grep -c '^  ok ')"
  [ "$n_ok" -eq 9 ]
  ! printf '%s' "$output" | grep -q '^  NOT ok '
}

@test "new (default) scaffolds a run dir on stdout with both arms, brief, scorecard, run notes" {
  run "$T" new
  [ "$status" -eq 0 ]
  run_dir="$(printf '%s\n' "$output" | head -1)"
  [ -d "$run_dir/A-fable" ]
  [ -d "$run_dir/B-kimi" ]
  [ -f "$run_dir/brief.md" ]
  [ -f "$run_dir/SCORECARD.md" ]
  [ -f "$run_dir/RUN.md" ]
}

@test "the default brief targets a design-taste frontend task (the gap being tested)" {
  run_dir="$("$T" new 2>/dev/null | head -1)"
  grep -qi 'pricing' "$run_dir/brief.md"
  grep -qi 'self-contained' "$run_dir/brief.md"
}

@test "custom brief via --brief-text is honored (operator's OWN task)" {
  run_dir="$("$T" new --brief-text 'redesign my dashboard header' 2>/dev/null | head -1)"
  grep -Fq 'redesign my dashboard header' "$run_dir/brief.md"
}

@test "rubric prints the beat-margin decision rule" {
  run "$T" rubric
  [ "$status" -eq 0 ]
  [[ "$output" == *"beat Arm A"* ]]
  [[ "$output" == *"hedge only"* ]]
}

@test "unknown command → exit 2 (fail-closed dispatch)" {
  run "$T" frobnicate
  [ "$status" -eq 2 ]
}
