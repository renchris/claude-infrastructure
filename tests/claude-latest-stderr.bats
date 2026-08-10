#!/usr/bin/env bats
# claude-latest — per-session stderr capture (crash forensics). The launcher tees
# claude.exe stderr to a bounded ~/.claude/logs/stderr/<ts>-<pid>.log so a hard
# crash's final diagnostic ("error text -> bare shell") survives on disk, while the
# live terminal still shows stderr and the exit code is preserved. A clean run
# leaves a 0-byte log that the NEXT launch garbage-collects (dead pid + empty).
# Kill switch: CLAUDE_STDERR_CAPTURE=0.
#
# Tests run the REAL launcher against a stubbed binary (CLAUDE_SKIP_UPDATE=1 =>
# hermetic, no network). Coverage: exit code + stdout preserved through the tee ·
# stderr captured to a log · kill-switch disables capture · empty dead-pid log GC'd.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LAUNCHER="$REPO/bin/claude-latest"
  export HOME="$BATS_TEST_TMPDIR/home"
  export CLAUDE_SKIP_UPDATE=1                 # skip update_if_needed (no network)
  BIN="$HOME/.claude-versions/current/node_modules/.bin"
  SD="$HOME/.claude/logs/stderr"
  mkdir -p "$BIN" "$HOME/.claude/logs"
}

# stub the real binary: echo stdout, optionally emit a stderr line, exit chosen code
mk_stub() { # $1=exitcode  $2=stderr-line(optional)
  {
    echo '#!/bin/bash'
    echo 'echo "STUB-STDOUT $*"'
    [ -n "${2:-}" ] && echo "echo '$2' >&2"
    echo "exit ${1:-0}"
  } > "$BIN/claude"
  chmod +x "$BIN/claude"
}

@test "exit code + stdout preserved through the tee" {
  mk_stub 7 "STUB-STDERR-BOOM"
  run bash "$LAUNCHER" HELLO
  [ "$status" -eq 7 ]
  [[ "$output" == *"STUB-STDOUT HELLO"* ]]
}

@test "CLAUDE_CODE_STOP_HOOK_BLOCK_CAP: defaulted to 50 (/goal runway); an operator override wins" {
  # The harness force-ends a turn after N consecutive hook-blocked stops (binary default 8), and an
  # UNMET /goal evaluation is such a block — docs/research/goal-in-handoff-2026-08-08.md
  # § RESOLUTION. The launcher is the one funnel every session passes through, so the default must
  # be visible in the exec'd binary's environment, and an explicit operator value must survive.
  {
    echo '#!/bin/bash'
    echo 'echo "CAP=${CLAUDE_CODE_STOP_HOOK_BLOCK_CAP:-unset}"'
    echo 'exit 0'
  } > "$BIN/claude"; chmod +x "$BIN/claude"
  run bash "$LAUNCHER"
  [[ "$output" == *"CAP=50"* ]] || false
  run env CLAUDE_CODE_STOP_HOOK_BLOCK_CAP=8 bash "$LAUNCHER"
  [[ "$output" == *"CAP=8"* ]] || false
}

@test "stderr is captured to a per-pid log" {
  mk_stub 1 "FATAL-HEAP-OOM"
  run bash "$LAUNCHER" X
  run grep -rl 'FATAL-HEAP-OOM' "$SD"
  [ "$status" -eq 0 ]
}

@test "kill switch disables capture (no stderr log written)" {
  mk_stub 0 "SHOULD-NOT-CAPTURE"
  export CLAUDE_STDERR_CAPTURE=0
  run bash "$LAUNCHER" X
  [ "$status" -eq 0 ]
  [ ! -d "$SD" ] || [ -z "$(ls -A "$SD" 2>/dev/null)" ]
}

@test "clean-run empty log of a dead pid is GC'd on the next launch" {
  mkdir -p "$SD"
  : > "$SD/20000101T000000-999999.log"        # stale, empty, definitely-dead pid
  mk_stub 0 ""                                 # clean run, writes no stderr
  run bash "$LAUNCHER" X
  [ "$status" -eq 0 ]
  [ ! -e "$SD/20000101T000000-999999.log" ]    # GC'd
}
