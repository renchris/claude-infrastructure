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

@test "a non-delivered verdict reaches a channel with no liveness dependency" {
  # 2026-08-01: send_page no longer escalates INLINE. One notification per finding is a storm at 14
  # findings a sweep (measured: 1,519 in an hour), so the RECORDED class is routed into a per-sweep
  # DIGEST that posts once. The liveness-free channel is still the destination — the hop changed, not
  # the guarantee. The behavioural proof is supervisor-e2e T32; these are the structural pins.
  run bash -c "sed -n '/^send_page()/,/^}/p' '$SUP'"
  echo "$output" | grep -q 'digest_add'
  grep -q '^digest_flush()' "$SUP"
  grep -q '^page_escalate_os()' "$SUP"
  # the digest is what actually posts, and the sweep must flush it — an accumulator nobody drains
  # would be silence wearing a delivery's clothes
  run bash -c "sed -n '/^digest_flush()/,/^}/p' '$SUP'"
  echo "$output" | grep -q 'page_escalate_os'
  run bash -c "sed -n '/^sweep()/,/^}/p' '$SUP'"
  echo "$output" | grep -q 'digest_flush'
}

@test "RECORDED keeps its damping marker; only a REFUSED transport forgets it" {
  # The storm's mechanism: e6d789a8 sent every non-delivered verdict down the failure path, which
  # damp_forgets the marker so the next sweep re-sends — unbounded against a permanently dead desk.
  # damp_forget must sit ONLY on the refused path, after the RECORDED branch has already returned.
  run bash -c "sed -n '/^send_page()/,/^}/p' '$SUP'"
  [ "$status" -eq 0 ]
  recorded_line="$(echo "$output" | grep -n 'digest_add' | head -1 | cut -d: -f1)"
  forget_line="$(echo "$output" | grep -n 'damp_forget' | head -1 | cut -d: -f1)"
  # one assertion per line: under errexit the right-hand side of `A && B` is the only reachable
  # verdict, so a conjunction silently discards A (the dead-assertion class the ratchet catches).
  [ -n "$recorded_line" ]
  [ -n "$forget_line" ]
  [ "$recorded_line" -lt "$forget_line" ]
  # and the RECORDED branch returns 0 (handled) before ever reaching it
  echo "$output" | sed -n "${recorded_line},\$p" | grep -q 'return 0'
}

@test "the escalation passes text as AppleScript ARGV, never interpolated into the script" {
  run bash -c "sed -n '/^page_escalate_os()/,/^}/p' '$SUP'"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'on run argv'
  echo "$output" | grep -q 'item 2 of argv'
  # a quoted heredoc — so nothing in the message is expanded by the shell either
  echo "$output" | grep -q "<<'OSA'"
}

@test "escalation is best-effort, but it REPORTS whether anything was posted" {
  run bash -c "sed -n '/^page_escalate_os()/,/^}/p' '$SUP'"
  echo "$output" | grep -q 'return 0'          # still cannot break the sweep that raised it
  # …and it must be able to say NO: a caller that keeps a damping marker on the strength of this call
  # has to distinguish "posted" from "there was no channel" (claimed-outcome-vs-checked-outcome).
  echo "$output" | grep -q 'return 1'
  echo "$output" | grep -q 'os_channel_available'
  # the capability probe itself, with an operator/test seam — a `command -v` with no seam leaves the
  # no-channel branch untestable, since no suite can un-find /usr/bin/osascript via PATH
  run bash -c "sed -n '/^os_channel_available()/,/^}/p' '$SUP'"
  echo "$output" | grep -q 'command -v osascript'
  echo "$output" | grep -q 'CC_SUP_OS_CHANNEL'
}

@test "lead-supervisor.sh still parses" {
  run bash -n "$SUP"
  [ "$status" -eq 0 ]
}
