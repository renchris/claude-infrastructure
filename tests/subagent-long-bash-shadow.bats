#!/usr/bin/env bats
# subagent-long-bash-shadow — the COUNT-ONLY subagent rule (docs/plans/USAGE_LEVERS.md § W3).
#
# Owns: which calls the rule counts (a subagent's foreground Bash with timeout > 270 s), which of
# those the narrowed rule would deny and under which class, that it never prints or decides, and
# that its host hooks/validate-bash.sh feeds it without changing a verdict.
# RED-proof: new behaviour. Mutants checked by hand on scratch copies: dropping the 270000 bound
# fails (2); dropping the validate-bash passenger block fails (4).
# W6 RED-proof (2026-10-24): against the base hook (git show 11f7f87fa:…) (5) fails: no
# would_deny_class field, and `bash -c '<loop>'` was not a poll loop.
# S3 RED-proof (2026-10-25): against the base hooks (git show c43f39d2b:…) (6)-(10) fail: rows are
# v:2 with no arm and no wider class, and validate-bash never pipes a no-timeout call, so no d4_follow.
#
# Hermetic: $HOME and the log are fixtures; validate-bash runs with the same isolation its own
# suites use (CC_SHARED_CHECKOUT, CC_VB_DECISION_LOG, no kitty).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/subagent-long-bash-shadow.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_SUBAGENT_LONG_BASH_LOG="$BATS_TEST_TMPDIR/slb.jsonl"
  export CC_SHARED_CHECKOUT="$BATS_TEST_TMPDIR/shared"; mkdir -p "$CC_SHARED_CHECKOUT"
  export CC_VB_DECISION_LOG="$BATS_TEST_TMPDIR/decisions.jsonl"
  export IT2_WRAPPER_NO_KITTY=1
  export SHIP_LAND_CONVERGE=off DEPLOY_REPO="$BATS_TEST_TMPDIR/deploy-repo"
  unset KITTY_WINDOW_ID CC_SUBAGENT_LONG_BASH VALIDATE_BASH_DISABLED VALIDATE_BASH_LEGACY CC_VB_AGENT_RM_DENY
  if ! command -v jq >/dev/null 2>&1; then skip "jq not installed"; fi
}

payload() { # <command> [timeout_ms] [agent_id] [run_in_background]
  jq -nc --arg c "$1" --argjson t "${2:-600000}" --arg a "${3-agent-a1}" --argjson bg "${4:-false}" \
    '{tool_name:"Bash",session_id:"sid-1",tool_use_id:"toolu_1",transcript_path:"/x/sid-1.jsonl",
      tool_input:({command:$c,timeout:$t} + (if $bg then {run_in_background:true} else {} end))}
     + (if $a == "" then {} else {agent_id:$a,agent_type:"workflow-lean"} end)'
}
feed() { run bash -c 'printf "%s" "$1" | /bin/bash "$2"' _ "$(payload "$@")" "$HOOK"; }
last_why() { tail -1 "$CC_SUBAGENT_LONG_BASH_LOG" | jq -r '.why // "-"'; }

@test "(1) narrowed classes: what the command says it will do" {
  while IFS='|' read -r want cmd; do
    feed "$cmd"
    [ "$status" -eq 0 ]; [ -z "$output" ]
    got="$(last_why)"
    [ "$got" = "$want" ] || { echo "cmd=[$cmd] want=$want got=$got"; false; }
  done <<'EOF'
poll-loop|until [ -f /tmp/done ]; do sleep 30; done
poll-loop|for i in $(seq 40); do gh pr view 1 && break; sleep 20; done
long-sleep|sleep 600
waiter|cc-await-ping abc --timeout 3300
waiter|timeout 900 ./run.sh
waiter|timeout 5m make check
waiter|./start.sh & wait
long-runner|bats tests/foo.bats
long-runner|bash scripts/ship-land.sh
long-runner|pnpm test
-|git status
-|sleep 30
-|timeout 60 curl -s example.com
EOF
  # each would-deny also arms a follow row for the next call (S3): count the verdict rows
  [ "$(jq -s '[.[] | select(.kind == "subagent_bash")] | length' "$CC_SUBAGENT_LONG_BASH_LOG")" -eq 13 ]
  jq -e -s '[.[] | select(.kind == "subagent_bash")] | all(.[]; .broad == true and .would == "count" and (.cmd_sha256 | length) == 64
             and .agent_type == "workflow-lean" and .tool_use_id == "toolu_1")' "$CC_SUBAGENT_LONG_BASH_LOG" >/dev/null
}

@test "(2) not counted: the main thread, a backgrounded call, timeout <= 270 s, no timeout" {
  feed 'sleep 600' 600000 ''
  feed 'sleep 600' 600000 agent-a1 true
  feed 'sleep 600' 270000
  run bash -c 'jq -nc "{session_id:\"s\",agent_id:\"a\",tool_input:{command:\"sleep 600\"}}" | /bin/bash "$1"' _ "$HOOK"
  [ "$status" -eq 0 ]
  [ ! -s "$CC_SUBAGENT_LONG_BASH_LOG" ]
}

@test "(3) never decides: rc 0 and empty stdout on garbage, and CC_SUBAGENT_LONG_BASH=off logs nothing" {
  run bash -c 'printf "{not json" | /bin/bash "$1"' _ "$HOOK"
  [ "$status" -eq 0 ]; [ -z "$output" ]
  CC_SUBAGENT_LONG_BASH=off feed 'sleep 600'
  [ "$status" -eq 0 ]
  [ ! -s "$CC_SUBAGENT_LONG_BASH_LOG" ]
}

@test "(4) hosted by validate-bash: the row is written and the verdict is the same with the rule off" {
  vb() { run bash -c 'printf "%s" "$1" | /bin/bash "$2"' _ "$1" "$REPO/hooks/validate-bash.sh"; }
  # a subagent rm that validate-bash denies, with a long timeout: still denied, and counted
  p="$(payload 'rm -rf /var/x/out; sleep 600')"
  vb "$p"; on_status=$status; on_out="$output"
  [ "$(printf '%s' "$on_out" | jq -r '.hookSpecificOutput.permissionDecision')" = deny ]
  [ "$(jq -r .why "$CC_SUBAGENT_LONG_BASH_LOG")" = long-sleep ]
  CC_SUBAGENT_LONG_BASH=off vb "$p"
  [ "$status" -eq "$on_status" ]; [ "$output" = "$on_out" ]
  # a benign one passes silently either way
  vb "$(payload 'sleep 400')"
  [ "$status" -eq 0 ]; [ -z "$output" ]
  [ "$(jq -sr '[.[] | .kind] | join(",")' "$CC_SUBAGENT_LONG_BASH_LOG")" = "subagent_bash,d4_follow,subagent_bash" ]
  # the main thread's call never reaches the rule
  vb "$(payload 'sleep 400' 600000 '')"
  [ "$(wc -l < "$CC_SUBAGENT_LONG_BASH_LOG")" -eq 3 ]
}

@test "(5) W6: would-deny splits by class, and an inner timeout under 300 s is exempt from the count" {
  # want: would_deny_class|narrow|exempt|inner_timeout_s|command
  while IFS='|' read -r cls nar ex inner cmd; do
    feed "$cmd"
    [ "$status" -eq 0 ]; [ -z "$output" ]
    got="$(tail -1 "$CC_SUBAGENT_LONG_BASH_LOG" | jq -r '[(.would_deny_class // "-"), .narrow, (.exempt // "-"), (.inner_timeout_s // "-")] | join("|")')"
    [ "$got" = "$cls|$nar|$ex|$inner" ] || { echo "cmd=[$cmd] want=$cls|$nar|$ex|$inner got=$got"; false; }
  done <<'ROWS'
poll-loop|true|-|-|until [ -f /tmp/done ]; do sleep 30; done
long-runner|true|-|-|bats tests/foo.bats
waiter|true|-|-|cc-await-ping abc --timeout 3300
waiter|true|-|-|sleep 600
waiter|true|-|900|timeout 900 ./run.sh
-|false|inner-timeout|260|timeout 260 bash -c 'until [ -f /tmp/done ]; do sleep 30; done'
-|false|inner-timeout|240|timeout 4m bats tests/foo.bats
poll-loop|true|-|600|timeout 260 ./a.sh; timeout 600 bash -c 'while :; do sleep 20; done'
-|false|-|60|timeout 60 curl -s example.com
ROWS
  # the original class stays visible on an exempt row
  [ "$(jq -sr '[.[] | select(.exempt) | .why] | join(",")' "$CC_SUBAGENT_LONG_BASH_LOG")" = "poll-loop,long-runner" ]
}

# ── W7+ S3: v3 rows, the D4 arm, the wider pattern, d4_follow, 2 KB rows ────────────────────────
s3_flags() { # <mode> <pct> — a flag file with salted D4 entry, plus a fresh guard heartbeat
  export CC_LEVER_STATE_DIR="$BATS_TEST_TMPDIR/levers"; mkdir -p "$CC_LEVER_STATE_DIR"
  jq -nc --arg m "$1" --argjson p "$2" '{v:1,rev:7,levers:{D4:{stage:"S0",mode:$m,pct:$p,holdback:0,
    salt:"s3-d4-salt",split_salt:"s3-split"}}}' > "$CC_LEVER_STATE_DIR/flags.json"
  touch "$CC_LEVER_STATE_DIR/guard.heartbeat"
}
vbp() { printf '%s' "$1" | /bin/bash "$REPO/hooks/validate-bash.sh"; }
# p3 <command> <timeout_ms|-> <tool_use_id> [agent_id] — a payload with its own ids; "-" = no timeout
p3() {
  jq -nc --arg c "$1" --arg t "$2" --arg u "$3" --arg a "${4:-agent-a1}" \
    '{tool_name:"Bash",session_id:"sid-1",tool_use_id:$u,agent_id:$a,agent_type:"general-purpose",
      transcript_path:"/Users/u/.claude-next2/projects/p/sid-1.jsonl",
      tool_input:({command:$c} + (if $t == "-" then {} else {timeout:($t|tonumber)} end))}'
}

@test "(6) S3 v3 row: UTC Z, acct and tp_acct, and the D4 arm per agent_id equals the python twin's" {
  s3_flags shadow 0
  for a in agent-a1 agent-b2 agent-c3; do
    printf '%s' "$(p3 'sleep 600' 600000 "t-$a" "$a")" | CLAUDE_CONFIG_DIR="$HOME/.claude-next3" /bin/bash "$HOOK"
  done
  [ "$(wc -l < "$CC_SUBAGENT_LONG_BASH_LOG")" -eq 3 ]
  jq -e -s 'all(.[]; .v == 3 and (.ts | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$"))
             and .acct == ".claude-next3" and .tp_acct == ".claude-next2"
             and .arm.lever == "D4" and .arm.flag_src == "file" and .arm.arm == "ctrl" and .arm.pct_eff == 0
             and .arm.unit == .agent_id)' "$CC_SUBAGENT_LONG_BASH_LOG" >/dev/null
  # the arm (u, split) is the S1 control plane's, not re-derived: lever_flags.py over the same unit
  while read -r a u split; do
    want="$(/usr/bin/python3 -I "$REPO/hooks/lib/lever_flags.py" arm D4 "$a" | jq -r '"\(.u) \(.split)"')"
    [ "$u $split" = "$want" ] || { echo "$a: hook=$u $split python=$want"; false; }
  done < <(jq -r '"\(.agent_id) \(.arm.u) \(.arm.split)"' "$CC_SUBAGENT_LONG_BASH_LOG")
}

@test "(7) S3 wider pattern is its own class: never narrow, never would_deny_class" {
  # want: wider|wider_would_deny|would_deny_class|command
  while IFS='|' read -r w wwd cls cmd; do
    feed "$cmd"
    [ "$status" -eq 0 ]; [ -z "$output" ]
    got="$(tail -1 "$CC_SUBAGENT_LONG_BASH_LOG" | jq -r '[(.wider // "-"), .wider_would_deny, (.would_deny_class // "-")] | join("|")')"
    [ "$got" = "$w|$wwd|$cls" ] || { echo "cmd=[$cmd] want=$w|$wwd|$cls got=$got"; false; }
  done <<'ROWS'
time-sleep|true|-|python3 -c "import time; time.sleep(400)"
select-undef|true|-|perl -e 'select(undef, undef, undef, 400)'
time-sleep|false|-|timeout 200 python3 -c "import time; time.sleep(400)"
time-sleep|false|poll-loop|while true; do python3 -c "import time; time.sleep(5)"; sleep 10; done
-|false|-|python3 -c "print(1)"
ROWS
  [ "$(jq -s '[.[] | select(.wider != null and .narrow)] | length' "$CC_SUBAGENT_LONG_BASH_LOG")" -eq 1 ]
}

@test "(8) S3 follow pipe: validate-bash links an agent's next Bash call to its would-deny, once" {
  vbp "$(p3 'until [ -f /tmp/done ]; do sleep 30; done' 600000 t1)" >/dev/null
  [ -e "$CC_SUBAGENT_LONG_BASH_LOG.pending/agent-a1" ]
  vbp "$(p3 'git status' 600000 t-other agent-zz)" >/dev/null     # another agent: not a follow
  vbp "$(p3 'echo hi; echo rc=$?' - t2)" >/dev/null               # no timeout: piped only as a follow
  vbp "$(p3 'echo again' - t3)" >/dev/null                         # marker consumed: nothing logged
  [ "$(jq -sc '[.[] | select(.kind == "d4_follow")
       | [.tool_use_id, .follows_tool_use_id, .follows_class, .echo_rc, .same_cmd, .arm.unit]]' "$CC_SUBAGENT_LONG_BASH_LOG")" \
    = '[["t2","t1","poll-loop",true,false,"agent-a1"]]' ]
  [ ! -e "$CC_SUBAGENT_LONG_BASH_LOG.pending/agent-a1" ]
  [ "$(jq -sr '[.[] | .tool_use_id] | join(",")' "$CC_SUBAGENT_LONG_BASH_LOG")" = "t1,t-other,t2" ]
  # a wider-pattern would-deny arms the pipe too, and a re-issued identical command reads same_cmd
  c='python3 -c "import time; time.sleep(400)"'
  vbp "$(p3 "$c" 600000 t4)" >/dev/null
  vbp "$(p3 "$c" 600000 t5)" >/dev/null
  [ "$(jq -sc '[.[] | select(.kind == "d4_follow" and .tool_use_id == "t5") | [.follows_wider, .same_cmd]]' "$CC_SUBAGENT_LONG_BASH_LOG")" \
    = '[["time-sleep",true]]' ]
}

@test "(9) S3 pct 0 never denies, and nor does a raised arm: the shadow has no deny path" {
  for mode_pct in "shadow 0" "live 100"; do
    # shellcheck disable=SC2086  # two words on purpose
    s3_flags $mode_pct
    : > "$CC_SUBAGENT_LONG_BASH_LOG"
    run vbp "$(p3 'until [ -f /tmp/done ]; do sleep 30; done' 600000 t1)"
    [ "$status" -eq 0 ]; [ -z "$output" ]
    run vbp "$(p3 'echo next' - t2)"
    [ "$status" -eq 0 ]; [ -z "$output" ]
    [ "$(jq -sr '[.[] | .kind] | join(",")' "$CC_SUBAGENT_LONG_BASH_LOG")" = "subagent_bash,d4_follow" ]
  done
  # under live 100 with a fresh heartbeat the arm reads treat: logged, and still nothing decided
  [ "$(jq -sr '[.[] | .arm.arm] | unique | join(",")' "$CC_SUBAGENT_LONG_BASH_LOG")" = treat ]
}

@test "(10) S3 rows stay under 2 KB in one write: oversize fields shed, concurrent appends stay whole" {
  # 4-byte characters in the command and 128-char ids (the agent_id is logged twice: id and arm unit)
  # push the full row past 2 KB
  big="until [ -f /tmp/d ]; do sleep 30; done; $(printf '\360\237\230\200%.0s' $(seq 200))"
  id="$(printf 'x%.0s' $(seq 128))"
  tp="/Users/u/.claude/projects/$(printf 'p%.0s' $(seq 400))/s.jsonl"
  jq -nc --arg c "$big" --arg tp "$tp" --arg id "$id" '{session_id:$id,agent_id:$id,agent_type:$id,
    tool_use_id:$id,transcript_path:$tp,tool_input:{command:$c,timeout:600000}}' | /bin/bash "$HOOK"
  [ "$(wc -l < "$CC_SUBAGENT_LONG_BASH_LOG")" -eq 1 ]
  [ "$(LC_ALL=C wc -c < "$CC_SUBAGENT_LONG_BASH_LOG")" -le 2048 ]
  [ "$(jq -r '[.trunc, .would_deny_class, .transcript_path] | join("|")' "$CC_SUBAGENT_LONG_BASH_LOG")" = "true|poll-loop|" ]
  : > "$CC_SUBAGENT_LONG_BASH_LOG"
  near="sleep 600; $(printf 'é%.0s' $(seq 400))"
  for i in $(seq 1 24); do
    p3 "$near" 600000 "tc$i" "agent-$i" | /bin/bash "$HOOK" &
  done
  wait
  [ "$(wc -l < "$CC_SUBAGENT_LONG_BASH_LOG")" -eq 24 ]
  [ "$(jq -s 'length' "$CC_SUBAGENT_LONG_BASH_LOG")" -eq 24 ]
  [ "$(LC_ALL=C awk '{ if (length($0) > m) m = length($0) } END { print m }' "$CC_SUBAGENT_LONG_BASH_LOG")" -lt 2048 ]
}
