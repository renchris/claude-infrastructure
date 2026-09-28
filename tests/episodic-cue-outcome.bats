#!/usr/bin/env bats
# episodic-cue-outcome.bats — scripts/episodic-cue-outcome.py classes each episodic cue fire older
# than 24 h as used (a later Bash claude-search, main transcript or subagent file), unused, or
# no-transcript, across every account root, and prints the EPISODIC-VERDICT line. Hermetic: the fire
# log, the account roots and the clock are all seams pointed into the test tmpdir.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/cfg"
  mkdir -p "$HOME" "$CLAUDE_CONFIG_DIR"
  A="$BATS_TEST_TMPDIR/acct-a"; B="$BATS_TEST_TMPDIR/acct-b"
  mkdir -p "$A/projects/-p1" "$B/projects/-p2"
  export CC_EPISODIC_ROOTS="$A:$B"
  export CC_EPISODIC_LOG="$BATS_TEST_TMPDIR/episodic-cue.jsonl"
  # 2026-09-28T12:00:00Z; every fixture fire is at 2026-09-26T12:00:00Z (48 h old) unless noted.
  export CC_EPISODIC_NOW=1790596800
  : > "$CC_EPISODIC_LOG"
}

fire() { # <sid> [ts]
  printf '{"ts":"%s","sid":"%s","cwd":"/x","pattern":"like-we-did","nouns":"wifi","prompt_len":9,"prompt_sha1":"ab"}\n' \
    "${2:-2026-09-26T12:00:00Z}" "$1" >> "$CC_EPISODIC_LOG"
}

bash_call() { # <ts> <command>
  jq -cn --arg ts "$1" --arg c "$2" \
    '{type:"assistant",timestamp:$ts,message:{content:[{type:"tool_use",name:"Bash",input:{command:$c}}]}}'
}

outcome() { python3 "$REPO/scripts/episodic-cue-outcome.py"; }

@test "a claude-search after the fire is used; before it, or none, is unused" {
  fire s-used; fire s-before; fire s-none
  bash_call 2026-09-26T12:05:00Z "claude-search 'wifi cafes'" > "$A/projects/-p1/s-used.jsonl"
  bash_call 2026-09-26T11:55:00Z "claude-search 'wifi cafes'" > "$A/projects/-p1/s-before.jsonl"
  bash_call 2026-09-26T12:05:00Z "git log --oneline" > "$A/projects/-p1/s-none.jsonl"
  run outcome
  [ "$status" -eq 0 ]
  [ "${lines[${#lines[@]}-1]}" = "EPISODIC-VERDICT fires=3 used=1 unused=2 unresolved=0" ]
}

@test "a search in a subagent file on a second account root counts as used" {
  fire s-sub
  mkdir -p "$B/projects/-p2/s-sub/subagents"
  bash_call 2026-09-26T12:00:30Z "git status" > "$B/projects/-p2/s-sub.jsonl"
  bash_call 2026-09-26T12:01:00Z "/Users/x/.claude/bin/claude-search --deep-search 'x'" \
    > "$B/projects/-p2/s-sub/subagents/agent-1.jsonl"
  run outcome
  [ "${lines[${#lines[@]}-1]}" = "EPISODIC-VERDICT fires=1 used=1 unused=0 unresolved=0" ]
}

@test "claude-search mentioned only in prose or a non-Bash tool is not a use" {
  fire s-prose
  {
    jq -cn '{type:"assistant",timestamp:"2026-09-26T12:02:00Z",message:{content:[{type:"text",text:"try claude-search"}]}}'
    jq -cn '{type:"assistant",timestamp:"2026-09-26T12:03:00Z",message:{content:[{type:"tool_use",name:"Read",input:{file_path:"/bin/claude-search"}}]}}'
  } > "$A/projects/-p1/s-prose.jsonl"
  run outcome
  [ "${lines[${#lines[@]}-1]}" = "EPISODIC-VERDICT fires=1 used=0 unused=1 unresolved=0" ]
}

@test "a fire with no transcript is unresolved; fires under 24 h old and a non-date ts are skipped" {
  fire s-gone
  fire s-young 2026-09-28T06:00:00Z
  fire s-bad not-a-timestamp
  printf 'not json\n' >> "$CC_EPISODIC_LOG"
  run outcome
  [ "$status" -eq 0 ]
  [ "${lines[${#lines[@]}-1]}" = "EPISODIC-VERDICT fires=1 used=0 unused=0 unresolved=1" ]
}

@test "a missing fire log is zero fires, exit 0" {
  export CC_EPISODIC_LOG="$BATS_TEST_TMPDIR/absent.jsonl"
  run outcome
  [ "$status" -eq 0 ]
  [ "${lines[${#lines[@]}-1]}" = "EPISODIC-VERDICT fires=0 used=0 unused=0 unresolved=0" ]
}
