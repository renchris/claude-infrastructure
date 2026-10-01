#!/usr/bin/env bats
# lib/claude-launcher.zsh _cc_route_check — the always-isolate gate reads the .worktree-isolate
# marker (worktree-isolation rollout step 4, backlog 3c51c384f885), reso keeps its basename test,
# and the installed ~/.reso pool rung is consulted for reso only.
#
# HERMETIC: $HOME is fixtured, the function is extracted from the lib and sourced alone under
# `zsh -f` (no rc, no router install), and every rung it can reach is a stub that records its call.
# CLAUDE_ISOLATION_SKIP is unset so the skip branch cannot pass every case vacuously.

setup() {
  command -v zsh >/dev/null || skip "zsh not installed"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/Development/.worktrees" "$HOME/.reso/bin"
  unset CLAUDE_ISOLATION_SKIP
  CALLS="$BATS_TEST_TMPDIR/calls"; : >"$CALLS"; export CALLS
  FN="$BATS_TEST_TMPDIR/route-check.zsh"
  awk '/^_cc_route_check\(\) \{/,/^\}/' "$BATS_TEST_DIRNAME/../lib/claude-launcher.zsh" >"$FN"
  grep -q '^_cc_route_check() {' "$FN"
}

# make_repo <name> → a primary checkout (.git is a DIR) with a cold new-worktree.sh stub
make_repo() {
  local r="$BATS_TEST_TMPDIR/$1"
  mkdir -p "$r/scripts"
  git -C "$r" init -q
  printf '#!/bin/bash\necho "new-worktree $1" >>"$CALLS"\nmkdir -p "$HOME/Development/.worktrees/wt-$1"\n' \
    >"$r/scripts/new-worktree.sh"
  chmod +x "$r/scripts/new-worktree.sh"
  printf '%s\n' "$r"
}

reso_pool_stub() {
  printf '#!/bin/bash\necho "reso-pool $2" >>"$CALLS"\nd="$HOME/Development/.worktrees/pool-$2"\nmkdir -p "$d"\necho "$d"\n' \
    >"$HOME/.reso/bin/worktree-pool.sh"
}

route() { # route <dir> → runs the gate there
  run zsh -f -c "source '$FN'; cd '$1' && _cc_route_check"
}

@test "a repo carrying .worktree-isolate is isolated through its own new-worktree.sh" {
  r="$(make_repo claude-infrastructure)"
  : >"$r/.worktree-isolate"
  route "$r"
  [ "$status" -eq 0 ]
  [[ "$output" == "$HOME/Development/.worktrees/wt-cc-"* ]] || false
  [ -d "$output" ]
  grep -q '^new-worktree cc-' "$CALLS"
}

@test "a repo without the marker launches in place and builds nothing" {
  r="$(make_repo some-other-repo)"
  route "$r"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -s "$CALLS" ]
}

@test "the installed reso pool is NOT consulted for a non-reso marker repo" {
  reso_pool_stub
  r="$(make_repo claude-infrastructure)"
  : >"$r/.worktree-isolate"
  route "$r"
  [ "$status" -eq 0 ]
  ! grep -q '^reso-pool' "$CALLS" || false
  grep -q '^new-worktree cc-' "$CALLS"
}

@test "reso keeps its basename gate and claims from the installed pool, with no marker file" {
  reso_pool_stub
  r="$(make_repo reso-management-app)"
  route "$r"
  [ "$status" -eq 0 ]
  [[ "$output" == "$HOME/Development/.worktrees/pool-cc-"* ]] || false
  grep -q '^reso-pool cc-' "$CALLS"
  ! grep -q '^new-worktree' "$CALLS"
}

@test "a linked worktree (.git is a FILE) is already isolated and builds nothing" {
  r="$(make_repo claude-infrastructure)"
  : >"$r/.worktree-isolate"
  wt="$BATS_TEST_TMPDIR/linked"
  git -C "$r" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  git -C "$r" worktree add -q "$wt" 2>/dev/null
  [ -f "$wt/.git" ]
  : >"$CALLS"
  route "$wt"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -s "$CALLS" ]
}

@test "CLAUDE_ISOLATION_SKIP=1 opts one launch out, marker or not" {
  r="$(make_repo claude-infrastructure)"
  : >"$r/.worktree-isolate"
  run env CLAUDE_ISOLATION_SKIP=1 zsh -f -c "source '$FN'; cd '$r' && _cc_route_check"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -s "$CALLS" ]
}

@test "a failed cold build refuses the launch (non-zero), never a silent fallback to root" {
  r="$(make_repo claude-infrastructure)"
  : >"$r/.worktree-isolate"
  printf '#!/bin/bash\nexit 3\n' >"$r/scripts/new-worktree.sh"
  route "$r"
  [ "$status" -ne 0 ]
}
