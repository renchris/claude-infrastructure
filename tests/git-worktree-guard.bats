#!/usr/bin/env bats
# git-worktree-guard.bats — the -C blindness fix (2026-07-25): the guard's literal matches never
# saw `git -C <repo> worktree remove` / `git -C <repo> branch -d`, so the audit-§7 cleanup form
# ran entirely unguarded; and the worktree-list check ran in the hook's cwd, not the -C target.
# Red-proof: test 2 FAILS against the pre-fix guard (verified by stash-revert during authoring:
# `git -C … branch -d <held>` exited 0 instead of 2). Test 4 is a reaches-the-leg smoke only —
# its idle path exits 0 pre- and post-fix, so it discriminates nothing on its own.

setup() {
  # HERMETICITY (run_gate's blocking test-hermeticity ratchet): fixture $HOME FIRST so every test
  # inherits it. The git commands below already pass -c user.email/-c user.name explicitly, so they
  # do not depend on the real ~/.gitconfig this hides.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export TDIR="$(mktemp -d)"
  export REPO="$TDIR/repo"
  git init -q "$REPO"
  git -C "$REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
  git -C "$REPO" worktree add -q "$TDIR/wt-held" -b held-branch
  GUARD="$BATS_TEST_DIRNAME/../hooks/git-worktree-guard.sh"
}

teardown() {
  git -C "$REPO" worktree remove --force "$TDIR/wt-held" 2>/dev/null || true
  rm -rf "$TDIR"
}

run_guard() {  # $1 = the bash command string
  printf '{"tool_input":{"command":%s}}' "$(printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')" | bash "$GUARD"
}

@test "plain branch -d of a worktree-held branch is BLOCKED" {
  cd "$REPO"
  run run_guard "git branch -d held-branch"
  [ "$status" -eq 2 ]
}

@test "-C form: branch -d of a worktree-held branch is BLOCKED from any cwd" {
  cd "$TDIR"   # NOT the repo — the -C target must be interrogated, not the cwd
  run run_guard "git -C $REPO branch -d held-branch"
  [ "$status" -eq 2 ]
}

@test "plain worktree remove of a non-live path passes (fail-open on idle)" {
  cd "$REPO"
  run run_guard "git worktree remove $TDIR/nonexistent-wt"
  [ "$status" -eq 0 ]
}

@test "-C form reaches the worktree-remove leg (idle path still passes)" {
  cd "$TDIR"
  run run_guard "git -C $REPO worktree remove $TDIR/nonexistent-wt"
  [ "$status" -eq 0 ]
}

@test "unrelated git commands pass through untouched" {
  cd "$REPO"
  run run_guard "git -C $REPO log --oneline -1"
  [ "$status" -eq 0 ]
}

@test "branch delete of a NON-held branch passes" {
  cd "$REPO"
  git -C "$REPO" branch free-branch
  run run_guard "git branch -d free-branch"
  [ "$status" -eq 0 ]
}
