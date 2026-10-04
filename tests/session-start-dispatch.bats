#!/usr/bin/env bats
# session-start-dispatch.bats — the one SessionStart process that runs the nine folded hooks
# (hooks/session-start-dispatch.sh, fix row 17; registration in migrations/0056).
#
# What it must preserve from the harness it replaces, each asserted on fixture children:
#   · every child gets the payload, and the merged output keeps both channels (context, banner) in
#     registration order; plain-text stdout counts as context
#   · one hung child costs only its own output, inside the bound, never the others'
#   · a FINISHED child's detached helper survives the bound (the kill keys on a live group leader)
#   · the merged context stays under the harness's per-hook cap

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd -P)"
  SSD="$REPO/hooks/session-start-dispatch.sh"
  D="$BATS_TEST_TMPDIR"; H="$D/hooks"; mkdir -p "$H"
  export CC_SSD_HOOK_DIR="$H" CC_SSD_BOUND_S=2
  HELPER_PID=""
}

teardown() { [ -z "$HELPER_PID" ] || kill "$HELPER_PID" 2>/dev/null || true; }

child() { # <name> <body>
  printf '#!/bin/bash\n%s\n' "$2" > "$H/$1"; chmod +x "$H/$1"
}

PAYLOAD='{"session_id":"sid-ssd-1","hook_event_name":"SessionStart","source":"startup"}'

dispatch() { # <children> [cap]
  printf '%s' "$PAYLOAD" > "$D/p"
  run env CC_SSD_CHILDREN="$1" CC_SSD_CAP="${2:-9500}" bash "$SSD" < "$D/p"
}

@test "merges JSON and plain-text children in order, both channels, and hands every child the payload" {
  child a.sh 'printf "%s" "{\"hookSpecificOutput\":{\"hookEventName\":\"SessionStart\",\"additionalContext\":\"A1\"},\"systemMessage\":\"S1\"}"'
  child b.sh 'echo P2'
  # shellcheck disable=SC2016  # the child's own program, expanded when it runs
  child c.sh 'jq -r .session_id; [ -n "$CC_HOOK_PARENT_PID" ] && echo parent-set'
  child d.sh 'printf "%s" "{\"systemMessage\":\"S4\"}"'
  child e.sh 'echo NEVER'; chmod -x "$H/e.sh"                        # not executable ⇒ skipped
  dispatch "a.sh b.sh c.sh d.sh e.sh missing.sh"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r .hookSpecificOutput.additionalContext)" = "$(printf 'A1\nP2\nsid-ssd-1\nparent-set')" ]
  [ "$(printf '%s' "$output" | jq -r .systemMessage)" = "$(printf 'S1\nS4')" ]
  [ "$(printf '%s' "$output" | jq -r .hookSpecificOutput.hookEventName)" = SessionStart ]
}

@test "a hung child is killed at the bound; the others' output survives and the dispatcher returns" {
  child fast.sh 'echo FAST'
  child hung.sh 'echo $$ > "'"$D"'/hung"; exec sleep 60'
  local t0=$SECONDS
  dispatch "fast.sh hung.sh"
  [ "$status" -eq 0 ]
  [ $((SECONDS - t0)) -lt 10 ]
  [ "$(printf '%s' "$output" | jq -r .hookSpecificOutput.additionalContext)" = FAST ]
  run kill -0 "$(cat "$D/hung")"
  [ "$status" -ne 0 ]                                              # the hung child was killed, not orphaned
}

@test "a finished child's detached helper outlives the bound even when another child is hung" {
  child spawner.sh 'sleep 30 >/dev/null 2>&1 & echo $! > "'"$D"'/helper"; echo SPAWNED'
  child hung.sh 'sleep 60'
  dispatch "spawner.sh hung.sh"
  [ "$status" -eq 0 ]
  HELPER_PID="$(cat "$D/helper")"
  kill -0 "$HELPER_PID"
}

@test "no child output ⇒ nothing printed, exit 0" {
  child quiet.sh 'exit 0'
  dispatch "quiet.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "the merged context is capped under the harness's per-hook cap" {
  child big.sh 'head -c 20000 /dev/zero | tr "\\0" x; echo'
  dispatch big.sh 9500
  [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext | length')" -eq 9500 ]
}

@test "the shipped child list names nine hooks that exist and none of the four kept separate" {
  run bash -c 'grep -o "CHILDREN:-[^}]*" "$1"' _ "$SSD"
  local list="${output#CHILDREN:-}" n=0 c
  for c in $list; do
    [ -x "$REPO/hooks/$c" ] || { echo "missing $c"; false; }
    n=$((n + 1))
  done
  [ "$n" -eq 9 ]
  for c in dod-persist.sh desk-brief-inject.sh mailbox-drain.sh mailbox-wake-arm.sh; do
    [[ " $list " != *" $c "* ]] || { echo "$c must stay separate"; false; }
  done
}
