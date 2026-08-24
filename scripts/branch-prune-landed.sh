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
#
# 🚨 The manifest is written BEFORE any deletion (so a crash mid-run still leaves a restore source),
# which means its verdict column is an INTENT — `PRUNE` — not an OUTCOME. Left there, a reader
# restoring from it cannot tell a branch we deleted from one we merely planned to, and a FAILED
# batch would sit in the record indistinguishable from a successful one. So the outcome is folded
# back in below, per branch: PRUNE -> DELETED or DELETE-FAILED. (Repo memory:
# claimed-outcome-vs-checked-outcome — a claim under a damping marker is not a checked result.)
# ── PRESERVE THE EVIDENCE THIS DELETION DESTROYS (backlog f85fce7c26f5) ────────────────────────
# `bin/cc-cloud` answers "did this off-box session finish?" by asking whether its declared paths are
# content-present on the trunk — and it derives that path set from the BRANCH'S OWN COMMITS, which
# this loop is about to make unreachable. A declaration whose `paths=` is still empty at deletion
# time can therefore never assert landedness again, and its session reads UNKNOWN forever.
# So: fill first, delete second. The ordering is the whole point — one line later is too late.
#
# FAIL-OPEN, DELIBERATELY. Preservation is a courtesy to a different tool; a missing cc-cloud, an
# undeclared branch, or a delete-only range must not stop a prune that is otherwise correct. Every
# outcome is reported, so a silent skip is not one of them. `--branch` is rc 0 when nothing declares
# the branch, which is the common case here: most pruned branches were never cloud sessions.
#
# HONEST LIMIT, measured rather than assumed: this preserves the REBASED land and NOT the fast-
# forwarded one. `fill-paths` bounds its range at the merge-base with the trunk, and for a branch
# that is a true ANCESTOR of the trunk that range is empty — it refuses (naming that cause exactly)
# rather than writing an empty set, and the session stays UNKNOWN. That is the rare arm here: this
# file's own header records `--merged` finding 1 of 97 against `git cherry`'s 56, because ship-land
# rebases. Verified both ways on a fixture: rebased land -> `paths=docs/vm.md`, session reads
# LANDED after the delete; ancestor land -> refusal, session reads UNKNOWN. UNKNOWN is the correct
# verdict for it — it emits no row and states that landedness is not assertable, which is the fact.
if command -v cc-cloud >/dev/null 2>&1; then
  echo "preserving cc-cloud path sets for ${#safe[@]} branch(es) before deleting them..."
  for b in "${safe[@]}"; do
    cc-cloud fill-paths --branch "$b" 2>&1 | sed 's/^/    /' || true
  done
else
  echo "note: cc-cloud not on PATH — path sets NOT preserved; any cloud session on these branches" >&2
  echo "      will read UNKNOWN rather than LANDED (bin/cc-cloud, ORDERING note)." >&2
fi

rc=0
i=0
deleted_list="$(mktemp)"; failed_list="$(mktemp)"
trap 'rm -f "$deleted_list" "$failed_list"' EXIT
while [ "$i" -lt "${#safe[@]}" ]; do
  batch=("${safe[@]:$i:20}")
  if git push origin --delete "${batch[@]}" >/dev/null 2>&1; then
    echo "  deleted ${#batch[@]}"
    printf '%s\n' "${batch[@]}" >> "$deleted_list"
  else
    echo "  BATCH FAILED (${#batch[@]} branches) — see manifest to retry" >&2; rc=1
    printf '%s\n' "${batch[@]}" >> "$failed_list"
  fi
  i=$((i+20))
done

# Fold the outcome back into the manifest, so the record states what HAPPENED.
tmp_manifest="$(mktemp)"
awk -F'\t' -v OFS='\t' -v del="$deleted_list" -v fail="$failed_list" '
  BEGIN { while ((getline l < del)  > 0) D[l]=1
          while ((getline l < fail) > 0) F[l]=1 }
  /^#/ { print; next }
  $6=="PRUNE" && ($1 in D) { $6="DELETED";       print; next }
  $6=="PRUNE" && ($1 in F) { $6="DELETE-FAILED"; print; next }
  { print }
' "$MANIFEST" > "$tmp_manifest" && mv "$tmp_manifest" "$MANIFEST"
echo "  manifest verdicts folded to outcome (DELETED / DELETE-FAILED)"

git fetch origin --prune --quiet
echo "remote branches remaining: $(git branch -r | grep -vc HEAD)"
[ "$rc" -eq 0 ] && echo "✓ branch-prune-landed: done; every deletion is restorable from $MANIFEST"
exit "$rc"
