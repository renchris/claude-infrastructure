#!/usr/bin/env bats
# task-created-attrib — the TaskCreated sidecar that gives a task a creator.
#
# RED-PROOF. Every case here fails on the pre-fix tree for the strongest possible reason: on
# origin/main `hooks/task-created-attrib.sh` does not exist, so `bash <missing>` exits 127 and each
# assertion below goes red. The control is `git show origin/main:hooks/task-created-attrib.sh`,
# which errors — the file is the fix.
#
# THE ASSERTION THAT MATTERS MOST IS THE BORING ONE. `TaskCreated` is a BLOCKING event
# (`ovn=["Stop","TeammateIdle","TaskCreated","TaskCompleted"]`, binary 2.1.260 @157431448) and
# `TaskCreate`'s body throws away the just-created task when a hook returns feedback (@164041206).
# So "exit 0 and print nothing" is not hygiene here, it is the correctness property: a hook that
# exits 1 on a malformed payload DELETES the operator's task. Cases 4-7 pin exactly that, one
# failure mode each, because a single happy-path case would pass over every one of them.
#
# Harness laws: assertions use the explicit `|| { …; false; }` form — a non-final `[[ ]]` is
# errexit-EXEMPT under bats and would be a DEAD assertion (memory: negated-assertion-dead-unless-final).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/task-created-attrib.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export TASK_ATTRIB_TASKS_DIR="$BATS_TEST_TMPDIR/tasks"
  mkdir -p "$TASK_ATTRIB_TASKS_DIR"
  unset CLAUDE_CODE_TASK_LIST_ID CLAUDE_CONFIG_DIR
  SID="b418b97a-d3ec-4444-b993-4f29d55f425a"
}

# A literal TaskCreated payload in the binary's own schema (@157890649).
payload() { # <task_id> [team_name]
  jq -cn --arg s "$SID" --arg t "$1" --arg tm "${2:-}" '
    {session_id:$s, transcript_path:"/tmp/t.jsonl", cwd:"/Users/chrisren/Development/x",
     hook_event_name:"TaskCreated", task_id:$t, task_subject:"land the migration"}
    + (if $tm == "" then {} else {team_name:$tm} end)'
}

@test "1: a well-formed TaskCreated writes the sidecar, and its three fields are the join" {
  mkdir -p "$TASK_ATTRIB_TASKS_DIR/$SID"
  printf '{}' > "$TASK_ATTRIB_TASKS_DIR/$SID/7.json"
  run bash -c "$(printf '%q' "$HOOK")" <<<"$(payload 7)"
  [ "$status" -eq 0 ] || { echo "status=$status out=$output"; false; }
  f="$TASK_ATTRIB_TASKS_DIR/$SID/.owners/7"
  [ -f "$f" ] || { echo "no sidecar at $f"; ls -R "$TASK_ATTRIB_TASKS_DIR"; false; }
  # session id, an ISO-8601 UTC stamp, and the cwd — tab-separated, one line.
  line="$(cat "$f")"
  [ "$(cut -f1 <<<"$line")" = "$SID" ] || { echo "field 1 = $(cut -f1 <<<"$line")"; false; }
  grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' <<<"$(cut -f2 <<<"$line")" \
    || { echo "field 2 is not an ISO ts: $(cut -f2 <<<"$line")"; false; }
  [ "$(cut -f3 <<<"$line")" = "/Users/chrisren/Development/x" ] || { echo "field 3 = $(cut -f3 <<<"$line")"; false; }
  [ "$(wc -l <"$f" | tr -d ' ')" -eq 1 ] || { echo "expected exactly one line"; false; }
}

@test "2: the list is the candidate that ACTUALLY holds the task, not the first guess" {
  # CLAUDE_CODE_TASK_LIST_ID is the binary's first branch, so a naive hook writes there — but the
  # task landed under the session id. A sidecar in the wrong directory is invisible, and invisibly so.
  export CLAUDE_CODE_TASK_LIST_ID="claude-infrastructure-main"
  mkdir -p "$TASK_ATTRIB_TASKS_DIR/$CLAUDE_CODE_TASK_LIST_ID" "$TASK_ATTRIB_TASKS_DIR/$SID"
  printf '{}' > "$TASK_ATTRIB_TASKS_DIR/$SID/3.json"
  run bash "$HOOK" <<<"$(payload 3)"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -f "$TASK_ATTRIB_TASKS_DIR/$SID/.owners/3" ] || { echo "sidecar not beside the task"; false; }
  [ ! -e "$TASK_ATTRIB_TASKS_DIR/$CLAUDE_CODE_TASK_LIST_ID/.owners/3" ] \
    || { echo "wrote into the env-named list, which does not hold the task"; false; }
}

@test "3: with no task file anywhere, it falls back to the env list id and still records the owner" {
  export CLAUDE_CODE_TASK_LIST_ID="claude-infrastructure-main"
  run bash "$HOOK" <<<"$(payload 9)"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -f "$TASK_ATTRIB_TASKS_DIR/claude-infrastructure-main/.owners/9" ] \
    || { echo "no fallback sidecar"; ls -R "$TASK_ATTRIB_TASKS_DIR"; false; }
}

@test "4: a malformed payload exits 0 and writes NOTHING (a non-zero exit deletes the task)" {
  run bash "$HOOK" <<<'this is not json {{{'
  [ "$status" -eq 0 ] || { echo "status=$status — a blocking TaskCreated hook must never fail"; false; }
  [ -z "$output" ] || { echo "wrote to stdout: $output"; false; }
  n="$(find "$TASK_ATTRIB_TASKS_DIR" -name '.owners' | wc -l | tr -d ' ')"
  [ "$n" -eq 0 ] || { echo "created $n .owners dir(s) from a malformed payload"; false; }
}

@test "5: valid JSON missing task_id (and missing session_id) exits 0 and writes nothing" {
  run bash "$HOOK" <<<"$(jq -cn --arg s "$SID" '{session_id:$s, hook_event_name:"TaskCreated", cwd:"/tmp"}')"
  [ "$status" -eq 0 ] || { echo "status=$status"; false; }
  [ -z "$output" ] || { echo "stdout: $output"; false; }
  run bash "$HOOK" <<<'{"task_id":"4","hook_event_name":"TaskCreated","cwd":"/tmp"}'
  [ "$status" -eq 0 ] || { echo "status=$status"; false; }
  n="$(find "$TASK_ATTRIB_TASKS_DIR" -name '.owners' | wc -l | tr -d ' ')"
  [ "$n" -eq 0 ] || { echo "half a join is not a join, but it wrote $n .owners dir(s)"; false; }
}

@test "6: empty stdin exits 0 silently" {
  run bash "$HOOK" </dev/null
  [ "$status" -eq 0 ] || { echo "status=$status"; false; }
  [ -z "$output" ] || { echo "stdout: $output"; false; }
}

@test "7: an unwritable tasks root exits 0 silently (the task survives, the sidecar does not)" {
  chmod 500 "$TASK_ATTRIB_TASKS_DIR"
  run bash "$HOOK" <<<"$(payload 11)"
  chmod 700 "$TASK_ATTRIB_TASKS_DIR"
  [ "$status" -eq 0 ] || { echo "status=$status out=$output"; false; }
  [ -z "$output" ] || { echo "stdout: $output"; false; }
}

@test "8: ids are sanitized, so no payload can write outside the tasks root" {
  # The binary sanitizes both ids with /[^a-zA-Z0-9_-]/g -> '-'. A hook that did not would accept
  # ../../ in task_id and drop a file wherever the payload said.
  export CLAUDE_CODE_TASK_LIST_ID="../../escape"
  run bash "$HOOK" <<<"$(payload '../../pwned')"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ ! -e "$BATS_TEST_TMPDIR/pwned" ] || { echo "escaped the tasks root"; false; }
  [ -f "$TASK_ATTRIB_TASKS_DIR/------escape/.owners/------pwned" ] \
    || { echo "not sanitized the way the binary sanitizes"; find "$TASK_ATTRIB_TASKS_DIR"; false; }
}

@test "9: the hook is executable and declares bash (settings.json invokes it as a bare command)" {
  [ -x "$HOOK" ] || { echo "$HOOK is not executable — a registered non-executable is a registered no-op"; false; }
  head -1 "$HOOK" | grep -q '^#!/bin/bash' || { echo "shebang: $(head -1 "$HOOK")"; false; }
}

@test "10: a blank timestamp is PADDED, so a tab-splitting reader is not shifted left" {
  # The sidecar is a three-cell tab row and cell 2 is NOT last, so an empty cell 2 would not read
  # back empty — tab is IFS whitespace, so it would shift the cwd into the timestamp column,
  # silently, exit 0. That is the class scripts/tsv-pad-lint.sh ratchets, and its rule is to pad at
  # the EMITTER because the read side cannot be repaired. `date` failing is the only way cell 2 can
  # go blank here, so that is the case pinned.
  shim="$BATS_TEST_TMPDIR/shim"; mkdir -p "$shim"
  printf '#!/bin/sh\nexit 1\n' > "$shim/date"; chmod +x "$shim/date"
  mkdir -p "$TASK_ATTRIB_TASKS_DIR/$SID"
  printf '{}' > "$TASK_ATTRIB_TASKS_DIR/$SID/21.json"
  run env PATH="$shim:$PATH" bash "$HOOK" <<<"$(payload 21)"
  [ "$status" -eq 0 ] || { echo "status=$status out=$output"; false; }
  f="$TASK_ATTRIB_TASKS_DIR/$SID/.owners/21"
  [ -f "$f" ] || { echo "no sidecar when date fails"; false; }
  line="$(cat "$f")"
  [ -n "$(cut -f2 <<<"$line")" ] || { echo "cell 2 is EMPTY — the next reader gets cwd in the ts column"; false; }
  [ "$(cut -f3 <<<"$line")" = "/Users/chrisren/Development/x" ] \
    || { echo "cell 3 shifted: $(cut -f3 <<<"$line")"; false; }
}
