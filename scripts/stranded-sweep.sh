#!/usr/bin/env bash
# stranded-sweep.sh — detect commits STRANDED on local branches: committed here but
# whose content never reached the trunk (dropped by a concurrent rebase-land — the
# 2026-07-11 incident). A plain "N unlanded" count read 0 and missed it; this checks
# content, not just SHA reachability.
#
#   scripts/stranded-sweep.sh [--mine <session-id>] [trunk]
#
# STRANDED := a commit that is NOT patch-equivalent on trunk (git cherry `+`), is NOT
# reachable by SHA, AND ALL of whose changed paths are ABSENT from the trunk tree
# (the incident class: new files that never landed). A path that exists on trunk with
# different content is NOT flagged (legitimately-evolved file → avoids false alarms).
#
# Two modes:
#   * DEFAULT (review-not-fail) — reports EVERY stranded commit across all local
#     branches; exit 1 = REVIEW (operator ruling: recover only YOUR own dropped work,
#     NEVER cherry-pick a peer session's unlanded WIP onto the trunk). On a
#     multi-session box exit 1 is the normal state, so it is a prompt, not a verdict.
#   * --mine <session-id> (decidable) — reports ONLY stranded commits carrying your
#     session's ownership trailer, silent on peers. Exit 1 = YOUR content was dropped
#     (a real own-drop to recover); exit 0 = no own-session drop. This turns the REVIEW
#     into a machine-decidable pass/fail (T-P9-4 — the auto-land crux).
#
# OWNERSHIP TRAILER CONVENTION: a session's commits should carry a
# `Session-Id: <CLAUDE_CODE_SESSION_ID>` trailer (`Land-Session:` is also accepted) so
# `--mine` can attribute a drop. ship-land.sh stamps land.log with the sid and adds
# this trailer to any commit IT makes; sessions add it per the commit convention. A
# post-hoc trailer on already-made commits is impossible, hence the land.log sid too.
#
# Exit 1 if any (own, under --mine) stranded found (lists all first); else exit 0.
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

# is-this-commit-mine — true iff it carries our ownership trailer (Session-Id or
# Land-Session == MINE). git parses trailers structurally; exact whole-line match.
mine_match() {  # $1=sha
  [[ -z "${MINE}" ]] && return 1
  git show -s --format='%(trailers:key=Session-Id,valueonly,separator=%x0A)%x0A%(trailers:key=Land-Session,valueonly,separator=%x0A)' "$1" 2>/dev/null \
    | grep -qxF "${MINE}"
}

found=0
branch_count=0
for branch in $(git for-each-ref --format='%(refname:short)' refs/heads/); do
  [[ "${branch}" = "${TRUNK}" ]] && continue
  branch_count=$(( branch_count + 1 ))

  # `+ <sha>` lines = commits on branch NOT patch-equivalent on trunk.
  while IFS= read -r line; do
    case "${line}" in
      '+ '*) sha="${line#+ }" ;;
      *) continue ;;
    esac

    # Already on trunk by SHA → landed, skip.
    git merge-base --is-ancestor "${sha}" "${REMOTE_TRUNK}" 2>/dev/null && continue

    paths="$(git diff-tree --no-commit-id --name-only -r "${sha}" 2>/dev/null)"
    [[ -z "${paths}" ]] && continue

    all_absent=1
    absent_paths=""
    while IFS= read -r path; do
      [[ -z "${path}" ]] && continue
      if [[ -n "$(git ls-tree "${REMOTE_TRUNK}" -- "${path}" 2>/dev/null)" ]]; then
        all_absent=0                    # present on trunk (any content) → not the incident class
      else
        absent_paths="${absent_paths}${path}
"
      fi
    done <<EOF
${paths}
EOF

    if [[ "${all_absent}" = "1" ]]; then
      # --mine: skip a peer session's drop (silent); report only own-session drops.
      if [[ -n "${MINE}" ]] && ! mine_match "${sha}"; then
        continue
      fi
      found=$(( found + 1 ))
      short="$(git rev-parse --short "${sha}")"
      echo "✗ STRANDED ${short} on branch '${branch}' — paths absent from ${REMOTE_TRUNK}:"
      printf '%s' "${absent_paths}" | while IFS= read -r p; do
        [[ -n "${p}" ]] && echo "    ${p}"
      done
      echo "  recovery:"
      echo "    git branch backup/stranded-${short} ${sha}"
      echo "    git checkout ${TRUNK} && git fetch origin ${TRUNK} && git reset --hard ${REMOTE_TRUNK}"
      echo "    git cherry-pick ${sha}"
      echo "    # then gate (shellcheck + bats) and land via scripts/land-lock.sh"
      echo ""
    fi
  done <<EOF
$(git cherry "${REMOTE_TRUNK}" "${branch}" 2>/dev/null)
EOF
done

if [[ "${found}" -gt 0 ]]; then
  if [[ -n "${MINE}" ]]; then
    echo "✗ stranded-sweep --mine: ${found} commit(s) from YOUR session (${MINE}) dropped — content not on ${REMOTE_TRUNK}. Recover them via the recipes above; this is your own land drop, not peer WIP." >&2
  else
    echo "✗ stranded-sweep: ${found} commit(s) with content not on ${REMOTE_TRUNK}, across ${branch_count} branch(es)." >&2
    echo "  REVIEW each: recover only commits YOUR session just had a land drop; a peer session's unlanded WIP is expected — never cherry-pick it onto the trunk." >&2
  fi
  exit 1
fi
if [[ -n "${MINE}" ]]; then
  echo "✓ stranded-sweep --mine: 0 own-session (${MINE}) drops across ${branch_count} branch(es)"
else
  echo "✓ stranded-sweep: 0 stranded across ${branch_count} branch(es)"
fi
exit 0
