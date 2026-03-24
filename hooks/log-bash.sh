#!/bin/bash
INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
EXIT=$(echo "$INPUT" | jq -r '.tool_result.exitCode // 0')
mkdir -p ~/.claude/logs
echo "[$(date '+%Y-%m-%d %H:%M:%S')] $CMD | Exit: $EXIT" >> ~/.claude/logs/bash-execution.log
exit 0
