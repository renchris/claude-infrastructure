#!/usr/bin/env bash
# land-lock.sh — machine-wide landing serializer, REPO-KEYED (any repo).
#
#   scripts/land-lock.sh [--] <cmd> [args…]
#
# Runs <cmd> while holding a single mutex keyed to the current repo, so at most ONE
# session's gate+push runs at a time across all worktrees of that repo on this box.
# The lock is held ONLY across the wrapped command (gate+push, seconds-to-minutes),
# never a whole session — implementation parallelism is unaffected.
#
# The lock dir is /tmp/land-lock-<hash(repo_root)>/lock.d (override LAND_LOCK_DIR).
# pid-liveness is MEANINGFUL because THIS process runs <cmd> as a child and waits: the
# pid written into the lock is alive for the entire hold, so a crashed holder is reaped
# by the kill -0 check.
#
# Kill switch:  LAND_SERIALIZE=off scripts/land-lock.sh -- <cmd>   → run <cmd> unlocked.
# Tunables:     LAND_LOCK_TTL (empty/wedged-reap age, default 1200s) ·
#               LAND_LOCK_WAIT (max queue wait, default 3600s).
# Telemetry:    one JSON line per landing appended to ${LAND_LOG:-~/.claude/land.log}
#               {ts, repo, branch, wait_s, hold_s, exit, pid}.
#
# bash 3.2-safe (macOS default — no declare -A / mapfile / [[ -v ]] / ${var^^}).
# `pipefail` load-bearing; NO `set -e` (the EXIT trap must fire with the child's real
# code, not an -e abort).
set -uo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
HASH="$(printf '%s' "${REPO_ROOT}" | shasum | cut -c1-12)"
LOCK_PARENT="${LAND_LOCK_DIR:-/tmp/land-lock-${HASH}}"
LOCK="${LOCK_PARENT}/lock.d"
LOG="${LAND_LOG:-${HOME}/.claude/land.log}"
TTL="${LAND_LOCK_TTL:-1200}"        # empty/wedged-holder reap age (s)
WAIT_MAX="${LAND_LOCK_WAIT:-3600}"  # max seconds to queue for the lock before giving up
POLL=2
mkdir -p "${LOCK_PARENT}"
mkdir -p "$(dirname "${LOG}")" 2>/dev/null || true

# Accept an optional `--` separator, then require a command.
[[ "${1:-}" = "--" ]] && shift
[[ $# -gt 0 ]] || { echo "✗ land-lock.sh: no command given. Usage: land-lock.sh [--] <cmd> [args…]" >&2; exit 64; }

BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"

logline() {  # $1=wait_s $2=hold_s $3=exit
  printf '{"ts":"%s","repo":"%s","branch":"%s","wait_s":%s,"hold_s":%s,"exit":%s,"pid":%s}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${REPO_ROOT}" "${BRANCH}" "$1" "$2" "$3" "$$" >> "${LOG}" 2>/dev/null || true
}

# Kill switch → concurrent behavior (no lock, no log).
if [[ "${LAND_SERIALIZE:-on}" = "off" ]]; then
  echo "→ land-lock: LAND_SERIALIZE=off — running unserialized." >&2
  exec "$@"
fi

write_owner() { printf '%s\n' "$$" > "${LOCK}/pid"; printf '%s\n' "${BRANCH}" > "${LOCK}/branch" 2>/dev/null || true; }

# REAP RULE — correctness core; DIVERGES from reso deliberately (acceptance gate 3).
# A LIVE holder pid is NEVER reaped, even past TTL: a silently-dropped commit costs more
# than a wedged-lock wait, and LAND_SERIALIZE=off is the escape hatch.
try_acquire() {
  mkdir "${LOCK}" 2>/dev/null && { write_owner; return 0; }
  local holder stale age
  holder="$(cat "${LOCK}/pid" 2>/dev/null || true)"
  age="$(( $(date +%s) - $(stat -f %m "${LOCK}" 2>/dev/null || echo 0) ))"
  stale=0
  if [[ -z "${holder}" ]]; then
    # mkdir'd but pid not yet written — a real owner mid-acquire; grace 5s, else TTL.
    { [[ "${age}" -ge 5 ]] || [[ "${age}" -gt "${TTL}" ]]; } && stale=1
  elif kill -0 "${holder}" 2>/dev/null; then
    stale=0                                          # holder ALIVE → NEVER stale (wait it out)
  else
    stale=1                                          # holder pid DEAD → reap immediately
  fi
  if [[ "${stale}" = "1" ]]; then
    rm -rf "${LOCK}"
    mkdir "${LOCK}" 2>/dev/null && { write_owner; return 0; }
  fi
  return 1
}

WAIT_START="$(date +%s)"
WAITED=0
until try_acquire; do
  WAITED="$(( $(date +%s) - WAIT_START ))"
  if [[ "${WAITED}" -ge "${WAIT_MAX}" ]]; then
    echo "✗ land-lock: waited ${WAITED}s for ${LOCK} (holder pid $(cat "${LOCK}/pid" 2>/dev/null || echo '?'), branch $(cat "${LOCK}/branch" 2>/dev/null || echo '?')). Retry, or LAND_SERIALIZE=off to bypass." >&2
    logline "${WAITED}" 0 75
    exit 75   # EX_TEMPFAIL
  fi
  [[ "$(( WAITED % 30 ))" -lt "${POLL}" ]] && echo "→ land-lock: queued behind $(cat "${LOCK}/branch" 2>/dev/null || echo '?') (pid $(cat "${LOCK}/pid" 2>/dev/null || echo '?')) — ${WAITED}s…" >&2
  sleep "${POLL}"
done
WAITED="$(( $(date +%s) - WAIT_START ))"

HOLD_START="$(date +%s)"
CODE=130
# shellcheck disable=SC2329  # invoked indirectly via `trap release EXIT`
release() {
  rm -rf "${LOCK}"
  logline "${WAITED}" "$(( $(date +%s) - HOLD_START ))" "${CODE}"
}
trap release EXIT
if [[ "${WAITED}" -gt 0 ]]; then
  echo "→ land-lock: acquired after ${WAITED}s — machine-wide landing lock held." >&2
else
  echo "→ land-lock: acquired (no wait) — machine-wide landing lock held." >&2
fi

"$@"
CODE=$?
exit "${CODE}"
