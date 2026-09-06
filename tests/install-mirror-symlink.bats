#!/usr/bin/env bats
# install.sh ensure_real_dir() must PRESERVE a config-dir directory symlink that already points at
# the matching ~/.claude entry, and must still REPAIR every other symlink.
#
# Pre-fix, ensure_real_dir `rm`'d every directory symlink unconditionally. That is the generator
# behind ~/.claude-next/commands sitting frozen at 2026-07-18 for seven weeks: lib/config-mirror.zsh
# creates the whole-directory mirror link, install.sh destroyed it and rebuilt per-file links, and
# because deploy-live.sh runs install.sh on every advance, install.sh always won — silently, with no
# alarm on either side. Backlog 72f21be2bb05; evidence in
# docs/research/activation-queue-audit-2026-09-04.md § "The generator".
#
# The suite is written so each case indicts ONE site:
#   1  fixture control              — the mirror link really is a symlink before install runs
#   2  mirror link SURVIVES         — RED against the pre-fix rm-everything body
#   3  fork link is REPAIRED        — RED against a predicate too broad to tell a mirror from a fork
#   4  dangling mirror-shaped link  — RED against a predicate that compares readlink TEXT
#   5  global config dir            — RED against dropping the IS_GLOBAL guard (a self-link there
#                                     is a genuine fork, not the mirror state)
#   6  per-file links still land    — the preserved link must still be a usable deposit target

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  # install.sh derives IS_GLOBAL from "$CONFIG_DIR" == "$HOME/.claude" and, on the global path,
  # links entrypoints under $HOME/bin. Fixture $HOME so no case here can reach the operator's live
  # tree — and so this suite's own notion of "the matching ~/.claude entry" is the fixture's.
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/bin" "$HOME/.claude"
  CFG="$BATS_TEST_TMPDIR/cfg"
  mkdir -p "$CFG"
  ELSEWHERE="$BATS_TEST_TMPDIR/elsewhere"
  mkdir -p "$ELSEWHERE"
}

run_install() { run bash "$REPO/install.sh" --config-dir "$CFG"; }

# Extract the predicate for the cases a full install cannot reach cheaply (a GLOBAL install would
# additionally touch $HOME/bin and LaunchAgents). Same idiom as tests/announce-before-retire.bats.
call_predicate() {  # $1=CONFIG_DIR  $2=dir-under-test  -> exit 0 iff "already correct"
  local fn; fn="$(sed -n '/^is_global_mirror_link()/,/^}/p' "$REPO/install.sh")"
  [ -n "$fn" ] || { echo "extraction found no is_global_mirror_link()"; return 2; }
  bash -c '
    set -uo pipefail
    CONFIG_DIR="$1"; shift
    IS_GLOBAL=false
    [[ "$CONFIG_DIR" == "$HOME/.claude" ]] && IS_GLOBAL=true
    '"$fn"'
    is_global_mirror_link "$1"
  ' _ "$1" "$2"
}

@test "fixture control: the mirror link is a symlink to the matching ~/.claude entry before install" {
  mkdir -p "$HOME/.claude/commands"
  ln -s "$HOME/.claude/commands" "$CFG/commands"
  [ -L "$CFG/commands" ]
  [ "$(cd -P "$CFG/commands" && pwd -P)" = "$(cd -P "$HOME/.claude/commands" && pwd -P)" ]
}

@test "a directory symlink pointing at the matching ~/.claude entry SURVIVES the install" {
  mkdir -p "$HOME/.claude/commands"
  ln -s "$HOME/.claude/commands" "$CFG/commands"

  run_install
  [ "$status" -eq 0 ]

  # The load-bearing assertion: pre-fix this is a REAL directory, because ensure_real_dir rm'd it.
  [ -L "$CFG/commands" ]
  [ "$(cd -P "$CFG/commands" && pwd -P)" = "$(cd -P "$HOME/.claude/commands" && pwd -P)" ]
  # ...and the run must not have announced a replacement for it.
  [[ "$output" != *"$CFG/commands is a directory symlink"* ]]
}

@test "a directory symlink pointing SOMEWHERE ELSE is still repaired into a real directory" {
  # The global counterpart MUST exist here. Without it the predicate short-circuits on its own
  # "no counterpart" arm and this case passes without ever reaching the path comparison — i.e. it
  # would be discharged by a sibling guard and could not tell a fork from a mirror at all.
  mkdir -p "$HOME/.claude/commands"
  ln -s "$ELSEWHERE" "$CFG/commands"
  [ -d "$HOME/.claude/commands" ]
  [ "$(cd -P "$CFG/commands" && pwd -P)" != "$(cd -P "$HOME/.claude/commands" && pwd -P)" ]

  run_install
  [ "$status" -eq 0 ]

  [ ! -L "$CFG/commands" ]
  [ -d "$CFG/commands" ]
  [[ "$output" == *"$CFG/commands is a directory symlink"* ]]
}

@test "a symlink whose target has been REMOVED is still repaired" {
  # Isolates the "resolves to nothing" arm: the counterpart exists, so only the dangling link
  # itself can be the reason to repair.
  mkdir -p "$HOME/.claude/commands"
  ln -s "$BATS_TEST_TMPDIR/gone" "$CFG/commands"
  [ ! -d "$CFG/commands" ]

  run_install
  [ "$status" -eq 0 ]

  [ ! -L "$CFG/commands" ]
  [ -d "$CFG/commands" ]
}

@test "a mirror-shaped symlink with NO global counterpart is still repaired" {
  # Correct readlink text, nothing behind it — there is no shared surface to join.
  ln -s "$HOME/.claude/commands" "$CFG/commands"
  [ ! -d "$HOME/.claude/commands" ]

  run_install
  [ "$status" -eq 0 ]

  [ ! -L "$CFG/commands" ]
  [ -d "$CFG/commands" ]
}

@test "on the GLOBAL config dir a directory symlink is never 'already correct'" {
  # A real directory symlink living UNDER ~/.claude. Its own matching entry is itself, so a
  # resolve-and-compare with no IS_GLOBAL guard reports "already correct" and ensure_real_dir
  # would stop repairing genuine forks in the global tree.
  mkdir -p "$HOME/.claude/commands-real"
  ln -s "$HOME/.claude/commands-real" "$HOME/.claude/commands"
  run call_predicate "$HOME/.claude" "$HOME/.claude/commands"
  [ "$status" -ne 0 ]

  # Control: the SAME shape under a non-global config dir IS already correct, so the case above
  # is pinning the IS_GLOBAL guard rather than passing for some unrelated reason.
  mkdir -p "$HOME/.claude/agents"
  ln -s "$HOME/.claude/agents" "$CFG/agents"
  run call_predicate "$CFG" "$CFG/agents"
  [ "$status" -eq 0 ]
}

@test "per-file links still land through a preserved mirror link" {
  mkdir -p "$HOME/.claude/commands"
  ln -s "$HOME/.claude/commands" "$CFG/commands"

  run_install
  [ "$status" -eq 0 ]

  # Preserving the directory must not cost the deposit: a tracked command has to be reachable
  # through the link, and to be a symlink back to the repo.
  src="$REPO/commands/ship.md"
  [ -f "$src" ]
  [ -L "$CFG/commands/ship.md" ]
  [ "$(readlink "$CFG/commands/ship.md")" = "$src" ]
  # It landed in the SHARED directory, which is the whole point of the mirror.
  [ -L "$HOME/.claude/commands/ship.md" ]
}
