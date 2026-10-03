#!/usr/bin/env bats
# migration 0053 — every account back on the ONE canonical instructions file (INSTRUCTION_BUDGET D3).
#
# Pins: it refuses until install.sh's step 1 has converged (else accounts would move onto the full
# text); --dry-run writes nothing; --confirm re-points every account so CLAUDE.md and rules resolve to
# ~/.claude/CLAUDE.md and ~/.claude/rules, drops the 0042 registry lines and retires rules.slim; its own
# header `migration-verify` line goes 1 -> 0 across the apply; a re-run is a no-op; and a failed reset
# restores every account to its 0042 arm (all or none).
# Hermetic: scratch HOME with its own accounts.json, the repo's mirror lib and CLI linked in.
# RED-proof: new file; against a migration body that skips the reset loop, test 4 fails on the
# resolved links and on the verify line.

setup() {
  unset CC_BATS_ACTIVE CC_MIGRATION_STATE
  export HOME="$BATS_TEST_TMPDIR/home"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  MIG="$REPO/migrations/0053-instructions-canonical-file-all-accounts.sh"
  mkdir -p "$HOME/.claude/lib" "$HOME/.claude/bin" "$HOME/.claude/rules" "$HOME/.claude/rules.slim" \
    "$HOME/.claude-tertiary" "$HOME/.claude-quaternary"
  ln -s "$REPO/lib/config-mirror.zsh" "$HOME/.claude/lib/config-mirror.zsh"
  ln -s "$REPO/bin/cc-instructions-variant" "$HOME/.claude/bin/cc-instructions-variant"
  printf 'full rules\n' > "$HOME/.claude/CLAUDE.full.md"
  printf 'slim rules\n' > "$HOME/.claude/CLAUDE.slim.md"
  cp "$HOME/.claude/CLAUDE.slim.md" "$HOME/.claude/CLAUDE.md"            # step 1 converged
  printf 'board\n' | tee "$HOME/.claude/rules/00-mission-board.md" > "$HOME/.claude/rules.slim/00-mission-board.md"
  printf '{"accounts":[{"name":"next3","config_dir":"~/.claude-tertiary"},{"name":"next4","config_dir":"~/.claude-quaternary"}]}\n' \
    > "$HOME/.claude/accounts.json"
  printf '.claude-tertiary slim\n.claude-quaternary slim\n' > "$HOME/.claude/instruction-variants"
  for d in .claude-tertiary .claude-quaternary; do                       # the 0042 shape
    ln -s "$HOME/.claude/CLAUDE.slim.md" "$HOME/$d/CLAUDE.md"
    ln -s "$HOME/.claude/rules.slim" "$HOME/$d/rules"
  done
  VERIFY="$(sed -n 's/^# migration-verify: //p' "$MIG")"
}

on_slim() { [ "$(readlink "$HOME/$1/CLAUDE.md")" = "$HOME/.claude/CLAUDE.slim.md" ] && [ "$(readlink "$HOME/$1/rules")" = "$HOME/.claude/rules.slim" ]; }
on_canon() { [ "$(readlink "$HOME/$1/CLAUDE.md")" = "$HOME/.claude/CLAUDE.md" ] && [ "$(readlink "$HOME/$1/rules")" = "$HOME/.claude/rules" ]; }

@test "refuses while ~/.claude/CLAUDE.md still holds the full text, and writes nothing" {
  cp "$HOME/.claude/CLAUDE.full.md" "$HOME/.claude/CLAUDE.md"
  run bash "$MIG" --confirm all-accounts
  [ "$status" -eq 1 ]
  [[ "$output" == *"REFUSED"*"converge first"* ]] || false
  on_slim .claude-tertiary
  on_slim .claude-quaternary
  [ ! -d "$HOME/.claude/backups" ]
}

@test "refuses while ~/.claude/rules holds more than the mission board" {
  printf 'essay\n' > "$HOME/.claude/rules/agent-operating-lessons.md"
  run bash "$MIG" --confirm all-accounts
  [ "$status" -eq 1 ]
  [[ "$output" == *"agent-operating-lessons.md"* ]] || false
  on_slim .claude-tertiary
}

@test "--dry-run names both accounts and writes nothing; a bare run is a usage error" {
  run bash "$MIG" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"will re-point: next3 next4"* ]] || false
  on_slim .claude-tertiary
  [ -d "$HOME/.claude/rules.slim" ]
  run bash "$MIG"
  [ "$status" -eq 2 ]
}

@test "--confirm: every account resolves to the canonical file, registry lines gone, rules.slim retired, verify 1 -> 0" {
  run bash -c "$VERIFY"
  [ "$status" -eq 1 ]
  run bash "$MIG" --confirm all-accounts
  [ "$status" -eq 0 ]
  on_canon .claude-tertiary
  on_canon .claude-quaternary
  run grep -c 'claude-' "$HOME/.claude/instruction-variants"
  [ "$output" = 0 ]
  [ ! -e "$HOME/.claude/rules.slim" ]
  [ -n "$(find "$HOME/.claude/backups" -path '*/instructions-canonical-0053-*/rules.slim/00-mission-board.md')" ]
  run bash -c "$VERIFY"
  [ "$status" -eq 0 ]
  run bash "$MIG" --confirm all-accounts
  [ "$status" -eq 0 ]
  [[ "$output" == *"already applied"* ]] || false
}

@test "all or none: a failed reset puts every account back on its 0042 arm" {
  local stub="$BATS_TEST_TMPDIR/civ"
  # Fails only next4's reset; everything else is the real CLI, so the rollback under test is 0053's.
  # shellcheck disable=SC2016  # the stub's own $1/$2/$@, expanded when it runs
  printf '#!/bin/bash\n[ "$1 $2" = "reset next4" ] && exit 1\nexec %q "$@"\n' "$REPO/bin/cc-instructions-variant" > "$stub"
  chmod +x "$stub"
  run env CC_INSTRUCTIONS_VARIANT_BIN="$stub" bash "$MIG" --confirm all-accounts
  [ "$status" -eq 1 ]
  [[ "$output" == *"reset FAILED on next4"* ]] || false
  on_slim .claude-tertiary
  on_slim .claude-quaternary
  grep -qx '.claude-tertiary slim' "$HOME/.claude/instruction-variants"
}
