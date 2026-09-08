#!/usr/bin/env bash
# stranded-exposure.sh — the REPO-WIDE census of stranded content: how much work sits on
# branches and has never reached the trunk, deduplicated across branches by PATCH-ID, and
# stratified by the classes that decide whether a number means anything.
#
#   scripts/stranded-exposure.sh [--trunk <ref>] [--machine] [--drop-list]
#
# ── Why this exists, and why it is NOT scripts/stranded-sweep.sh ───────────────────────────
# `stranded-sweep.sh` is the per-branch DROP detector and stays the verdict of record for
# "was MY work dropped" (`--mine`). It deliberately has no cross-branch view: it counts
# commits, per branch, and two branches carrying the same patch count twice.
#
# This script answers the other question — "how much DISTINCT content is stranded repo-wide"
# — and it exists because that number was handed forward as PROSE and rotted in flight. The
# figure in backlog `35de32d78364` moved 290 → 342 inside one hour, was re-derived as 164,
# and read 1115 when this script first ran 43 days later. A number nothing can recompute is
# not a measurement; it is a rumour with a decimal point. Run this instead of quoting it.
#
# ── The four readings, and why three of them mislead ───────────────────────────────────────
#   AHEAD (D1/D2)  `git rev-list --count origin/main..<branch>`, summed.
#                  USELESS ALONE and wrong in the LARGE direction. This repo lands by
#                  REBASE, so a fully-landed branch keeps its original SHAs, none of which
#                  are reachable from trunk. Measured here: 7,496 raw ahead commits of which
#                  1,251 patch-ids were already on trunk verbatim. A branch reading
#                  "456 ahead" can be 100% landed.
#   DISTINCT (D3)  the union of those commits, deduped by SHA. Still counts one patch that
#                  lives on nine branches as nine.
#   STRANDED (D4)  distinct PATCH-IDs not present anywhere in trunk's history. The honest
#                  ceiling — but still an over-count, because a rebase that resolved a
#                  conflict, or reflowed a comment, changes the patch-id of content that
#                  DID land (memory: git-cherry-plus-is-not-absence-from-trunk).
#   DROP           the only reading that means content LOSS: a stranded commit where EVERY
#                  changed path is ABSENT from the trunk tree. This is the 2026-07-11
#                  incident class — new files that never landed. It is what stranded-sweep
#                  detects per-branch; here it is deduped repo-wide.
#
# Report all four. A single number is what let a 6.7x over-count survive 43 days.
#
# ── The stratum that decides whether the number is actionable ──────────────────────────────
# Branches are classed by name, because three classes are stranded BY DESIGN and counting
# them as exposure is the "unlinked by design" error (memory: sibling-auditors-must-share-
# the-state-model):
#   BY-DESIGN  ship/backup-* · preland-backup* · backup/* · superseded/* · park/*
#              ship-land writes these as PRE-REBASE snapshots. Their patch-ids differ from
#              the landed form BECAUSE the land rebased them. Measured: 448 of 1115 stranded
#              patch-ids existed on NO other class — i.e. 40% of the headline was the
#              pre-rebase shadow of already-landed work.
#   WORKTREE   wt-* — a live session's branch. Stranded here usually means IN FLIGHT.
#   NAMED      everything else. The only class where "stranded" may mean "abandoned".
#
# ── The ruling this script must not break ──────────────────────────────────────────────────
# It prints NO cherry-pick recipe and NO covering set. Operator ruling, recorded in
# stranded-sweep.sh's own output: "Peer WIP is expected on a multi-session box and is NOT
# yours to recover — never cherry-pick it onto main." A census is a census. Landing another
# session's branch is the drop incident this repo's CLAUDE.md forbids.
#
# ── The reading that changes the disposition ───────────────────────────────────────────────
# DROP patches per month tells you whether you are looking at a BACKLOG or a GENERATOR.
# Measured 2026-09-08: 20 (Jul) · 17 (Aug) · 16 (Sep 1-8) — i.e. the rate roughly TRIPLED
# per-day while the backlog was nominally being swept. A one-time sweep of a generator is
# bailing, not fixing. If the recent months are not declining, the actionable work is
# upstream of this script, not in it.
#
# Exit 0 always UNLESS the instrument itself failed (exit 2) — this is a CENSUS, not a gate.
# A non-zero here must never be readable as "content was lost"; that is what DROP is for.
# bash 3.2-safe. `pipefail` load-bearing; NO `set -e`.
set -uo pipefail

TRUNK_REF="origin/main"
MACHINE=0
DROP_LIST=0

while [ $# -gt 0 ]; do
  case "$1" in
    --trunk)     TRUNK_REF="${2:-}"; shift 2 ;;
    --machine)   MACHINE=1; shift ;;
    --drop-list) DROP_LIST=1; shift ;;
    -h|--help)   sed -n '2,8p' "$0"; exit 0 ;;
    *) echo "stranded-exposure: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

command -v git >/dev/null 2>&1 || { echo "stranded-exposure: git not on PATH" >&2; exit 2; }
git rev-parse --git-dir >/dev/null 2>&1 || { echo "stranded-exposure: not a git repository" >&2; exit 2; }

# A trunk we cannot resolve is an INSTRUMENT failure, never an empty census. Resolving it to
# nothing would make every branch read as fully stranded — the alarm-shaped false positive.
if ! git rev-parse --verify -q "${TRUNK_REF}^{commit}" >/dev/null; then
  echo "stranded-exposure: cannot resolve trunk ref '${TRUNK_REF}' — NO VERDICT" >&2
  exit 2
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/stranded-exposure.XXXXXX")" || exit 2
trap 'rm -rf "${WORK}" 2>/dev/null || true' EXIT

# ---- D3: the union of every commit on any ref that trunk cannot reach -----------------------
# --branches --remotes rather than --all: tags and refs/land/* are not work-carrying branches.
if ! git rev-list --no-merges --branches --remotes --not "${TRUNK_REF}" > "${WORK}/ahead.sha" 2>"${WORK}/err"; then
  echo "stranded-exposure: rev-list failed — NO VERDICT" >&2; sed 's/^/  /' "${WORK}/err" >&2; exit 2
fi
AHEAD_SHAS=$(wc -l < "${WORK}/ahead.sha" | tr -d ' ')

# ---- patch-id both sides. `git diff-tree --stdin -p` emits the commit line patch-id keys on.
git rev-list --no-merges "${TRUNK_REF}" \
  | git diff-tree --stdin -p --root 2>/dev/null | git patch-id --stable > "${WORK}/trunk.pid"
git diff-tree --stdin -p --root < "${WORK}/ahead.sha" 2>/dev/null | git patch-id --stable > "${WORK}/ahead.pid"

# A trunk that patch-ids to nothing while carrying commits means the pipeline broke, and every
# ahead patch would then read STRANDED. Fail closed rather than publish a maximal number.
if [ ! -s "${WORK}/trunk.pid" ] && [ "$(git rev-list --count --no-merges "${TRUNK_REF}")" -gt 0 ]; then
  echo "stranded-exposure: trunk patch-id index came back empty — NO VERDICT" >&2; exit 2
fi

awk '{print $1}' "${WORK}/trunk.pid" | sort -u > "${WORK}/trunk.pid.set"
awk '{print $1}' "${WORK}/ahead.pid" | sort -u > "${WORK}/ahead.pid.set"
comm -23 "${WORK}/ahead.pid.set" "${WORK}/trunk.pid.set" > "${WORK}/stranded.pid.set"

DISTINCT_PIDS=$(wc -l < "${WORK}/ahead.pid.set" | tr -d ' ')
STRANDED_PIDS=$(wc -l < "${WORK}/stranded.pid.set" | tr -d ' ')
LANDED_PIDS=$(( DISTINCT_PIDS - STRANDED_PIDS ))

# ---- class stratification ------------------------------------------------------------------
awk '{print $2"\t"$1}' "${WORK}/ahead.pid" | sort > "${WORK}/sha2pid"
: > "${WORK}/class.pid"
BRANCHES_WITH_STRANDED=0
git for-each-ref --format='%(refname:short)' refs/heads refs/remotes 2>/dev/null | while read -r b; do
  git rev-list --no-merges "$b" --not "${TRUNK_REF}" 2>/dev/null | sort > "${WORK}/.b"
  [ -s "${WORK}/.b" ] || continue
  join -t"$(printf '\t')" "${WORK}/.b" "${WORK}/sha2pid" 2>/dev/null \
    | awk -F"\t" '{print $2}' | sort -u > "${WORK}/.bp"
  comm -12 "${WORK}/.bp" "${WORK}/stranded.pid.set" > "${WORK}/.bs"
  [ -s "${WORK}/.bs" ] || continue
  case "$b" in
    ship/backup-*|origin/ship/backup-*|preland-backup*|origin/preland-backup*|\
    backup/*|origin/backup/*|superseded/*|origin/superseded/*|park/*|origin/park/*)
      cls=BY-DESIGN ;;
    wt-*|origin/wt-*) cls=WORKTREE ;;
    *) cls=NAMED ;;
  esac
  sed "s/^/${cls}\t/" "${WORK}/.bs" >> "${WORK}/class.pid"
  echo "$b" >> "${WORK}/hitbranches"
done
[ -f "${WORK}/hitbranches" ] && BRANCHES_WITH_STRANDED=$(sort -u "${WORK}/hitbranches" | wc -l | tr -d ' ')

cls_count() { awk -F"\t" -v c="$1" '$1==c{print $2}' "${WORK}/class.pid" 2>/dev/null | sort -u; }
cls_count BY-DESIGN > "${WORK}/p.design"
cls_count WORKTREE  > "${WORK}/p.worktree"
cls_count NAMED     > "${WORK}/p.named"
sort -u "${WORK}/p.worktree" "${WORK}/p.named" > "${WORK}/p.notdesign"
DESIGN_ONLY=$(comm -23 "${WORK}/p.design" "${WORK}/p.notdesign" | wc -l | tr -d ' ')
N_DESIGN=$(wc -l < "${WORK}/p.design" | tr -d ' ')
N_WORKTREE=$(wc -l < "${WORK}/p.worktree" | tr -d ' ')
N_NAMED=$(wc -l < "${WORK}/p.named" | tr -d ' ')

# ---- DROP class: every changed path absent from trunk ---------------------------------------
git ls-tree -r --name-only "${TRUNK_REF}" | sort > "${WORK}/trunk.paths"
awk 'NR==FNR{s[$1];next} ($1 in s){print $2}' "${WORK}/stranded.pid.set" "${WORK}/ahead.pid" \
  | sort -u > "${WORK}/stranded.sha"
: > "${WORK}/drop.sha"
while read -r c; do
  git diff-tree --no-commit-id --name-only -r "$c" 2>/dev/null | sort -u > "${WORK}/.paths"
  [ -s "${WORK}/.paths" ] || continue
  if [ "$(comm -12 "${WORK}/.paths" "${WORK}/trunk.paths" | wc -l | tr -d ' ')" -eq 0 ]; then
    echo "$c" >> "${WORK}/drop.sha"
  fi
done < "${WORK}/stranded.sha"
awk 'NR==FNR{d[$1];next} ($2 in d){print $1}' "${WORK}/drop.sha" "${WORK}/ahead.pid" \
  | sort -u > "${WORK}/drop.pid"
DROP_PIDS=$(wc -l < "${WORK}/drop.pid" | tr -d ' ')
DROP_SHAS=$(wc -l < "${WORK}/drop.sha" 2>/dev/null | tr -d ' ')

# ---- regeneration: DROP patches by month (backlog or generator?) -----------------------------
awk 'NR==FNR{d[$1];next} ($1 in d) && !seen[$1]++ {print $2}' "${WORK}/drop.pid" "${WORK}/ahead.pid" \
  > "${WORK}/drop.rep"
: > "${WORK}/drop.months"
while read -r c; do git log -1 --format=%cs "$c" 2>/dev/null | cut -c1-7; done < "${WORK}/drop.rep" \
  | sort | uniq -c | sort -k2 > "${WORK}/drop.months"

if [ "${MACHINE}" -eq 1 ]; then
  printf 'verdict=census trunk=%s ahead_shas=%s distinct_pids=%s landed_pids=%s stranded_pids=%s stranded_branches=%s design_pids=%s design_only_pids=%s worktree_pids=%s named_pids=%s drop_pids=%s drop_shas=%s\n' \
    "${TRUNK_REF}" "${AHEAD_SHAS}" "${DISTINCT_PIDS}" "${LANDED_PIDS}" "${STRANDED_PIDS}" \
    "${BRANCHES_WITH_STRANDED}" "${N_DESIGN}" "${DESIGN_ONLY}" "${N_WORKTREE}" "${N_NAMED}" \
    "${DROP_PIDS}" "${DROP_SHAS}"
  exit 0
fi

echo "stranded-exposure — repo-wide census against ${TRUNK_REF}"
echo
echo "  AHEAD    ${AHEAD_SHAS} commit(s) on branches trunk cannot reach  (rebase-landed work is IN here)"
echo "  DISTINCT ${DISTINCT_PIDS} patch-id(s) after cross-branch dedupe"
echo "    ├─ already on trunk verbatim: ${LANDED_PIDS}   (landed under a rewritten SHA)"
echo "    └─ STRANDED:                  ${STRANDED_PIDS}   across ${BRANCHES_WITH_STRANDED} branch(es)"
echo
echo "  STRANDED by branch class (a patch on two classes is counted in both):"
echo "    BY-DESIGN (backup/superseded/park): ${N_DESIGN}   of which ${DESIGN_ONLY} exist NOWHERE ELSE"
echo "    WORKTREE  (wt-*, usually in flight): ${N_WORKTREE}"
echo "    NAMED     (the only maybe-abandoned): ${N_NAMED}"
echo
echo "  DROP  ${DROP_PIDS} patch-id(s) / ${DROP_SHAS} commit(s) — every changed path ABSENT from trunk."
echo "        This is the only reading that means content LOSS. Per-branch verdict and"
echo "        own-session attribution: scripts/stranded-sweep.sh --mine \"\$CLAUDE_CODE_SESSION_ID\""
echo
echo "  DROP by month — is this a backlog or a generator?"
if [ -s "${WORK}/drop.months" ]; then
  sed 's/^/    /' "${WORK}/drop.months"
  echo "    (a flat or rising tail means a GENERATOR: sweeping it once cannot hold.)"
else
  echo "    none"
fi
if [ "${DROP_LIST}" -eq 1 ] && [ -s "${WORK}/drop.rep" ]; then
  echo
  echo "  DROP patches (one representative SHA per patch-id):"
  while read -r c; do
    printf '    %s  %s\n' "$(git log -1 --format='%cs %h' "$c")" "$(git log -1 --format=%s "$c" | cut -c1-64)"
  done < "${WORK}/drop.rep"
fi
echo
echo "  NO recovery recipe is printed, by ruling: peer WIP is not yours to cherry-pick onto trunk."
exit 0
