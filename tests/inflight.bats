#!/usr/bin/env bats
# inflight.bats — hooks/lib/inflight.sh: what the scope floor reads as "work still running"
# (docs/research/lead-keeps-working-2026-10-24.md §3.3; rows S8, S8b, S9, S9b, S22 of §7.3 at the
# lib level). Fixtures are real record shapes: a Bash tool_use + its `Command running in background`
# tool_result, an `Async agent launched` tool_result, and `<task-id>` notifications in each of the
# three record kinds that carry them (user, queued_command attachment, queue-operation).

LIB="$BATS_TEST_DIRNAME/../hooks/lib/inflight.sh"
BH="$BATS_TEST_DIRNAME/../hooks/boundary-handoff.sh"

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  unset CLAUDE_CODE_SESSION_ID CLAUDE_SESSION_ID WRAP_SESSION_ID
  export CC_BH_WAVE_WARM_S=1800
  # S22 reads boundary-handoff.sh (only its bh_live_waves runs), so its /tmp seam is pinned too
  export CC_TELEMETRY_DIR="$BATS_TEST_TMPDIR/telemetry"
  SID="11111111-2222-3333-4444-555555555555"
  PROJ="$BATS_TEST_TMPDIR/projects/-Users-someone-repo"
  TP="$PROJ/$SID.jsonl"
  OUT="$BATS_TEST_TMPDIR/tasks"
  mkdir -p "$PROJ" "$OUT"
  : >"$TP"
  # shellcheck disable=SC1090,SC1091  # path resolved at run time
  . "$LIB"
}

# age <path> — mtime 3 h ago, past CC_BH_WAVE_WARM_S
age() {
  touch -t "$(date -v-3H +%Y%m%d%H%M.%S 2>/dev/null || date -d '-3 hours' +%Y%m%d%H%M.%S)" "$1"
}

# bg <id> <command> — the tool_use, its background tool_result, and a fresh output file
bg() {
  local id="$1" cmd="$2" tu="toolu_$1"
  : >"$OUT/$id.output"
  jq -nc --arg tu "$tu" --arg c "$cmd" \
    '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",id:$tu,name:"Bash",input:{command:$c,run_in_background:true}}]}}' >>"$TP"
  jq -nc --arg tu "$tu" --arg id "$id" --arg o "$OUT/$id.output" \
    '{type:"user",message:{role:"user",content:[{type:"tool_result",tool_use_id:$tu,content:("Command running in background with ID: " + $id + ". Output is being written to: " + $o + ". You will be notified when it completes. To check interim output, use Read on that file path.")}]},toolUseResult:{stdout:"",stderr:"",interrupted:false,backgroundTaskId:$id}}' >>"$TP"
}

# agent <id> — an async agent launch and a fresh subagent transcript beside ours
agent() {
  mkdir -p "$PROJ/$SID/subagents"
  : >"$PROJ/$SID/subagents/agent-$1.jsonl"
  jq -nc --arg id "$1" \
    '{type:"user",message:{role:"user",content:[{type:"tool_result",tool_use_id:("toolu_a" + $id),content:[{type:"text",text:("Async agent launched successfully. (This tool result is internal metadata, never quote it.)\nagentId: " + $id + " (internal ID - do not mention to user.)\nThe agent is working in the background.")}]}]}}' >>"$TP"
}

note() { printf '<task-notification>\n<task-id>%s</task-id>\n<tool-use-id>toolu_%s</tool-use-id>\n<status>completed</status>\n</task-notification>' "$1" "$1"; }
done_user()  { jq -nc --arg c "$(note "$1")" '{type:"user",message:{role:"user",content:$c}}' >>"$TP"; }
done_queued() { jq -nc --arg c "$(note "$1")" '{type:"attachment",attachment:{type:"queued_command",prompt:$c,commandMode:"task-notification"}}' >>"$TP"; }
done_queueop() { jq -nc --arg c "$(note "$1")" '{type:"queue-operation",operation:"enqueue",timestamp:"2099-01-01T00:00:00.000Z",content:$c}' >>"$TP"; }

@test "S8: a live non-watcher background Bash task reads 1 bg" {
  bg b1live "sleep 999"
  run inflight_bg_tasks "$TP"
  [ "$status" -eq 0 ]
  [ "$output" = "1 bg" ]
}

@test "S8: a live async agent with a fresh subagent transcript reads 1 agent" {
  agent a8e552e552430265c
  run inflight_bg_tasks "$TP"
  [ "$status" -eq 0 ]
  [ "$output" = "1 agent" ]
}

@test "S8: both kinds live at once list both kinds" {
  bg b1live "sleep 999"
  agent a8e552e552430265c
  run inflight_bg_tasks "$TP"
  [ "$output" = "2 bg,agent" ]
}

@test "S8b: an agent finished by a <task-id> in a user record reads 0" {
  agent a8e552e552430265c
  done_user a8e552e552430265c
  run inflight_bg_tasks "$TP"
  [ "$output" = "0" ]
}

@test "S8b: an unfinished agent whose subagent transcript is 3 h old reads 0" {
  agent a8e552e552430265c
  age "$PROJ/$SID/subagents/agent-a8e552e552430265c.jsonl"
  run inflight_bg_tasks "$TP"
  [ "$output" = "0" ]
}

@test "S9: a watcher by absolute path alone reads 0" {
  bg bpctefji1 "/Users/someone/.claude/bin/cc-await-ping 134 --timeout 3300 --interval 15"
  run inflight_bg_tasks "$TP"
  [ "$output" = "0" ]
}

@test "S9: a watcher behind timeout <n> alone reads 0" {
  bg b5rshfkra "timeout 3400 /x/cc-await-ping 134"
  run inflight_bg_tasks "$TP"
  [ "$output" = "0" ]
}

@test "S9: a watcher behind a VAR=value assignment alone reads 0" {
  bg b5rshfkrb "CC_X=1 cc-await-ping 134"
  run inflight_bg_tasks "$TP"
  [ "$output" = "0" ]
}

@test "S9: a non-watcher ship-land reads 1 bg" {
  bg bshipland "bash scripts/ship-land.sh"
  run inflight_bg_tasks "$TP"
  [ "$output" = "1 bg" ]
}

@test "S9b: a task finished by a queued_command attachment reads 0" {
  bg bqueued1 "bash scripts/ship-land.sh"
  done_queued bqueued1
  run inflight_bg_tasks "$TP"
  [ "$output" = "0" ]
}

@test "S9b: a task finished by a queue-operation record reads 0" {
  bg bqueueop "bash scripts/ship-land.sh"
  done_queueop bqueueop
  run inflight_bg_tasks "$TP"
  [ "$output" = "0" ]
}

@test "S9b: a task never notified whose output file is 3 h old reads 0" {
  bg bstale01 "bash scripts/ship-land.sh"
  age "$OUT/bstale01.output"
  run inflight_bg_tasks "$TP"
  [ "$output" = "0" ]
}

@test "a missing or unreadable transcript reads ?" {
  run inflight_bg_tasks "$BATS_TEST_TMPDIR/nope.jsonl"
  [ "$output" = "?" ]
  bg b1live "sleep 999"
  chmod 000 "$TP"
  run inflight_bg_tasks "$TP"
  chmod 600 "$TP"
  [ "$output" = "?" ]
}

@test "/bin/bash 3.2: both functions under set -u" {
  bg b1live "sleep 999"
  mkdir -p "$PROJ/$SID/subagents/workflows/r1"
  printf '%s\n' '{"type":"started"}' >"$PROJ/$SID/subagents/workflows/r1/journal.jsonl"
  : >"$PROJ/$SID/subagents/workflows/r1/agent-x.jsonl"
  run /bin/bash -c 'set -u; . "$1"; inflight_bg_tasks "$2"; printf "|"; inflight_waves "$2"' _ "$LIB" "$TP"
  [ "$status" -eq 0 ]
  [ "$output" = "1 bg|1" ]
}

@test "S22: inflight_waves and boundary-handoff's bh_live_waves agree on one fixture" {
  local W="$PROJ/$SID/subagents/workflows"
  mkdir -p "$W/live" "$W/done"
  printf '%s\n' '{"type":"started"}' '{"type":"started"}' '{"type":"result"}' >"$W/live/journal.jsonl"
  : >"$W/live/agent-x.jsonl"
  printf '%s\n' '{"type":"started"}' '{"type":"result"}' >"$W/done/journal.jsonl"
  : >"$W/done/agent-y.jsonl"
  sed -n '/^bh_live_waves() {/,/^}/p' "$BH" >"$BATS_TEST_TMPDIR/bh.sh"
  [ -s "$BATS_TEST_TMPDIR/bh.sh" ]
  # shellcheck disable=SC1091  # generated by the sed above
  . "$BATS_TEST_TMPDIR/bh.sh"
  local mine theirs
  mine="$(inflight_waves "$TP")"
  theirs="$(tp="$TP" bh_live_waves)"
  [ "$mine" = 1 ] || false
  [ "$theirs" = "$mine" ] || false
  age "$W/live/agent-x.jsonl"
  mine="$(inflight_waves "$TP")"
  theirs="$(tp="$TP" bh_live_waves)"
  [ "$mine" = 0 ] || false
  [ "$theirs" = "$mine" ]
}
