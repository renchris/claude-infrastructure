#!/usr/bin/env bats
# comms-safety — F4 exit-deadline: the wait/sweep deadline is an INPUT that TIGHTENS during exit sequences
# (900s) and relaxes otherwise (3600s). The W5 desk was 50 min late on an HOURLY-tuned re-observe. The
# tool's --selftest RED-proves the event-adaptivity; these bats add CLI-level regression.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  D="$REPO/scripts/exit-deadline.sh"
  export CC_EXIT_SEQUENCE_FLAG="$BATS_TEST_TMPDIR/exit.flag"
  unset CC_EXIT_SEQUENCE
}

@test "selftest passes 7/7 (a zero-check suite must not 'pass')" {
  run "$D" --selftest
  [ "$status" -eq 0 ]
  n="$(printf '%s' "$output" | grep -c '^  ok ')"
  [ "$n" -eq 7 ]
}

@test "no exit sequence → 3600 default" {
  run "$D" resolve
  [ "$status" -eq 0 ]
  [ "$output" = "3600" ]
}

@test "exit-sequence flag file → 900" {
  : > "$CC_EXIT_SEQUENCE_FLAG"
  run "$D" resolve
  [ "$output" = "900" ]
}

@test "CC_EXIT_SEQUENCE env → 900" {
  CC_EXIT_SEQUENCE=1 run "$D" resolve
  [ "$output" = "900" ]
}

@test "per-layer pair honored under an exit sequence (--exit 600)" {
  CC_EXIT_SEQUENCE=on run "$D" resolve --default 1800 --exit 600
  [ "$output" = "600" ]
}

@test "per-layer default honored with no exit sequence (--default 1800)" {
  run "$D" resolve --default 1800 --exit 600
  [ "$output" = "1800" ]
}

@test "active: exit 1 when normal, exit 0 in an exit sequence" {
  run "$D" active
  [ "$status" -eq 1 ]
  : > "$CC_EXIT_SEQUENCE_FLAG"
  run "$D" active
  [ "$status" -eq 0 ]
}

@test "non-integer deadline → usage error (exit 2)" {
  run "$D" resolve --default abc
  [ "$status" -eq 2 ]
}
