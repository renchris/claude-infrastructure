#!/usr/bin/env bats
# bash-audit-attrib — session attribution + true exit codes for the two per-Bash-call audit logs
# (audit 09 D-3). Both writers were forensically useless: `hooks/log-bash.sh` read the WRONG
# payload field (`.tool_result` — the PostToolUse field is `.tool_response`), so the `// 0`
# default always won and every line read `Exit: 0` even for failures; `hooks/validate-bash.sh`
# appended the raw command with no timestamp and no session id, so nothing was greppable by
# session and a multi-line command shredded the line structure.
#
# Harness laws: L1 every fixture payload is the LITERAL PostToolUse/PreToolUse shape Claude Code
# emits (`.session_id` is a first-class field — 22 hooks already read it, e.g.
# hooks/completion-assert.sh:54); L2 assertions key on failure-DISTINCT strings (a nonzero exit
# code, the sid) so the pre-change code goes RED; L3 every assertion is `[ ]` / `grep -q`; L4
# both a failing and a succeeding command are fixtured, so an "always print nonzero" bug fails too.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LOG_BASH="$REPO/hooks/log-bash.sh"
  VALIDATE_BASH="$REPO/hooks/validate-bash.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/logs"
  EXEC_LOG="$HOME/.claude/logs/bash-execution.log"
  CMD_LOG="$HOME/.claude/logs/bash-commands.log"
}

# literal PostToolUse payload: `tool_response`, NOT `tool_result`
post_payload() { # <command> <exitCode> <session_id>
  jq -nc --arg c "$1" --argjson e "$2" --arg s "$3" \
    '{session_id:$s,hook_event_name:"PostToolUse",tool_name:"Bash",
      tool_input:{command:$c},tool_response:{stdout:"",stderr:"",exitCode:$e}}'
}

pre_payload() { # <command> <session_id>
  jq -nc --arg c "$1" --arg s "$2" \
    '{session_id:$s,hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c}}'
}

# ── log-bash.sh — the exit code must be REAL ────────────────────────────────────────────────
@test "log-bash records a NONZERO exit code from .tool_response" {
  post_payload 'grep -q nope /etc/hosts' 1 'sid-aaa' | bash "$LOG_BASH"
  [ -f "$EXEC_LOG" ]
  grep -q 'Exit: 1' "$EXEC_LOG"
}

@test "log-bash still records exit 0 for a succeeding command (not always-nonzero)" {
  post_payload 'true' 0 'sid-bbb' | bash "$LOG_BASH"
  grep -q 'Exit: 0' "$EXEC_LOG"
}

@test "log-bash attributes the line to the stdin session_id" {
  post_payload 'echo hi' 3 'sid-ccc' | bash "$LOG_BASH"
  grep -q 'sid-ccc' "$EXEC_LOG"
  grep -q 'Exit: 3' "$EXEC_LOG"
}

@test "log-bash falls back to '-' when the payload carries no session_id" {
  jq -nc '{hook_event_name:"PostToolUse",tool_input:{command:"echo x"},tool_response:{exitCode:7}}' \
    | bash "$LOG_BASH"
  grep -q '\[-\]' "$EXEC_LOG"
  grep -q 'Exit: 7' "$EXEC_LOG"
}

@test "log-bash line carries an ISO-8601 UTC timestamp" {
  post_payload 'echo iso' 0 'sid-ddd' | bash "$LOG_BASH"
  grep -qE '^\[[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\]' "$EXEC_LOG"
}

# ── validate-bash.sh — the audit line must be greppable by session ──────────────────────────
@test "validate-bash audit line carries timestamp + session id + the command" {
  pre_payload 'echo audited' 'sid-eee' | bash "$VALIDATE_BASH"
  [ -f "$CMD_LOG" ]
  grep -qE '^\[[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\] \[sid-eee\] echo audited$' "$CMD_LOG"
}

@test "validate-bash audit line uses '-' when no session_id is present" {
  jq -nc '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:"echo anon"}}' \
    | bash "$VALIDATE_BASH"
  grep -qE '\[-\] echo anon$' "$CMD_LOG"
}

@test "validate-bash still denies a catastrophic pattern (audit change is additive)" {
  payload="$(pre_payload 'sudo rm -rf /etc' 'sid-fff')"
  run bash "$VALIDATE_BASH" <<<"$payload"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"permissionDecision": "deny"'
}
