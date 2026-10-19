#!/usr/bin/env bats
# cutreplay-pretooluse.bats — cutreplay.py --event PreToolUse rebuilds a cancelled PreToolUse call's
# exact payload from a transcript, and a9-replay-pretooluse.py replays it in a HERMETIC HOME (README
# §5 Wave 7, A9-F9: validate-bash appends to logs under $HOME, so a replay must never see the real
# one). Fixture transcripts and a stub hook only; HOME is the test dir.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  CUT="$REPO/docs/research/load-hook-timeouts-2026-10-11/cutreplay.py"
  REPLAY="$REPO/docs/research/startup-hooks-2026-10-18/a9-replay-pretooluse.py"
  export HOME="$BATS_TEST_TMPDIR/home"
  P="$HOME/.claude/projects/-x"; mkdir -p "$P"
  SID=11111111-2222-4333-8444-555555555555
  T="$P/$SID.jsonl"
  {
    jq -cn --arg s "$SID" '{type:"user",sessionId:$s,cwd:"/nonexistent",message:{role:"user",content:"go"}}'
    jq -cn --arg s "$SID" '{type:"assistant",sessionId:$s,permissionMode:"auto",cwd:"/nonexistent",
        message:{role:"assistant",content:[{type:"tool_use",id:"toolu_A",name:"Bash",
        input:{command:"git status --short",description:"Show status"}}]}}'
    jq -cn --arg s "$SID" '{type:"attachment",sessionId:$s,cwd:"/nonexistent",timestamp:"2026-10-18T06:40:07.854Z",
        attachment:{type:"hook_cancelled",hookName:"PreToolUse:Bash",toolUseID:"toolu_A",hookEvent:"PreToolUse",
        command:"~/.claude/hooks/validate-bash.sh",durationMs:10098,timedOut:true,timeoutMs:10000}}'
    # A Stop cancel in the same transcript must not be picked up by the PreToolUse mode, and vice versa.
    jq -cn --arg s "$SID" '{type:"attachment",sessionId:$s,cwd:"/nonexistent",timestamp:"2026-10-18T06:41:00Z",
        attachment:{type:"hook_cancelled",hookEvent:"Stop",command:"~/.claude/hooks/validate-bash.sh"}}'
  } > "$T"
  OUT="$BATS_TEST_TMPDIR/cases"
}

@test "PreToolUse: the payload is rebuilt from the tool_use the cancel names, once per transcript" {
  # A second account dir whose projects/ is a symlink to the first (as ~/.claude-next is) is the same
  # transcript: one case, not two.
  mkdir -p "$HOME/.claude-next"; ln -s "$HOME/.claude/projects" "$HOME/.claude-next/projects"
  run python3 -I "$CUT" --event PreToolUse validate-bash 5 "$OUT"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c .)" -eq 1 ]
  jq -e --arg s "$SID" '.session_id==$s and .hook_event_name=="PreToolUse" and .tool_name=="Bash"
        and .tool_input.command=="git status --short" and .tool_use_id=="toolu_A"
        and .permission_mode=="auto" and .cwd=="/nonexistent"' "$OUT/1/stdin.json"
  tp="$(jq -r .transcript_path "$OUT/1/stdin.json")"
  [ "$(grep -c . "$tp")" -eq 2 ]
  tail -1 "$tp" | jq -e '.message.content[0].id=="toolu_A"' >/dev/null
}

@test "Stop mode is unchanged by the new flag: it still rebuilds only Stop cancels" {
  run python3 -I "$CUT" validate-bash 5 "$OUT"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c .)" -eq 1 ]
  jq -e '.hook_event_name=="Stop" and .stop_hook_active==false and (has("tool_input")|not)' "$OUT/1/stdin.json"
}

@test "the replay runs the hook in a hermetic HOME: its writes land in the case dir, never in \$HOME" {
  python3 -I "$CUT" --event PreToolUse validate-bash 5 "$OUT" >/dev/null
  hook="$BATS_TEST_TMPDIR/hooks/stub-gate.sh"; mkdir -p "${hook%/*}"
  printf '%s\n' '#!/bin/bash' 'in=$(cat)' 'mkdir -p "$HOME/.claude/logs"' \
    'printf "%s\n" "$in" >> "$HOME/.claude/logs/audit.jsonl"' \
    'printf "%s\n" "${CLAUDE_CONFIG_DIR:-unset}" > "$HOME/.claude/logs/ccd"' \
    'sleep 1' \
    'printf "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\"}}\n"' > "$hook"
  chmod +x "$hook"
  export CLAUDE_CONFIG_DIR="$HOME/.claude-live"
  run python3 -I "$REPLAY" "$hook" "$OUT" --repo "$REPO" --json "$BATS_TEST_TMPDIR/r.json"
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.claude/logs/audit.jsonl" ]
  jq -e '.tool_input.command=="git status --short"' "$OUT/1/home/.claude/logs/audit.jsonl"
  [ "$(cat "$OUT/1/home/.claude/logs/ccd")" = unset ]
  [ -L "$OUT/1/home/.claude/hooks" ]
  [ "$(readlink "$OUT/1/home/.claude/hooks")" = "$REPO/hooks" ]
  jq -e '.cases[0].decision=="deny" and .cases[0].rc==0 and .cases[0].ms>=900' "$BATS_TEST_TMPDIR/r.json"
}

@test "--trace charges the slow line of the hook" {
  b5=/opt/homebrew/bin/bash
  [ -x "$b5" ] || skip "no bash 5 at $b5"
  python3 -I "$CUT" --event PreToolUse validate-bash 5 "$OUT" >/dev/null
  hook="$BATS_TEST_TMPDIR/hooks/stub-gate.sh"; mkdir -p "${hook%/*}"
  printf '%s\n' '#!/bin/bash' 'in=$(cat)' 'x=1' 'sleep 1' 'y=2' > "$hook"
  chmod +x "$hook"
  run python3 -I "$REPLAY" "$hook" "$OUT" --repo "$REPO" --trace "$b5" --json "$BATS_TEST_TMPDIR/r.json"
  [ "$status" -eq 0 ]
  jq -e '.top_lines[0].file=="stub-gate.sh" and .top_lines[0].line==4 and .top_lines[0].src=="sleep 1"
         and .top_lines[0].ms>=900' "$BATS_TEST_TMPDIR/r.json"
}
