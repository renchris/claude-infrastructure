#!/usr/bin/env bash
# stranded-sweep.sh — detect commits STRANDED on local branches: committed here but
# whose content never reached the trunk (dropped by a concurrent rebase-land — the
# 2026-07-11 incident). A plain "N unlanded" count read 0 and missed it; this checks
# content, not just SHA reachability.
#
#   scripts/stranded-sweep.sh [--mine <session-id>] [trunk]
#
# STRANDED := a commit on a local branch that is NOT reachable by SHA from the trunk AND
# ALL of whose changed paths are ABSENT from the trunk tree (the incident class: new files
# that never landed). A path that exists on trunk with different content is NOT flagged
# (legitimately-evolved file → avoids false alarms).
#
# `git cherry` enumerates the candidates and NOTHING else — its +/- classification is not
# trusted, because it was measured wrong in both directions on this repo's own refs. The
# per-path content check is the only verdict. If cherry cannot read a branch at all, that
# branch is a NON-VERDICT, named on stderr and never counted as clean.
#
# Two modes:
#   * DEFAULT (review-not-fail) — a bounded COUNT: how many commits, on how many of how
#     many branches, naming at most 3. exit 1 = REVIEW (operator ruling: recover only YOUR
#     own dropped work, NEVER cherry-pick a peer session's unlanded WIP onto the trunk).
#     On a multi-session box exit 1 is the normal state, so it is a prompt, not a verdict:
#     it fired on 955 of 989 lands, and what it used to print was a per-commit wall with a
#     cherry-pick recipe for peer WIP that its own next line forbade cherry-picking. The
#     detail and the recipe now belong to `--mine`, whose owner can act on them.
#   * --mine <session-id> (decidable) — reports ONLY stranded commits carrying your
#     session's ownership trailer, silent on peers. Exit 1 = YOUR content was dropped
#     (a real own-drop to recover); exit 0 = no own-session drop. This turns the REVIEW
#     into a machine-decidable pass/fail (T-P9-4 — the auto-land crux).
#
# OWNERSHIP: `--mine <sid>` attributes a drop from the LAND ANCHORS ship-land already
# writes — a `refs/land/failed/*-<sid>-*` ref (a land that failed) or a land.log row's
# `head` for that sid (a land that succeeded). A commit is ours iff an anchor reaches it.
# The `Session-Id:`/`Land-Session:` commit trailer this script was originally built on is
# written by NOTHING (0 of the last 500 trunk commits carry one); it is kept only as a
# last arm. See the block above mine_match for the measurement and the failure it caused.
#
# Exit 1 if any (own, under --mine) stranded found (lists all first), OR if any branch was
# UNREADABLE (a non-verdict is not a pass); else exit 0. Exit 1 is advisory in every mode:
# ship-land.sh renders it as `sweep=review` and never fails a land on it.
#
# bash 3.2-safe. `pipefail` load-bearing; NO `set -e`.
set -uo pipefail

MINE=""
TRUNK=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --mine) MINE="${2:-}"; shift 2 ;;
    --mine=*) MINE="${1#--mine=}"; shift ;;
    --) shift ;;
    -*) echo "✗ stranded-sweep: unknown option '$1'. Usage: stranded-sweep.sh [--mine <sid>] [trunk]" >&2; exit 64 ;;
    *) TRUNK="$1"; shift ;;
  esac
done
if [[ -z "${TRUNK}" ]]; then
  TRUNK="$(git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')"
  [[ -z "${TRUNK}" ]] && TRUNK="main"
fi

# Best-effort refresh — never fail if offline.
git fetch -q origin "${TRUNK}" 2>/dev/null || true

REMOTE_TRUNK="origin/${TRUNK}"

# --- OWNERSHIP: which stranded commits are MINE -------------------------------------
# Keyed on identity that EXISTS. `--mine` used to key solely on a `Session-Id:` /
# `Land-Session:` git trailer that NOTHING in this repo writes — measured 2026-08-12, 0 of
# the last 500 commits on origin/main carry either, and ship-land.sh:121 is a comment
# describing a convention that was never built. So `--mine` could only ever report 0: the
# sweep's one damping mechanism was dead on arrival. The trailer survives as the LAST arm
# (one git call, and it starts working the day something writes it), but nothing depends
# on it now.
#
# The two anchors ship-land really does write both name a COMMIT this session tried to put
# on the trunk. A stranded sha is ours iff an anchor REACHES it:
#
#   1. refs/land/failed/<utcstamp>-<sid>-<branch>  (ship-land.sh:806-812) — the pinned head
#      of a land that FAILED. 93 such refs exist in this repo today.
#   2. land.log rows carrying our `sid`, via their `head` field (ship-land.sh attest_land)
#      — the head of a land that SUCCEEDED. This arm is the one that covers the incident
#      the whole script exists for: on 2026-07-11 the land succeeded and a SIBLING's
#      rebase dropped dfacccd out of the trunk afterwards. No failed-land ref exists in
#      that story, so anchor 1 alone would be blind to exactly the case being detected.
#
# Over-attribution direction: a commit a peer authored but that sits in the history we
# landed reads as ours. That is the safe direction — it shows the owner one extra commit
# to REVIEW, where the alternative (the trailer) showed them nothing, ever.
MINE_ANCHORS=""
if [[ -n "${MINE}" ]]; then
  # ship-land builds the ref name through `tr -c 'A-Za-z0-9._-' '-'` over the WHOLE name,
  # so the sid must be sanitised identically or a legal sid could not match its own ref.
  mine_key="$(printf '%s' "${MINE}" | tr -c 'A-Za-z0-9._-' '-')"
  mine_raw="$(git for-each-ref --format='%(objectname)' "refs/land/failed/*-${mine_key}-*" 2>/dev/null)"
  land_log="${LAND_LOG:-${HOME}/.claude/land.log}"
  if [[ -r "${land_log}" ]]; then
    # Bounded read: a drop older than 5000 land rows is not the "recover it now" case.
    mine_raw="${mine_raw}
$(tail -n 5000 "${land_log}" 2>/dev/null | grep -F "\"sid\":\"${MINE}\"" \
    | sed -n 's/.*"head":"\([0-9a-f][0-9a-f]*\)".*/\1/p')"
  fi
  # Keep only anchors this repo actually holds — an unknown sha would cost one fork per
  # candidate commit and answer nothing (land.log is global; its rows span repos).
  while IFS= read -r anchor; do
    [[ -z "${anchor}" ]] && continue
    git cat-file -e "${anchor}^{commit}" 2>/dev/null && MINE_ANCHORS="${MINE_ANCHORS}${anchor}
"
  done <<EOF
$(printf '%s' "${mine_raw}" | sort -u)
EOF
fi

mine_match() {  # $1=sha — an own-session land anchor reaches it, else the legacy trailer
  [[ -z "${MINE}" ]] && return 1
  local anchor
  while IFS= read -r anchor; do
    [[ -z "${anchor}" ]] && continue
    git merge-base --is-ancestor "$1" "${anchor}" 2>/dev/null && return 0
  done <<EOF
${MINE_ANCHORS}
EOF
  # NOT `grep -q`. This pipeline is the FUNCTION-FINAL statement, so its rc is what the caller's
  # `! mine_match "${sha}"` reads, and `pipefail` is declared load-bearing at the top of this file.
  # An early-exiting grep kills `git show` with SIGPIPE and the caller is handed 141 — measured
  # 20/20 at 137,819 B on bash 3.2.57 — which is not zero and therefore means NOT MINE. A MATCH
  # would read as a peer's commit and be SILENTLY SKIPPED, which in `--mine` is the one outcome
  # this mode exists to prevent: an own-session drop that goes unreported. Reading to the end costs
  # nothing here (nothing writes these trailers today) and cannot invert.
  # tests/stranded-sweep.bats pins it behaviourally, past the measured floor.
  git show -s --format='%(trailers:key=Session-Id,valueonly,separator=%x0A)%x0A%(trailers:key=Land-Session,valueonly,separator=%x0A)' "$1" 2>/dev/null \
    | grep -xF "${MINE}" >/dev/null
}

NL='
'
# The trunk's file paths, read ONCE. Membership is then a fork-free shell match instead of
# a `git ls-tree` per candidate commit. This is load-bearing, not tidying: the script walks
# 708 refs on the land path, and feeding cherry's `-` commits to the content check (the
# oracle fix above) roughly triples the candidates — measured 72s → 154s with a fork per
# candidate, back under the original with this.
TRUNK_PATHS="${NL}$(git ls-tree -r --name-only "${REMOTE_TRUNK}" 2>/dev/null)${NL}"

found=0
branch_count=0
unreadable=0
unreadable_names=""
hit_branches=0
hit_list=""

# Verdict for ONE candidate commit. Reads sha/paths/branch, updates found/branch_hits.
# STRANDED := every path this commit touched is absent from the trunk tree. A path that
# exists on trunk with different content is NOT the incident class (legitimately-evolved
# file → no false alarm).
judge_commit() {
  [[ -z "${sha}" || -z "${paths}" ]] && return 0   # no paths ⇒ merge commit ⇒ nothing to judge
  local p
  while IFS= read -r p; do
    [[ -z "${p}" ]] && continue
    case "${TRUNK_PATHS}" in
      *"${NL}${p}${NL}"*) return 0 ;;              # present on trunk → not the incident class
    esac
  done <<EOF
${paths}
EOF
  # ALL absent. Only now confirm it is not already on the trunk by SHA. cherry's default
  # limit IS the merge base, so a listed commit cannot be an ancestor of the trunk (it
  # would have been the merge base); the check stays because it is the load-bearing
  # invariant, and at one fork per would-be REPORT it is now free.
  git merge-base --is-ancestor "${sha}" "${REMOTE_TRUNK}" 2>/dev/null && return 0
  # --mine: skip a peer session's drop (silent); report only own-session drops.
  [[ -n "${MINE}" ]] && ! mine_match "${sha}" && return 0
  found=$(( found + 1 ))
  branch_hits=$(( branch_hits + 1 ))
  # DAMPING (backlog fd517a5863cc). The per-commit wall and the recovery recipe are for
  # the OWNER only. Un-`--mine`, this fired on 955 of 989 lands — an alarm that fires 97%
  # of the time carries essentially no bits — and what it printed was a cherry-pick recipe
  # for peer WIP that its own next line tells the reader never to cherry-pick. Default
  # mode reports the COUNT and points at the one question actionable to the caller.
  [[ -z "${MINE}" ]] && return 0
  local short
  short="$(git rev-parse --short "${sha}")"
  echo "✗ STRANDED ${short} on branch '${branch}' — paths absent from ${REMOTE_TRUNK}:"
  printf '%s' "${paths}" | while IFS= read -r p; do
    [[ -n "${p}" ]] && echo "    ${p}"
  done
  echo "  recovery:"
  echo "    git branch backup/stranded-${short} ${sha}"
  echo "    git checkout ${TRUNK} && git fetch origin ${TRUNK} && git reset --hard ${REMOTE_TRUNK}"
  echo "    git cherry-pick ${sha}"
  echo "    # then gate (shellcheck + bats) and land via scripts/land-lock.sh"
  echo ""
  return 0
}
for branch in $(git for-each-ref --format='%(refname:short)' refs/heads/); do
  [[ "${branch}" = "${TRUNK}" ]] && continue
  branch_count=$(( branch_count + 1 ))

  # `git cherry` is the cheap PRE-FILTER — it enumerates the branch's commits that are not
  # on the trunk. It is NOT the verdict, and its rc is now CHECKED. Two failures paid for:
  #
  #   * WRONG IN BOTH DIRECTIONS on this repo's own refs (W4 measurement): it cleared 3 refs
  #     that still held residue, and convicted 0a131da73 whose every path was blob-identical
  #     to the trunk. So BOTH markers are fed to the per-path content check below — `+` (not
  #     patch-equivalent) and `-` (patch-equivalent, i.e. cherry's own "already landed" claim)
  #     — and that content check alone decides. Cost is unchanged in practice: the check exits
  #     at the FIRST path found on trunk, which is every `-` commit's first path.
  #   * INSTRUMENT FAILURE READ AS A CLEAN SUBJECT. This used to be `done <<EOF
  #     $(git cherry ... 2>/dev/null) EOF` — rc discarded, stderr swallowed. An unborn ref, a
  #     ref pointing at a missing object, any corruption ⇒ cherry exits 128 with EMPTY stdout,
  #     the loop reads zero lines, and the branch was silently certified CLEAN. A failure of
  #     the instrument is now a NON-VERDICT that names the branch (reported below) and is
  #     never counted as clean.
  cherry_out="$(git cherry "${REMOTE_TRUNK}" "${branch}" 2>&1)"
  cherry_rc=$?
  if [[ "${cherry_rc}" -ne 0 ]]; then
    unreadable=$(( unreadable + 1 ))
    unreadable_names="${unreadable_names}    ${branch} — git cherry exit ${cherry_rc}: $(printf '%s' "${cherry_out}" | tr '\n' ' ')
"
    continue
  fi

  # Candidate shas — BOTH cherry markers, since its classification is not the verdict.
  cands=""
  while IFS= read -r line; do
    case "${line}" in
      '+ '*) cands="${cands}${line#+ }${NL}" ;;
      '- '*) cands="${cands}${line#- }${NL}" ;;
    esac
  done <<EOF
${cherry_out}
EOF
  [[ -z "${cands}" ]] && continue

  # ONE diff-tree for every candidate on this branch — `--stdin` reads commit ids and
  # emits `<sha>` followed by that commit's paths. Output ordering is the input's.
  branch_hits=0
  sha=""
  paths=""
  while IFS= read -r line; do
    is_head=0
    if [[ "${#line}" -eq 40 ]]; then
      # A 40-char line is a commit header only if it is one of the shas WE fed — a path
      # could in principle be 40 hex chars, and guessing would silently drop its commit.
      case "${cands}" in *"${line}${NL}"*) is_head=1 ;; esac
    fi
    if [[ "${is_head}" -eq 1 ]]; then
      judge_commit
      sha="${line}"
      paths=""
      continue
    fi
    [[ -n "${line}" ]] && paths="${paths}${line}${NL}"
  done <<EOF
$(printf '%s' "${cands}" | git diff-tree --stdin --name-only -r 2>/dev/null)
EOF
  judge_commit

  if [[ "${branch_hits}" -gt 0 ]]; then
    hit_branches=$(( hit_branches + 1 ))
    # Bounded: the un-`--mine` summary names at most 3 branches and counts the rest. On
    # this repo the un-damped verdict was 69 commits across 675 branches.
    if [[ "${hit_branches}" -le 3 ]]; then
      hit_list="${hit_list}${hit_list:+, }${branch} (${branch_hits})"
    fi
  fi
done

readable=$(( branch_count - unreadable ))
if [[ "${unreadable}" -gt 0 ]]; then
  echo "? stranded-sweep: NO VERDICT for ${unreadable} branch(es) — the instrument failed, so these are NOT certified clean:" >&2
  printf '%s' "${unreadable_names}" >&2
fi

if [[ "${found}" -gt 0 ]]; then
  if [[ -n "${MINE}" ]]; then
    echo "✗ stranded-sweep --mine: ${found} commit(s) from YOUR session (${MINE}) dropped — content not on ${REMOTE_TRUNK}. Recover them via the recipes above; this is your own land drop, not peer WIP." >&2
  else
    more=""
    [[ "${hit_branches}" -gt 3 ]] && more=" (+$(( hit_branches - 3 )) more)"
    echo "✗ stranded-sweep: ${found} commit(s) hold content not on ${REMOTE_TRUNK}, on ${hit_branches} of ${readable} local branch(es): ${hit_list}${more}" >&2
    echo "  Peer WIP is expected on a multi-session box and is NOT yours to recover — never cherry-pick it onto ${TRUNK}. That is why no recipe is printed here." >&2
    echo "  The one actionable question is whether YOUR OWN work was dropped: scripts/stranded-sweep.sh --mine \"\$CLAUDE_CODE_SESSION_ID\" ${TRUNK}" >&2
  fi
  exit 1
fi

# An instrument failure is NOT a clean verdict. Exit 1 here is the same REVIEW rung the
# default mode already uses (ship-land treats any non-zero as advisory and never fails a
# land on it), deliberately NOT a new exit code — a new non-verdict code only moves the
# failure onto every consumer testing `-eq 0` (memory: new-nonverdict-state-strands-its-consumers).
# The TEXT is what distinguishes it: no "✓", and it never claims a drop either.
if [[ "${unreadable}" -gt 0 ]]; then
  if [[ -n "${MINE}" ]]; then
    echo "? stranded-sweep --mine: NO VERDICT — 0 own-session (${MINE}) drops among ${readable} readable branch(es), but ${unreadable} branch(es) could not be read (above)." >&2
  else
    echo "? stranded-sweep: NO VERDICT — 0 stranded among ${readable} readable branch(es), but ${unreadable} branch(es) could not be read (above)." >&2
  fi
  exit 1
fi

if [[ -n "${MINE}" ]]; then
  echo "✓ stranded-sweep --mine: 0 own-session (${MINE}) drops across ${readable} branch(es)"
else
  echo "✓ stranded-sweep: 0 stranded across ${readable} branch(es)"
fi
exit 0
