#!/usr/bin/env bash
# land-lock.sh — machine-wide landing serializer, REPO-KEYED (any repo).
#
#   scripts/land-lock.sh [--] <cmd> [args…]      run <cmd> holding the mutex
#   scripts/land-lock.sh --status | --waiters | --alarms | --print-lock-dir
#                                                pure reads; NO lock is taken (P4 defect 6)
#
# Runs <cmd> while holding a single mutex keyed to the current repo, so at most ONE
# session's gate+push runs at a time across all worktrees of that repo on this box.
# The lock is held ONLY across the wrapped command (gate+push, seconds-to-minutes),
# never a whole session — implementation parallelism is unaffected.
#
# LOCK KEY (correctness core): the mutex is keyed on the SHARED git dir
# (`git rev-parse --path-format=absolute --git-common-dir`, normalized to the repo
# root), NOT the per-worktree `--show-toplevel`. `--show-toplevel` diverges across
# worktrees (each worktree is its own toplevel) so two worktrees of ONE repo would
# get two different lock dirs and land CONCURRENTLY — the exact topology the desk
# runs (every session in its own worktree). `--git-common-dir` is shared across all
# worktrees of a repo, so they all collide on one mutex. (Fixes G-P9-1.)
#
# The lock dir is /tmp/land-lock-<hash(shared-git-dir)>/lock.d (override LAND_LOCK_DIR).
# Introspect the resolved dir without landing:  scripts/land-lock.sh --print-lock-dir
# pid-liveness is MEANINGFUL because THIS process runs <cmd> as a child and waits: the
# pid written into the lock is alive for the entire hold, so a crashed holder is reaped
# by the pid+lstart liveness check (a bare `kill -0` is fooled when the OS recycles a dead
# holder's pid to a new live process under load — the lock records lstart to catch that).
#
# Kill switch:  LAND_SERIALIZE=off scripts/land-lock.sh -- <cmd>   → run <cmd> unlocked.
# Tunables:     LAND_LOCK_TTL (empty/wedged-reap age, default 1200s) ·
#               LAND_LOCK_WAIT (max queue wait, default 3600s) ·
#               LAND_LOCK_REAP_TTL (abandoned reap-mutex age, default 30s — see reap_and_claim).
# Telemetry:    JSON lines appended to ${LAND_LOG:-~/.claude/land.log}
#               {ts, repo, branch, event, wait_s, hold_s, exit, depth, pid}.
#               event=release (the terminal row, as before) · timeout · and — new in P4 — queued
#               and acquired, emitted ONLY by a lander that actually had to wait, so the wait is
#               visible while it is happening instead of only once it resolves. Non-terminal rows
#               carry exit -1.
#
# bash 3.2-safe (macOS default — no declare -A / mapfile / [[ -v ]] / ${var^^}).
# `pipefail` load-bearing; NO `set -e` (the EXIT trap must fire with the child's real
# code, not an -e abort).
set -uo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"   # telemetry: which checkout/worktree landed
# LOCK KEY — the SHARED git dir, so every worktree of one repo collides on ONE mutex.
# `--git-common-dir` (absolute) resolves to the main repo's `.git` from every worktree;
# normalize by stripping a per-worktree `/worktrees/<n>` gitdir suffix (defensive — some
# git versions return the per-worktree gitdir) then the trailing `/.git`, leaving the
# canonical repo root. Fall back to the toplevel for a non-repo / ancient git.
LOCK_KEY="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
if [[ -n "${LOCK_KEY}" ]]; then
  LOCK_KEY="${LOCK_KEY%/worktrees/*}"
  LOCK_KEY="${LOCK_KEY%/.git}"
else
  LOCK_KEY="${REPO_ROOT}"
fi
HASH="$(printf '%s' "${LOCK_KEY}" | shasum | cut -c1-12)"
LOCK_PARENT="${LAND_LOCK_DIR:-/tmp/land-lock-${HASH}}"
LOCK="${LOCK_PARENT}/lock.d"
REAP_LOCK="${LOCK_PARENT}/reap.d"   # serializes REAPERS only — never the lock itself

LOG="${LAND_LOG:-${HOME}/.claude/land.log}"
TTL="${LAND_LOCK_TTL:-1200}"        # empty/wedged-holder reap age (s)
WAIT_MAX="${LAND_LOCK_WAIT:-3600}"  # max seconds to queue for the lock before giving up
REAP_TTL="${LAND_LOCK_REAP_TTL:-30}"  # abandoned reap-mutex age (s) — the section is milliseconds
POLL=2
WAITERS="${LOCK_PARENT}/waiters"    # one file per QUEUED acquirer — the visible depth (P4 defect 4)

# ── stat DIALECT — VALIDATE THE OUTPUT, NEVER CHAIN ON THE EXIT CODE ─────────────────────────────
# 🚨 `stat -f %m <path> 2>/dev/null || echo <default>` is NOT the portable idiom, and this file
# spelled it five times. On BSD `-f` is "format" and `%m` is the mtime. On GNU `-f` is
# `--file-system`, so `%m` is read as a FILENAME: stat prints the *real* path's filesystem block to
# STDOUT — `  File: "/tmp/land-lock-…/lock.d"`, ID, Namelen, Type, Blocks, Inodes — and only THEN
# exits 1. `2>/dev/null` hides nothing, because that block is on stdout. The `||` default is then
# APPENDED to the block rather than replacing it, and the caller's `$(( now - $(…) ))` dies under
# `set -u` with `File: unbound variable`.
#
# THE REPO ALREADY PAID FOR THIS AND ALREADY WROTE THE CURE. `scripts/autonomy-sweep.sh:213`
# (file_mtime) documents the mechanism in these words, down to the error string;
# `scripts/drain-chain-assert.sh:189` records the same dialect making a rotor "a silent no-op on
# every Linux host"; `scripts/wrap-ledger.sh:273` says GNU `stat -f` must be VALIDATED rather than
# trusted. None of the three reached HERE — the land path's own mutex — which is this plan's
# standing generator (a landed remedy that never reached every holder) met once more.
#
# MEASURED 2026-08-31 in a cloud VM (BACKLOG_DRAIN_24_7, the off-box cause census): with two
# landers contending, the loser's ship-land exits 127 mid-gate and writes no result at all.
# `lock_is_stale` (age), `--status` (held), the hung-lock scan (age) and `reap_and_claim` (reap-TTL)
# all take that route. `lock_generation`'s `%i` is worse because it is SILENT: it is not in an
# arithmetic context, so the token simply carries the filesystem block instead of the inode — and
# that block is IDENTICAL for every directory on one filesystem, so the anti-ABA guarantee its own
# comment rests on ("`rm -rf` + `mkdir` always yields a NEW directory") is void on Linux, with no
# error anywhere. A mutex that stops distinguishing generations is the failure this file exists to
# prevent.
#
# GNU FIRST, for autonomy-sweep.sh's stated reason: BSD `stat` has no `-c` at all, so it cannot
# half-succeed the way `-f` does. Bare `stat`, matching this file's existing spelling — the output
# validation is what makes the resolution safe, so no new PATH assumption is added. bash 3.2-safe.
stat_field() {  # <bsd-spec> <gnu-spec> <path> [default=0] → the numeric field, or the default
  local v
  v="$(stat -c "$2" "$3" 2>/dev/null)"
  case "$v" in ''|*[!0-9]*) v="$(stat -f "$1" "$3" 2>/dev/null)" ;; esac
  case "$v" in ''|*[!0-9]*) v="${4:-0}" ;; esac
  printf '%s' "$v"
}
path_mtime() { stat_field %m %Y "$1" "${2:-0}"; }   # <path> [default] → mtime epoch seconds
path_inode() { stat_field %i %i "$1" "${2:-0}"; }   # <path> [default] → inode number

# ── INTROSPECTION VERBS + THE MISUSE GUARD (P4 defect 6) ─────────────────────────────────────────
# MEASURED: 23 ledger rows are `exit 127` — agents guessing `land-lock.sh status`. `status` was not
# a verb, so it was treated as PAYLOAD: the machine-wide mutex was TAKEN and only then did `status`
# fail to exec. One such guess waited 2,777 s on the lock to run a command that never existed, and
# every other lander on the box paid for that wait. Two halves, and neither works alone:
#   1. REAL VERBS, so the guess has a destination. The word agents reach for is `status`; refusing
#      it and offering nothing just moves the misuse to the next synonym.
#   2. A GUARD BEFORE THE MUTEX. A first argument that contains no `/` and that `command -v` cannot
#      resolve is not a payload, it is a typo or a guessed verb — refuse with EX_USAGE (64) while
#      the lock is still untouched. Keyed on RESOLVABILITY, not on a denylist of spellings, because
#      a denylist gets out-run by the next guess (memory: denylist-enumerates-spellings-not-the-
#      class). A path (`./x.sh`, `/usr/bin/foo`) is never second-guessed, so every real call site —
#      ship-land's `"$LAND_LOCK" -- "$SELF" __locked …` included — is untouched.
# All verbs are PURE READS and run before any mkdir, so introspection never litters /tmp and never
# takes the lock.
# ── {pid,lstart} IDENTITY — ONE DIALECT, PINNED (the C31/C33 class) ──────────────────────────────
# `ps -o lstart=` renders through LC_TIME **and** TZ, so THE SAME LIVE PID reads as two different
# strings depending on who is looking. Measured on this box 2026-08-21, same pid, same instant:
#     LANG=en_CA.UTF-8 (every session — 17/17 live `claude` procs) → `Fri 21 Aug 06:45:22 2026    `
#     LC_ALL=C         (launchd has no LANG; 5 of our own scripts `export LC_ALL=C`)
#                                                                 → `Fri Aug 21 06:45:22 2026    `
#     TZ=UTC                                                      → the hour moves by 7
# Compared as strings, an UNEQUAL reading means "pid REUSED by a stranger ⇒ holder DEAD ⇒ reap", so
# a cross-locale reader reaps the LANDING MUTEX out from under a live holder and two lands run at
# once — the rebase-drop incident .claude/CLAUDE.md opens with. Three separate hazards, one fix:
#
#   1. RENDERING — pin TZ *and* LC_ALL on every reading (LC_ALL, not LC_TIME: LC_ALL outranks every
#      other locale variable, so one pin cannot be defeated by an LC_TIME the caller also set).
#      TZ is pinned too, which the C31 shape did not: it is a second, independent axis of the same
#      bug (memory: process-start-time-renders-in-ambient-timezone), and scripts/lib/cc-common.sh
#      already pins both here for the same reason.
#   2. PADDING — `ps` pads to a fixed column width. A difference in trailing blanks is not a
#      difference in identity, and comparing untrimmed strings re-introduces this class the next
#      time a ps changes its padding. Trim on WRITE and on READ.
#   3. THE UNREADABLE INSTRUMENT — `ps` returning nothing for a pid `kill -0` has just proved alive
#      is a FAILED PROBE, not a stranger. Pre-fix that empty string fell straight through the
#      `rec != cur` comparison into the reap branch, so the one condition under which NOTHING is
#      known was the condition that produced two live landers. It is now honoured, per H2 below.
#
# MIGRATION, and it is load-bearing rather than defensive: a lock already on disk carries the OLD
# ambient rendering, which does NOT equal the new canonical one (measured: `Fri 21 Aug 06:46:23
# 2026` vs `Fri Aug 21 13:46:23 2026`). A canonical-only reader would therefore reap exactly one
# live holder on the way in — this fix committing the bug it removes. So a record that fails the
# canonical compare is re-checked against the AMBIENT rendering before it is called a mismatch.
# That fallback cannot launder a genuinely recycled pid: both readings are of the SAME pid taken at
# the SAME moment, so no rendering of a *different* start instant can equal the record.
#
# Net direction, asserted by the tests below and never merely claimed: this path can only ever reap
# FEWER locks than before. H2 is strictly strengthened.
proc_lstart() {   # <pid> → that pid's start time rendered CANONICALLY and trimmed; "" = unreadable
  TZ=UTC LC_ALL=C ps -o lstart= -p "${1:-$$}" 2>/dev/null | sed 's/^ *//;s/ *$//'
}
lstart_matches() { # <recorded> <pid> → 0 iff <recorded> is NOT evidence that <pid> is a stranger.
                   # Returns 0 (honour) for every unusable reading; 1 ONLY on a proven mismatch.
  local rec cur
  rec="$(printf '%s' "${1:-}" | sed 's/^ *//;s/ *$//')"
  [[ -n "${rec}" ]] || return 0                     # nothing recorded — caller's compat rule owns it
  cur="$(proc_lstart "${2:-}")"
  [[ -n "${cur}" ]] || return 0                     # hazard 3: unreadable instrument ⇒ NOT a mismatch
  [[ "${rec}" = "${cur}" ]] && return 0
  cur="$(ps -o lstart= -p "${2:-}" 2>/dev/null | sed 's/^ *//;s/ *$//')"   # migration: pre-fix record
  [[ -n "${cur}" && "${rec}" = "${cur}" ]] && return 0
  return 1                                          # proven stranger → the caller may reap
}

holder_live() {   # $1=lock.d → 0 iff its recorded holder is a LIVE process whose lstart MATCHES.
                  # Same pid+lstart rule as lock_is_stale, in the same dialect, for the same reason.
  local d="$1" pid rec
  pid="$(cat "${d}/pid" 2>/dev/null || true)"
  case "${pid:-}" in ''|*[!0-9]*) return 1 ;; esac
  kill -0 "${pid}" 2>/dev/null || return 1
  rec="$(cat "${d}/lstart" 2>/dev/null || true)"
  lstart_matches "${rec}" "${pid}" || return 1
  return 0
}

waiters_live() {  # $1=lock parent → one "<pid> <waited_s> <branch>" line per LIVE waiter.
                  # PRUNES as it reads: a waiter SIGKILLed mid-queue runs no trap and leaves its
                  # file behind, so the registry is self-healing rather than monotonically growing.
  local wd="$1/waiters" f pid rec ts now
  [[ -d "${wd}" ]] || return 0
  now="$(date +%s)"
  for f in "${wd}"/*; do
    [[ -f "${f}" ]] || continue
    pid="${f##*/}"
    case "${pid}" in ''|*[!0-9]*) rm -f "${f}" 2>/dev/null; continue ;; esac
    rec="$(sed -n 's/^lstart=//p' "${f}" 2>/dev/null | sed -n 1p)"
    # Same dialect as holder_live/lock_is_stale — ONE identity rule for the whole file. The old
    # `[[ -z "$cur" ]]` prune is GONE: an unreadable `ps` deleted a LIVE waiter's registration, so
    # an instrument failure silently shrank the very queue depth --status exists to publish.
    if ! kill -0 "${pid}" 2>/dev/null || ! lstart_matches "${rec}" "${pid}"; then
      rm -f "${f}" 2>/dev/null; continue
    fi
    ts="$(sed -n 's/^since=//p' "${f}" 2>/dev/null | sed -n 1p)"
    case "${ts}" in ''|*[!0-9]*) ts="${now}" ;; esac
    printf '%s %s %s\n' "${pid}" "$(( now - ts ))" "$(sed -n 's/^branch=//p' "${f}" 2>/dev/null | sed -n 1p)"
  done
}

lock_alarm_rows() {  # machine-wide: one JSON row per LIVE holder that is PAST ITS BUDGET.
  # P4 defect 5. H2 (never reap a LIVE holder) STANDS and is not weakened by one byte here — this
  # is the OTHER half of H2, which was missing: if the policy is that we will never take the lock
  # back from a live holder, then a live holder that never lets go has to reach a human, and it
  # reached nobody. Live proof: holder pid 82031 was observed ppid-1 (its owning session dead) and
  # nothing anywhere raised a word about it.
  #
  # THE TRIGGER IS "LIVE PAST TTL", NOT "ppid == 1" — deliberately, and this corrects the framing
  # the audit row uses. Orphanhood is NOT evidence of abandonment on this box: a backgrounded land
  # is the normal shape (Bash-tool ceiling 600 s < episode p90 991 s) and its launching shell exits
  # immediately, so a perfectly healthy lander is reparented to pid 1 exactly like a derelict one —
  # the identical false-positive cc-await-ping's owner guard documents. An alarm that fired on every
  # healthy backgrounded land would fire always and therefore say nothing (memory:
  # alarm-polarity-and-attention-budget). Over-budget IS the harm, it strictly contains the observed
  # case (82031 was orphaned AND long-held), and ppid is carried in the DETAIL where it belongs.
  local parent d age pid ppid state now
  now="$(date +%s)"
  for parent in ${LAND_LOCK_SCAN:-/tmp/land-lock-*}; do
    d="${parent}/lock.d"
    [[ -d "${d}" ]] || continue
    holder_live "${d}" || continue
    age="$(( now - $(path_mtime "${d}" "${now}") ))"
    [[ "${age}" -gt "${TTL}" ]] || continue
    pid="$(cat "${d}/pid" 2>/dev/null || echo '?')"
    ppid="$(ps -o ppid= -p "${pid}" 2>/dev/null | tr -d ' ' || true)"
    if [[ "${ppid:-0}" = "1" ]]; then state="ORPHANED-HELD"; else state="OVER-BUDGET"; fi
    printf '{"kind":"land-lock-hung","state":"%s","detail":"pid %s has held the land mutex %ss (budget %ss, ppid %s); H2 forbids reaping a LIVE holder — this needs a human","subject":"%s","recover_cmd":"ps -o pid,ppid,lstart,command -p %s","ts":%s}\n' \
      "${state}" "${pid}" "${age}" "${TTL}" "${ppid:-?}" "${d}" "${pid}" "${now}"
  done
}

case "${1:-}" in
  --print-lock-dir)
    printf '%s\n' "${LOCK_PARENT}"
    exit 0 ;;
  --status)
    printf 'lock dir: %s\n' "${LOCK}"
    if [[ -d "${LOCK}" ]]; then
      if holder_live "${LOCK}"; then
        printf 'holder:   pid %s  branch %s  held %ss  (LIVE — H2: never reaped)\n' \
          "$(cat "${LOCK}/pid" 2>/dev/null || echo '?')" "$(cat "${LOCK}/branch" 2>/dev/null || echo '?')" \
          "$(( $(date +%s) - $(path_mtime "${LOCK}" "$(date +%s)") ))"
      else
        printf 'holder:   present but DEAD or empty — the next acquirer reaps it\n'
      fi
    else
      printf 'holder:   (free)\n'
    fi
    printf 'waiters:  %s\n' "$(waiters_live "${LOCK_PARENT}" | grep -c . || true)"
    waiters_live "${LOCK_PARENT}" | while read -r p w b; do printf '  pid %s  branch %s  waited %ss\n' "$p" "$b" "$w"; done
    exit 0 ;;
  --waiters)
    waiters_live "${LOCK_PARENT}"
    exit 0 ;;
  --alarms)
    lock_alarm_rows
    exit 0 ;;
  --help|-h)
    sed -n '2,6p' "$0"
    printf 'Verbs (pure reads, no lock taken): --print-lock-dir · --status · --waiters · --alarms\n'
    exit 0 ;;
esac

mkdir -p "${LOCK_PARENT}"
mkdir -p "$(dirname "${LOG}")" 2>/dev/null || true

# Accept an optional `--` separator, then require a command.
[[ "${1:-}" = "--" ]] && shift
[[ $# -gt 0 ]] || { echo "✗ land-lock.sh: no command given. Usage: land-lock.sh [--] <cmd> [args…]  |  verbs: --print-lock-dir --status --waiters --alarms" >&2; exit 64; }

# THE GUARD — before the mutex, never after (see the block above).
case "$1" in
  */*) ;;   # a path: never second-guessed
  *)
    if ! command -v "$1" >/dev/null 2>&1; then
      echo "✗ land-lock.sh: '$1' is neither a runnable command nor a land-lock verb — REFUSING before the lock is taken. (Guessed verbs used to be run as payload: the mutex was held for the whole wait and then exited 127; one such guess waited 2777s to run a command that does not exist.) Verbs: --print-lock-dir · --status · --waiters · --alarms. To wrap a command: land-lock.sh -- <cmd> [args…]" >&2
      exit 64
    fi ;;
esac

BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"

logline() {  # $1=event $2=wait_s $3=hold_s $4=exit [$5=queue depth]
  # SCHEMA GROWTH IS SAFE (land.log's readers tail it / select by key), and `event` is what makes
  # the waiter rows below distinguishable from a completed hold: a non-terminal row carries
  # exit -1, so nothing that counts `exit == 0` lands or sums hold_s changes its answer.
  printf '{"ts":"%s","repo":"%s","branch":"%s","event":"%s","wait_s":%s,"hold_s":%s,"exit":%s,"depth":%s,"pid":%s}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${REPO_ROOT}" "${BRANCH}" "$1" "$2" "$3" "$4" "${5:-0}" "$$" >> "${LOG}" 2>/dev/null || true
}

# ── THE WAITER REGISTRY (P4 defect 4) ────────────────────────────────────────────────────────────
# MEASURED: land-lock logged only at timeout or the release EXIT trap, so a QUEUED waiter wrote
# NOTHING until its wait resolved — three live waiters were observed with zero ledger rows, and all
# four rows then appeared at once on release. Waits of 98 s / 665 s / 2,362 s / 5,536 s were
# therefore invisible for their entire duration, which is precisely the interval in which someone
# would want to know. Two fixes, both about the WAIT rather than its outcome:
#   · a file per queued acquirer in the lock dir, so DEPTH is readable by anyone (`--status`);
#   · a ledger row at ACQUIRE-START, not only at resolution.
# Registration happens only once the first try_acquire has FAILED — an uncontended land (the
# common case) adds no file and no row, so this cannot become log volume that hides its own signal.
waiter_register() {
  mkdir -p "${WAITERS}" 2>/dev/null || return 0
  {
    printf 'lstart=%s\n' "$(proc_lstart "$$")"
    printf 'since=%s\n'  "$(date +%s)"
    printf 'branch=%s\n' "${BRANCH}"
  } > "${WAITERS}/$$" 2>/dev/null || true
}
# shellcheck disable=SC2329  # invoked indirectly via `trap waiter_unregister EXIT` while queued.
waiter_unregister() { rm -f "${WAITERS}/$$" 2>/dev/null || true; }

# Kill switch → concurrent behavior (no lock, no log).
if [[ "${LAND_SERIALIZE:-on}" = "off" ]]; then
  echo "→ land-lock: LAND_SERIALIZE=off — running unserialized." >&2
  exec "$@"
fi

write_owner() {
  printf '%s\n' "$$" > "${LOCK}/pid"
  # Record OUR start-time next to the pid so a later acquirer can distinguish a live holder
  # from a DEAD holder whose pid the OS has recycled to a new process (see try_acquire).
  # Rendered through the ONE chokepoint, so the writer and every reader speak one dialect.
  proc_lstart "$$" > "${LOCK}/lstart" 2>/dev/null || true
  printf '%s\n' "${BRANCH}" > "${LOCK}/branch" 2>/dev/null || true
}

# REAP RULE — correctness core; DIVERGES from reso deliberately (acceptance gate 3).
# A LIVE holder pid is NEVER reaped, even past TTL: a silently-dropped commit costs more
# than a wedged-lock wait, and LAND_SERIALIZE=off is the escape hatch. (H2.)
#
# FACTORED OUT of try_acquire so reap_and_claim can RE-RUN it, unchanged, inside the reap
# mutex: ONE predicate, two call sites, so the re-check can never drift from the check that
# authorised the reap (memory: actuator-is-the-arbiter — never re-implement a gate's predicate
# outside it).
lock_is_stale() {  # 0 = reapable · 1 = live, hold off
  local holder age rec_lstart
  holder="$(cat "${LOCK}/pid" 2>/dev/null || true)"
  age="$(( $(date +%s) - $(path_mtime "${LOCK}" 0) ))"
  if [[ -z "${holder}" ]]; then
    # mkdir'd but pid not yet written — a real owner mid-acquire; grace 5s, else TTL.
    { [[ "${age}" -ge 5 ]] || [[ "${age}" -gt "${TTL}" ]]; } && return 0
    return 1
  fi
  if kill -0 "${holder}" 2>/dev/null; then
    # pid is alive — but under load a DEAD holder's pid can be RECYCLED to a new process,
    # which kill -0 alone cannot detect (it flaked exactly this way, wedging every landing:
    # 2026-07-25). Verify identity by start-time: a recycled pid belongs to a different
    # process with a different lstart → the original holder is dead → reap. pid+lstart rule
    # (memory: periodic-job-self-overlap — kill -0 alone is insufficient under pid reuse).
    # The comparison goes through lstart_matches, so a locale/TZ/padding difference and an
    # unreadable `ps` can no longer masquerade as a recycled pid. H2 DIVERGES here from
    # postland-verify.sh's twin ON PURPOSE and that divergence is this file's documented policy,
    # not an oversight: postland bounds its unverifiable-holder honour by TTL, because two live
    # verifiers are cheap; here a live holder is NEVER reaped at any age, because two live LANDERS
    # rebase-drop a commit. The unverifiable holder is not left unattended either — once it is past
    # budget, lock_alarm_rows pages a human, which is the OTHER half of H2.
    rec_lstart="$(cat "${LOCK}/lstart" 2>/dev/null || true)"
    lstart_matches "${rec_lstart}" "${holder}" || return 0   # pid REUSED by a stranger → holder DEAD
    return 1                                         # same live process → H2: NEVER stale
  fi
  return 0                                           # holder pid DEAD → reap immediately
}

# GENERATION — the identity of the lock object we JUDGED, so a reaper can prove inside the reap
# mutex that it is deleting that same dead holder and not a live one that replaced it. pid+lstart
# alone are not enough (a reaped-and-recreated lock can carry an identical empty pid file), so the
# inode is in the token: `rm -rf` + `mkdir` always yields a NEW directory.
lock_generation() {
  printf '%s|%s|%s' \
    "$(cat "${LOCK}/pid" 2>/dev/null || true)" \
    "$(cat "${LOCK}/lstart" 2>/dev/null || true)" \
    "$(path_inode "${LOCK}" 0)"
}

# ATOMIC REAP. `rm -rf "${LOCK}"; mkdir "${LOCK}"` was NOT atomic and could not be made so by
# ordering alone: two acquirers that both judged the lock dead both removed it and both recreated
# it — 3 simultaneous holders reproduced (land-architecture-100p-2026-08-10 §2.H), i.e. the mutex
# silently stopped being a mutex in exactly the crash-recovery case it exists for. A rename-claim
# does not fix it either: A renames the dead lock away and recreates it, and B's rename then
# carries off A's LIVE lock. Two things together make it atomic:
#   1. A REAP MUTEX (${REAP_LOCK}) serializes reapers, so at most one deletes at a time.
#   2. A GENERATION + staleness RE-CHECK inside it: the lock must still be the same object we
#      judged AND must still be stale by the same rule. Anything else ⇒ abort, touch nothing,
#      re-observe on the next poll.
# (2) is what closes the window (1) alone leaves — the loser wakes, sees the winner's LIVE lock,
# and queues, which is the correct outcome rather than a second reap.
# H2 is strictly strengthened, never weakened: this path can only ever reap FEWER locks than
# before, and a live holder now has to survive two independent liveness reads instead of one.
reap_and_claim() {  # $1 = the generation token observed when we judged it stale
  local gen="$1" rc=1 rage
  if ! mkdir "${REAP_LOCK}" 2>/dev/null; then
    # A reaper killed mid-section would wedge every future reap on this box, so the reap mutex has
    # its own TTL. The section is milliseconds (a couple of stats, an rm, a mkdir), so anything
    # older than REAP_TTL is abandoned rather than working. Losing this race is harmless: we just
    # return and re-observe.
    rage="$(( $(date +%s) - $(path_mtime "${REAP_LOCK}" "$(date +%s)") ))"
    [[ "${rage}" -gt "${REAP_TTL}" ]] && rm -rf "${REAP_LOCK}" 2>/dev/null
    return 1
  fi
  if [[ "$(lock_generation)" = "${gen}" ]] && lock_is_stale; then
    rm -rf "${LOCK}"
    # A plain acquirer can still win the gap between the rm and this mkdir — that is a legitimate
    # fresh owner, so failing here means "wait", never "try harder".
    mkdir "${LOCK}" 2>/dev/null && { write_owner; rc=0; }
  fi
  rmdir "${REAP_LOCK}" 2>/dev/null || true
  return "${rc}"
}

try_acquire() {
  mkdir "${LOCK}" 2>/dev/null && { write_owner; return 0; }
  local gen; gen="$(lock_generation)"    # BEFORE the verdict, so the token names what we judged
  lock_is_stale || return 1
  reap_and_claim "${gen}"
}

WAIT_START="$(date +%s)"
WAITED=0
QUEUED=0
DEPTH=0
until try_acquire; do
  if [[ "${QUEUED}" -eq 0 ]]; then
    # FIRST failure ⇒ we are genuinely queued. Register, become visible, and say so in the ledger
    # NOW rather than at resolution. The EXIT trap covers the timeout path and any trapped death
    # while queued; an untrapped kill leaves a file that waiters_live prunes on the next read.
    QUEUED=1
    waiter_register
    trap waiter_unregister EXIT
    DEPTH="$(waiters_live "${LOCK_PARENT}" | grep -c . || true)"
    logline "queued" 0 0 -1 "${DEPTH}"
    echo "→ land-lock: QUEUED behind $(cat "${LOCK}/branch" 2>/dev/null || echo '?') (holder pid $(cat "${LOCK}/pid" 2>/dev/null || echo '?')) — queue depth ${DEPTH}. This wait is visible now: bash $0 --status" >&2
  fi
  WAITED="$(( $(date +%s) - WAIT_START ))"
  if [[ "${WAITED}" -ge "${WAIT_MAX}" ]]; then
    echo "✗ land-lock: waited ${WAITED}s for ${LOCK} (holder pid $(cat "${LOCK}/pid" 2>/dev/null || echo '?'), branch $(cat "${LOCK}/branch" 2>/dev/null || echo '?')). Retry, or LAND_SERIALIZE=off to bypass." >&2
    logline "timeout" "${WAITED}" 0 75 "${DEPTH}"
    exit 75   # EX_TEMPFAIL
  fi
  [[ "$(( WAITED % 30 ))" -lt "${POLL}" ]] && echo "→ land-lock: queued behind $(cat "${LOCK}/branch" 2>/dev/null || echo '?') (pid $(cat "${LOCK}/pid" 2>/dev/null || echo '?')) — ${WAITED}s…" >&2
  sleep "${POLL}"
done
WAITED="$(( $(date +%s) - WAIT_START ))"
if [[ "${QUEUED}" -eq 1 ]]; then
  waiter_unregister
  logline "acquired" "${WAITED}" 0 -1 "${DEPTH}"
fi

HOLD_START="$(date +%s)"
CODE=130
# shellcheck disable=SC2329  # invoked indirectly via `trap release EXIT`
release() {
  rm -rf "${LOCK}"
  logline "release" "${WAITED}" "$(( $(date +%s) - HOLD_START ))" "${CODE}" "${DEPTH}"
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
