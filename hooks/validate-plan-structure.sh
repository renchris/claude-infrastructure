#!/bin/bash
# PostToolUse hook — minimal Phase 0 guard for plan files
# Non-blocking (exit 0 always). Warns only if Phase 0 / Agent Team Orchestration is missing.
# Per d6 tradeoff analysis: minimal validation only. Full structural checks deferred
# until empirical failure pattern emerges (zero incidents since PreToolUse added).

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
# Only warn if file has 3+ sections (structured multi-phase plan, not a simple doc)
SECTION_COUNT=$(grep -c "^## \|^### " "$FILE" 2>/dev/null || echo "0")
[ "$SECTION_COUNT" -lt 3 ] && exit 0

if ! grep -qEi "Phase 0|Agent Team Orchestration|Team Orchestration|Pre-Flight Checklist" "$FILE" 2>/dev/null; then
  BASENAME=$(basename "$FILE")
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": "PLAN VALIDATION [${BASENAME}]: No Phase 0 / Agent Team Orchestration section found. Per CLAUDE.md Plan Document Conventions, the first upcoming section must cover: team size, roles, task dependencies, worktree assignments, spawn wave order."
  }
}
EOF
fi

exit 0
