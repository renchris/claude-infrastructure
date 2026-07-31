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
  # Kill the liveness probe FIRST. A backgrounded grandchild that outlives the test holds bats' TAP
  # fd open and wedges the whole run (memory: fixture-lifetime-is-an-orphan-leak-bound) — which is
  # why the probe below is spawned with all three fds detached and is killed unconditionally here.
  [ -n "${PROBE_PID:-}" ] && kill "$PROBE_PID" 2>/dev/null && wait "$PROBE_PID" 2>/dev/null
  git -C "$REPO" worktree remove --force "$TDIR/wt-held" 2>/dev/null || true
  rm -rf "$TDIR"
}

# Spawn a process that (a) matches `pgrep -f claude` and (b) is cwd'd in $1 — i.e. exactly what the
# liveness leg exists to find. `exec -a` sets argv[0], which is what pgrep -f reads.
spawn_live_probe() {
  ( cd "$1" && exec -a "claude-guard-liveprobe" sleep 120 ) >/dev/null 2>&1 </dev/null &
  PROBE_PID=$!
  sleep 0.4   # let the exec land so lsof can see the cwd
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

# ── the liveness leg's own verdict — the guard's WHOLE PURPOSE, previously untested ──────────────
# Tests 3/4 only assert the remove leg PASSES on idle, so the suite went green whether the guard
# blocked a live worktree or fell wide open (this file's own header: test 4 "discriminates nothing").
# That is the fail-open-pinned-by-its-own-suite shape (memory: present-but-inverted-guard). These two
# pin both directions, and together they discriminate the batched lsof: a batch that lost the exact
# cwd match would block test B, and one that lost the population would miss test A.
@test "A: worktree remove of a LIVE worktree (process cwd'd in it) is BLOCKED" {
  cd "$REPO"
  spawn_live_probe "$TDIR/wt-held"
  run run_guard "git worktree remove $TDIR/wt-held"
  [ "$status" -eq 2 ]
}

@test "B: worktree remove of a real IDLE worktree passes despite claude processes elsewhere" {
  cd "$REPO"
  git -C "$REPO" worktree add -q "$TDIR/wt-idle" -b idle-branch
  spawn_live_probe "$TDIR"           # live, matches pgrep — but cwd'd OUTSIDE the target worktree
  run run_guard "git worktree remove $TDIR/wt-idle"
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
