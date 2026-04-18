#!/bin/bash
# PreToolUse hook on Agent tool — enforces Agent Teams for implementation tasks.
#
# DENY: Background subagents with implementation keywords (code-writing) are blocked.
#       Model receives clear instructions to retry with team_name set.
# ALLOW+NUDGE: Foreground agents without team_name get a reminder.
# ALLOW SILENT: Agents with team_name, known read-only types, research prompts.

set -uo pipefail

command -v jq &>/dev/null || exit 0

INPUT=$(cat)

# Extract Agent tool parameters
TEAM_NAME=$(echo "$INPUT" | jq -r '.tool_input.team_name // empty')
RUN_BG=$(echo "$INPUT" | jq -r '.tool_input.run_in_background // false')
PROMPT=$(echo "$INPUT" | jq -r '.tool_input.prompt // empty')
SUBAGENT_TYPE=$(echo "$INPUT" | jq -r '.tool_input.subagent_type // empty')
MODEL=$(echo "$INPUT" | jq -r '.tool_input.model // empty')

# Teammate spawns (team_name set) MUST use claude-opus-4-7 on Max plan.
# Max-plan auto-mode allowlist is claude-opus-4-7 ONLY — Sonnet 4.6 and older
# Opus silent-demote to acceptEdits and break team parallelism. Blocks the
# 2026-04-17 failure mode where a lead followed a stale plan that hardcoded
# Sonnet for "mechanical" teammates. Rule: memory/feedback-agent-team-models.md.
if [ -n "$TEAM_NAME" ] && [ -n "$MODEL" ]; then
  case "$MODEL" in
    claude-opus-4-7|claude-opus-4-7\[*|opus)
      : ;;  # allowed — current Opus 4.7, [1m] variant, or alias
    *)
      cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Teammate spawn rejected: model='$MODEL' is not on the Max-plan auto-mode allowlist. Use model='claude-opus-4-7' (or 'opus' alias) for all teammates. Anything else silent-demotes to acceptEdits and breaks team parallelism. Rule: memory/feedback-agent-team-models.md — universal Opus 4.7 on Max plan."
  }
}
EOF
      exit 0
      ;;
  esac
fi

# If team_name is set (with valid or absent model), this is an Agent Team — allow silently
[ -n "$TEAM_NAME" ] && exit 0

# If this is a known read-only subagent type, allow silently
case "$SUBAGENT_TYPE" in
  Explore|Plan|claude-code-guide|fresh-eyes-evaluator|north-star-design-agent|visual-design-iterator) exit 0 ;;
esac

# Check if the prompt contains implementation keywords (case-insensitive)
IMPL_KEYWORDS="implement|create.*file|write.*code|modify|refactor|add.*column|schema|migration|build.*component|fix.*bug|update.*file|delete.*file|edit.*file|new.*route|new.*component|add.*feature|deploy|seed|generate|write.*test|create.*component|add.*hook"
RESEARCH_KEYWORDS="research|explore|investigate|find|search|analyze|audit|verify|check|review|read|look|scan|inspect|evaluate|fetch|report|list|summarize|compare"

# Count implementation vs research keyword matches
IMPL_COUNT=$(echo "$PROMPT" | grep -oEi "$IMPL_KEYWORDS" 2>/dev/null | wc -l | tr -d ' ')
RESEARCH_COUNT=$(echo "$PROMPT" | grep -oEi "$RESEARCH_KEYWORDS" 2>/dev/null | wc -l | tr -d ' ')

# If clearly research-oriented (more research keywords than implementation), allow silently
if [ "$RESEARCH_COUNT" -gt "$IMPL_COUNT" ] && [ "$IMPL_COUNT" -le 1 ]; then
  exit 0
fi

# DENY: Background subagent with implementation keywords — block and redirect to Agent Teams
if [ "$RUN_BG" = "true" ] && [ "$IMPL_COUNT" -ge 2 ]; then
  cat <<'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Background subagents cannot write code. Implementation tasks require Agent Teams for visibility and coordination. To proceed: use TeamCreate first, then spawn agents with team_name parameter set (e.g., team_name='implementation-wave-1'). You ARE authorized to use Agent Teams — this constraint exists to ensure parallel work is coordinated safely. If this task is purely research/exploration with no code changes, rephrase the prompt to clarify."
  }
}
EOF
  exit 0
fi

# ALLOW+NUDGE: Foreground agent without team_name that looks like implementation
if [ "$IMPL_COUNT" -ge 2 ]; then
  cat <<'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "additionalContext": "AGENT TEAMS DEFAULT: This agent spawn involves code changes but has no team_name. Per global rules, ALL implementation tasks with 2+ code-writing tasks MUST use Agent Teams (TeamCreate + team_name + worktree isolation). Only research/exploration subagents should run without team_name. You ARE authorized to use Agent Teams."
  }
}
EOF
  exit 0
fi

# Default: allow silently (ambiguous or single-keyword cases)
exit 0
