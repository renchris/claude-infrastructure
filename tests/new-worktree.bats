#!/usr/bin/env bats
# new-worktree.bats — the launcher contract for scripts/new-worktree.sh.
#
# HERMETIC BY CONSTRUCTION: $HOME is fixtured to a temp dir, which is what redirects the
# script's own `$HOME/Development/.worktrees` target. A suite that skipped this would create
# worktrees in the operator's REAL tree on every run — and, per the repo's hermeticity ratchet,
# would red the land gate for every other lander too.
#
# The three assertions that matter are the ones ~/.zshrc:_cc_route_check() actually depends on:
# the DERIVED path, the STDERR-only stream discipline, and the NON-ZERO exit on failure. If any
# of those drift, the launcher silently either loses the worktree or launches un-isolated.

setup() {
  SCRIPT="$BATS_TEST_DIRNAME/../scripts/new-worktree.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  # An origin the script can fetch from, so the origin/main path is the one under test.
  ORIGIN="$BATS_TEST_TMPDIR/origin.git"
  git init --quiet --bare -b main "$ORIGIN"
  REPO="$BATS_TEST_TMPDIR/repo"
  git init --quiet -b main "$REPO"
  git -C "$REPO" config user.email t@t.t
  git -C "$REPO" config user.name t
  echo seed > "$REPO/seed.txt"
  git -C "$REPO" add seed.txt
  git -C "$REPO" commit --quiet -m seed
  git -C "$REPO" remote add origin "$ORIGIN"
  git -C "$REPO" push --quiet -u origin main 2>/dev/null
  cp "$SCRIPT" "$REPO/new-worktree.sh"
  chmod +x "$REPO/new-worktree.sh"
}

@test "missing name exits 2" {
  run bash -c "cd '$REPO' && ./new-worktree.sh"
  [ "$status" -eq 2 ]
}

@test "path-like name is rejected, not silently mkdir -p'd" {
  run bash -c "cd '$REPO' && ./new-worktree.sh ../escape"
  [ "$status" -eq 2 ]
}

@test "creates the worktree at the path the launcher DERIVES" {
  run bash -c "cd '$REPO' && ./new-worktree.sh mysession"
  [ "$status" -eq 0 ]
  # ~/.zshrc derives exactly this; it never reads our stdout.
  [ -d "$HOME/Development/.worktrees/wt-mysession" ]
  [ -f "$HOME/Development/.worktrees/wt-mysession/seed.txt" ]
}

@test "stdout is EMPTY — every human-facing byte goes to stderr" {
  out="$(cd "$REPO" && ./new-worktree.sh quiet1 2>/dev/null)"
  [ -z "$out" ]
}

@test "an existing destination is refused, never clobbered" {
  run bash -c "cd '$REPO' && ./new-worktree.sh dup"
  [ "$status" -eq 0 ]
  run bash -c "cd '$REPO' && ./new-worktree.sh dup"
  [ "$status" -eq 3 ]
}

@test "gitignored runtime files are COPIED, not symlinked" {
  mkdir -p "$REPO/.claude"
  echo '{"x":1}' > "$REPO/.claude/settings.local.json"
  run bash -c "cd '$REPO' && ./new-worktree.sh withcfg"
  [ "$status" -eq 0 ]
  dst="$HOME/Development/.worktrees/wt-withcfg/.claude/settings.local.json"
  [ -f "$dst" ]
  [ ! -L "$dst" ]   # a symlink would make every worktree mutate the shared file
}

@test "branches off origin/main, not a stale local main" {
  # Advance origin BEHIND the local ref's back, then assert the new worktree has the origin commit.
  clone="$BATS_TEST_TMPDIR/clone"
  git clone --quiet "$ORIGIN" "$clone"
  git -C "$clone" config user.email t@t.t
  git -C "$clone" config user.name t
  echo newer > "$clone/newer.txt"
  git -C "$clone" add newer.txt
  git -C "$clone" commit --quiet -m newer
  git -C "$clone" push --quiet origin main
  run bash -c "cd '$REPO' && ./new-worktree.sh fresh"
  [ "$status" -eq 0 ]
  [ -f "$HOME/Development/.worktrees/wt-fresh/newer.txt" ]
}
