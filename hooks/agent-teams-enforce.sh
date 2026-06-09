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

# Teammate spawns (team_name set) MUST use a Max-plan auto-mode-allowlisted model.
# Allowlist is read from the SSOT (~/.claude/model-config.yaml
# .auto_mode_allowlist.non_firstParty_max — claude-opus-4-8 as of 2026-06-09) so
# this hook can never drift from a model bump again (pre-2026-06-09 it hardcoded
# opus-4-7 and would have rejected the swept 4-8 manifests). Off-allowlist models
# silent-demote to acceptEdits and break team parallelism. Teams run BOTH launcher
# tracks (stable 2.1.114 + claude-next eval); frontier models (claude-fable-5)
# become teammate-eligible the moment they're verified into the SSOT allowlist —
# until then they risk silent auto-mode demotion, so they're denied here. Blocks
# the 2026-04-17 failure mode (stale plan hardcoding Sonnet for "mechanical"
# teammates).
# Rule: memory/feedback-agent-team-models.md + model-upgrade skill.
if [ -n "$TEAM_NAME" ] && [ -n "$MODEL" ]; then
  ALLOWED=$(yq -r '.auto_mode_allowlist.non_firstParty_max[]' "$HOME/.claude/model-config.yaml" 2>/dev/null)
  [ -n "$ALLOWED" ] || ALLOWED="claude-opus-4-8"   # fallback if yq/config unavailable
  ALLOWED_FLAT=$(echo "$ALLOWED" | tr '\n' ' ')
  MODEL_BASE="${MODEL%%\[*}"                        # strip [1m]-style suffixes
  ALLOW_OK=0
  case "$MODEL_BASE" in
    *-*)  # full model ID — must match an allowlisted ID exactly
      for m in $ALLOWED; do
        [ "$MODEL_BASE" = "$m" ] && ALLOW_OK=1
      done
      ;;
    *)    # bare family alias (opus, fable, …) — allowed iff the allowlist
          # contains a model of that family (alias resolves to it)
      for m in $ALLOWED; do
        case "$m" in claude-"$MODEL_BASE"-*) ALLOW_OK=1 ;; esac
      done
      ;;
  esac
  if [ "$ALLOW_OK" -ne 1 ]; then
    cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Teammate spawn rejected: model='$MODEL' is not on the Max-plan auto-mode allowlist (${ALLOWED_FLAT}). Use model='opus' (alias) or an allowlisted ID for all teammates. Off-allowlist models silent-demote to acceptEdits and break team parallelism. Frontier models (claude-fable-5) become teammate-eligible only after verification into the SSOT allowlist (~/.claude/model-config.yaml auto_mode_allowlist.non_firstParty_max) — verify with one test spawn on the eval track, then append it there; this hook follows the SSOT automatically. Rule: memory/feedback-agent-team-models.md."
  }
}
EOF
    exit 0
  fi
fi

# If team_name is set (with valid or absent model), this is an Agent Team — allow silently
[ -n "$TEAM_NAME" ] && exit 0

# If this is a known read-only subagent type, allow silently
case "$SUBAGENT_TYPE" in
  Explore|Plan|claude-code-guide|fresh-eyes-evaluator|north-star-design-agent|visual-design-iterator) exit 0 ;;
esac

# === RESEARCH ESCAPE HATCH ===
# Strong research-only markers override the keyword heuristic. Lead prepends
# any of these phrases to a research-only prompt to bypass false-positives
# (e.g. research about "schema", "migration mechanics", "Phase 0 patterns"
# was previously blocked because those words triggered the impl regex).
# Discriminator is the EXPLICIT marker, not the topic.
RESEARCH_MARKERS='READ[- ]ONLY RESEARCH|RESEARCH[- ]ONLY|NO (FILES|CODE)( WILL BE)? (WRITTEN|MODIFIED|CREATED)|WRITES? NOTHING (TO|ON) DISK|Tool budget:[[:space:]]*(Read|Glob|Grep|WebFetch|WebSearch|,|[[:space:]])+|Tool use limited to:[[:space:]]*(Read|Glob|Grep|WebFetch|WebSearch|,|[[:space:]])'
if echo "$PROMPT" | grep -qEi "$RESEARCH_MARKERS"; then
  exit 0
fi

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
