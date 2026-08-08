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

  # `-b main` is HERMETICITY, not style: init.defaultBranch is unset on this box, so a bare
  # `git init` fixture lands on `master`, while the real scripts/new-worktree.sh resolves its base
  # as origin/main → main and then fails to find it. That left tests 8 and 9 — the two that use the
  # REAL cold builder — red from the environment rather than from the subject (measured 2026-08-08,
  # red at HEAD before this file's ownership tests existed). The suite must not read a git config
  # it does not set.
  REPO="$BATS_TEST_TMPDIR/repo"
  git init -q -b main "$REPO"
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

# The REAL scripts/new-worktree.sh from this checkout as the cold builder, for the tests that must
# exercise the actual argv contract rather than a stub's. install_cold above accepts ANY argv[1] and
# honours argv[2], so every test using it was structurally BLIND to the 2026-08-05 defect: the real
# script refused any argv[1] containing '/' (exit 2) and ignored argv[2] entirely. A stub that is
# more permissive than production cannot fail the way production fails.
install_cold_real() {
  cp "$BATS_TEST_DIRNAME/../scripts/new-worktree.sh" "$REPO/scripts/new-worktree.sh"
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

@test "8. END-TO-END, REAL cold builder: a SLASHED -w name builds and the paths AGREE" {
  # RED PROOF (measured 2026-08-05 against HEAD~: rc 1, empty stdout, log "must be a bare name").
  # The hook keeps '/' in $BRANCH — its sanitiser's tr allows it — but derives WT from the SLUGGED
  # name, so this pins the two things that were in conflict: the build SUCCEEDS, and the path the
  # hook prints is the path that actually got created.
  install_cold_real
  run_hook feat/slashed

  [ "$status" -eq 0 ]
  [ "$output" = "$HOME/Development/.worktrees/wt-feat-slashed" ]
  [ -d "$output" ]
  # ...and the branch keeps its '/' — the reso-parity half (slugging argv[1] would rename feat/x).
  [ "$(git -C "$output" branch --show-current)" = "feat/slashed" ]
}

@test "9. END-TO-END, REAL cold builder: a bare -w name is byte-identical to before" {
  # The no-regression side: the ~/.zshrc gate only ever passes a bare cc-<HHMMSS>-<pid>, so the
  # derived-path guarantee it depends on must be untouched by the widening.
  install_cold_real
  run_hook demo

  [ "$status" -eq 0 ]
  [ "$output" = "$COLD" ]
  [ "$(git -C "$output" branch --show-current)" = "demo" ]
}

# ── 10-13: the exit-point ownership assertion (backlog 4afd0515c83a, 2026-08-08) ────────────────
#
# THE DEFECT: on 2026-08-04 01:18 an `Agent isolation:"worktree"` spawn from a claude-infrastructure
# session was handed reso's wt-pool-2 — a worktree of ANOTHER REPOSITORY — and on 2026-08-05 01:16
# the same rung took wt-pool-9. Both lines are in worktree-lifecycle.log. Tests 1-5 above cover the
# fallback that produced them; these cover the QUESTION, which nothing asked: is the path we are
# about to hand back even ours?
#
# WHY A REAL SECOND REPO. The assertion is `git rev-parse --git-common-dir`, so only a genuine
# foreign worktree can trigger it — the mkdir'd stub dirs in tests 1-7 resolve to no repo at all,
# which is the assertion's deliberate third outcome (unattributable ⇒ not refused) and the reason
# this change left every one of them green.
make_foreign_worktree() {  # <dest> → a REAL worktree belonging to a DIFFERENT repository
  local other="$BATS_TEST_TMPDIR/other-repo"
  [ -d "$other" ] || {
    git init -q -b main "$other"
    git -C "$other" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
  }
  mkdir -p "$(dirname "$1")"
  git -C "$other" worktree add -q "$1" -b "foreign-$(basename "$1")" >/dev/null 2>&1
}

@test "10. RED PROOF: a pool slot belonging to ANOTHER repo is refused, not returned" {
  # The 2026-08-04 shape exactly: the allocator succeeds, prints a real directory, and the directory
  # is reso's. Pre-fix the hook printed it and exited 0 — that is how an agent got the wrong repo.
  install_cold
  make_foreign_worktree "$HOME/Development/.worktrees/wt-pool-9"
  cat > "$REPO/scripts/worktree-pool.sh" <<'EOS'
#!/bin/bash
printf '%s\n' "$HOME/Development/.worktrees/wt-pool-9"
exit 0
EOS
  chmod +x "$REPO/scripts/worktree-pool.sh"
  run_hook demo

  [ "$status" -eq 0 ]
  [ "$output" != "$HOME/Development/.worktrees/wt-pool-9" ]   # the load-bearing assertion
  [ "$output" = "$COLD" ]                                     # ...degraded to the cold rung
  [ -f "$HOME/.cold-ran" ]
  grep -q 'FOREIGN WORKTREE REFUSED' "$LOG"
}

@test "11. NEGATIVE CONTROL: a pool slot that really is OURS is still returned" {
  # Without this, test 10 could not tell "the guard reads ownership" from "the pool rung got
  # stricter" — both would pass. Same rung, same shape, only the owning repo differs.
  install_cold
  MINE="$HOME/Development/.worktrees/wt-pool-mine"
  mkdir -p "$(dirname "$MINE")"
  git -C "$REPO" worktree add -q "$MINE" -b pool-mine
  cat > "$REPO/scripts/worktree-pool.sh" <<EOS
#!/bin/bash
printf '%s\n' "$MINE"
exit 0
EOS
  chmod +x "$REPO/scripts/worktree-pool.sh"
  run_hook demo

  [ "$status" -eq 0 ]
  [ "$output" = "$MINE" ]
  [ ! -f "$HOME/.cold-ran" ]                                  # the fast path still short-circuits
  ! grep -q 'FOREIGN WORKTREE REFUSED' "$LOG"
}

@test "12. the pre-created shape refuses a foreign path BEFORE copying .env.local into it" {
  # This rung's setup step writes a secret into the tree it was handed, so the check has to precede
  # it: a leaked .env.local is not undone by a later refusal.
  printf 'SECRET=1\n' > "$REPO/.env.local"
  WT="$HOME/Development/.worktrees/wt-precreated-foreign"
  make_foreign_worktree "$WT"
  run bash -c "printf '{\"worktree_path\":\"$WT\",\"main_worktree\":\"$REPO\"}' | bash '$HOOK'"

  [ "$status" -eq 1 ]
  [ -z "$output" ]
  [ ! -f "$WT/.env.local" ]
  grep -q 'FOREIGN WORKTREE REFUSED' "$LOG"
}

@test "13. a cold builder wired to the wrong repo fails the launch instead of returning it" {
  # No rung remains below the cold one, so there is nothing to degrade to: the only safe answer is a
  # failed `claude -w`. Models a repo whose own new-worktree.sh points at another repository.
  cat > "$REPO/scripts/new-worktree.sh" <<EOS
#!/bin/bash
git -C "$BATS_TEST_TMPDIR/other-repo" worktree add -q "\$2" -b "wrong-\$1" >/dev/null 2>&1
EOS
  chmod +x "$REPO/scripts/new-worktree.sh"
  git init -q -b main "$BATS_TEST_TMPDIR/other-repo"
  git -C "$BATS_TEST_TMPDIR/other-repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
  run_hook demo

  [ "$status" -eq 1 ]
  [ -z "$output" ]
  grep -q 'FOREIGN WORKTREE REFUSED' "$LOG"
}

@test "7. the pre-created shape (worktree_path in stdin) still echoes the path back" {
  # The older CC hook shape — asserted so the fall-through rewrite cannot have disturbed the
  # early-return rung above it.
  WT="$BATS_TEST_TMPDIR/pre-made"; mkdir -p "$WT"
  run bash -c "printf '{\"worktree_path\":\"$WT\",\"main_worktree\":\"$REPO\"}' | bash '$HOOK'"

  [ "$status" -eq 0 ]
  [ "$output" = "$WT" ]
}
