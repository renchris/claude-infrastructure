#!/usr/bin/env bats
# The rc block kitty-setup.sh writes makes every interactive zsh a consumer of a staged successor
# (lib/pane-successor.sh cc_pane_successor_precmd; recycle-failures-kitty-2026-10-10 REPORT fix 8).
# Since c54a3c0bd 4 of 9 recycles revoked the stage and typed the launch line instead, because the
# shell that regained the tty was a plain interactive zsh and no consumer.
#
# The subject is the WRITTEN block run by a real `zsh -i` on a real pty (script(1)): kitty-setup.sh
# --apply writes it into a sandboxed ZDOTDIR, and stdin is /dev/null, so the shell gets exactly ONE
# prompt cycle before EOF ends it. The producer is played by a fixture prelude in the same rc, since
# the pty's name is not known before the shell holds it: it stages for $TTY with the meta the case
# asks for. Each negative differs from the claiming case in ONE field, so it is refused by that guard.
# $SHELL is a fake that runs the loop program and exits, as in pane-successor.bats.
#
# RED-proof (2026-10-11, this suite against the tree at d92eaa620): `1..8`, not ok 1, 6, 7, 8 — the
# claim, the fork control and both upgrade cases (no hook is written, so the marker never appears and
# the stage is still there to revoke). Cases 2-5 guard the refusals and the gate, and pass without
# a hook; each differs from case 1 in one field, and case 6 proves case 5's instrument is live.
# Assertions are `[ ]` / `|| false`; `[[ ]]` and `(( ))` are errexit-EXEMPT in bats.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SETUP="$REPO/scripts/kitty-setup.sh"
  command -v kitty >/dev/null 2>&1 || [ -x /Applications/kitty.app/Contents/MacOS/kitty ] \
    || skip "kitty is not installed — kitty-setup.sh exits early without it"
  command -v zsh >/dev/null 2>&1 || skip "zsh is not installed"

  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/lib"
  export ZDOTDIR="$HOME"
  export CC_KITTY_CONFIG_DIR="$HOME/.config/kitty"
  export CC_KITTY_BIN_DIR="$HOME/.claude/bin"
  export CC_KITTY_SHELL_RC="$HOME/.zshrc"
  export CC_KITTY_LOGIN_RC="$HOME/.zprofile"
  export CC_KITTY_SHIM_DIR="$HOME/.claude/shims"
  export CC_KITTY_SETTINGS="$HOME/settings.json"
  # See kitty-setup-login-path.bats: step 5's round trip must never fire from the suite.
  export CC_KITTY_NO_SPAWN_CHECK=1
  printf '{"teammateMode":"iterm2"}\n' > "$CC_KITTY_SETTINGS"
  : > "$CC_KITTY_LOGIN_RC"
  # The live layer's shape: ~/.claude/lib/<file> is a symlink into the checkout.
  ln -s "$REPO/lib/pane-successor.sh" "$HOME/.claude/lib/pane-successor.sh"

  export CC_PANE_SUCCESSOR_DIR="$BATS_TEST_TMPDIR/ps"
  unset CC_PANE_SUCCESSOR CC_PANE_SUCCESSOR_TTY CC_PANE_SUCCESSOR_NOW
  unset CC_PANE_SUCCESSOR_LOOP_PID CC_PANE_SUCCESSOR_HANDBACK TERM_PROGRAM
  export KITTY_WINDOW_ID=44
  # The "watcher" whose liveness take proves is this bats process.
  export W3_WPID=$$
  W3_WLSTART="$(TZ=UTC LC_ALL=C ps -o lstart= -p "$$" | tr -s ' ' | sed 's/^ *//; s/ *$//')"
  export W3_WLSTART
  # W3_AGE = how old the stage is when the shell starts. The prelude stamps created_epoch itself:
  # under machine load kitty-setup.sh alone can outlast the TTL between setup() and the prompt.
  export W3_AGE=0 W3_TTL=120 W3_STAGE=1 W3_NOFORK=0
  export W3_CMD="$BATS_TEST_TMPDIR/succ.cmd" W3_META="$BATS_TEST_TMPDIR/meta.json"
  export W3_TTYNAME="$BATS_TEST_TMPDIR/ttyname"
  MARK="$BATS_TEST_TMPDIR/marker"
  printf 'printf "successor ran\\n" > %q\n' "$MARK" > "$W3_CMD"

  FAKESH="$BATS_TEST_TMPDIR/fakesh"
  cat > "$FAKESH" <<'EOF'
#!/bin/bash
if [ "${3:-}" = -c ]; then shift 3; exec /bin/bash -c "$@"; fi
exit 0
EOF
  chmod +x "$FAKESH"

  # The producer, before the block: stage a successor for the tty this shell holds.
  cat > "$CC_KITTY_SHELL_RC" <<'EOF'
PS1='w3> '
print -r -- "${TTY##*/}" > "$W3_TTYNAME"
if [ "$W3_STAGE" = 1 ]; then
  source "$HOME/.claude/lib/pane-successor.sh"
  printf '{"pane":"44","pane_tty":"%s","pred_sid":"s-1","watcher_pid":%s,"watcher_lstart":"%s","created_epoch":%s,"ttl_s":%s,"mode":"fresh","token":"tok"}\n' \
    "$TTY" "$W3_WPID" "$W3_WLSTART" "$(( $(date +%s) - W3_AGE ))" "$W3_TTL" > "$W3_META"
  cc_pane_successor_stage "${TTY##*/}" "$W3_CMD" "$W3_META" || print W3-STAGE-FAILED
fi
EOF
}

# What every rc gets AFTER the block: a later precmd hook that proves the prompt cycle completed, and
# (W3_NOFORK=1) a process limit under which any fork from here on fails loudly.
append_postlude() {
  cat >> "$CC_KITTY_SHELL_RC" <<'EOF'
w3_prompt_reached() { print W3-PROMPT-REACHED; }
precmd_functions+=(w3_prompt_reached)
[ "$W3_NOFORK" = 1 ] && ulimit -u 1
EOF
}

apply() { bash "$SETUP" >/dev/null 2>&1 || true; }

# $@ = the ONE field this case changes, as env assignments.
one_prompt_cycle() { run env SHELL="$FAKESH" "$@" script -q /dev/null zsh -i </dev/null; }

staged_cmd() { printf '%s/%s.cmd' "$CC_PANE_SUCCESSOR_DIR" "$(cat "$W3_TTYNAME")"; }

assert_not_claimed() {
  [[ "$output" != *W3-STAGE-FAILED* ]] || { echo "$output"; false; }
  [[ "$output" == *W3-PROMPT-REACHED* ]] || { echo "$output"; false; }
  [ ! -e "$MARK" ] || { echo "the successor ran"; false; }
  [ -f "$(staged_cmd)" ] || { ls -la "$CC_PANE_SUCCESSOR_DIR"; false; }
}

@test "an interactive zsh claims the successor staged for its tty within one prompt cycle" {
  apply; append_postlude
  one_prompt_cycle
  [ -f "$MARK" ] || { echo "$output"; ls -la "$CC_PANE_SUCCESSOR_DIR"; false; }
  # The watcher's view: its revoke finds nothing, so it writes no recycle-successor-revoked row
  # and never types.
  # shellcheck source=/dev/null  # runtime path; the lib is linted as its own file
  . "$REPO/lib/pane-successor.sh"
  run cc_pane_successor_revoke "$(cat "$W3_TTYNAME")"
  [ "$status" -ne 0 ]
  [ ! -e "$CC_PANE_SUCCESSOR_DIR/$(cat "$W3_TTYNAME").revoked" ]
  run cc_pane_successor_claimed "$(cat "$W3_TTYNAME")"
  [ "$status" -eq 0 ]
}

@test "no claim: same tty, but the stage was made for another kitty window" {
  apply; append_postlude
  one_prompt_cycle KITTY_WINDOW_ID=45
  assert_not_claimed
}

@test "no claim: the watcher that staged it is dead" {
  apply; append_postlude
  one_prompt_cycle W3_WLSTART="Thu Jan  1 00:00:00 1970"
  assert_not_claimed
}

@test "no claim: the stage is past its TTL" {
  apply; append_postlude
  one_prompt_cycle W3_AGE=600
  assert_not_claimed
}

@test "nothing staged: the prompt hook forks nothing" {
  apply; append_postlude
  one_prompt_cycle W3_STAGE=0 W3_NOFORK=1
  [[ "$output" == *W3-PROMPT-REACHED* ]] || { echo "$output"; false; }
  [[ "$output" != *"fork failed"* ]] || { echo "$output"; false; }
}

@test "control for the case above: with a stage present the same limit catches the hook's fork" {
  apply; append_postlude
  one_prompt_cycle W3_NOFORK=1
  [[ "$output" == *"fork failed"* ]] || { echo "$output"; false; }
}

# ── delivery: the block every machine already has predates the hook ──────────────────────────────

# The block as written before fix 8: it has the cc-in-kitty token the old staleness test keyed on.
seed_pre_hook_block() {
  cat >> "$CC_KITTY_SHELL_RC" <<'EOF'
# >>> cc-kitty-agent-teams >>>
if [ -n "${KITTY_WINDOW_ID:-}" ] && [ -x "$HOME/.claude/bin/cc-in-kitty" ] && "$HOME/.claude/bin/cc-in-kitty"; then
  export ITERM_SESSION_ID="w0t0p0:$KITTY_WINDOW_ID"
fi
# <<< cc-kitty-agent-teams <<<
EOF
}

@test "apply upgrades a block that predates the hook, and the upgraded shell claims" {
  seed_pre_hook_block
  apply; append_postlude
  [ "$(grep -c '>>> cc-kitty-agent-teams >>>' "$CC_KITTY_SHELL_RC")" -eq 1 ] || { cat "$CC_KITTY_SHELL_RC"; false; }
  one_prompt_cycle
  [ -f "$MARK" ] || { echo "$output"; cat "$CC_KITTY_SHELL_RC"; false; }
}

@test "--check reports a block that predates the hook as outdated, and writes nothing" {
  seed_pre_hook_block
  local before; before="$(cat "$CC_KITTY_SHELL_RC")"
  run bash "$SETUP" --check
  [[ "$output" == *"OUTDATED cc-kitty-agent-teams block"* ]] || { echo "$output"; false; }
  [ "$before" = "$(cat "$CC_KITTY_SHELL_RC")" ]
}
