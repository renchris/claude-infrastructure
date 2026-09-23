#!/usr/bin/env bats
# config-mirror-instructions-variant — a per-account instructions A/B arm survives the mirror.
#
# The mirror re-points every shared entry of an account dir at ~/.claude at each session start, so
# an account whose CLAUDE.md was hand-pointed at a variant would silently revert to the shared file.
# A line "<account-dir-basename> <variant>" in ~/.claude/instruction-variants makes the mirror itself
# point that account's CLAUDE.md at ~/.claude/CLAUDE.<variant>.md. A malformed line or a missing
# variant file falls back to the shared CLAUDE.md: an account must never end up with no rules.
# (docs/research/token-efficiency-2026-09-23/ — the slim-instructions A/B.)

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude" "$HOME/.claude-tertiary" "$HOME/.claude-quaternary"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  MIRROR="$REPO/lib/config-mirror.zsh"
  printf 'full rules\n' > "$HOME/.claude/CLAUDE.md"
  printf 'slim rules\n' > "$HOME/.claude/CLAUDE.slim.md"
  REG="$HOME/.claude/instruction-variants"
}

sync_acct() { zsh -fc "source '$MIRROR'; _cc_sync_config_mirror '$HOME/$1'" 2>/dev/null; }
target_of() { readlink "$HOME/$1/CLAUDE.md"; }

@test "an unlisted account's CLAUDE.md points at the shared file" {
  sync_acct .claude-tertiary
  [ "$(target_of .claude-tertiary)" = "$HOME/.claude/CLAUDE.md" ]
}

@test "a listed account points at its variant; an unlisted one is untouched" {
  printf '.claude-tertiary slim\n' > "$REG"
  sync_acct .claude-tertiary
  sync_acct .claude-quaternary
  [ "$(target_of .claude-tertiary)" = "$HOME/.claude/CLAUDE.slim.md" ]
  [ "$(target_of .claude-quaternary)" = "$HOME/.claude/CLAUDE.md" ]
  [ "$(cat "$HOME/.claude-tertiary/CLAUDE.md")" = "slim rules" ]
}

@test "the variant survives a re-sync — the mirror no longer reverts it" {
  printf '.claude-tertiary slim\n' > "$REG"
  sync_acct .claude-tertiary
  sync_acct .claude-tertiary
  [ "$(target_of .claude-tertiary)" = "$HOME/.claude/CLAUDE.slim.md" ]
}

@test "removing the registry line re-points the account at the shared file" {
  printf '.claude-tertiary slim\n' > "$REG"
  sync_acct .claude-tertiary
  [ "$(target_of .claude-tertiary)" = "$HOME/.claude/CLAUDE.slim.md" ]
  : > "$REG"
  sync_acct .claude-tertiary
  [ "$(target_of .claude-tertiary)" = "$HOME/.claude/CLAUDE.md" ]
}

@test "a variant whose file is missing falls back to the shared CLAUDE.md" {
  printf '.claude-tertiary nosuch\n' > "$REG"
  sync_acct .claude-tertiary
  [ "$(target_of .claude-tertiary)" = "$HOME/.claude/CLAUDE.md" ]
}

@test "a malformed variant name falls back to the shared CLAUDE.md" {
  printf '.claude-tertiary ../../etc/passwd\n' > "$REG"
  sync_acct .claude-tertiary
  [ "$(target_of .claude-tertiary)" = "$HOME/.claude/CLAUDE.md" ]
}

@test "control: without the variant hook the mirror reverts a hand-pointed CLAUDE.md" {
  # Proves the second test has power: the unmodified loop re-points the link at the shared file.
  local mut="$BATS_TEST_TMPDIR/config-mirror-mutant.zsh"
  python3 - "$MIRROR" "$mut" <<'EOF'
import sys
src = open(sys.argv[1]).read()
anchor = '[[ "$name" == CLAUDE.md ]] && _cc_instructions_variant_target'
assert anchor in src, "anchor moved: re-anchor this control on the variant hook"
open(sys.argv[2], "w").write(src.replace(anchor, '[[ "$name" == NEVER ]] && _cc_instructions_variant_target'))
EOF
  printf '.claude-tertiary slim\n' > "$REG"
  ln -sfn "$HOME/.claude/CLAUDE.slim.md" "$HOME/.claude-tertiary/CLAUDE.md"
  zsh -fc "source '$mut'; _cc_sync_config_mirror '$HOME/.claude-tertiary'" 2>/dev/null
  [ "$(target_of .claude-tertiary)" = "$HOME/.claude/CLAUDE.md" ]
}
