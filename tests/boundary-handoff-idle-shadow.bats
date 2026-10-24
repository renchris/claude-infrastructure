#!/usr/bin/env bats
# boundary-handoff-idle-shadow.bats — the LOG-ONLY idle-recycle shadow in hooks/boundary-handoff.sh
# (docs/plans/USAGE_LEVERS.md W4). Owner suite for one contract: at a Stop, the hook appends one line
# to $CC_IRS_LOG saying whether the idle gap that opened the turn would have earned a recycle
# advisory (idle >= 15 min at >= 150k context, the gap not ended by the session's own background
# job), and it changes nothing else the hook prints or records.
#
# RED-proof: against the pre-W4 hook (git show HEAD~1:hooks/boundary-handoff.sh, before the shadow
# block) every case that expects a line fails at its `[ -s "$CC_IRS_LOG" ]` / line-count assertion,
# because that hook writes no such log; the parity half passes there too, which is the point of it.
#
# Assertions are simple commands only (bash exempts `[[ ]]` from errexit in a bats body).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/boundary-handoff.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_FIRE_CAPACITY_GATE=off
  export CC_TELEMETRY_DIR="$BATS_TEST_TMPDIR/tel"; mkdir -p "$CC_TELEMETRY_DIR"
  export CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_BOUNDARY_LATCH_DIR="$BATS_TEST_TMPDIR/latch"
  export CC_CONTINUE_SENTINEL="$BATS_TEST_TMPDIR/no-such-sentinel"
  export CC_RECYCLE_RETRY_DIR="$BATS_TEST_TMPDIR/recycle-retry"
  export CC_IRS_LOG="$BATS_TEST_TMPDIR/irs.jsonl"
  export CC_BOUNDARY_T_FREEWIN=0
  unset WRAP_SESSION_ID CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID CC_IRS CC_IRS_K CC_IRS_N_MIN
  NOW="$(date +%s)"
  TP="$BATS_TEST_TMPDIR/t.jsonl"
  # 40% fill on a 1M window sits below every advisory threshold, so the hook's own disposition is a
  # plain below-threshold abstain: any stdout at all would be the shadow leaking into the advisory.
  jq -nc --argjson ts "$NOW" --arg cwd "$BATS_TEST_TMPDIR" \
    '{ts:$ts,session_id:"sidS",cwd:$cwd,config_dir:"/cfg",used_pct:40,input_tokens:400000}' \
    > "$CC_TELEMETRY_DIR/sidS.json"
}

iso() { jq -rn --argjson e "$1" '$e | todate | sub("Z$"; ".123Z")'; }
asst() { # $1=epoch $2=context tokens
  jq -nc --arg t "$(iso "$1")" --argjson c "$2" \
    '{type:"assistant",timestamp:$t,message:{model:"claude-opus-5-5",usage:{input_tokens:2,cache_read_input_tokens:($c-1002),cache_creation_input_tokens:1000}}}'
}
prompt() { jq -nc --arg t "$(iso "$1")" --arg s "$2" '{type:"user",timestamp:$t,message:{role:"user",content:$s}}'; }
toolres() { jq -nc --arg t "$(iso "$1")" '{type:"user",timestamp:$t,message:{role:"user",content:[{type:"tool_result",tool_use_id:"tu1",content:"ok"}]}}'; }
notice() { # $1=epoch $2=summary
  prompt "$1" "$(printf '<task-notification>\n<task-id>b1</task-id>\n<tool-use-id>tu9</tool-use-id>\n<status>completed</status>\n<summary>%s</summary>\n</task-notification>' "$2")"
}

# transcript <idle seconds> <context at idle> <opener: prompt|job|watcher> [growth in the new turn]
# One finished turn, an idle gap, then the turn this Stop closes (its context grows by <growth>).
transcript() {
  local g="$1" c="$2" d="${4:-5000}" t0=$(( NOW - $1 - 120 ))
  {
    prompt $(( t0 - 60 )) "first task"
    asst   $(( t0 - 50 )) "$c"
    toolres $(( t0 - 40 ))
    asst   "$t0" "$c"
    case "$3" in
      prompt)  prompt $(( t0 + g - 2 )) "next step" ;;
      job)     notice $(( t0 + g - 2 )) 'Background command "bats tests/x.bats" completed (exit code 0)' ;;
      watcher) notice $(( t0 + g - 2 )) 'Background command "cc-await-ping --timeout 3300" completed' ;;
    esac
    asst   $(( t0 + g )) $(( c + d ))
    toolres $(( t0 + g + 10 ))
    asst   $(( t0 + g + 20 )) $(( c + d + 1000 ))
  } > "$TP"
}

# stop <on|off> — one Stop; stdout to $BATS_TEST_TMPDIR/<arm>.out, the IDL row (minus its clock) to .idl
stop() {
  rm -f "$CC_IDL"
  jq -cn --arg t "$TP" '{session_id:"sidS",transcript_path:$t}' \
    | CC_IRS="$1" "$HOOK" > "$BATS_TEST_TMPDIR/$1.out" 2>/dev/null
  jq -c 'del(.ts)' "$CC_IDL" > "$BATS_TEST_TMPDIR/$1.idl"
}
parity() {
  cmp -s "$BATS_TEST_TMPDIR/on.out" "$BATS_TEST_TMPDIR/off.out" || { echo "stdout differs"; cat "$BATS_TEST_TMPDIR"/o*.out; false; }
  cmp -s "$BATS_TEST_TMPDIR/on.idl" "$BATS_TEST_TMPDIR/off.idl" || { echo "IDL differs"; cat "$BATS_TEST_TMPDIR"/o*.idl; false; }
  [ ! -s "$BATS_TEST_TMPDIR/on.out" ] || { echo "the shadow printed: $(cat "$BATS_TEST_TMPDIR/on.out")"; false; }
}
field() { jq -r ".$1" "$CC_IRS_LOG"; }

@test "20 idle minutes at 300k: one line saying it would have advised, and the hook's output and IDL row are unchanged" {
  transcript 1200 300000 prompt
  stop off
  [ ! -e "$CC_IRS_LOG" ] || { echo "CC_IRS=off still wrote"; cat "$CC_IRS_LOG"; false; }
  stop on
  parity
  [ "$(wc -l < "$CC_IRS_LOG" | tr -d ' ')" = 1 ] || { cat "$CC_IRS_LOG"; false; }
  [ "$(field v)" = ok ]
  [ "$(field gap_s)" = 1200 ]
  [ "$(field ctx_at_idle)" = 300000 ]
  [ "$(field would_advise)" = true ]
  [ "$(field sid)" = sidS ]
}

@test "the threshold is the context at IDLE, not the context now: 100k at idle is logged as not advised" {
  # Telemetry says 400k now and this turn's own requests reach 300k+, so only the context at the
  # idle point (100k) can make the answer "no".
  transcript 1200 100000 prompt 200000
  stop off; stop on
  parity
  [ "$(field would_advise)" = false ]
  [ "$(field ctx_at_idle)" = 100000 ]
}

@test "a gap ended by the session's own background job is busy; one ended by a watcher is idle" {
  transcript 1800 300000 job
  stop off; stop on
  parity
  [ "$(field busy_notice)" = true ]
  [ "$(field would_advise)" = false ]
  rm -f "$CC_IRS_LOG"
  transcript 1800 300000 watcher
  stop on
  [ "$(field busy_notice)" = false ]
  [ "$(field would_advise)" = true ]
}

@test "a gap shorter than 15 minutes writes nothing" {
  transcript 600 300000 prompt
  stop on
  [ ! -s "$CC_IRS_LOG" ] || { cat "$CC_IRS_LOG"; false; }
  [ -s "$CC_IDL" ]   # the hook did evaluate this Stop
}
