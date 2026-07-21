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
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg"
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mbox"
  export IT2_LOG="$BATS_TEST_TMPDIR/it2.log"
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
