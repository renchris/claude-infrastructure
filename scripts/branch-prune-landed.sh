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
# ── THE DELETION JOURNAL, WHICH IS NEVER TRUNCATED (backlog 529aebcb4992) ───────────────────────
# The manifest is a per-RUN record and is rewritten from its header every run, so a second run on
# the same day erased the first run's DELETED rows: all 26 manifests on disk held 0 DELETED rows
# while this script had deleted ~92 fire refs. `cloud-lane-liveness.sh` needs the opposite — the
# set of every branch ever deleted — because its population control reads a missing fire ref as
# a deletion it cannot account for, and so read UNKNOWN forever. Every successful delete is
# therefore APPENDED to a journal (`--journal`, CC_PRUNE_JOURNAL, default
# $CC_CLOUD_STATE/branch-prune-deleted.tsv), one `<deleted_at_utc>\t<branch>\t<sha>` line each.
# FAIL-OPEN: a journal that cannot be written is reported on stderr and never fails the prune.
# `--backfill` reconstructs the deletions made before the journal existed (see backfill() below).
#
# Usage:  scripts/branch-prune-landed.sh [--dry-run] [--trunk <branch>] [--manifest <path>]
#                                        [--journal <path>] [--backfill]
set -uo pipefail

TRUNK="${CC_PRUNE_TRUNK:-main}"
MIN_AGE_H="${CC_PRUNE_MIN_AGE_H:-6}"
DRY=0
MANIFEST=""
STATE_D="${CC_CLOUD_STATE:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/autonomy/cloud}"   # autonomy-sweep's own expression
JOURNAL="${CC_PRUNE_JOURNAL:-$STATE_D/branch-prune-deleted.tsv}"
BACKFILL=0

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)  DRY=1; shift ;;
    --trunk)    TRUNK="${2:?--trunk needs a branch}"; shift 2 ;;
    --manifest) MANIFEST="${2:?--manifest needs a path}"; shift 2 ;;
    --journal)  JOURNAL="${2:?--journal needs a path}"; shift 2 ;;
    --backfill) BACKFILL=1; shift ;;
    -h|--help)  sed -n '2,33p' "$0"; exit 0 ;;
    *) echo "branch-prune-landed: unknown arg $1" >&2; exit 2 ;;
  esac
done

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "branch-prune-landed: not in a git repo" >&2; exit 2; }
cd "$repo_root" || exit 2

# journal_open — create the journal with its header when absent. Appends even the header (`>>`), so
# two racing runs can never truncate each other's rows: the file only ever grows.
journal_open() {
  [ -e "$JOURNAL" ] && return 0
  mkdir -p "$(dirname "$JOURNAL")" && printf '# deleted_at_utc\tbranch\tsha\tsource\n' >> "$JOURNAL"
}

# journal_deleted <branch>... — one line per branch this run just deleted. The sha comes from the
# manifest, which is written before any push; the remote-tracking ref is already gone by now.
journal_deleted() {
  local at; at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  if ! { journal_open && printf '%s\n' "$@" | awk -F'\t' -v OFS='\t' -v at="$at" -v m="$MANIFEST" '
      BEGIN { while ((getline l < m) > 0) { split(l, f, "\t"); S[f[1]] = f[2] } }
      NF { print at, $0, S[$0] }' >> "$JOURNAL"; } 2>/dev/null; then
    echo "  WARNING: deletion journal $JOURNAL NOT written for $# branch(es) — cloud-lane-liveness" >&2
    echo "           will read their absence as an unaccounted deletion (UNKNOWN)" >&2
  fi
  return 0
}

# ── --backfill: the deletions made before the journal existed ──────────────────────────────────
# One-shot and idempotent. A branch is journaled as `backfill` only when BOTH hold:
#   · on-disk evidence that it EXISTED on the remote — a manifest PRUNE/DELETED row (this script
#     saw it), or a cloud `.decl` naming it whose `.seen` carries `sha=` (the watcher saw it pushed).
#     A `.decl` alone is NOT enough: it proves a session was dispatched, never that it pushed.
#   · it is absent from `git ls-remote --heads origin` right now.
# A failed or trunk-less ls-remote aborts with nothing written: "cannot look" is not "absent", and
# reading it as absent would journal every live branch as deleted. Column 1 of a backfill row is
# the backfill instant — the deletion happened ON OR BEFORE it — and column 4 says `backfill`.
backfill() {
  local heads names cand at before after
  heads="$(git ls-remote --heads origin 2>/dev/null)" || {
    echo "backfill: ls-remote failed — cannot look is not absent; nothing journaled" >&2; return 1; }
  names="$(printf '%s\n' "$heads" | sed -E 's#^[0-9a-f]+[[:space:]]+refs/heads/##')"
  printf '%s\n' "$names" | grep -xF "$TRUNK" >/dev/null || {
    echo "backfill: the remote listing lacks the trunk '$TRUNK' — not a trustworthy census; nothing journaled" >&2; return 1; }

  cand="$(mktemp)"
  awk -F'\t' -v OFS='\t' '!/^#/ && ($6=="PRUNE" || $6=="DELETED") && $1!="" { sub(/^origin\//, "", $1); print $1, $2 }' \
    "$STATE_D"/branch-prune-manifest-*.tsv 2>/dev/null >> "$cand"
  echo "backfill: $(wc -l < "$cand" | tr -d ' ') manifest PRUNE/DELETED row(s) in $STATE_D"
  local d b s sha n_decl=0
  for d in "$STATE_D"/*.decl; do
    [ -f "$d" ] || continue
    b="$(sed -n 's/^branch=//p' "$d" | head -1)"; s="${d%.decl}.seen"
    [ -n "$b" ] && [ -f "$s" ] || continue
    sha="$(sed -n 's/^sha=//p' "$s" | head -1)"
    [ -n "$sha" ] || continue
    printf '%s\t%s\n' "$b" "$sha" >> "$cand"; n_decl=$((n_decl+1))
  done
  echo "backfill: $n_decl .decl branch(es) with a .seen sha"

  journal_open || { echo "backfill: cannot create $JOURNAL" >&2; rm -f "$cand"; return 1; }
  before=$(grep -vc '^#' "$JOURNAL" 2>/dev/null); before="${before:-0}"
  at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  # First evidence row per branch wins; drop anything still on the remote or already journaled.
  printf '%s\n' "$names" > "$cand.live"
  awk -F'\t' -v OFS='\t' -v at="$at" -v j="$JOURNAL" -v live="$cand.live" '
    BEGIN { while ((getline l < live) > 0) L[l] = 1
            while ((getline l < j) > 0) { if (l ~ /^#/) continue; split(l, f, "\t"); J[f[2]] = 1 } }
    NF && !($1 in L) && !($1 in J) && !($1 in seen) { seen[$1] = 1; print at, $1, $2, "backfill" }
  ' "$cand" >> "$JOURNAL" || { echo "backfill: append to $JOURNAL failed" >&2; rm -f "$cand" "$cand.live"; return 1; }
  rm -f "$cand" "$cand.live"
  after=$(grep -vc '^#' "$JOURNAL" 2>/dev/null); after="${after:-0}"
  echo "backfill: appended $((after - before)) deletion(s) to $JOURNAL ($after journaled in total)"
}

if [ "$BACKFILL" = 1 ]; then backfill; exit $?; fi

[ -n "$MANIFEST" ] || MANIFEST="$repo_root/docs/research/branch-prune-manifest-$(date -u +%Y-%m-%d).tsv"

echo "branch-prune-landed: trunk=origin/$TRUNK  min-age=${MIN_AGE_H}h  dry-run=$DRY"
git fetch origin --prune --quiet || { echo "fetch failed" >&2; exit 1; }

# An epoch → UTC instant, on BOTH date implementations. BSD `date -r <epoch>` reads its argument as
# an epoch; GNU `date -r <file>` reads it as a FILENAME — so under GNU this printed
# `date: <epoch>: No such file or directory` once per branch and left last_commit_utc EMPTY. That
# column is part of the restore record (it is how a reader judges whether a deleted branch was live
# work), and this script runs on Linux in every cloud session. Same fallback idiom the suites use.
iso_utc() {
  date -u -r "$1" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -d "@$1" '+%Y-%m-%dT%H:%M:%SZ'
}

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
    "$b" "$sha" "$s" "$d" "$(iso_utc "$ts")" "$verdict" >> "$MANIFEST"
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
    journal_deleted "${batch[@]}"   # per batch, so a run killed mid-loop still journals what it did
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
