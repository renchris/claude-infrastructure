#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031
#   Every @test body is its own subshell, so an export inside one is test-local.
#
# handoff-fire refuses a directory argument that is not an existing absolute directory free of control
# characters — exit 2, before any gate, before any spawn and before any spawn row (lr-wake incident
# 2026-10-18, REPORT §4 Wave E; RC7). Pane 403: an agent's `sed` misparse produced the cwd
# $'whose\n/Users/chrisren/Development/claude-infrastructure'; `--cwd` took it verbatim, the fire
# spawned, the pane printed `zsh:cd:1: no such file or directory`, kept a plain shell, and the fire said
# nothing for its whole engagement window.
#
# RED on origin/main before this wave: --cwd and --resume-cwd were accepted unvalidated (the dry-run
# cases exited 0 and the real fire went on to the spawn path), and stamp-peer said exit 1.
#
# Hermetic: HOME, the spawn log and every terminal are stubs; the real-fire case has no anchor and the
# headless resolver is switched off, so even an unfixed tree cannot reach a real terminal.

setup() {
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  # Seams that do NOT resolve under $HOME (test-hermeticity-lint 5a/5b): absent paths, sensors fail open.
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/account-sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/no-such-claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  HF="$REPO/scripts/handoff-fire.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/logs"
  export CC_SPAWN_LOG_FILE="$BATS_TEST_TMPDIR/spawns.jsonl"
  export KLOG="$BATS_TEST_TMPDIR/kitty.log" KSTATE="$BATS_TEST_TMPDIR/ls.json"; : > "$KLOG"; echo '[]' > "$KSTATE"
  export CC_TERM_KITTY="$BATS_TEST_DIRNAME/fixtures/pane-placement/fake-kitty.py"
  export CC_TERM_KITTY_TO="unix:$BATS_TEST_TMPDIR/sock"
  export CC_FIRE_HEADLESS_ANCHOR=off IT2_WRAPPER_NO_KITTY=1
  unset KITTY_WINDOW_ID ITERM_SESSION_ID CLAUDE_SESSION_ID
  STUB="$BATS_TEST_TMPDIR/stub"; mkdir -p "$STUB"
  printf '#!/bin/sh\necho "osascript $*" >> "%s"\nexit 1\n' "$KLOG" > "$STUB/osascript"; chmod +x "$STUB/osascript"
  export PATH="$STUB:$PATH"
  PF="$BATS_TEST_TMPDIR/p.txt"; printf 'brief\n' > "$PF"
  GOOD="$BATS_TEST_TMPDIR/good dir"; mkdir -p "$GOOD"
}

fire() { bash "$HF" --prompt-file "$PF" --launcher claude-test "$@"; }

@test "THE PANE-403 CWD: \$'whose\\n/tmp' exits 2, says why, and writes no spawn row" {
  run fire --cwd $'whose\n/tmp' --dry-run
  echo "$output"
  [ "$status" -eq 2 ]
  [[ "$output" == *"--cwd REFUSED"*"control character"* ]] || false
  [ ! -s "$CC_SPAWN_LOG_FILE" ]
}

@test "a RELATIVE --cwd exits 2" {
  run fire --cwd some/relative/dir --dry-run
  [ "$status" -eq 2 ]
  [[ "$output" == *"--cwd REFUSED"*"not absolute"* ]] || false
}

@test "a NONEXISTENT --cwd exits 2" {
  run fire --cwd "$BATS_TEST_TMPDIR/no-such-dir" --dry-run
  [ "$status" -eq 2 ]
  [[ "$output" == *"--cwd REFUSED"*"not a directory"* ]] || false
}

@test "the REAL fire (no --dry-run) refuses BEFORE any gate or spawn: no spawn row, no kitty launch" {
  run fire --cwd $'whose\n/tmp'
  echo "$output"
  [ "$status" -eq 2 ]
  [ ! -s "$CC_SPAWN_LOG_FILE" ]
  ! grep -q -- 'launch' "$KLOG" || false
  # before the capacity gate and the payload gates: none of their rows were written
  [ ! -s "$HOME/.claude/logs/handoffs.jsonl" ] || ! grep -q 'whose' "$HOME/.claude/logs/handoffs.jsonl"
}

@test "--resume-cwd is validated the same way (relative and control characters)" {
  run fire --resume-cwd rel/dir --dry-run
  [ "$status" -eq 2 ]
  [[ "$output" == *"--resume-cwd REFUSED"* ]] || false
  run fire --resume-cwd $'/tmp\tx' --dry-run
  [ "$status" -eq 2 ]
  [[ "$output" == *"--resume-cwd REFUSED"*"control character"* ]] || false
}

@test "stamp-peer --cwd: a control character exits 2 and writes no stamp" {
  export CC_FIRED_DIR="$BATS_TEST_TMPDIR/fired"
  run bash "$HF" stamp-peer --pane 28 --cwd $'whose\n/tmp' --by 2
  [ "$status" -eq 2 ]
  [[ "$output" == *"stamp-peer --cwd REFUSED"* ]] || false
  [ ! -f "$CC_FIRED_DIR/28.json" ]
}

@test "CONTROL: an existing absolute directory (with a space in it) passes the validation" {
  run fire --cwd "$GOOD" --dry-run
  echo "$output"
  [ "$status" -eq 0 ]
  ! [[ "$output" == *"REFUSED"* ]] || false
}
