#!/usr/bin/env bats
# cc-notify-socket-wake.bats — cc-notify wakes a DEAF idle pane through bin/cc-wake, and records the
# line a message landed on under the sender's key (docs/plans/AGENT_PEER_WAKE.md).
#
# The waker is a FAKE whose exit code each test chooses: cc-wake's own gates are pinned in
# tests/cc-wake.bats, and what is under test here is only the SEAM — when cc-notify calls it, what it
# passes, and that only the waker's own rc 0 earns the word "woken".
#
# BATS ERREXIT DISCIPLINE: a non-final `[[ ]]`, `!` or `A && B` carries `|| false`.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  NOTIFY="$REPO/bin/cc-notify"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg" CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mbox"
  export CC_COMMS_ALARM_DIR="$BATS_TEST_TMPDIR/comms-alarms"
  export CC_NOTIFY_LAUNCHCTL_BIN="$BATS_TEST_TMPDIR/no-launchctl-here"
  mkdir -p "$CC_REGISTRY_DIR" "$CC_MAILBOX_DIR"
  unset CC_NOTIFY_WAKE
  UUID="AAAAAAAA-1111-2222-3333-444444444444"
  printf '{"paneUUID":"%s","name":"peer","cwd":"/tmp","account":"next","pid":%s,"startedAt":1}' \
    "$UUID" "$$" > "$CC_REGISTRY_DIR/$UUID.json"
  STUB="$BATS_TEST_TMPDIR/it2"
  printf '#!/bin/bash\n[ "$1 $2" = "session list" ] && printf %s\\n %s\nexit 0\n' "'[{\"id\":\"$UUID\"}]'" "" > "$STUB"
  chmod +x "$STUB"; export IT2_BIN="$STUB"
  # the sender's own pane, so the line record has a key to land under
  export ITERM_SESSION_ID="w0t0p0:SENDER-0000-1111-2222-333333333333"
  WLOG="$BATS_TEST_TMPDIR/waker.log"; WRC="$BATS_TEST_TMPDIR/waker.rc"; printf 0 > "$WRC"
  cat > "$BATS_TEST_TMPDIR/fake-wake" <<SH
#!/bin/bash
printf '%s\n' "\$*" >> "$WLOG"
echo "cc-wake: verdict=fake" >&2
exit \$(cat "$WRC")
SH
  chmod +x "$BATS_TEST_TMPDIR/fake-wake"
  export CC_PANE_WAKE_BIN="$BATS_TEST_TMPDIR/fake-wake"
}

@test "live pane, no watcher, waker succeeds: reported woken-socket, keeping the 'wake-path armed' literal" {
  run "$NOTIFY" "$UUID" "hello"
  [ "$status" -eq 0 ]
  [[ "$output" == *"reason=woken-socket"* ]] || false
  [[ "$output" == *"wake-path armed"* ]] || false
  grep -q -- "$UUID --no-wait" "$WLOG"
}

@test "waker refuses: still reason=no-watcher and the 'NO watcher armed' literal — never a claimed wake" {
  printf 1 > "$WRC"
  run "$NOTIFY" "$UUID" "hello"
  [ "$status" -eq 0 ]
  [[ "$output" == *"reason=no-watcher"* ]] || false
  [[ "$output" != *"woken-socket"* ]] || false
  [[ "$output" == *"NO watcher armed"* ]] || false
  [[ "$output" == *"cc-wake: verdict=fake"* ]] || false
}

@test "--no-wake: the waker is never invoked" {
  run "$NOTIFY" --no-wake "$UUID" "hello"
  [ "$status" -eq 0 ]
  [[ "$output" == *"reason=no-watcher"* ]] || false
  [ ! -s "$WLOG" ]
}

@test "CC_NOTIFY_WAKE=0: the waker is never invoked" {
  CC_NOTIFY_WAKE=0 run "$NOTIFY" "$UUID" "hello"
  [ "$status" -eq 0 ]
  [ ! -s "$WLOG" ]
}

@test "an armed watcher wins: no socket wake on top of it" {
  printf 'pid=%s\n' "$$" > "$CC_MAILBOX_DIR/$UUID.watching"
  run "$NOTIFY" "$UUID" "hello"
  [[ "$output" == *"reason=wake-path-armed"* ]] || false
  [ ! -s "$WLOG" ]
}

@test "the landed line is recorded under the sender's key in .sent-lines (box, line, target)" {
  run "$NOTIFY" "$UUID" "first"
  run "$NOTIFY" "$UUID" "second"
  f="$CC_MAILBOX_DIR/.sent-lines/SENDER-0000-1111-2222-333333333333"
  [ -s "$f" ]
  [ "$(tail -n1 "$f" | awk '{print $2, $3, $4}')" = "$UUID 2 $UUID" ]
  # and .sent keeps its field-counted shape (cc-reaper / handoff-fire read NF)
  [ "$(awk '{print NF}' "$CC_MAILBOX_DIR/.sent/SENDER-0000-1111-2222-333333333333" | sort -u)" = 2 ]
}
