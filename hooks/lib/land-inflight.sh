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
  [ -n "${_li_rec}" ] || return 1
  _li_cur="$(ps -o lstart= -p "${_li_pid}" 2>/dev/null || true)"
  [ "${_li_rec}" = "${_li_cur}" ] || return 1
  _li_ts="$(land_inflight_field "${_li_f}" started)"
  case "${_li_ts}" in ''|*[!0-9]*) _li_ts=0 ;; esac
  printf '%s %s %s\n' "${_li_pid}" "${_li_ts}" "$(land_inflight_field "${_li_f}" branch)"
}
