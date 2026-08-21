#!/usr/bin/env bash
# hooks/lib/land-inflight.sh — ONE reader for the ship-land IN-FLIGHT marker
# (land-architecture-100p-2026-08-10 §5 P4, defect 3).
#
# THE DEFECT, measured: `scripts/wrap-ledger.sh` and `hooks/completion-assert.sh` compute the close
# state from `trunk..HEAD`, which is ALSO true for the entire duration of a land. A land is minutes
# long (episode p90 991 s) and the only workable shape is backgrounded, so the common case is that
# the close protocol runs WHILE the land runs: the ledger reads 📦 "on a branch only — /ship to land
# it", the readout renders that as the ONE command, and the operator (or the model's own auto-ship)
# fires a SECOND /ship on the same worktree. That second land takes the machine-wide mutex behind
# its own sibling, and a lock the first land is holding is exactly the wait this repo has spent
# 2,362 s and 5,536 s on.
#
# THE MARKER is per-WORKTREE — `--absolute-git-dir`, not the common dir. Two worktrees of one repo
# may legitimately land at the same time (they collide on the mutex, which is the design); what is
# never legitimate is two lands from ONE worktree, because they share a HEAD and a rebase.
#
# LIVENESS IS pid + lstart, NEVER pid alone. A pid is recycled by the OS under load, and this file
# outlives its writer whenever the writer is SIGKILLed (defect 1's population — a killed land runs
# no trap). `land-lock.sh` learned that the hard way on 2026-07-25 and this reader uses the same
# rule, deliberately in the same dialect.
#
# FAIL DIRECTION IS TOWARD "NOT IN FLIGHT", and that is the load-bearing choice. A false
# IN-FLIGHT suppresses the 📦 nudge over work that is genuinely parked — the FM1 park-and-call-it-
# done hazard, i.e. losing the commits. A false NOT-IN-FLIGHT merely restores today's behaviour.
# So anything unreadable, unparseable, missing an lstart, or naming a pid whose start-time does not
# match is reported as NOT in flight.
#
# Consumers: scripts/ship-land.sh (producer + its own concurrency refusal), scripts/wrap-ledger.sh
# (LANDING= machine field, and the 📦 readout it inverts), hooks/completion-assert.sh (exonerates
# the unlanded conviction). Sourced, never executed.

land_inflight_path() {   # $1 = any dir inside the worktree (default .) → the marker path, rc 1 if not a repo
  _li_gd="$(git -C "${1:-.}" rev-parse --absolute-git-dir 2>/dev/null || true)"
  [ -n "${_li_gd}" ] || return 1
  printf '%s/ship-land-inflight' "${_li_gd}"
}

land_inflight_field() {  # $1=marker file $2=key → the value, or "" (first occurrence wins)
  sed -n "s/^$2=//p" "$1" 2>/dev/null | sed -n 1p
}

# ── {pid,lstart} DIALECT — ONE CANONICAL RENDERING, PINNED (the C31/C33/land-lock class) ─────────
# `ps -o lstart=` formats through LC_TIME **and** TZ, so THE SAME LIVE PID reads as two different
# strings depending on who is looking. This pair is a guaranteed miss rather than a rare one,
# because the fleet's two lstart producers write OPPOSITE dialects. Measured 2026-08-21:
#     ship-land-inflight markers on disk  →  3/3   `Fri Aug 21 08:05:57 2026`  (C dialect)
#     ~/.claude/wait-contracts records    →  64/64 `Fri 21 Aug 11:03:20 2026`  (ambient en_CA)
# Same-moment proof on a LIVE land (pid 21936, branch claude/fire-20260820T172902Z-13979-1):
#     STORED by ship-land            [Fri Aug 21 08:05:57 2026    ]
#     a session reader renders       [Fri 21 Aug 08:05:57 2026    ]   → exact compare MISMATCHES
# so land_inflight_live reported NOT-IN-FLIGHT for a land that was running. That is this file's
# entire purpose defeated 100% of the time, not intermittently: wrap-ledger then renders 📦 "on a
# branch only — /ship to land it" DURING the land, and ship-land's own exit-11 concurrency refusal
# never fires, so a second land takes the same worktree's HEAD and rebase.
#
# THE FIX IS ON BOTH SIDES, because only a canonical WRITE is locale-independent by construction:
# scripts/ship-land.sh inflight_claim records li_lstart, and this reader compares the same
# rendering. TZ is pinned as well as LC_ALL — a second, independent axis of the same bug (memory:
# process-start-time-renders-in-ambient-timezone), and LC_ALL rather than LC_TIME because LC_ALL
# outranks every other locale variable, so one pin cannot be defeated by a caller's LC_TIME.
#
# MIGRATION, and it is load-bearing rather than defensive: every marker already on disk carries a
# PRE-FIX rendering, so a canonical-only reader would call each one a stranger — this fix
# committing the bug it removes. The fallbacks re-check the SAME pid at the SAME moment in the two
# dialects this fleet is MEASURED to produce (the reader's own ambient, and LC_ALL=C at local TZ —
# the two populations above). A record in some third dialect matches nothing and falls through to
# NOT-IN-FLIGHT, which is exactly today's behaviour — degraded, never worse. This is a measured
# population, not a denylist of guessed spellings (memory: denylist-enumerates-spellings-not-the-
# class), and canonical writes make it a set that ages out.
#
# THE FALLBACKS CANNOT MANUFACTURE A FALSE IN-FLIGHT — the direction this file names as the
# dangerous one, because a false IN-FLIGHT suppresses the 📦 nudge over genuinely parked work.
# Every candidate is a rendering of the SAME pid taken at the SAME moment, so no rendering of a
# DIFFERENT start instant can equal the record: the time-of-day digits differ in every dialect.
# Asserted by tests/land-inflight.bats ("a genuinely recycled pid"), never merely claimed.
li_lstart() {   # <pid> → that pid's start time rendered CANONICALLY and trimmed; "" = unreadable
  TZ=UTC LC_ALL=C ps -o lstart= -p "${1:-$$}" 2>/dev/null | sed 's/^ *//;s/ *$//'
}

li_lstart_matches() { # <recorded> <pid> → 0 iff <recorded> is evidence <pid> is the SAME process.
                      # Fail direction is NOT-IN-FLIGHT: every unusable reading returns 1.
  _li_r="$(printf '%s' "${1:-}" | sed 's/^ *//;s/ *$//')"
  [ -n "${_li_r}" ] || return 1        # never recorded — cannot exonerate a recycled pid
  _li_c="$(li_lstart "${2:-}")"
  [ -n "${_li_c}" ] || return 1        # unreadable instrument — per this file's fail direction
  [ "${_li_r}" = "${_li_c}" ] && return 0
  _li_c="$(ps -o lstart= -p "${2:-}" 2>/dev/null | sed 's/^ *//;s/ *$//')"
  [ -n "${_li_c}" ] && [ "${_li_r}" = "${_li_c}" ] && return 0        # migration: reader-ambient
  _li_c="$(LC_ALL=C ps -o lstart= -p "${2:-}" 2>/dev/null | sed 's/^ *//;s/ *$//')"
  [ -n "${_li_c}" ] && [ "${_li_r}" = "${_li_c}" ] && return 0        # migration: C at local TZ
  return 1
}

land_inflight_live() {   # $1 = any dir inside the worktree (default .)
                         # rc 0 + prints "<pid> <started_epoch> <branch>" iff a land is IN FLIGHT
                         # rc 1 (prints nothing) otherwise — including every unreadable case.
  _li_f="$(land_inflight_path "${1:-.}")" || return 1
  [ -s "${_li_f}" ] || return 1
  _li_pid="$(land_inflight_field "${_li_f}" pid)"
  case "${_li_pid}" in ''|*[!0-9]*) return 1 ;; esac
  kill -0 "${_li_pid}" 2>/dev/null || return 1
  # An lstart that was never recorded cannot exonerate a recycled pid, so its ABSENCE is treated as
  # "cannot adjudicate" ⇒ not in flight, per the fail direction above.
  _li_rec="$(land_inflight_field "${_li_f}" lstart)"
  li_lstart_matches "${_li_rec}" "${_li_pid}" || return 1
  _li_ts="$(land_inflight_field "${_li_f}" started)"
  case "${_li_ts}" in ''|*[!0-9]*) _li_ts=0 ;; esac
  printf '%s %s %s\n' "${_li_pid}" "${_li_ts}" "$(land_inflight_field "${_li_f}" branch)"
}
