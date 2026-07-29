#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2329
# cc-tlid — the task-board SHARING KEY. Hermetic: every test builds its own git repo under
# BATS_TEST_TMPDIR and points CC_TASKS_INDEX at a temp file, so nothing reads the operator's
# real ~/.claude/tasks-index.json or the live checkout.
#
# The invariant that matters most is the LAST test: cc-tlid must never print an empty id. It runs in
# the launcher hot path, and an empty id makes Claude Code fall back to a per-session throwaway board
# — the fleet silently un-shares itself with no error anywhere. Every degradation path is asserted to
# still produce a usable id rather than to exit non-zero.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  C="$REPO/bin/cc-tlid"
  D="$BATS_TEST_TMPDIR"
  export CC_TASKS_INDEX="$D/tasks-index.json"
  mkrepo() { # <path> — a git repo with one commit (worktrees need a commit to branch from)
    mkdir -p "$1" && git -C "$1" init -q
    git -C "$1" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  }
}

@test "primary checkout → bare repo basename (no branch component)" {
  mkrepo "$D/myproj"
  run bash -c "cd '$D/myproj' && '$C'"
  [ "$status" -eq 0 ]
  [ "$output" = "myproj" ]
}

@test "branch does NOT change the id — the whole point of the repo-identity key" {
  mkrepo "$D/myproj"
  git -C "$D/myproj" checkout -q -b some/feature-branch
  run bash -c "cd '$D/myproj' && '$C'"
  [ "$status" -eq 0 ]
  [ "$output" = "myproj" ]
}

@test "linked worktree resolves to the PRIMARY repo, not the worktree dir" {
  mkrepo "$D/myproj"
  git -C "$D/myproj" worktree add -q -b wt1 "$D/wt-elsewhere" >/dev/null 2>&1
  [ -d "$D/wt-elsewhere" ] || skip "git worktree unavailable"
  run bash -c "cd '$D/wt-elsewhere' && '$C'"
  [ "$status" -eq 0 ]
  # Would be "wt-elsewhere" (or "wt-elsewhere-wt1" under the old scheme) if --git-common-dir
  # were replaced by --show-toplevel. That substitution is the bug this test exists to catch.
  [ "$output" = "myproj" ]
}

@test "a subdirectory of the repo resolves to the repo, not the subdir" {
  mkrepo "$D/myproj"
  mkdir -p "$D/myproj/src/deep/nested"
  run bash -c "cd '$D/myproj/src/deep/nested' && '$C'"
  [ "$status" -eq 0 ]
  [ "$output" = "myproj" ]
}

@test "non-git directory → <basename>-nogit (historical convention preserved)" {
  mkdir -p "$D/plainly"
  run bash -c "cd '$D/plainly' && '$C'"
  [ "$status" -eq 0 ]
  [ "$output" = "plainly-nogit" ]
}

@test "same basename owned by a DIFFERENT project → disambiguated with a path hash" {
  mkrepo "$D/dup"
  printf '{"taskLists":{"dup":{"project":"/somewhere/else/dup"}}}\n' > "$CC_TASKS_INDEX"
  run bash -c "cd '$D/dup' && '$C'"
  [ "$status" -eq 0 ]
  [ "$output" != "dup" ] || false            # must NOT silently share the incumbent's board
  case "$output" in dup-*) ;; *) false ;; esac
}

@test "index says WE own the basename → keep the clean name (incumbent is never renamed)" {
  mkrepo "$D/mine"
  real="$(cd "$D/mine" && pwd -P)"
  printf '{"taskLists":{"mine":{"project":"%s"}}}\n' "$real" > "$CC_TASKS_INDEX"
  run bash -c "cd '$D/mine' && '$C'"
  [ "$status" -eq 0 ]
  [ "$output" = "mine" ]
}

@test "repo basename with path-unsafe characters is sanitised to one safe segment" {
  mkrepo "$D/we ird:name"
  run bash -c "cd '$D/we ird:name' && '$C'"
  [ "$status" -eq 0 ]
  case "$output" in */*|.*|"") false ;; esac
  printf '%s' "$output" | grep -Eq '^[A-Za-z0-9._-]+$' || false
}

@test "--explain reports the resolved primary and the reason" {
  mkrepo "$D/myproj"
  run bash -c "cd '$D/myproj' && '$C' --explain"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'id: *myproj' || false
  echo "$output" | grep -q 'primary:' || false
}

@test "NEVER prints an empty id — degradation must stay usable, not silently un-share the fleet" {
  mkrepo "$D/myproj"
  # Every degradation at once: unreadable index, and a PATH without jq.
  printf 'not json at all\n' > "$CC_TASKS_INDEX"
  run bash -c "cd '$D/myproj' && PATH=/usr/bin:/bin '$C'"
  [ "$status" -eq 0 ]
  [ -n "$output" ] || false
  run bash -c "cd '$D' && CC_TASKS_INDEX=/nonexistent/idx.json '$C'"
  [ "$status" -eq 0 ]
  [ -n "$output" ] || false
}
