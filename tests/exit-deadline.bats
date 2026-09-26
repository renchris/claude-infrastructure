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

@test "selftest passes, is non-vacuous (floor), and its tally matches what it rendered" {
  floor=7                        # raise when checks are added; LOWERING it is a deliberate act
  run "$D" --selftest
  [ "$status" -eq 0 ]
  # `|| true` normalizes grep's rc-1-on-zero-matches; the count is data, the assertions are the verdict.
  ok_lines="$(printf '%s' "$output" | grep -c '^  ok ' || true)"
  claimed="$(printf '%s' "$output" | sed -n 's/^exit-deadline --selftest: \([0-9][0-9]*\) passed,.*/\1/p')"
  [ "$ok_lines" -ge "$floor" ]    # FLOOR, not an exact count: an added check is growth, not a red
  [ -n "$claimed" ]
  [ "$claimed" = "$ok_lines" ]    # TALLY: the summary counts what it actually rendered
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
