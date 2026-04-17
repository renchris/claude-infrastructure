#!/bin/bash
# PreToolUse hook — injects "Agent Teams = default" context BEFORE plan files are written/edited.
# Non-blocking (permissionDecision: allow). Fires only for plan file paths.
# This ensures the model has Agent Teams guidance in context before writing any plan.

set -uo pipefail

command -v jq &>/dev/null || exit 0

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

[ -z "$FILE" ] && exit 0

# === PLAN FILE DETECTION ===
IS_PLAN=false
case "$FILE" in
  "$HOME/.claude/plans/"*.md)                    IS_PLAN=true ;;
  *"/.claude-plans/"*.md)                        IS_PLAN=true ;;
  *"/docs/plans/"*.md)                           IS_PLAN=true ;;
  docs/plans/*.md)                               IS_PLAN=true ;;
  *"/AGENT_TEAM"*".md")                          IS_PLAN=true ;;
  *"PLAN"*".md")                                 IS_PLAN=true ;;
  *"plan"*".md")                                 IS_PLAN=true ;;
esac

[ "$IS_PLAN" = false ] && exit 0

# Check if this is an implementation plan (not just a research doc named "plan")
# Look for implementation keywords in the file content if it exists
if [ -f "$FILE" ]; then
  if ! grep -qEi "Phase [1-9]|Implementation|Wave [1-9]|Task [1-9]|Sprint|Milestone|Team|Teammate" "$FILE" 2>/dev/null; then
    # New plan file (doesn't exist yet) or no implementation keywords — still inject context
    # because the model is about to write implementation content
    :
  fi
fi

cat <<'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "additionalContext": "AGENT TEAMS DEFAULT: This is a plan file. Agent Teams are the standard workflow for ALL implementation tasks with 2+ code-writing tasks. Include Phase 0 (Agent Team Orchestration) as the FIRST section: team roster, task dependency graph, worktree assignments, spawn wave order. Only use background subagents for research/exploration (no code changes). Reference: memory/agent-teams-hardened-playbook.md for pre-flight checklist and lifecycle."
  }
}
EOF
