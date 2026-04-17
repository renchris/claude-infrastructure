#!/bin/bash
# PostToolUse hook — Phase 0 / Agent Teams guard for plan files
# Non-blocking (exit 0 always). Warns strongly if Phase 0 / Agent Team Orchestration
# is missing from implementation plans. Agent Teams are the DEFAULT for all
# implementation work (user expects 9/10 sessions to use Agent Teams).

set -uo pipefail

command -v jq &>/dev/null || exit 0

INPUT=$(cat)
FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_result.filePath // empty')

[ -z "$FILE" ] && exit 0
[ ! -f "$FILE" ] && exit 0

# === PLAN FILE DETECTION (must match backup-before-write.sh exactly) ===
IS_PLAN=false
case "$FILE" in
  "$HOME/.claude/plans/"*.md)                    IS_PLAN=true ;;
  *"/.claude-plans/"*.md)                        IS_PLAN=true ;;
  *"/docs/plans/"*.md)                           IS_PLAN=true ;;
  docs/plans/*.md)                               IS_PLAN=true ;;
  *"/AGENT_TEAM_IMPLEMENTATION_PLAN"*.md)        IS_PLAN=true ;;
esac

[ "$IS_PLAN" = false ] && exit 0

# === PHASE 0 CHECK ===
# Warn if file has 2+ sections (any structured plan with multiple tasks)
SECTION_COUNT=$(grep -c "^## \|^### " "$FILE" 2>/dev/null || echo "0")
[ "$SECTION_COUNT" -lt 2 ] && exit 0

# Check if this looks like an implementation plan (has phases, tasks, or implementation keywords)
IS_IMPL=false
if grep -qEi "Phase [1-9]|Implementation|Wave [1-9]|Task [1-9]|Sprint|Milestone" "$FILE" 2>/dev/null; then
  IS_IMPL=true
fi

if [ "$IS_IMPL" = true ] && ! grep -qEi "Phase 0|Agent Team Orchestration|Team Orchestration|Pre-Flight Checklist|Team Roster" "$FILE" 2>/dev/null; then
  BASENAME=$(basename "$FILE")
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": "⚠️ AGENT TEAMS REQUIRED [${BASENAME}]: This implementation plan has NO Phase 0 / Agent Team Orchestration. Per CLAUDE.md: Agent Teams are the DEFAULT for all implementation work (9/10 sessions). Add Phase 0 as the FIRST section with: team roster, task dependency graph, worktree assignments, spawn wave order. Only omit for purely research/exploration plans with no code changes. Use the plan-update skill 'Phase 0' template."
  }
}
EOF
fi

exit 0
