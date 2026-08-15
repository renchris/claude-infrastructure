#!/usr/bin/env bats
# worktree-memory-link.bats — a linked worktree's project memory must resolve to the PRIMARY repo's.
#
# THE DEFECT UNDER TEST (measured 2026-07-31, before this script existed): Claude Code keys project
# state on cwd, so a linked worktree gets its own $CONFIG/projects/<encode(cwd)>/ with NO memory/.
# 164 worktree-keyed project dirs on this box, 0 with memory/, against 213 topic files in the
# primary's. Test 1 is the RED PROOF: it asserts the linked path resolves to the primary's content,
# which is false by construction until the script runs (test 5 pins that pre-state explicitly, so
# the suite would still fail if the script silently became a no-op).
#
# HERMETIC: fixture $HOME first, and CC_WML_CONFIG_DIRS pinned into $BATS_TEST_TMPDIR so this can
# never write into the operator's real ~/.claude/projects. A test that touched the real config dir
# could DESTROY live memory, so the pin is load-bearing, not hygiene.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export TDIR="$BATS_TEST_TMPDIR/t"; mkdir -p "$TDIR"
  git init -q "$TDIR/repo"
  git -C "$TDIR/repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
  git -C "$TDIR/repo" worktree add -q "$TDIR/wt-a" -b branch-a
  # PHYSICAL paths, deliberately. On macOS $BATS_TEST_TMPDIR sits under /var, a symlink to
  # /private/var, and the script resolves with `pwd -P`. Keying the fixture on the UNRESOLVED path
  # made the script compute a different project key than the test asserted on — every assertion then
  # examined a slot the script never touched, which showed up as 5 failures AND one vacuous PASS
  # (the "never clobbers" test passed because the script was nowhere near that directory).
  REPO="$(cd "$TDIR/repo" && pwd -P)"; export REPO
  WT="$(cd "$TDIR/wt-a" && pwd -P)"; export WT

  export CFG="$BATS_TEST_TMPDIR/cfg"
  export CC_WML_CONFIG_DIRS="$CFG"
  export CC_WML_QUIET=1

  # encode(): EVERY character outside [a-zA-Z0-9] -> '-'. See ckey() below for why this suite may
  # not simply re-run the subject's own expression.
  PKEY="$(ckey "$REPO")"
  WKEY="$(ckey "$WT")"
  export PKEY WKEY
  mkdir -p "$CFG/projects/$PKEY/memory"
  echo 'INDEX-CONTENT' > "$CFG/projects/$PKEY/memory/MEMORY.md"

  SCRIPT="$BATS_TEST_DIRNAME/../scripts/worktree-memory-link.sh"
  export SCRIPT
}

# THE ORACLE IS INDEPENDENT OF THE SUBJECT — this is the point, not a style choice. This suite used
# to recompute the project key with the SAME lossy `sed 's|[/.]|-|g'` the script carried, so the
# assertion and the subject moved together and the encoder defect was UNFALSIFIABLE by its own
# tests: run with a TMPDIR containing '_', the suite was 13/13 ok while asserting on slots named
# `…tmp_under…` — keys Claude Code can never emit. A green suite meant nothing.
#
# The rule below is stated from GROUND TRUTH rather than from the script: across all four live
# config roots, 1,661 project dirs, zero contain '_' or '.', and every one matches
# ^[-a-zA-Z0-9]+$; /Users/chrisren/Development/doc_classifier (which exists) is keyed
# -Users-chrisren-Development-doc-classifier in all four, while the narrow rule's
# …-doc_classifier exists nowhere. The last test asserts the SHAPE of the minted slot and
# recomputes nothing at all, so it stays honest even if this helper and the subject ever agree on
# the wrong thing.
ckey() { printf '%s' "$1" | LC_ALL=C sed 's/[^a-zA-Z0-9]/-/g'; }

@test "1. RED PROOF: worktree memory resolves to the primary's content after linking" {
  run bash "$SCRIPT" "$WT"
  [ "$status" -eq 0 ]
  [ -L "$CFG/projects/$WKEY/memory" ]
  # The whole point: reading through the link yields the PRIMARY's index.
  run cat "$CFG/projects/$WKEY/memory/MEMORY.md"
  [ "$status" -eq 0 ]
  [ "$output" = "INDEX-CONTENT" ]
}

@test "2. the primary checkout itself is skipped — never links to itself" {
  run bash "$SCRIPT" "$REPO"
  [ "$status" -eq 0 ]
  [ ! -L "$CFG/projects/$PKEY/memory" ]   # still a real dir, untouched
  [ -d "$CFG/projects/$PKEY/memory" ]
}

@test "3. idempotent — a second run leaves exactly one correct link" {
  bash "$SCRIPT" "$WT"
  bash "$SCRIPT" "$WT"
  [ -L "$CFG/projects/$WKEY/memory" ]
  run cat "$CFG/projects/$WKEY/memory/MEMORY.md"
  [ "$output" = "INDEX-CONTENT" ]
}

@test "4. NEVER clobbers a real memory dir already in the worktree's project slot" {
  mkdir -p "$CFG/projects/$WKEY/memory"
  echo 'PRECIOUS' > "$CFG/projects/$WKEY/memory/local.md"
  run bash "$SCRIPT" "$WT"
  [ "$status" -eq 0 ]
  [ ! -L "$CFG/projects/$WKEY/memory" ]          # left as a real dir
  run cat "$CFG/projects/$WKEY/memory/local.md"
  [ "$output" = "PRECIOUS" ]                      # content survived
}

@test "5. pre-state control: without running the script there is no link (guards against a no-op)" {
  [ ! -e "$CFG/projects/$WKEY/memory" ]
  run cat "$CFG/projects/$WKEY/memory/MEMORY.md"
  [ "$status" -ne 0 ]
}

@test "6. a non-repo path exits 0 and creates nothing" {
  mkdir -p "$TDIR/plain"
  run bash "$SCRIPT" "$TDIR/plain"
  [ "$status" -eq 0 ]
  NKEY="$(ckey "$TDIR/plain")"
  [ ! -e "$CFG/projects/$NKEY" ]
}

@test "7. --all --create backfills every linked worktree of the repo" {
  git -C "$REPO" worktree add -q "$TDIR/wt-b" -b branch-b
  BKEY="$(ckey "$(cd "$TDIR/wt-b" && pwd -P)")"
  run bash "$SCRIPT" --all --create "$REPO"
  [ "$status" -eq 0 ]
  [ -L "$CFG/projects/$WKEY/memory" ]
  [ -L "$CFG/projects/$BKEY/memory" ]
  run cat "$CFG/projects/$BKEY/memory/MEMORY.md"
  [ "$output" = "INDEX-CONTENT" ]
}

@test "11. plain --all does NOT mint project dirs for worktrees that never hosted a session" {
  # Cardinality guard: only 5 of this repo's 118 real worktrees have ever hosted a session, so a
  # sweep that creates a slot per worktree would mint ~226 dirs of pure litter.
  git -C "$REPO" worktree add -q "$TDIR/wt-b" -b branch-b
  BKEY="$(ckey "$(cd "$TDIR/wt-b" && pwd -P)")"
  run bash "$SCRIPT" --all "$REPO"
  [ "$status" -eq 0 ]
  [ ! -e "$CFG/projects/$WKEY" ]
  [ ! -e "$CFG/projects/$BKEY" ]
}

@test "12. plain --all DOES link a worktree whose project dir already exists" {
  mkdir -p "$CFG/projects/$WKEY"          # this worktree has hosted a session
  git -C "$REPO" worktree add -q "$TDIR/wt-b" -b branch-b
  BKEY="$(ckey "$(cd "$TDIR/wt-b" && pwd -P)")"
  run bash "$SCRIPT" --all "$REPO"
  [ "$status" -eq 0 ]
  run cat "$CFG/projects/$WKEY/memory/MEMORY.md"
  [ "$output" = "INDEX-CONTENT" ]         # linked, because its slot existed
  [ ! -e "$CFG/projects/$BKEY" ]          # skipped, because its slot did not
}

@test "13. single-path (hook) mode still creates the slot — that is the whole point" {
  [ ! -e "$CFG/projects/$WKEY" ]
  run bash "$SCRIPT" "$WT"
  [ "$status" -eq 0 ]
  run cat "$CFG/projects/$WKEY/memory/MEMORY.md"
  [ "$output" = "INDEX-CONTENT" ]
}

@test "8. a dangling or mispointed link is repointed at the primary" {
  mkdir -p "$CFG/projects/$WKEY"
  ln -s "../nonexistent-key/memory" "$CFG/projects/$WKEY/memory"
  [ ! -e "$CFG/projects/$WKEY/memory/MEMORY.md" ]   # dangling to start
  run bash "$SCRIPT" "$WT"
  [ "$status" -eq 0 ]
  run cat "$CFG/projects/$WKEY/memory/MEMORY.md"
  [ "$output" = "INDEX-CONTENT" ]
}

@test "9. --check reports without changing anything" {
  run bash "$SCRIPT" --check "$WT"
  [ "$status" -eq 0 ]
  [ ! -e "$CFG/projects/$WKEY/memory" ]
}

@test "10. relative link survives the config dir being moved" {
  bash "$SCRIPT" "$WT"
  mv "$CFG" "$BATS_TEST_TMPDIR/cfg-moved"
  run cat "$BATS_TEST_TMPDIR/cfg-moved/projects/$WKEY/memory/MEMORY.md"
  [ "$status" -eq 0 ]
  [ "$output" = "INDEX-CONTENT" ]
}

@test "14. the project key is the CLASS [^a-zA-Z0-9]→'-' — asserted by SHAPE, recomputing nothing" {
  # The one assertion in this file that cannot move with the subject: it does not encode anything,
  # it states what Claude Code's own encoder can EMIT. Ground truth: 1,661 live project dirs across
  # four config roots, every one matching ^[-a-zA-Z0-9]+$.
  #
  # The fixture path carries exactly the characters the narrow rule kept — an underscore and a
  # space — so a slot minted under `sed 's|[/.]|-|g'` contains them verbatim and is a key no
  # session will ever look up. Under the class rule the same path is keyed in the emittable
  # alphabet and the link is reachable.
  git -C "$REPO" worktree add -q "$TDIR/wt_c d" -b branch-c
  local wtc; wtc="$(cd "$TDIR/wt_c d" && pwd -P)"
  run bash "$SCRIPT" "$wtc"
  [ "$status" -eq 0 ]

  local slot base linked=0
  for slot in "$CFG"/projects/*; do
    [ -e "$slot" ] || continue
    base="$(basename "$slot")"
    case "$base" in
      *[!-a-zA-Z0-9]*)
        echo "project slot outside the emittable alphabet ^[-a-zA-Z0-9]+\$: $base" >&2
        return 1 ;;
    esac
    [ -L "$slot/memory" ] && linked=1
  done
  [ "$linked" = 1 ]                                   # and it actually linked something

  # reading through the new worktree's link yields the primary's index
  run cat "$CFG/projects/$(ckey "$wtc")/memory/MEMORY.md"
  [ "$status" -eq 0 ]
  [ "$output" = "INDEX-CONTENT" ]
}

@test "15. --all reaches a worktree whose path contains a SPACE (porcelain is not whitespace-split)" {
  # `git worktree list --porcelain` does not quote, so `awk '/^worktree /{print $2}'` handed the
  # loop only the first field: `…/wt d` arrived as `…/wt`, which is not a worktree, so the whole
  # tree was lost to `skip (unreadable)` at exit 0 — a silent miss, not an error.
  git -C "$REPO" worktree add -q "$TDIR/wt d" -b branch-d
  local wtd; wtd="$(cd "$TDIR/wt d" && pwd -P)"
  run bash "$SCRIPT" --all --create "$REPO"
  [ "$status" -eq 0 ]
  [ -L "$CFG/projects/$(ckey "$wtd")/memory" ]
  run cat "$CFG/projects/$(ckey "$wtd")/memory/MEMORY.md"
  [ "$output" = "INDEX-CONTENT" ]
}

@test "16. the usage block documents the flag the code actually implements" {
  # The only documentation of the create mode was a comment naming `--all-create`, which nothing
  # implements: the code tests `--create`, so `--all --all-create <repo>` consumed nothing, fell
  # through to the target and reported `not a git repo: --all-create` at exit 0. Neither spelling
  # appeared in the usage block at all.
  run bash "$SCRIPT" --help
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF -- '--all --create'
  printf '%s\n' "$output" | grep -qF 'CC_WML_QUIET'          # the range still covers the whole header
  # Scoped to what a user is SHOWN, not to the file: the file still contains the string inside the
  # comment that explains why the flag never existed, and a guard wide enough to convict its own
  # explanation is the wrong guard.
  if printf '%s\n' "$output" | grep -qF -- '--all-create'; then
    echo "the help advertises --all-create, which nothing implements" >&2; return 1
  fi
}
