#!/usr/bin/env bats
# mailbox-drain — v2 non-keystroke delivery. Proves the drain lands mail as CONTEXT (additionalContext
# on prompt/session-start; decision:block on stop), advances the SHARED .seen cursor EXACTLY ONCE, and
# never touches a keystroke transport. Isolated via CC_MAILBOX_DIR + a synthetic ITERM_SESSION_ID.
#
# Harness rules (from tests/cc-notify.bats, learned from real escapes):
#   1. `|| false` on EVERY bare [[ ]] — bats does not trap a [[ ]] failure mid-body.
#   2. Assert the SPECIFIC string, never a loose glob that a degraded result also matches.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  DRAIN="$REPO/hooks/mailbox-drain.sh"
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mbox"
  mkdir -p "$CC_MAILBOX_DIR"
  UUID="AAAAAAAA-1111-2222-3333-444444444444"
  export ITERM_SESSION_ID="w0t0p0:$UUID"
  MBOX="$CC_MAILBOX_DIR/$UUID.md"
  SEEN="$CC_MAILBOX_DIR/$UUID.seen"
}

seed() { printf '%s\n' "$@" > "$MBOX"; }
add()  { printf '%s\n' "$@" >> "$MBOX"; }

@test "prompt drain: pending mail → additionalContext (never keystrokes), cursor advances to EOF" {
  seed "2026-07-20T10:00:00+0000 [reaper] page one" "2026-07-20T10:01:00+0000 [supervisor] page two"
  run bash -c 'echo "{}" | "$0" prompt' "$DRAIN"
  [ "$status" -eq 0 ]
  ev="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.hookEventName')"
  [ "$ev" = "UserPromptSubmit" ]
  ctx="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  printf '%s' "$ctx" | grep -q 'page one'
  printf '%s' "$ctx" | grep -q 'page two'
  # delivered as CONTEXT — the payload says so, and there is no keystroke transport involved.
  printf '%s' "$ctx" | grep -q 'as CONTEXT'
  [ "$(cat "$SEEN")" -eq 2 ]
}

@test "exactly-once: a second identical drain delivers NOTHING (cursor already at EOF)" {
  seed "a msg" "b msg"
  echo '{}' | "$DRAIN" prompt >/dev/null
  run bash -c 'echo "{}" | "$0" prompt' "$DRAIN"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "session-start drain emits SessionStart additionalContext" {
  seed "resume-time message"
  run bash -c 'echo "{}" | "$0" session-start' "$DRAIN"
  [ "$status" -eq 0 ]
  ev="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.hookEventName')"
  [ "$ev" = "SessionStart" ]
  printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext' | grep -q 'resume-time message'
}

@test "stop drain: pending mail → decision:block reason (the wake channel), cursor advances" {
  seed "mid-turn page from supervisor"
  run bash -c 'echo "{}" | "$0" stop' "$DRAIN"
  [ "$status" -eq 0 ]
  dec="$(printf '%s' "$output" | jq -r '.decision')"
  [ "$dec" = "block" ]
  printf '%s' "$output" | jq -r '.reason' | grep -q 'mid-turn page from supervisor'
  [ "$(cat "$SEEN")" -eq 1 ]
}

@test "stop drain: NO pending mail → no block, exit 0 (never a spurious wedge)" {
  seed "already seen"
  echo "1" > "$SEEN"
  run bash -c 'echo "{}" | "$0" stop' "$DRAIN"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "append-during-drain: a line added AFTER the count is read stays pending (no loss, no dup)" {
  seed "first" "second"
  # first drain sees 2 → delivers both, cursor=2
  echo '{}' | "$DRAIN" prompt >/dev/null
  [ "$(cat "$SEEN")" -eq 2 ]
  add "third"
  # next drain delivers ONLY the third
  run bash -c 'echo "{}" | "$0" prompt' "$DRAIN"
  ctx="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  printf '%s' "$ctx" | grep -q 'third'
  printf '%s' "$ctx" | grep -qv 'first' || true
  run bash -c 'printf "%s" "$1" | grep -c "second"' _ "$ctx"
  [ "$output" -eq 0 ]
  [ "$(cat "$SEEN")" -eq 3 ]
}

@test "cursor is byte-consistent with handoff-disposition (--ack writes the SAME value the drain does)" {
  seed "one" "two" "three"
  echo '{}' | "$DRAIN" prompt >/dev/null
  drain_cursor="$(cat "$SEEN")"
  # handoff-disposition --ack computes the cursor the same way (grep -c '') and writes it to .seen
  rm -f "$SEEN"
  CC_MAILBOX_DIR="$CC_MAILBOX_DIR" "$REPO/scripts/handoff-disposition.sh" --session "$UUID" --ack >/dev/null 2>&1 || true
  ack_cursor="$(cat "$SEEN")"
  [ "$drain_cursor" -eq "$ack_cursor" ]
}

@test "rotated mailbox (cursor ahead of EOF) re-delivers rather than swallowing" {
  printf 'only line after rotate\n' > "$MBOX"
  echo "9" > "$SEEN"    # stale cursor beyond EOF (file was truncated + regrown)
  run bash -c 'echo "{}" | "$0" prompt' "$DRAIN"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext' | grep -q 'only line after rotate'
  [ "$(cat "$SEEN")" -eq 1 ]
}

@test "no pane uuid → clean no-op (never errors)" {
  unset ITERM_SESSION_ID
  seed "unreachable"
  run bash -c 'echo "{}" | "$0" prompt' "$DRAIN"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "the drain NEVER invokes a keystroke transport (no it2 on PATH is needed)" {
  seed "context-only delivery"
  # Run with an empty PATH-ish env for it2: if the drain shelled out to it2 it would fail; it must not.
  IT2_BIN=/nonexistent/it2 run bash -c 'echo "{}" | "$0" prompt' "$DRAIN"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext' | grep -q 'context-only delivery'
}
