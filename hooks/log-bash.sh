#!/bin/bash
# log-bash.sh — PostToolUse(Bash) audit line: ISO timestamp · session id · command · REAL exit code.
#
# D-3 (audit 09): this hook read `.tool_result.exitCode`. The PostToolUse payload field is
# `.tool_response`, so the `// 0` default always won and EVERY line in bash-execution.log read
# `Exit: 0` — including for commands that failed. Session attribution was missing entirely, so
# nothing in a 13 MB log was greppable by session. `.session_id` is a first-class stdin field
# (22 hooks in this repo already read it, e.g. hooks/completion-assert.sh:54) — never
# CLAUDE_SESSION_ID, which CC does not export to hooks (D-9).
# Builtin read, NOT `$(cat)`: command substitution forks AND execs /bin/cat on the hottest path
# in the system (this hook fires on EVERY Bash tool call). Measured 2026-07-31: ~6 ms per hook,
# ~18% of the 163 ms PreToolUse/Bash chain across the five hooks that did this. `read -d ''`
# returns non-zero at EOF -- the normal case here -- hence `|| true`; it also PRESERVES the
# trailing newline that `$(cat)` strips, so strip it back off for byte-parity with the old value.
IFS= read -r -d '' INPUT || true
while [ "${INPUT%$'\n'}" != "${INPUT}" ]; do INPUT="${INPUT%$'\n'}"; done
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
EXIT=$(printf '%s' "$INPUT" | jq -r '.tool_response.exitCode // 0' 2>/dev/null)
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // "-"' 2>/dev/null)
[ -n "$SID" ] || SID="-"
[ -n "$EXIT" ] || EXIT=0
mkdir -p ~/.claude/logs
echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] [$SID] $CMD | Exit: $EXIT" >> ~/.claude/logs/bash-execution.log
exit 0
