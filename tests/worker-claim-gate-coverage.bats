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
#
# RED-PROOF for the SECOND enforcement point, cases 09-13 (recorded 2026-08-10, backlog
# 5deb4418a648), by the same two mutations applied to hooks/agent-teams-enforce.sh:
#   M1 the invocation commented out         → 09, 10, 13 RED   (11, 12 green — they test other axes)
#   M2 the whole block moved BELOW the       → 10 RED, 09 green — so 10 observes POSITION, with the
#      capacity term, call left intact          call fully present: gate 113→187 vs capacity 183→79
#   M3 the deny sentence reworded            → 11, 13 RED
# M1 is what CAUGHT case 10's first draft, which used a bare `lineno … 'cc_worker_claim_admit
# agent-tool'` and stayed GREEN against a commented-out call — the same non-call-matching-a-call
# error case 01 records, arriving one hook later. The predicate is now anchored to a statement start.
# Case 12's predicate was likewise caught by its own first run: it asserted `"basis":"absent"` (JSON)
# against a file that writes `basis:"absent"` (jq object construction), and went RED on the subject
# it was meant to certify.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LIB="$REPO/scripts/lib/worker-claim-gate.sh"
  HOOK="$REPO/hooks/check-edit-boundary.sh"
  # The SECOND enforcement point (backlog 5deb4418a648). HOOK stops a duplicate corrupting the
  # worktree; HOOK2 stops it spending the fleet. Both are already-registered hooks — HOOK on
  # PreToolUse|Write|Edit|MultiEdit, HOOK2 on PreToolUse|Agent — so neither needed a settings.json
  # entry, which is the C10 hand-step that leaves gates rotting in the activation queue.
  HOOK2="$REPO/hooks/agent-teams-enforce.sh"
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
  # EVERY refusal is ENUMERATED AND JOURNALLED — the invariant, not a headcount.
  #
  # This was `[ "$(grep -c 'return 9' "$LIB")" -eq 1 ]`, which reddened the moment a SECOND
  # legitimate refusal arrived (the done-latched arm, 2026-08-07) while being unable to catch the
  # thing it was written to catch: a `return 9` smuggled into a fail-open branch keeps the count at
  # one. An `-eq N` over a growing subject only ever fires on its own growth
  # (memory `exact-count-assertion-tripwires-its-own-subject`), so it is replaced by the property
  # the count was standing in for.
  #
  # The property: every `return 9` is immediately preceded by a `_cc_wclaim_emit refuse <basis>`,
  # and every such basis is on this list. Adding a refusal is then a DELIBERATE edit here — which is
  # the point — while adding an admit costs nothing. A refusal on an unnamed basis goes RED, and so
  # does a refusal that returns silently.
  n9="$(grep -c 'return 9' "$LIB")"
  [ "$n9" -ge 1 ]
  [ "$(grep -c '_cc_wclaim_emit refuse' "$LIB")" -eq "$n9" ]
  # the basis set is exactly the sanctioned two — a live lease, and a completed item
  bases="$(grep -o '_cc_wclaim_emit refuse [a-z-]*' "$LIB" | awk '{print $3}' | sort -u | tr '\n' ' ')"
  [ "$bases" = "done-latched measured " ]
  # and NO fail-open basis may sit on a refusing path
  for basis in 'fail-open' 'gate-off' 'unknown-id' 'no-claim'; do
    [ "$(grep -c "_cc_wclaim_emit refuse $basis" "$LIB")" -eq 0 ]
  done
  grep -A2 'verdict=noop-live-claimer\*)' "$LIB" >/dev/null
}

@test "09 the SPAWN surface carries the gate too — the cost this item measured is fan-out, not writes" {
  # WHY A SECOND POINT. The write gate (cases 01-03) is blind to the whole cost until after it is
  # paid: a worker orients BEFORE it edits, so a duplicate's subagents are all spawned upstream of
  # its first Write. The 2026-08-07 lineage reconstructed from logs/pane-spawns.jsonl is three
  # generations and 91+ sessions in ONE worktree; the filed item's own cost line is "one full worker
  # slot plus its subagents". Same library, same lease, second consumer.
  [ -f "$HOOK2" ]
  # A REAL INVOCATION, by the same predicate case 01 uses and for the same reason — the `command -v`
  # existence probe must not be able to satisfy it.
  [ "$(grep -cE '^[[:space:]]*cc_worker_claim_admit [a-z]' "$HOOK2")" -ge 1 ]
  grep -q 'command -v cc_worker_claim_admit' "$HOOK2"
  # ALREADY REGISTERED, never a new file (the C10 / pending-activation argument, verbatim from 01)
  grep -qE 'PreToolUse hook on Agent tool|Matcher: *Agent' "$HOOK2"
  # a DISTINCT caller id from the write gate: the caller keys the admit cache, and one shared key
  # would let a cached write-admit silently vouch for a spawn (and vice versa)
  grep -q 'cc_worker_claim_admit agent-tool' "$HOOK2"
  [ "$(grep -c 'cc_worker_claim_admit edit-boundary' "$HOOK2")" -eq 0 ]
}

@test "10 the spawn gate runs BEFORE the capacity term and before every policy exit" {
  # POSITION, not presence — case 02's lesson on the other hook. This one has a specific ordering
  # claim to defend: the duplicate term must precede the CAPACITY term, because capacity's refusal
  # is TRANSIENT ("shed and retry") while this one is TERMINAL ("stand down"). A duplicate handed
  # the transient sentence is told to come back, when the correct answer is that it must never run.
  # ANCHORED ON A REAL CALL, not on any mention. A first draft used a bare
  # `lineno "$HOOK2" 'cc_worker_claim_admit agent-tool'` and stayed GREEN when the invocation was
  # commented out — the mutation control below found it. A position case that a `#` satisfies is
  # measuring the position of a comment, which is case 01's lesson arriving one hook later. The
  # pattern requires the call to begin its own statement, so a leading `#` cannot be absorbed.
  gate="$(lineno "$HOOK2" '^[[:space:]]*cc_worker_claim_admit agent-tool')"
  cap="$(lineno "$HOOK2" '^[[:space:]]*if ! CC_ADMIT_LOAD_TERM=off cc_capacity_admit')"
  budget="$(lineno "$HOOK2" '_sb_max=')"
  [ -n "$gate" ]; [ -n "$cap" ]; [ -n "$budget" ]
  [ "$gate" -lt "$cap" ]
  [ "$gate" -lt "$budget" ]
  # and it must sit BELOW the single stdin drain, or it reads an empty pipe (case 03's property)
  input="$(lineno "$HOOK2" '^INPUT=\$(cat)')"
  [ -n "$input" ]; [ "$input" -lt "$gate" ]
  [ "$(grep -c '^INPUT=\$(cat)' "$HOOK2")" -eq 1 ]
}

@test "11 the spawn refusal uses the deny schema and names a drivable action" {
  block="$(sed -n "/DUPLICATE WORKER — subagent spawn refused/p" "$HOOK2")"
  [ -n "$block" ]
  printf '%s' "$block" | grep -q 'DO NOT retry'
  printf '%s' "$block" | grep -q 'self-close'
  printf '%s' "$block" | grep -q 'CC_WCLAIM_GATE=off'
  # the deny verdict itself, in the PreToolUse schema
  grep -q 'permissionDecision: *"deny"' "$HOOK2"
}

@test "12 an ABSENT library leaves the Agent hook's OTHER guards armed, and says so in the ledger" {
  # The fall-through contract (case 08) applied to the second point. An unreachable library must not
  # be able to disarm the model allowlist / brief cap / depth cap that share this hook.
  grep -q 'command -v cc_worker_claim_admit' "$HOOK2"
  refute_match "$(grep -A3 'for _wcg in' "$HOOK2")" 'exit 1'
  first="$(grep -A1 'for _wcg in' "$HOOK2" | head -1)"
  printf '%s' "$first" | grep -q 'dirname "\$_ateh_wcg_self"'
  # and inertness is LOUD IN THE LEDGER — a silent admit is how a gate ships dead
  refute_match "$(grep -A6 'command -v cc_worker_claim_admit' "$HOOK2")" 'echo .*UNGATED.*>&2'
  # jq OBJECT-CONSTRUCTION form, not JSON: the keys are bare in the source (`basis:"absent"`), and a
  # `"basis":"absent"` predicate matches the emitted line but not the file that emits it. Anchored on
  # the gate name so it cannot be satisfied by the capacity term's own absent-row beside it.
  grep -q 'gate:"worker-claim-gate",verdict:"admit",basis:"absent",caller:"agent-tool"' "$HOOK2"
}

@test "13 END-TO-END: the Agent hook actually DENIES a spawn from a session that lacks the lease" {
  # The only case in this suite that RUNS a hook. Cases 09-12 prove the call is present and placed;
  # this proves the whole chain executes — hook -> library -> actuator verdict -> deny JSON. It is
  # the difference the suite header names: a correct decision behind a dead branch is
  # indistinguishable from no decision at all.
  wt="$BATS_TEST_TMPDIR/wt/wt-aaaaaaaaaaaa"; mkdir -p "$wt"
  fake="$BATS_TEST_TMPDIR/fake-backlog"
  cat > "$fake" <<'EOF'
#!/bin/bash
echo "cc-backlog: refused — verdict=noop-live-claimer; aaaaaaaaaaaa is held by Chriss-MacBook-Pro-3-999999, which is LIVE"
exit 4
EOF
  chmod +x "$fake"
  run env CC_WCLAIM_BACKLOG_BIN="$fake" \
      bash -c "printf '%s' '{\"cwd\":\"$wt\",\"session_id\":\"s1\",\"tool_input\":{\"prompt\":\"research the thing\",\"subagent_type\":\"Explore\"}}' | bash '$HOOK2'"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision')" = "deny" ]
  printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecisionReason' | grep -q 'DUPLICATE WORKER'

  # CONTROL 1 — the SAME hook, the SAME payload, with the lease held BY THIS SESSION: must ADMIT.
  # Without this the deny above could be an unconditional refusal of every Agent call in a wt- dir.
  cat > "$fake" <<'EOF'
#!/bin/bash
echo "cc-backlog: verdict=noop-already-ours"
exit 0
EOF
  run env CC_WCLAIM_BACKLOG_BIN="$fake" \
      bash -c "printf '%s' '{\"cwd\":\"$wt\",\"session_id\":\"s1\",\"tool_input\":{\"prompt\":\"research the thing\",\"subagent_type\":\"Explore\"}}' | bash '$HOOK2'"
  [ "$status" -eq 0 ]
  refute_match "$output" 'DUPLICATE WORKER'

  # CONTROL 2 — a session that is NOT in a dispatch worktree is not our population at all, whatever
  # the ledger would have said. This is the forkless not-a-worker branch, and it is the one that
  # keeps the gate off the hot path for every ordinary session on the box.
  cat > "$fake" <<'EOF'
#!/bin/bash
echo "cc-backlog: refused — verdict=noop-live-claimer; held by someone-else, which is LIVE"
exit 4
EOF
  run env CC_WCLAIM_BACKLOG_BIN="$fake" \
      bash -c "printf '%s' '{\"cwd\":\"$BATS_TEST_TMPDIR\",\"session_id\":\"s1\",\"tool_input\":{\"prompt\":\"research the thing\",\"subagent_type\":\"Explore\"}}' | bash '$HOOK2'"
  [ "$status" -eq 0 ]
  refute_match "$output" 'DUPLICATE WORKER'
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
