#!/usr/bin/env bats
# kitty-setup-guard-link — scripts/kitty-setup.sh deploys bin/kitty-fullscreen-guard into the bin dir.
#
# WHY (review wf_bf440f65-940, kitty-crash-2026-10-15). install.sh links only bin/cc-*, desk-*, ms365-*
# and dl*; every kitty-* tool reaches ~/.claude/bin through kitty-setup.sh's explicit list. kitty.conf's
# detach / close_tab rebinds launch ${HOME}/.claude/bin/kitty-fullscreen-guard BY THAT PATH, and ⌘W and
# the pane menu fail CLOSED without the guard — so a guard missing from the list is every close chord
# and every menu move refused, on every pane, with nothing on screen.
#
# RED-proof: against `git show 59562cfd6:scripts/kitty-setup.sh` (before the guard joined the list)
# both cases fail: no link, and --check says nothing about the guard.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SETUP="${KSG_SETUP:-$REPO/scripts/kitty-setup.sh}"
  command -v kitty >/dev/null 2>&1 || [ -x /Applications/kitty.app/Contents/MacOS/kitty ] \
    || skip "kitty is not installed — kitty-setup.sh exits early without it"
  unset KITTY_LISTEN_ON KITTY_WINDOW_ID KITTY_PID
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_KITTY_CONFIG_DIR="$HOME/.config/kitty"
  export CC_KITTY_BIN_DIR="$HOME/.claude/bin"
  export CC_KITTY_SHELL_RC="$HOME/.zshrc"
  export CC_KITTY_LOGIN_RC="$HOME/.zprofile"
  export CC_KITTY_SHIM_DIR="$HOME/.claude/shims"
  export CC_KITTY_SETTINGS="$HOME/settings.json"
  export CC_KITTY_NO_SPAWN_CHECK=1   # never the live round trip from the suite
  printf '{"teammateMode":"iterm2"}\n' > "$CC_KITTY_SETTINGS"
  : > "$CC_KITTY_SHELL_RC"; : > "$CC_KITTY_LOGIN_RC"
}

@test "apply links kitty-fullscreen-guard beside the tools that call it, pointing into the checkout" {
  run bash "$SETUP"
  [ -L "$CC_KITTY_BIN_DIR/kitty-fullscreen-guard" ] || { echo "$output"; ls -la "$CC_KITTY_BIN_DIR"; false; }
  [ "$(readlink "$CC_KITTY_BIN_DIR/kitty-fullscreen-guard")" = "$(cd "$(dirname "$SETUP")/.." && pwd)/bin/kitty-fullscreen-guard" ]
  [ -x "$CC_KITTY_BIN_DIR/kitty-fullscreen-guard" ]
}

@test "--check names the guard: deployed after apply, missing before" {
  run bash "$SETUP" --check
  [[ "$output" == *"kitty-fullscreen-guard missing"* ]] || { echo "$output"; false; }
  bash "$SETUP" >/dev/null 2>&1 || true
  run bash "$SETUP" --check
  [[ "$output" == *"kitty-fullscreen-guard deployed"* ]] || { echo "$output"; false; }
}
