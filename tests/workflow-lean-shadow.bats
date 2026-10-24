#!/usr/bin/env bats
# shellcheck disable=SC2016  # the fixtures are JS source: their backticks are template literals, not expansions
# hooks/workflow-lean-shadow.py — the LOG-ONLY PreToolUse hook on Workflow (docs/plans/USAGE_LEVERS.md
# W1.3). Two contracts: (1) it never denies — no stdout, exit 0, on every input including its own
# failures; (2) each agent() call is logged with the verdict a deny-mode hook would reach, the brief's
# commit/ship/Skill/MCP markers and the hook's latency.
# RED-proof (2026-10-24, scratch copies): a copy that prints a deny decision fails test 2; a copy whose
# agentType reader always returns None fails test 1 (the `lean` slot reads would-deny).
# W6 RED-proof (2026-10-24): against the base hook (git show 11f7f87fa:…) test 4 fails: the `nd` slot
# reads would-deny (no marker) and the row has no resume_from_run_id / script_sha / repeat_in_session.
# Hermetic: scratch HOME; the log path is $HOME-rooted.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/workflow-lean-shadow.py"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  LOG="$HOME/.claude/logs/workflow-lean-shadow.jsonl"
  FIX="$REPO/tests/fixtures/workflow-lean-shadow/mixed.js"
}

# fire <tool_input json> — one PreToolUse event on stdin, as Claude Code sends it
fire() { jq -nc --argjson ti "$1" '{session_id:"S",tool_use_id:"T",cwd:"/nonexistent",tool_name:"Workflow",tool_input:$ti}' \
  | /usr/bin/env python3 "$HOOK"; }
slot() { jq -r --arg l "$1" ".slots[] | select(.label == \$l) | $2" "$LOG"; }

@test "1: every agent() call in code is classified; strings, comments and x.agent( are not calls" {
  run fire "$(jq -nc --rawfile s "$FIX" '{script:$s}')"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(jq -r '.parse' "$LOG")" = ok ]
  [ "$(jq -r '.calls' "$LOG")" -eq 6 ]
  [ "$(slot r1 .verdict)" = would-deny ]
  [ "$(slot r1 .rewrite)" = "agentType: 'workflow-lean'" ]
  [ "$(slot fix .verdict)" = keep-default ]
  [ "$(slot fix .markers.commit)" = true ]
  [ "$(slot opq .verdict)" = unknown ]
  [ "$(slot lean .verdict)" = has-agent-type ]
  [ "$(slot lean .agent_type)" = workflow-lean ]
  [ "$(slot "s-\${i}" .markers.skill)" = true ]
  [ "$(jq -r '[.slots[] | select(.agent_type == "opaque")] | length' "$LOG")" -eq 1 ]
  [ "$(jq -r '.would_deny' "$LOG")" = true ]
  [ "$(jq -r '.latency_ms.timeout_s' "$LOG")" -eq 5 ]
  jq -e '.latency_ms.wall >= 0 and .latency_ms.cpu > 0' "$LOG" >/dev/null
  # the brief text itself is never written
  ! grep -q 'Fix the bug' "$LOG" || false
}

@test "2: it never denies — empty stdout and exit 0 on garbage, empty input, an unresolved workflow and an unwritable log" {
  for input in 'not json' '' '{"tool_input":{"script":"agent(`x`"}}' \
               '{"tool_name":"Workflow","tool_input":{"name":"no-such-workflow"}}' \
               '{"tool_name":"Workflow","tool_input":{"script":"await agent(`go`, {label: \"a\"})"}}'; do
    run bash -c 'printf "%s" "$1" | /usr/bin/env python3 "$2"' _ "$input" "$HOOK"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
  done
  [ "$(jq -sr '[.[].parse] | join(",")' "$LOG")" = "error,error,ok,unresolved,ok" ]
  rm -rf "$HOME/.claude/logs"; mkdir -p "$HOME/.claude"; : > "$HOME/.claude/logs"   # the log dir is a FILE
  run fire '{"script":"await agent(`go`)"}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "3: a scriptPath workflow is read from its file and logged with its source" {
  run fire "$(jq -nc --arg p "$FIX" '{scriptPath:$p}')"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.source + " " + (.calls|tostring)' "$LOG")" = "scriptPath 6" ]
}

@test "4: W6 — resumeFromRunId, script sha, repeat-in-session, and a needs-default comment keeps the default agent" {
  s1='await agent(`Summarise the notes` /* needs-default */, {label: "nd"}); await agent(`say /* needs-default */`, {label: "str"})'
  run fire "$(jq -nc --arg s "$s1" '{script:$s, resumeFromRunId:"wf_abc123"}')"
  [ "$status" -eq 0 ]; [ -z "$output" ]
  [ "$(slot nd .verdict)" = keep-default ]
  [ "$(slot nd .needs_default)" = true ]
  # the marker counts only as a comment, never inside the brief's own text
  [ "$(slot str .verdict)" = would-deny ]
  [ "$(slot str .needs_default)" = false ]
  [ "$(jq -r .resume_from_run_id "$LOG")" = wf_abc123 ]
  [ "$(jq -r .script_sha "$LOG")" = "$(printf '%s' "$s1" | openssl dgst -sha256 -r | cut -d' ' -f1)" ]
  [ "$(jq -r .repeat_in_session "$LOG")" = 0 ]
  # the same script again in this session is a repeat; another session or script is not
  fire "$(jq -nc --arg s "$s1" '{script:$s}')"
  jq -nc --arg s "$s1" '{session_id:"OTHER",tool_name:"Workflow",tool_input:{script:$s}}' | /usr/bin/env python3 "$HOOK"
  fire '{"script":"await agent(`x`)"}'
  [ "$(jq -sr '[.[] | "\(.session_id):\(.repeat_in_session):\(.resume_from_run_id)"] | join(",")' "$LOG")" \
    = "S:0:wf_abc123,S:1:null,OTHER:0:null,S:0:null" ]
}
