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

# ── 03b · THE DISPATCHER IS NOT A PEER (backlog b922dde5567b, 2026-08-09) ─────────────────────
# Case 02 above is the control, and the pair is the claim: same live `<host>-<pid>` holder, same
# verb, opposite verdicts, one delta — `--role dispatcher`.
#
# This gate inherits the fix for free because it never re-implements the predicate: it calls
# `cc-backlog reclaim` and branches on the documented verdict (the header's ACTUATOR IS THE ARBITER
# property, paying off). Pinned here anyway, because THIS is where the damage landed — on 2026-08-09
# the gate returned rc 9 on the FIRST Edit of the worker cc-dispatch had just fired for this very
# item, and told it to stand down as a duplicate of its own dispatcher.
@test "03b a LIVE DISPATCHER holder ADMITS the worker — it is a hand-over, not a duplicate" {
  id="$(bash "$CB" add --project /r --title live-dispatcher --source s)"
  bash "$CB" claim "$id" --by "$HOST-$$" --role dispatcher >/dev/null   # alive, by construction
  mkdir -p "$BATS_TEST_TMPDIR/wt-$id"
  export CC_WCLAIM_PID=999999                            # we are the worker it spawned
  run admit "$(wt "$id")"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'ADMIT'
  [ "$(by_of "$id")" = "$HOST-999999" ]                  # and the worker now holds the lease
}

@test "03c ONE-SHOT at the gate: once a worker holds it, the NEXT session is refused as before" {
  # The exemption must not survive the hand-over, or the gate stops protecting the worker it just
  # admitted — which is the storm case 02 exists to prevent, merely deferred by one session.
  id="$(bash "$CB" add --project /r --title oneshot-gate --source s)"
  bash "$CB" claim "$id" --by "$HOST-1" --role dispatcher >/dev/null
  mkdir -p "$BATS_TEST_TMPDIR/wt-$id"
  export CC_WCLAIM_PID=$$                                # worker 1 takes it under a LIVE pid
  run admit "$(wt "$id")"
  [ "$status" -eq 0 ]
  export CC_WCLAIM_PID=999999                            # worker 2 arrives in the same worktree
  run admit "$(wt "$id")"
  [ "$status" -eq 9 ]
  printf '%s' "$output" | grep -q 'REFUSING'
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

# ── 19-22 · THE DONE ARM ───────────────────────────────────────────────────────────────────────
# Why this arm exists (measured 2026-08-07, item 149789b69fc4). The `noop-status` branch used to
# admit open / done / blocked alike, on the stated premise that "`cc-dispatch` owns whether an item
# may be worked, and a done-latch refusal is its rc 4, taken before any spawn". That premise covers
# only workers dispatch SPAWNED. On the day, dispatch fired EXACTLY ONCE and the population arrived
# by Agent-tool fan-out instead — 224 spawns over 3 generations, a path that never consults dispatch
# and so never meets its rc 4. Those workers reached a DONE item, read "not claimed", and were let
# through: 6 rows, basis=no-claim, every one a duplicate. Lifetime record before the fix: 21 admits,
# ZERO refusals. Case 19 is that storm as an executable assertion.
#
# Case 20 is the anti-clog control and matters as much as 19. The finisher's own follow-up writes —
# the commit, the cleanup — must NOT be refused, or the gate locks every worker out of the work it
# just completed and jams the commit path it exists to protect. A refusal that cannot tell the
# finisher from a duplicate is a worse defect than the one being fixed.
item_done_by() { # $1=title $2=holder → id, and makes wt-<id>
  local id; id="$(bash "$CB" add --project /r --title "$1" --source s)"
  bash "$CB" claim "$id" --by "$2" >/dev/null
  # `done` QUOTED: it is a shell keyword, so a bare one reads as a loop terminator and shellcheck
  # says so (SC1010) — the same class as the `local then` trap this library's own cache helper
  # records. It parses today only because no for/while is open; quoting makes the verb literal.
  bash "$CB" "done" "$id" --evidence e >/dev/null
  mkdir -p "$BATS_TEST_TMPDIR/wt-$id"
  printf '%s' "$id"
}

@test "19 a DONE item REFUSES a session that did not finish it (the 149789b69fc4 fan-out)" {
  id="$(item_done_by finished "$HOST-$$")"
  [ "$(by_of "$id")" = "$HOST-$$" ]          # the latch carries `by` — the premise of the whole arm
  export CC_WCLAIM_PID=999999                # a DIFFERENT session, exactly like the 40 duplicates
  run admit "$(wt "$id")"
  [ "$status" -eq 9 ]
  printf '%s' "$output" | grep -q 'REFUSING'
  printf '%s' "$output" | grep -q 'STAND DOWN'
  run cat "$CC_WCLAIM_IDL"
  printf '%s' "$output" | jq -e --arg i "$id" \
    'select(.gate=="worker-claim-gate" and .verdict=="refuse" and .basis=="done-latched" and .item==$i)' >/dev/null
}

@test "20 the FINISHER of a done item is ADMITTED — it must not be locked out of its own commit" {
  id="$(item_done_by mine-finished "$HOST-$$")"
  run admit "$(wt "$id")"                    # same identity that completed it
  [ "$status" -eq 0 ]
  refute_match "$output" 'REFUSING'
}

@test "21 an OPEN item is STILL admitted — the done arm must not widen into eligibility policy" {
  id="$(bash "$CB" add --project /r --title still-open --source s)"
  mkdir -p "$BATS_TEST_TMPDIR/wt-$id"
  export CC_WCLAIM_PID=999999
  run admit "$(wt "$id")"
  [ "$status" -eq 0 ]
  refute_match "$output" 'REFUSING'
}

@test "22 a done item whose holder is UNREADABLE admits — never refuse on a lookup that failed" {
  id="$(item_done_by unreadable "$HOST-$$")"
  export CC_WCLAIM_PID=999999
  printf '#!/bin/bash\ncase "$1" in list) exit 1 ;; esac\nexec %s "$@"\n' "$CB" \
    > "$BATS_TEST_TMPDIR/cb-nolist"; chmod +x "$BATS_TEST_TMPDIR/cb-nolist"
  export CC_WCLAIM_BACKLOG_BIN="$BATS_TEST_TMPDIR/cb-nolist"
  run admit "$(wt "$id")"
  [ "$status" -eq 0 ]
  refute_match "$output" 'REFUSING'
}

# ── 23 · THE SECOND ORACLE'S REFUSAL MUST SURVIVE THE TRIP (backlog f61c1eaaba05) ──────────────
# `cc-backlog reclaim` gained a second oracle: a `<host>-<pid>` incumbent whose pid is spent but
# whose WORKTREE holds another session's process tree keeps the lease, and the ledger says so with a
# NEW token, `verdict=noop-live-worktree`. This gate's `*)` arm is fail-OPEN by design, so a new
# refusal spelling left unwired would be silently upgraded into an ADMIT — the ledger would refuse
# the re-key and the gate would wave the duplicate through anyway, which is strictly worse than not
# adding the oracle at all (memory: new-nonverdict-state-strands-its-consumers).
#
# A STUB producer, deliberately: cc-backlog.bats already pins the oracle end-to-end against real
# occupancy. What is unpinned — and what actually broke in the analogous case this file's test 01
# was written for — is whether the token reaches an executable consumer.
wclaim_stub_verdict() { # $1=verdict line → points the gate's ledger seam at a stub emitting it
  printf '#!/bin/bash\nprintf "%%s\\n" "%s"\n' "$1" > "$BATS_TEST_TMPDIR/stubccb"
  chmod +x "$BATS_TEST_TMPDIR/stubccb"
  export CC_WCLAIM_BACKLOG_BIN="$BATS_TEST_TMPDIR/stubccb"
}

@test "23 a WORKTREE-live incumbent REFUSES — the new token must not fall into the fail-open arm" {
  mkdir -p "$BATS_TEST_TMPDIR/wt-abcdef012345"
  wclaim_stub_verdict "cc-backlog reclaim: verdict=noop-live-worktree abcdef012345 is held by $HOST-$DEADPID, whose process is gone but whose WORKTREE IS LIVE: live process cwd in /w/wt-abcdef012345 belonging to another session (3 proc: 11 22 33)"
  run admit "$BATS_TEST_TMPDIR/wt-abcdef012345"
  [ "$status" -eq 9 ]
  printf '%s' "$output" | grep -q 'REFUSING'
  # The holder is PARSED OUT of the ledger's own sentence, and the sentence differs from
  # noop-live-claimer's ("whose process is gone", not "which is LIVE") — so the extractor is its own
  # and an empty holder here would mean a silently mis-copied pattern.
  printf '%s' "$output" | grep -q "$HOST-$DEADPID"
  refute_match "$output" 'ADMIT'
}

@test "24 that refusal is NEVER cached — it must dissolve the instant the worktree empties" {
  # The admit arm writes a TTL marker; this arm must not, or a worker refused once would stay refused
  # for the whole TTL after the occupying session exited. Behavioural, not a file check: the second
  # evaluation must go back to the ledger and refuse again on its own evidence.
  mkdir -p "$BATS_TEST_TMPDIR/wt-abcdef012346"
  wclaim_stub_verdict "cc-backlog reclaim: verdict=noop-live-worktree abcdef012346 is held by $HOST-$DEADPID, whose process is gone but whose WORKTREE IS LIVE: live process cwd in /w belonging to another session (1 proc: 11)"
  run admit "$BATS_TEST_TMPDIR/wt-abcdef012346"
  [ "$status" -eq 9 ]
  # No TTL marker was minted. Written as a plain assertion, never `… || true`: a check that cannot
  # fail certifies nothing (memory: verification-harness-vacuous-pass-traps). This is the first call
  # in the test, so an entry here could only have come from this refusal.
  [ -z "$(ls -A "$CC_WCLAIM_STATE_DIR" 2>/dev/null || true)" ]
  # …and once the worktree empties, the SAME gate admits — the §9 bound, exercised.
  wclaim_stub_verdict "cc-backlog reclaim: verdict=reclaimed abcdef012346 by $HOST-$$ (was $HOST-$DEADPID)"
  run admit "$BATS_TEST_TMPDIR/wt-abcdef012346"
  [ "$status" -eq 0 ]
}

@test "25 the token has a CONSUMER THAT ACTS in scripts/lib, not just a producer in bin/" {
  # The census test 01 makes for noop-live-claimer, for the token added on top of it. A verdict that
  # exists only in the producer is the exact shape 01 was written after.
  run grep -rl 'noop-live-worktree' "$REPO/scripts/lib"
  [ "$status" -eq 0 ]
  grep -q 'noop-live-worktree' "$REPO/bin/cc-backlog"
  grep -q 'noop-live-worktree' "$REPO/hooks/session-register.sh"
}

# ── the gate must see the worktree from a NESTED cwd ─────────────────────────────
#
# Measured 2026-08-10: item derivation read only the FINAL path component, so
# `wt-<id>` resolved to its item while `wt-<id>/src` resolved to nothing and took the
# NOT-A-WORKER return — admit, no record, no ledger consult. Every duplicate-worker and
# live-incumbent refusal was therefore bypassed for any worker that cd'd into a
# subdirectory, which is the normal case: workers edit under src/, docs/, tests/.
# The pre-existing tests all used the worktree ROOT as cwd, so they stayed green.

@test "nested cwd inside a dispatch worktree still resolves the item" {
  run bash -c '. "$1"; cc_worker_claim_admit probe "$2" edit >/dev/null 2>&1; cc_worker_claim_item' _ "$LIB" "/tmp/x/wt-aaaaaaaaaaaa/src"
  [ "$output" = "aaaaaaaaaaaa" ]
}

@test "deeply nested cwd still resolves the item" {
  run bash -c '. "$1"; cc_worker_claim_admit probe "$2" edit >/dev/null 2>&1; cc_worker_claim_item' _ "$LIB" "/tmp/x/wt-aaaaaaaaaaaa/src/a/b/c"
  [ "$output" = "aaaaaaaaaaaa" ]
}

@test "the worktree ROOT still resolves (no regression)" {
  run bash -c '. "$1"; cc_worker_claim_admit probe "$2" edit >/dev/null 2>&1; cc_worker_claim_item' _ "$LIB" "/tmp/x/wt-aaaaaaaaaaaa"
  [ "$output" = "aaaaaaaaaaaa" ]
}

@test "a non-id worktree name stays out of the population even when nested" {
  run bash -c '. "$1"; cc_worker_claim_admit probe "$2" edit >/dev/null 2>&1; cc_worker_claim_item' _ "$LIB" "/tmp/x/wt-pool-7/src"
  [ "$output" = "" ]
}

@test "an UPPERCASE id is not a dispatch worktree, nested or not" {
  run bash -c '. "$1"; cc_worker_claim_admit probe "$2" edit >/dev/null 2>&1; cc_worker_claim_item' _ "$LIB" "/tmp/x/wt-AAAAAAAAAAAA/src"
  [ "$output" = "" ]
}

@test "an ordinary repo path is never in the population" {
  run bash -c '. "$1"; cc_worker_claim_admit probe "$2" edit >/dev/null 2>&1; cc_worker_claim_item' _ "$LIB" "/Users/x/Development/claude-infrastructure/scripts"
  [ "$output" = "" ]
}

# ── 26-29 · A SUBAGENT MUST NOT TAKE ITS OWN LEAD'S LEASE (backlog 5bb6555f22df) ────────────────
#
# THE INCIDENT, 2026-08-08T01:20:09Z on item 23eccae755a9. A lead spawned two READ-ONLY research
# subagents. A background subagent is a REAL child CC process whose comm is `claude.exe`, so
# `_cc_wclaim_ancestor_pid` stopped on IT, and the gate then called `reclaim` — which is a RE-KEY.
# The subagent won the race for a lease its lead had not yet touched, and the lead's next Write was
# refused as a DUPLICATE WORKER and told to stand down and retire its own pane. ~17 minutes of
# blocked writes, self-released only when the children exited.
#
# WHY THE FIX IS "NEVER CLAIM" RATHER THAN "CLAIM AS THE LEAD". Measured live on CC 2.1.220: a
# background subagent is parented to `bin/cc-pane-runner` under kitty, and the spawning session's pid
# appears NOWHERE in its ancestry. The lineage that a widen-the-identity repair would need does not
# exist in the process tree, so declining the lease is the only reachable remedy.
#
# RED-PROOF (recorded 2026-08-11, against the REAL pre-fix artifact from origin/main, not a mutant):
# case 26 replayed against `git show origin/main:scripts/lib/worker-claim-gate.sh` gives the
# subagent the lease (`by` becomes the agent identity) and then returns rc 9 for the LEAD — the
# incident reproduced exactly. Case 28 is the other direction and fails against a library that
# matches the bare `--agent-id` flag instead of the consistent triple.

# argv of a REAL background subagent, transcribed from the live measurement above.
agent_argv() { # $1=name $2=team → writes an argv file, echoes its path
  local f="$BATS_TEST_TMPDIR/argv.$1"
  printf '%s\n' "/Users/x/.claude-220/node_modules/@anthropic-ai/claude-code/bin/claude.exe --agent-id $1@$2 --agent-name $1 --team-name $2 --agent-color blue --parent-session-id b2da9008-fecf-4ef0-81c9-e0ac56baa061 --agent-type Explore --permission-mode auto --effort high --model claude-opus-5" > "$f"
  printf '%s' "$f"
}

@test "26 a SUBAGENT never takes the lease, so its LEAD is not locked out of its own item" {
  # the spent identity cc-dispatch left behind — a lease nobody live holds yet, which is the state
  # the 2026-08-08 race was run from (the lead had not yet made its first Write).
  id="$(item_claimed_by dispatched "$HOST-$DEADPID")"

  # the lead's read-only subagent writes FIRST. Its pid is $$ — provably alive, so pre-fix this
  # reclaim SUCCEEDS and the theft is real, not hypothetical.
  CC_WCLAIM_ARGV_FILE="$(agent_argv probe session-b2da9008)"; export CC_WCLAIM_ARGV_FILE
  export CC_WCLAIM_PID=$$
  run admit "$(wt "$id")"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'subagent'
  # THE ASSERTION THE WHOLE ITEM IS ABOUT: the lease did not move.
  [ "$(by_of "$id")" = "$HOST-$DEADPID" ]

  # now the LEAD writes. Pre-fix this was rc 9 + "STAND DOWN … retire this pane".
  unset CC_WCLAIM_ARGV_FILE
  export CC_WCLAIM_PID=$PPID
  run admit "$(wt "$id")"
  [ "$status" -eq 0 ]
  [ "$(by_of "$id")" = "$HOST-$PPID" ]
}

@test "27 the subagent admit is RECORDED with its own basis — never a silent bypass" {
  id="$(item_claimed_by recorded "$HOST-$DEADPID")"
  CC_WCLAIM_ARGV_FILE="$(agent_argv probe session-b2da9008)"; export CC_WCLAIM_ARGV_FILE
  run admit "$(wt "$id")"
  [ "$status" -eq 0 ]
  # one row, and it says WHY it was admitted — an admit indistinguishable from a measured one would
  # make this branch invisible to cc-idl and cc-audit (the header's every-branch-records rule).
  [ "$(jq -r 'select(.gate=="worker-claim-gate") | .basis' < "$CC_WCLAIM_IDL" | grep -c '^subagent$')" -eq 1 ]
  [ "$(jq -r 'select(.basis=="subagent") | .item' < "$CC_WCLAIM_IDL")" = "$id" ]
}

@test "28 PROSE is not an agent — a brief that MENTIONS --agent-id must not disarm the gate" {
  # This suite's own subject demonstrates the trap: `ps -o command=` flattens argv, so the brief of
  # the session that fixed this bug carries `--agent-id` as an apparent word (it is in the backlog
  # title). A bare-flag match would read that LEAD as a subagent and skip the lease check entirely.
  # Here the three flags are all present but the record does not agree with itself.
  id="$(item_claimed_by prose "$HOST-$$")"          # a LIVE incumbent, as in case 02
  printf '%s\n' "claude --model claude-opus-5 TASK — gate the claim on NOT being an agent: argv carries --agent-id and --agent-name and --team-name, see backlog" \
    > "$BATS_TEST_TMPDIR/argv.prose"
  export CC_WCLAIM_ARGV_FILE="$BATS_TEST_TMPDIR/argv.prose"
  export CC_WCLAIM_PID=999999                        # a DIFFERENT session, exactly as case 02
  run admit "$(wt "$id")"
  [ "$status" -eq 9 ]                                # still refused: prose bought nothing
  [ "$(by_of "$id")" = "$HOST-$$" ]

  # and the same with a consistent-looking pair but a mismatched team — co-presence is not identity
  printf '%s\n' "claude.exe --agent-id probe@session-aaa --agent-name probe --team-name session-bbb" \
    > "$BATS_TEST_TMPDIR/argv.mixed"
  export CC_WCLAIM_ARGV_FILE="$BATS_TEST_TMPDIR/argv.mixed"
  run admit "$(wt "$id")"
  [ "$status" -eq 9 ]
}

@test "29 the agent discriminator is at PARITY with hooks/lib/agent-identity.sh's rule" {
  # Duplicated rather than shared — the same treatment the identity derivation gets (case 14), for
  # the reasons in the library header. Duplication is only safe while a divergence goes RED.
  AID="$REPO/hooks/lib/agent-identity.sh"
  [ -f "$AID" ]
  for flag in ' --agent-id ' ' --agent-name ' ' --team-name '; do
    grep -q -- "$flag" "$LIB"
    grep -q -- "$flag" "$AID"
  done
  # BOTH must require the record to agree with itself, not merely carry the three flags.
  grep -q 'nm@\$tm' "$LIB"
  grep -q 'substr(id, 1, at - 1) == nm' "$AID"
}
