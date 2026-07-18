#!/usr/bin/env bats
# activation-watch (SessionStart) — the absence-is-loud re-page for the C10 activation queue (D-v).
# The tool's --selftest RED-proves the age/done/absent logic; these bats add independent CLI-level
# coverage via CC_ACTIVATION_DIR fixtures + the SessionStart additionalContext JSON contract.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  H="$REPO/hooks/activation-watch.sh"
  Q="$BATS_TEST_TMPDIR/queue"
  mkdir -p "$Q"
  OLD="$(date -v-25H +%Y%m%d%H%M.%S 2>/dev/null || echo 200001010000.00)"
}
stage() { printf '#!/bin/bash\n' > "$Q/$1"; [ -n "${2:-}" ] && touch -t "$2" "$Q/$1"; return 0; }

@test "selftest passes and runs all 7 checks (a zero-check suite must not 'pass')" {
  run "$H" --selftest
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | grep -c '^  ok ')" -eq 7 ]
  ! printf '%s' "$output" | grep -q '^  FAIL'
}

@test "stale (>24h) un-run activation → named in the additionalContext" {
  stage "p0-14-activate.sh" "$OLD"
  CC_ACTIVATION_DIR="$Q" run "$H"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'p0-14-activate.sh'
  printf '%s' "$output" | grep -q 'ACTIVATION QUEUE'
}

@test "output is valid SessionStart additionalContext JSON" {
  stage "x-activate.sh" "$OLD"
  CC_ACTIVATION_DIR="$Q" run "$H"
  printf '%s' "$output" | jq -e '.hookSpecificOutput.hookEventName == "SessionStart"' >/dev/null
  printf '%s' "$output" | jq -e '.hookSpecificOutput.additionalContext | test("x-activate.sh")' >/dev/null
}

@test "fresh (<24h) un-run activation → NOT named" {
  stage "fresh-activate.sh"
  CC_ACTIVATION_DIR="$Q" run "$H"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test ".done-marked stale activation → NOT named" {
  stage "ran-activate.sh" "$OLD"
  : > "$Q/ran-activate.sh.done"
  CC_ACTIVATION_DIR="$Q" run "$H"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "absent queue dir → silent, exit 0 (fail-open)" {
  CC_ACTIVATION_DIR="$BATS_TEST_TMPDIR/nope" run "$H"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "mixed queue: only the stale un-run one is named" {
  stage "stale-a.sh" "$OLD"
  stage "fresh-b.sh"
  stage "done-c.sh" "$OLD"; : > "$Q/done-c.sh.done"
  CC_ACTIVATION_DIR="$Q" run "$H"
  printf '%s' "$output" | grep -q 'stale-a.sh'
  ! printf '%s' "$output" | grep -q 'fresh-b.sh'
  ! printf '%s' "$output" | grep -q 'done-c.sh'
}
