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
# launch): CC_RESEARCH_ROUTER=off. The classifier waits at most 9 s (§4.1, ruling 4bf73c4e55d5), inside the 10 s timeout
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
    # One jq parse yields the cwd and the session id, \x1f-separated (the hooks/research-block.sh
    # idiom): a non-whitespace IFS keeps an empty cwd from shifting the fields, and a session id that
    # is neither a string nor absent prints _sidt=o, which never takes the fast exit below.
    _fields="$(printf '%s' "$INPUT" | jq -r '[(.cwd // "" | tostring),
      (.session_id | if type == "string" then "s" elif . == null then "n" else "o" end),
      (.session_id | if type == "string" then . else "" end)] | join("\u001f")' 2>/dev/null)" && _parsed=1 || _parsed=0
    IFS=$'\x1f' read -r _cwd _sidt _sid <<EOF
$_fields
EOF
    _by=cwd
    _res=""
    [ -n "$_cwd" ] && _res="$(rp_resolve_cwd "$_cwd" 2>/dev/null)"
    if [ -z "$_res" ]; then _by=prompt; _res="$(rp_resolve_prompt "$PROMPT" 2>/dev/null)"; fi
    # FAST EXIT (docs/research/load-hook-timeouts-2026-10-11 item 7): with no program resolved,
    # router.py `prompt` does one thing — route_clear(<sid>) for a genuine prompt, nothing for a
    # machine envelope — and prints nothing. So when the session also has NO route record the router
    # is a no-op, and that is every prompt of every session outside a program, on a machine whose
    # registry exists: one python3 start per prompt saved. A session that DOES carry a record still
    # goes to the router, which alone knows the genuine/envelope split (MACHINE_ENVELOPE) that decides
    # whether the record is cleared. The record's name is router.py route_path() — sid with
    # [^A-Za-z0-9_.-] → _, cut at 128, "unknown" when empty — and, as in research-block.sh, the exit is
    # taken only for a sid that sanitizer leaves unchanged, so the two cannot drift.
    _rr_no_route() { # $1=sid → rc 0 iff the sid is sanitizer-stable and has no route record
      local LC_ALL=C s="${1:-unknown}"   # byte ranges: a locale must not widen A-Z past ASCII
      case "$s" in *[!A-Za-z0-9_.-]*) return 1 ;; esac
      [ "${#s}" -le 128 ] || return 1
      [ ! -e "${CC_RESEARCH_HOME:-$HOME/.claude/autonomy/research}/route-state/$s.json" ]
    }
    if [ -n "$_res" ] || [ "$_parsed" != 1 ] || [ "$_sidt" = o ] \
      || [ "${_fields#*$'\n'}" != "$_fields" ] || ! _rr_no_route "$_sid"; then
      _out="$(printf '%s' "$INPUT" | /usr/bin/env python3 "$RR_ROUTER" prompt \
                --program "${_res%% *}" --state "${_res##* }" --by "$_by" 2>/dev/null)"
      if [ -n "$_out" ]; then printf '%s\n' "$_out"; exit 0; fi
    fi
    case "${_res##* }" in certifying|certified|build-certifying|build-certified|implementation-signed) exit 0 ;; esac   # routed silently (work-order)
  fi
fi

# A harness-injected <task-notification> is a machine prompt, not a human's intent: this nudge fired
# on 60 of 90 machine prompts (docs/research/startup-hooks-2026-10-18/A9-beyond-startup.md, "What this
# axis missed" 2), against the adopted rule "early exit on <task-notification> prompts for
# human-intent nudges" (docs/research/load-hook-timeouts-2026-10-11/DESIGN.md). Placed AFTER the
# router, which must still see machine envelopes. Anchored regex, as in handoff-intent-nudge.sh.
_rp_tn='^[[:space:]]*<task-notification>'
[[ $PROMPT =~ $_rp_tn ]] && exit 0

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
