#!/usr/bin/env bash
# branch-prune-landed.sh — delete ONLY remote branches whose every commit is already on the trunk
# by PATCH EQUIVALENCE, never by ancestry.
#
# ── WHY ANCESTRY IS THE WRONG TEST (measured 2026-08-19) ────────────────────────────────────────
# `git branch -r --merged origin/main` reported 1 merged branch out of 97. `git cherry` — which
# compares PATCH IDs rather than shas — reported 56. The gap is our own landing pipeline: ship-land
# rebases before it pushes, which rewrites every object, so a branch whose bytes are verbatim on
# main still reads "not merged" and still shows "Ahead 1" in the GitHub UI. Pruning on ancestry
# would therefore have kept 55 branches that hold nothing, and — far worse — a reader trusting the
# same signal concludes that landed work was lost. (Repo memory: cited-sha-may-not-survive-the-land.)
#
# ── WHAT THIS REFUSES TO DELETE ────────────────────────────────────────────────────────────────
#   · any branch with >=1 commit NOT patch-equivalent on the trunk  (that is real stranded work)
#   · any branch whose tip is younger than CC_PRUNE_MIN_AGE_H hours (default 6) — a live cloud
#     session may still be pushing to it
#   · the trunk itself
# Everything it does delete is recorded first, with its sha, so any deletion is reversible:
#   git push origin <sha>:refs/heads/<branch>
#
# Usage:  scripts/branch-prune-landed.sh [--dry-run] [--trunk <branch>] [--manifest <path>]
set -uo pipefail

TRUNK="${CC_PRUNE_TRUNK:-main}"
MIN_AGE_H="${CC_PRUNE_MIN_AGE_H:-6}"
DRY=0
MANIFEST=""

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)  DRY=1; shift ;;
    --trunk)    TRUNK="${2:?--trunk needs a branch}"; shift 2 ;;
    --manifest) MANIFEST="${2:?--manifest needs a path}"; shift 2 ;;
    -h|--help)  sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "branch-prune-landed: unknown arg $1" >&2; exit 2 ;;
  esac
done

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "branch-prune-landed: not in a git repo" >&2; exit 2; }
cd "$repo_root" || exit 2

[ -n "$MANIFEST" ] || MANIFEST="$repo_root/docs/research/branch-prune-manifest-$(date -u +%Y-%m-%d).tsv"

echo "branch-prune-landed: trunk=origin/$TRUNK  min-age=${MIN_AGE_H}h  dry-run=$DRY"
git fetch origin --prune --quiet || { echo "fetch failed" >&2; exit 1; }

now=$(date +%s)
safe=(); held_strand=0; held_young=0; stranded_commits=0

mkdir -p "$(dirname "$MANIFEST")"
printf '# branch\tsha\tstranded\tlanded\tlast_commit_utc\tverdict\n' > "$MANIFEST"

while read -r ref; do
  b="${ref#origin/}"
  [ "$b" = "$TRUNK" ] && continue
  [ "$b" = "HEAD" ] && continue

  cherry="$(git cherry "origin/$TRUNK" "$ref" 2>/dev/null)" || continue
  s=$(printf '%s\n' "$cherry" | grep -c '^+')
  d=$(printf '%s\n' "$cherry" | grep -c '^-')
  sha="$(git rev-parse "$ref" 2>/dev/null)" || continue
  ts="$(git log -1 --format=%ct "$ref" 2>/dev/null)" || continue
  age_h=$(( (now - ts) / 3600 ))

  if [ "$s" -gt 0 ]; then
    verdict="HOLD-stranded"; held_strand=$((held_strand+1)); stranded_commits=$((stranded_commits+s))
  elif [ "$age_h" -lt "$MIN_AGE_H" ]; then
    verdict="HOLD-young"; held_young=$((held_young+1))
  else
    verdict="PRUNE"; safe+=("$b")
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$b" "$sha" "$s" "$d" "$(date -u -r "$ts" '+%Y-%m-%dT%H:%M:%SZ')" "$verdict" >> "$MANIFEST"
done < <(git branch -r --format='%(refname:short)' | grep -v '^origin/HEAD')

echo "manifest: $MANIFEST"
echo "  PRUNE          : ${#safe[@]}"
echo "  HOLD-stranded  : $held_strand branch(es) carrying $stranded_commits un-landed commit(s)"
echo "  HOLD-young     : $held_young (<${MIN_AGE_H}h old)"

if [ "${#safe[@]}" -eq 0 ]; then echo "nothing to prune."; exit 0; fi
if [ "$DRY" -eq 1 ]; then
  printf '  would delete: %s\n' "${safe[@]}"
  echo "dry-run: nothing deleted."; exit 0
fi

# Batch the deletes; a failed batch must not be reported as success.
rc=0
i=0
while [ "$i" -lt "${#safe[@]}" ]; do
  batch=("${safe[@]:$i:20}")
  if git push origin --delete "${batch[@]}" >/dev/null 2>&1; then
    echo "  deleted ${#batch[@]}"
  else
    echo "  BATCH FAILED (${#batch[@]} branches) — see manifest to retry" >&2; rc=1
  fi
  i=$((i+20))
done

git fetch origin --prune --quiet
echo "remote branches remaining: $(git branch -r | grep -vc HEAD)"
[ "$rc" -eq 0 ] && echo "✓ branch-prune-landed: done; every deletion is restorable from $MANIFEST"
exit "$rc"
