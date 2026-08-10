#!/bin/bash
# goal-state.sh — ONE answer to "does this session have a LIVE /goal?", shared by every surface
# that could otherwise sabotage it.
#
# WHY (docs/research/goal-in-handoff-2026-08-08.md § RESOLVED 2026-08-09 + § RESOLUTION 2026-08-10).
# `/goal` registers a type:"prompt" Stop hook inside the CC binary. The Stop handler's FIRST act is
# to DELETE that hook for the duration of any Stop at which the task registry holds non-terminal
# background work (`Tio`: any local_bash task), restoring it in a `finally` — so the registry reads
# healthy before and after, and the goal is silently skipped during. A parked
# `cc-await-ping --timeout 14400` background Bash therefore makes an armed goal inert for hours,
# and THREE of our own surfaces used to instruct exactly that arm (mailbox-drain's nag,
# session-continue's WAKE FLOOR block, CLAUDE.md § Agent Teams). Each now consults this predicate
# first. One lib, one predicate, so the producers cannot drift.
#
# THE PREDICATE. A goal is LIVE iff the transcript's LAST goal_status ATTACHMENT has met==false
# and not failed. Record dictionary (read out of the 2.1.220 binary, kld/Qdr @232982, eval
# @233098):
#   sentinel:true  met:false              → ARM marker (set, not yet evaluated)        → LIVE
#   (no sentinel)  met:false              → an evaluation that judged UNMET            → LIVE
#   (no sentinel)  met:false failed:true  → judged IMPOSSIBLE; CC cleared the goal     → not live
#   (no sentinel)  met:true               → achieved (auto-cleared)                    → not live
#   sentinel:true  met:true               → `/goal clear` marker                       → not live
#
# ⚠ TRAP (measured on the session that produced the finding): a bare `grep goal_status` matches
# the assistant's own PROSE about goals — 6 hits where the truth was 1. Filter type=="attachment".
# grep runs first only to keep the jq slurp off multi-MB transcripts.
#
# FAIL DIRECTION. Every consumer uses this to SUPPRESS advice or REFUSE an arm. A false "no goal"
# merely restores the old behaviour; a false "goal live" would silence a wake-path nag a goal-less
# session needs. So every failure — no path, no file, no jq, unparseable line — returns rc 1.

goal_live_condition() { # $1 = transcript path → prints the condition; rc 0 iff a /goal is LIVE
  local tp="$1" rec
  [ -n "$tp" ] || return 1
  case "$tp" in "~"*) tp="$HOME${tp#\~}" ;; esac
  [ -f "$tp" ] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  rec="$(grep -a 'goal_status' "$tp" 2>/dev/null | jq -rc --slurp '
    [ .[] | select(.type == "attachment")
          | .attachment | select(.type == "goal_status") ] | last // empty' 2>/dev/null)" || return 1
  [ -n "$rec" ] || return 1
  [ "$(printf '%s' "$rec" | jq -r '(.met // false) or (.failed // false)' 2>/dev/null)" = "false" ] || return 1
  printf '%s' "$(printf '%s' "$rec" | jq -r '.condition // ""' 2>/dev/null)"
  return 0
}
