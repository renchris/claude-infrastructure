#!/usr/bin/env bats
# kitty-setup.sh step 3b — login-shell PATH precedence for the `it2` Claude Code actually drives.
#
# THE DEFECT THIS PINS. Claude Code resolves its it2 with `$SHELL -lc "command -v it2"` and then
# EXECUTES `<that path> session list`, requiring exit 0 (function Uor, read out of the live 2.1.219
# binary). `zsh -lc` is login-but-NOT-interactive, so it reads .zprofile and NEVER .zshrc — and
# ~/.claude/bin, where the it2 wrapper lives, was added to PATH only in .zshrc. Whichever it2 an
# earlier PATH entry owned therefore won. On this box that was a uv-installed real it2, whose
# `session list` fails inside kitty with rc=2, so Agent Teams died with "the it2 CLI is not
# reachable" while every file-existence check in this same script reported green.
#
# Because Uor() CACHES the resolved path for all later calls, losing that race is not only a kitty
# failure: on iTerm2 it silently bypasses bin/it2-wrapper, forfeiting the never-prompt profile, the
# forced close, and the 30s process bound whose absence deadlocked the fleet on 2026-07-25.
#
# WHAT IS AND IS NOT TESTED HERE. The apply/undo/idempotence contract is hermetic and is pinned
# below. The live half — that the operator's real login shell now resolves the wrapper — cannot be
# made hermetic (it depends on the actual $SHELL and real dotfiles), so it is deliberately NOT
# asserted here; `kitty-setup.sh --check` performs that probe against the real environment by
# replaying Uor() itself. Asserting it here would only encode which machine ran the suite.
#
# Assertions are `[ ]` / `|| false`; `[[ ]]` and `(( ))` are errexit-EXEMPT in bats.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SETUP="$REPO/scripts/kitty-setup.sh"
  command -v kitty >/dev/null 2>&1 || [ -x /Applications/kitty.app/Contents/MacOS/kitty ] \
    || skip "kitty is not installed — kitty-setup.sh exits early without it"

  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  # Every seam pointed into the tmpdir, so a run cannot touch the operator's real dotfiles,
  # ~/.claude/bin, or ~/.config/kitty. A test for a script that edits dotfiles must be incapable
  # of editing the real ones.
  export CC_KITTY_CONFIG_DIR="$HOME/.config/kitty"
  export CC_KITTY_BIN_DIR="$HOME/.claude/bin"
  export CC_KITTY_SHELL_RC="$HOME/.zshrc"
  export CC_KITTY_LOGIN_RC="$HOME/.zprofile"
  export CC_KITTY_SHIM_DIR="$HOME/.claude/shims"
  export CC_KITTY_SETTINGS="$HOME/settings.json"
  # Step 5 proves the USE path by really splitting a pane and closing it. That is the right check
  # for an operator running --check in their own terminal and the WRONG thing for a test suite: run
  # from a genuine kitty pane it would open and close panes in the operator's live window on every
  # invocation. A guard whose verifier triggers the guarded effect is its own defect.
  export CC_KITTY_NO_SPAWN_CHECK=1
  printf '{"teammateMode":"iterm2"}\n' > "$CC_KITTY_SETTINGS"
  : > "$CC_KITTY_SHELL_RC"
  : > "$CC_KITTY_LOGIN_RC"
}

apply() { run bash "$SETUP"; }

@test "apply creates the shim symlink pointing at the it2 wrapper" {
  apply
  [ -L "$CC_KITTY_SHIM_DIR/it2" ] || { echo "$output"; false; }
  [ "$(readlink "$CC_KITTY_SHIM_DIR/it2")" = "$CC_KITTY_BIN_DIR/it2" ] || {
    echo "shim points at $(readlink "$CC_KITTY_SHIM_DIR/it2")"; false; }
}

@test "apply writes the PATH block into the LOGIN rc, not the interactive one" {
  apply
  # .zprofile is the file `zsh -lc` reads; .zshrc is the file it does NOT. Writing the PATH fix to
  # .zshrc would look identical in a diff and fix nothing at all, so the FILE is the assertion.
  grep -q 'cc-it2-login-path' "$CC_KITTY_LOGIN_RC" || { echo "login rc:"; cat "$CC_KITTY_LOGIN_RC"; false; }
  # `! A || { …; false; }` is the live form. `A && { …; false; }` is and-absorbed by errexit, and
  # the mechanical `… || false` repair fails on BOTH branches — measured, not assumed.
  ! grep -q 'cc-it2-login-path' "$CC_KITTY_SHELL_RC" || { echo "PATH block landed in .zshrc, which -lc never reads"; false; }
}

@test "the block prepends the shim dir, so it beats an earlier it2 on PATH" {
  apply
  # Prepending is the whole mechanism: appending would leave the losing entry still winning.
  grep -qE "export PATH=\"$CC_KITTY_SHIM_DIR:\\\$PATH\"" "$CC_KITTY_LOGIN_RC" || {
    echo "login rc:"; cat "$CC_KITTY_LOGIN_RC"; false; }
}

@test "apply is idempotent — a second run does not duplicate the block" {
  apply
  apply
  N=$(grep -c '>>> cc-it2-login-path >>>' "$CC_KITTY_LOGIN_RC")
  [ "$N" -eq 1 ] || { echo "block written $N times"; cat "$CC_KITTY_LOGIN_RC"; false; }
}

@test "undo removes both the block and the shim, and leaves the rc otherwise intact" {
  printf '# operator line that must survive\n' > "$CC_KITTY_LOGIN_RC"
  apply
  grep -q 'cc-it2-login-path' "$CC_KITTY_LOGIN_RC" || { echo "precondition failed"; false; }
  run bash "$SETUP" --undo
  ! grep -q 'cc-it2-login-path' "$CC_KITTY_LOGIN_RC" || { echo "block survived undo"; cat "$CC_KITTY_LOGIN_RC"; false; }
  [ ! -L "$CC_KITTY_SHIM_DIR/it2" ] || { echo "shim survived undo"; false; }
  grep -q 'operator line that must survive' "$CC_KITTY_LOGIN_RC" || {
    echo "undo ate unrelated content:"; cat "$CC_KITTY_LOGIN_RC"; false; }
}

@test "undo leaves a shim dir alone when it still holds someone else's shim" {
  apply
  printf '#!/bin/sh\n' > "$CC_KITTY_SHIM_DIR/other-tool"; chmod +x "$CC_KITTY_SHIM_DIR/other-tool"
  run bash "$SETUP" --undo
  # rmdir refuses a non-empty dir, which is exactly the protection wanted: undoing THIS tool must
  # not delete a directory a future tool also parks a shim in.
  [ -d "$CC_KITTY_SHIM_DIR" ] || { echo "undo removed a shim dir that was still in use"; false; }
  [ -x "$CC_KITTY_SHIM_DIR/other-tool" ] || { echo "undo deleted an unrelated shim"; false; }
}

@test "--check reports the 3b probe rather than only file existence" {
  apply
  run bash "$SETUP" --check
  # The check must replay Claude Code's gate. A pure file-existence check reported 11/11 green
  # throughout the outage this step fixes, so the presence of the probe line is itself the
  # regression guard against sliding back to existence-only checking.
  echo "$output" | grep -q 'session list' || { echo "$output"; false; }
  echo "$output" | grep -q 'login-shell it2 resolves' || { echo "$output"; false; }
}
