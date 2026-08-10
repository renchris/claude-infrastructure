#!/usr/bin/env bats
# mailbox-wake-arm.bats — the SessionStart asyncRewake ADAPTER.
#
# WHAT IT GUARDS. asyncRewake wakes the model on exit 2; cc-await-ping exits 0 on mail-arrived and 2
# on timeout. Registering the watcher directly — as the 2026-07-29 remainder specifies — would be
# SILENT on every delivered message and fire a SPURIOUS wake on every idle timeout. Every assertion
# below pins one half of that translation, plus the stream rule (the harness carries an asyncRewake
# hook's STDERR and drops its STDOUT) and the identity fallback that survives a resume.
# Design: docs/plans/CROSS_SESSION_COMMS_V2.md §10 finding 4.
#
# HERMETIC: $HOME is fixtured, and the watcher is a FAKE whose exit code each test chooses — the real
# cc-await-ping would block for hours and its verdict is not what is under test here.
#
# BATS ERREXIT DISCIPLINE: a non-final `[[ ]]`, `(( ))`, `!` or `A && B` is errexit-EXEMPT and
# therefore a DEAD assertion. Every such assertion carries `|| false`; `[ ]` as the final command is
# live and needs no suffix.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude"
  # THIRD SEAM, and it is not cosmetic: the adapter's candidate list is
  #   $(dirname $0)/../bin · ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/bin · $HOME/.claude/bin
  # CLAUDE_CONFIG_DIR is set in a real session's environment, so without this the "no watcher on
  # disk" test fell through to the operator's LIVE cc-await-ping and blocked for its full 14340 s
  # timeout. Fixturing $HOME alone does not close it (memory hermetic-in-stubs-not-in-interpreter).
  export CLAUDE_CONFIG_DIR="$HOME/.claude"
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mbox"
  mkdir -p "$CC_MAILBOX_DIR"

  # A fixtured tree shaped like the repo, so the adapter's FIRST candidate path
  # ($(dirname $0)/../bin/cc-await-ping) resolves to our fake rather than the live watcher.
  FAKE="$BATS_TEST_TMPDIR/tree"
  mkdir -p "$FAKE/hooks" "$FAKE/bin"
  cp "$REPO/hooks/mailbox-wake-arm.sh" "$FAKE/hooks/"
  chmod +x "$FAKE/hooks/mailbox-wake-arm.sh"
  ARM="$FAKE/hooks/mailbox-wake-arm.sh"
  ARGV="$BATS_TEST_TMPDIR/argv"

  PANE="AAAAAAAA-1111-2222-3333-444444444444"
  SESS="11111111-aaaa-bbbb-cccc-000000000001"
  export ITERM_SESSION_ID="w0t0p0:$PANE"

  # HEADLESS-GUARD SEAM — every legacy test models the INTERACTIVE dispatch the adapter was proven
  # on. Without this pin the guard walks the REAL process tree: green when bats runs under an
  # operator's interactive claude ancestor, red under launchd — the polarity trap of
  # MEMORY.md hermetic-in-stubs-not-in-interpreter. Guard-specific tests override per-case.
  export CC_WAKE_ARM_HARNESS_ARGV="/fixture/.claude-220/node_modules/.bin/claude --permission-mode auto --model claude-opus-5"
}

# Install a fake watcher that records its argv and exits with the code this test is about.
fake_ping() { # <exit-code> [stdout-body]
  cat > "$FAKE/bin/cc-await-ping" <<FAKEEOF
#!/bin/bash
printf '%s\n' "\$*" > "$ARGV"
[ -n "${2:-}" ] && printf '%s\n' "${2:-}"
exit ${1}
FAKEEOF
  chmod +x "$FAKE/bin/cc-await-ping"
}

# Run the adapter with a harness stdin payload, capturing the two streams SEPARATELY — the whole
# point of this file is which stream the body lands on.
run_arm() { # [session_id]
  local sid="${1:-}"
  if [ -n "$sid" ]; then printf '{"session_id":"%s"}' "$sid"; else printf '{}'; fi \
    | "$ARM" >"$BATS_TEST_TMPDIR/out" 2>"$BATS_TEST_TMPDIR/err"
}

# ── THE INVERSION — the reason this adapter exists ───────────────────────────────────────────────

@test "INVERSION: watcher rc 0 (MAIL ARRIVED) becomes adapter exit 2 — the wake" {
  fake_ping 0 "2026-08-09T10:00:00-0700 [peer] the seam ruling you asked for"
  run run_arm "$SESS"
  [ "$status" -eq 2 ]
}

@test "INVERSION: watcher rc 2 (TIMED OUT) becomes adapter exit 0 — silent, no synthesized turn" {
  fake_ping 2 ""
  run run_arm "$SESS"
  [ "$status" -eq 0 ]
}

@test "STREAM: the mail body goes to STDERR (the harness drops an asyncRewake hook's stdout)" {
  fake_ping 0 "2026-08-09T10:00:00-0700 [peer] deliver me on stderr"
  run run_arm "$SESS"
  [ "$status" -eq 2 ]
  grep -q 'deliver me on stderr' "$BATS_TEST_TMPDIR/err" || false
  # …and NOT on stdout, which the harness would silently discard
  [ "$(grep -c 'deliver me on stderr' "$BATS_TEST_TMPDIR/out")" = "0" ]
}

@test "INVERSION: watcher rc 4 (delivered, cursor stuck) still WAKES — a dup beats a swallow" {
  fake_ping 4 "2026-08-09T10:00:00-0700 [peer] cursor stuck but this is real mail"
  run run_arm "$SESS"
  [ "$status" -eq 2 ]
  grep -q 'cursor stuck but this is real mail' "$BATS_TEST_TMPDIR/err" || false
  grep -q 'dup, never a loss' "$BATS_TEST_TMPDIR/err" || false
}

@test "INVERSION: watcher rc 5 (ORPHANED) does NOT wake — that mail is the successor's to adopt" {
  fake_ping 5 ""
  run run_arm "$SESS"
  [ "$status" -eq 0 ]
}

@test "NEVER WAKE EMPTY: rc 0 with no body still carries readable text, never a blank reminder" {
  fake_ping 0 ""
  run run_arm "$SESS"
  [ "$status" -eq 2 ]
  grep -q 'cc-mail' "$BATS_TEST_TMPDIR/err" || false
}

# ── IDENTITY — survives the resume that unset $ITERM_SESSION_ID ──────────────────────────────────

@test "IDENTITY: the PANE is preferred when present (its keyset covers pane AND session)" {
  fake_ping 2 ""
  run run_arm "$SESS"
  grep -q "$PANE" "$ARGV" || false
}

@test "IDENTITY: with no pane in the env, it arms on the harness's session_id — the resume case" {
  fake_ping 2 ""
  unset ITERM_SESSION_ID
  CC_PANE_ID="" run run_arm "$SESS"
  grep -q "$SESS" "$ARGV" || false
}

@test "IDENTITY: with NEITHER id, it records unaddressability and does not burn a turn" {
  fake_ping 2 ""
  unset ITERM_SESSION_ID
  CC_PANE_ID="" run run_arm ""
  [ "$status" -eq 0 ]
  # loud, but on a channel that costs nothing — and written by a hook that provably RAN, which is the
  # existence evidence a missing heartbeat alone can never supply
  grep -q 'unaddressable' "$CC_MAILBOX_DIR/.unaddressable" || false
  # the watcher must not have been invoked at all
  [ ! -f "$ARGV" ]
}

# ── KILL SWITCH ──────────────────────────────────────────────────────────────────────────────────

@test "KILL SWITCH: CC_WAKE_ARM=0 is a total no-op — no watcher, no wake" {
  fake_ping 0 "should never be read"
  CC_WAKE_ARM=0 run run_arm "$SESS"
  [ "$status" -eq 0 ]
  [ ! -f "$ARGV" ]
}

# ── DEGRADE — an arming hook must never be the thing that breaks a session ───────────────────────

@test "DEGRADE: no watcher on disk is a silent no-op, never a spurious wake" {
  rm -f "$FAKE/bin/cc-await-ping"
  run run_arm "$SESS"
  [ "$status" -eq 0 ]
}

@test "BOUND: the watcher timeout is set strictly UNDER the registered hook timeout of 14400" {
  fake_ping 2 ""
  run run_arm "$SESS"
  # whichever bound binds first must be OURS, so we exit through the clean silent path rather than
  # being reaped mid-watch (the 2026-07-29 probe never established that the harness spares it)
  grep -q 'timeout 14340' "$ARGV" || false
}

# ── HEADLESS ONE-SHOT GUARD ──────────────────────────────────────────────────────────────────────
# asyncRewake is honored only when `isInteractive || hasStreamingInput` (2.1.220 dispatch gate). In
# a one-shot `claude -p`, the hook is dispatched SYNC — arming there would block session birth for
# the full watch. These pin all three branches of the guard; the interactive branch is exercised by
# every legacy test above via the setup seam.

@test "GUARD: one-shot print harness (claude -p) → NO watcher, silent exit 0" {
  fake_ping 0 "mail that must never be consumed"
  export CC_WAKE_ARM_HARNESS_ARGV="/fixture/bin/claude -p summarize the logs"
  run run_arm "$SESS"
  [ "$status" -eq 0 ]
  [ ! -f "$ARGV" ]
}

@test "GUARD: print WITH --input-format stream-json arms (streaming input keeps async dispatch)" {
  fake_ping 2 ""
  export CC_WAKE_ARM_HARNESS_ARGV="/fixture/bin/claude -p --input-format stream-json --output-format stream-json"
  run run_arm "$SESS"
  [ "$status" -eq 0 ]
  [ -f "$ARGV" ]
}

@test "GUARD: unresolvable dispatch mode (seam set-but-empty) → SKIP, never a possibly-sync watch" {
  fake_ping 0 "mail"
  export CC_WAKE_ARM_HARNESS_ARGV=""
  run run_arm "$SESS"
  [ "$status" -eq 0 ]
  [ ! -f "$ARGV" ]
}
