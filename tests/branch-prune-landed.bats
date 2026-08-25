#!/usr/bin/env bats
# branch-prune-landed.bats — the suite this script had never had.
#
# WHY IT EXISTS. `gate-select --direct` returns the suites whose failure would be *caused by* a
# diff. Across 262 `none-nodirect` lands, exactly one SOURCE file ever landed with an empty direct
# set: scripts/branch-prune-landed.sh, because no suite in the tree named it
# (docs/research/gate-select-direct-empty-2026-08-24.md, backlog 4577c399bf95). The selector was
# right and the tree was thin. This closes that hole for a script that DELETES REMOTE REFS.
#
# WHAT IS LOAD-BEARING. Cases 2, 3, 5, 6 are the REFUSALS, and they are worth more than the ones
# that prove it acts: everything this script deletes is irreversible except through the manifest,
# which is why cases 7-10 pin the record itself (written before the delete, sha resolvable,
# restorable, and folded from INTENT to OUTCOME — including the FAILED batch).
#
# CASE 1 IS THE PREMISE. The script's whole argument is that ancestry is the wrong test and patch
# equivalence is the right one. So case 1 carries git's own `--merged` as a control: the fixture
# branch reads NOT-merged to ancestry and IS pruned here. Without that control the case would pass
# just as well against a script that pruned on ancestry, and would prove nothing.
#
# HERMETIC: a bare fixture "origin" and a clone, both inside $BATS_TEST_TMPDIR, plus a fixture
# $HOME. Every push/delete in this suite lands on the fixture remote; nothing reaches a real one.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export TDIR="$BATS_TEST_TMPDIR/t"; mkdir -p "$TDIR"
  ORIGIN="$TDIR/origin.git"
  SCRIPT="$BATS_TEST_DIRNAME/../scripts/branch-prune-landed.sh"
  MANIFEST="$TDIR/manifest.tsv"
  NOW="$(date +%s)"

  git init -q --bare "$ORIGIN"
  git init -q "$TDIR/repo"
  cd "$TDIR/repo" || return 1
  gc --allow-empty -m base
  git branch -M main
  git remote add origin "$ORIGIN"
  git push -q origin main

  # landed-rewritten — the case the script exists for: its commit is on the trunk BY PATCH, under a
  # different sha, exactly as ship-land's pre-push rebase leaves every branch it lands.
  git checkout -q -b landed-rewritten main
  echo a > a.txt; git add a.txt; aged 172800 -m "adds a"
  git checkout -q main
  cpick landed-rewritten

  # stranded-work — a commit that is on NO trunk. Deleting this branch would lose it.
  git checkout -q -b stranded-work main
  echo z > z.txt; git add z.txt; aged 172800 -m "unlanded work"

  # fresh-landed — landed by patch like the first, but its tip is minutes old: a live session may
  # still be pushing to it, so age alone must hold it back.
  git checkout -q -b fresh-landed main
  echo b > b.txt; git add b.txt; gc -m "adds b"
  git checkout -q main
  cpick fresh-landed

  git checkout -q main
  git push -q origin main landed-rewritten stranded-work fresh-landed
}

# A fixture commit, identity pinned so this never reads the operator's git config.
gc() { git -c user.email=t@t -c user.name=t commit -q "$@"; }

# Land a fixture branch's commit onto the trunk the way ship-land does: by REWRITING it, so the
# trunk carries the patch under a sha the branch has never seen.
cpick() { git -c user.email=t@t -c user.name=t cherry-pick "$@" >/dev/null; }

# A fixture commit whose COMMITTER date is $1 seconds in the past — %ct is what the script ages on,
# so this is the only way the min-age rung is reachable at all.
aged() { local back="$1"; shift; GIT_COMMITTER_DATE="$(( NOW - back ))" gc "$@"; }

# Does the fixture remote still carry this branch?
on_origin() { git --git-dir="$ORIGIN" show-ref --verify --quiet "refs/heads/$1"; }

# The verdict column (6) of the manifest row for branch $1.
verdict() { awk -F'\t' -v b="$1" '$1==b {print $6}' "$MANIFEST"; }

# ── case 1: the premise — patch equivalence, never ancestry ───────────────────────────────────────
@test "1. a branch ancestry calls UNMERGED is pruned when its patch is already on the trunk" {
  # The control comes first: if git's own --merged ever starts listing this branch, the case below
  # stops discriminating and this line says so instead of passing quietly.
  git fetch -q origin
  run git branch -r --merged origin/main
  if printf '%s\n' "$output" | grep -q 'origin/landed-rewritten'; then
    echo "ancestry now calls it merged — this fixture no longer tests patch equivalence" >&2
    return 1
  fi

  run bash "$SCRIPT" --manifest "$MANIFEST"
  [ "$status" -eq 0 ]
  ! on_origin landed-rewritten || { echo "the landed branch survived the prune" >&2; return 1; }
  [ "$(verdict landed-rewritten)" = "DELETED" ]
}

# ── cases 2-6: the refusals ───────────────────────────────────────────────────────────────────────
@test "2. REFUSAL: a branch holding a commit that is on no trunk is never deleted" {
  run bash "$SCRIPT" --manifest "$MANIFEST"
  [ "$status" -eq 0 ]
  on_origin stranded-work
  [ "$(verdict stranded-work)" = "HOLD-stranded" ]
  # and the commit it holds is still reachable, which is the point of holding the ref
  git --git-dir="$ORIGIN" log -1 --format=%s refs/heads/stranded-work | grep -q 'unlanded work'
}

@test "3. REFUSAL: a fully landed branch younger than the min age is never deleted" {
  run bash "$SCRIPT" --manifest "$MANIFEST"
  [ "$status" -eq 0 ]
  on_origin fresh-landed
  [ "$(verdict fresh-landed)" = "HOLD-young" ]
}

@test "4. the age hold is the AGE and nothing else: min-age 0 releases the same branch" {
  # Non-vacuity control for case 3. Without it, case 3 passes against a script that held
  # fresh-landed for any reason at all — including one that never landed-checked it.
  CC_PRUNE_MIN_AGE_H=0 run bash "$SCRIPT" --manifest "$MANIFEST"
  [ "$status" -eq 0 ]
  ! on_origin fresh-landed || { echo "min-age 0 still held the branch" >&2; return 1; }
  [ "$(verdict fresh-landed)" = "DELETED" ]
  # the stranded hold is independent of age and must survive the same run
  on_origin stranded-work
}

@test "5. REFUSAL: --dry-run deletes nothing and says so" {
  run bash "$SCRIPT" --dry-run --manifest "$MANIFEST"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q 'dry-run: nothing deleted' || return 1
  printf '%s\n' "$output" | grep -q 'would delete: landed-rewritten' || return 1
  on_origin landed-rewritten
  on_origin stranded-work
  on_origin fresh-landed
  # INTENT is all a dry run may record — it deleted nothing, so it must claim nothing
  [ "$(verdict landed-rewritten)" = "PRUNE" ]
}

@test "6. REFUSAL: the trunk is never a candidate, whatever its age" {
  CC_PRUNE_MIN_AGE_H=0 run bash "$SCRIPT" --manifest "$MANIFEST"
  [ "$status" -eq 0 ]
  on_origin main
  [ -z "$(verdict main)" ]
}

# ── cases 7-10: the record, which is the only thing that makes a deletion reversible ──────────────
@test "7. every deleted branch is restorable from the sha the manifest recorded" {
  git fetch -q origin
  local before; before="$(git rev-parse origin/landed-rewritten)"
  bash "$SCRIPT" --manifest "$MANIFEST" >/dev/null
  ! on_origin landed-rewritten || { echo "nothing was deleted, so this proves no reversibility" >&2; return 1; }

  local sha; sha="$(awk -F'\t' '$1=="landed-rewritten" {print $2}' "$MANIFEST")"
  [ "$sha" = "$before" ]
  git push -q origin "$sha:refs/heads/landed-rewritten"
  on_origin landed-rewritten
}

@test "8. the manifest records a resolvable sha and a verdict for every branch it considered" {
  bash "$SCRIPT" --dry-run --manifest "$MANIFEST" >/dev/null
  [ "$(grep -vc '^#' "$MANIFEST")" -eq 3 ]   # the three branches; the trunk is never a row
  # Columns are read with awk, never `IFS=$'\t' read`: tab is an IFS *whitespace* character, so
  # `read` collapses a run of them and an empty field silently shifts every column after it left.
  local sha
  while read -r sha; do
    [ -n "$sha" ]
    git cat-file -e "$sha^{commit}"
  done < <(awk -F'\t' '!/^#/ {print $2}' "$MANIFEST")
  [ "$(awk -F'\t' '!/^#/ && $6=="" {n++} END {print n+0}' "$MANIFEST")" -eq 0 ]
}

@test "9. a PRUNE verdict is folded to the OUTCOME, never left as the intent it was written as" {
  bash "$SCRIPT" --manifest "$MANIFEST" >/dev/null
  # PRUNE is written before any push; a row still reading PRUNE afterwards would leave a reader
  # unable to tell a branch we deleted from one we only planned to.
  ! grep -q 'PRUNE' "$MANIFEST" || { echo "an intent verdict survived the run" >&2; return 1; }
  [ "$(verdict landed-rewritten)" = "DELETED" ]
}

@test "10. a FAILED delete batch is reported as failure, in the exit code AND in the manifest" {
  # The remote refuses deletions, which is the one failure the script cannot detect from its own
  # side. A run that reported success here would leave a manifest saying DELETED over live branches.
  git --git-dir="$ORIGIN" config receive.denyDeletes true
  run bash "$SCRIPT" --manifest "$MANIFEST"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -q 'BATCH FAILED' || return 1
  # `grep -qv PATTERN` would be vacuous here — it succeeds on ANY non-matching line. Negate the
  # match itself: the success banner must be ABSENT from the whole run.
  ! printf '%s\n' "$output" | grep -q 'branch-prune-landed: done' || return 1
  [ "$(verdict landed-rewritten)" = "DELETE-FAILED" ]
  on_origin landed-rewritten
}

@test "11. the manifest timestamp column is a real UTC instant on every platform" {
  # The column is part of the restore record: it is how a reader decides whether a deleted branch
  # was live work. `date -r <epoch>` is BSD-only — under GNU date the argument reads as a FILENAME,
  # so on Linux (every cloud session in this fleet) the field silently emptied and the run printed
  # `date: <epoch>: No such file or directory` four times. Bind to the VALUE, not the run's rc.
  bash "$SCRIPT" --dry-run --manifest "$MANIFEST" >/dev/null
  local seen=0 ts
  while read -r ts; do
    seen=$((seen + 1))
    printf '%s\n' "$ts" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' \
      || { echo "a manifest row carries no UTC instant: '$ts'" >&2; return 1; }
  done < <(awk -F'\t' '!/^#/ {print $5}' "$MANIFEST")
  [ "$seen" -eq 3 ]   # an empty manifest would pass the loop above without asserting anything
}

# ── cases 12-14: the CLI, including the class branch-reaper.sh hung on ────────────────────────────
@test "12. an unknown argument is refused with exit 2 and deletes nothing" {
  run bash "$SCRIPT" --not-a-flag
  [ "$status" -eq 2 ]
  on_origin landed-rewritten
}

@test "13. a value-taking flag given LAST exits instead of spinning forever" {
  # branch-reaper.sh hung at 100% CPU on exactly this input, for all three of its value flags: with
  # one positional left, `shift 2` shifts nothing and returns non-zero, which nothing reads. The
  # timeout IS the assertion — without it, this test is the hang.
  local f
  for f in --trunk --manifest; do
    run timeout 10 bash "$SCRIPT" "$f"
    [ "$status" -ne 124 ] || { echo "$f spun until the timeout killed it" >&2; return 1; }
    [ "$status" -ne 0 ] || { echo "$f: a missing value was accepted as success" >&2; return 1; }
  done
}

@test "14. nothing safe to prune ends cleanly, and attempts no delete" {
  # Also the only case that exercises the empty-candidate path under `set -u`, where a bash 3.2
  # expansion of an empty array would abort the script mid-run instead of exiting 0.
  CC_PRUNE_MIN_AGE_H=99999 run bash "$SCRIPT" --manifest "$MANIFEST"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q 'nothing to prune' || return 1
  on_origin landed-rewritten
  on_origin stranded-work
  on_origin fresh-landed
}

@test "15. the manifest defaults to the documented in-repo path when none is given" {
  CC_PRUNE_MIN_AGE_H=99999 run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  local default_path
  default_path="$TDIR/repo/docs/research/branch-prune-manifest-$(date -u +%Y-%m-%d).tsv"
  [ -f "$default_path" ]
  [ ! -f "$MANIFEST" ]
}
