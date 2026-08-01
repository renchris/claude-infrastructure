#!/usr/bin/env bats
# kitty-setup.sh step 3 — the ITERM_SESSION_ID block it writes into the interactive rc.
#
# THE DEFECT THIS PINS (2026-07-31). The block used to be guarded by
#
#     if [ -n "${KITTY_WINDOW_ID:-}" ] && [ -z "${ITERM_SESSION_ID:-}" ]; then
#
# The second clause reads as conservative — "don't clobber what iTerm2 set" — and is the bug. A
# kitty pane launched from an iTerm2 pane INHERITS ITERM_SESSION_ID, so the guard preserved a stale
# iTerm2 pane UUID. Claude Code sliced that UUID out as the leader pane id and handed it to a kitty
# translator that cannot map it: every teammate spawn died with `not a kitty window id` while the
# backend's `session list` probe stayed green. Inside kitty, KITTY_WINDOW_ID is the only authority
# on which pane this is, so the export must be UNCONDITIONAL there.
#
# The mirror half is just as load-bearing: KITTY_WINDOW_ID is itself inherited by every iTerm2 pane
# under an iTerm2 launched from kitty, so "am I in kitty" is decided by bin/cc-in-kitty (ancestry),
# never by the variable. Overwriting a real iTerm2 id with a synthesised kitty one would be strictly
# worse than the original bug.
#
# Assertions are `[ ]` / `|| false`; `[[ ]]` and `(( ))` are errexit-EXEMPT in bats.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SETUP="$REPO/scripts/kitty-setup.sh"
  command -v kitty >/dev/null 2>&1 || [ -x /Applications/kitty.app/Contents/MacOS/kitty ] \
    || skip "kitty is not installed — kitty-setup.sh exits early without it"

  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_KITTY_CONFIG_DIR="$HOME/.config/kitty"
  export CC_KITTY_BIN_DIR="$HOME/.claude/bin"
  export CC_KITTY_SHELL_RC="$HOME/.zshrc"
  export CC_KITTY_LOGIN_RC="$HOME/.zprofile"
  export CC_KITTY_SHIM_DIR="$HOME/.claude/shims"
  export CC_KITTY_SETTINGS="$HOME/settings.json"
  # See kitty-setup-login-path.bats: step 5's round trip must never fire from the suite.
  export CC_KITTY_NO_SPAWN_CHECK=1
  printf '{"teammateMode":"iterm2"}\n' > "$CC_KITTY_SETTINGS"
  : > "$CC_KITTY_SHELL_RC"
  : > "$CC_KITTY_LOGIN_RC"
  BLOCK_ID="cc-kitty-agent-teams"
}

apply() { run bash "$SETUP"; }

# The block exactly as an existing machine already carries it — the state every ~/.zshrc that ever
# ran the old setup is in right now.
seed_stale_block() {
  cat > "$CC_KITTY_SHELL_RC" <<'EOF'
# operator line above that must survive
# >>> cc-kitty-agent-teams >>>
# Claude Code gates its iTerm2 pane backend on an ENV VAR (it never handshakes with iTerm2):
if [ -n "${KITTY_WINDOW_ID:-}" ] && [ -z "${ITERM_SESSION_ID:-}" ]; then
  export ITERM_SESSION_ID="w0t0p0:$KITTY_WINDOW_ID"
fi
# <<< cc-kitty-agent-teams <<<
# operator line below that must survive
EOF
}

block_of() { sed -n "/# >>> $BLOCK_ID >>>/,/# <<< $BLOCK_ID <<</p" "$CC_KITTY_SHELL_RC"; }

# Run the written block under zsh with a stubbed verdict, and report what ITERM_SESSION_ID becomes.
# $1 = exit code for cc-in-kitty, $2 = the ITERM_SESSION_ID already in the environment.
eval_block() {
  mkdir -p "$CC_KITTY_BIN_DIR"
  rm -f "$CC_KITTY_BIN_DIR/cc-in-kitty"
  { printf '#!/bin/bash\n'; printf 'exit %s\n' "$1"; } > "$CC_KITTY_BIN_DIR/cc-in-kitty"
  chmod +x "$CC_KITTY_BIN_DIR/cc-in-kitty"
  block_of > "$BATS_TEST_TMPDIR/block.zsh"
  HOME="$HOME" KITTY_WINDOW_ID=11 ITERM_SESSION_ID="$2" \
    zsh -c "source '$BATS_TEST_TMPDIR/block.zsh'; printf '%s\n' \"\$ITERM_SESSION_ID\""
}

# ── what gets written ────────────────────────────────────────────────────────────────────────────

@test "apply writes a block that decides the terminal by ancestry, not by \$KITTY_WINDOW_ID" {
  apply
  grep -q "$BLOCK_ID" "$CC_KITTY_SHELL_RC" || { echo "$output"; false; }
  block_of | grep -q 'cc-in-kitty' || { block_of; false; }
}

@test "the written block carries NO -z ITERM_SESSION_ID guard — the override is unconditional" {
  apply
  # The single character-level assertion this whole file exists for.
  ! block_of | grep -q 'z "${ITERM_SESSION_ID' || { echo "the stale guard was written:"; block_of; false; }
}

@test "the written block is valid zsh — a heredoc slip here breaks every new shell" {
  apply
  block_of > "$BATS_TEST_TMPDIR/block.zsh"
  run zsh -n "$BATS_TEST_TMPDIR/block.zsh"
  [ "$status" -eq 0 ] || { echo "$output"; block_of; false; }
}

# ── what it DOES: the behaviour, sourced ─────────────────────────────────────────────────────────

@test "REGRESSION ANCHOR: inside kitty it OVERWRITES an inherited iTerm2 id" {
  # The 2026-07-31 failure in one line. Pre-fix this printed the iTerm2 UUID straight back out, and
  # Claude Code handed that UUID to it2-kitty.
  apply
  run eval_block 0 "w0t15p4:E5D77446-2AE5-4463-929A-7ACBCD97018E"
  [ "$output" = "w0t0p0:11" ] || { echo "got '$output', want w0t0p0:11"; false; }
}

@test "inside kitty with nothing inherited, it still sets the id" {
  apply
  run eval_block 0 ""
  [ "$output" = "w0t0p0:11" ] || { echo "got '$output'"; false; }
}

@test "MIRROR ANCHOR: in an iTerm2 pane with an inherited KITTY_WINDOW_ID it changes NOTHING" {
  # Overwriting iTerm2's own correct pane id with a synthesised kitty one would be worse than the
  # bug this block fixes — it would break handoff, self-close and every pane-liveness read at once.
  apply
  run eval_block 1 "w0t15p4:E5D77446-2AE5-4463-929A-7ACBCD97018E"
  [ "$output" = "w0t15p4:E5D77446-2AE5-4463-929A-7ACBCD97018E" ] || { echo "got '$output'"; false; }
}

@test "with cc-in-kitty missing it changes nothing — a wrong id is worse than no change" {
  apply
  rm -f "$CC_KITTY_BIN_DIR/cc-in-kitty"
  block_of > "$BATS_TEST_TMPDIR/block.zsh"
  run env HOME="$HOME" KITTY_WINDOW_ID=11 ITERM_SESSION_ID="w0t15p4:REAL-ITERM-ID" \
      zsh -c "source '$BATS_TEST_TMPDIR/block.zsh'; printf '%s\n' \"\$ITERM_SESSION_ID\""
  [ "$output" = "w0t15p4:REAL-ITERM-ID" ] || { echo "got '$output'"; false; }
}

# ── reaching machines that already ran the old setup ─────────────────────────────────────────────

@test "REGRESSION ANCHOR: a STALE block is upgraded in place, not skipped" {
  # Idempotence keyed on "the marker is present" is correct until the block's CONTENT is the defect.
  # Skipping here would mean this fix reaches exactly zero of the machines that need it.
  seed_stale_block
  apply
  block_of | grep -q 'cc-in-kitty' || { echo "stale block survived --apply:"; block_of; false; }
  ! block_of | grep -q 'z "${ITERM_SESSION_ID' || { echo "stale guard survived:"; block_of; false; }
}

@test "the upgrade leaves exactly ONE block — two would both run and order would decide" {
  seed_stale_block
  apply
  N=$(grep -c ">>> $BLOCK_ID >>>" "$CC_KITTY_SHELL_RC")
  [ "$N" -eq 1 ] || { echo "block count $N"; cat "$CC_KITTY_SHELL_RC"; false; }
}

@test "the upgrade preserves unrelated rc content on both sides of the block" {
  seed_stale_block
  apply
  grep -q 'operator line above that must survive' "$CC_KITTY_SHELL_RC" || { cat "$CC_KITTY_SHELL_RC"; false; }
  grep -q 'operator line below that must survive' "$CC_KITTY_SHELL_RC" || { cat "$CC_KITTY_SHELL_RC"; false; }
}

@test "apply is idempotent — a second run neither duplicates nor re-splices" {
  apply
  local first; first="$(cat "$CC_KITTY_SHELL_RC")"
  apply
  [ "$(grep -c ">>> $BLOCK_ID >>>" "$CC_KITTY_SHELL_RC")" -eq 1 ] || { cat "$CC_KITTY_SHELL_RC"; false; }
  [ "$first" = "$(cat "$CC_KITTY_SHELL_RC")" ] || { echo "second apply mutated the rc"; false; }
}

# ── --check must call a stale block what it is ───────────────────────────────────────────────────

@test "--check reports a STALE block as missing, not as present" {
  # Reporting green on "a block exists" is the same class of error as the outage itself: a green
  # probe over a broken use path.
  seed_stale_block
  run bash "$SETUP" --check
  echo "$output" | grep -q 'STALE' || { echo "$output"; false; }
  [ "$status" -ne 0 ] || { echo "--check exited 0 with a stale block"; false; }
}

# ── step 5's verdict is THREE-valued: the absent verifier is not a terminal ──────────────────────

@test "REGRESSION ANCHOR: with cc-in-kitty NOT deployed, --check must not claim a terminal" {
  # Measured 2026-08-01 from a genuine kitty pane, before this was split out: step 5 read
  # `[ -x cc-in-kitty ] && cc-in-kitty`, so ABSENT fell into the same else-branch as a definitive
  # rc 1 and the checker printed "KITTY_* present but INHERITED — this is not a kitty pane" while
  # kitty really was the ancestor. Absent-verifier is the NORMAL state of --check before --apply, so
  # this was the first thing a new machine was told, and it was the wrong terminal.
  run env KITTY_WINDOW_ID=11 KITTY_PID=$$ bash "$SETUP" --check
  echo "$output" | grep -q 'UNVERIFIABLE' || { echo "$output"; false; }
  ! echo "$output" | grep -q 'this is not a kitty pane' || { echo "absent verifier read as a terminal:"; echo "$output"; false; }
}

@test "the unverifiable branch says the round trip did not run — silence would read as green" {
  # The spawn round-trip is the only check that exercises the USE path. Skipping it silently is how
  # a section that proved nothing gets read as a section that found nothing wrong.
  run env KITTY_WINDOW_ID=11 KITTY_PID=$$ bash "$SETUP" --check
  echo "$output" | grep -q 'round-trip did NOT run' || { echo "$output"; false; }
}

@test "positive control: a DEFINITIVE rc 1 still reports the inherited case" {
  # Without this, the anchor above would pass just as well if the INHERITED diagnosis were deleted
  # outright — and that diagnosis is the one that names the 2026-07-31 outage.
  mkdir -p "$CC_KITTY_BIN_DIR"
  { printf '#!/bin/bash\n'; printf '[ "${1:-}" = --why ] && printf "stub: vars are INHERITED\\n"\n'
    printf 'exit 1\n'; } > "$CC_KITTY_BIN_DIR/cc-in-kitty"
  chmod +x "$CC_KITTY_BIN_DIR/cc-in-kitty"
  run env KITTY_WINDOW_ID=11 KITTY_PID=$$ bash "$SETUP" --check
  echo "$output" | grep -q 'this is not a kitty pane' || { echo "$output"; false; }
  echo "$output" | grep -q 'INHERITED' || { echo "$output"; false; }
}

@test "--check exercises the USE path, not only the availability probe" {
  # `session list` returning rc 0 is precisely what stayed green through the outage, so the checker
  # has to do a real split → id → close round trip. This is a STRUCTURAL pin, deliberately: which
  # branch of step 5 runs depends on the terminal the suite happens to sit in, so asserting on
  # --check's output here would encode the machine rather than the contract (the same reasoning
  # kitty-setup-login-path.bats gives for not asserting its live 3b probe). The round trip's
  # behaviour is pinned hermetically in it2-kitty-terminal-guard.bats instead.
  grep -q 'spawn round-trip' "$SETUP" || { echo "the checker no longer exercises the use path"; false; }
  grep -q 'session split -v -s' "$SETUP" || { echo "the round trip no longer performs a real split"; false; }
}
