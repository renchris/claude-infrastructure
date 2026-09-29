#!/usr/bin/env bats
# validate-bash-agent-rm-deny.bats — inside a SUBAGENT (the PreToolUse payload carries a non-empty
# `agent_id`), an `rm -r` that would raise an ask is DENIED with a reason instead. Nobody can answer a
# prompt inside a subagent, so the ask stalls it; the reason tells it how to proceed without one.
# Main thread and pane teammates (no `agent_id` in the payload) keep the ask. Every other ask class is
# unchanged. Kill switch: CC_VB_AGENT_RM_DENY=off.
# Evidence and the verbatim reason: docs/research/hook-ask-confirmations-2026-09-28.md §7 (Round 5 —
# a "tell your lead" sentence made subagents stop without salvaging, so the reason carries none).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/validate-bash.sh"
  D="$BATS_TEST_TMPDIR"
  export HOME="$D/home"; mkdir -p "$HOME"
  unset KITTY_WINDOW_ID
  export IT2_WRAPPER_NO_KITTY=1
  export CC_SHARED_CHECKOUT="$D/shared"; mkdir -p "$D/shared"
  export CC_VB_DECISION_LOG="$D/decisions.jsonl"
  unset VALIDATE_BASH_LEGACY VALIDATE_BASH_DISABLED CC_VB_AGENT_RM_DENY
  if ! command -v jq >/dev/null 2>&1; then skip "jq not installed"; fi
}

# probe <command> [agent_id] — a PreToolUse payload; agent_id omitted ⇒ no key at all
probe() {
  run bash -c 'if [ -n "$2" ]; then
      jq -nc --arg c "$1" --arg a "$2" "{tool_name:\"Bash\", tool_input:{command:\$c}, session_id:\"sid-x\", agent_id:\$a}"
    else
      jq -nc --arg c "$1" "{tool_name:\"Bash\", tool_input:{command:\$c}, session_id:\"sid-x\"}"
    fi | "$0"' "$HOOK" "$1" "${2:-}"
}
decision() {
  if [ -z "$output" ]; then echo none; return; fi
  printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null || echo none
}
reason() { printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecisionReason'; }

REASON='Refused inside a subagent: no one can answer a prompt here. For a throwaway directory, create a fresh one in the same command: D=$(mktemp -d /tmp/<name>.XXXXXX) … rm -rf "$D". Do not reuse the old directory without clearing it — its old contents are still there; use a fresh mktemp directory. Do not delete it any other way (no find -delete, python, rsync or a script file). If the deletion is itself the task, stop and report the exact command to your lead.'

@test "subagent: rm -rf on a non-artifact target is DENIED with the round-4 reason, verbatim" {
  probe 'rm -rf /tmp/x/out' 'agent-abc123'
  [ "$(decision)" = deny ]
  [ "$(reason)" = "$REASON" ]
}

@test "subagent: the reason carries no 'tell your lead' sentence (round 5: 0/10 salvaged with it)" {
  probe 'rm -rf /tmp/x/out' 'agent-abc123'
  ! reason | grep -qi 'tell your lead'
}

@test "subagent: rm -R spelled differently is denied too" {
  probe 'rm --recursive --force src' 'agent-abc123'
  [ "$(decision)" = deny ]
}

@test "subagent: a fresh mktemp dir removed in the same command is UNCHANGED (no decision)" {
  probe 'D=$(mktemp -d /tmp/p.XXXXXX); rm -rf "$D"' 'agent-abc123'
  [ "$(decision)" = none ]
}

@test "main thread (no agent_id): the same rm still ASKS" {
  probe 'rm -rf /tmp/x/out'
  [ "$(decision)" = ask ]
}

@test "empty agent_id is the main thread: ASK" {
  run bash -c 'jq -nc "{tool_name:\"Bash\", tool_input:{command:\"rm -rf /tmp/x/out\"}, agent_id:\"\"}" | "$0"' "$HOOK"
  [ "$(decision)" = ask ]
}

@test "teammate-shaped payload (no agent_id; --agent-id only in the command's argv): ASK" {
  probe 'claude --agent-id w1@session-t -p hi; rm -rf /tmp/x/out'
  [ "$(decision)" = ask ]
}

@test "subagent: git reset --hard is UNCHANGED — still an ask" {
  probe 'git reset --hard HEAD~1' 'agent-abc123'
  [ "$(decision)" = ask ]
}

@test "kill switch CC_VB_AGENT_RM_DENY=off restores the ask inside a subagent" {
  export CC_VB_AGENT_RM_DENY=off
  probe 'rm -rf /tmp/x/out' 'agent-abc123'
  [ "$(decision)" = ask ]
}

@test "log_decision carries aid: the subagent's id on a deny, '-' on the main thread" {
  probe 'rm -rf /tmp/x/out' 'agent-abc123'
  [ "$(jq -r '.aid' "$CC_VB_DECISION_LOG" | tail -1)" = agent-abc123 ]
  [ "$(jq -r '.decision' "$CC_VB_DECISION_LOG" | tail -1)" = deny ]
  probe 'rm -rf /tmp/x/out'
  [ "$(jq -r '.aid' "$CC_VB_DECISION_LOG" | tail -1)" = - ]
  [ "$(jq -r '.decision' "$CC_VB_DECISION_LOG" | tail -1)" = ask ]
}

@test "an agent_id holding a tab cannot shift the command into a metadata cell" {
  run bash -c 'jq -nc "{tool_name:\"Bash\", tool_input:{command:\"rm -rf /tmp/x/out\"}, session_id:\"s\", agent_id:\"a\\tb\"}" | "$0"' "$HOOK"
  [ "$(decision)" = deny ]
}
