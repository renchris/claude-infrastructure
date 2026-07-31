#!/usr/bin/env bats
# send_page must PARSE cc-notify's verdict, not read its exit code.
#
# Measured 2026-07-31: paging a role whose pane is dead returns
#   verdict=mailbox-only enqueued=1 reason=target-not-live unacked=997   with rc=0
# cc-notify is entirely honest — it says "no drain will run" and "DELIVERED IS NOT READ". send_page
# was the liar: it checked rc and never read the token, so a session sat blocked on a permission
# prompt for 15.2 hours while every page was recorded as SENT into a box with 997 unacked messages.
# memory: claimed-outcome-vs-checked-outcome — the structured verdict existed; nobody parsed it.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_FIRE_CAPACITY_GATE=off
  REPO="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  SUP="$REPO/scripts/lead-supervisor.sh"
  [ -f "$SUP" ] || skip "lead-supervisor.sh not found"
}

@test "the delivered-only condition is explicit, not an rc check" {
  run grep -n 'verdict.*=.*delivered' "$SUP"
  [ "$status" -eq 0 ]
  # the old shape — success purely on rc — must be gone from send_page
  run bash -c "sed -n '/^send_page()/,/^}/p' '$SUP' | grep -q '^  \[ \"\$rc\" = 0 \] && return 0'"
  [ "$status" -ne 0 ]
}

@test "an unreadable verdict is a THIRD state, never promoted to success" {
  run bash -c "sed -n '/^send_page()/,/^}/p' '$SUP'"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '_verdict:=unreadable'
}

@test "a non-delivered verdict escalates to a channel with no liveness dependency" {
  run bash -c "sed -n '/^send_page()/,/^}/p' '$SUP'"
  echo "$output" | grep -q 'page_escalate_os'
  # and the escalation must exist
  grep -q '^page_escalate_os()' "$SUP"
}

@test "the escalation passes text as AppleScript ARGV, never interpolated into the script" {
  run bash -c "sed -n '/^page_escalate_os()/,/^}/p' '$SUP'"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'on run argv'
  echo "$output" | grep -q 'item 2 of argv'
  # a quoted heredoc — so nothing in the message is expanded by the shell either
  echo "$output" | grep -q "<<'OSA'"
}

@test "escalation is best-effort: it cannot break the sweep that raised it" {
  run bash -c "sed -n '/^page_escalate_os()/,/^}/p' '$SUP'"
  echo "$output" | grep -q 'return 0'
  echo "$output" | grep -q 'command -v osascript'
}

@test "lead-supervisor.sh still parses" {
  run bash -n "$SUP"
  [ "$status" -eq 0 ]
}
