#!/usr/bin/env bats
# cc-inbox-guard — the FAIL-LOUD backstop: undelivered mail (unacked past a deadline) escalates to the
# operator's phone + a durable alarm record; a CONSUMED inbox never does. This is the "undelivered-alarms"
# proof — nothing enqueued to a session silently vanishes. Isolated via CC_MAILBOX_DIR + a stub push-send
# + a clock override + a live-uuid override (bypasses it2).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  G="$REPO/bin/cc-inbox-guard"
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mbox"
  export CC_INBOX_GUARD_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_COMMS_ALARM_DIR="$BATS_TEST_TMPDIR/alarms"
  export CC_INBOX_GUARD_DEADLINE_S=600
  export CC_INBOX_GUARD_URGENT_S=60
  export CC_INBOX_GUARD_RECONCILE_BIN=""
  mkdir -p "$CC_MAILBOX_DIR"
  U="AAAAAAAA-1111-2222-3333-444444444444"
  PUSHLOG="$BATS_TEST_TMPDIR/push.log"
  export CC_INBOX_GUARD_PUSH_BIN="$BATS_TEST_TMPDIR/push"
  { printf '#!/bin/bash\n'; printf 'printf "%%s\\n" "$*" >> "%s"\nexit 0\n' "$PUSHLOG"; } > "$CC_INBOX_GUARD_PUSH_BIN"
  chmod +x "$CC_INBOX_GUARD_PUSH_BIN"
  # a fixed "now" and a helper to stamp a message N seconds in the past
  NOW=1784544000   # 2026-07-20T00:00:00Z-ish, fixed
  export CC_INBOX_GUARD_NOW="$NOW"
}
# write a message aged $1 seconds with [from] tag $2 into U's inbox (ISO from the fixed clock)
msg_aged() {
  local age="$1" from="$2" ts
  ts="$(date -u -r "$((NOW - age))" +%Y-%m-%dT%H:%M:%S+0000 2>/dev/null || date -u -d "@$((NOW-age))" +%Y-%m-%dT%H:%M:%S+0000)"
  printf '%s [%s] a message\n' "$ts" "$from" >> "$CC_MAILBOX_DIR/$U.md"
}
pushed() { [ -s "$PUSHLOG" ]; }
n_alarms() { find "$CC_COMMS_ALARM_DIR" -name 'undelivered-*.json' 2>/dev/null | wc -l | tr -d ' '; }

@test "selftest passes 3/3 (a zero-check suite must not 'pass')" {
  run "$G" --selftest
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | grep -c '^  ok ')" -eq 3 ]
}

@test "undelivered to a LIVE session past deadline → phone + alarm (fail-loud)" {
  msg_aged 3600 peer          # 1h old, unacked (.acked=0)
  export CC_INBOX_GUARD_LIVE_UUIDS="$U"
  run "$G" sweep
  [ "$status" -eq 0 ]
  pushed
  [ "$(n_alarms)" -ge 1 ]
}

@test "CONSUMED inbox (.acked advanced) → NO escalation (keys on .acked, not the eager .seen)" {
  msg_aged 3600 peer
  printf '1\n' > "$CC_MAILBOX_DIR/$U.seen"; printf '1\n' > "$CC_MAILBOX_DIR/$U.acked"
  export CC_INBOX_GUARD_LIVE_UUIDS="$U"
  run "$G" sweep
  [ "$status" -eq 0 ]
  ! pushed
  [ "$(n_alarms)" -eq 0 ]
}

@test "within deadline → NO escalation (a fresh unread line is not overdue)" {
  msg_aged 60 peer            # 60s < 600s deadline for a peer ping
  export CC_INBOX_GUARD_LIVE_UUIDS="$U"
  run "$G" sweep
  ! pushed
}

@test "F12: a reaper PAGE is urgent — overdue at 60s where a peer ping is not" {
  msg_aged 120 reaper         # 120s > 60s urgent deadline
  export CC_INBOX_GUARD_LIVE_UUIDS="$U"
  run "$G" sweep
  pushed
}

@test "F8: INDETERMINATE owner (it2 unreadable) → ESCALATE (silence is not fail-loud)" {
  msg_aged 3600 peer
  # no LIVE_UUIDS override + a broken it2 → owner_liveness returns indeterminate
  export CC_INBOX_GUARD_IT2=/nonexistent/it2
  unset CC_INBOX_GUARD_LIVE_UUIDS
  run "$G" sweep
  pushed
  printf '%s' "$output" | grep -qi 'INDETERMINATE'
}

@test "dead pane with unacked mail → escalate (the target died with mail undelivered)" {
  msg_aged 3600 supervisor
  export CC_INBOX_GUARD_LIVE_UUIDS="SOMETHING-ELSE"   # U is NOT live → dead
  export CC_INBOX_GUARD_IT2="$BATS_TEST_TMPDIR/it2ok"
  { printf '#!/bin/bash\n'; printf 'echo "[{\\"id\\":\\"SOMETHING-ELSE\\"}]"\n'; } > "$CC_INBOX_GUARD_IT2"; chmod +x "$CC_INBOX_GUARD_IT2"
  run "$G" sweep
  pushed
}

@test "damping: a second sweep of the SAME undelivered state does NOT re-escalate" {
  msg_aged 3600 peer
  export CC_INBOX_GUARD_LIVE_UUIDS="$U"
  "$G" sweep >/dev/null
  : > "$PUSHLOG"     # clear the phone log; the state marker persists
  run "$G" sweep
  ! pushed           # same (acked:lines) → damped
}

@test "damping RE-ARMS on new mail (a fresh undelivered line escalates again)" {
  msg_aged 3600 peer
  export CC_INBOX_GUARD_LIVE_UUIDS="$U"
  "$G" sweep >/dev/null
  : > "$PUSHLOG"
  msg_aged 3600 reaper        # NEW line → (acked:lines) changes → re-escalate
  run "$G" sweep
  pushed
}

@test "F11: cursor past EOF (rotation/truncation under a live cursor) → escalate" {
  msg_aged 60 peer            # 1 line, fresh
  printf '9\n' > "$CC_MAILBOX_DIR/$U.seen"   # .seen=9 > 1 line → rotated/truncated
  export CC_INBOX_GUARD_LIVE_UUIDS="$U"
  run "$G" sweep
  pushed
  printf '%s' "$output" | grep -qi 'cursor past EOF'
}

@test "F4: an enqueue-FAILED record (cc-notify exit 5) escalates + is consumed" {
  mkdir -p "$CC_COMMS_ALARM_DIR"
  printf '{"kind":"enqueue-failed","target":"%s","msg":"could not persist"}' "$U" > "$CC_COMMS_ALARM_DIR/enqueue-fail-x.json"
  run "$G" sweep
  pushed
  [ ! -f "$CC_COMMS_ALARM_DIR/enqueue-fail-x.json" ]    # handled (moved/removed), never re-fires forever
}

@test "--dry-run escalates NOTHING (classify-only)" {
  msg_aged 3600 peer
  export CC_INBOX_GUARD_LIVE_UUIDS="$U"
  run "$G" sweep --dry-run
  [ "$status" -eq 0 ]
  ! pushed
  [ "$(n_alarms)" -eq 0 ]
  printf '%s' "$output" | grep -qi 'WOULD-ESCALATE'
}
