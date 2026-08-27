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

@test "the worktree guard answers KEPT for a member even when the worktree-branch list is past the SIGPIPE floor" {
  # WHAT TEST 4 CANNOT SEE, AND WHY THIS ARM EXISTS. Test 4 proves the exclusion decides correctly
  # on a fixture whose worktree-branch list is ONE branch — about 17 bytes. The defect this arm
  # pins is a function of the list's SIZE, so test 4 stayed green over it for the whole of the
  # defect's life. A red count says a suite noticed; only a differently-sized fixture says which.
  #
  # WHY 120,000 AND NOT ANOTHER NUMBER. Measured 2026-08-27 against the REAL extracted function,
  # 20 trials per cell at load ~71: `printf | grep -q` (two stages, builtin producer) answers
  # correctly 20/20 at 1,323 B (the live feed that day) and at 20,000 B, and INVERTS 20/20 at
  # 120,000 B with the needle at the HEAD — and is correct again at 120,000 B with the needle at
  # the TAIL, because `grep -q` exits at the FIRST match, so the earlier the needle the sooner the
  # pipe closes. 120,000-at-the-head is inside the always-inverted band, so a re-introduced
  # `grep -q` fails this arm on EVERY run rather than one in twenty.
  #
  # This is a MECHANISM arm, not a spelling arm: it feeds the real function and reads its answer,
  # so it survives any rewording of the cure.
  local fn feed body needle
  [ "$(/usr/bin/grep -c '^is_kept() {' "$SCRIPT")" -eq 1 ]
  fn="$BATS_TEST_TMPDIR/is_kept.sh"
  awk '/^is_kept\(\) \{/,/^\}/' "$SCRIPT" > "$fn"
  [ "$(/usr/bin/grep -c 'worktree_branches' "$fn")" -ge 1 ]

  needle="wt-00c8a786f8fd"
  body="$(awk 'BEGIN{for(i=0;i<6000;i++) printf "filler/branch-%06d\n", i}')"
  [ "${#body}" -ge 120000 ]

  # PIPEFAIL MUST BE ON, or this arm is vacuous: without it the pre-fix pipeline answers correctly
  # too and no fixture size could ever make it fail.
  run bash -c 'set -uo pipefail; case "$(set -o | /usr/bin/grep "^pipefail")" in *on*) echo PF=on;; *) echo PF=off;; esac'
  [[ "$output" == *"PF=on"* ]] || false

  # POSITIVE: the needle is a MEMBER, at the head of an oversized list. Correct answer is KEPT (0).
  feed="$needle
$body"
  FEED="$feed" run bash -c '
    set -uo pipefail
    PROTECTED="^(main|master|trunk|HEAD)$"
    KEEP_EXTRA=()
    worktree_branches="$FEED"
    . "$1"
    is_kept "$2"; echo "verdict=$?"' _ "$fn" "$needle"
  [[ "$output" == *"verdict=0"* ]] || {
    echo "a worktree-held branch read NOT-KEPT at $(printf %s "$feed" | wc -c) bytes — it is reapable" >&2; false; }

  # NEGATIVE CONTROL: the same oversized list with the needle ABSENT must answer NOT-KEPT (1). This
  # is what stops the arm passing by always answering 0. It must hold in BOTH states of the subject.
  FEED="$body" run bash -c '
    set -uo pipefail
    PROTECTED="^(main|master|trunk|HEAD)$"
    KEEP_EXTRA=()
    worktree_branches="$FEED"
    . "$1"
    is_kept "$2"; echo "verdict=$?"' _ "$fn" "$needle"
  [[ "$output" == *"verdict=1"* ]] || { echo "NEG control: a non-member read KEPT" >&2; false; }
}

@test "no pipeline feeds the fleet-sized worktree-branch list into an early-exiting grep" {
  # SPAN = THE WHOLE FILE, deliberately, because this is a property of ONE VARIABLE and it had TWO
  # consumers: is_kept's, and the main loop's own guard ~11 lines below it. A span narrowed to the
  # function would have pinned one and left the other, and the two are not independent belts — one
  # oversized feed inverted both at once.
  #
  # Comment lines are stripped FIRST: the cure carries a comment naming the hazard by name, and a
  # raw grep would convict the fixed file for documenting its own fix.
  local code
  code="$BATS_TEST_TMPDIR/code.sh"
  /usr/bin/grep -v '^[[:space:]]*#' "$SCRIPT" > "$code"
  [ "$(/usr/bin/grep -cE 'worktree_branches.*grep -q' "$code")" -eq 0 ]
  # …and the cure is WIRED at both sites, so this cannot pass by the variable simply disappearing.
  [ "$(/usr/bin/grep -cE 'case .*worktree_branches' "$code")" -eq 2 ]
}
