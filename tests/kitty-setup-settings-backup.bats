#!/usr/bin/env bats
# kitty-setup.sh's teammateMode step backs up each REAL settings.json once, and only when it changes
# it. It used to `cp` through every account dir's symlink on every apply, leaving 2,000+ real
# settings.json.bak-kitty-* copies across the account dirs by 2026-10-01 — each one a FORKED line
# the config mirror printed before every `claude` launch.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SETUP="$REPO/scripts/kitty-setup.sh"
  command -v kitty >/dev/null 2>&1 || [ -x /Applications/kitty.app/Contents/MacOS/kitty ] \
    || skip "kitty is not installed — kitty-setup.sh exits early without it"

  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/main" "$HOME/acct"
  export CC_KITTY_CONFIG_DIR="$HOME/.config/kitty"
  export CC_KITTY_BIN_DIR="$HOME/.claude/bin"
  export CC_KITTY_SHELL_RC="$HOME/.zshrc"
  export CC_KITTY_LOGIN_RC="$HOME/.zprofile"
  export CC_KITTY_SHIM_DIR="$HOME/.claude/shims"
  export CC_KITTY_NO_SPAWN_CHECK=1
  # One real file and an account dir that reaches it through a symlink — the live layout.
  printf '{"teammateMode":"tmux"}\n' > "$HOME/main/settings.json"
  ln -s "$HOME/main/settings.json" "$HOME/acct/settings.json"
  export CC_KITTY_SETTINGS="$HOME/main/settings.json
$HOME/acct/settings.json"
  : > "$CC_KITTY_SHELL_RC"
  : > "$CC_KITTY_LOGIN_RC"
}

baks() { find "$HOME/main" "$HOME/acct" -name 'settings.json.bak-kitty-*' | wc -l | tr -d ' '; }

@test "one backup per REAL file, beside it — never a real copy in the symlinked account dir" {
  run bash "$SETUP"
  grep -q '"teammateMode": "iterm2"' "$HOME/main/settings.json" || { cat "$HOME/main/settings.json"; false; }
  [ -L "$HOME/acct/settings.json" ] || { echo "the account dir's symlink was replaced"; false; }
  [ "$(baks)" = 1 ] || { find "$HOME" -name '*bak-kitty*'; false; }
  [ -z "$(find "$HOME/acct" -name 'settings.json.bak-kitty-*')" ] || { echo "a real backup landed in the account dir"; false; }
}

@test "a re-apply with nothing to change writes no backup at all" {
  bash "$SETUP" >/dev/null 2>&1 || true
  before="$(baks)"
  run bash "$SETUP"
  [ "$(baks)" = "$before" ] || { echo "backups $before -> $(baks)"; false; }
}
