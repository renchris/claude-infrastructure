#!/bin/bash
# UserPromptSubmit — pre-cognition nudge for breadth-first RESEARCH fan-outs.
#
# Why: the research-subagents anti-under-spawn discipline works by shaping cognition BEFORE the model
# picks a subagent count. The agent-teams-enforce hook injects the research-subagents pointer at the
# Agent SPAWN — which is too late for the count-choice (the count is already chosen). This hook fires
# on the USER PROMPT, so the decompose-before-count reminder PRECEDES the model's fan-out cognition.
# The full detail still lives in the research-subagents skill; this is the resident forcing-function's
# reach into ad-hoc research that never goes through the /research command. Advisory only (never blocks).
set -uo pipefail
command -v jq &>/dev/null || exit 0
INPUT=$(cat)
PROMPT=$(printf '%s' "$INPUT" | jq -r '.prompt // .user_prompt // empty' 2>/dev/null || echo "")
[ -z "$PROMPT" ] && exit 0

# Strong breadth-first research-INTENT markers (multi-word; deliberately avoids firing on a generic
# "find"/"check"/"look at"). Over-firing is cheap + self-scoping (the message says "IF a fan-out");
# under-firing is the real risk this guards.
INTENT='research (the|how|what|whether|options|approaches|design)|explore the design space|design space of|all angles on|how (can|should|do|might) (we|i|you) (improve|approach|design|optimi[sz]e)|fan.?out|spawn .*(research|subagents)|survey the|comprehensive(ly)? (audit|review|research)|multi-axis|breadth.first|/research|what are (all )?(the )?(options|approaches|ways|angles|tradeoffs)'
if printf '%s' "$PROMPT" | grep -qiE "$INTENT"; then
  cat <<'EOF'
{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"RESEARCH-INTENT PRE-COGNITION: if this resolves to a breadth-first research fan-out, DECOMPOSE before counting — render the pre-spawn decomposition table (one row per distinct axis -> sub-questions) and read the subagent count OFF it. Default N=10 (band 8-12); never start from a number; no parallelism cap. A depth-first single-subsystem question is single-agent instead. Load the research-subagents skill for the full discipline (question-type gate, named-entity audit, 6-field briefs, 15-20% adversarial floor, OASIS stop)."}}
EOF
fi
exit 0
