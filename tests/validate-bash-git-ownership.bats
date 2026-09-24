#!/usr/bin/env bats
# validate-bash GIT-OWNERSHIP — `git reset --hard`, `git stash drop`, `git restore` decided on the
# repo's live state instead of by three blanket `permissions.ask` rules.
#
# Census (docs/plans/PERMISSION_PROMPT_CONSOLIDATION.md, 30 days to 2026-09-24): 64 + 29 + 11 prompts,
# ~150 h of stalled sessions, on resets of clean trees, drops of the session's own tagged stash, and
# unstage-only restores. Every PERMIT here is paired with the sibling that differs by one lever and
# must still ASK; the parent artifact is replayed from git to prove the permits were real asks.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/validate-bash.sh"
  unset KITTY_WINDOW_ID
  export IT2_WRAPPER_NO_KITTY=1
  export CC_SHARED_CHECKOUT="$BATS_TEST_TMPDIR/shared"; mkdir -p "$CC_SHARED_CHECKOUT"
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
  # A repo one commit BEHIND its origin/main, clean: resetting onto origin/main loses nothing.
  FX="$BATS_TEST_TMPDIR/fx"
  mkdir -p "$FX"
  git -C "$FX" init -q -b main .
  git -C "$FX" commit -q --allow-empty -m A
  printf 'x\n' > "$FX/f"; git -C "$FX" add f; git -C "$FX" commit -q -m B
  git -C "$FX" update-ref refs/remotes/origin/main HEAD
  git -C "$FX" reset -q --hard HEAD~1
  command -v jq >/dev/null 2>&1 || skip "jq not installed"
}

decide_with() {  # <hook> <command> [cwd] → DENY | ASK | PASS
  local out
  out="$(python3 -c 'import json,sys;print(json.dumps({"session_id":"7bacff59-dcaa-472c-8600-cca1baaa4ae4","cwd":sys.argv[2],"tool_input":{"command":sys.argv[1]}}))' "$2" "${3:-$FX}" \
        | bash "$1" 2>/dev/null)"
  [ -z "$out" ] && { printf 'PASS'; return 0; }
  printf '%s' "$out" | python3 -c 'import sys,json;print(json.load(sys.stdin)["hookSpecificOutput"]["permissionDecision"].upper())'
}
decision() { decide_with "$HOOK" "$@"; }

parent_hook() {
  local pre="$BATS_TEST_TMPDIR/parent"
  mkdir -p "$pre"
  ln -sfn "$REPO/hooks/lib" "$pre/lib"
  git -C "$REPO" show 871b87723:hooks/validate-bash.sh > "$pre/validate-bash.sh"
  printf '%s' "$pre/validate-bash.sh"
}

# ── reset --hard ────────────────────────────────────────────────────────────────────────────────

@test "PERMITS a reset --hard that loses nothing: clean tree, no local commit, read-only prelude" {
  [ "$(decision 'git reset --hard origin/main -q')" = "PASS" ]
  [ "$(decision 'git reset -q --hard origin/main')" = "PASS" ]
  [ "$(decision $'set -e\ngit fetch origin -q 2>/dev/null || true\necho "before"\ngit reset --hard origin/main -q\ngit log --oneline -1')" = "PASS" ]
  # A local commit whose patch is ALREADY in the target is not lost either (git cherry reads `-`).
  printf 'x\n' > "$FX/f"; git -C "$FX" add f; git -C "$FX" commit -q -m B-again
  [ "$(decision 'git reset --hard origin/main')" = "PASS" ]
}

@test "SIBLINGS of reset --hard still ASK: dirty tree, a unique local commit, re-aimed repo, opaque shapes" {
  printf 'y\n' > "$FX/g"; git -C "$FX" add g
  [ "$(decision 'git reset --hard origin/main')" = "ASK" ]                   # staged change
  git -C "$FX" reset -q; rm -f "$FX/g"
  printf 'z\n' > "$FX/h"; git -C "$FX" add h; git -C "$FX" commit -q -m C
  [ "$(decision 'git reset --hard origin/main')" = "ASK" ]                   # a commit only HERE
  printf 'w\n' >> "$FX/h"
  [ "$(decision 'git reset --hard HEAD')" = "ASK" ]                          # unstaged tracked edit
  git -C "$FX" reset -q --hard HEAD~1
  [ "$(decision 'cd /tmp && git reset --hard origin/main')" = "ASK" ]
  [ "$(decision "git -C $FX reset --hard origin/main")" = "ASK" ]
  [ "$(decision 'GIT_DIR=/x/.git git reset --hard origin/main')" = "ASK" ]
  [ "$(decision 'git stash pop; git reset --hard origin/main')" = "ASK" ]
  [ "$(decision "bash -c 'git reset --hard origin/main'")" = "ASK" ]
  [ "$(decision 'timeout 9 git reset --hard origin/main')" = "ASK" ]
  [ "$(decision 'git reset --hard "$T"')" = "ASK" ]
  [ "$(decision 'git reset --hard no-such-ref')" = "ASK" ]
  [ "$(decision 'git reset --hard origin/main' "$BATS_TEST_TMPDIR")" = "ASK" ]   # not a repo
}

@test "a MENTION of reset --hard is not an invocation" {
  [ "$(decision 'git commit -m "never git reset --hard here"')" = "PASS" ]
}

# ── stash drop ──────────────────────────────────────────────────────────────────────────────────

@test "PERMITS dropping the entry this command re-found by its own tag; bare or indexed drops ASK" {
  [ "$(decision $'N=$(git stash list --format=\'%gd %gs\' | grep mytag-42 | head -1 | cut -d\' \' -f1); [ -n "$N" ] && git stash drop "$N"')" = "PASS" ]
  [ "$(decision 'git stash drop')" = "ASK" ]
  [ "$(decision 'git stash drop stash@{0}')" = "ASK" ]
  [ "$(decision 'git stash drop "$N"')" = "ASK" ]                                     # N bound elsewhere
  [ "$(decision $'N=stash@{0}; git stash drop "$N"')" = "ASK" ]                       # not tag-selected
  [ "$(decision 'git -C /x stash drop')" = "ASK" ]
}

# ── restore ─────────────────────────────────────────────────────────────────────────────────────

@test "PERMITS an unstage-only restore; anything touching the working tree ASKS" {
  [ "$(decision 'git restore --staged f')" = "PASS" ]
  [ "$(decision 'git restore -S f')" = "PASS" ]
  [ "$(decision 'git restore f')" = "ASK" ]
  [ "$(decision 'git restore --staged --worktree f')" = "ASK" ]
  [ "$(decision 'git restore -SW f')" = "ASK" ]
  [ "$(decision 'git restore --source=HEAD --staged --worktree f')" = "ASK" ]
  [ "$(decision 'git log --grep restore')" = "PASS" ]
}

# ── the parent ──────────────────────────────────────────────────────────────────────────────────

@test "RED ON PARENT: the pre-change hook asked on the lossless reset and on the mention" {
  local pre; pre="$(parent_hook)"
  ! cmp -s "$HOOK" "$pre" || false
  [ "$(decide_with "$pre" 'git reset --hard origin/main -q')" = "ASK" ]
  [ "$(decide_with "$pre" 'git commit -m "never git reset --hard here"')" = "ASK" ]
  # …and never saw the re-aimed or flag-first spellings at all (the settings rule missed them too).
  [ "$(decide_with "$pre" "git -C $FX reset --hard origin/main")" = "PASS" ]
  [ "$(decide_with "$pre" 'git stash drop')" = "PASS" ]
}
