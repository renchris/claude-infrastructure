#!/usr/bin/env bats
# worktree-setup.bats — the WorktreeCreate provisioner's allocator ladder and stdout contract.
#
# THE DEFECT UNDER TEST (measured 2026-08-05, hooks/worktree-setup.sh:93+96 before the fix):
# the pool rung fell back to the machine-GLOBAL $HOME/.reso/bin/worktree-pool.sh whenever $REPO
# shipped no allocator of its own, with no repo test on that path. reso's pool slots live at a
# SHARED worktree root under generic wt-pool-N names, so `claim` switched one of RESO's slots to
# the caller's branch and printed it back — this hook took wt-pool-9 and handed a
# claude-infrastructure session a checkout of the wrong repo. reso closed it at the allocator
# chokepoint (99753cf31: foreign caller refused, exit 3), which converted a silent wrong-repo
# success into a hard `claude -w` failure, because rung 2 treated a failed claim as fatal.
#
# TWO-SIDED BY CONSTRUCTION. Test 1's foreign allocator SUCCEEDS and prints a real directory —
# deliberately, and it is the whole discriminating power of this suite. A stub that exited 3 would
# pass post-fix for the WRONG reason (claim fails, hook falls through) and could not tell "the
# fallback is gone" from "the fall-through works". With a SUCCEEDING stub the pre-fix hook prints
# the foreign path and exits 0, so test 1 goes red on the real prior artifact. Verified against it
# via `git show <pre-fix>:hooks/worktree-setup.sh` — 1 and 2 red before, all green after.
#
# HERMETIC: fixture $HOME (test-hermeticity-lint rule 1) — the subject writes
# $HOME/.claude/logs/worktree-lifecycle.log and derives every worktree path from $HOME, and
# link_memory reaches the real worktree-memory-link.sh, so CC_WML_CONFIG_DIRS is pinned into
# $BATS_TEST_TMPDIR as well. Nothing here can touch the operator's ~/.claude or ~/.reso.
#
# CC_WTS_HOOK overrides the subject under test (default: this checkout's copy) — that is the seam
# the pre-fix replay uses, so the mutant check runs the REAL prior file, never a re-typed one.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_WML_CONFIG_DIRS="$BATS_TEST_TMPDIR/cfg"; mkdir -p "$CC_WML_CONFIG_DIRS"
  export CC_WML_QUIET=1

  HOOK="${CC_WTS_HOOK:-$BATS_TEST_DIRNAME/../hooks/worktree-setup.sh}"
  export HOOK
  LOG="$HOME/.claude/logs/worktree-lifecycle.log"
  export LOG

  REPO="$BATS_TEST_TMPDIR/repo"
  git init -q "$REPO"
  git -C "$REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
  mkdir -p "$REPO/scripts"
  export REPO

  # Where a cold build lands. The hook derives this itself; the stub below honours it so the two
  # can be asserted equal rather than assumed so.
  COLD="$HOME/Development/.worktrees/wt-demo"
  export COLD
}

# A cold-build stub matching the hook's call shape (`new-worktree.sh <branch> <path>`), leaving a
# sentinel so "the cold rung ran" is EVIDENCE and not an inference from the printed path.
install_cold() {
  cat > "$REPO/scripts/new-worktree.sh" <<'EOS'
#!/bin/bash
mkdir -p "$2" && touch "$HOME/.cold-ran"
echo "cold-built $1 -> $2" >&2
exit 0
EOS
  chmod +x "$REPO/scripts/new-worktree.sh"
}

# The reso allocator as INSTALLED on this box: present, and refusing a foreign caller (99753cf31).
install_foreign_refusing() {
  mkdir -p "$HOME/.reso/bin"
  cat > "$HOME/.reso/bin/worktree-pool.sh" <<'EOS'
#!/bin/bash
touch "$HOME/.foreign-ran"
echo "✗ worktree-pool: refusing to claim — this pool belongs to another repo." >&2
exit 3
EOS
  chmod +x "$HOME/.reso/bin/worktree-pool.sh"
}

# The same allocator BEFORE that gate existed: it succeeds, and hands back a slot of the WRONG
# repo. This is the state the fallback was written against and the one that made it dangerous.
install_foreign_succeeding() {
  mkdir -p "$HOME/.reso/bin" "$HOME/Development/.worktrees/wt-pool-9"
  cat > "$HOME/.reso/bin/worktree-pool.sh" <<'EOS'
#!/bin/bash
touch "$HOME/.foreign-ran"
printf '%s\n' "$HOME/Development/.worktrees/wt-pool-9"
exit 0
EOS
  chmod +x "$HOME/.reso/bin/worktree-pool.sh"
}

# $REPO's OWN allocator, refusing (empty pool / its own ownership gate / any allocator bug).
install_own_pool_failing() {
  cat > "$REPO/scripts/worktree-pool.sh" <<'EOS'
#!/bin/bash
touch "$HOME/.own-pool-ran"
echo "✗ worktree-pool: refusing to claim" >&2
exit 3
EOS
  chmod +x "$REPO/scripts/worktree-pool.sh"
}

run_hook() {  # $1 = worktree name
  run bash -c "printf '{\"name\":\"$1\",\"cwd\":\"$REPO\"}' | bash '$HOOK'"
}

@test "1. RED PROOF: a repo with no allocator of its own never reaches for reso's" {
  install_cold
  install_foreign_succeeding      # would succeed if called — that is the point
  run_hook demo

  [ "$status" -eq 0 ]
  # The load-bearing assertion: the machine-global allocator was not invoked AT ALL.
  [ ! -f "$HOME/.foreign-ran" ]
  # ...and the path handed back is OURS, not the foreign wt-pool-9 slot.
  [ "$output" = "$COLD" ]
  [ -f "$HOME/.cold-ran" ]
}

@test "2. RED PROOF: a refused pool claim falls THROUGH to the cold path, never exit 1" {
  install_cold
  install_own_pool_failing
  run_hook demo

  [ "$status" -eq 0 ]
  [ -f "$HOME/.own-pool-ran" ]    # the repo's own allocator WAS tried (positive control)
  [ -f "$HOME/.cold-ran" ]        # ...and its refusal degraded to a cold build
  [ "$output" = "$COLD" ]
  grep -q 'falling through to the cold path' "$LOG"
}

@test "3. a successful claim from the repo's OWN pool still wins (no regression)" {
  install_cold
  mkdir -p "$HOME/Development/.worktrees/wt-pool-3"
  cat > "$REPO/scripts/worktree-pool.sh" <<'EOS'
#!/bin/bash
printf '%s\n' "$HOME/Development/.worktrees/wt-pool-3"
exit 0
EOS
  chmod +x "$REPO/scripts/worktree-pool.sh"
  run_hook demo

  [ "$status" -eq 0 ]
  [ "$output" = "$HOME/Development/.worktrees/wt-pool-3" ]
  [ ! -f "$HOME/.cold-ran" ]      # the fast path short-circuits the cold one
}

@test "4. a claim that prints a path which does not EXIST falls through too" {
  install_cold
  cat > "$REPO/scripts/worktree-pool.sh" <<'EOS'
#!/bin/bash
printf '%s\n' "$HOME/Development/.worktrees/wt-pool-does-not-exist"
exit 0
EOS
  chmod +x "$REPO/scripts/worktree-pool.sh"
  run_hook demo

  [ "$status" -eq 0 ]
  [ "$output" = "$COLD" ]
  [ -f "$HOME/.cold-ran" ]
}

@test "5. the installed reso allocator being present+refusing does not break a cold launch" {
  install_cold
  install_foreign_refusing        # the LIVE 2026-08-05 shape: exit 3 on a foreign caller
  run_hook demo

  [ "$status" -eq 0 ]
  [ ! -f "$HOME/.foreign-ran" ]
  [ "$output" = "$COLD" ]
}

@test "6. STDOUT CONTRACT: stdout carries the worktree path and nothing else" {
  # CC aborts `claude -w` with "no successful output" on any other stdout byte — the exact
  # 2026-07-02 break (a hookSpecificOutput JSON blob). Pinned because this hook has no other guard
  # against it, and the 2026-07-18 audit filed its absence as G-P9-9.
  install_cold
  install_foreign_refusing
  run_hook demo

  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  case "$output" in /*) ;; *) false ;; esac
  [ -d "$output" ]
}

@test "7. the pre-created shape (worktree_path in stdin) still echoes the path back" {
  # The older CC hook shape — asserted so the fall-through rewrite cannot have disturbed the
  # early-return rung above it.
  WT="$BATS_TEST_TMPDIR/pre-made"; mkdir -p "$WT"
  run bash -c "printf '{\"worktree_path\":\"$WT\",\"main_worktree\":\"$REPO\"}' | bash '$HOOK'"

  [ "$status" -eq 0 ]
  [ "$output" = "$WT" ]
}
