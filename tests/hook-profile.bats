#!/usr/bin/env bats
# hook-profile.bats — the lean hook profile (hooks/lib/hook-profile.sh, fix row 16 of
# docs/research/concurrency-scale-2026-10-04/README.md).
#
# Two contracts:
#   1. The predicate: advisory hooks skip under CC_HOOK_PROFILE=lean or a subagent payload; lead-only
#      hooks skip on a subagent payload only; an agent_id that is merely QUOTED in the command or
#      escaped inside a string never reads as the caller's identity.
#   2. Each wired hook exits BEFORE any jq or python3 when it skips — that is the whole saving — and
#      still reaches them on an ordinary top-level payload (the positive control that proves the
#      jq/python3 stubs are actually on the path the hook takes).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd -P)"
  LIB="$REPO/hooks/lib/hook-profile.sh"
  D="$BATS_TEST_TMPDIR"
  export HOME="$D/home"; mkdir -p "$HOME/.claude/logs" "$D/bin" "$D/cwd"
  unset CC_HOOK_PROFILE
  # jq / python3 stubs that record being reached and then behave as absent
  for t in jq python3; do
    printf '#!/bin/bash\necho %s >> "%s/reached"\nexit 1\n' "$t" "$D" > "$D/bin/$t"
    chmod +x "$D/bin/$t"
  done
}

skip_says() { # <class> <payload> → prints yes|no
  run bash -c '. "$1"; cc_hook_skip "$2" "$3" && echo yes || echo no' _ "$LIB" "$1" "$2"
  printf '%s' "$output"
}

LEAD='{"session_id":"s1","hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"true"}}'
SUB='{"session_id":"s1","agent_id":"a1b2c3d4","agent_type":"general-purpose","hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"true"}}'

@test "advisory: skipped under CC_HOOK_PROFILE=lean and inside a subagent, run otherwise" {
  [ "$(skip_says advisory "$LEAD")" = no ]
  [ "$(skip_says advisory "$SUB")" = yes ]
  [ "$(CC_HOOK_PROFILE=lean skip_says advisory "$LEAD")" = yes ]
  [ "$(CC_HOOK_PROFILE=lean skip_says advisory "")" = yes ]     # env alone, before stdin is read
  [ "$(CC_HOOK_PROFILE=full skip_says advisory "$LEAD")" = no ]
}

@test "lead-only: skipped inside a subagent only — a lean headless lead still runs it" {
  [ "$(skip_says lead-only "$SUB")" = yes ]
  [ "$(skip_says lead-only "$LEAD")" = no ]
  [ "$(CC_HOOK_PROFILE=lean skip_says lead-only "$LEAD")" = no ]
}

@test "an agent_id quoted in the command or escaped in a string is not the caller's identity" {
  quoted='{"session_id":"s1","tool_name":"Bash","tool_input":{"command":"grep \"agent_id\":\"a1b2\" x"}}'
  [ "$(skip_says advisory "$quoted")" = no ]
  # a key after tool_input (CC emits identity first) is ignored too
  after='{"session_id":"s1","tool_input":{"command":"true"},"agent_id":"a1b2"}'
  [ "$(skip_says advisory "$after")" = no ]
  [ "$(skip_says advisory '{"agent_id":""}')" = no ]               # empty id is not a subagent
  [ "$(skip_says bogus "$SUB")" = no ]                               # unknown class never skips
}

run_hook() { # <hook> <payload> [arg...] → status in $status; reached tools in $D/reached
  local h="$1" p="$2"; shift 2
  rm -f "$D/reached"
  printf '%s' "$p" > "$D/payload"
  run env PATH="$D/bin:/usr/bin:/bin" bash "$REPO/hooks/$h" "$@" < "$D/payload"
}

reached() { [ -s "$D/reached" ]; }

@test "each advisory hook exits before jq/python3 when skipped, and reaches them when not" {
  local h
  for h in log-bash.sh relay-verbatim.sh teammate-checkpoint.sh memory-index-drain.sh bash-output-offload.sh; do
    run_hook "$h" "$SUB"
    [ "$status" -eq 0 ] || { echo "$h subagent rc=$status"; false; }
    ! reached || { echo "$h reached $(cat "$D/reached") on a subagent payload"; false; }
    CC_HOOK_PROFILE=lean run_hook "$h" "$LEAD"
    ! reached || { echo "$h reached $(cat "$D/reached") under lean"; false; }
    run_hook "$h" "$LEAD"
    reached || { echo "$h never reached jq/python3 on a lead payload: the control is vacuous"; false; }
  done
}

@test "teammate-checkpoint's Stop checkpoint is never skipped, even under lean" {
  stop='{"session_id":"s1","agent_id":"a1b2c3d4","hook_event_name":"Stop","cwd":"/nonexistent"}'
  CC_HOOK_PROFILE=lean run_hook teammate-checkpoint.sh "$stop"
  reached
}

@test "each lead-only hook exits before jq inside a subagent, and still runs for a lean lead" {
  run_hook waiting-recycle.sh "$SUB"
  [ "$status" -eq 0 ]; ! reached || false     # a bare `! x` mid-test is errexit-exempt (dead)
  run_hook mailbox-drain.sh "$SUB" post-tool
  [ "$status" -eq 0 ]; ! reached || false     # a bare `! x` mid-test is errexit-exempt (dead)
  CC_HOOK_PROFILE=lean run_hook mailbox-drain.sh "$LEAD" post-tool
  reached
  CC_HOOK_PROFILE=lean run_hook waiting-recycle.sh "$LEAD"
  reached
}

@test "a missing lib fails open to the full hook" {
  mkdir -p "$D/h"
  cp "$REPO/hooks/relay-verbatim.sh" "$D/h/"                 # no lib/ beside it
  rm -f "$D/reached"
  run env PATH="$D/bin:/usr/bin:/bin" bash "$D/h/relay-verbatim.sh" <<< "$SUB"
  [ "$status" -eq 0 ]
  reached
}
