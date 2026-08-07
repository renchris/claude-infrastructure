#!/usr/bin/env bats
# THE COVERAGE LEDGER for the duplicate-worker gate — which enforcement points carry it, and where
# in the file they sit, asserted from the TREE (backlog 18323346082a).
#
# WHY A SEPARATE SUITE FROM tests/worker-claim-gate.bats. That one proves the library DECIDES
# correctly. This one proves the decision is WIRED and REACHABLE, which is a different failure mode
# and the one this whole item is about: on 2026-08-07 `cc-backlog` decided perfectly — it refused
# eight duplicate sessions with `verdict=noop-live-claimer` — and every one of them worked the item
# anyway, because the verdict reached a journal and no actuator. A correct decision behind a dead
# branch is indistinguishable from no decision at all.
#
# ASSERTED BY INVOCATION AND BY POSITION, NOT BY MENTION (memory
# `caller-census-keyed-on-path-misses-the-name`: a census keyed on the wrong token read "zero
# callers" for a hook that was live). Every case greps for a real call and, where ordering is the
# property, compares LINE NUMBERS — because the defect this guards is not a missing call, it is a
# call placed after an early exit that the common case takes.
#
# THE ORDERING CASE (02) IS THE LOAD-BEARING ONE. `check-edit-boundary.sh` returns early whenever no
# freeze/focus boundary is set, which is the box's normal state. A gate placed below that line is
# armed only while an operator happens to have a boundary active — i.e. essentially never. This is
# the `24b` lesson from tests/capacity-admit-coverage.bats ("the Agent gate runs BEFORE every
# early-exit, so no subagent type escapes it") applied to a second hook.
#
# RED-PROOF (recorded 2026-08-07): case 01 was re-run against a hook with the call commented out and
# went RED; case 02 was re-run with the gate block moved BELOW the state-file early exit and went
# RED while every other case stayed green — so it observes position, not presence. Case 05's
# mutation control is inline.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LIB="$REPO/scripts/lib/worker-claim-gate.sh"
  HOOK="$REPO/hooks/check-edit-boundary.sh"
  DETECT="$REPO/hooks/session-register.sh"
  # HERMETIC $HOME even though every case here only READS the tree. The subjects default their state
  # dir, IDL and cc-backlog resolution to $HOME, so any case added later that actually RUNS one of
  # them would silently write the operator's live ~/.claude — and the leak would arrive with that
  # future case, not with this setup(). Fixturing now costs nothing and closes it in advance;
  # scripts/test-hermeticity-lint.sh enforces it, and its instruction is explicit: fix the suite, do
  # NOT add to the allowlist (the ratchet only shrinks).
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_WCLAIM_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_WCLAIM_STATE_DIR="$BATS_TEST_TMPDIR/state"
}

refute_match() { [ "$(printf '%s' "$1" | grep -c "$2")" -eq 0 ]; }

# line number of the first line matching $2 in file $1, or "" — the primitive the ordering cases use
lineno() { grep -n "$2" "$1" 2>/dev/null | head -1 | cut -d: -f1; }

@test "01 the ACTUATOR is called — a real invocation in a hook already in settings.json" {
  [ -f "$LIB" ]
  grep -q '^cc_worker_claim_admit()' "$LIB"
  # A REAL INVOCATION — not a comment, and specifically NOT the `command -v` existence probe.
  # The first draft grepped `^[^#]*cc_worker_claim_admit ` and stayed GREEN when the actual call was
  # commented out, because `if command -v cc_worker_claim_admit >/dev/null` satisfied it: the census
  # matched a line that TESTS FOR the actuator rather than one that RUNS it, which is the same
  # non-call-matching-a-call error as `caller-census-keyed-on-path-misses-the-name`, inverted. Found
  # by the mutation control below, which is why it is run rather than reasoned about.
  # The invocation begins its own statement, so a leading `#` cannot be absorbed by `[[:space:]]*`.
  [ "$(grep -cE '^[[:space:]]*cc_worker_claim_admit [a-z]' "$HOOK")" -ge 1 ]
  # …and the fall-through probe is separately present, since case 08 depends on it existing
  grep -q 'command -v cc_worker_claim_admit' "$HOOK"
  # and it must be in a hook that is ALREADY registered, never a new file: a new hook needs a
  # settings.json entry (C10 operator-only), i.e. the pending-activation queue where scripts rot
  # >24h unrun. A gate that ships inert is the generator this item exists inside of.
  grep -q 'Matcher: Write|Edit|MultiEdit' "$HOOK"
}

@test "02 the gate runs BEFORE every early exit — the boundary hook returns early by default" {
  gate="$(lineno "$HOOK" 'cc_worker_claim_admit edit-boundary')"
  statefile="$(lineno "$HOOK" '! -f "\$STATE_FILE" \] && exit 0')"
  jqexit="$(lineno "$HOOK" 'if ! command -v jq')"
  [ -n "$gate" ]; [ -n "$statefile" ]; [ -n "$jqexit" ]
  [ "$gate" -lt "$statefile" ]
  [ "$gate" -lt "$jqexit" ]
}

@test "03 stdin is drained ONCE, above the gate — a second `cat` would read an empty pipe" {
  input="$(lineno "$HOOK" '^INPUT=\$(cat)')"
  gate="$(lineno "$HOOK" 'cc_worker_claim_admit edit-boundary')"
  [ -n "$input" ]; [ "$input" -lt "$gate" ]
  [ "$(grep -c '^INPUT=\$(cat)' "$HOOK")" -eq 1 ]
}

@test "04 the DETECTOR still consumes the ledger's refusal — the other half of the seam" {
  # session-register.sh is where the refusal is first seen (SessionStart, in the worktree that names
  # the item). It cannot BLOCK — SessionStart has no such field — but if it stops consuming the
  # verdict the ledger's contract has silently lost its only other reader.
  grep -q 'verdict=noop-live-claimer' "$DETECT"
  grep -q 'incumbent live' "$DETECT"
}

@test "05 the REFUSAL is emitted in the PreToolUse deny schema, with a drivable action" {
  grep -q 'permissionDecision": *"deny"\|permissionDecision: *"deny"' "$HOOK"
  grep -q 'hookEventName' "$HOOK"
  # a refusal that does not say what to do next is the advisory shape again, one level up
  grep -q 'self-close' "$HOOK"
  grep -q 'DO NOT retry' "$HOOK"
  # and it must name its own override, so the gate can never be an unescapable wall
  grep -q 'CC_WCLAIM_GATE=off' "$HOOK"
}

@test "06 NO REFUSAL BUDGET — this gate must never acquire capacity-admit's release-on-expiry shape" {
  # scripts/lib/capacity-admit.sh ADMITS after CC_ADMIT_BUDGET consecutive refusals, because a
  # TRANSIENT MACHINE STATE must not become a permanent outage. Here the refusal denies a FACT about
  # a live lease: admitting on expiry MINTS the second worker. The unsafe direction is inverted, so
  # the two libraries must not converge. Structural half of tests/worker-claim-gate.bats case 13.
  #
  # THE ASSERTION IS OVER CODE, NOT OVER THE FILE TEXT, and that distinction is the case's whole
  # correctness. A first draft banned the substrings outright and went RED against its own subject:
  # the library's header NAMES `CC_ADMIT_BUDGET` in the paragraph explaining why it deliberately has
  # no budget. A denylist over spellings cannot tell "implements this" from "documents why it must
  # not" — it fires on the very comment that keeps the next reader from re-introducing the defect,
  # i.e. it punishes the fix (memory `denylist-enumerates-spellings-not-the-class`,
  # `guard-proxy-fails-in-both-directions`). Comments are stripped first, so the class under test is
  # EXECUTABLE budget logic.
  code="$(grep -v '^[[:space:]]*#' "$LIB")"
  refute_match "$code" 'budget-expired'
  refute_match "$code" 'CC_ADMIT_BUDGET'
  refute_match "$code" '_cc_admit_spend'
  # MUTATION CONTROL: the same greps must be able to FIRE, and against the same comment-stripped
  # shape — otherwise the strip itself could be what makes this pass. capacity-admit implements all
  # three in code, so a control that reads them there proves the predicate is live.
  cap="$REPO/scripts/lib/capacity-admit.sh"
  [ -f "$cap" ]
  capcode="$(grep -v '^[[:space:]]*#' "$cap")"
  [ "$(printf '%s' "$capcode" | grep -c 'budget-expired')" -gt 0 ]
  [ "$(printf '%s' "$capcode" | grep -c '_cc_admit_spend')" -gt 0 ]
}

@test "07 the gate FAILS OPEN on every unknown — it must not convict on its own bad wiring" {
  # Each of these branches returns 0 (admit). A gate whose failure mode is refusal turns an
  # unreadable oracle into a fleet-wide write freeze.
  for basis in 'fail-open' 'gate-off' 'unknown-id' 'no-claim'; do
    grep -q "$basis" "$LIB"
  done
  # exactly ONE `return 9` in the library: the live-claimer branch and nothing else
  [ "$(grep -c 'return 9' "$LIB")" -eq 1 ]
  grep -A2 'verdict=noop-live-claimer\*)' "$LIB" >/dev/null
}

@test "08 an ABSENT library falls through — it must not disarm the hook's other guard" {
  # `[ -f ] && . && break` then a `command -v` test, never an unconditional source or an exit.
  grep -q 'command -v cc_worker_claim_admit' "$HOOK"
  refute_match "$(grep -A3 'for _wcg in' "$HOOK")" 'exit 1'
  # the symlink-resolved sibling must be FIRST: ~/.claude/hooks/*.sh are symlinks into the checkout,
  # so a $CLAUDE_CONFIG_DIR-first lookup finds nothing until the next deploy — the
  # deployed-layer-bootstrap-circle, verified live in 64a7d1fa.
  first="$(grep -A1 'for _wcg in' "$HOOK" | head -1)"
  printf '%s' "$first" | grep -q 'dirname "\$_ceb_self"'
}
