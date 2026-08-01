#!/usr/bin/env bash
# branch-reaper.sh — delete local branch REFS whose commits are already ancestors of the trunk.
#
# THE PROBLEM. Measured 2026-08-01: 1,354 local branches, 647 of them ancestors of origin/main,
# growing ~5.5x/week with no reaper. scripts/worktree-gc.sh reaps worktree DIRECTORIES but never
# branches — deliberately, so a vanished worktree stays recoverable via its branch. Nothing has ever
# reaped the branch side, so refs accumulate without bound. This matters now because the fleet is
# moving to per-session worktree isolation, which mints one branch + one worktree per session at
# 14-27 sessions/day: without a reaper, isolation compounds the very cardinality problem that was
# the strongest argument against it.
#
# WHY DELETING AN ANCESTOR-MERGED REF LOSES NOTHING. The gate is `git branch --merged <trunk>`:
# the branch tip is an ANCESTOR of the trunk, so every commit it names is already reachable from
# the trunk and is not a deletion candidate for gc. Deleting the ref removes a NAME, not history.
# This is deliberately STRICTER than worktree-gc's landed test, which also accepts patch-id
# equivalence via `git cherry` (rebased/cherry-picked content that landed under a different sha).
# Patch-id equivalence is the right call when DECIDING NOT TO DELETE A DIRECTORY; it is the wrong
# call for deleting a ref, because a patch-id match can be coincidental for small diffs and the
# ref is the last durable carrier. Strict-ancestor only. (memory: verify-by-CONTENT, and
# search-branch-graveyard-before-building — the graveyard is exactly what this must not eat.)
#
# WHAT IT WILL NOT TOUCH, EVER:
#   • a branch with a checked-out worktree (118 of them today) — that is a live session's carrier,
#     and hooks/git-worktree-guard.sh independently refuses this too.
#   • the trunk, or anything in $PROTECTED.
#   • a branch that is NOT an ancestor of the trunk — i.e. every branch holding unlanded work,
#     which is 707 of the 1,354 and includes every peer session's WIP.
#   • by default, human-named branches. Only machine-minted names (wt-<hex>, agent-<hex>,
#     cc-<HHMMSS>-<pid>, session-<hex>) are in scope, because nobody refers to those by name.
#     `--include-named` widens to every merged branch; it is never the default.
#
# REVERSIBILITY. Every run writes a restore manifest (name<TAB>sha) BEFORE deleting anything, and
# `--restore <manifest>` recreates every ref in it. Since the shas are ancestors of the trunk they
# cannot be gc'd out from under the manifest, so the undo stays valid indefinitely.
#
# Usage:
#   branch-reaper.sh                      dry-run (DEFAULT — prints the plan, deletes nothing)
#   branch-reaper.sh --confirm            actually delete
#   branch-reaper.sh --include-named      widen scope to human-named merged branches too
#   branch-reaper.sh --restore <manifest> recreate every ref recorded in a manifest
#   branch-reaper.sh --trunk <ref>        override trunk (default origin/main)
#   branch-reaper.sh --keep <regex>       additional never-delete pattern (repeatable)

set -uo pipefail

TRUNK="origin/main"
CONFIRM=0
INCLUDE_NAMED=0
RESTORE=""
KEEP_EXTRA=()
MANIFEST_DIR="${BRANCH_REAPER_MANIFEST_DIR:-$HOME/.claude/autonomy/branch-reaper}"

# Machine-minted branch names: nobody refers to these by name, so reaping them is invisible.
AUTO_RE='^(wt-[0-9a-f]{8,}|agent-[0-9a-f]{8,}|cc-[0-9]{6}-[0-9]+|session-[0-9a-f]{8,}|pool/slot-[0-9]+)$'
PROTECTED='^(main|master|trunk|HEAD)$'

die() { printf 'branch-reaper: %s\n' "$1" >&2; exit "${2:-1}"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --confirm) CONFIRM=1; shift;;
    --include-named) INCLUDE_NAMED=1; shift;;
    --restore) RESTORE="${2:-}"; shift 2;;
    --trunk) TRUNK="${2:-}"; shift 2;;
    --keep) KEEP_EXTRA+=("${2:-}"); shift 2;;
    -h|--help) sed -n '1,40p' "$0"; exit 0;;
    *) die "unknown arg: $1" 2;;
  esac
done

git rev-parse --git-dir >/dev/null 2>&1 || die "not a git repository" 2

# ── restore mode ────────────────────────────────────────────────────────────
if [ -n "$RESTORE" ]; then
  [ -f "$RESTORE" ] || die "manifest not found: $RESTORE" 2
  n=0; fail=0
  while IFS=$'\t' read -r name sha; do
    [ -n "${name:-}" ] && [ -n "${sha:-}" ] || continue
    if git show-ref --verify --quiet "refs/heads/$name"; then
      printf '  = exists, skipped: %s\n' "$name"
    elif git branch "$name" "$sha" 2>/dev/null; then
      n=$((n+1)); printf '  + restored: %s -> %s\n' "$name" "${sha:0:12}"
    else
      fail=$((fail+1)); printf '  ! FAILED:   %s -> %s\n' "$name" "${sha:0:12}" >&2
    fi
  done < "$RESTORE"
  printf 'branch-reaper: restored %d ref(s), %d failure(s)\n' "$n" "$fail"
  [ "$fail" -eq 0 ] || exit 1
  exit 0
fi

git rev-parse --verify --quiet "$TRUNK" >/dev/null || die "trunk not found: $TRUNK (fetch first?)" 2

# Branches that currently back a worktree — NEVER candidates. Read from git's own porcelain
# rather than parsing paths, so a worktree in any location is covered.
worktree_branches="$(git worktree list --porcelain 2>/dev/null | sed -n 's|^branch refs/heads/||p' | sort -u)"

is_kept() {
  local b="$1" re
  printf '%s' "$b" | grep -qE "$PROTECTED" && return 0
  printf '%s\n' "$worktree_branches" | grep -qxF "$b" && return 0
  for re in ${KEEP_EXTRA[@]+"${KEEP_EXTRA[@]}"}; do
    printf '%s' "$b" | grep -qE "$re" && return 0
  done
  return 1
}

cand_auto=(); cand_named=(); skipped_wt=0; skipped_prot=0
while IFS= read -r b; do
  [ -n "$b" ] || continue
  if printf '%s' "$b" | grep -qE "$PROTECTED"; then skipped_prot=$((skipped_prot+1)); continue; fi
  if printf '%s\n' "$worktree_branches" | grep -qxF "$b"; then skipped_wt=$((skipped_wt+1)); continue; fi
  is_kept "$b" && continue
  if printf '%s' "$b" | grep -qE "$AUTO_RE"; then cand_auto+=("$b"); else cand_named+=("$b"); fi
done < <(git branch --merged "$TRUNK" --format='%(refname:short)')

targets=( ${cand_auto[@]+"${cand_auto[@]}"} )
[ "$INCLUDE_NAMED" = "1" ] && targets+=( ${cand_named[@]+"${cand_named[@]}"} )

total_refs=$(git for-each-ref refs/heads | wc -l | tr -d ' ')
printf 'branch-reaper: trunk=%s  local branches=%s\n' "$TRUNK" "$total_refs"
printf '  merged & machine-minted (in scope):      %s\n' "${#cand_auto[@]}"
printf '  merged & human-named   (%s): %s\n' "$([ "$INCLUDE_NAMED" = 1 ] && echo 'IN scope  ' || echo 'out of scope')" "${#cand_named[@]}"
printf '  skipped, has a worktree:                 %s\n' "$skipped_wt"
printf '  skipped, protected:                      %s\n' "$skipped_prot"
printf '  NOT merged (untouched, holds work):      %s\n' "$(( total_refs - ${#cand_auto[@]} - ${#cand_named[@]} - skipped_wt - skipped_prot ))"
printf '  => would delete:                         %s\n' "${#targets[@]}"

[ "${#targets[@]}" -eq 0 ] && { printf 'branch-reaper: nothing to do.\n'; exit 0; }

if [ "$CONFIRM" != "1" ]; then
  printf '\nDRY RUN — nothing deleted. Sample of the target set:\n'
  printf '  %s\n' "${targets[@]:0:10}"
  [ "${#targets[@]}" -gt 10 ] && printf '  … and %s more\n' "$(( ${#targets[@]} - 10 ))"
  printf '\nRe-run with --confirm to delete. A restore manifest is written first.\n'
  exit 0
fi

# ── write the restore manifest BEFORE deleting anything ─────────────────────
mkdir -p "$MANIFEST_DIR" || die "cannot create $MANIFEST_DIR"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
MANIFEST="$MANIFEST_DIR/reaped-$STAMP.tsv"
: > "$MANIFEST"
for b in "${targets[@]}"; do
  sha="$(git rev-parse --verify --quiet "refs/heads/$b")" || continue
  printf '%s\t%s\n' "$b" "$sha" >> "$MANIFEST"
done
written=$(wc -l < "$MANIFEST" | tr -d ' ')
[ "$written" -eq "${#targets[@]}" ] || die "manifest incomplete ($written/${#targets[@]}) — refusing to delete" 3
printf 'branch-reaper: manifest %s (%s refs)\n' "$MANIFEST" "$written"

deleted=0; failed=0
for b in "${targets[@]}"; do
  if git branch -d "$b" >/dev/null 2>&1; then deleted=$((deleted+1))
  else failed=$((failed+1)); printf '  ! could not delete: %s\n' "$b" >&2; fi
done
printf 'branch-reaper: deleted %s, failed %s, remaining local branches %s\n' \
  "$deleted" "$failed" "$(git for-each-ref refs/heads | wc -l | tr -d ' ')"
printf 'branch-reaper: undo with  bash %s --restore %s\n' "$0" "$MANIFEST"
exit 0
