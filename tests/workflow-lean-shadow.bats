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
# S3 RED-proof (2026-10-25): against the base hook (git show c43f39d2b:…) 5-7 fail: ts carries -0500,
# no acct / arm / follows_deny, and a row over 2 KB is written whole.
# Hermetic: scratch HOME; the log path is $HOME-rooted.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/workflow-lean-shadow.py"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  LOG="$HOME/.claude/logs/workflow-lean-shadow.jsonl"
  FIX="$REPO/tests/fixtures/workflow-lean-shadow/mixed.js"
  unset CLAUDE_CONFIG_DIR CC_LEVER_LINEAGE CC_LEVER_EXCLUDE CC_LEVER_ALL CC_LEVER_D2 CC_LEVER_FLAGS CC_HOOK_PARENT_PID CC_WORKFLOW_SHADOW
  export CC_LEVER_STATE_DIR="$BATS_TEST_TMPDIR/levers"
}

# fire <tool_input json> — one PreToolUse event on stdin, as Claude Code sends it
fire() { jq -nc --argjson ti "$1" '{session_id:"S",tool_use_id:"T",cwd:"/nonexistent",tool_name:"Workflow",tool_input:$ti}' \
  | /usr/bin/env python3 "$HOOK"; }
# a row over 2 KB is split into the call row plus kind=slots rows (S3): slot() reads across both
slot() { jq -r --arg l "$1" "(.slots // [])[] | select(.label == \$l) | $2" "$LOG"; }
call() { jq -r "select(.kind != \"slots\") | $1" "$LOG"; }

@test "1: every agent() call in code is classified; strings, comments and x.agent( are not calls" {
  run fire "$(jq -nc --rawfile s "$FIX" '{script:$s}')"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(call .parse)" = ok ]
  [ "$(call .calls)" -eq 6 ]
  [ "$(slot r1 .verdict)" = would-deny ]
  [ "$(slot r1 .rewrite)" = "agentType: 'workflow-lean'" ]
  [ "$(slot fix .verdict)" = keep-default ]
  [ "$(slot fix .markers.commit)" = true ]
  [ "$(slot opq .verdict)" = unknown ]
  [ "$(slot lean .verdict)" = has-agent-type ]
  [ "$(slot lean .agent_type)" = workflow-lean ]
  [ "$(slot "s-\${i}" .markers.skill)" = true ]
  [ "$(jq -s '[.[] | (.slots // [])[] | select(.agent_type == "opaque")] | length' "$LOG")" -eq 1 ]
  [ "$(call .would_deny)" = true ]
  [ "$(call .latency_ms.timeout_s)" -eq 5 ]
  [ "$(call '.latency_ms.wall >= 0 and .latency_ms.cpu > 0')" = true ]
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
  [ "$(call '.source + " " + (.calls|tostring)')" = "scriptPath 6" ]
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

# ── W7+ S3: UTC Z, acct, the D2 arm per lineage root, follows_deny, 2 KB rows ───────────────────
s3_flags() {
  export CC_LEVER_STATE_DIR="$BATS_TEST_TMPDIR/levers"; mkdir -p "$CC_LEVER_STATE_DIR"
  jq -nc '{v:1,rev:3,levers:{D2:{stage:"S0",mode:"shadow",pct:0,holdback:0,salt:"s3-d2-salt",split_salt:"s3-split"}}}' \
    > "$CC_LEVER_STATE_DIR/flags.json"
}
fire_as() { # <sid> <tool_use_id> <script>
  jq -nc --arg s "$1" --arg t "$2" --arg c "$3" '{session_id:$s,tool_use_id:$t,cwd:"/nonexistent",tool_name:"Workflow",tool_input:{script:$c}}' \
    | /usr/bin/env python3 "$HOOK"
}

@test "5: S3 — UTC Z, acct, and the D2 arm is per lineage root (the S1 resolver), equal to the lib's" {
  s3_flags
  CC_LEVER_LINEAGE=root-A CLAUDE_CONFIG_DIR="$HOME/.claude-next4" fire_as S1 T1 'await agent(`x`)'
  CC_LEVER_LINEAGE=root-A fire_as S2 T2 'await agent(`x`)'
  fire_as S3 T3 'await agent(`x`)'
  jq -e -s 'all(.[]; (.ts | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$")) and .arm.lever == "D2"
             and .arm.flag_src == "file" and .arm.arm == "ctrl" and .arm.pct_eff == 0 and .arm.unit == .lineage)' "$LOG" >/dev/null
  [ "$(jq -sr '[.[] | "\(.acct):\(.lineage):\(.lineage_src)"] | join(",")' "$LOG")" \
    = ".claude-next4:root-A:env,.claude:root-A:env,.claude:S3:self" ]
  # two sessions of one lineage share the arm; it is the lib's arm, not a re-derivation
  [ "$(jq -sr '[.[0].arm.u, .[1].arm.u] | unique | length' "$LOG")" -eq 1 ]
  [ "$(jq -sr '.[0].arm.u' "$LOG")" = "$(/usr/bin/python3 -I "$REPO/hooks/lib/lever_flags.py" arm D2 root-A | jq -r .u)" ]
  # the hook resolves read-only: no lever state written
  [ ! -e "$CC_LEVER_STATE_DIR/arms" ]
}

@test "6: S3 — follows_deny reads this session's previous row, whatever its timestamp offset" {
  mkdir -p "${LOG%/*}"
  # a pre-S3 row with a local offset, 90 s before now, that was a would-deny
  jq -nc --arg ts "$(date -r $(( $(date +%s) - 90 )) +%Y-%m-%dT%H:%M:%S%z)" \
    '{ts:$ts,session_id:"S",tool_use_id:"T0",script_sha:"old",would_deny:true}' > "$LOG"
  fire_as S T1 'await agent(`x`, {agentType: "workflow-lean"})'
  fire_as S T2 'await agent(`y`)'
  fire_as OTHER T3 'await agent(`z`)'
  fire_as S T4 'await agent(`y`)'
  [ "$(jq -sr '.[1:][] | "\(.tool_use_id):\(.follows_deny):\(.prev_tool_use_id):\(.prev_same_script)"' "$LOG" | paste -sd, -)" \
    = "T1:true:T0:false,T2:false:T1:false,T3:null:null:null,T4:true:T2:true" ]
  gap="$(jq -sr '.[1].prev_gap_s' "$LOG")"
  awk -v g="$gap" 'BEGIN { exit !(g >= 85 && g <= 120) }' || { echo "prev_gap_s=$gap"; false; }
}

@test "7: S3 — every row is one write of at most 2 KB: a larger call is split losslessly into slot rows" {
  s=""; for i in $(seq 1 60); do s="$s await agent(\`brief $i\`, {label: \"slot-label-number-$i\"});"; done
  fire_as S T1 "$s"
  [ "$(LC_ALL=C awk '{ if (length($0) > m) m = length($0) } END { print m }' "$LOG")" -le 2047 ]
  k="$(call .slot_rows)"
  [ "$k" -ge 2 ]
  [ "$(wc -l < "$LOG")" -eq $(( k + 1 )) ]
  [ "$(call '"\(.slots_shed):\(.calls):\(.verdicts["would-deny"]):\(.would_deny):\(has("slots"))"')" = "split:60:60:true:false" ]
  # the slot rows carry every slot, in order, joined by the call's tool_use_id
  [ "$(jq -sr '[.[] | select(.kind == "slots" and .tool_use_id == "T1") | .slots[] | .label] | join(",")' "$LOG")" \
    = "$(for i in $(seq 1 60); do printf 'slot-label-number-%s\n' "$i"; done | paste -sd, -)" ]
  # a slot row is never read back as the session's previous call
  fire_as S T2 'await agent(`x`, {agentType: "workflow-lean"})'
  [ "$(call 'select(.tool_use_id == "T2") | "\(.prev_tool_use_id):\(.follows_deny)"')" = "T1:true" ]
  # a call that fits stays one row
  : > "$LOG"
  fire_as S T3 'await agent(`x`)'
  [ "$(wc -l < "$LOG")" -eq 1 ]
  [ "$(jq -r '"\(.slots_shed):\(.slots | length)"' "$LOG")" = "null:1" ]
}
