#!/bin/bash
# PreToolUse hook for Bash command validation
# Exit 0 with JSON to stdout for decisions, exit 2 for blocking errors

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Block dangerous commands
if echo "$CMD" | grep -qE '(rm -rf /|sudo rm|chmod 777|:(){ :|:& };:)'; then
  # Output decision JSON to stdout (per 2.1.11 spec)
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Dangerous command pattern blocked: potential system damage"
  }
}
EOF
  exit 0  # Exit 0 with JSON for controlled denial
fi

# Log command for audit
mkdir -p ~/.claude/logs
echo "$CMD" >> ~/.claude/logs/bash-commands.log
exit 0
