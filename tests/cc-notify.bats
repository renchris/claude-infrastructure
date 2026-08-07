#!/usr/bin/env bats
# cc-notify (v2) — the NON-KEYSTROKE transport. Proves cc-notify ENQUEUES to the target's inbox
# (~/.claude/mailbox/<uuid>.md) and NEVER calls it2 `session send` (the v1 keystroke path that raced the
# user's live input — the exact bug v2 removes). Liveness decides the honest exit verdict cc-announce
# trusts: a LIVE session → "delivered to inbox"; a NOT-live target → "mailbox only"; unresolvable → 3;
# unwritable inbox → 5. Isolated via CC_REGISTRY_DIR / CC_MAILBOX_DIR and an IT2_BIN stub.
#
# Harness rules (learned from real escapes, v1 suite):
#   1. `|| false` on EVERY bare [[ ]] — bats does not trap a bare [[ ]] failure mid-body.
#   2. Assert the SPECIFIC verdict string, never a loose glob a degraded result also matches.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  NOTIFY="$REPO/bin/cc-notify"
  # Fixture $HOME FILE-WIDE (2026-08-08, landed with the --cloud arm). Five tests below already did
  # this per-test, which is precisely the shape the hermeticity ratchet names as insufficient: it
  # leaves every OTHER test resolving cc-notify's $HOME-rooted defaults — the mailbox, the roles dir,
  # the comms-alarm store, and now the cc-cloud declaration store — against the operator's live ~/.
  # The per-test lines stay where they are (harmless, and they document the intent at the tests that
  # most depend on it); this makes the property hold for the file.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg"
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mbox"
  export IT2_LOG="$BATS_TEST_TMPDIR/it2.log"
  # THE LEAK THIS SUITE WAS (backlog 817faf3a4968). This was set per-test at the F4 test only, so the
  # other two inbox-unwritable tests below wrote their alarm records into the operator's LIVE
  # ~/.claude/autonomy/comms-alarms. Measured 2026-07-29: 510 of the store's 511 enqueue-fail records
  # were this suite's, 40% of the whole store, and cc-inbox-guard phoned the operator once per record.
  # It belongs in setup() for the reason the $HOME ratchet gives: per-test does not count, it leaves
  # every OTHER test in the file pointed at live state.
  export CC_COMMS_ALARM_DIR="$BATS_TEST_TMPDIR/comms-alarms"
  mkdir -p "$CC_REGISTRY_DIR" "$CC_MAILBOX_DIR"

  UUID="AAAAAAAA-1111-2222-3333-444444444444"
  # a LIVE registered peer: pid=$$ (this test proc, kill -0 succeeds) + the it2 stub lists its pane.
  printf '{"paneUUID":"%s","name":"peer","cwd":"/tmp","account":"next","pid":%s,"startedAt":1}' \
    "$UUID" "$$" > "$CC_REGISTRY_DIR/$UUID.json"

  # it2 stub: `session list --json` → the live pane set (peer UUID); `session send` → LOG it, so a test
  # can assert it is NEVER called. cc-notify v2 must only ever use `session list` (read-only), never send.
  STUB="$BATS_TEST_TMPDIR/it2"
  cat > "$STUB" <<SH
#!/bin/bash
if [ "\$1" = "session" ] && [ "\$2" = "list" ]; then
  printf '[{"id":"%s"}]\n' "$UUID"; exit 0
fi
if [ "\$1" = "session" ] && [ "\$2" = "send" ]; then
  printf 'SEND %s\n' "\$*" >> "$IT2_LOG"; exit 0
fi
exit 0
SH
  chmod +x "$STUB"
  export IT2_BIN="$STUB"

  # ── OFF-BOX (--cloud) fixtures — docs/plans/CLOUD_OBSERVABILITY.md §9.2 ─────────────────────────
  export CC_CLOUD_STATE="$BATS_TEST_TMPDIR/cloud"
  # The REAL bin/cc-cloud, deliberately NOT a stub: the whole first step of §9.2 is a join against
  # cc-cloud's declaration store (declared AND not retired), and a stub would test the stub. The
  # store itself is fixtured above, so this touches nothing live.
  export CC_CLOUD_BIN="$REPO/bin/cc-cloud"

  # `claude` STUB. The real binary would spend the operator's quota AND fire a message at a live
  # session, so no test in this file may ever reach it. Its answer is file-driven (out/err/rc under
  # $STUB_DIR) so a test can pose ANY of the API's answers without re-writing the stub.
  export STUB_DIR="$BATS_TEST_TMPDIR/stub"; mkdir -p "$STUB_DIR"
  export CLOUD_LOG="$BATS_TEST_TMPDIR/claude.log"
  CLAUDE_STUB="$BATS_TEST_TMPDIR/claude"
  cat > "$CLAUDE_STUB" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >> "$CLOUD_LOG"
[ -f "$STUB_DIR/out" ] && cat "$STUB_DIR/out"
[ -f "$STUB_DIR/err" ] && cat "$STUB_DIR/err" >&2
exit "$(cat "$STUB_DIR/rc" 2>/dev/null || echo 0)"
SH
  chmod +x "$CLAUDE_STUB"
  export CC_CLAUDE_BIN="$CLAUDE_STUB"
  # The default answer is the one MEASURED against a live session on 2026-08-08 (no pty, stdin
  # closed) — the fixture is the observed artifact, not an invented shape.
  printf '{"ok":true,"session_id":"session_01CHQoFxvsoDQ9KgJFSLrKno","url":"https://claude.ai/code/session_01CHQoFxvsoDQ9KgJFSLrKno"}\n' > "$STUB_DIR/out"

  CLOUD_ID="session_01CHQoFxvsoDQ9KgJFSLrKno"

  # Answer poser: cloud_answer <stdout> [stderr] [rc]
  cloud_answer() {
    printf '%s\n' "$1" > "$STUB_DIR/out"
    printf '%s' "${2:-}" > "$STUB_DIR/err"
    printf '%s' "${3:-0}" > "$STUB_DIR/rc"
  }
  # A declaration, made WITHOUT touching the network: --repo points at a non-repo, so cc-cloud's
  # `git ls-remote` baseline probe fails fast and the declaration is still written (that is its
  # documented behaviour — an unmeasured baseline beats an unobservable session).
  declare_cloud() { "$REPO/bin/cc-cloud" declare --id "${1:-$CLOUD_ID}" --branch cf-wave-c --repo "$BATS_TEST_TMPDIR/not-a-repo" >/dev/null 2>&1; }
  retire_cloud()  { "$REPO/bin/cc-cloud" retire  --id "${1:-$CLOUD_ID}" >/dev/null 2>&1; }
  cloud_calls()   { if [ -f "$CLOUD_LOG" ]; then grep -c . "$CLOUD_LOG"; else echo 0; fi; }
}

sent_count() { if [ -f "$IT2_LOG" ]; then grep -c '^SEND' "$IT2_LOG"; else echo 0; fi; }

@test "resolves a friendly NAME to a LIVE session → 'delivered to inbox', enqueues, NO keystroke" {
  run "$NOTIFY" peer "hello world"
  [ "$status" -eq 0 ]
  [[ "$output" == *"delivered to inbox"* ]] || false
  grep -q '\] hello world' "$CC_MAILBOX_DIR/$UUID.md"   # line is "<iso> [<sender>] hello world"
  [ "$(sent_count)" -eq 0 ]     # THE anti-keystroke invariant: session send was NEVER called
}

@test "raw pane UUID of a live pane passes through and enqueues" {
  run "$NOTIFY" "$UUID" "ping"
  [ "$status" -eq 0 ]
  [[ "$output" == *"delivered to inbox"* ]] || false
  grep -q '\] ping' "$CC_MAILBOX_DIR/$UUID.md"
  [ "$(sent_count)" -eq 0 ]
}

@test "NOT-live target (it2 lists no such pane, no registry row) → 'mailbox only', exit 0, still enqueued" {
  DEAD="DDDDDDDD-9999-8888-7777-666666666666"
  run "$NOTIFY" "$DEAD" "to a closed pane"
  [ "$status" -eq 0 ]
  [[ "$output" == *"mailbox only"* ]] || false
  [[ "$output" == *"NOT a live session"* ]] || false
  grep -q '\] to a closed pane' "$CC_MAILBOX_DIR/$DEAD.md"   # recorded even though not-live
  [ "$(sent_count)" -eq 0 ]
}

@test "liveness UNVERIFIABLE (it2 errors) → recorded degrade, exit 0, enqueued" {
  # break it2 so `session list` errors → liveness oracle unavailable → unknown, never a false not-live.
  printf '#!/bin/bash\nexit 1\n' > "$IT2_BIN"
  GHOST="EEEEEEEE-9999-8888-7777-666666666666"
  run "$NOTIFY" "$GHOST" "maybe live"
  [ "$status" -eq 0 ]
  [[ "$output" == *"UNVERIFIABLE"* ]] || false
  grep -q '\] maybe live' "$CC_MAILBOX_DIR/$GHOST.md"
}

@test "wake-path: a fresh .watching heartbeat → 'wake-path armed'; its absence → 'NO watcher armed' (F5)" {
  # no watcher armed → delivered but not a guaranteed wake
  run "$NOTIFY" "$UUID" "no watcher"
  [[ "$output" == *"NO watcher armed"* ]] || false
  # arm a fresh watcher heartbeat → wake-path armed (VERIFIED-worthy for cc-announce)
  : > "$CC_MAILBOX_DIR/$UUID.watching"
  run "$NOTIFY" "$UUID" "with watcher"
  [[ "$output" == *"wake-path armed"* ]] || false
}

@test "F4: inbox-unwritable self-escalates — a durable alarm record is written even though exit is swallowed" {
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/ro/deeper"
  export CC_COMMS_ALARM_DIR="$BATS_TEST_TMPDIR/comms-alarms"
  mkdir -p "$BATS_TEST_TMPDIR/ro"; chmod 500 "$BATS_TEST_TMPDIR/ro"
  run "$NOTIFY" "$UUID" "cannot persist"
  chmod 700 "$BATS_TEST_TMPDIR/ro"
  [ "$status" -eq 5 ]
  # the loud path does NOT depend on the mailbox it reports as broken — an alarm lands in a DIFFERENT dir
  [ -n "$(find "$CC_COMMS_ALARM_DIR" -name 'enqueue-fail-*.json' 2>/dev/null)" ]
}

@test "ALWAYS enqueues on success (the inbox is the durable transport, not a fallback)" {
  run "$NOTIFY" peer "durable record"
  [ "$status" -eq 0 ]
  [ -f "$CC_MAILBOX_DIR/$UUID.md" ]
  grep -q 'durable record' "$CC_MAILBOX_DIR/$UUID.md"
}

@test "unresolvable target → exit 3, no mailbox (unknown name, not a UUID)" {
  run "$NOTIFY" "not-a-name-or-uuid" "x"
  [ "$status" -eq 3 ]
  [ ! -f "$CC_MAILBOX_DIR/not-a-name-or-uuid.md" ]
}

@test "missing message (non-self target) → usage error exit 2" {
  run "$NOTIFY" peer
  [ "$status" -eq 2 ]
}

@test "inbox UNWRITABLE → exit 5 LOUD (a message that cannot persist is not delivered)" {
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/ro/deeper"
  mkdir -p "$BATS_TEST_TMPDIR/ro"; chmod 500 "$BATS_TEST_TMPDIR/ro"
  run "$NOTIFY" "$UUID" "cannot persist"
  chmod 700 "$BATS_TEST_TMPDIR/ro"     # restore for teardown
  [ "$status" -eq 5 ]
  [[ "$output" == *"FAILED to write inbox"* ]] || false
}

@test "--self prints own pane UUID and exits (no message)" {
  export ITERM_SESSION_ID="w0t0p0:$UUID"
  run "$NOTIFY" --self
  [ "$status" -eq 0 ]
  [ "$output" = "$UUID" ]
}

@test "--self <msg> enqueues into own inbox (self is always live)" {
  export ITERM_SESSION_ID="w0t0p0:$UUID"
  run "$NOTIFY" --self "note to self"
  [ "$status" -eq 0 ]
  grep -q 'note to self' "$CC_MAILBOX_DIR/$UUID.md"
  [ "$(sent_count)" -eq 0 ]
}

@test "--from attribution appears in the inbox line" {
  run "$NOTIFY" --from reaper "$UUID" "surface page"
  [ "$status" -eq 0 ]
  grep -q '\[reaper\] surface page' "$CC_MAILBOX_DIR/$UUID.md"
}

@test "--mailbox-only records but reports inbox-only, exit 0" {
  run "$NOTIFY" --mailbox-only "$UUID" "record only"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--mailbox-only"* ]] || false
  grep -q 'record only' "$CC_MAILBOX_DIR/$UUID.md"
  [ "$(sent_count)" -eq 0 ]
}

@test "a message with embedded newlines is collapsed to ONE inbox line (cursor invariant)" {
  run "$NOTIFY" "$UUID" "$(printf 'line-a\nline-b\nline-c')"
  [ "$status" -eq 0 ]
  # exactly ONE line was appended (one message = one line, so the .seen cursor counts messages)
  [ "$(grep -c '' "$CC_MAILBOX_DIR/$UUID.md")" -eq 1 ]
  grep -q 'line-a line-b line-c' "$CC_MAILBOX_DIR/$UUID.md"
}

@test "delivery-survives-busy-pane: a busy / bash-prompt pane still gets the message (mailbox → context, never keystrokes)" {
  # 'busy' is IRRELEVANT to delivery — there is no keystroke to race. cc-notify enqueues regardless of what
  # the pane is doing (mid-command, at a bash prompt, user actively typing) and touches NO composer.
  run "$NOTIFY" "$UUID" "reaper page while you were mid-command"
  [ "$status" -eq 0 ]
  grep -q 'reaper page while you were mid-command' "$CC_MAILBOX_DIR/$UUID.md"
  [ "$(sent_count)" -eq 0 ]     # zero keystrokes → nothing to corrupt / mis-run on the busy pane
  # and the drain surfaces it as CONTEXT at the next SAFE boundary — never as a command on the bash line.
  local drain="$REPO/hooks/mailbox-drain.sh" out
  out="$(ITERM_SESSION_ID="w0t0p0:$UUID" bash -c 'echo "{}" | "$0" prompt' "$drain")"
  printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext' | grep -q 'reaper page while you were mid-command'
}

@test "cc-notify NEVER invokes the keystroke transport across ALL send paths" {
  "$NOTIFY" peer "one" >/dev/null 2>&1
  "$NOTIFY" "$UUID" "two" >/dev/null 2>&1
  "$NOTIFY" --from x "$UUID" "three" >/dev/null 2>&1
  export ITERM_SESSION_ID="w0t0p0:$UUID"; "$NOTIFY" --self "four" >/dev/null 2>&1
  [ "$(sent_count)" -eq 0 ]     # zero it2 `session send` across name/uuid/from/self — no keystrokes, ever
}

# ── v3 ADDRESSING: --role · forward chains · dead-target reroute (D1/D2/D3) ───────────────────────
# These pin the class that lost ~78% of all mail ever sent: an address frozen at producer start-up,
# a pane that recycled out from under it, and a "success" exit that looped for three days.

@test "--role resolves the role file at SEND time (not a snapshot) and enqueues to that pane" {
  export CC_ROLES_DIR="$BATS_TEST_TMPDIR/roles"; mkdir -p "$CC_ROLES_DIR"
  printf '%s\n' "$UUID" > "$CC_ROLES_DIR/desk"
  run "$NOTIFY" --role desk "role addressed"
  [ "$status" -eq 0 ]
  [[ "$output" == *"delivered to inbox"* ]] || false
  grep -q '\] role addressed' "$CC_MAILBOX_DIR/$UUID.md"
  [ "$(sent_count)" -eq 0 ]
}

@test "--role REPOINTED between sends follows the role, not the original pane (the anti-flood property)" {
  export CC_ROLES_DIR="$BATS_TEST_TMPDIR/roles"; mkdir -p "$CC_ROLES_DIR"
  local NEW="CCCCCCCC-9999-8888-7777-666666666666"
  printf '%s\n' "$UUID" > "$CC_ROLES_DIR/desk"
  "$NOTIFY" --role desk "before recycle" >/dev/null 2>&1
  printf '%s\n' "$NEW" > "$CC_ROLES_DIR/desk"          # the desk recycled; role repointed
  "$NOTIFY" --role desk "after recycle" >/dev/null 2>&1
  grep -q 'before recycle' "$CC_MAILBOX_DIR/$UUID.md"
  grep -q 'after recycle'  "$CC_MAILBOX_DIR/$NEW.md"
  ! grep -q 'after recycle' "$CC_MAILBOX_DIR/$UUID.md" || false   # the OLD box does not keep receiving
}

@test "--role with a MISSING role file → exit 3 with a hint, and nothing is enqueued" {
  export CC_ROLES_DIR="$BATS_TEST_TMPDIR/roles"; mkdir -p "$CC_ROLES_DIR"
  run "$NOTIFY" --role nosuch "x"
  [ "$status" -eq 3 ]
  [[ "$output" == *"role 'nosuch' is not set"* ]] || false
  [ -z "$(ls -A "$CC_MAILBOX_DIR")" ]
}

@test "--role with an EMPTY role file → exit 3 (an unset role is not a silent no-op)" {
  export CC_ROLES_DIR="$BATS_TEST_TMPDIR/roles"; mkdir -p "$CC_ROLES_DIR"
  : > "$CC_ROLES_DIR/desk"
  run "$NOTIFY" --role desk "x"
  [ "$status" -eq 3 ]
}

# ── EMPTY POSITIONAL TARGET ≠ UNKNOWN TARGET (2026-08-10, backlog 08ba1e3dccc2) ───────────────────
# `cc-notify "$(cat ~/.claude/cc-roles/desk)" "<msg>"` is the sanctioned back-channel form, and when
# the role is unset the substitution collapses the address to "" in the CALLER's shell. That empty
# string used to reach the registry resolver, miss (an empty name can only ever miss), and come back
# as reason=no-such-target + "the registry … holds no live session by that name … try: cc-notify
# --list" — a true statement about the wrong subsystem, which is how a worker completion rotted into
# inbox-guard/390.escalated with nobody able to name the cause.
@test "an EMPTY positional target reports reason=empty-target, NOT a registry miss" {
  export CC_ROLES_DIR="$BATS_TEST_TMPDIR/roles"; mkdir -p "$CC_ROLES_DIR"
  run "$NOTIFY" "$(cat "$CC_ROLES_DIR/desk" 2>/dev/null)" "worker completion report"
  [ "$status" -eq 3 ]
  [[ "$output" == *"reason=empty-target"* ]] || false
  [[ "$output" == *"enqueued=0"* ]] || false
  # The misdiagnosis this test exists to keep out: the registry is not the fault and must not be blamed.
  [[ "$output" != *"reason=no-such-target"* ]] || false
  [[ "$output" != *"try: cc-notify --list"* ]] || false
  [ -z "$(ls -A "$CC_MAILBOX_DIR")" ]
}

@test "the empty-target diagnostic names the role file as the producer and --role as the cure" {
  export CC_ROLES_DIR="$BATS_TEST_TMPDIR/roles"; mkdir -p "$CC_ROLES_DIR"
  run "$NOTIFY" "" "x"
  [[ "$output" == *"$CC_ROLES_DIR/<role>"* ]] || false          # where the empty address came from
  [[ "$output" == *"cc-notify --role <name>"* ]] || false        # the form that self-diagnoses instead
}

@test "the empty-target diagnostic lists the roles that ARE set (and says so when none are)" {
  export CC_ROLES_DIR="$BATS_TEST_TMPDIR/roles"; mkdir -p "$CC_ROLES_DIR"
  run "$NOTIFY" "" "x"
  [[ "$output" == *"NO role is set"* ]] || false                 # desk unset AND nothing else set
  printf '%s\n' "$UUID" > "$CC_ROLES_DIR/orchestrator"           # one role set, desk still unset
  : > "$CC_ROLES_DIR/operator"                                   # empty → unset to the resolver
  printf '   \n'      > "$CC_ROLES_DIR/scribe"                   # whitespace-only → also unset
  run "$NOTIFY" "" "x"
  [[ "$output" == *"roles that ARE set"* ]] || false
  [[ "$output" == *"orchestrator"* ]] || false
  # role_uuid is the arbiter, so an empty/whitespace-only file must NOT be advertised as addressable.
  [[ "$output" != *"operator"* ]] || false
  [[ "$output" != *"scribe"* ]] || false
}

# THE CONTROL for the partition above: a non-empty unknown target must still be no-such-target. This
# is the case payload-lint.sh:63 and handoff-fire.sh:6295 document by name (`cc-notify 776 …`), so an
# empty-target arm wide enough to swallow it would break both of those contracts silently.
@test "a NON-empty unknown target still reports no-such-target (empty-target did not widen)" {
  run "$NOTIFY" 776 "x"
  [ "$status" -eq 3 ]
  [[ "$output" == *"reason=no-such-target"* ]] || false
  [[ "$output" != *"reason=empty-target"* ]] || false
}

@test "a send to a pane with a .forward lands in the SUCCESSOR's box, not the dead one" {
  local DEAD="DEADBEEF-1111-2222-3333-444444444444"
  printf '%s\n' "$UUID" > "$CC_MAILBOX_DIR/$DEAD.forward"    # DEAD self-closed → UUID (live) continues
  run "$NOTIFY" "$DEAD" "follow the chain"
  [ "$status" -eq 0 ]
  [[ "$output" == *"following its forward chain"* ]] || false
  grep -q 'follow the chain' "$CC_MAILBOX_DIR/$UUID.md"
  [ ! -f "$CC_MAILBOX_DIR/$DEAD.md" ]                        # nothing written to the dead box
}

@test "dead target with NO forward → REROUTED to the desk role, tagged [for:<orig>]" {
  export CC_ROLES_DIR="$BATS_TEST_TMPDIR/roles"; mkdir -p "$CC_ROLES_DIR"
  printf '%s\n' "$UUID" > "$CC_ROLES_DIR/desk"               # UUID is the live desk
  local DEAD="DEADBEEF-1111-2222-3333-444444444444"          # not in the it2 stub's live list
  run "$NOTIFY" "$DEAD" "orphaned page"
  [ "$status" -eq 0 ]
  [[ "$output" == *"rerouted to desk"* ]] || false
  grep -q "\[for:$DEAD\] orphaned page" "$CC_MAILBOX_DIR/$UUID.md"   # the desk sees it, attributed
  grep -q 'orphaned page' "$CC_MAILBOX_DIR/$DEAD.md"                 # forensics stay in the dead box
}

@test "a reroute stays HONEST — stderr never upgrades it to a delivery to the original target" {
  export CC_ROLES_DIR="$BATS_TEST_TMPDIR/roles"; mkdir -p "$CC_ROLES_DIR"
  printf '%s\n' "$UUID" > "$CC_ROLES_DIR/desk"
  local DEAD="DEADBEEF-1111-2222-3333-444444444444"
  run "$NOTIFY" "$DEAD" "still undelivered"
  [[ "$output" == *"mailbox only"* ]] || false                       # the W5 verdict survives
  [[ "$output" == *"NOT a delivery to the original target"* ]] || false
  [[ "$output" != *"delivered to inbox [$DEAD]"* ]] || false         # never a false success
}

@test "dead target with NO desk role → says so plainly instead of claiming a reroute" {
  export CC_ROLES_DIR="$BATS_TEST_TMPDIR/roles"; mkdir -p "$CC_ROLES_DIR"
  local DEAD="DEADBEEF-1111-2222-3333-444444444444"
  run "$NOTIFY" "$DEAD" "nobody home"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no reroute"* ]] || false
  [[ "$output" != *"rerouted to desk"* ]] || false
}

@test "an UNKNOWN-liveness target is NOT rerouted (only an authoritative dead target is)" {
  export CC_ROLES_DIR="$BATS_TEST_TMPDIR/roles"; mkdir -p "$CC_ROLES_DIR"
  printf '%s\n' "$UUID" > "$CC_ROLES_DIR/desk"
  local UNK="DEADBEEF-1111-2222-3333-444444444444"
  printf '#!/bin/bash\nexit 1\n' > "$BATS_TEST_TMPDIR/it2-broken"    # no liveness oracle
  chmod +x "$BATS_TEST_TMPDIR/it2-broken"
  IT2_BIN="$BATS_TEST_TMPDIR/it2-broken" run "$NOTIFY" "$UNK" "unknown liveness"
  [ "$status" -eq 0 ]
  [[ "$output" == *"UNVERIFIABLE"* ]] || false
  [[ "$output" != *"rerouted"* ]] || false                           # would spam the desk on every it2 blip
  [ ! -f "$CC_MAILBOX_DIR/$UUID.md" ] || ! grep -q 'unknown liveness' "$CC_MAILBOX_DIR/$UUID.md"
}

# ── v4 RESOLVER AVAILABILITY: no blocking subprocess · honest rc · a round-tripping listing ───────
# These pin the class that cost 6 non-delivered advisories across 3 attempts and 2 wrong diagnoses:
# `it2 session list --json` (iTerm2 IPC) exceeded 120s under pane load, and BOTH cc-notify hot paths
# went through it — so a valid target came back as rc=3 "not a live session name or a pane UUID".
# The wrong diagnoses ("it times out", then "the short UUID is not accepted") were both symptoms; the
# fault was that the resolver could block at all, and that its failure was indistinguishable from a
# bad address. A stub that HANGS is therefore the load-bearing fixture here — a fast stub cannot tell
# a registry-direct resolver apart from the it2-shelling one it replaced.

# it2 stub that hangs far longer than any bound — stands in for iTerm2 under pane load 13-16.
# It also SPIES: every invocation is appended to $IT2_SPY before the stub does anything else, so a test
# can assert the strong claim ("this path never touches it2") DIRECTLY rather than inferring it from
# elapsed time. Timing alone is not sufficient here, and a green suite proved it: with the it2 call
# bounded at CC_IT2_TIMEOUT_S=5 and the hang tests asserting <10s, disabling the registry-direct
# target_live() — the SECOND of the two hang sites, and the one whose fix this suite exists to pin —
# still passed 40/40, because the fallback merely degraded to a 5s bounded call. The bound was pinned;
# the fix was not.
hanging_it2() {
  cat > "$BATS_TEST_TMPDIR/it2-hang" <<'SH'
#!/bin/bash
# Record FIRST — the assertion is "never invoked", so the spy must fire even on paths that then hang.
# `:?` rather than a default: a spy that silently failed to record would make every it2_untouched
# assertion pass vacuously, which is the exact failure mode this fixture exists to end.
printf '%s\n' "$*" >> "${IT2_SPY:?it2 stub invoked with no spy ledger wired}"
if [ "$1" = "session" ] && [ "$2" = "list" ]; then sleep 300; exit 0; fi
exit 0
SH
  chmod +x "$BATS_TEST_TMPDIR/it2-hang"
  export IT2_BIN="$BATS_TEST_TMPDIR/it2-hang"
  export IT2_SPY="$BATS_TEST_TMPDIR/it2-calls"
  : > "$IT2_SPY"
}

# Same spy, but it does NOT hang: records, then returns a valid (empty) pane list immediately. For the
# positive control, where the claim is only "the spy records" — never "it records within a bound".
spying_it2() {
  cat > "$BATS_TEST_TMPDIR/it2-spy" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >> "${IT2_SPY:?it2 stub invoked with no spy ledger wired}"
if [ "$1" = "session" ] && [ "$2" = "list" ]; then printf '[]\n'; exit 0; fi
exit 0
SH
  chmod +x "$BATS_TEST_TMPDIR/it2-spy"
  export IT2_BIN="$BATS_TEST_TMPDIR/it2-spy"
  export IT2_SPY="$BATS_TEST_TMPDIR/it2-calls"
  : > "$IT2_SPY"
}

# Effect-read of "off the blocking path entirely". Asserts the ledger EXISTS before asserting it is
# empty — an absent ledger would mean the fixture was never wired, not that it2 went untouched.
it2_untouched() {
  [ -f "$IT2_SPY" ] || { echo "spy ledger $IT2_SPY missing — hanging_it2 was not called"; return 1; }
  [ ! -s "$IT2_SPY" ] || { echo "it2 WAS invoked: $(cat "$IT2_SPY")"; return 1; }
}
secs() { local s e; s=$(date +%s); "$@" >/dev/null 2>&1; e=$(date +%s); echo $(( e - s )); }

@test "v4: a NAME send to a registered pane never touches it2 — completes fast even while it2 HANGS" {
  hanging_it2
  local t; t="$(secs "$NOTIFY" peer "under load")"
  [ "$t" -lt 10 ] || { echo "took ${t}s — the resolver is still going through the blocking it2 call"; false; }
  it2_untouched || false          # the actual claim: not merely "fast", but never on the IPC at all
  run "$NOTIFY" peer "under load 2"
  [ "$status" -eq 0 ]
  [[ "$output" == *"delivered to inbox"* ]] || false
  grep -q '\] under load' "$CC_MAILBOX_DIR/$UUID.md"
}

@test "v4: a full-UUID send to a registered pane is fast too (the liveness path was the SECOND hang)" {
  # The documented workaround — 'pass the full 36-char UUID' — only ever LOOKED reliable: resolution
  # short-circuits, but target_live() then shelled into the same it2 call. The enqueue had already
  # happened, so mail landed while the process hung. Both call sites must be off the blocking path.
  hanging_it2
  local t; t="$(secs "$NOTIFY" "$UUID" "full uuid under load")"
  [ "$t" -lt 10 ] || { echo "took ${t}s — target_live() is still on the blocking it2 call"; false; }
  # Load-bearing: a registered row must be decided from the REGISTRY, not via a bounded-but-still-taken
  # it2 call. Elapsed time cannot see that difference (a 5s bound also lands under 10s), so reverting
  # registry-direct target_live() is caught ONLY here.
  it2_untouched || false
  grep -q 'full uuid under load' "$CC_MAILBOX_DIR/$UUID.md"
}

@test "v4: an UNREGISTERED target still consults it2, but BOUNDED — degrades to UNVERIFIABLE, never hangs" {
  hanging_it2
  export CC_IT2_TIMEOUT_S=1
  local GHOST="FFFFFFFF-9999-8888-7777-666666666666"
  local t; t="$(secs "$NOTIFY" "$GHOST" "bounded")"
  [ "$t" -lt 20 ] || { echo "took ${t}s — the it2 call is unbounded"; false; }
  run "$NOTIFY" "$GHOST" "bounded 2"
  [ "$status" -eq 0 ]
  [[ "$output" == *"UNVERIFIABLE"* ]] || false      # a timeout is 'unknown', never a false not-live
  grep -q 'bounded' "$CC_MAILBOX_DIR/$GHOST.md"
}

@test "v4: POSITIVE CONTROL — the it2 spy really records, so it2_untouched cannot pass vacuously" {
  # Without this, the two "never touches it2" assertions above could be green because the stub never
  # writes at all rather than because the resolver stayed off the IPC. An UNREGISTERED target has no
  # registry row to decide liveness from, so it2 MUST be consulted here. Deliberately NOT the hanging
  # stub: a 1s bound racing the stub's own process startup made this assertion flaky under suite load,
  # and a flaky control is worse than none. The claim is "the spy records", not "it records fast".
  spying_it2
  local GHOST="FFFFFFFF-1234-5678-9999-000000000000"
  run "$NOTIFY" "$GHOST" "positive control"
  [ "$status" -eq 0 ]
  [ -s "$IT2_SPY" ] || { echo "spy recorded nothing even where it2 IS expected — the spy is blind"; false; }
  grep -q 'session list' "$IT2_SPY" || { echo "spy ledger holds: $(cat "$IT2_SPY")"; false; }
}

@test "v4: RESOLVER UNAVAILABLE (registry unreadable) → exit 4, NOT exit 3 — the target is unverified, not invalid" {
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/no-such-registry"
  run "$NOTIFY" peer "x"
  [ "$status" -eq 4 ]
  [[ "$output" == *"RESOLVER UNAVAILABLE"* ]] || false
  [[ "$output" == *"UNVERIFIED, not invalid"* ]] || false
  # the OLD lie must be gone: never blame the address when the resolver is what failed
  [[ "$output" != *"not a live session name or a pane UUID"* ]] || false
}

@test "v4: an existing-but-UNREADABLE registry is exit 4, not a phantom 'empty registry' exit 3" {
  local ro="$BATS_TEST_TMPDIR/ro-reg"; mkdir -p "$ro"; chmod 000 "$ro"
  CC_REGISTRY_DIR="$ro" run "$NOTIFY" peer "x"
  chmod 700 "$ro"
  [ "$status" -eq 4 ]
  [[ "$output" == *"RESOLVER UNAVAILABLE"* ]] || false
}

@test "v4: a genuinely UNKNOWN name is still exit 3, and says the registry WAS readable" {
  run "$NOTIFY" "not-a-name-or-uuid" "x"
  [ "$status" -eq 3 ]
  [[ "$output" == *"is UNKNOWN"* ]] || false
  [[ "$output" == *"readable"* ]] || false          # the distinguishing claim vs exit 4
  [[ "$output" != *"RESOLVER UNAVAILABLE"* ]] || false
}

@test "v4: the 8-char UUID prefix that --list prints ROUND-TRIPS into cc-notify's own input" {
  # `cc-sessions` printed .paneUUID[0:8] for years; cc-notify's own resolver rejected it.
  run "$NOTIFY" "AAAAAAAA" "prefix addressed"
  [ "$status" -eq 0 ]
  [[ "$output" == *"delivered to inbox"* ]] || false
  grep -q '\] prefix addressed' "$CC_MAILBOX_DIR/$UUID.md"
}

@test "v4: a prefix is matched case-insensitively (registry uuids are upper-case)" {
  run "$NOTIFY" "aaaaaaaa" "lower-case prefix"
  [ "$status" -eq 0 ]
  grep -q 'lower-case prefix' "$CC_MAILBOX_DIR/$UUID.md"
}

@test "v4: a DASHED partial resolves — the paste shape a full-uuid column actually produces" {
  # The listing prints the 36-char DASHED uuid, so a trimmed selection carries dashes (a double-click
  # tends to stop at a dash boundary). The old gate demanded pure hex yet compared against a dashed
  # uuid, so every dash-bearing partial returned rc=3 "target genuinely UNKNOWN" — this item's own
  # defect class, made MORE likely by the very column change that was supposed to fix round-tripping.
  for t in "AAAAAAAA-1111" "AAAAAAAA-1111-2222" "AAAAAAAA-1111-2222-3333"; do
    run "$NOTIFY" "$t" "dashed $t"
    [ "$status" -eq 0 ] || { echo "dashed partial '$t' refused with $status: $output"; false; }
    grep -q "dashed $t" "$CC_MAILBOX_DIR/$UUID.md" || false
  done
}

@test "v4: a DASH-STRIPPED partial resolves too, including all 32 hex digits" {
  # The mirror failure: hand-stripping the dashes yields >8 hex, which the old gate ACCEPTED and then
  # could not match, because the stored uuid is dashed — so 9..32-hex pastes died as "UNKNOWN" as well.
  # Dashes are normalised out of BOTH sides now, so every shape of one address resolves to it.
  for t in "AAAAAAAA1" "AAAAAAAA1111" "AAAAAAAA111122223333444444444444"; do
    run "$NOTIFY" "$t" "stripped $t"
    [ "$status" -eq 0 ] || { echo "stripped partial '$t' refused with $status: $output"; false; }
    grep -q "stripped $t" "$CC_MAILBOX_DIR/$UUID.md" || false
  done
}

@test "v4: dash-tolerance does NOT weaken the guards — too-short and non-hex still exit 3" {
  # Counted with the dashes removed, <8 hex digits is still too weak to address a pane, and a non-hex
  # body is still not a uuid. Admitting dashes makes both easy to loosen by accident — "AAAA----" is
  # the specific trap: 8 characters, but only 4 hex DIGITS, so padding with dashes must not buy its way
  # past the bar. (A LEADING dash is deliberately not tested here: it is an option by construction and
  # the parser rejects it with usage/rc 2, which is correct and has nothing to do with prefix matching.)
  for t in "AAAAAAA" "AAAA-AAA" "AAAA----" "ZZZZZZZZ" "AAAAAAAA-11ZZ"; do
    run "$NOTIFY" "$t" "x"
    [ "$status" -eq 3 ] || { echo "'$t' should be UNKNOWN (3), got $status: $output"; false; }
  done
}

@test "v4: an AMBIGUOUS DASHED prefix still fails LOUD (exit 6), enqueueing nothing" {
  local TWIN="AAAAAAAA-5555-6666-7777-888888888888"
  printf '{"paneUUID":"%s","name":"twin","cwd":"/tmp","account":"next","pid":%s,"startedAt":1}' \
    "$TWIN" "$$" > "$CC_REGISTRY_DIR/$TWIN.json"
  run "$NOTIFY" "AAAAAAAA-" "who am i for"
  [ "$status" -eq 6 ]
  [[ "$output" == *"AMBIGUOUS"* ]] || false
  [ ! -f "$CC_MAILBOX_DIR/$UUID.md" ]
  [ ! -f "$CC_MAILBOX_DIR/$TWIN.md" ]
  # …and a longer prefix disambiguates in EITHER shape, onto the correct pane of the two
  run "$NOTIFY" "AAAAAAAA-5555" "to the twin"
  [ "$status" -eq 0 ]
  grep -q 'to the twin' "$CC_MAILBOX_DIR/$TWIN.md"
  run "$NOTIFY" "AAAAAAAA1111" "to the original"
  [ "$status" -eq 0 ]
  grep -q 'to the original' "$CC_MAILBOX_DIR/$UUID.md"
}

@test "v4: an AMBIGUOUS prefix fails LOUD (exit 6) and enqueues NOTHING — never a silent wrong pane" {
  local TWIN="AAAAAAAA-5555-6666-7777-888888888888"
  printf '{"paneUUID":"%s","name":"twin","cwd":"/tmp","account":"next","pid":%s,"startedAt":1}' \
    "$TWIN" "$$" > "$CC_REGISTRY_DIR/$TWIN.json"
  run "$NOTIFY" "AAAAAAAA" "who am i for"
  [ "$status" -eq 6 ]
  [[ "$output" == *"AMBIGUOUS"* ]] || false
  [ ! -f "$CC_MAILBOX_DIR/$UUID.md" ]
  [ ! -f "$CC_MAILBOX_DIR/$TWIN.md" ]
}

@test "v4: a name matching only a DEAD row stays unresolvable (the live-only addressing contract holds)" {
  local DEADROW="BBBBBBBB-1111-2222-3333-444444444444"
  printf '{"paneUUID":"%s","name":"ghostpeer","cwd":"/tmp","account":"next","pid":999999,"startedAt":1}' \
    "$DEADROW" > "$CC_REGISTRY_DIR/$DEADROW.json"
  run "$NOTIFY" ghostpeer "x"
  [ "$status" -eq 3 ]
  [ ! -f "$CC_MAILBOX_DIR/$DEADROW.md" ]
}

@test "v4: ONE corrupt registry row cannot take the whole resolver down" {
  # `jq -s` over the set fails wholesale on a single bad file; without the per-file fallback that
  # would turn one unparseable row into a total addressing outage.
  printf 'not json at all {{{' > "$CC_REGISTRY_DIR/CORRUPT.json"
  run "$NOTIFY" peer "resolved despite corruption"
  [ "$status" -eq 0 ]
  [[ "$output" == *"delivered to inbox"* ]] || false
  grep -q 'resolved despite corruption' "$CC_MAILBOX_DIR/$UUID.md"
}

@test "v4: cc-sessions prints the FULL paneUUID, and that column feeds straight back into cc-notify" {
  # The round-trip proven end to end: take what the listing prints, paste it in, and it must resolve.
  local out col
  out="$("$REPO/bin/cc-sessions" 2>/dev/null)"
  [[ "$out" == *"$UUID"* ]] || { echo "listing did not print the full uuid: $out"; false; }
  col="$(printf '%s\n' "$out" | awk '$1=="peer"{print $2}')"
  [ "$col" = "$UUID" ] || { echo "UUID column was '$col', not the full '$UUID'"; false; }
  run "$NOTIFY" "$col" "round-tripped from the listing"
  [ "$status" -eq 0 ]
  grep -q 'round-tripped from the listing' "$CC_MAILBOX_DIR/$UUID.md"
}

@test "v4: cc-sessions itself does not hang when it2 does (--list must work under the load that broke it)" {
  hanging_it2
  export CC_IT2_TIMEOUT_S=1
  local t; t="$(secs "$REPO/bin/cc-sessions" --json)"
  [ "$t" -lt 20 ] || { echo "cc-sessions took ${t}s — its it2 call is still unbounded"; false; }
  # and a timed-out pane list must NOT be read as 'no panes' → the live row survives on pid truth
  run "$REPO/bin/cc-sessions" --json
  [[ "$output" == *"$UUID"* ]] || false
}

@test "a REROUTE follows the desk's OWN forward chain (never tees into a self-closed desk box)" {
  # Without this the anti-stranding mechanism would itself strand mail: the desk role can name a pane
  # that has since self-closed, leaving a .forward to its successor.
  export CC_ROLES_DIR="$BATS_TEST_TMPDIR/roles"; mkdir -p "$CC_ROLES_DIR"
  local OLDDESK="ABCDEF01-1111-2222-3333-444444444444"
  local DEAD="DEADBEEF-1111-2222-3333-444444444444"
  printf '%s\n' "$OLDDESK" > "$CC_ROLES_DIR/desk"              # role still names the OLD desk…
  printf '%s\n' "$UUID"    > "$CC_MAILBOX_DIR/$OLDDESK.forward" # …which self-closed → live successor
  run "$NOTIFY" "$DEAD" "reroute me"
  [ "$status" -eq 0 ]
  [[ "$output" == *"rerouted to desk [$UUID]"* ]] || false      # landed on the SUCCESSOR
  grep -q "\[for:$DEAD\] reroute me" "$CC_MAILBOX_DIR/$UUID.md"
  [ ! -f "$CC_MAILBOX_DIR/$OLDDESK.md" ]                        # nothing written to the dead desk box
}

# ── THE CALLER CONTRACT (incident 2026-07-26T04:40Z, backlog 0298535c1584) ───────────────────────────
# The resolver-availability rewrite above made cc-notify's OWN rc honest. It cannot make the rc a
# CALLER sees honest: `timeout` reports 124 whatever the child exits with, so the desk's
# `timeout 90 cc-notify …` returned 124 and TOTAL SILENCE over a message that had already been
# enqueued. Guessing "undelivered" re-sends a message that landed; guessing "delivered" loses one that
# did not. stderr is the only channel left, so every terminal path now carries a parseable token and
# `enqueued=` is the field that settles it.

@test "CALLER CONTRACT: a caller's own bound fires mid-send → rc 124 AND stderr says the message persisted" {
  # The incident verbatim. A hung it2 parks the send inside the (bounded) liveness probe, long past the
  # enqueue; the caller's bound then fires. Pre-token this printed nothing at all.
  printf '#!/bin/bash\nsleep 120\n' > "$BATS_TEST_TMPDIR/it2-hang"; chmod +x "$BATS_TEST_TMPDIR/it2-hang"
  local GHOST="BBBBBBBB-1111-2222-3333-444444444444"      # unregistered ⇒ the it2 fallback is reached
  IT2_BIN="$BATS_TEST_TMPDIR/it2-hang" CC_IT2_TIMEOUT_S=60 \
    run timeout -s TERM 4 "$NOTIFY" "$GHOST" "killed mid-send"
  [ "$status" -eq 124 ]
  [[ "$output" == *"verdict=interrupted"* ]] || false
  [[ "$output" == *"enqueued=1"* ]] || false
  grep -q 'killed mid-send' "$CC_MAILBOX_DIR/$GHOST.md"   # the delivery stands; only the verdict is lost
}

@test "CALLER CONTRACT: a kill BEFORE the enqueue reports enqueued=0 — the token never over-claims" {
  # The mirror case, and the one that makes enqueued= worth reading: an interrupted send must be able
  # to say the message did NOT persist. Kept honest by an unwritable inbox, so the enqueue cannot
  # succeed no matter where the signal lands.
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/ro/deeper"
  mkdir -p "$BATS_TEST_TMPDIR/ro"; chmod 500 "$BATS_TEST_TMPDIR/ro"
  run "$NOTIFY" "$UUID" "cannot persist"
  chmod 700 "$BATS_TEST_TMPDIR/ro"
  [ "$status" -eq 5 ]
  [[ "$output" == *"verdict=undelivered"* ]] || false
  [[ "$output" == *"enqueued=0"* ]] || false
}

@test "every terminal path prints a machine-parseable verdict= token (callers must not glob prose)" {
  run "$NOTIFY" "$UUID" "a"
  [[ "$output" == *"cc-notify: verdict=delivered enqueued=1 uuid=$UUID "* ]] || false
  run "$NOTIFY" --mailbox-only "$UUID" "b"
  # FIELD-WISE, never one contiguous string. The token is an EXTENSIBLE k=v line and this assertion
  # pinned every field in one glob, so adding a field (the read-receipt cursor, which lands between
  # uuid= and reason=) read as a contract BREAK rather than a contract extension. Pin what this test
  # is about — that each field is present and parseable — not the spacing between them.
  [[ "$output" == *"cc-notify: verdict=mailbox-only enqueued=1 uuid=$UUID "* ]] || false
  [[ "$output" == *"reason=requested"* ]] || false
  run "$NOTIFY" "DDDDDDDD-9999-8888-7777-666666666666" "c"
  [[ "$output" == *"verdict=mailbox-only"* ]] || false
  [[ "$output" == *"reason=target-not-live"* ]] || false
  run "$NOTIFY" nope-not-a-name "d"
  [[ "$output" == *"verdict=unresolvable"* ]] || false
  [[ "$output" == *"reason=no-such-target"* ]] || false
  [[ "$output" == *"enqueued=0"* ]] || false
}

@test "the token distinguishes RESOLVER-UNAVAILABLE (4) from target-UNKNOWN (3) and AMBIGUOUS (6)" {
  # The three now-distinct exit codes must be distinguishable from stderr alone, so a caller that only
  # captures output (or has its rc overwritten by its own bound) still gets the right answer.
  run "$NOTIFY" nope-not-a-name "x"
  [ "$status" -eq 3 ]; [[ "$output" == *"reason=no-such-target"* ]] || false
  printf '{"paneUUID":"AAAAAAAA-1111-2222-3333-555555555555","name":"peer2","cwd":"/tmp","account":"next","pid":%s,"startedAt":1}' $$ \
    > "$CC_REGISTRY_DIR/AAAAAAAA-1111-2222-3333-555555555555.json"
  run "$NOTIFY" "AAAAAAAA-1111-2222-3333" "y"
  [ "$status" -eq 6 ]; [[ "$output" == *"reason=ambiguous-prefix"* ]] || false
  chmod 000 "$CC_REGISTRY_DIR"
  run "$NOTIFY" some-name "z"
  chmod 755 "$CC_REGISTRY_DIR"
  [ "$status" -eq 4 ]; [[ "$output" == *"reason=resolver-unavailable"* ]] || false
}

@test "the token never contradicts the prose the existing consumers grep (both are emitted)" {
  # cc-announce, completion-push.sh and desk-invariant.sh all match on the human sentence. The token is
  # ADDITIVE — a build that replaced the prose with the token would break every one of them silently.
  run "$NOTIFY" "$UUID" "both surfaces"
  [[ "$output" == *"verdict=delivered"* ]] || false
  [[ "$output" == *"delivered to inbox [$UUID]"* ]] || false
  [ "$(sent_count)" -eq 0 ]
}

@test "wake-path is PROVEN, not claimed: a marker naming a DEAD watcher is NOT armed (F5 falsifiability)" {
  # cc-await-ping clears its marker from an EXIT trap, which SIGKILL never runs — so a killed watcher
  # left a marker that stayed "fresh" and kept earning VERIFIED for a wake that could not happen.
  sleep 30 & wpid=$!
  printf 'pid=%s\n' "$wpid" > "$CC_MAILBOX_DIR/$UUID.watching"
  run "$NOTIFY" "$UUID" "live watcher"
  [[ "$output" == *"wake-path armed"* ]] || false          # alive pid → armed
  kill "$wpid" 2>/dev/null || true; wait "$wpid" 2>/dev/null || true
  touch "$CC_MAILBOX_DIR/$UUID.watching"                    # still perfectly FRESH — only the pid died
  run "$NOTIFY" "$UUID" "dead watcher"
  [[ "$output" == *"NO watcher armed"* ]] || false          # dead pid → NOT armed (the fix)
}

@test "a LEGACY (pid-less) .watching marker still reads as armed — no regression on older watchers" {
  : > "$CC_MAILBOX_DIR/$UUID.watching"
  run "$NOTIFY" "$UUID" "legacy marker"
  [[ "$output" == *"wake-path armed"* ]] || false
}

# ── READ RECEIPT — "delivered" answered a different question than the one being asked ─────────────
# 2026-07-26 14:10: the desk told two panes their land-lock blocker was stale. cc-notify reported
# "delivered to inbox (live session)" for both. Neither ever read the line — ~4 h idle, 4 unread
# each — and the desk reported them to the operator as unblocked. Nothing lied; "delivered" was
# true. Delivery, surfacing and consumption are three events and only the third means "they know".

@test "receipt: the SEND cites the cursor — line + unacked, not just 'delivered'" {
  run "$NOTIFY" "$UUID" "the land-lock blocker is STALE — retry"
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=delivered"* ]] || false
  [[ "$output" == *"line=1"* ]] || false          # the citable handle: this message is line 1
  [[ "$output" == *"unacked=1"* ]] || false       # ...and nothing in this box has been consumed
  [[ "$output" == *"DELIVERED IS NOT READ"* ]] || false
  run "$NOTIFY" "$UUID" "second"
  [[ "$output" == *"line=2"* ]] || false          # the cursor tracks the actual append
  [[ "$output" == *"unacked=2"* ]] || false       # the backlog is visible AT SEND TIME (the 14:10 signal)
}

@test "receipt: THE THREE EVENTS — delivered→unread, drained→surfaced, a turn→read (rc gates)" {
  run "$NOTIFY" "$UUID" "retry now"
  [ "$status" -eq 0 ]
  # 1. DELIVERED but nothing has surfaced it
  run "$NOTIFY" --receipt "$UUID" 1
  [ "$status" -eq 1 ]                                        # rc is the verdict: NOT read
  [[ "$output" == *"receipt=unread"* ]] || false
  [[ "$output" == *"Do NOT report this session as told"* ]] || false
  # 2. the drain SURFACED it — still not proof a turn carried it
  echo '{}' | ITERM_SESSION_ID="w0t0p0:$UUID" "$REPO/hooks/mailbox-drain.sh" prompt >/dev/null
  run "$NOTIFY" --receipt "$UUID" 1
  [ "$status" -eq 1 ]                                        # surfaced is NOT read — the load-bearing case
  [[ "$output" == *"receipt=surfaced"* ]] || false
  # 3. a turn provably carried it (the Stop fold advances .acked)
  run bash -c "source '$REPO/hooks/lib/mailbox-pending.sh'; mailbox_promote_acked '$UUID'"
  run "$NOTIFY" --receipt "$UUID" 1
  [ "$status" -eq 0 ]                                        # ONLY here may a desk say "I told them"
  [[ "$output" == *"receipt=read"* ]] || false
  [[ "$output" == *"Safe to report this session as told"* ]] || false
}

@test "receipt: a claim can never be laundered — an UNSENT line is unread, not read" {
  # Fail-safe direction matters: a malformed or out-of-range query must report the WEAKEST verdict.
  # If this ever returned 'read' it would manufacture exactly the false confidence the tool exists
  # to remove.
  run "$NOTIFY" --receipt "$UUID" 99
  [ "$status" -eq 1 ]
  [[ "$output" == *"receipt=unread"* ]] || false
}

@test "receipt: refuses a missing/non-numeric line instead of guessing" {
  run "$NOTIFY" --receipt "$UUID"
  [ "$status" -eq 2 ]
  [[ "$output" == *"needs the LINE"* ]] || false
  run "$NOTIFY" --receipt "$UUID" not-a-number
  [ "$status" -eq 2 ]
}

@test "receipt: follows the forward chain, so it reads the box the SEND actually reached" {
  # A self-closed pane's mail follows its successor. If the receipt did not follow the same chain it
  # would report 'unread' about a box nobody wrote to — a false negative that reads as a lost message.
  SUCC="EEEEEEEE-1111-2222-3333-444444444444"
  printf '{"paneUUID":"%s","name":"succ","cwd":"/tmp","account":"next","pid":%s,"startedAt":1}' \
    "$SUCC" "$$" > "$CC_REGISTRY_DIR/$SUCC.json"
  printf '%s\n' "$SUCC" > "$CC_MAILBOX_DIR/$UUID.forward"
  run "$NOTIFY" "$UUID" "follows the chain"
  [ "$status" -eq 0 ]
  [ "$(grep -c '' "$CC_MAILBOX_DIR/$SUCC.md")" -eq 1 ]        # it landed in the SUCCESSOR's box
  run "$NOTIFY" --receipt "$UUID" 1                           # queried by the OLD address
  [[ "$output" == *"uuid=$SUCC"* ]] || false                  # ...answered about the successor's box
  [[ "$output" == *"receipt=unread"* ]] || false
}

# ── D3 REROUTE, the two holes that let a FALSE reroute claim out (task #121, 2026-08-01) ──────────
# Ground truth that produced these: ~/.claude/cc-roles/desk named a self-closed pane, that pane's
# .forward named a successor that was ALSO gone, and the successor's box held ~1446 lines with no
# cursor. Two independent holes in the block that exists to end exactly that class:
#   HOLE 1 — the whole block was gated on `[ "$uuid" = "$ORIG_UUID" ]`, so following a forward
#            SKIPPED the reroute (and the desk-is-down warning with it): total silence on the path
#            where the chain head is dead, which is the only way to reach that arm at all.
#   HOLE 2 — the self-tee guard compared the FORWARDED desk against the FORWARDED target, so a desk
#            that is the target in its PRE-forward form fell through to the reroute arm, which then
#            asserted "the desk is the standing triager" about a uuid that had just failed
#            target_live. The invariant these pin: that sentence is a claim about a READER, and it is
#            never printed about a box with none.

@test "HOLE 1: a forward followed to a DEAD successor still REROUTES (the gate made it silent)" {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_ROLES_DIR="$BATS_TEST_TMPDIR/roles"; mkdir -p "$CC_ROLES_DIR"
  local D1="D1D1D1D1-1111-2222-3333-444444444444"     # the addressee the sender named — dead
  local D2="D2D2D2D2-1111-2222-3333-444444444444"     # its successor — ALSO dead
  printf '%s\n' "$D2"   > "$CC_MAILBOX_DIR/$D1.forward"
  printf '%s\n' "$UUID" > "$CC_ROLES_DIR/desk"        # the desk itself IS live here
  run "$NOTIFY" "$D1" "chained page"
  [ "$status" -eq 0 ]
  [[ "$output" == *"following its forward chain"* ]] || false
  [[ "$output" == *"mailbox only"* ]] || false
  [[ "$output" == *"rerouted to desk [$UUID]"* ]] || false
  grep -q "\[for:$D1\] chained page" "$CC_MAILBOX_DIR/$UUID.md"   # tagged with the ORIGINAL addressee
  grep -q 'chained page' "$CC_MAILBOX_DIR/$D2.md"                 # forensics stay in the chain head
}

@test "HOLE 1: a forward followed to a dead successor with NO desk role still SAYS so (never silence)" {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_ROLES_DIR="$BATS_TEST_TMPDIR/roles"; mkdir -p "$CC_ROLES_DIR"
  local D1="D1D1D1D1-1111-2222-3333-444444444444"
  local D2="D2D2D2D2-1111-2222-3333-444444444444"
  printf '%s\n' "$D2" > "$CC_MAILBOX_DIR/$D1.forward"
  run "$NOTIFY" "$D1" "nobody at the head"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no reroute"* ]] || false
  [[ "$output" == *"role is unset"* ]] || false
  [[ "$output" != *"standing triager"* ]] || false
}

@test "HOLE 2: a DEAD desk box is never called 'the standing triager' — recorded, no proven reader" {
  # The disk-truth case: desk role → a self-closed pane → .forward → a successor that is also gone.
  # The tee still happens (forensics), but the CLAIM must degrade to what is true.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_ROLES_DIR="$BATS_TEST_TMPDIR/roles"; mkdir -p "$CC_ROLES_DIR"
  local DK="DCDCDCDC-1111-2222-3333-444444444444"     # role names this pane — self-closed
  local DS="DEDEDEDE-1111-2222-3333-444444444444"     # its successor — ALSO dead, no reader
  local D3="D3D3D3D3-1111-2222-3333-444444444444"     # an unrelated dead addressee
  printf '%s\n' "$DK" > "$CC_ROLES_DIR/desk"
  printf '%s\n' "$DS" > "$CC_MAILBOX_DIR/$DK.forward"
  run "$NOTIFY" "$D3" "page into the void"
  [ "$status" -eq 0 ]
  [[ "$output" != *"the desk is the standing triager"* ]] || false
  [[ "$output" != *"rerouted to desk"* ]] || false
  [[ "$output" == *"NO triager"* ]] || false
  [[ "$output" == *"NO proven reader"* ]] || false
  [[ "$output" == *"NOT a delivery to the original target"* ]] || false
  grep -q "\[for:$D3\] page into the void" "$CC_MAILBOX_DIR/$DS.md"   # forensics still land
}

@test "HOLE 2: the target IS the desk in its PRE-forward form → desk-is-down, never a self-tee" {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_ROLES_DIR="$BATS_TEST_TMPDIR/roles"; mkdir -p "$CC_ROLES_DIR"
  local DK="DCDCDCDC-1111-2222-3333-444444444444"     # the desk pane, self-closed
  local DS="DEDEDEDE-1111-2222-3333-444444444444"     # its successor, also dead
  printf '%s\n' "$DK" > "$CC_ROLES_DIR/desk"
  printf '%s\n' "$DS" > "$CC_MAILBOX_DIR/$DK.forward"
  run "$NOTIFY" "$DK" "paging the desk itself"        # addressed by its PRE-forward uuid
  [ "$status" -eq 0 ]
  [[ "$output" == *"the triager itself is down"* ]] || false
  [[ "$output" == *"no reroute"* ]] || false
  [[ "$output" != *"the desk is the standing triager"* ]] || false
  [ "$(grep -c '' "$CC_MAILBOX_DIR/$DS.md")" -eq 1 ]  # the enqueue only — never tee'd onto itself
}

@test "CONTROL: a LIVE desk still gets the full reroute claim (the honesty gate is not a blanket mute)" {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_ROLES_DIR="$BATS_TEST_TMPDIR/roles"; mkdir -p "$CC_ROLES_DIR"
  local D3="D3D3D3D3-1111-2222-3333-444444444444"
  printf '%s\n' "$UUID" > "$CC_ROLES_DIR/desk"
  run "$NOTIFY" "$D3" "live desk page"
  [ "$status" -eq 0 ]
  [[ "$output" == *"the desk is the standing triager"* ]] || false
  [[ "$output" != *"NO proven reader"* ]] || false
  grep -q "\[for:$D3\] live desk page" "$CC_MAILBOX_DIR/$UUID.md"
}

# ══ OFF-BOX (--cloud) — CLOUD_OBSERVABILITY.md §9.2, the SEND-side seam ════════════════════════════
# One test per arm of §9.2's three steps, plus the two disciplines the spec is emphatic about: the
# refusal that keeps an uncheckable claim from ever being made (step 1), and the --receipt UNKNOWN
# that keeps a QUEUE ACK from being read as a READ RECEIPT. The `claude` binary is a stub in every
# one of them — the real one spends the operator's quota and messages a live session.

@test "--cloud: an UNDECLARED id is REFUSED with exit 3, and the transport is never even called" {
  run "$NOTIFY" --cloud "$CLOUD_ID" "hello off-box"
  [ "$status" -eq 3 ]
  [[ "$output" == *"verdict=cloud-unobservable"* ]] || false
  [[ "$output" == *"reason=undeclared"* ]] || false
  [[ "$output" == *"could never be checked"* ]] || false
  # The load-bearing half: refusing AFTER sending would still have made the uncheckable claim.
  [ "$(cloud_calls)" -eq 0 ]
}

@test "--cloud: DECLARED + {ok:true} → exit 0, verdict=cloud-queued, sidecar records the URL" {
  declare_cloud
  run "$NOTIFY" --cloud "$CLOUD_ID" "hello off-box"
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=cloud-queued"* ]] || false
  [[ "$output" == *"queued=1"* ]] || false
  [[ "$output" == *"recorded=1"* ]] || false
  # §9.2 step 2, verbatim: the transport is `claude -p <msg> --cloud <id> --output-format json`.
  grep -qF -- "-p hello off-box --cloud $CLOUD_ID --output-format json" "$CLOUD_LOG"
  # §9.2 step 3: the send is recorded in the declaration's sidecar, WITH the returned url — the only
  # handle by which anyone can later go and look at what the session did with the message.
  [ -f "$CC_CLOUD_STATE/$CLOUD_ID.sends" ]
  grep -qF '"url":"https://claude.ai/code/session_01CHQoFxvsoDQ9KgJFSLrKno"' "$CC_CLOUD_STATE/$CLOUD_ID.sends"
  grep -qF '"msg":"hello off-box"' "$CC_CLOUD_STATE/$CLOUD_ID.sends"
  # QUEUED, never "delivered": the word this tool reserves for a message a live reader will drain is
  # not available for a queue ack.
  [[ "$output" != *"delivered to inbox"* ]] || false
}

@test "--cloud: {ok:false} exits non-zero carrying the API's OWN reason, never a bare failure" {
  declare_cloud
  cloud_answer '{"ok":false,"error":"session has already terminated"}'
  run "$NOTIFY" --cloud "$CLOUD_ID" "too late"
  [ "$status" -eq 8 ]
  [[ "$output" == *"verdict=cloud-refused"* ]] || false
  [[ "$output" == *"session has already terminated"* ]] || false
  [[ "$output" == *"NOT queued"* ]] || false
  # A refused send must leave no record claiming otherwise.
  [ ! -f "$CC_CLOUD_STATE/$CLOUD_ID.sends" ]
}

@test "--cloud --receipt: UNKNOWN (rc 7) — and the assertion that matters is that it is NOT 0" {
  declare_cloud
  run "$NOTIFY" --cloud "$CLOUD_ID" --receipt 1
  # THE invariant. {ok:true} is a QUEUE ack; there is no <uuid>.seen/.acked cursor off-box, so no
  # configuration of this box could make the answer "read". 0 here would rebuild exactly the false
  # confidence this file's DELIVERED-IS-NOT-READ apparatus was paid for.
  [ "$status" -ne 0 ]
  # …and distinguishable from the LOCAL "not read" (rc 1), which is a fact that was measured.
  [ "$status" -ne 1 ]
  [ "$status" -eq 7 ]
  [[ "$output" == *"verdict=cloud-receipt-unknown"* ]] || false
  [[ "$output" == *"UNKNOWN"* ]] || false
  [[ "$output" != *"READ —"* ]] || false
}

@test "--cloud --receipt: UNKNOWN does not depend on the declaration (an undeclared id is not 0 either)" {
  run "$NOTIFY" --cloud "$CLOUD_ID" --receipt 1
  [ "$status" -eq 7 ]
  [[ "$output" == *"verdict=cloud-receipt-unknown"* ]] || false
}

@test "--cloud: a RETIRED declaration is NOT off-box → refused, exit 3" {
  declare_cloud
  retire_cloud
  run "$NOTIFY" --cloud "$CLOUD_ID" "after retirement"
  [ "$status" -eq 3 ]
  [[ "$output" == *"verdict=cloud-unobservable"* ]] || false
  [ "$(cloud_calls)" -eq 0 ]
}

@test "--cloud: a claude binary with NO --cloud flag fails with a NAMED reason (exit 4), never generic" {
  declare_cloud
  # 2.1.114 (the stable pin) has no --cloud at all; 2.1.220 has it present-but-hidden. `--help`
  # cannot tell them apart, so the answer comes from the real call's own refusal.
  cloud_answer '' 'error: unknown option --cloud' 1
  run "$NOTIFY" --cloud "$CLOUD_ID" "to an old binary"
  [ "$status" -eq 4 ]
  [[ "$output" == *"verdict=cloud-transport-unavailable"* ]] || false
  [[ "$output" == *"reason=flag-unsupported"* ]] || false
  [[ "$output" == *"does NOT support --cloud"* ]] || false
  [ ! -f "$CC_CLOUD_STATE/$CLOUD_ID.sends" ]
}

@test "--cloud: a SEMANTIC refusal is not laundered into 'your binary is too old'" {
  declare_cloud
  # The discriminator: this refusal does NOT name the option. Reporting it as a version fault would
  # send the caller upgrading a binary that was fine.
  cloud_answer '{"ok":false,"error":"unknown session id"}' '' 1
  run "$NOTIFY" --cloud "$CLOUD_ID" "who?"
  [ "$status" -eq 8 ]
  [[ "$output" == *"unknown session id"* ]] || false
  [[ "$output" != *"does NOT support --cloud"* ]] || false
}

@test "--cloud: an unparseable answer is a REFUSAL, never a success" {
  declare_cloud
  cloud_answer 'Bad gateway' '' 1
  run "$NOTIFY" --cloud "$CLOUD_ID" "into the fog"
  [ "$status" -eq 8 ]
  [[ "$output" == *"verdict=cloud-refused"* ]] || false
  [[ "$output" == *"Bad gateway"* ]] || false
}

@test "--cloud: CC_CLOUD_BIN set-EMPTY genuinely disables the lookup and FAILS CLOSED (exit 3)" {
  declare_cloud
  # The seam contract: `${VAR+set}` honors set-including-empty. A `${VAR:-}` implementation cannot
  # tell unset from set-empty and would silently fall back to PATH — i.e. the seam could not turn
  # the thing OFF, which is the property being asserted here.
  export CC_CLOUD_BIN=
  run "$NOTIFY" --cloud "$CLOUD_ID" "no oracle"
  [ "$status" -eq 3 ]
  [[ "$output" == *"reason=cc-cloud-unavailable"* ]] || false
  [ "$(cloud_calls)" -eq 0 ]
}

@test "--cloud: CC_CLAUDE_BIN set-EMPTY is a TRANSPORT outage (exit 4), not a bad target (3)" {
  declare_cloud
  export CC_CLAUDE_BIN=
  run "$NOTIFY" --cloud "$CLOUD_ID" "no transport"
  [ "$status" -eq 4 ]
  [[ "$output" == *"reason=no-claude-binary"* ]] || false
  [[ "$output" == *"UNVERIFIED, not invalid"* ]] || false
}

@test "--cloud: refuses to be combined with a pane target — they are different address KINDS" {
  declare_cloud
  run "$NOTIFY" --cloud "$CLOUD_ID" --role desk "which one?"
  [ "$status" -eq 2 ]
  [[ "$output" == *"different address KINDS"* ]] || false
  [ "$(cloud_calls)" -eq 0 ]
}

@test "--cloud: --help documents the flag (usage() prints a fixed line range — a stale range hides it)" {
  run "$NOTIFY" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--cloud"* ]] || false
  [[ "$output" == *"exits 7"* ]] || false
}

@test "REGRESSION CONTROL: with the cloud arm present, every LOCAL path is byte-for-byte unchanged" {
  # Without this you cannot tell a working feature from a broken resolver: the cloud dispatch sits
  # AHEAD of role resolution, the forward chain and the liveness classification, so a mistake there
  # is a mistake in every send this tool has ever made. One assertion per local verdict.
  declare_cloud                                   # a declared cloud id exists — and is irrelevant here

  run "$NOTIFY" peer "local name"                 # live registered name → delivered
  [ "$status" -eq 0 ]
  [[ "$output" == *"delivered to inbox"* ]] || false

  run "$NOTIFY" "$UUID" "local uuid"              # raw uuid passthrough → delivered
  [ "$status" -eq 0 ]
  [[ "$output" == *"delivered to inbox"* ]] || false

  run "$NOTIFY" "DDDDDDDD-9999-8888-7777-666666666666" "local dead"   # not-live → mailbox only
  [ "$status" -eq 0 ]
  [[ "$output" == *"mailbox only"* ]] || false

  run "$NOTIFY" nosuchsession "local unknown"     # unknown name → 3, unchanged
  [ "$status" -eq 3 ]
  [[ "$output" == *"verdict=unresolvable"* ]] || false

  run "$NOTIFY" --receipt peer 1                  # the LOCAL receipt still measures, rc 0/1 not 7
  [ "$status" -ne 7 ]
  [[ "$output" == *"receipt="* ]] || false

  grep -q '\] local name' "$CC_MAILBOX_DIR/$UUID.md"
  [ "$(sent_count)" -eq 0 ]                       # the anti-keystroke invariant still holds
  [ "$(cloud_calls)" -eq 0 ]                      # and no local send ever reached the cloud transport
}

# ── ACCOUNT SCOPING (backlog 95422d3518bc) ───────────────────────────────────────────────────────
# A session id is NOT a globally-addressable handle. Measured 2026-08-08, clean A/B: same id, same
# command, only CLAUDE_CONFIG_DIR differs → the owning account returns {ok:true}; another account
# returns {ok:false,…,"Session not found"}.
#
# The scoping is not what these tests are really about; the ERROR STRING is. A wrong-account send
# fails as "Session not found", which reads as a DEAD session — so passing the API's own reason
# through, which is right everywhere else, is on THIS path how a confidently wrong diagnosis reaches
# a human with the API's authority behind it. cc-notify must name the routing itself.

declare_cloud_acct() {   # $1=id $2=account (omit ⇒ no account field, the pre-existing-declaration state)
  if [ -n "${2:-}" ]; then
    "$REPO/bin/cc-cloud" declare --id "$1" --branch cf-wave-c --account "$2" --repo "$BATS_TEST_TMPDIR/not-a-repo" >/dev/null 2>&1
  else
    "$REPO/bin/cc-cloud" declare --id "$1" --branch cf-wave-c --repo "$BATS_TEST_TMPDIR/not-a-repo" >/dev/null 2>&1
  fi
}
# accounts.json with a LITERAL ~, because that is how the real file stores it and an unexpanded ~
# yields a path that exists nowhere — a failure that would look exactly like the wrong-account error.
write_accounts() {
  mkdir -p "$HOME/.claude" "$HOME/cfg-owner"
  printf '{"accounts":[{"name":"owner","config_dir":"~/cfg-owner"},{"name":"ghost","config_dir":"~/cfg-missing"}]}\n' \
    > "$HOME/.claude/accounts.json"
}

@test "cloud: the send is ROUTED to the declared owning account" {
  write_accounts
  declare_cloud_acct session_01OWNED owner
  run "$NOTIFY" --cloud session_01OWNED "hi"
  echo "$output" | grep -q "routing to owning account 'owner'" || false
  echo "$output" | grep -q "cfg-owner" || false
}

# THE THIRD STATE. A declaration made before the account field existed must not be GUESSED at —
# "assume the current account" is precisely what manufactures the misleading error.
@test "cloud: a declaration with NO account WARNS and names the fix — it never guesses" {
  write_accounts
  declare_cloud_acct session_01NOACCT
  run "$NOTIFY" --cloud session_01NOACCT "hi"
  echo "$output" | grep -q 'NO owning account' || false
  echo "$output" | grep -q 'reads as a dead session and is NOT one' || false
  echo "$output" | grep -q 'cc-cloud declare .* --account' || false
  # It still SENDS — refusing would strand every declaration made before the field existed.
  ! echo "$output" | grep -q 'routing to owning account' || false
}

@test "cloud: an account with no usable config dir REFUSES rather than sending from the wrong one" {
  write_accounts
  declare_cloud_acct session_01GHOST ghost      # config_dir points at a directory that does not exist
  run "$NOTIFY" --cloud session_01GHOST "hi"
  [ "$status" -eq 5 ] || false
  echo "$output" | grep -q "indistinguishable from a dead session" || false
}

@test "cloud: cc-cloud records the owning account, and list --json exposes it" {
  declare_cloud_acct session_01FIELD owner
  grep -q '^account=owner$' "$CC_CLOUD_STATE/session_01FIELD.decl" || false
  run "$REPO/bin/cc-cloud" list --json
  echo "$output" | grep -q '"account":"owner"' || false
}

# ── kitty numeric pane ids (id-space law: registry keys on a kitty box are decimal ints) ────────

@test "kitty numeric pane id resolves via its registry row and enqueues" {
  # A kitty-keyed registry row: filename IS the pane id, no uuid shape anywhere.
  printf '{"paneUUID":"247","name":"lakehouse-lecture-247","cwd":"/tmp","account":"next","pid":%s,"startedAt":1}' "$$" \
    > "$CC_REGISTRY_DIR/247.json"
  run "$NOTIFY" 247 "numeric id ping"
  [ "$status" -eq 0 ]
  [[ "$output" == *"enqueued=1"* ]] || false
  grep -q '\] numeric id ping' "$CC_MAILBOX_DIR/247.md"
  [ "$(sent_count)" -eq 0 ]     # the anti-keystroke invariant holds on this path too
}

@test "numeric token with NO registry row stays UNKNOWN (control — numerics never blind-passthrough)" {
  run "$NOTIFY" 999 "to nobody"
  [ "$status" -eq 3 ]
  [[ "$output" == *"verdict=unresolvable"* ]] || false
  [ ! -e "$CC_MAILBOX_DIR/999.md" ]
  [[ "$output" == *"enqueued=0"* ]] || false   # positive control beside the absence assertion
}
