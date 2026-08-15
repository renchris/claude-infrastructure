#!/usr/bin/env bats
# branch-reaper.bats — the reaper may delete ONLY branch refs whose commits are already ancestors
# of the trunk, and must never touch a worktree-backed, protected, or unlanded branch.
#
# The load-bearing tests are the REFUSALS (2, 3, 4, 8): this script deletes refs, so every test that
# proves it *declines* is worth more than the one that proves it acts. Test 9 pins reversibility.
#
# HERMETIC: fixture $HOME first, and BRANCH_REAPER_MANIFEST_DIR pinned inside BATS_TEST_TMPDIR so a
# run can never write into the operator's real ~/.claude.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export BRANCH_REAPER_MANIFEST_DIR="$BATS_TEST_TMPDIR/manifests"
  export TDIR="$BATS_TEST_TMPDIR/t"; mkdir -p "$TDIR"

  # An "origin" to act as trunk, and a clone whose origin/main is a real remote-tracking ref.
  git init -q --bare "$TDIR/origin.git"
  git init -q "$TDIR/repo"
  cd "$TDIR/repo" || return 1
  git -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
  git branch -M main
  git remote add origin "$TDIR/origin.git"
  git push -q origin main

  # merged, machine-minted  -> IN scope
  git branch wt-00c8a786f8fd main
  git branch agent-a324ff526efde68d main
  # merged, human-named     -> out of scope by default
  git branch feat/something-readable main
  # UNMERGED (holds real work) -> must never be touched
  git checkout -q -b unlanded-work main
  echo x > f.txt; git add f.txt; git -c user.email=t@t -c user.name=t commit -q -m work
  git checkout -q main

  SCRIPT="$BATS_TEST_DIRNAME/../scripts/branch-reaper.sh"
  export SCRIPT
}

@test "1. dry-run is the DEFAULT and deletes nothing" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"DRY RUN"* ]] || false
  git show-ref --verify --quiet refs/heads/wt-00c8a786f8fd
}

@test "2. REFUSAL: an unmerged branch is never a candidate" {
  run bash "$SCRIPT" --confirm --include-named
  [ "$status" -eq 0 ]
  git show-ref --verify --quiet refs/heads/unlanded-work
}

@test "3. REFUSAL: the trunk branch itself is protected" {
  run bash "$SCRIPT" --confirm --include-named
  [ "$status" -eq 0 ]
  git show-ref --verify --quiet refs/heads/main
}

@test "4. REFUSAL: a branch backing a worktree is EXCLUDED from the candidate set" {
  # NOTE ON WHAT THIS CAN AND CANNOT PROVE. git itself refuses to delete a branch checked out in a
  # worktree, so "the branch still exists" passes even with our exclusion removed — that assertion
  # is vacuous (verified by mutation: deleting the exclusion line left it green). So this test binds
  # to what OUR code decides: the branch must be COUNTED as worktree-skipped and must NOT appear in
  # the delete plan. Matching the bare label "has a worktree" is also vacuous — that string prints
  # unconditionally, with a 0 next to it. Bind to the VALUE.
  git worktree add -q "$TDIR/wt-live" wt-00c8a786f8fd
  run bash "$SCRIPT" --confirm
  [ "$status" -eq 0 ]
  git show-ref --verify --quiet refs/heads/wt-00c8a786f8fd
  skipped="$(printf '%s\n' "$output" | sed -n 's/.*skipped, has a worktree: *\([0-9][0-9]*\).*/\1/p')"
  [ "${skipped:-0}" -ge 1 ]
  would="$(printf '%s\n' "$output" | sed -n 's/.*=> would delete: *\([0-9][0-9]*\).*/\1/p')"
  [ "${would:-99}" -eq 1 ]   # only agent-…; the worktree-backed one is not in the plan
  git worktree remove --force "$TDIR/wt-live"
}

@test "5. machine-minted merged branches ARE deleted with --confirm" {
  run bash "$SCRIPT" --confirm
  [ "$status" -eq 0 ]
  ! git show-ref --verify --quiet refs/heads/wt-00c8a786f8fd || false
  ! git show-ref --verify --quiet refs/heads/agent-a324ff526efde68d
}

@test "6. human-named merged branches are OUT of scope by default" {
  run bash "$SCRIPT" --confirm
  [ "$status" -eq 0 ]
  git show-ref --verify --quiet refs/heads/feat/something-readable
}

@test "7. --include-named widens scope to human-named merged branches" {
  run bash "$SCRIPT" --confirm --include-named
  [ "$status" -eq 0 ]
  ! git show-ref --verify --quiet refs/heads/feat/something-readable
}

@test "8. REFUSAL: --keep <regex> excludes matching branches" {
  run bash "$SCRIPT" --confirm --keep '^wt-00c8'
  [ "$status" -eq 0 ]
  git show-ref --verify --quiet refs/heads/wt-00c8a786f8fd
  ! git show-ref --verify --quiet refs/heads/agent-a324ff526efde68d
}

@test "9. every deletion is reversible from the manifest" {
  sha_before="$(git rev-parse refs/heads/wt-00c8a786f8fd)"
  bash "$SCRIPT" --confirm >/dev/null
  ! git show-ref --verify --quiet refs/heads/wt-00c8a786f8fd || false
  m="$(find "$BRANCH_REAPER_MANIFEST_DIR" -name 'reaped-*.tsv' -type f | head -1)"
  [ -f "$m" ]
  run bash "$SCRIPT" --restore "$m"
  [ "$status" -eq 0 ]
  [ "$(git rev-parse refs/heads/wt-00c8a786f8fd)" = "$sha_before" ]
}

@test "10. the manifest is written BEFORE any deletion (and is complete)" {
  bash "$SCRIPT" --confirm >/dev/null
  m="$(find "$BRANCH_REAPER_MANIFEST_DIR" -name 'reaped-*.tsv' -type f | head -1)"
  # one line per deleted ref, each name<TAB>sha with a resolvable sha
  [ "$(wc -l < "$m" | tr -d ' ')" -eq 2 ]
  while IFS=$'\t' read -r name sha; do
    [ -n "$name" ]; git cat-file -e "$sha^{commit}"
  done < "$m"
}

@test "11. a merged branch whose sha is an ancestor stays reachable from trunk after deletion" {
  sha="$(git rev-parse refs/heads/wt-00c8a786f8fd)"
  bash "$SCRIPT" --confirm >/dev/null
  # the whole safety argument: deleting the NAME does not orphan the COMMIT
  run git merge-base --is-ancestor "$sha" origin/main
  [ "$status" -eq 0 ]
}

# ── the three findings of screen-branch-reaper.md, re-verified in TRIAGE-2026-08-15 section 2 ─────
# None had coverage: this suite always passed a value to every flag, never invoked -h, had no
# timeout, and bound only to `skipped, has a worktree` and `would delete` — never the residual.

@test "a value-taking flag given LAST exits instead of spinning forever" {
  # `shift 2` with one positional left shifts nothing and returns non-zero, and nothing reads that
  # status under `set -uo pipefail` with no `-e`. All three flags hung at 100% CPU; two of them are
  # documented usage. The timeout is the assertion — without it this test IS the hang.
  local f
  for f in --trunk --keep --restore; do
    run timeout 10 bash "$SCRIPT" "$f"
    if [ "$status" -eq 124 ]; then echo "$f spun until the timeout killed it" >&2; return 1; fi
    [ "$status" -eq 2 ] || { echo "$f: expected the usage refusal (2), got $status" >&2; return 1; }
  done
}

@test "--help documents every flag the parser implements" {
  # The usage block runs to the --keep line; --help printed a fixed 1,40p and stopped two lines
  # short, hiding exactly the two flags most likely to be typed last and therefore to hang.
  run bash "$SCRIPT" --help
  [ "$status" -eq 0 ]
  local f
  for f in --confirm --include-named --restore --trunk --keep; do
    printf '%s\n' "$output" | grep -qF -- "$f" || { echo "--help never mentions $f" >&2; return 1; }
  done
}

@test "a --keep'd branch is counted as kept, NOT as 'NOT merged (untouched, holds work)'" {
  # The NOT-merged line is a RESIDUAL, so a branch dropped by --keep with no bucket of its own was
  # relabelled as still holding work — a merged, contentless ref reported as unlanded, with nothing
  # about the branch having changed. Ground truth is git's own --no-merged count, which --keep
  # cannot move.
  local truth; truth="$(git branch --no-merged origin/main --format='%(refname:short)' | grep -c . || true)"
  run bash "$SCRIPT"
  local bare; bare="$(printf '%s\n' "$output" | sed -n 's/.*NOT merged.*: *//p')"
  [ "$bare" = "$truth" ] || { echo "bare run: NOT-merged=$bare, ground truth=$truth" >&2; return 1; }

  run bash "$SCRIPT" --keep '^wt-'
  local kept_run; kept_run="$(printf '%s\n' "$output" | sed -n 's/.*NOT merged.*: *//p')"
  [ "$kept_run" = "$truth" ] || {
    echo "--keep moved NOT-merged to $kept_run; ground truth is still $truth" >&2; return 1; }
  local keptn; keptn="$(printf '%s\n' "$output" | sed -n 's/.*--keep pattern: *//p')"
  [ "${keptn:-0}" -ge 1 ] || { echo "--keep matched nothing, so this test proves nothing" >&2; return 1; }
}
