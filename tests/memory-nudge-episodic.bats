#!/usr/bin/env bats
# memory-nudge-episodic.bats — the RENDERED JSON of hooks/memory-nudge.sh with the episodic cue
# (truememory §3.18, #18): cue-only on a non-due prompt, cue + nudge on a due one, nothing on a
# non-matching non-due prompt, always exactly one JSON object, the cue still reached through a
# symlinked hooks dir (X1), and CC_EPISODIC_CUE=off. Hermetic: HOME, config, state, IDL and the
# index all live in the test tmpdir, as in nudge-supersession-run.sh.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/cfg"
  export MEMORY_NUDGE_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export MEMORY_INDEX_PATH="$BATS_TEST_TMPDIR/mem/MEMORY.md"
  mkdir -p "$HOME" "$CLAUDE_CONFIG_DIR" "$MEMORY_NUDGE_STATE_DIR" "$BATS_TEST_TMPDIR/mem"
  printf -- '- [A](a.md) — one\n' > "$MEMORY_INDEX_PATH"
  unset CC_EPISODIC_CUE
  HOOK="$REPO/hooks/memory-nudge.sh"
  CUE_PROMPT='retrieve that Dynamic Workflow research from a week ago about pinterest'
}

nudge() { # <interval> <prompt> [hook]
  jq -cn --arg p "$2" '{session_id:"sid-ep",cwd:"/nonexistent-cwd-xyz",prompt:$p}' \
    | MEMORY_NUDGE_INTERVAL="$1" bash "${3:-$HOOK}"
}

@test "non-due prompt with a cue prints one JSON object carrying ONLY the cue" {
  run nudge 1000 "$CUE_PROMPT"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -s length)" -eq 1 ]
  run jq -r '.hookSpecificOutput.hookEventName + "|" + .hookSpecificOutput.additionalContext' <<< "$output"
  [[ "$output" == "UserPromptSubmit|EPISODIC CUE: "*"claude-search 'dynamic workflow research pinterest'"* ]] || false
  [[ "$output" != *"MEMORY CHECK"* ]] || false
}

@test "due prompt with a cue prints one JSON object: cue first, then the nudge" {
  run nudge 1 "$CUE_PROMPT"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -s length)" -eq 1 ]
  run jq -r '.hookSpecificOutput.additionalContext' <<< "$output"
  [[ "$output" == "EPISODIC CUE: "*"MEMORY CHECK (periodic)"* ]] || false
}

@test "non-matching non-due prompt prints nothing; non-matching due prompt prints the plain nudge" {
  run nudge 1000 'fix the failing test'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run nudge 1 'fix the failing test'
  [ "$(printf '%s' "$output" | jq -s length)" -eq 1 ]
  run jq -r '.hookSpecificOutput.additionalContext' <<< "$output"
  [[ "$output" != *"EPISODIC CUE"* ]] || false
  [[ "$output" == *"MEMORY CHECK (periodic)"* ]] || false
}

@test "every counted prompt logs one memory-nudge:episodic IDL row" {
  nudge 1000 "$CUE_PROMPT" >/dev/null
  nudge 1000 'fix the failing test' >/dev/null
  run jq -r 'select(.hook == "memory-nudge:episodic") | .disposition + " " + .reason' "$CC_IDL"
  [ "${lines[0]}" = "fired time-ago" ]
  [ "${lines[1]}" = "abstained no-match" ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "X1: a hooks dir of per-file symlinks still renders the cue" {
  mkdir -p "$BATS_TEST_TMPDIR/live/hooks/lib"
  ln -s "$HOOK" "$BATS_TEST_TMPDIR/live/hooks/memory-nudge.sh"
  [ ! -e "$BATS_TEST_TMPDIR/live/hooks/lib/episodic_cue.sh" ]
  run nudge 1000 "$CUE_PROMPT" "$BATS_TEST_TMPDIR/live/hooks/memory-nudge.sh"
  [ "$status" -eq 0 ]
  run jq -r '.hookSpecificOutput.additionalContext' <<< "$output"
  [[ "$output" == "EPISODIC CUE: "* ]] || false
}

@test "CC_EPISODIC_CUE=off: no cue on either path, nudge unchanged" {
  export CC_EPISODIC_CUE=off
  run nudge 1000 "$CUE_PROMPT"
  [ -z "$output" ]
  run nudge 1 "$CUE_PROMPT"
  run jq -r '.hookSpecificOutput.additionalContext' <<< "$output"
  [[ "$output" == *"MEMORY CHECK (periodic)"* ]] || false
  [[ "$output" != *"EPISODIC CUE"* ]] || false
}

@test "an over-cap index keeps the 🚨 warning FIRST; the cue follows it, then the nudge" {
  : > "$MEMORY_INDEX_PATH"
  for i in $(seq 1 210); do printf -- '- [T%s](t%s.md) — n\n' "$i" "$i" >> "$MEMORY_INDEX_PATH"; done
  run nudge 1 "$CUE_PROMPT"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -s length)" -eq 1 ]
  run jq -r '.hookSpecificOutput.additionalContext' <<< "$output"
  [[ "$output" == "🚨 MEMORY INDEX OVER ITS LINE LIMIT"*"EPISODIC CUE: "*"MEMORY CHECK (periodic)"* ]] || false
}
