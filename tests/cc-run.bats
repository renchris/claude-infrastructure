#!/usr/bin/env bats
# L3 — cc-run: the effect-bound progress-heartbeat wrapper. The tool's own selftest RED-proves the
# output-keyed discriminator; these bats add CLI-level regression (output pass-through, beat freshness).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  RUN="$REPO/bin/cc-run"
  export CC_RUN_HEARTBEAT_DIR="$BATS_TEST_TMPDIR/hb"
}
age_of() { local now mt; now="$(date +%s)"; mt="$(stat -f %m "$1" 2>/dev/null || echo 0)"; echo "$((now - mt))"; }

@test "selftest passes and runs all 4 checks (a zero-check suite must not 'pass')" {
  run "$RUN" selftest
  [ "$status" -eq 0 ]
  n_ok="$(printf '%s' "$output" | grep -c '^  ok ')"
  [ "$n_ok" -eq 4 ]
}

@test "streams the command's output through to stdout" {
  run "$RUN" --label o -- bash -c 'echo hello-world'
  [ "$status" -eq 0 ]
  [[ "$output" == *"hello-world"* ]]
}

@test "L3-a: output then silence → the heartbeat is STALE by the silent duration (keyed on output)" {
  "$RUN" --label a -- bash -c 'echo x; sleep 2' >/dev/null 2>&1
  [ -f "$CC_RUN_HEARTBEAT_DIR/a.beat" ]
  [ "$(age_of "$CC_RUN_HEARTBEAT_DIR/a.beat")" -ge 1 ]
}

@test "L3-a: silence then output → the heartbeat is FRESH (advanced with the output)" {
  "$RUN" --label b -- bash -c 'sleep 2; echo x' >/dev/null 2>&1
  # age_of is INTEGER seconds; the beat-write→check gap can straddle a second boundary under
  # suite load, reading age 1 for a beat that is really ~0s old (flake). <2 tolerates that one
  # boundary while still failing a start-keyed/stale beat (age ≈ the 2s command duration).
  [ "$(age_of "$CC_RUN_HEARTBEAT_DIR/b.beat")" -lt 2 ]
}

@test "L3-blind: --expect silent records heartbeat_expectation=none (routes liveness to L1/pid)" {
  "$RUN" --label s --expect silent -- sleep 0 >/dev/null 2>&1
  [ "$(jq -r '.heartbeat_expectation' "$CC_RUN_HEARTBEAT_DIR/s.meta")" = "none" ]
  [ "$(jq -r '.expect' "$CC_RUN_HEARTBEAT_DIR/s.meta")" = "silent" ]
}

@test "the command's real exit code propagates through the heartbeat pipe" {
  run "$RUN" --label e -- bash -c 'exit 7'
  [ "$status" -eq 7 ]
}
