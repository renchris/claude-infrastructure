#!/usr/bin/env bats
# boot-resume-launch.sh — the TTY-coupled resume seam (T-P16-2). The GUI drive (iTerm2) is not
# unit-testable, but --dry-run makes the command-construction (shell-quoting a spacey cwd, the
# osascript assembly, the reso-resume-one arg order) fully verifiable without a display.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LAUNCH="$REPO/scripts/boot-resume-launch.sh"
  export CC_RESUME_ONE_BIN="/Users/x/.reso/bin/reso-resume-one"
  # PIN THE TERMINAL. Since 2026-07-31 the script has a kitty arm, so every assertion below is
  # about the iTerm2 arm SPECIFICALLY — and this suite is now routinely run from inside kitty,
  # where an inherited KITTY_WINDOW_ID would otherwise decide the verdict. The kitty arm has its
  # own suite (tests/kitty-recovery-launch.bats).
  unset KITTY_WINDOW_ID
  export IT2_WRAPPER_NO_KITTY=1
}

@test "--help exits 0" {
  run bash "$LAUNCH" --help
  [ "$status" -eq 0 ]
}

@test "missing args → usage exit 2" {
  run bash "$LAUNCH"
  [ "$status" -eq 2 ]
}

@test "dry-run builds a reso-resume-one command with account, cwd, sid" {
  run bash "$LAUNCH" --dry-run next4 /Users/x/Development/.worktrees/wt-zeta sid-123
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "reso-resume-one"
  echo "$output" | grep -q "next4"
  echo "$output" | grep -q "/Users/x/Development/.worktrees/wt-zeta"
  echo "$output" | grep -q "sid-123"
  echo "$output" | grep -q "create window with default profile"
  echo "$output" | grep -q "write text"
}

@test "dry-run: a cwd with spaces stays single-quoted (survives the write-text shell)" {
  run bash "$LAUNCH" --dry-run next2 "/Users/x/My Worktrees/wt a" sid-x branchy
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "'/Users/x/My Worktrees/wt a'"
  echo "$output" | grep -q "branchy"      # optional branch arg carried through
}

@test "CC_LAUNCH_DRYRUN=1 env also triggers dry-run" {
  CC_LAUNCH_DRYRUN=1 run bash "$LAUNCH" next /tmp/wt sid9
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "CMD:"
}
