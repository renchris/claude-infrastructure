#!/usr/bin/env bats
# install-instructions-variant.bats — install.sh deploys ONE canonical global instructions file.
#
# THE DEFECT (docs/plans/INSTRUCTION_BUDGET.md D1, measured 2026-10-03). Claude Code's ancestor walk
# loads ~/.claude/CLAUDE.md and ~/.claude/rules/*.md for every cwd under $HOME, and dedupes them
# against an account's own CLAUDE.md/rules only by realpath. install.sh copied the FULL text to
# ~/.claude/CLAUDE.md while migration 0042 pointed every account at CLAUDE.slim.md, so every session
# loaded slim + full (~181k chars). The fix (D2/D3): ~/.claude/CLAUDE.md holds the SELECTED variant
# (registry line `global <v>`, default slim) as a regular file, the full text deploys to
# CLAUDE.full.md, and rules/ holds only the mission board.
#
# RED-proof: against the pre-fix install.sh (git show e4ade9394:install.sh) tests 1, 3, 4 and 5 fail —
# CLAUDE.md is the full text, CLAUDE.full.md is never written, and the stray rule stays loaded.
# Test 2 (the registry selects full) is green pre-fix by construction; it pins the opposite polarity.
#
# Hermeticity: fixture $HOME and fixture repo; every install runs --config-dir into a throwaway dir,
# which also keeps install.sh's global legs (bin/, LaunchAgents) off.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export GIT_CONFIG_GLOBAL="$BATS_TEST_TMPDIR/probe-gitconfig"
  FIX="$BATS_TEST_TMPDIR/repo"; CFG="$BATS_TEST_TMPDIR/cfg"
  mkdir -p "$FIX/agents" "$FIX/scripts/lib" "$CFG"
  cp "$REPO/install.sh" "$FIX/install.sh"
  cp "$REPO/scripts/lib/real-home.sh" "$FIX/scripts/lib/real-home.sh"
  printf '# fixture FULL global instructions\n' > "$FIX/CLAUDE.global.md"
  printf '# fixture SLIM global instructions\n' > "$FIX/CLAUDE.global.slim.md"
  printf '#!/bin/bash\necho fixture-statusline\n' > "$FIX/statusline.sh"
  printf 'fixture agent\n' > "$FIX/agents/fixture-agent.md"
  STUB="$BATS_TEST_TMPDIR/stub"; mkdir -p "$STUB"
  printf '#!/bin/sh\nexit 0\n' > "$STUB/launchctl"
  printf '#!/bin/sh\nexit 0\n' > "$STUB/defaults"
  chmod +x "$STUB/launchctl" "$STUB/defaults"
  export PATH="$STUB:$PATH"
}

install_fixture() { run bash "$FIX/install.sh" --config-dir "$CFG"; }

@test "no registry line: CLAUDE.md is the slim variant as a regular file, the full text is CLAUDE.full.md" {
  install_fixture
  [ "$status" -eq 0 ]
  [ ! -L "$CFG/CLAUDE.md" ]
  cmp "$CFG/CLAUDE.md" "$FIX/CLAUDE.global.slim.md"
  cmp "$CFG/CLAUDE.full.md" "$FIX/CLAUDE.global.md"
  cmp "$CFG/CLAUDE.slim.md" "$FIX/CLAUDE.global.slim.md"
}

@test "registry 'global full': CLAUDE.md is the full text" {
  printf 'global full\n.claude-next slim\n' > "$CFG/instruction-variants"
  install_fixture
  [ "$status" -eq 0 ]
  cmp "$CFG/CLAUDE.md" "$FIX/CLAUDE.global.md"
}

@test "a symlinked CLAUDE.md is replaced by a regular file, and its old target is left alone" {
  printf 'operator scratch\n' > "$CFG/elsewhere.md"
  ln -s "$CFG/elsewhere.md" "$CFG/CLAUDE.md"
  install_fixture
  [ "$status" -eq 0 ]
  [ ! -L "$CFG/CLAUDE.md" ]
  cmp "$CFG/CLAUDE.md" "$FIX/CLAUDE.global.slim.md"
  [ "$(cat "$CFG/elsewhere.md")" = "operator scratch" ]
}

@test "slim rule set: CLAUDE.rules.slim.<name>.md deploys to rules/<name>.md as a copy and survives the stray sweep" {
  printf 'close rules\n' > "$FIX/CLAUDE.rules.slim.10-session-close.md"
  mkdir -p "$CFG/rules"; printf 'board\n' > "$CFG/rules/00-mission-board.md"
  install_fixture
  [ "$status" -eq 0 ]
  [ ! -L "$CFG/rules/10-session-close.md" ]
  cmp "$CFG/rules/10-session-close.md" "$FIX/CLAUDE.rules.slim.10-session-close.md"
  install_fixture
  [ -f "$CFG/rules/00-mission-board.md" ]
  [ -f "$CFG/rules/10-session-close.md" ]
  [ "$(find "$CFG/rules" -type f | wc -l | tr -d ' ')" -eq 2 ]
  [[ "$output" != *"retired rules/"* ]] || false
}

@test "registry 'global full': the slim rule set is not deployed, and a deployed one is retired (full already holds it)" {
  printf 'close rules\n' > "$FIX/CLAUDE.rules.slim.10-session-close.md"
  install_fixture
  [ -f "$CFG/rules/10-session-close.md" ]
  printf 'global full\n' > "$CFG/instruction-variants"
  install_fixture
  [ "$status" -eq 0 ]
  cmp "$CFG/CLAUDE.md" "$FIX/CLAUDE.global.md"
  [ ! -e "$CFG/rules/10-session-close.md" ]
}

@test "a registry variant this checkout lacks falls back to the full text, and says so" {
  printf 'global nosuch\n' > "$CFG/instruction-variants"
  install_fixture
  [ "$status" -eq 0 ]
  cmp "$CFG/CLAUDE.md" "$FIX/CLAUDE.global.md"
  [[ "$output" == *"variant 'nosuch' is not in this checkout"* ]] || false
}

@test "rules/: a stray rule is moved to backups/rules-retired/, the mission board stays, a re-run is quiet" {
  mkdir -p "$CFG/rules"
  printf 'board\n' > "$CFG/rules/00-mission-board.md"
  printf 'stale essay\n' > "$CFG/rules/agent-operating-lessons.md"
  install_fixture
  [ "$status" -eq 0 ]
  [ "$(ls "$CFG/rules")" = "00-mission-board.md" ]
  [ "$(cat "$CFG/rules/00-mission-board.md")" = "board" ]
  [ "$(cat "$CFG"/backups/rules-retired/agent-operating-lessons.md.*)" = "stale essay" ]
  install_fixture
  [ "$status" -eq 0 ]
  [[ "$output" != *"retired rules/"* ]] || false
  [ "$(find "$CFG/backups/rules-retired" -type f | wc -l | tr -d ' ')" -eq 1 ]
}
