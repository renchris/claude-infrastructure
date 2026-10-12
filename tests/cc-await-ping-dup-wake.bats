#!/usr/bin/env bats
# cc-await-ping — ONE ping, ONE wake (2026-10-12).
#
# Measured on lead pane 223 (sid 4f7d7e9e) 2026-10-11: a fired peer's ping landed in the PANE box, the
# default watcher (keyset pane+session) fired and woke the lead, the lead re-armed, and the NEW watcher
# fired again 2-7 s later on `[forwarded:223] <the same line>` in the SESSION box — three double wakes
# in one evening, each a full model turn. The copy is written by the drain's coverage fold
# (hooks/mailbox-drain.sh → mailbox_migrate) at the PostToolUse of the re-arm call itself, i.e. AFTER
# the new watcher seeded its cursors from `.seen`. Nothing advanced `.seen` in between, because a
# watcher PEEKS (backlog 0366d5cc7b87) and a task-notification wake is not a UserPromptSubmit.
#
# The fix is a wake RECORD (<key>.woke), never a `.seen` write: the drain still delivers every line.
# Every case runs its watcher in the FOREGROUND on pre-seeded state, so no fork outlives a test.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  AWAIT="$REPO/bin/cc-await-ping"
  DRAIN="$REPO/hooks/mailbox-drain.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/bin"
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mbox"
  mkdir -p "$CC_MAILBOX_DIR"
  export CC_AWAIT_IT2_BIN=                      # no pane transport: owner guard stays fail-closed
  export CC_BEAT_DIR="$BATS_TEST_TMPDIR/beats"; mkdir -p "$CC_BEAT_DIR"
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg"; mkdir -p "$CC_REGISTRY_DIR"
  unset KITTY_PID KITTY_LISTEN_ON KITTY_WINDOW_ID CC_PANE_ID
  PANE="AAAAAAAA-1111-2222-3333-444444444444"
  SESS="bbbbbbbb-9999-8888-7777-666666666666"
  export ITERM_SESSION_ID="w0t0p0:$PANE"
  mkdir -p "$CC_MAILBOX_DIR/.alias"
  printf '2026-10-11T00:00:00+0000 %s\n' "$SESS" > "$CC_MAILBOX_DIR/.alias/$PANE"
  PING='2026-10-11T22:54:34-0500 [lr-notify-304] HANDOFF-PING fire-lr-notify: progress — items 1-2 landed'
}

watch() { run "$AWAIT" --interval 1 --timeout "${1:-3}"; }   # the default no-arg form the lead arms
fold()  { # the drain's coverage fold: pane box → session box, session .seen NOT yet committed
  bash -c '. "$1/hooks/lib/mailbox-pending.sh" && mailbox_migrate "$2" "$3"' _ "$REPO" "$PANE" "$SESS" >/dev/null
}

@test "re-arm on the SAME key: a line the predecessor printed does not wake the successor" {
  printf '%s\n' "$PING" > "$CC_MAILBOX_DIR/$PANE.md"
  watch 4
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"items 1-2 landed"* ]] || false
  watch 3                                                   # .seen still 0: no drain ran in between
  [ "$status" -eq 2 ] || { echo "status=$status"; echo "$output"; false; }
  [[ "$output" == *"verdict=timeout"* ]] || false
}

@test "re-arm after the coverage fold: the [forwarded:] copy of a printed line does not wake" {
  printf '%s\n' "$PING" > "$CC_MAILBOX_DIR/$PANE.md"
  watch 4
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  fold
  [ "$(grep -c '\[forwarded:AAAAAAAA\]' "$CC_MAILBOX_DIR/$SESS.md")" -eq 1 ]
  watch 3
  [ "$status" -eq 2 ] || { echo "status=$status"; echo "$output"; false; }
}

@test "the drain still owns delivery: the wake record writes no .seen and no .acked" {
  printf '%s\n' "$PING" > "$CC_MAILBOX_DIR/$PANE.md"
  watch 4
  [ "$status" -eq 0 ]
  [ ! -e "$CC_MAILBOX_DIR/$PANE.seen" ]
  [ ! -e "$CC_MAILBOX_DIR/$PANE.acked" ]
  [ -s "$CC_MAILBOX_DIR/$PANE.woke" ]
}

@test "F6a CONTROL: a forwarded copy of a line NO watcher printed still fires at once" {
  printf '%s\n' "$PING" > "$CC_MAILBOX_DIR/$PANE.md"
  fold                                                      # folded before any watcher saw it
  watch 4
  [ "$status" -eq 0 ] || { echo "status=$status"; echo "$output"; false; }
  [[ "$output" == *"[forwarded:AAAAAAAA]"*"items 1-2 landed"* ]] || false
}

@test "F6a CONTROL: mail that lands after the predecessor fired wakes the successor, alone" {
  printf '%s\n' "$PING" > "$CC_MAILBOX_DIR/$PANE.md"
  watch 4
  [ "$status" -eq 0 ]
  printf '%s\n' '2026-10-11T23:10:00-0500 [peer-305] HANDOFF-PING fire-y: DONE — landed abc123' >> "$CC_MAILBOX_DIR/$PANE.md"
  watch 4
  [ "$status" -eq 0 ] || { echo "status=$status"; echo "$output"; false; }
  [[ "$output" == *"landed abc123"* ]] || false
  [[ "$output" != *"items 1-2 landed"* ]] || false
}

@test "FAIL-OPEN: a record whose line no longer matches the box (rotated) is ignored" {
  printf '%s\n' "$PING" > "$CC_MAILBOX_DIR/$PANE.md"
  watch 4
  [ "$status" -eq 0 ]
  printf '%s\n' '2026-10-12T01:00:00-0500 [peer-306] HANDOFF-PING fire-z: DONE — after rotation' > "$CC_MAILBOX_DIR/$PANE.md"
  watch 4
  [ "$status" -eq 0 ] || { echo "status=$status"; echo "$output"; false; }
  [[ "$output" == *"after rotation"* ]] || false
}

@test "drain: a woken-but-unshown line is delivered at the next tool call, past the 20 s throttle" {
  # Without the second wake the dedupe removes, the wake turn's own PostToolUse drain is what shows the
  # body. A fresh throttle stamp must not defer it to a boundary that may never come.
  printf '%s\n' "$PING" > "$CC_MAILBOX_DIR/$PANE.md"
  watch 4
  [ "$status" -eq 0 ]
  : > "$CC_MAILBOX_DIR/$PANE.posttool"
  run bash -c 'printf "{}" | "$0" post-tool' "$DRAIN"
  [[ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext // ""')" == *"items 1-2 landed"* ]] \
    || { echo "$output"; false; }
}

@test "drain CONTROL: with no wake record the 20 s throttle still holds" {
  printf '%s\n' "$PING" > "$CC_MAILBOX_DIR/$PANE.md"
  : > "$CC_MAILBOX_DIR/$PANE.posttool"
  run bash -c 'printf "{}" | "$0" post-tool' "$DRAIN"
  [[ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null)" != *"items 1-2 landed"* ]] \
    || { echo "$output"; false; }
}
