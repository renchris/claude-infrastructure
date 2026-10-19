#!/usr/bin/env bats
# close-research-pending-rules.bats — REPORT.md A8
# (docs/research/research-pending-implementation-close-2026-10-18/): a research turn that names work
# it cannot drive FILES it, so the rung is ⛔ and the verdict reads "no — research done,
# implementation pending". E0 stays a superset: the new sentence is added beside "a read-only turn
# that names drivable work is not E0", never in its place — a past draft nearly narrowed it, the same
# pattern research-program-exemption-rules.bats guards.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  G="$REPO/CLAUDE.global.md"; S="$REPO/CLAUDE.rules.slim.10-session-close.md"
}

# E0's rule text in each variant: the full variant's readout-table row, the slim variant's bullet.
e0_global() { grep -F '| _E0_ read-only' "$G"; }
e0_slim() { grep -F -- '- E0, read-only turn:' "$S"; }

assert_e0() {
  local t="$1"
  [ -n "$t" ] || { echo "no E0 text found"; return 1; }
  printf '%s' "$t" | grep -qi 'a read-only turn that names drivable work is not E0' \
    || { echo "E0 lost its superset clause: $t"; return 1; }
  printf '%s' "$t" | grep -q 'recheck' || { echo "E0 does not name cc-decide recheck: $t"; return 1; }
  printf '%s' "$t" | grep -q 'research done, implementation pending' \
    || { echo "E0 does not give the research-done verdict: $t"; return 1; }
}

@test "global: E0 keeps 'not E0' and files what it cannot drive, with the research-done verdict" {
  assert_e0 "$(e0_global)"
}

@test "slim: E0 keeps 'not E0' and files what it cannot drive, with the research-done verdict" {
  assert_e0 "$(e0_slim)"
}

@test "neither variant's disposition row exempts research from the ledger" {
  ! grep -qF '/ research (no tracked writes)' "$S" || { echo "slim row still exempts research"; false; }
  ! grep -qF '/ research (no tracked writes)' "$G" || { echo "global row still exempts research"; false; }
  grep -qF '| Read-only / advisory (no tracked writes) |' "$S"
  grep -qF '| Read-only / advisory (no tracked writes) |' "$G"
}
