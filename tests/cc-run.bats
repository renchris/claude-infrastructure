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
  t0="$(date +%s)"
  "$RUN" --label b -- bash -c 'sleep 2; echo x' >/dev/null 2>&1
  [ -f "$CC_RUN_HEARTBEAT_DIR/b.beat" ]
  # The beat is keyed on OUTPUT (command-relative t≈2s), not START (t=0). Assert it was written
  # >=1s AFTER the command started — a start-relative delta that is robust to suite-load check-delay,
  # unlike an absolute age-at-check (age_of), which under parallel load straddles multiple
  # integer-second boundaries and false-flakes (3596b45 class; recurred 2026-07-18 full-suite run).
  # A start-keyed bug writes the beat at ~t0 (delta ~0) and FAILS; the correct output-keyed beat's
  # mtime is ~2s past t0. The 2s sleep guarantees a wide margin either side of the 1s split.
  beat_mt="$(stat -f %m "$CC_RUN_HEARTBEAT_DIR/b.beat")"
  [ "$((beat_mt - t0))" -ge 1 ]
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
