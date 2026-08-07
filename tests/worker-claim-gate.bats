#!/usr/bin/env bats
# scripts/lib/worker-claim-gate.sh — carrying a REFUSED claim into the refused worker's BEHAVIOUR
# (backlog 18323346082a).
#
# THE DEFECT THIS SUITE EXISTS TO KEEP FIXED. On 2026-08-07 eight sessions came up in one worktree
# for item 191d4d056c98. cc-dispatch fired ONCE; seven sessions each logged
# `disposition:"noop", reason:"incumbent live"` between 10:41:46Z and 10:44:27Z — and each then did
# the whole item anyway. The ledger's lease was never wrong; it simply had no consumer that ACTED.
# A census of the executable tree found `noop-live-claimer` in exactly three places: the producer
# (bin/cc-backlog:1034), one IDL line (hooks/session-register.sh:220), and two tests asserting the
# string appears. Case 01 is that census as an executable assertion.
#
# WHY THE REAL cc-backlog, NOT A STUB. The gate's whole correctness rests on a round trip: the
# identity it writes (`<host>-<durable claude pid>`) must be the identity cc-backlog's `claimer_live`
# resolves via its cheap `kill -0` path (bin/cc-backlog:1307-1312). A stub would assert the two
# halves agree with the stub, not with each other — and two independently-correct halves that
# disagree on the host spelling yield a claim resolving as PROVEN DEAD, which is worse than no gate
# at all (memory `output-must-round-trip-into-input`). Cases 02/03/14 are that round trip.
#
# WHY CASE 13 IS THE LOAD-BEARING ONE. The sibling library scripts/lib/capacity-admit.sh carries
# CC_ADMIT_BUDGET: after N consecutive refusals it ADMITS and pages, because §9's law forbids an
# unbounded gate on an actuation path. Copying that here would MINT the second worker this file
# exists to prevent — the unsafe direction is inverted between a transient machine state and a
# standing fact about a live lease. Case 13 pins the absence of a budget, so a future reader
# "restoring parity" with capacity-admit goes RED instead of re-creating the 2026-08-07 storm.
#
# RED-PROOF (recorded 2026-08-07): case 01 is the pre-fix control and fails against a tree where the
# gate is not wired; every REFUSE case was re-run with CC_WCLAIM_GATE=off and returned 0 instead of
# 9; case 13 was re-run with a mutated library carrying a 2-refusal budget and went RED on the third
# call, confirming it can observe the regression it names. A control that cannot fail proves nothing.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LIB="$REPO/scripts/lib/worker-claim-gate.sh"
  HOOK="$REPO/hooks/check-edit-boundary.sh"
  CB="$REPO/bin/cc-backlog"
  # HERMETIC $HOME (enforced by scripts/test-hermeticity-lint.sh). The library falls back to $HOME
  # for its IDL, its cache dir and its cc-backlog resolution, so an unfixtured run would read and
  # write the operator's live ~/.claude/autonomy. Every seam is also set explicitly; $HOME is the
  # backstop that catches the one someone forgets to override later.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_WCLAIM_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_WCLAIM_STATE_DIR="$BATS_TEST_TMPDIR/state"
  # The registry oracle: EMPTY, so no session-shaped claimer is ever live and the pid path is the
  # only thing that can absolve — the isolation every verdict below depends on.
  printf '#!/bin/bash\necho "[]"\n' > "$BATS_TEST_TMPDIR/nosess"; chmod +x "$BATS_TEST_TMPDIR/nosess"
  export CC_BACKLOG_SESSIONS_BIN="$BATS_TEST_TMPDIR/nosess"
  HOST="$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo localhost)"
  DEADPID=2147483647
  # The gate derives its own pid by walking for a `claude` ancestor; under bats there is none, so it
  # would fall back to $PPID and every case would race the harness. CC_WCLAIM_PID/HOST make the
  # identity an INPUT. Case 14 pins the real derivation separately, so these overrides cannot hide a
  # walk that stopped working.
  export CC_WCLAIM_HOST="$HOST"
  export CC_WCLAIM_PID=$$
  export CC_WCLAIM_BACKLOG_BIN="$CB"
}

# NEGATIVE assertions must NOT be written `! cmd`: bash exempts a `!`-inverted command from set -e,
# so such a line only fails the test when it is the LAST line of the body. These return non-zero.
refute_match()   { [ "$(printf '%s' "$1" | grep -c "$2")" -eq 0 ]; }
refute_in_file() { [ ! -s "$2" ] || [ "$(grep -c "$1" "$2")" -eq 0 ]; }

# Run ONE evaluation in a fresh subshell. The subshell's rc IS the gate's rc — deliberately the last
# statement. An earlier draft ended with `cc_worker_claim_reason`, whose own 0 masks every REFUSE,
# and the rc-9 assertions passed against rc 0 until they were run (the identical trap recorded in
# tests/capacity-admit.bats). Reason goes to stdout so a case can assert on both.
admit() { # $1=cwd [$2=what] → prints reason, exits with the gate's rc
  bash -c '. "$1"; cc_worker_claim_admit test-caller "$2" "$3"; rc=$?; cc_worker_claim_reason; exit $rc' \
    _ "$LIB" "$1" "${2:-write}"
}

# a dispatched item claimed the way cc-dispatch claims it, with a caller-chosen holder.
item_claimed_by() { # $1=title $2=holder → id, and makes wt-<id>
  local id; id="$(bash "$CB" add --project /r --title "$1" --source s)"
  bash "$CB" claim "$id" --by "$2" >/dev/null
  mkdir -p "$BATS_TEST_TMPDIR/wt-$id"
  printf '%s' "$id"
}
wt() { printf '%s/wt-%s' "$BATS_TEST_TMPDIR" "$1"; }
by_of() { bash "$CB" list --all --json | jq -r --arg i "$1" '.[]|select(.id==$i)|.by'; }

# ── 01 · THE CENSUS — the pre-fix control, stated as an assertion ─────────────────────────────
@test "01 the refusal has a CONSUMER THAT ACTS, not just a journal line" {
  # Before this change `noop-live-claimer` appeared in the tree only as a producer, one IDL write,
  # and two string assertions. This asserts an executable consumer exists AND that it can refuse.
  run grep -rl 'noop-live-claimer' "$REPO/scripts/lib"
  [ "$status" -eq 0 ]
  # and the consumer must actually return the refusal code, not merely mention the token
  grep -q 'return 9' "$LIB"
}

# ── 02-03 · the two states that matter, through the REAL ledger ───────────────────────────────
@test "02 a LIVE incumbent REFUSES this session's write (the 2026-08-07 storm, prevented)" {
  id="$(item_claimed_by live-incumbent "$HOST-$$")"      # the test's own pid: provably alive
  export CC_WCLAIM_PID=999999                            # we are a DIFFERENT session
  run admit "$(wt "$id")"
  [ "$status" -eq 9 ]
  printf '%s' "$output" | grep -q 'REFUSING'
  # and it did NOT steal the claim — the incumbent still owns it
  [ "$(by_of "$id")" = "$HOST-$$" ]
}

@test "03 the session that HOLDS the claim is admitted (the incumbent must keep working)" {
  id="$(item_claimed_by mine "$HOST-$$")"
  run admit "$(wt "$id")"
  [ "$status" -eq 0 ]
  [ "$(by_of "$id")" = "$HOST-$$" ]
}

@test "04 a DEAD incumbent is reclaimed and the write proceeds (self-healing, no operator step)" {
  id="$(item_claimed_by dead-incumbent "$HOST-$DEADPID")"
  run admit "$(wt "$id")"
  [ "$status" -eq 0 ]
  [ "$(by_of "$id")" = "$HOST-$$" ]                      # re-keyed to us
}

@test "05 an item carrying NO claim is admitted — this gate arbitrates leases, not eligibility" {
  id="$(bash "$CB" add --project /r --title unclaimed --source s)"
  mkdir -p "$(wt "$id")"
  run admit "$(wt "$id")"
  [ "$status" -eq 0 ]
  run cat "$CC_WCLAIM_IDL"
  printf '%s' "$output" | jq -e 'select(.basis=="no-claim")' >/dev/null
}

# ── 06-07 · the population boundary: this runs on EVERY write on the box ──────────────────────
@test "06 NOT a dispatch worktree: admitted with NO ledger call and NO IDL row" {
  # A row per write would flood the IDL that cc-idl and cc-audit read; an alarm that always fires
  # carries the same zero bits as one that cannot. The recorder proves zero forks to cc-backlog.
  rec="$BATS_TEST_TMPDIR/rec"; : > "$rec"
  cat > "$BATS_TEST_TMPDIR/cbrec" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$rec"
exec "$CB" "\$@"
EOF
  chmod +x "$BATS_TEST_TMPDIR/cbrec"
  export CC_WCLAIM_BACKLOG_BIN="$BATS_TEST_TMPDIR/cbrec"
  mkdir -p "$BATS_TEST_TMPDIR/ordinary-project"
  run admit "$BATS_TEST_TMPDIR/ordinary-project"
  [ "$status" -eq 0 ]
  [ ! -s "$rec" ]
  refute_in_file 'worker-claim-gate' "$CC_WCLAIM_IDL"
}

@test "07 a wt-<name> that is not a 12-hex id is ignored (wt-pool-7, wt-feature-x, wt-<11hex>)" {
  for bad in wt-pool-7 wt-feature-x wt-abcdef01234 wt-ABCDEF012345; do
    mkdir -p "$BATS_TEST_TMPDIR/$bad"
    run admit "$BATS_TEST_TMPDIR/$bad"
    [ "$status" -eq 0 ]
  done
  refute_in_file 'worker-claim-gate' "$CC_WCLAIM_IDL"
}

# ── 08-10 · a gate must never convict on its own bad wiring ───────────────────────────────────
@test "08 FAIL-OPEN: an unresolvable cc-backlog admits and NAMES the cause" {
  id="$(item_claimed_by no-bin "$HOST-$$")"
  export CC_WCLAIM_BACKLOG_BIN="$BATS_TEST_TMPDIR/nope"
  run admit "$(wt "$id")"
  [ "$status" -eq 0 ]
  run cat "$CC_WCLAIM_IDL"
  printf '%s' "$output" | jq -e 'select(.basis=="fail-open" and (.detail|test("not resolvable")))' >/dev/null
}

@test "09 FAIL-OPEN: unparsed reclaim output admits — an unreadable oracle is not evidence" {
  id="$(item_claimed_by garbled "$HOST-$$")"
  printf '#!/bin/bash\necho "something else entirely"\n' > "$BATS_TEST_TMPDIR/garble"
  chmod +x "$BATS_TEST_TMPDIR/garble"
  export CC_WCLAIM_BACKLOG_BIN="$BATS_TEST_TMPDIR/garble"
  run admit "$(wt "$id")"
  [ "$status" -eq 0 ]
  run cat "$CC_WCLAIM_IDL"
  printf '%s' "$output" | jq -e 'select(.basis=="fail-open" and (.detail|test("unparsed")))' >/dev/null
}

@test "10 the OFF switch admits and is RECORDED — an override must not read back as a healthy admit" {
  id="$(item_claimed_by off-switch "$HOST-$$")"
  export CC_WCLAIM_PID=999999
  run env CC_WCLAIM_GATE=off bash -c '. "$1"; cc_worker_claim_admit c "$2" w; exit $?' _ "$LIB" "$(wt "$id")"
  [ "$status" -eq 0 ]
  run cat "$CC_WCLAIM_IDL"
  printf '%s' "$output" | jq -e 'select(.basis=="gate-off")' >/dev/null
}

# ── 11-12 · the cache asymmetry: admits cached, refusals NEVER ────────────────────────────────
@test "11 an ADMIT is cached — the incumbent does not pay a ledger fork on every write" {
  id="$(item_claimed_by cached "$HOST-$$")"
  rec="$BATS_TEST_TMPDIR/rec2"; : > "$rec"
  cat > "$BATS_TEST_TMPDIR/cbrec2" <<EOF
#!/bin/bash
printf 'call\n' >> "$rec"
exec "$CB" "\$@"
EOF
  chmod +x "$BATS_TEST_TMPDIR/cbrec2"
  export CC_WCLAIM_BACKLOG_BIN="$BATS_TEST_TMPDIR/cbrec2"
  admit "$(wt "$id")" >/dev/null
  admit "$(wt "$id")" >/dev/null
  admit "$(wt "$id")" >/dev/null
  [ "$(grep -c call "$rec")" -eq 1 ]
}

@test "12 a REFUSAL is NEVER cached — it must dissolve the instant the incumbent dies" {
  id="$(item_claimed_by not-cached "$HOST-$$")"
  export CC_WCLAIM_PID=999999
  run admit "$(wt "$id")"; [ "$status" -eq 9 ]
  # the incumbent dies: re-key the ledger to a dead pid, and the very next evaluation must ADMIT
  bash "$CB" reopen "$id" --force >/dev/null 2>&1 || true
  bash "$CB" claim "$id" --by "$HOST-$DEADPID" --force >/dev/null 2>&1 \
    || bash "$CB" claim "$id" --by "$HOST-$DEADPID" >/dev/null
  run admit "$(wt "$id")"
  [ "$status" -eq 0 ]
}

# ── 13 · THE LOAD-BEARING CASE: there is no refusal budget, and there must not be ──────────────
@test "13 NO BUDGET — the Nth consecutive refusal is still a refusal (never capacity-admit's shape)" {
  # capacity-admit ADMITS after CC_ADMIT_BUDGET consecutive refusals, because a transient machine
  # state must not become a permanent outage. Here the refusal denies a FACT about a live lease, so
  # admitting on expiry mints the second worker. Ten is well past any plausible budget default.
  id="$(item_claimed_by no-budget "$HOST-$$")"
  export CC_WCLAIM_PID=999999
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    run admit "$(wt "$id")"
    [ "$status" -eq 9 ]
  done
  # and the incumbent still owns it after ten refusals
  [ "$(by_of "$id")" = "$HOST-$$" ]
  # the library must carry no budget vocabulary at all — a grep control, so adding one goes RED here
  refute_match "$(cat "$LIB")" 'budget-expired'
}

# ── 14 · IDENTITY PARITY — the round trip this gate's correctness rests on ────────────────────
@test "14 the identity derivation is byte-identical to hooks/session-register.sh's" {
  # The two are DUPLICATED deliberately (session-register is a hot SessionStart hook whose structure
  # is load-bearing), so they are pinned equal here instead — the same treatment the capacity
  # ceilings get in tests/capacity-admit-parity.bats. A host spelling that drifts on one side yields
  # a claim resolving PROVEN DEAD, which is worse than no gate.
  a="$(sed -n '/claude_ancestor_pid()/,/^}/p'      "$REPO/hooks/session-register.sh" | grep -v '^claude_ancestor_pid')"
  b="$(sed -n '/_cc_wclaim_ancestor_pid()/,/^}/p'  "$LIB"                            | grep -v '^_cc_wclaim_ancestor_pid')"
  [ -n "$a" ]; [ -n "$b" ]
  [ "$a" = "$b" ]
  # and the host derivation, which is the half that actually bit in the referenced incident
  grep -q 'hostname -s 2>/dev/null || hostname 2>/dev/null || echo localhost' "$LIB"
  grep -q 'hostname -s 2>/dev/null || hostname 2>/dev/null || echo localhost' "$REPO/hooks/session-register.sh"
}

# ── 15-17 · the actual PreToolUse contract, through the real hook ─────────────────────────────
# Asserted on the hook's OUTPUT, never on the library's report of itself: the deny is a JSON
# document Claude Code parses, and a library that refuses while the hook emits nothing is exactly
# the advisory shape this whole change exists to remove.
fire_hook() { # $1=cwd $2=file_path → the hook's stdout
  printf '{"cwd":"%s","session_id":"deadbeef-0000-0000-0000-000000000000","tool_name":"Write","tool_input":{"file_path":"%s"}}' \
    "$1" "$2" | command /bin/bash "$HOOK" 3>&-
}

@test "15 the hook DENIES a duplicate's write in the real PreToolUse schema" {
  id="$(item_claimed_by hook-deny "$HOST-$$")"
  export CC_WCLAIM_PID=999999
  run fire_hook "$(wt "$id")" "$(wt "$id")/x.md"
  [ "$status" -eq 0 ]                                   # a PreToolUse hook must always exit 0
  printf '%s' "$output" | jq -e '.hookSpecificOutput.permissionDecision=="deny"' >/dev/null
  printf '%s' "$output" | jq -e '.hookSpecificOutput.hookEventName=="PreToolUse"' >/dev/null
  # the reason must tell the agent what to DO, not merely that it was refused
  printf '%s' "$output" | jq -e '.hookSpecificOutput.permissionDecisionReason|test("self-close")' >/dev/null
  printf '%s' "$output" | jq -e '.hookSpecificOutput.permissionDecisionReason|test("DO NOT retry")' >/dev/null
}

@test "16 the hook ADMITS the claim-holder's write (no output at all)" {
  id="$(item_claimed_by hook-allow "$HOST-$$")"
  run fire_hook "$(wt "$id")" "$(wt "$id")/x.md"
  [ "$status" -eq 0 ]
  refute_match "$output" 'deny'
}

@test "17 an ABSENT library must not disarm the hook's freeze/focus boundary" {
  # The gate is an addition to a hook that already enforces something. A missing library must fall
  # through, never exit — the 24c lesson from tests/capacity-admit-coverage.bats.
  mkdir -p "$BATS_TEST_TMPDIR/frozen" "$HOME/.claude"
  # Written through the hook's OWN `set` CLI, not by hand: it resolves each path with `pwd -P`, and
  # on macOS /tmp is a symlink to /private/tmp — a hand-written state file records the unresolved
  # spelling, the hook resolves the incoming path, and the prefix match silently misses. The fixture
  # would then pass for the wrong reason on any box where the two agree (memory
  # `control-must-replay-the-real-artifact`).
  bash "$HOOK" set freeze "$BATS_TEST_TMPDIR/frozen" >/dev/null
  frozen_real="$(cd "$BATS_TEST_TMPDIR/frozen" && pwd -P)"
  fake="$BATS_TEST_TMPDIR/fakehooks"; mkdir -p "$fake"
  cp "$HOOK" "$fake/check-edit-boundary.sh"            # a copy whose ../scripts/lib does not exist
  run bash -c 'printf "{\"cwd\":\"$1\",\"tool_input\":{\"file_path\":\"$2\"}}" | command /bin/bash "$3" 3>&-' \
    _ "$BATS_TEST_TMPDIR" "$frozen_real/f.md" "$fake/check-edit-boundary.sh"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.hookSpecificOutput.permissionDecision=="deny"' >/dev/null
  printf '%s' "$output" | jq -e '.hookSpecificOutput.permissionDecisionReason|test("edit-boundary")' >/dev/null
}

# ── 18 · the record, so a silent no-op cannot be told from an inert mechanism ──────────────────
@test "18 a refusal is journalled with the item AND the incumbent it names" {
  id="$(item_claimed_by journalled "$HOST-$$")"
  export CC_WCLAIM_PID=999999
  run admit "$(wt "$id")"; [ "$status" -eq 9 ]
  run cat "$CC_WCLAIM_IDL"
  printf '%s' "$output" | jq -e --arg i "$id" --arg h "$HOST-$$" \
    'select(.gate=="worker-claim-gate" and .verdict=="refuse" and .item==$i and .holder==$h)' >/dev/null
}
