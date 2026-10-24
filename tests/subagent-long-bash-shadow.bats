#!/usr/bin/env bats
# subagent-long-bash-shadow — the COUNT-ONLY subagent rule (docs/plans/USAGE_LEVERS.md § W3).
#
# Owns: which calls the rule counts (a subagent's foreground Bash with timeout > 270 s), which of
# those the narrowed rule would deny and under which class, that it never prints or decides, and
# that its host hooks/validate-bash.sh feeds it without changing a verdict.
# RED-proof: new behaviour. Mutants checked by hand on scratch copies: dropping the 270000 bound
# fails (2); dropping the validate-bash passenger block fails (4).
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
  [ "$(wc -l < "$CC_SUBAGENT_LONG_BASH_LOG")" -eq 13 ]
  jq -e -s 'all(.[]; .broad == true and .would == "count" and (.cmd_sha256 | length) == 64
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
  [ "$(wc -l < "$CC_SUBAGENT_LONG_BASH_LOG")" -eq 2 ]
  # the main thread's call never reaches the rule
  vb "$(payload 'sleep 400' 600000 '')"
  [ "$(wc -l < "$CC_SUBAGENT_LONG_BASH_LOG")" -eq 2 ]
}
