#!/usr/bin/env bats
# cc-owner — the resolver that answers "who ALREADY runs this" before a command is handed over.
# The two tests that matter are the POLARITY ones: this script must never convert its own ignorance
# into a finding, in either direction.

setup() { OWNER="${BATS_TEST_DIRNAME}/../bin/cc-owner"; }

@test "a launchd-owned script resolves to its agent, whatever spelling names it" {
  # Keyed on BASENAME, not path: the measured corpus hands the same script over as an absolute
  # path, a ~-path and a repo-relative path, and the plist names it a fourth way.
  run bash "$OWNER" "bash /Users/chrisren/Development/claude-infrastructure/scripts/deploy-live.sh"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q "OWNED"
  printf '%s' "$output" | grep -q "com.claude.deploy-live"

  run bash "$OWNER" "bash ~/Development/claude-infrastructure/scripts/deploy-live.sh --force"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q "com.claude.deploy-live"
}

@test "POLARITY: an unowned script is rc 1 and says so WITHOUT asserting a human is needed" {
  run bash "$OWNER" "bash /tmp/no-such-script-$$.sh"
  [ "$status" -eq 1 ]
  # The wording is the test. "no owner" must never render as "the operator must run this" — that
  # inference is the defect this tool exists to interrupt, and re-emitting it here would close the
  # loop in the wrong direction.
  printf '%s' "$output" | grep -q "NOT proof a human is needed"
}

@test "POLARITY: a command naming NO script is 'cannot resolve', never 'unowned'" {
  # 48.7% of measured emissions are this shape (/deploy, cc-blockers, open tel:…). Reporting them
  # as unowned would be a confident answer over a question this tool cannot see.
  run bash "$OWNER" "cc-blockers"
  [ "$status" -eq 1 ]
  printf '%s' "$output" | grep -q "cannot resolve"
  ! printf '%s' "$output" | grep -q "OWNED"
}

@test "--quiet is rc-only (the form a producer calls)" {
  run bash "$OWNER" --quiet "bash /Users/chrisren/Development/claude-infrastructure/scripts/deploy-live.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "no argument is a usage error (rc 2), never a silent 'unowned'" {
  run bash "$OWNER"
  [ "$status" -eq 2 ]
}
