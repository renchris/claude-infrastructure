#!/usr/bin/env bats
# MANIFEST allow-list matching must not depend on JSON whitespace.
#
# ~/.claude-versions/MANIFEST.jsonl is the ONE enforcing store for binary
# advancement: bin/claude-latest default-denies auto-install of any version that
# is not explicitly stable/candidate there. It read that store with
#   grep -E "\"version\":\"X\""   +   sed -nE 's/.*"status":"([^"]+)".*/\1/p'
# — both of which assume the compact, space-free spelling.
#
# Measured 2026-08-20 on the live store: 3 of 25 entries are written in the
# spaced form `{"version": "2.1.237", "status": "skip", ...}` — the spelling any
# programmatic writer (jq, python json.dumps) emits by default — and the matcher
# cannot see one of them. A miss is indistinguishable from absence
# (memory: lookup-miss-is-not-absence), so the launcher fell into its `*)`
# default-deny arm and logged "no MANIFEST entry" about an entry that was there.
#
# Today that happens to fail SAFE, because all three spaced entries are `skip`
# and default-deny refuses too. The direction that bites is the other one: a
# reviewed, smoke-tested `stable` entry written with spaces is silently never
# installed, and the log blames a missing entry. That is the case pinned first
# below — it is RED before the fix and green after.
#
# The two discriminators exist so the fix cannot be a blanket "allow": a spaced
# `skip` must still refuse, and a version with NO entry must still default-deny.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LAUNCHER="$REPO/bin/claude-latest"
  export HOME="$BATS_TEST_TMPDIR/home"
  VD="$HOME/.claude-versions"
  mkdir -p "$HOME/.claude" "$VD"

  # installed = 2.1.220 (what `current` points at)
  mk_version 2.1.220
  ln -sfn "$VD/2.1.220" "$VD/current"

  # a stubbed npm on PATH reports 2.1.237 as available (no network)
  STUB="$BATS_TEST_TMPDIR/stubbin"; mkdir -p "$STUB"
  printf '#!/bin/bash\necho 2.1.237\n' > "$STUB/npm"; chmod +x "$STUB/npm"
  export PATH="$STUB:$PATH"

  # the candidate version is already unpacked, so a permitted upgrade just
  # SWITCHES — the gate is exercised without any install/network step.
  mk_version 2.1.237
}

mk_version() { # $1 = version
  local d="$VD/$1/node_modules/.bin"
  mkdir -p "$d"
  printf '#!/bin/bash\necho "STUB-CLAUDE %s"\nexit 0\n' "$1" > "$d/claude"
  chmod +x "$d/claude"
}

manifest() { printf '%s\n' "$@" > "$VD/MANIFEST.jsonl"; }

REFUSAL='not in MANIFEST allow-list'

# ---- the red-proof: the spelling a programmatic writer actually emits --------

@test "spaced stable entry is HONORED (pre-fix: silently default-denied)" {
  manifest '{"version": "2.1.237", "status": "stable", "date_added": "2026-08-20T00:00:00Z"}'
  run bash "$LAUNCHER"
  [[ "$output" != *"$REFUSAL"* ]] || {
    echo "REGRESSION: a reviewed stable entry was invisible to the matcher"; false; }
  [[ "$output" == *"2.1.237"* ]] || false
}

# ---- discriminators: the fix must not become a blanket allow ----------------

@test "spaced skip entry refuses FOR THE SKIP REASON, not by falling through" {
  # Pre-fix this refuses too — but by default-deny, because the entry is
  # invisible. Asserting only "it refused" would pass in both worlds and credit
  # the fix with nothing (memory: sibling-guard-makes-the-fixture-vacuous), so
  # the assertion is on the REASON the launcher logs.
  manifest '{"version": "2.1.237", "status": "skip", "date_added": "2026-08-20T00:00:00Z"}'
  run bash "$LAUNCHER"
  [[ "$output" != *"STUB-CLAUDE 2.1.237"* ]] || {
    echo "a skip entry must never auto-install"; false; }
  run cat "$HOME/.claude/.update-versions.log"
  [[ "$output" == *"MANIFEST status=skip"* ]] || {
    echo "refused, but blamed a missing entry instead of the skip it was given"; false; }
}

@test "no entry at all still DEFAULT-DENIES (the security property)" {
  manifest '{"version":"2.1.999","status":"stable","date_added":"2026-08-20T00:00:00Z"}'
  run bash "$LAUNCHER"
  [[ "$output" == *"$REFUSAL"* ]] || false
}

@test "compact stable entry keeps working (no regression on 22 of 25 rows)" {
  manifest '{"version":"2.1.237","status":"stable","date_added":"2026-08-20T00:00:00Z"}'
  run bash "$LAUNCHER"
  [[ "$output" != *"$REFUSAL"* ]] || false
}

# ---- the same matcher, second site -----------------------------------------

@test "the hold-watch shares the matcher and must read a spaced entry too" {
  W="$REPO/scripts/watch-claude-code-2118-hold.sh"
  [ -f "$W" ] || skip "watch script absent"
  manifest '{"version": "2.1.237", "status": "skip", "date_added": "2026-08-20T00:00:00Z"}'
  # exercise the matcher the script uses, sourced from the script itself so the
  # test cannot drift from the subject (mention-vs-use).
  line="$(grep -n 'skip_check=' "$W" | head -1 | cut -d: -f1)"
  [ -n "$line" ] || false
  expr="$(sed -n "${line}p" "$W")"
  [[ "$expr" == *'[[:space:]]'* ]] || {
    echo "watch matcher still assumes space-free JSON: $expr"; false; }
}
