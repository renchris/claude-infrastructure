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

@test "cc-notify NEVER invokes the keystroke transport across ALL send paths" {
  "$NOTIFY" peer "one" >/dev/null 2>&1
  "$NOTIFY" "$UUID" "two" >/dev/null 2>&1
  "$NOTIFY" --from x "$UUID" "three" >/dev/null 2>&1
  export ITERM_SESSION_ID="w0t0p0:$UUID"; "$NOTIFY" --self "four" >/dev/null 2>&1
  [ "$(sent_count)" -eq 0 ]     # zero it2 `session send` across name/uuid/from/self — no keystrokes, ever
}
