#!/usr/bin/env bats
# CC_DISPATCH_VENUE_ONLY — the migration lever: fire ONE venue, park the rest VISIBLY.
#
# WHY THIS KNOB EXISTS. Before it, the dispatcher had exactly two states: everything fires, or
# DECIDE_ONLY stops every spawn including the cloud ones. "Migrate from local spawn to cloud spawn"
# was inexpressible. This is the third axis.
#
# THE LOAD-BEARING PROPERTY is NOT that it narrows — it is that narrowing to nothing is
# DISTINGUISHABLE from a healthy empty queue. A filter that silently matched zero rows would read
# exactly like a correctly-configured cloud-only box with no cloud work: a total outage wearing the
# shape of success. Every test below either pins the parked COUNT or pins the REFUSAL.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SUT="$REPO/bin/cc-dispatch"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/autonomy"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_DISPATCH_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_DISPATCH_LOCK_DIR="$BATS_TEST_TMPDIR/lock"
  export CC_DISPATCH_PROJECT="p"
  : > "$CC_BACKLOG_FILE"; : > "$CC_DISPATCH_IDL"
}

# row <id> <venuePlan|-> — an open, dispatchable item in project p
row() {
  local vp=""
  [ "${2:--}" != "-" ] && vp=", \"venuePlan\":\"$2\""
  printf '{"id":"%s","ts":"2026-08-01T00:00:00Z","event":"add","project":"p","title":"t %s"%s}\n' \
    "$1" "$1" "$vp" >> "$CC_BACKLOG_FILE"
}

@test "unset: the filter is absent, so every dispatchable item survives (the incumbent path)" {
  row a cloud; row b local; row c -
  run env -u CC_DISPATCH_VENUE_ONLY "$SUT" --decide
  [ "$status" -eq 0 ]
  # No park record at all — an unset filter must not journal a narrowing that did not happen.
  ! grep -q 'venue-only' "$CC_DISPATCH_IDL"
}

@test "=cloud admits ONLY the cloud rows" {
  row a cloud; row b local; row c cloud
  run env CC_DISPATCH_VENUE_ONLY=cloud "$SUT" --decide
  [ "$status" -eq 0 ]
  grep -q 'venue-only=cloud parked 1 of 3' "$CC_DISPATCH_IDL"
}

@test "an UNLABELLED row is parked too — absence of a plan is not evidence of eligibility" {
  # The producer fails CLOSED for the same reason: a wrong answer in a venue nobody can SEE.
  row a cloud; row c -; row d -
  run env CC_DISPATCH_VENUE_ONLY=cloud "$SUT" --decide
  [ "$status" -eq 0 ]
  grep -q 'venue-only=cloud parked 2 of 3' "$CC_DISPATCH_IDL"
}

# THE TEST THIS FILE EXISTS FOR. Narrowing to zero must be LOUD.
@test "parking the WHOLE queue is journalled with its count, never a silent empty wave" {
  row b local; row c local
  run env CC_DISPATCH_VENUE_ONLY=cloud "$SUT" --decide
  [ "$status" -eq 0 ]
  grep -q 'venue-only=cloud parked 2 of 2' "$CC_DISPATCH_IDL"
}

@test "a genuinely empty queue does NOT emit a park record — the two states stay apart" {
  # The other half of the discrimination: no dispatchable rows at all is not the same event as
  # 'the filter removed them', and a reader must be able to tell which happened.
  run env CC_DISPATCH_VENUE_ONLY=cloud "$SUT" --decide
  [ "$status" -eq 0 ]
  ! grep -q 'venue-only' "$CC_DISPATCH_IDL"
}

@test "an unrecognised value REFUSES the pass rather than narrowing it to zero" {
  # A typo'd venue matches no row, and a silent narrowing would be indistinguishable from a healthy
  # cloud-only box with an empty cloud queue (MEMORY: default-path-hardening-is-blind-to-the-
  # explicit-argument). Fail-closed and visible beats fail-quiet.
  row a cloud; row b local
  run env CC_DISPATCH_VENUE_ONLY=Cloud "$SUT" --decide
  [ "$status" -eq 3 ]
  printf '%s' "$output" | grep -q 'closed set'
  grep -q 'outside the closed set' "$CC_DISPATCH_IDL"
}

@test "=local is symmetric — the lever is a filter, not a cloud special case" {
  # If only 'cloud' worked this would be a hardcoded migration rather than a venue filter, and
  # rolling BACK to local-only would need another code change.
  row a cloud; row b local
  run env CC_DISPATCH_VENUE_ONLY=local "$SUT" --decide
  [ "$status" -eq 0 ]
  grep -q 'venue-only=local parked 1 of 2' "$CC_DISPATCH_IDL"
}
