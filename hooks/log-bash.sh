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
# D-3 RECURRENCE (2026-09-04, measured with a positive control inside one headless run). The D-3 fix
# above renamed `.tool_result` → `.tool_response` and stopped there, but BOTH halves were still wrong:
#   (a) There is no `exitCode` on `.tool_response` either. The real success payload is
#       {stdout, stderr, interrupted, isImage, noOutputExpected} — so the `// 0` default kept winning.
#   (b) A FAILING tool never reaches PostToolUse at all: the harness dispatches PostToolUseFailure
#       INSTEAD of it (`echo control-ok` → PostToolUse; `false` → PostToolUseFailure and NO
#       PostToolUse), and that payload carries `.error` ("Exit code 1") with no tool_response.
# Consequence, measured on the live log: 37,319 `Exit:` fields over 9 days, every one of them `0`.
# Line 2's "REAL exit code" had never once been true. So derive it from the EVENT, not a field:
#   PostToolUse        ⇒ the tool succeeded by construction ⇒ 0
#   PostToolUseFailure ⇒ parse `.error`; KEEP its text when it is not an exit code (interrupt,
#                        timeout), because "Interrupted" is information a coerced 1 would destroy.
# Registration is the other half: PostToolUseFailure must be wired alongside PostToolUse/Bash or this
# branch is unreachable and the log stays a success-only sample. See settings-templates/.
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
SID=$(printf '%s' "$INPUT" | jq -r '.session_id // "-"' 2>/dev/null)
EVT=$(printf '%s' "$INPUT" | jq -r '.hook_event_name // empty' 2>/dev/null)
if [ "$EVT" = "PostToolUseFailure" ]; then
  ERR=$(printf '%s' "$INPUT" | jq -r '.error // empty' 2>/dev/null)
  ERR=${ERR//$'\n'/ }                            # the audit line must stay single-line
  case "$ERR" in
    'Exit code '*) EXIT="${ERR#Exit code }" ;;
    '')            EXIT="fail" ;;                # failed, cause unstated — never launder this to 0
    *)             EXIT="$ERR" ;;                # e.g. "Interrupted", a timeout, a tool-side error
  esac
else
  EXIT=0
fi
[ -n "$SID" ] || SID="-"
[ -n "$EXIT" ] || EXIT="fail"
mkdir -p ~/.claude/logs
echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] [$SID] $CMD | Exit: $EXIT" >> ~/.claude/logs/bash-execution.log
exit 0
