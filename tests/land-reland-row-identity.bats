#!/usr/bin/env bats
# ship-land's `re-land <branch>: …` producer — ONE ROW PER STUCK BRANCH, however many attempts.
#
# WHAT THIS PINS, AND WHY IT HAD NO TEST. The backlog id is `sha256(project ⑟ title ⑟ source)`, so
# the row's identity is only as stable as its LEAST stable component. Two of the three were
# stabilised in turn and each fix left the population growing through the field it did not pin:
# aa1886a5e stabilised the TITLE (it used to carry the sandbox path, the exit code and the pinned
# ref), and 017650872 stabilised the PROJECT. Neither landed with a test, so the invariant they
# both serve — one stuck branch is ONE job to do — was carried by prose alone.
#
# THE MECHANISM 017650872 CLOSED IS A RACE, NOT A LABEL. desk-land.sh hands ship-land a throwaway
# worktree (`$WTROOT/.desk-land-<branch>-<pid>`) and removes it in its own EXIT trap; the failure
# inbox runs from OUR trap, so on a signalled death the two teardowns race. With the admin entry
# gone and the directory still standing, `git rev-parse --show-toplevel` FAILS and cc-backlog's
# project_default falls back to `basename $(pwd)` — the sandbox name, which carries a PID. So the
# row's identity became a function of which process happened to observe the failure. Measured on
# the live store: branch claude/fire-20260818T080549Z-15840-1 owns ELEVEN rows differing in nothing
# but `project=.desk-land-…-17917 / -32615 / -37586 / -39245 / …`. The fix resolves the durable
# checkout ONCE, EARLY (LAND_MAIN_ROOT, main_outer) and hands the answer to the trap: a value
# captured while the worktree is alive cannot be un-resolved by its teardown.
#
# THE CONTROL IS THE PRE-FIX PRODUCER'S OWN BYTES (017650872^), replayed against the identical
# fixture — never a re-implementation of what it used to do. It forks where the current producer
# folds, so this suite cannot go green on a fixture that is simply too weak to express the defect
# (memory: control-must-replay-the-real-artifact). Verified red at authoring: 2 rows, projects
# `.desk-land-feat-stuck-1111` and `-2222`.
#
# AND THE FOLD IS BY BRANCH, NOT A BLANKET COLLAPSE — pinned in the opposite direction too. A
# producer that hashed every failure onto one constant would satisfy the fold test and destroy the
# store; two DIFFERENT branches must still mint two rows.
#
# RESIDUAL, DELIBERATELY NOT PINNED AS BEHAVIOUR (2026-09-09). The guard
# `case "$land_proj" in ""|.*) : ;;` refuses to file a sandbox label EXPLICITLY — and then falls
# through to cc-backlog's cwd default, which in the raced sandbox re-derives the identical volatile
# label. Measured: with LAND_MAIN_ROOT empty the current producer forks exactly like the pre-fix
# one (2 rows). It is UNREACHABLE today because main_outer assigns LAND_MAIN_ROOT before it claims
# the in-flight marker, and the inbox files only past that claim — which is what the last test here
# pins. Pinning the fork itself would guard the bug (memory: stale-assertion-becomes-an-inverted-
# guard), so the ORDERING that makes it unreachable is what is asserted instead.
#
# Fixtures are real git repos under $BATS_TEST_TMPDIR and the store is a per-test CC_BACKLOG_FILE —
# the live ~/.claude/autonomy/backlog.jsonl is never opened. Every test gets a fresh tmpdir, so no
# destructive verb appears anywhere.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"   # hermetic: never touch the live ~/
  export GIT_CONFIG_NOSYSTEM=1
  export GIT_AUTHOR_NAME=fx GIT_AUTHOR_EMAIL=fx@example.invalid
  export GIT_COMMITTER_NAME=fx GIT_COMMITTER_EMAIL=fx@example.invalid
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_BACKLOG_BIN="$REPO/bin/cc-backlog"
  export CC_BACKLOG_PROJECT_WARN=off CC_BACKLOG_COVERAGE_WARN=off
  export CLAUDE_CODE_SESSION_ID=reland-row-identity
  # BATS_TEST_TMPDIR is set, and the producer refuses to file under bats unless FORCED — which is
  # the seam this suite exists to use (see the `on` branch in land_failure_inbox).
  export SHIP_LAND_FAILURE_INBOX=on
  D="$BATS_TEST_TMPDIR/fx"; mkdir -p "$D"
  M="$D/fixtureproj"
  CUR="$BATS_TEST_TMPDIR/fn-current.sh"
  slice "$REPO/scripts/ship-land.sh" > "$CUR"
  [ -s "$CUR" ]                                   # an empty slice would pass every assertion below
}

# slice <file> → the land_failure_inbox function, verbatim, from the SUBJECT's own bytes.
slice() { sed -n '/^land_failure_inbox() {/,/^}/p' "$1"; }

# fx_main → a fixture main checkout with one commit.
fx_main() {
  mkdir -p "$M"
  git -C "$M" init -q "$M"
  git -C "$M" symbolic-ref HEAD refs/heads/main
  git -C "$M" commit -q --allow-empty -m init
}

# fx_sandbox <pid> → a throwaway worktree named like desk-land's, with the teardown race already
# lost: the admin entry is gone and the directory still stands, so git is unresolvable from inside.
fx_sandbox() {
  local s="$D/.desk-land-feat-stuck-$1"
  git -C "$M" worktree add -q --detach "$s" HEAD
  rm -rf "$M/.git/worktrees"
  printf '%s' "$s"
}

# attempt <slice> <sandbox> <branch> <land_main_root> — one failed land observing its own death.
attempt() {
  ( cd "$2" || exit 0
    # shellcheck disable=SC1090
    . "$1"
    INFLIGHT_FILE="$D/inflight"; : > "$INFLIGHT_FILE"   # non-empty ⇒ the land actually STARTED
    # These three are READ BY THE SOURCED SLICE, which shellcheck cannot follow across `.` — the
    # whole point of the harness is that the subject's own bytes consume them. Assigning them is
    # the call, so the finding is a true statement about this file and a false one about the run.
    # shellcheck disable=SC2034
    BRANCH="$3"
    # shellcheck disable=SC2034
    REPO_ROOT="$2"
    # shellcheck disable=SC2034
    LAND_MAIN_ROOT="$4"
    land_failure_inbox 6 exit
  ) >/dev/null 2>&1 || true
}

# rows → the distinct backlog ids of this producer's rows, one per line.
rows() {
  [ -s "$CC_BACKLOG_FILE" ] || return 0
  jq -r 'select((.title // "") | startswith("re-land ")) | .id' "$CC_BACKLOG_FILE" | sort -u
}
row_projects() {
  jq -r 'select((.title // "") | startswith("re-land ")) | .project' "$CC_BACKLOG_FILE" | sort -u
}

@test "two failed attempts on ONE branch under DIFFERENT sandbox labels fold onto ONE row" {
  fx_main
  s1="$(fx_sandbox 1111)"; s2="$(fx_sandbox 2222)"
  attempt "$CUR" "$s1" feat/stuck "$M"
  attempt "$CUR" "$s2" feat/stuck "$M"
  # Filed at all — an inbox that silently wrote nothing would also read as "one row" if counted
  # loosely, so the population is asserted before its size.
  [ "$(rows | wc -l | tr -d ' ')" -eq 1 ]
  # …and under the DURABLE checkout's name, never a sandbox's.
  [ "$(row_projects)" = "fixtureproj" ]
}

@test "the fold is by BRANCH: two stuck branches still mint two rows" {
  fx_main
  s1="$(fx_sandbox 1111)"; s2="$(fx_sandbox 2222)"
  attempt "$CUR" "$s1" feat/stuck-a "$M"
  attempt "$CUR" "$s2" feat/stuck-b "$M"
  [ "$(rows | wc -l | tr -d ' ')" -eq 2 ]
}

@test "CONTROL — the pre-fix producer (017650872^) FORKS on the identical fixture" {
  # The red half. Pinned sha, not a re-implementation: this is the very code the fix replaced.
  git -C "$REPO" cat-file -e '017650872^:scripts/ship-land.sh' 2>/dev/null \
    || skip "017650872^ is unreachable in this checkout — the control cannot replay the real artifact"
  local pre="$BATS_TEST_TMPDIR/fn-prefix.sh"
  git -C "$REPO" show '017650872^:scripts/ship-land.sh' | slice /dev/stdin > "$pre"
  [ -s "$pre" ]
  fx_main
  s1="$(fx_sandbox 1111)"; s2="$(fx_sandbox 2222)"
  attempt "$pre" "$s1" feat/stuck "$M"
  attempt "$pre" "$s2" feat/stuck "$M"
  [ "$(rows | wc -l | tr -d ' ')" -eq 2 ]
  # The forking FIELD, named — so a future reader sees which component carried the identity, not
  # merely that the count was wrong.
  [ "$(row_projects | tr '\n' ' ')" = ".desk-land-feat-stuck-1111 .desk-land-feat-stuck-2222 " ]
}

@test "the durable checkout is resolved BEFORE the in-flight claim that gates the inbox" {
  # What makes the guard's fall-through unreachable (see the header's RESIDUAL note). The inbox
  # files only past inflight_claim; if a refactor ever claimed the marker first, a trap firing in
  # that window would resolve its project from the raced sandbox again.
  local body a b
  body="$(awk '/^main_outer\(\) \{/{f=1} f{print} f&&/^\}/{exit}' "$REPO/scripts/ship-land.sh")"
  [ -n "$body" ]
  a="$(printf '%s\n' "$body" | grep -n '^[[:space:]]*LAND_MAIN_ROOT=' | head -1 | cut -d: -f1)"
  b="$(printf '%s\n' "$body" | grep -n '^[[:space:]]*inflight_claim[[:space:]]*$' | head -1 | cut -d: -f1)"
  # Both endpoints asserted present: a missing one would otherwise make the comparison vacuous
  # (memory: absent-range-endpoint-selects-everything).
  [ -n "$a" ]
  [ -n "$b" ]
  [ "$a" -lt "$b" ]
}
