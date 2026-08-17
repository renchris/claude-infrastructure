#!/usr/bin/env bats
# cc-backlog code-locality warning (backlog bf63ce9f91fd): a label can be perfectly DISPATCHABLE
# and still name a repo that does not contain the code the item is about. project_dispatch_warn
# cannot see that — it only asks whether the label is in the dispatch set.
#
# THE CONTROL THAT CAN FAIL is "PRE-FIX CONTROL" below: it asserts the SUT actually carries this
# arm. Run against origin/main before the fix, `code_locality_warn` does not exist, no path emits
# the phrase, and that test RED-s — so the green arms here credit this change rather than the
# ambient behaviour of a tool that already warned for some other reason.
#
# The live instance being pinned: a4c0c06e0829 was filed project=reso-management-app while
# tests/cc-close-attrib.bats and bin/cc-close-attrib exist ONLY in claude-infrastructure, so every
# dispatched worker opened the wrong checkout and could not land.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SUT="$REPO/bin/cc-backlog"

  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/autonomy"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"; : > "$CC_BACKLOG_FILE"

  # A throwaway "other project" checkout — a real git repo, so the guard's own
  # `rev-parse --git-dir` precondition is satisfied and silence can never be mistaken for a pass.
  OTHER="$BATS_TEST_TMPDIR/other-repo"
  mk_repo "$OTHER"

  CONF="$BATS_TEST_TMPDIR/dispatch-projects.conf"
  printf 'other-project  repo=%s\n' "$OTHER" > "$CONF"
  export CC_DISPATCH_PROJECTS_CONF="$CONF"

  # A path that exists in the cc-backlog checkout (this repo) and not in $OTHER.
  HERE_PATH="bin/cc-backlog"
}

# mk_repo <dir> — a git repo with one commit. Identity via env, never `git config user.email`
# without -C (that spelling is denied by hooks/validate-bash.sh).
mk_repo() {
  mkdir -p "$1"
  git -C "$1" init -q 2>/dev/null
  mkdir -p "$1/bin"; printf 'x\n' > "$1/bin/placeholder"
  git -C "$1" add -A 2>/dev/null
  env GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t \
    git -C "$1" commit -qm init 2>/dev/null
}

@test "PRE-FIX CONTROL: the SUT carries a code-locality arm at all" {
  # Fails against any revision predating this change — that is the point.
  grep -q 'code_locality_warn' "$SUT"
  grep -q 'does not contain the code this item cites' "$SUT"
}

@test "WARNS when the named project's repo lacks every cited path" {
  run env CC_BACKLOG_PROJECT_WARN=off "$SUT" add \
    --project other-project --title "fix the kill -SEGV fixture in $HERE_PATH"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'does not contain the code this item cites'
}

@test "the id is still on stdout at rc 0 — the caller contract is unchanged" {
  # Every `id=$(cc-backlog add …)` caller must be byte-identical; the warning is stderr-only.
  run env CC_BACKLOG_PROJECT_WARN=off bash -c \
    "'$SUT' add --project other-project --title 'broken $HERE_PATH' 2>/dev/null"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  printf '%s' "$output" | grep -qE '^[0-9a-f]{12}$'
}

@test "SILENT when the cited path DOES exist in the named repo" {
  # n_there > 0 ⇒ the label is at least plausibly right ⇒ no guess.
  run env CC_BACKLOG_PROJECT_WARN=off "$SUT" add \
    --project other-project --title "placeholder is wrong in bin/placeholder"
  [ "$status" -eq 0 ]
  ! printf '%s' "$output" | grep -q 'does not contain the code this item cites'
}

@test "SILENT when the title cites no extractable path" {
  run env CC_BACKLOG_PROJECT_WARN=off "$SUT" add \
    --project other-project --title "the dashboard feels slow when filtering"
  [ "$status" -eq 0 ]
  ! printf '%s' "$output" | grep -q 'does not contain the code this item cites'
}

@test "SILENT when the label has no repo= row — it cannot know, so it does not guess" {
  printf 'other-project  skip=not dispatched yet\n' > "$CONF"
  run env CC_BACKLOG_PROJECT_WARN=off "$SUT" add \
    --project other-project --title "broken $HERE_PATH"
  [ "$status" -eq 0 ]
  ! printf '%s' "$output" | grep -q 'does not contain the code this item cites'
}

@test "SILENT when the declared repo is not a readable git checkout" {
  printf 'other-project  repo=%s/nope\n' "$BATS_TEST_TMPDIR" > "$CONF"
  run env CC_BACKLOG_PROJECT_WARN=off "$SUT" add \
    --project other-project --title "broken $HERE_PATH"
  [ "$status" -eq 0 ]
  ! printf '%s' "$output" | grep -q 'does not contain the code this item cites'
}

@test "SILENT when the named repo IS this repo — there is no locality question" {
  printf 'other-project  repo=%s\n' "$REPO" > "$CONF"
  run env CC_BACKLOG_PROJECT_WARN=off "$SUT" add \
    --project other-project --title "broken $HERE_PATH"
  [ "$status" -eq 0 ]
  ! printf '%s' "$output" | grep -q 'does not contain the code this item cites'
}

@test "CC_BACKLOG_LOCALITY_WARN=off is the opt-out for fixture callers" {
  run env CC_BACKLOG_PROJECT_WARN=off CC_BACKLOG_LOCALITY_WARN=off "$SUT" add \
    --project other-project --title "broken $HERE_PATH"
  [ "$status" -eq 0 ]
  ! printf '%s' "$output" | grep -q 'does not contain the code this item cites'
}

@test "an untracked path in the named repo still counts as present" {
  # A worker provisioned from that repo would find it, so `ls-tree HEAD` alone would over-warn.
  mkdir -p "$OTHER/scripts"; printf 'y\n' > "$OTHER/scripts/fresh.sh"
  run env CC_BACKLOG_PROJECT_WARN=off "$SUT" add \
    --project other-project --title "fix scripts/fresh.sh"
  [ "$status" -eq 0 ]
  ! printf '%s' "$output" | grep -q 'does not contain the code this item cites'
}
