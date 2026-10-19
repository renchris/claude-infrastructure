#!/usr/bin/env bats
# explain-decisions-command.bats — REPORT.md A9
# (docs/research/research-pending-implementation-close-2026-10-18/): /explain-decisions ends in a
# disposition, not a list. The re-check writes its report somewhere durable, stamps each packet it
# could not close or implement, and closes on the research-done verdict — so the operator sees the
# sign-off rung instead of a session that read the decisions and went quiet.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  C="$REPO/commands/explain-decisions.md"
}

@test "the command stamps what it cannot settle with cc-decide recheck" {
  grep -q 'cc-decide recheck' "$C"
}

@test "the report path is durable: the command says never /tmp" {
  grep -i 'never' "$C" | grep -q '/tmp'
}

@test "the command closes on the research-done, implementation-pending verdict" {
  grep -q 'research done, implementation pending' "$C"
}
