#!/usr/bin/env bats
# workflow-script-edit-allow.sh — allows Write/Edit on Dynamic Workflow files under a config dir and
# stays SILENT (defers to the normal permission flow) for every other path. Both directions pinned.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  H="$REPO/hooks/workflow-script-edit-allow.sh"
  export HOME=/Users/tester
}

# decision <event> <path> → ALLOW or DEFER
decision() {
  local out
  out="$(jq -cn --arg e "$1" --arg p "$2" '{hook_event_name:$e, tool_name:"Edit", tool_input:{file_path:$p}}' | "$H" 2>/dev/null)"
  [ -z "$out" ] && { echo DEFER; return; }
  printf '%s' "$out" | jq -r '(.hookSpecificOutput.permissionDecision // .hookSpecificOutput.decision.behavior // "DEFER") | ascii_upcase'
}

@test "hook is executable" {
  [ -x "$H" ]
}

@test "allows session workflow scripts under every account dir, on both events" {
  for p in /Users/tester/.claude/projects/-Users-x-repo/0f1e/workflows/scripts/a-wf_1.js \
           /Users/tester/.claude-next/projects/-Users-x-repo/0f1e/workflows/scripts/a-wf_1.js \
           /Users/tester/.claude-quaternary/projects/p/s/workflows/state.json \
           /Users/tester/.claude/workflows/saved.js; do
    for e in PreToolUse PermissionRequest; do
      [ "$(decision "$e" "$p")" = ALLOW ] || { echo "expected ALLOW: $e $p"; false; }
    done
  done
}

@test "each event gets its own output shape" {
  p=/Users/tester/.claude/projects/p/s/workflows/scripts/a.js
  out="$(jq -cn --arg p "$p" '{hook_event_name:"PermissionRequest", tool_input:{file_path:$p}}' | "$H")"
  [ "$(jq -r .hookSpecificOutput.hookEventName <<<"$out")" = PermissionRequest ]
  out="$(jq -cn --arg p "$p" '{hook_event_name:"PreToolUse", tool_input:{file_path:$p}}' | "$H")"
  [ "$(jq -r .hookSpecificOutput.hookEventName <<<"$out")" = PreToolUse ]
}

@test "defers settings, memory, hooks and other config-dir files" {
  for p in /Users/tester/.claude/settings.json /Users/tester/.claude-next/settings.json \
           /Users/tester/.claude/projects/p/memory/MEMORY.md /Users/tester/.claude/hooks/x.sh \
           /Users/tester/.claude/projects/p/s/subagents/a.jsonl /Users/tester/.claude/CLAUDE.md; do
    [ "$(decision PreToolUse "$p")" = DEFER ] || { echo "expected DEFER: $p"; false; }
  done
}

@test "defers traversal, other homes, look-alike dirs and empty input" {
  for p in /Users/tester/.claude/projects/p/s/workflows/../../../settings.json \
           /Users/other/.claude/projects/p/s/workflows/a.js \
           /Users/tester/notclaude/.claude/projects/p/s/workflows/a.js \
           /Users/tester/.claude.bak/projects/p/s/workflows/a.js \
           /tmp/.claude/workflows/a.js ""; do
    [ "$(decision PreToolUse "$p")" = DEFER ] || { echo "expected DEFER: $p"; false; }
  done
}
