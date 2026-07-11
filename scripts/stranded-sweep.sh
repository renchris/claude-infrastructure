#!/usr/bin/env bash
# stranded-sweep.sh — detect commits STRANDED on local branches: committed here but
# whose content never reached the trunk (dropped by a concurrent rebase-land — the
# 2026-07-11 incident). A plain "N unlanded" count read 0 and missed it; this checks
# content, not just SHA reachability.
#
#   scripts/stranded-sweep.sh [trunk]
#
# STRANDED := a commit that is NOT patch-equivalent on trunk (git cherry `+`), is NOT
# reachable by SHA, AND ALL of whose changed paths are ABSENT from the trunk tree
# (the incident class: new files that never landed). A path that exists on trunk with
# different content is NOT flagged (legitimately-evolved file → avoids false alarms).
#
# Exit 1 if any stranded found (lists all first); else exit 0.
#
# bash 3.2-safe. `pipefail` load-bearing; NO `set -e`.
set -uo pipefail

TRUNK="${1:-}"
if [[ -z "${TRUNK}" ]]; then
  TRUNK="$(git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')"
  [[ -z "${TRUNK}" ]] && TRUNK="main"
fi

# Best-effort refresh — never fail if offline.
git fetch -q origin "${TRUNK}" 2>/dev/null || true

REMOTE_TRUNK="origin/${TRUNK}"

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
  echo "✗ stranded-sweep: ${found} commit(s) with content not on ${REMOTE_TRUNK}, across ${branch_count} branch(es)." >&2
  echo "  REVIEW each: recover only commits YOUR session just had a land drop; a peer session's unlanded WIP is expected — never cherry-pick it onto the trunk." >&2
  exit 1
fi
echo "✓ stranded-sweep: 0 stranded across ${branch_count} branch(es)"
exit 0
