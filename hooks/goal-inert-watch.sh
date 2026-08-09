#!/usr/bin/env bash
# goal-inert-watch.sh — Stop hook: say so when an armed `/goal` is being SKIPPED by Claude Code.
#
# THE DEFECT (measured 2026-08-09, docs/research/goal-in-handoff-2026-08-08.md § RESOLVED).
# `/goal <condition>` registers a `type:"prompt"` Stop hook. The FIRST thing CC's Stop handler does
# is delete that hook again whenever the task registry holds non-terminal background work:
#
#     if(_We(B)||Tio(B)){ … i.sessionHooksRegistry.remove(kt(),"Stop",y),
#                         w("[goal] evaluation deferred — background work still running") }
#     … finally{ if(y) i.sessionHooksRegistry.add(kt(),"Stop","",y) }
#
# The `finally` puts it back, so the registry reads CORRECT before the Stop and CORRECT after it,
# and is wrong only DURING — the one moment nothing can observe. `Tio` fires on any non-terminal
# `local_bash` task, and this box tells every session to arm `cc-await-ping --timeout 14400` as a
# background Bash "before you go idle". That watcher is non-terminal for FOUR HOURS, so on this box
# an armed goal is inert by default: measured 2h / ~12 turns / 0 evaluations, and no log the
# operator ever sees. The deferral itself is CC's, is deliberate, and is not ours to fix — judging
# "is the objective met?" mid-flight would read an incomplete transcript and burn an LLM call per
# Stop. What IS ours is that the failure is silent. This hook is the compensating control: it makes
# the skip LOUD, from a hook we own, on the same Stop where the skip happens.
#
# ── FIRE PREDICATE ── all four, else silent:
#   1. stdin is a Stop payload carrying `background_tasks` (CC ships it — YTe @237761:
#      `{background_tasks: cip(i.taskRegistry.all()), session_crons: uip()}` spread into the input).
#   2. the transcript's LAST `goal_status` ATTACHMENT is a sentinel with met=false — i.e. a goal is
#      ARMED and has never been evaluated since. A non-sentinel last record means the evaluator IS
#      running (nothing to report); `sentinel:true, met:true` is the CLEAR marker (goal is gone).
#   3. ≥1 background task of a type CC's predicate counts AND whose carve-outs we can decide.
#   4. not damped (page-damp, keyed on the condition — a state, never a clock).
#
# ⚠️ TWO TRAPS THIS HOOK IS BUILT AROUND, both of which silently produce the WRONG answer:
#   (a) `background_tasks[].type` is the DISPLAY name, not the raw one. `F$o` @237760745 maps
#       local_bash→"shell", local_agent→"subagent", local_workflow→"workflow",
#       in_process_teammate→"teammate", remote_agent→"cloud session". A hook grepping `local_bash`
#       matches NOTHING and reports all-clear forever — the caller-census-keyed-on-path defect.
#   (b) a bare `grep goal_status` on a transcript matches the assistant's own PROSE about goals. On
#       the session that produced this finding it returned 6 hits where the truth was 1, which
#       nearly inverted the conclusion. Every read here filters `type == "attachment"` first.
#
# ── WHY WE ABSTAIN ON teammate / cloud session ──
#   `_We` excludes `in_process_teammate && isIdle` and `remote_agent && isLongRunning`. Neither flag
#   is in the `cip()` payload, so for those two types we CANNOT decide whether CC would defer. We
#   count only the three types with no carve-out (shell · subagent · workflow) — where the payload
#   is sufficient to reproduce CC's predicate exactly. Under-reporting is the correct direction: a
#   hook that cried "your goal is inert" at a session whose goal was fine would be trained around.
#   `shell` alone covers cc-await-ping, which is the entire observed cause.
#
# ── DELIVERY ── pure-advisory `{"systemMessage": …}`, NEVER `{decision:"block"}` and NEVER
#   `additionalContext`. Per CLAUDE.md § Session Close (measured on 2.1.220): additionalContext
#   DOES reach the model at Stop but FORCES another turn and increments the same consecutive-block
#   counter; systemMessage is the only Stop field that does not extend the turn. This hook informs,
#   it does not steer — it must not be able to hold a session open. Always exits 0.
#
# Tests: tests/goal-inert-watch.bats (incl. the display-name mutation — swap "shell" for
# "local_bash" and the fire case must go silent).
set -uo pipefail

_gi_abstain() { exit 0; }

input="$(cat 2>/dev/null || true)"
[ -n "$input" ] || _gi_abstain
command -v jq >/dev/null 2>&1 || _gi_abstain

# ── (1) a Stop payload, with the task list CC hands us ────────────────────────────────────────────
TP="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null || true)"
SID="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null || true)"
[ -n "$TP" ] || _gi_abstain
case "$TP" in "~"*) TP="$HOME${TP#\~}" ;; esac
[ -f "$TP" ] || _gi_abstain

# ── (3) deferring background work, by DISPLAY name, restricted to the decidable types ─────────────
# `cip()`'s producer `Gw()` already filters to status running|pending, so anything present here is
# non-terminal; the status re-check is belt-and-braces against a future payload change.
DEFERRERS="$(printf '%s' "$input" | jq -r '
  [ (.background_tasks // [])[]
    | select((.type // "") | IN("shell","subagent","workflow"))
    | select(((.status // "running") | IN("completed","failed","killed")) | not)
    | "\(.type): \(.command // .description // "-")" ] | .[]' 2>/dev/null || true)"
[ -n "$DEFERRERS" ] || _gi_abstain

# ── (2) an ARMED, never-evaluated goal ────────────────────────────────────────────────────────────
# grep narrows a possibly-huge transcript cheaply; jq then enforces type=="attachment" (trap b).
GOAL="$(grep -a 'goal_status' "$TP" 2>/dev/null | jq -rc --slurp '
  [ .[] | select(.type == "attachment")
        | .attachment | select(.type == "goal_status") ] | last // empty' 2>/dev/null || true)"
[ -n "$GOAL" ] || _gi_abstain

IS_SENTINEL="$(printf '%s' "$GOAL" | jq -r '.sentinel // false' 2>/dev/null || echo false)"
IS_MET="$(printf '%s' "$GOAL" | jq -r '.met // false' 2>/dev/null || echo false)"
# armed-and-unevaluated == the arm marker is still the most recent goal record.
[ "$IS_SENTINEL" = "true" ] && [ "$IS_MET" = "false" ] || _gi_abstain
COND="$(printf '%s' "$GOAL" | jq -r '.condition // ""' 2>/dev/null || true)"

# ── (4) damping — fingerprint is the STATE (the condition), never a clock ─────────────────────────
# Same resolution ladder the sibling Stop hooks use — hooks/ is symlinked into the live layer, so
# resolve beside the script first, then the configured layer, then $HOME. A missing lib degrades to
# UNDAMPED (fail-open), never to silent: losing a true warning is worse than repeating one.
_gscd="$(dirname "${BASH_SOURCE[0]}")"
_dampsh="$_gscd/lib/page-damp.sh"
[ -f "$_dampsh" ] || _dampsh="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/lib/page-damp.sh"
[ -f "$_dampsh" ] || _dampsh="$HOME/.claude/hooks/lib/page-damp.sh"
if [ -r "$_dampsh" ]; then
  # shellcheck source=lib/page-damp.sh
  # shellcheck disable=SC1091  # runtime-resolved source; the ship gate runs shellcheck without -x
  . "$_dampsh" 2>/dev/null || true
  if command -v damp_should_send >/dev/null 2>&1; then
    _fp="GOAL-INERT:$(printf '%s' "$COND" | cksum 2>/dev/null | tr -dc '0-9' || true)"
    damp_should_send "goal-inert-${SID:-unknown}" "$_fp" || _gi_abstain
  fi
fi

N="$(printf '%s\n' "$DEFERRERS" | grep -c . 2>/dev/null || echo 0)"
SHORT="$COND"; [ "${#SHORT}" -gt 120 ] && SHORT="${SHORT:0:117}..."

MSG="$(printf '%s\n' \
"⚠️  YOUR /goal IS NOT BEING EVALUATED — Claude Code skipped it at this Stop." \
"" \
"   goal (armed, 0 evaluations so far): \"$SHORT\"" \
"" \
"   CC deletes the goal's Stop hook whenever background work is live, then silently restores it," \
"   so the registry always LOOKS healthy. $N background task(s) are holding it off right now:" \
"$(printf '%s\n' "$DEFERRERS" | sed 's/^/     · /')" \
"" \
"   A 4-hour cc-await-ping watcher never settles, so the goal stays inert for as long as it runs." \
"   To keep a session going, use the mechanism we own — it is unaffected by this:" \
"     ~/.claude/hooks/session-continue.sh set \"<the ONE next step>\"" \
"   Detail: docs/research/goal-in-handoff-2026-08-08.md § RESOLVED 2026-08-09")"

jq -nc --arg m "$MSG" '{systemMessage:$m}' 2>/dev/null || true
exit 0
