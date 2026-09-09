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

# ── THE GREP LEG, AS ITS OWN FUNCTION — because a bare `grep` in a pipeline is a THIRD outcome ────
#
# THE BUG THIS REMOVES (A04 § 3, exhaustive-drive 2026-09-08; 375 of 469 goal-inert-watch
# evaluations in one day, and 47 of 48 sampled sids had ZERO goal_status lines). Both readers below
# were written as `grep … | jq …` and both consumers run `set -o pipefail`. grep's NO-MATCH exit is
# 1, so under pipefail the pipeline's status is 1 no matter how well jq did, `|| return 1` fires,
# and the commonest state on this box — a session that never armed a goal — was reported as
# UNREADABLE. That is precisely the laundering this file's header forbids, in the other direction:
# `absent` is a POSITIVE finding and a failure must not wear it, but neither may the positive
# finding be dressed up as a failure. `goal-inert-watch.sh` logged `goal-unreadable` 375× for a
# transcript it had read perfectly.
#
# THREE OUTCOMES, NOT TWO, and that is why `|| true` on the whole pipeline is the wrong fix:
#   grep matched (rc 0)      → hand jq the hits                     → jq decides
#   grep did not match (rc 1)→ hand jq NOTHING; `--slurp` makes []  → the readers report `absent`
#   grep ERRORED   (rc ≥ 2)  → unreadable, and it must stay rc 1 at the caller
# A bare `|| true` collapses the third into the second and would report a file grep could not even
# open as "this session never armed a goal". So the helper neutralises ONLY the no-match status.
# jq's own failure (a corrupt record among the hits) still fails the pipeline under pipefail and
# still returns 1 — the "grep succeeded but jq failed" rc the fix is required to preserve.
_goal_grep() { # $1 = transcript path → matching lines on stdout; rc 0 = grep RAN, 1 = grep ERRORED
  local _gg_rc
  grep -a 'goal_status' "$1" 2>/dev/null
  _gg_rc=$?
  [ "$_gg_rc" -le 1 ] && return 0
  return 1
}

goal_live_condition() { # $1 = transcript path → prints the condition; rc 0 iff a /goal is LIVE
  local tp="$1" rec
  [ -n "$tp" ] || return 1
  case "$tp" in "~"*) tp="$HOME${tp#\~}" ;; esac
  [ -f "$tp" ] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  rec="$(_goal_grep "$tp" | jq -rc --slurp '
    [ .[] | select(.type == "attachment")
          | .attachment | select(.type == "goal_status") ] | last // empty' 2>/dev/null)" || return 1
  [ -n "$rec" ] || return 1
  [ "$(printf '%s' "$rec" | jq -r '(.met // false) or (.failed // false)' 2>/dev/null)" = "false" ] || return 1
  printf '%s' "$(printf '%s' "$rec" | jq -r '.condition // ""' 2>/dev/null)"
  return 0
}

# ── THE LIVENESS ORACLE (E5, docs/research/goal-safe-2way-comms-2026-08-13.md §8/§9 B5) ──────────
#
# `goal_live_condition` answers "is a goal armed?" — the predicate every SUPPRESSOR needs. It
# cannot answer the question §2 could not answer retrospectively: **is that armed goal being
# EVALUATED?** Both poles look identical to it. A goal deferred behind real in-flight work (A2
# working as designed) and a goal starved for hours behind a parked watcher are both simply "live".
# Measured across the fleet, 47 of 84 goal sessions had ZERO evaluations and the decomposition was
# "retrospectively unknowable" — evaluation-liveness had no oracle, so the residual could not be
# measured before OR after a fix.
#
# The oracle is one count and one verdict, and both are already in the transcript: CC writes a
# `goal_status` ATTACHMENT for the arm (`sentinel:true`) and one for every evaluation the tool-less
# evaluator LLM makes (no sentinel). So `evals` = non-sentinel records SINCE THE LAST ARM, and
# `last` = what the most recent record said. `0 evals` on a goal armed an hour ago is the
# starvation pole, visible AT THE CLOSE instead of in a 3-day corpus sweep.
#
# ⚠ SAME TWO TRAPS as the predicate above, for the same reasons: `type=="attachment"` filters the
# assistant's own PROSE about goals (6 hits where the truth was 1), and the record dictionary is
# the one documented in this file's header — LAST record wins, in both directions.
#
# COUNTED SINCE THE LAST ARM, never over the whole file: a session that armed, met, and re-armed a
# goal is on its SECOND goal, and carrying the first goal's evaluations into the second's count
# would report a healthy number over a goal that has never been judged — the exact false negative
# this exists to remove.
#
# FAIL DIRECTION differs from the predicate's, because the consumer differs. This one REPORTS; it
# suppresses nothing and gates nothing. So a failure must be legible as a failure (rc 1 ⇒ the
# consumer prints "unknown"), never as `absent` — which is a POSITIVE finding ("this session never
# armed a goal") and would launder an unreadable transcript into a clean bill of health.
goal_liveness() { # $1 = transcript path → TSV: state \t evals \t last \t epoch \t condition; rc 1 = unreadable
  local tp="$1" out
  [ -n "$tp" ] || return 1
  case "$tp" in "~"*) tp="$HOME${tp#\~}" ;; esac
  [ -f "$tp" ] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  # grep first for the same reason as above (keep the slurp off multi-MB transcripts); one jq for
  # all five fields, because this runs on a close path and a field-per-fork would cost five.
  out="$(_goal_grep "$tp" | jq -rc --slurp '
    [ .[] | select(.type == "attachment")
          | select((.attachment.type // "") == "goal_status")
          | { sentinel: (.attachment.sentinel // false),
              met:      (.attachment.met // false),
              failed:   (.attachment.failed // false),
              cond:     (.attachment.condition // ""),
              t:        (.timestamp // .attachment.timestamp // "") } ] as $r
    | if ($r | length) == 0 then "absent\t0\tnone\t0\t"
      else
        # the LAST arm marker (sentinel ∧ ¬met); `/goal clear` is sentinel ∧ met and is NOT one.
        ([ $r | to_entries[] | select(.value.sentinel and (.value.met | not)) | .key ] | last) as $arm
        | (if $arm == null then 0 else $arm + 1 end) as $from
        | [ $r[$from:][] | select(.sentinel | not) ] as $evals
        | ($r | last) as $z
        | (if   $z.failed then "failed" elif $z.met then "cleared" else "live" end) as $state
        | (if   $z.sentinel and ($z.met | not) then "arm"
           elif $z.failed                      then "failed"
           elif $z.sentinel and $z.met         then "clear"
           elif $z.met                         then "met"
           else                                     "unmet" end) as $last
        # ISO-8601 with fractional seconds is NOT fromdateiso8601-parseable — CC writes
        # "…:01.234Z", so the sub is load-bearing. An unparseable stamp ⇒ 0 ⇒ the consumer says
        # "time unknown"; it never becomes a wrong clock.
        | (if ($z.t | length) == 0 then 0
           else (try ($z.t | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601) catch 0) end) as $epoch
        | [ $state, ($evals | length | tostring), $last, ($epoch | tostring),
            ($z.cond | tostring | gsub("[\\t\\r\\n]"; " ")) ] | @tsv
      end' 2>/dev/null)" || return 1
  [ -n "$out" ] || return 1
  printf '%s' "$out"
  return 0
}
