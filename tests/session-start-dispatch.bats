#!/usr/bin/env bats
# session-start-dispatch.bats — the one SessionStart process that runs the ten folded hooks
# (hooks/session-start-dispatch.sh, fix row 17; registration in migrations/0056; v2 per
# docs/research/startup-hooks-2026-10-18/README.md Wave 2 and A3-dispatcher.md §6).
#
# What it must preserve from v1, each asserted on fixture children:
#   · every child gets the payload, and the merged output keeps both channels (context, banner) in
#     registration order; plain-text stdout counts as context
#   · a HEALTHY run prints v1's exact bytes — pinned against v1 itself, replayed from git
#   · a FINISHED child's detached helper survives the backstop (the kill keys on a live group leader)
# What v2 changes:
#   · it prints by CC_SSD_EMIT_S from process start; a late child keeps running and is killed only at
#     CC_SSD_LATE_S, never before, and nothing it does can hold the harness's stdout open
#   · every late, killed, cut, absent or malformed child is named FIRST in the systemMessage, and the
#     fail-open exits print a static, valid systemMessage instead of nothing
#   · the context cap is whole-or-nothing per child; tier 0 (the recycle packet) is never cut
#   · one ledger row per run, one late row per late child, an outbox byte-identical to stdout
# Everything runs under /bin/bash (3.2 on macOS), the interpreter the harness's shebang gets.
# shellcheck disable=SC2030,SC2031  # each @test is its own subshell: a per-test export is the point

setup() {
  export CC_STARTUP_HEALTH_DIR="$BATS_TEST_TMPDIR/startup-health"  # startup sentinels: never the live ~/.claude/state/startup-health
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd -P)"
  SSD="$REPO/hooks/session-start-dispatch.sh"
  D="$BATS_TEST_TMPDIR"; H="$D/hooks"; mkdir -p "$H"
  export HOME="$D/home"; mkdir -p "$HOME"                         # hermetic: no child reads the live ~/
  export CC_SSD_HOOK_DIR="$H" CC_SSD_LEDGER="$D/ledger.jsonl" CC_SSD_SPOOL="$D/spool"
  export CC_SSD_EMIT_S=9 CC_SSD_LATE_S=60
  unset CLAUDE_CONFIG_DIR
  # Wall-clock slack past EMIT. A3 §6 says EMIT + 2, a foreground figure: cc-bats runs suites in the
  # utility QoS band, where at load ~400 the same run measured 4.8-6.2 s at EMIT 2 (2.1 s in the
  # foreground) with the deadline itself honored (ledger total_ms ~2,700, lag_s 1). The property
  # under test is "returns at the deadline, not when the 60 s child ends", which 8 s still separates.
  SLACK="${SSD_TEST_SLACK:-8}"
}

# Late children outlive the dispatcher by design, so every one a test starts is recorded and reaped.
teardown() {
  local p
  if [ -f "$D/pids" ]; then while read -r p; do kill -KILL "$p" 2>/dev/null || true; done < "$D/pids"; fi
  chmod -R u+w "$D" 2>/dev/null || true
}

child() { # <name> <body>
  printf '#!/bin/bash\n%s\n' "$2" > "$H/$1"; chmod +x "$H/$1"
}
hung() { # <name> [stdout before hanging] — a child that records its pid and hangs
  child "$1" "${2:+echo $2; }echo \$\$ >> \"$D/pids\"; exec sleep 60"
}

PAYLOAD='{"session_id":"sid-ssd-1","hook_event_name":"SessionStart","source":"startup"}'

dispatch() { # <children> — fd 3 closed so a late child cannot hold bats' own pipe
  printf '%s' "$PAYLOAD" > "$D/p"
  run env CC_SSD_CHILDREN="$1" /bin/bash "$SSD" < "$D/p" 3>&-
}
ctx() { printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext // empty'; }
sm()  { printf '%s' "$output" | jq -r '.systemMessage // empty'; }
row() { jq -c 'select(.kind == null)' "$CC_SSD_LEDGER" | tail -1; }       # the main row of the last run
late_row() { [ -f "$CC_SSD_LEDGER" ] && jq -e -c "select(.kind == \"late\" and .c == \"$1\")" "$CC_SSD_LEDGER"; }
wait_for() { # <seconds> <command...>
  local i=0
  while [ "$i" -lt $(( $1 * 10 )) ]; do "${@:2}" >/dev/null 2>&1 && return 0; sleep 0.1; i=$((i + 1)); done
  return 1
}

@test "merges JSON and plain-text children in order, both channels, and hands every child the payload" {
  child a.sh 'printf "%s" "{\"hookSpecificOutput\":{\"hookEventName\":\"SessionStart\",\"additionalContext\":\"A1\"},\"systemMessage\":\"S1\"}"'
  child b.sh 'echo P2'
  # shellcheck disable=SC2016  # the child's own program, expanded when it runs
  child c.sh 'jq -r .session_id; [ -n "$CC_HOOK_PARENT_PID" ] && echo parent-set'
  child d.sh 'printf "%s" "{\"systemMessage\":\"S4\"}"'
  child e.sh 'echo NEVER'; chmod -x "$H/e.sh"                        # not executable ⇒ absent, named
  dispatch "a.sh b.sh c.sh d.sh e.sh missing.sh"
  [ "$status" -eq 0 ]
  [ "$(ctx)" = "$(printf 'A1\nP2\nsid-ssd-1\nparent-set')" ]
  [ "$(printf '%s' "$output" | jq -r .hookSpecificOutput.hookEventName)" = SessionStart ]
  # the two absent children are named first, one line each, then the banners in order
  [ "$(sm | sed -n 3,4p)" = "$(printf 'S1\nS4')" ]
  [[ "$(sm | sed -n 1p)" == "⚠ startup: e.sh is missing or not executable in "* ]] || false
  [[ "$(sm | sed -n 2p)" == "⚠ startup: missing.sh is missing or not executable in "* ]] || false
  [ "$(row | jq -r '[.kids[].st] | join(",")')" = ok,ok,ok,ok,absent,absent ]
}

@test "a healthy run prints v1's exact bytes, with no notice added (v1 replayed from git)" {
  # The control is the REAL v1 artifact, not a restatement of it: 38ee1eac7 is the last commit that
  # touched the v1 dispatcher. Real child names are used so the tier table is exercised and must
  # not reorder anything.
  git -C "$REPO" show 38ee1eac7:hooks/session-start-dispatch.sh > "$D/v1.sh"
  child recycle-failed-inject.sh 'printf "%s" "{\"hookSpecificOutput\":{\"hookEventName\":\"SessionStart\",\"additionalContext\":\"packet ✓ ünïcode\"}}"'
  child session-start.sh 'echo "MCP: 4 server(s) connected"; echo'
  child setup-plan-symlinks.sh 'printf "Plans: 3 open\n\n"'
  child accounts-board.sh 'printf "%s" "{\"systemMessage\":\"\\u001b[1mBOARD\\u001b[0m\\nline 2\"}"'
  child escalation-watch.sh 'exit 0'
  child failing.sh 'echo FAILED-BUT-SAID-THIS; exit 1'
  child frontier-status.sh 'printf "%s" "{\"systemMessage\":\"S-last\",\"hookSpecificOutput\":{\"hookEventName\":\"SessionStart\",\"additionalContext\":\"Frontier: open\"}}"'
  printf '%s' "$PAYLOAD" > "$D/p"
  local kids="recycle-failed-inject.sh session-start.sh setup-plan-symlinks.sh accounts-board.sh escalation-watch.sh failing.sh frontier-status.sh"
  CC_SSD_CHILDREN="$kids" CC_SSD_BOUND_S=9 /bin/bash "$D/v1.sh" < "$D/p" > "$D/v1.out" 3>&-
  CC_SSD_CHILDREN="$kids" /bin/bash "$SSD" < "$D/p" > "$D/v2.out" 3>&-
  [ -s "$D/v1.out" ]
  cmp "$D/v1.out" "$D/v2.out"
  [ "$(row | jq -r '.notices | length')" -eq 0 ]
}

@test "deadline: the dispatcher prints at EMIT with what finished and names the late child first" {
  child fast.sh 'echo FAST'
  hung slow.sh
  export CC_SSD_EMIT_S=3
  local t0; t0=$(date +%s)
  dispatch "fast.sh slow.sh"
  [ "$status" -eq 0 ]
  [ $(( $(date +%s) - t0 )) -lt $((3 + SLACK)) ]
  [ "$(ctx)" = FAST ]
  [[ "$(sm | sed -n 1p)" == "⚠ startup: slow.sh still running at 3s"* ]] || false
  [ "$(row | jq -r '.kids[1].st')" = late ]
}

@test "USR1 interrupts a blocking wait on /bin/bash, the primitive the deadline rests on" {
  /bin/bash --version | head -1 | grep -q 'version 3\.2' || skip "/bin/bash is not 3.2 here"
  # shellcheck disable=SC2016  # the inner shell's program
  run /bin/bash -c 'trap : USR1; sleep 30 & p=$!; (sleep 1; kill -USR1 $$) & t=$SECONDS; wait $p; rc=$?; kill $p; echo "$rc $((SECONDS - t))"' 3>&-
  [ "${output%% *}" -gt 128 ]
  [ "${output##* }" -le 2 ]
  # and end to end: the deadline holds under 3.2 with a child that never finishes
  hung slow.sh
  export CC_SSD_EMIT_S=2
  local t0; t0=$(date +%s)
  dispatch "slow.sh"
  [ $(( $(date +%s) - t0 )) -lt $((2 + SLACK)) ]
}

@test "a late child that finishes gets a late-ok row and a late outbox, and the run dir is removed" {
  child fast.sh 'echo FAST'
  child slow.sh "sleep 6; touch \"$D/marker\"; echo LATEX"
  export CC_SSD_EMIT_S=3 CC_SSD_LATE_S=20
  dispatch "fast.sh slow.sh"
  [ "$(ctx)" = FAST ]
  wait_for 25 late_row slow.sh
  [ -e "$D/marker" ]
  [ "$(late_row slow.sh | jq -r '"\(.st) \(.rc)"')" = "late-ok 0" ]
  [ "$(jq -r .hookSpecificOutput.additionalContext "$CC_SSD_SPOOL/late/sid-ssd-1.json")" = LATEX ]
  # shellcheck disable=SC2016  # the inner shell's program
  wait_for 5 bash -c '! ls -d "$1"/run.* >/dev/null 2>&1' _ "$CC_SSD_SPOOL"
}

@test "a hung child is not killed at the deadline but at LATE_S, then TERM/KILL; the others survive" {
  child fast.sh 'echo FAST'
  hung hung.sh
  export CC_SSD_EMIT_S=3 CC_SSD_LATE_S=5
  local t0; t0=$(date +%s)
  dispatch "fast.sh hung.sh"
  [ "$status" -eq 0 ]
  [ "$(ctx)" = FAST ]
  local hp; hp="$(head -1 "$D/pids")"
  kill -0 "$hp"                                                      # alive after the print
  wait_for 20 late_row hung.sh
  [ $(( $(date +%s) - t0 )) -ge 5 ]                                  # never before LATE_S
  [ "$(late_row hung.sh | jq -r .st)" = killed ]
  run kill -0 "$hp"
  [ "$status" -ne 0 ]                                                # killed, not orphaned
}

@test "a finished child's detached helper outlives the backstop even when another child is hung" {
  child spawner.sh "sleep 30 >/dev/null 2>&1 & echo \$! | tee -a \"$D/pids\" > \"$D/helper\"; echo SPAWNED"
  hung hung.sh
  export CC_SSD_EMIT_S=3 CC_SSD_LATE_S=4
  dispatch "spawner.sh hung.sh"
  [ "$status" -eq 0 ]
  wait_for 20 late_row hung.sh                                       # the backstop has fired
  kill -0 "$(cat "$D/helper")"
}

@test "no pipe hold: dispatcher | cat returns by the deadline while a late child still runs" {
  hung slow.sh
  printf '%s' "$PAYLOAD" > "$D/p"
  local t0; t0=$(date +%s)
  CC_SSD_CHILDREN=slow.sh CC_SSD_EMIT_S=2 /bin/bash "$SSD" < "$D/p" 3>&- | cat > "$D/out"
  [ $(( $(date +%s) - t0 )) -lt $((2 + SLACK)) ]
  kill -0 "$(head -1 "$D/pids")"
  jq -e .systemMessage "$D/out"
}

@test "no child output ⇒ nothing printed, exit 0" {
  child quiet.sh 'exit 0'
  dispatch "quiet.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "the context cap is whole-or-nothing: an oversized child is dropped whole and named, the rest kept" {
  child big.sh 'head -c 20000 /dev/zero | tr "\\0" x; echo'
  child small.sh 'echo SMALL'
  dispatch "big.sh small.sh"
  [ "$(ctx)" = SMALL ]
  [[ "$(sm)" == *"dropped big.sh's context (20000 chars)"* ]] || false
  [ "$(row | jq -r '.kids[0] | "\(.st) \(.cut)"')" = "cut ctx" ]
}

@test "tier 0 is kept whole while lower tiers that no longer fit are dropped and named" {
  child recycle-failed-inject.sh 'head -c 9200 /dev/zero | tr "\\0" x'
  child setup-plan-symlinks.sh 'head -c 400 /dev/zero | tr "\\0" y'
  child frontier-status.sh 'head -c 400 /dev/zero | tr "\\0" z'
  dispatch "recycle-failed-inject.sh setup-plan-symlinks.sh frontier-status.sh"
  [ "$(ctx | tr -cd x | wc -c | tr -d ' ')" -eq 9200 ]
  [ "$(ctx | tr -cd yz | wc -c | tr -d ' ')" -eq 0 ]
  [ "$(ctx | wc -c | tr -d ' ')" -le 9500 ]
  [[ "$(ctx)" == "Plans line missing this start"* ]] || false        # model-facing ⇒ one model line
  [[ "$(sm)" == *"dropped setup-plan-symlinks.sh's context (400 chars)"* ]] || false
  [[ "$(sm)" == *"dropped frontier-status.sh's context (400 chars)"* ]] || false
  [ "$(row | jq -r '[.kids[].st] | join(",")')" = ok,cut,cut ]
}

@test "tier 0 alone over the cap is truncated with a pointer to its packet, never dropped" {
  child recycle-failed-inject.sh 'head -c 12000 /dev/zero | tr "\\0" x'
  dispatch "recycle-failed-inject.sh"
  [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext | length')" -le 9500 ]
  [[ "$(ctx)" == *"[truncated "*" chars — read the full packet: ~/.claude/autonomy/recycle-failed/sid-ssd-1.prompt.md]" ]] || false
  [[ "$(sm)" == *"recycle-failed-inject.sh truncated"* ]]
}

@test "the systemMessage cap drops whole banners from the end and names each" {
  local b
  for b in a b c; do
    child "$b.sh" "printf '{\"systemMessage\":\"%s\"}' \"\$(head -c 4000 /dev/zero | tr '\\0' $b)\""
  done
  dispatch "a.sh b.sh c.sh"
  [ "$(printf '%s' "$output" | jq -r '.systemMessage | length')" -le 9000 ]
  [[ "$(sm | sed -n 1p)" == "⚠ startup: banners over the 9000-char cap → dropped c.sh's banner (4000 chars)" ]] || false
  [ "$(sm | tr -cd c | wc -c | tr -d ' ')" -lt 10 ]                  # no c-banner bytes, only the names
  [ "$(sm | tr -cd a | wc -c | tr -d ' ')" -ge 4000 ]
}

@test "a child killed by a signal has its partial output dropped and named, never merged" {
  child fast.sh 'echo FAST'
  # shellcheck disable=SC2016  # the child's own program
  child dies.sh 'echo PARTIAL; kill -9 $$'
  dispatch "fast.sh dies.sh"
  [ "$(ctx)" = FAST ]
  [[ "$(sm)" == "⚠ startup: dies.sh was killed (rc 137) → its partial output (8 chars) was dropped, not merged"* ]] || false
  [ "$(row | jq -r '.kids[1].st')" = killed ]
}

@test "unparseable JSON is merged as plain context, as the harness would, but named" {
  child bad.sh 'echo "{\"hookSpecificOutput\":"'
  dispatch "bad.sh"
  [ "$(ctx)" = '{"hookSpecificOutput":' ]
  [[ "$(sm)" == "⚠ startup: bad.sh printed unparseable JSON"* ]] || false
  [ "$(row | jq -r '.kids[0].st')" = malformed ]
}

@test "watchPaths are forwarded as a union and sessionTitle/reloadSkills pass through" {
  child a.sh 'printf "%s" "{\"hookSpecificOutput\":{\"hookEventName\":\"SessionStart\",\"watchPaths\":[\"/x\",\"/y\"],\"sessionTitle\":\"T1\"}}"'
  child b.sh 'printf "%s" "{\"hookSpecificOutput\":{\"hookEventName\":\"SessionStart\",\"watchPaths\":[\"/y\",\"/z\"],\"sessionTitle\":\"T2\",\"reloadSkills\":true}}"'
  dispatch "a.sh b.sh"
  [ "$(printf '%s' "$output" | jq -c .hookSpecificOutput)" = '{"hookEventName":"SessionStart","watchPaths":["/x","/y","/z"],"sessionTitle":"T1","reloadSkills":true}' ]
}

@test "model-line policy: a late model-facing child costs one context line, a late banner child none" {
  child fast.sh 'echo FAST'
  hung setup-task-symlinks.sh
  export CC_SSD_EMIT_S=3
  dispatch "fast.sh setup-task-symlinks.sh"
  [ "$(ctx)" = "$(printf 'Tasks line missing this start; active tasks are under .claude-tasks/_current/.\nFAST')" ]
  hung accounts-board.sh
  dispatch "fast.sh accounts-board.sh"
  [ "$(ctx)" = FAST ]
  [[ "$(sm)" == "⚠ startup: accounts-board.sh still running at 3s → the accounts board NOT shown"*"re-check: claude-accounts" ]]
}

@test "the outbox holds exactly the printed line" {
  child a.sh 'echo CTX; exit 0'
  child b.sh 'printf "%s" "{\"systemMessage\":\"B\"}"'
  printf '%s' "$PAYLOAD" > "$D/p"
  CC_SSD_CHILDREN="a.sh b.sh" /bin/bash "$SSD" < "$D/p" > "$D/out" 3>&-
  [ -s "$D/out" ]
  cmp "$D/out" "$CC_SSD_SPOOL/outbox/sid-ssd-1.startup.json"
}

@test "a harness TERM leaves a harness-term ledger row naming what was pending, and a partial outbox" {
  child fast.sh 'echo FAST'
  hung hang.sh
  printf '%s' "$PAYLOAD" > "$D/p"
  CC_SSD_CHILDREN="fast.sh hang.sh" CC_SSD_EMIT_S=20 CC_SSD_LATE_S=21 /bin/bash "$SSD" < "$D/p" > "$D/out" 3>&- &
  local dp=$!
  wait_for 15 test -s "$D/pids"
  # shellcheck disable=SC2016  # the inner shell's program; r01 existing means fast.sh has finished
  wait_for 15 bash -c 'ls "$1"/run.*/r01' _ "$CC_SSD_SPOOL"
  kill -TERM "$dp"
  wait "$dp" || true
  jq -e -c 'select(.kind == "harness-term") | select(.pending == ["hang.sh"] and .finished == ["fast.sh"] and .printed == false)' "$CC_SSD_LEDGER"
  jq -e '.systemMessage | startswith("⚠ session-start-dispatch: cancelled by Claude Code")' "$CC_SSD_SPOOL/outbox/sid-ssd-1.startup.json"
  [ ! -s "$D/out" ]
}

@test "no jq on PATH ⇒ one static, valid systemMessage naming the check, exit 0" {
  mkdir -p "$D/bin"
  local t
  for t in ps mktemp mkdir cat stat mv rm sleep; do ln -s "$(PATH=/usr/bin:/bin command -v "$t")" "$D/bin/$t"; done
  child a.sh 'echo A'
  printf '%s' "$PAYLOAD" > "$D/p"
  run env PATH="$D/bin" CC_SSD_CHILDREN=a.sh /bin/bash "$SSD" < "$D/p" 3>&-
  [ "$status" -eq 0 ]
  printf '%s' "$output" | python3 -I -c 'import json,sys; d=json.loads(sys.stdin.read()); assert set(d)=={"systemMessage"}; assert d["systemMessage"].startswith("⚠ session-start-dispatch: jq is not on PATH")'
}

@test "no work dir (spool and TMPDIR unwritable) ⇒ a static, valid systemMessage, exit 0" {
  mkdir -p "$D/ro"; chmod 500 "$D/ro"
  child a.sh "touch \"$D/a.ran\"; echo A"
  printf '%s' "$PAYLOAD" > "$D/p"
  run env CC_SSD_SPOOL="$D/ro/spool" TMPDIR="$D/ro" CC_SSD_CHILDREN=a.sh /bin/bash "$SSD" < "$D/p" 3>&-
  [ "$status" -eq 0 ]
  printf '%s' "$output" | python3 -I -c 'import json,sys; d=json.loads(sys.stdin.read()); assert d["systemMessage"].startswith("⚠ session-start-dispatch: could not create a work dir")'
  [ ! -e "$D/a.ran" ]
}

@test "nothing executable ⇒ a static, valid systemMessage, exit 0" {
  dispatch "missing-1.sh missing-2.sh"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | python3 -I -c 'import json,sys; d=json.loads(sys.stdin.read()); assert d["systemMessage"].startswith("⚠ session-start-dispatch: none of the startup hooks")'
}

@test "ledger: 20 parallel dispatches append 20 parseable rows with the v1 row fields" {
  child a.sh 'echo A'
  child b.sh 'printf "%s" "{\"systemMessage\":\"B\"}"'
  printf '%s' "$PAYLOAD" > "$D/p"
  local i
  export CC_SSD_EMIT_S=30                                            # 20 at once at load: nobody late
  for i in $(seq 1 20); do
    CC_SSD_CHILDREN="a.sh b.sh" /bin/bash "$SSD" < "$D/p" > "$D/out.$i" 3>&- &
  done
  wait
  [ "$(jq -s 'length' "$CC_SSD_LEDGER")" -eq 20 ]
  jq -e -s 'all(.[]; .v == 1 and .sid == "sid-ssd-1" and .src == "startup" and .printed == true
                and (.total_ms | type) == "number" and (.kids | length) == 2
                and all(.kids[]; .st == "ok" and .rc == 0 and .ms >= 0))' "$CC_SSD_LEDGER"
}

@test "the shipped child list names eleven hooks that exist and none of the four kept separate" {
  run bash -c 'grep -o "CHILDREN:-[^}]*" "$1"' _ "$SSD"
  local list="${output#CHILDREN:-}" n=0 c
  for c in $list; do
    [ -x "$REPO/hooks/$c" ] || { echo "missing $c"; false; }
    n=$((n + 1))
  done
  # nine folded by 0056, plus recycle-failed-inject.sh (§D4) — first, and tier 0, so it is never cut —
  # plus lever-arm-start.sh (USAGE_LEVERS.md § W7+ §3, the usage levers' session stamp)
  [ "$n" -eq 11 ]
  [ "${list%% *}" = recycle-failed-inject.sh ]
  for c in dod-persist.sh desk-brief-inject.sh mailbox-drain.sh mailbox-wake-arm.sh; do
    [[ " $list " != *" $c "* ]] || { echo "$c must stay separate"; false; }
  done
}

@test "every shipped child has a row in the merge's table" {
  run bash -c 'grep -o "CHILDREN:-[^}]*" "$1"' _ "$SSD"
  local c
  for c in ${output#CHILDREN:-}; do
    grep -qF "\"$c\": {tier:" "$REPO/hooks/lib/ssd-merge.jq" || { echo "no table row for $c"; false; }
  done
}
