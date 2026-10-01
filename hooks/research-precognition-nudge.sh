#!/bin/bash
# UserPromptSubmit — pre-cognition nudge for breadth-first RESEARCH fan-outs.
#
# Why: the research-subagents anti-under-spawn discipline works by shaping cognition BEFORE the model
# picks a subagent count. The agent-teams-enforce hook injects the research-subagents pointer at the
# Agent SPAWN — which is too late for the count-choice (the count is already chosen). This hook fires
# on the USER PROMPT, so the decompose-before-count reminder PRECEDES the model's fan-out cognition.
# The full detail still lives in the research-subagents skill; this is the resident forcing-function's
# reach into ad-hoc research that never goes through the /research command. Advisory only (never blocks).
#
# RE-ASK ROUTER (wave B1, REPORT.md §4.1 and §8 item 5; docs/plans/RESEARCH_PROGRAM_BUILD.md).
# Before the nudge: when the session resolves to a research program in state `certifying` or
# `certified`, every genuine prompt is classified into one route (scripts/research-kit/router.py
# `prompt`) and the turn's label is recorded for hooks/research-block.sh and the relay check in
# hooks/completion-assert.sh. Two keys, in order: the working directory, then a program's slug or
# alias named in the prompt. There is NO single-active fallback (§10 open item 2): a pane that
# resolves by neither key is not a program session and is left exactly as before. A routed prompt
# replaces the fan-out nudge below, which would contradict the block. Kill switch (operator, at
# launch): CC_RESEARCH_ROUTER=off. The classifier waits at most 6 s (§4.1), inside the 10 s timeout
# migrations/0050 registers.
set -uo pipefail
command -v jq &>/dev/null || exit 0
INPUT=$(cat)
PROMPT=$(printf '%s' "$INPUT" | jq -r '.prompt // .user_prompt // empty' 2>/dev/null || echo "")
[ -z "$PROMPT" ] && exit 0

if [ "${CC_RESEARCH_ROUTER:-}" != off ] && [ -z "${CC_RESEARCH_ROUTER_INNER:-}" ]; then
  _here="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
  _rl="$_here/lib/research-router.sh"
  [ -f "$_rl" ] || { _t="$0"; [ -L "$_t" ] && _t="$(readlink "$_t")"; _rl="$(cd "$(dirname "$_t")" 2>/dev/null && pwd)/lib/research-router.sh"; }
  [ -f "$_rl" ] || _rl="$HOME/.claude/hooks/lib/research-router.sh"
  # shellcheck source=lib/research-router.sh
  # shellcheck disable=SC1091  # runtime-resolved source; the ship gate runs shellcheck without -x
  if [ -f "$_rl" ] && . "$_rl" 2>/dev/null && rr_registry_present && rr_init "$0"; then
    _cwd="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)"
    _by=cwd
    _res=""
    [ -n "$_cwd" ] && _res="$(rp_resolve_cwd "$_cwd" 2>/dev/null)"
    if [ -z "$_res" ]; then _by=prompt; _res="$(rp_resolve_prompt "$PROMPT" 2>/dev/null)"; fi
    _out="$(printf '%s' "$INPUT" | /usr/bin/env python3 "$RR_ROUTER" prompt \
              --program "${_res%% *}" --state "${_res##* }" --by "$_by" 2>/dev/null)"
    if [ -n "$_out" ]; then printf '%s\n' "$_out"; exit 0; fi
    case "${_res##* }" in certifying|certified) exit 0 ;; esac   # routed silently (work-order)
  fi
fi

# Strong breadth-first research-INTENT markers (multi-word; deliberately avoids firing on a generic
# "find"/"check"/"look at"). Over-firing is cheap + self-scoping (the message says "IF a fan-out");
# under-firing is the real risk this guards.
INTENT='research (the|how|what|whether|options|approaches|design)|explore the design space|design space of|all angles on|how (can|should|do|might) (we|i|you) (improve|approach|design|optimi[sz]e)|fan.?out|spawn .*(research|subagents)|survey the|comprehensive(ly)? (audit|review|research)|multi-axis|breadth.first|/research|what are (all )?(the )?(options|approaches|ways|angles|tradeoffs)'
if printf '%s' "$PROMPT" | grep -qiE "$INTENT"; then
  cat <<'EOF'
{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"RESEARCH-INTENT PRE-COGNITION: if this resolves to a breadth-first research fan-out, DECOMPOSE before counting — render the pre-spawn decomposition table (one row per distinct axis -> sub-questions) and read the subagent count OFF it. Default N=10 (band 8-12); never start from a number; no parallelism cap. A depth-first single-subsystem question is single-agent instead. Load the research-subagents skill for the full discipline (question-type gate, named-entity audit, 7-field briefs INCLUDING the mandatory field 7 Delivery — name the absolute artifact path each subagent WRITES, because a subagent's prose is invisible and only a file is delivered, 15-20% adversarial floor, OASIS stop)."}}
EOF
fi
exit 0
