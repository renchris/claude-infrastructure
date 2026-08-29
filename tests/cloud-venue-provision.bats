#!/usr/bin/env bats
# The venue census that decides whether a cloud VM's own land path can render a verdict.
#
# WHAT THIS SUITE IS FOR, GIVEN THE SUBJECT ALREADY HAS A --selftest. The script's --selftest drives
# venue_verdict() with synthetic operands and proves it DISCRIMINATES. It cannot prove the two things
# that actually decide whether the file is useful: that the live probes reach those cells on a real
# box, and that the claim the script makes ABOUT ship-land.sh is still true of ship-land.sh. Both are
# pinned here. The second is the load-bearing one — the whole file is an argument about someone
# else's control flow, and an argument about code is a claim that rots when that code changes.
#
# THE ASYMMETRY UNDER TEST (measured on a cloud VM 2026-08-29, docs/plans/BACKLOG_DRAIN_24_7.md):
#   ShellCheck absent → bats-shellcheck-lint exits 2 → bats_sc_nonverdict → GATE_KILLED → exit 9.
#   bats absent       → suites exit 127 with zero TAP not-ok lines → CUT → smoke "partial" → exit 0.
# (Capitalised deliberately: a comment whose first word is the lower-case tool name parses as a
#  malformed directive and aborts analysis of this whole file — the lint above says so, and this
#  suite tripped it anyway, which is the third instance in one diff.)
# One is a lock; the other is a silent ungating. The plan's addendum called them "both locks".

setup() {
  REPO="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  SUT="$REPO/scripts/cloud-venue-provision.sh"
  LAND="$REPO/scripts/ship-land.sh"
  # Hermetic $HOME: nothing in the subject reads it today, and the subject is a file that runs
  # before a land, which is the worst place to discover that changed.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
}

# ── the subject's own discrimination proof, run as a test so a regression in it is a red suite ────
@test "cloud-venue-provision --selftest passes and reports a full count" {
  run bash "$SUT" --selftest
  [ "$status" -eq 0 ]
  [[ "$output" =~ --selftest:\ ([0-9]+)/([0-9]+)\  ]] || false
  [ "${BASH_REMATCH[1]}" = "${BASH_REMATCH[2]}" ]
  [ "${BASH_REMATCH[1]}" -ge 12 ]
}

# ── the live probes reach the cells, on whatever box this runs on ─────────────────────────────────
@test "--check reads READY on a box that has both tools" {
  command -v shellcheck >/dev/null 2>&1 || skip "no shellcheck on this box — the positive control is unavailable"
  command -v bats >/dev/null 2>&1 || skip "no bats on this box (impossible: bats is running this)"
  run bash "$SUT" --check
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict: READY"* ]]
}

@test "--check reads LOCKED, and exits non-zero, when the checker is absent" {
  CC_VENUE_ABSENT="shellcheck" run bash "$SUT" --check
  [ "$status" -ne 0 ]
  [[ "$output" == *"verdict: LOCKED"* ]] || false
  [[ "$output" == *"exits 9"* ]]
}

# THE THIRD LOCK, driven through the witness rather than by installing an old binary. The probe's
# whole claim is that it measures THIS BOX by RUNNING the checker, so pointing it at a file that is
# genuinely unclean must reach STALE-CHECKER — and pointing it at a clean one must not.
@test "--check reads STALE-CHECKER when the checker reds its witness" {
  command -v shellcheck >/dev/null 2>&1 || skip "no shellcheck on this box"
  printf '#!/bin/sh\nfoo=1\necho $foo | grep -q x && echo "$UNSET_VAR"\ncd /tmp/$foo\n' > "$BATS_TEST_TMPDIR/dirty.sh"
  # the fixture must actually be unclean, or this test proves nothing about the probe
  run shellcheck "$BATS_TEST_TMPDIR/dirty.sh"
  [ "$status" -ne 0 ]
  CC_VENUE_WITNESS="$BATS_TEST_TMPDIR/dirty.sh" run bash "$SUT" --check
  [ "$status" -ne 0 ]
  [[ "$output" == *"verdict: STALE-CHECKER"* ]] || false
  [[ "$output" == *"witness stale"* ]]
}

@test "the witness probe abstains rather than convicting when there is no witness" {
  CC_VENUE_WITNESS="$BATS_TEST_TMPDIR/does-not-exist.sh" run bash "$SUT" --check
  [[ "$output" == *"witness ok"* ]] || false
  [[ "$output" != *"STALE-CHECKER"* ]]
}

@test "an absent checker outranks a stale one — the land meets them in that order" {
  printf '#!/bin/sh\ncd /tmp/$1\n' > "$BATS_TEST_TMPDIR/dirty2.sh"
  CC_VENUE_ABSENT="shellcheck" CC_VENUE_WITNESS="$BATS_TEST_TMPDIR/dirty2.sh" run bash "$SUT" --check
  [[ "$output" == *"verdict: LOCKED"* ]] || false
  [[ "$output" != *"STALE-CHECKER"* ]]
}

@test "--check reads UNGATED, and exits non-zero, when the runner is absent" {
  CC_VENUE_ABSENT="bats" run bash "$SUT" --check
  [ "$status" -ne 0 ]
  [[ "$output" == *"verdict: UNGATED"* ]] || false
  [[ "$output" == *"PROCEEDS unrun"* ]]
}

@test "the hard lock takes precedence over the silent one when both are absent" {
  CC_VENUE_ABSENT="shellcheck bats" run bash "$SUT" --check
  [ "$status" -ne 0 ]
  [[ "$output" == *"verdict: LOCKED"* ]] || false
  [[ "$output" != *"UNGATED"* ]]
}

# THE SEAM'S ASYMMETRY, asserted rather than assumed. CC_VENUE_ABSENT exists only so the two failure
# cells are reachable from here; if it could ever manufacture PRESENCE it would let a suite certify a
# box that cannot land. Naming a tool that is already there must change nothing.
@test "CC_VENUE_ABSENT cannot manufacture presence" {
  command -v shellcheck >/dev/null 2>&1 || skip "no shellcheck on this box"
  run bash "$SUT" --check
  local plain="$output"
  CC_VENUE_ABSENT="curl git awk" run bash "$SUT" --check
  [ "$output" = "$plain" ]
}

# ── the NOT-APPLICABLE arm: the ratchet keys on the REPO, so a repo without suites is not locked ──
@test "a repo with no tests/*.bats abstains instead of convicting" {
  mkdir -p "$BATS_TEST_TMPDIR/other/scripts"
  cp "$SUT" "$BATS_TEST_TMPDIR/other/scripts/"
  CC_VENUE_ABSENT="shellcheck bats" run bash "$BATS_TEST_TMPDIR/other/scripts/cloud-venue-provision.sh" --check
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict: NOT-APPLICABLE"* ]] || false
  [[ "$output" != *"LOCKED"* ]]
}

@test "--check writes nothing and installs nothing" {
  local before; before="$(cd "$REPO" && git status --porcelain | sha256sum)"
  CC_VENUE_ABSENT="shellcheck bats" run bash "$SUT" --check
  local after; after="$(cd "$REPO" && git status --porcelain | sha256sum)"
  [ "$before" = "$after" ]
  [[ "$output" != *"installing"* ]]
}

@test "an unknown argument refuses rather than falling through to the install path" {
  run bash "$SUT" --wat
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown argument"* ]]
}

# ── the claims this file makes ABOUT ship-land.sh, pinned so they cannot rot silently ─────────────
# Both are greps for shapes, not for prose: a comment could be reworded without the routing changing,
# and the routing could change without the comment being touched. It is the routing that is pinned.

@test "ship-land still routes the checker's exit 2 to a NON-VERDICT that kills the gate" {
  grep -qE 'scrc -eq 2 \]\]; then bats_sc_nonverdict; return 1' "$LAND"
  # …and that handler must still set GATE_KILLED, which is what produces exit 9 rather than a red.
  sed -n '/^bats_sc_nonverdict()/,/^}/p' "$LAND" | grep -qE 'GATE_KILLED=1'
}

@test "ship-land still lets a CUT proceed — the polarity this venue script exists because of" {
  # `cut=1` ⇒ partial ⇒ return 0. If this ever becomes a refusal, the UNGATED verdict's sentence is
  # wrong (a missing runner would then be a second lock) and cloud-venue-provision.sh must be
  # re-read before this suite is made to pass again.
  run bash -c "sed -n '/if \[\[ \"\$cut\" -eq 1 \]\]; then/,/^  fi/p' '$LAND'"
  [ "$status" -eq 0 ]
  [[ "$output" == *'SMOKE_STATE="partial"'* ]] || false
  [[ "$output" == *"return 0"* ]] || false
  # AND NOTHING IN THE BLOCK REFUSES. Asserting only that `return 0` is PRESENT is a vacuous pin: a
  # `return 1` added above it satisfies the substring test while inverting the behaviour the whole
  # finding rests on. Measured while writing this suite — the weak form passed against exactly that
  # mutant. Absence is the half that carries the claim.
  [[ "$output" != *"return 1"* ]] || false
  [[ "$output" != *"gate_red"* ]]
}

@test "ship-land's smoke runner still invokes bats bare, which is why an absent runner exits 127" {
  sed -n '/^gate_bats()/,/^}/p' "$LAND" | grep -qE '(^|[[:space:]])bats "\$@"'
}

@test "the .bats ratchet's entry condition is still a property of the repo, not of the diff" {
  # This is what makes a missing checker block a DOCS-ONLY land here, and it is the single most
  # surprising half of the finding. If it ever becomes diff-scoped, LOCKED's sentence overstates.
  grep -qE '\[\[ -d tests \]\] && ls tests/\*\.bats' "$LAND"
}
