#!/usr/bin/env bats
# shellcheck disable=SC2016  # fixtures are JS source and shell commands: their $ and backticks are literal
# Lever D2 and D4 treatment paths (docs/plans/USAGE_LEVERS.md § W7+ §2 D2/D4, §4 row S11).
#
# Owns: (a) at pct 0 neither hook denies anything across a corpus, while each row logs what the
# treatment branch would do (D2 would_treat, D4 treat_verdict=would_deny); (b) at a forced pct 100 in
# a hermetic HOME, D2 blocks a script ONCE per (session, script_sha) and never a resume, a
# needs-default/keep-default script or the second same-sha submit, and D4 denies only the poll-loop
# class through validate-bash.sh's deny(), with the fixed message; (c) every kill switch wins over a
# raised flag file; (d) a deny is reachable only for a unit whose lever arm reads treat.
# RED-proof (2026-10-25, run): against the base hooks (git archive fca8a4a30 hooks) all of 1-7 fail:
# neither hook has a deny path, and rows carry no would_treat / treat_verdict. Mutants on a scratch
# copy, run together: D2 without block-once (no pre-check, no O_EXCL) and D4 without its arm = treat
# test fail 2, 4 and 6 and pass 1, 3, 5 and 7 (the kill switches zero pct_eff on their own).
#
# Hermetic: $HOME, the lever state dir and both logs are fixtures; validate-bash runs with the
# isolation its own suites use. The hooks run under /bin/bash (3.2 on macOS) and /usr/bin/env python3.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  WF="$REPO/hooks/workflow-lean-shadow.py"
  VB="$REPO/hooks/validate-bash.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_LEVER_STATE_DIR="$BATS_TEST_TMPDIR/levers"; mkdir -p "$CC_LEVER_STATE_DIR"
  WLOG="$HOME/.claude/logs/workflow-lean-shadow.jsonl"
  export CC_SUBAGENT_LONG_BASH_LOG="$BATS_TEST_TMPDIR/slb.jsonl"
  export CC_SHARED_CHECKOUT="$BATS_TEST_TMPDIR/shared"; mkdir -p "$CC_SHARED_CHECKOUT"
  export CC_VB_DECISION_LOG="$BATS_TEST_TMPDIR/decisions.jsonl"
  export IT2_WRAPPER_NO_KITTY=1
  export SHIP_LAND_CONVERGE=off DEPLOY_REPO="$BATS_TEST_TMPDIR/deploy-repo"
  unset CLAUDE_CONFIG_DIR CC_LEVER_LINEAGE CC_LEVER_EXCLUDE CC_LEVER_ALL CC_LEVER_D2 CC_LEVER_D4 \
        CC_LEVER_FLAGS CC_LEVER_HEARTBEAT CC_LEVER_DEADMAN_S CC_HOOK_PARENT_PID CC_WORKFLOW_SHADOW \
        CC_SUBAGENT_LONG_BASH CC_SUBAGENT_LONG_BASH_PENDING KITTY_WINDOW_ID VALIDATE_BASH_DISABLED \
        VALIDATE_BASH_LEGACY CC_VB_AGENT_RM_DENY
  if ! command -v jq >/dev/null 2>&1; then skip "jq not installed"; fi
}

flags() { # <mode> <pct> [holdback] — D2 and D4 entries, plus a fresh guard heartbeat
  jq -nc --arg m "$1" --argjson p "$2" --argjson hb "${3:-0}" \
    '{v:1,rev:11,levers:{D2:{stage:"S1",mode:$m,pct:$p,holdback:$hb,salt:"s11-d2",split_salt:"s11-sp"},
                         D4:{stage:"S1",mode:$m,pct:$p,holdback:$hb,salt:"s11-d4",split_salt:"s11-sp"}}}' \
    > "$CC_LEVER_STATE_DIR/flags.json"
  touch "$CC_LEVER_STATE_DIR/guard.heartbeat"
}
# wf <sid> <tool_use_id> <script> [resumeFromRunId] — one Workflow PreToolUse event; prints the hook's stdout
wf() {
  jq -nc --arg s "$1" --arg t "$2" --arg c "$3" --arg r "${4:-}" \
    '{session_id:$s,tool_use_id:$t,cwd:"/nonexistent",tool_name:"Workflow",
      tool_input:({script:$c} + (if $r == "" then {} else {resumeFromRunId:$r} end))}' \
    | /usr/bin/env python3 "$WF"
}
# vb <command> <timeout_ms|-> <tool_use_id> [agent_id|""] — one Bash event through validate-bash.sh
vb() {
  jq -nc --arg c "$1" --arg t "$2" --arg u "$3" --arg a "${4-agent-a1}" \
    '{tool_name:"Bash",session_id:"sid-1",tool_use_id:$u,transcript_path:"/x/sid-1.jsonl",
      tool_input:({command:$c} + (if $t == "-" then {} else {timeout:($t|tonumber)} end))}
     + (if $a == "" then {} else {agent_id:$a,agent_type:"general-purpose"} end)' \
    | /bin/bash "$VB"
}
decision() { printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecision // "none"' 2>/dev/null || echo none; }

D2_CORPUS=(
  'await agent(`summarise the notes`, {label: "r1"})'
  'await agent(`fix the bug and commit it`, {label: "fix"})'
  'await agent(`x` /* needs-default */, {label: "nd"})'
  'await agent(`y`, {agentType: "workflow-lean"})'
  'await agent(brief, opts)'
  'const r = await parallel([1,2].map(i => () => agent(`look ${i}`, {label: `s-${i}`})))'
)
POLL='until [ -f /tmp/done ]; do sleep 30; done'

@test "1: pct 0 (shadow, and live at 0) — zero denies across both corpora, while the treatment verdict is logged" {
  for mode in shadow live; do
    flags "$mode" 0
    : > "$CC_SUBAGENT_LONG_BASH_LOG"; rm -f "$WLOG"
    i=0
    for s in "${D2_CORPUS[@]}"; do
      i=$((i + 1))
      for sid in S-a S-b; do
        out="$(wf "$sid" "T$i" "$s")"; [ -z "$out" ] || { echo "D2 denied at pct 0: $s"; false; }
        out="$(wf "$sid" "R$i" "$s" wf_run1)"; [ -z "$out" ]
      done
    done
    while IFS= read -r c; do
      out="$(vb "$c" 600000 "t-$RANDOM")"
      [ "$(decision "$out")" != deny ] || { echo "D4 denied at pct 0 ($mode): $c"; false; }
    done <<'CMDS'
until [ -f /tmp/done ]; do sleep 30; done
for i in $(seq 40); do gh pr view 1 && break; sleep 20; done
bash -c 'while :; do curl -s localhost:3000 && break; sleep 5; done'
sleep 600
bats tests/foo.bats
python3 -c "import time; time.sleep(400)"
timeout 260 bash -c 'until [ -f /tmp/done ]; do sleep 30; done'; echo rc=$?
CMDS
    # D2: the first submit of each would-deny script per session would be treated, nothing more
    [ "$(jq -s '[.[] | select(.kind != "slots") | select(.denied == true)] | length' "$WLOG")" -eq 0 ]
    [ "$(jq -sr '[.[] | select(.kind != "slots" and .would_treat) | "\(.session_id):\(.tool_use_id)"] | join(",")' "$WLOG")" \
      = "S-a:T1,S-b:T1,S-a:T6,S-b:T6" ]
    [ "$(jq -s '[.[] | select(.resume_from_run_id != null and .would_deny) | .treat_skip] | unique' -c "$WLOG")" = '["resume"]' ]
    [ ! -e "$CC_LEVER_STATE_DIR/d2-blocked" ]
    # D4: the three poll loops read would_deny; every other class has no treatment verdict
    [ "$(jq -s '[.[] | select(.kind == "subagent_bash") | .treat_verdict // "-"] | join(",")' -r "$CC_SUBAGENT_LONG_BASH_LOG")" \
      = "would_deny,would_deny,would_deny,-,-,-,-" ]
    [ "$(jq -s '[.[] | .arm.arm] | unique | join(",")' -r "$CC_SUBAGENT_LONG_BASH_LOG")" = ctrl ]
  done
  [ ! -s "$CC_VB_DECISION_LOG" ] || ! grep -q 'usage lever D4' "$CC_VB_DECISION_LOG" || false
}

@test "2: D2 at pct 100 — blocks once per (session, script_sha), with the fixed message, and the row says so" {
  flags live 100
  s='await agent(`summarise`, {label: "r1"}); await agent(`fix and commit`, {label: "fix"})'
  out="$(wf S T1 "$s")"
  [ "$(decision "$out")" = deny ]
  reason="$(printf '%s' "$out" | jq -r .hookSpecificOutput.permissionDecisionReason)"
  [[ $reason == *"1 agent() slot(s)"*"line 1 'r1'"* ]] || false
  [[ $reason == *"agentType: 'workflow-lean'"*"/* needs-default */"*"never blocked again"* ]] || false
  [[ $reason != *"'fix'"* ]] || false                         # a keep-default slot is not named
  # the same script again in this session passes; another session's first submit is blocked once
  [ -z "$(wf S T2 "$s")" ]
  [ "$(decision "$(wf S2 T3 "$s")")" = deny ]
  [ -z "$(wf S2 T4 "$s")" ]
  # the edited resubmit (lean added) passes
  [ -z "$(wf S T5 'await agent(`summarise`, {label: "r1", agentType: "workflow-lean"})')" ]
  [ "$(jq -sr '[.[] | select(.kind != "slots") | "\(.tool_use_id):\(.denied):\(.treat_skip):\(.block_state)"] | join(",")' "$WLOG")" \
    = "T1:true:null:created,T2:false:repeat:exists,T3:true:null:created,T4:false:repeat:exists,T5:false:null:null" ]
  [ "$(jq -sr '.[1] | "\(.follows_deny):\(.prev_same_script)"' "$WLOG")" = "true:true" ]
  [ "$(find "$CC_LEVER_STATE_DIR/d2-blocked" -type f | wc -l | tr -d ' ')" -eq 2 ]
}

@test "3: D2 at pct 100 — never a resume, a needs-default or keep-default script, or an unparsed one" {
  flags live 100
  [ -z "$(wf S T1 'await agent(`summarise`, {label: "r1"})' wf_abc)" ]                 # resume
  [ -z "$(wf S T2 'await agent(`summarise` /* needs-default */, {label: "nd"})')" ]     # marker
  [ -z "$(wf S T3 'await agent(`run /ship when green`, {label: "sh"})')" ]              # keep-default
  [ -z "$(wf S T4 'await agent(brief, opts)')" ]                                        # unknown
  jq -nc '{session_id:"S",tool_use_id:"T5",tool_name:"Workflow",tool_input:{name:"no-such"}}' | /usr/bin/env python3 "$WF" > "$BATS_TEST_TMPDIR/o5"
  [ ! -s "$BATS_TEST_TMPDIR/o5" ]
  [ "$(jq -sr '[.[] | "\(.tool_use_id):\(.would_treat):\(.denied):\(.treat_skip)"] | join(",")' "$WLOG")" \
    = "T1:false:false:resume,T2:false:false:null,T3:false:false:null,T4:false:false:null,T5:false:false:null" ]
  # the resumed script was never blocked, so its first fresh submit still is
  [ "$(decision "$(wf S T6 'await agent(`summarise`, {label: "r1"})')")" = deny ]
}

@test "4: D2 block-once holds under a race, and a missing row or state means no deny" {
  flags live 100
  s='await agent(`race`, {label: "r"})'
  for i in 1 2 3 4 5 6 7 8; do wf S "T$i" "$s" > "$BATS_TEST_TMPDIR/race.$i" & done
  wait
  [ "$(cat "$BATS_TEST_TMPDIR"/race.* | grep -c '"deny"')" -eq 1 ]
  # an unwritable log: the deny is printed only after its row is written
  rm -rf "$HOME/.claude/logs"; : > "$HOME/.claude/logs"
  [ -z "$(wf S3 T9 'await agent(`other`, {label: "o"})')" ]
  # an unwritable state dir: no block-once state, so no deny
  rm -f "$HOME/.claude/logs"
  rm -rf "$CC_LEVER_STATE_DIR/d2-blocked"; : > "$CC_LEVER_STATE_DIR/d2-blocked"   # the state dir is a FILE
  [ -z "$(wf S4 T10 'await agent(`third`, {label: "t"})')" ]
  [ "$(jq -r 'select(.tool_use_id == "T10") | "\(.would_treat):\(.denied):\(.block_state)"' "$WLOG")" = "true:false:error" ]
}

@test "5: D4 at pct 100 — validate-bash denies only a poll loop, with the fixed message; the sliced re-issue passes" {
  flags live 100
  out="$(vb "$POLL" 600000 t1)"
  [ "$(decision "$out")" = deny ]
  reason="$(printf '%s' "$out" | jq -r .hookSpecificOutput.permissionDecisionReason)"
  [[ $reason == *"usage lever D4"*"do not poll"*"timeout 260 bash -c '<the loop>'; echo rc=\$?"*"270000"*"rc=124"* ]] || false
  [[ $reason == *"Do not use run_in_background"* ]] || false
  [ "$(jq -r 'select(.decision == "deny") | .reason' "$CC_VB_DECISION_LOG" | grep -c 'usage lever D4')" -eq 1 ]
  # what the message asks for passes, and its follow row links back to the deny
  [ "$(decision "$(vb "timeout 260 bash -c '$POLL'; echo rc=\$?" 270000 t2)")" != deny ]
  [ "$(jq -sc '[.[] | select(.kind == "d4_follow") | [.follows_tool_use_id, .follows_verdict, .echo_rc]]' "$CC_SUBAGENT_LONG_BASH_LOG")" \
    = '[["t1","deny",true]]' ]
  # not the poll-loop class, an inner-timeout exemption, the main thread or a backgrounded call: no deny
  while IFS='|' read -r aid cmd; do
    [ "$(decision "$(vb "$cmd" 600000 "t-$RANDOM" "$aid")")" != deny ] || { echo "denied: [$aid] $cmd"; false; }
  done <<'ROWS'
agent-b|sleep 600
agent-b|cc-await-ping abc --timeout 3300
agent-b|bats tests/foo.bats
agent-b|python3 -c "import time; time.sleep(400)"
agent-b|timeout 260 bash -c 'until [ -f /tmp/done ]; do sleep 30; done'
|until [ -f /tmp/done ]; do sleep 30; done
ROWS
  # the would_deny/deny row carries what a precision hillclimb needs: class, inner timeout, a 200-char head
  long="until [ -f /tmp/done ]; do sleep 30; done; $(printf 'x%.0s' $(seq 300))"
  vb "$long" 600000 t-long agent-c >/dev/null
  [ "$(jq -r 'select(.tool_use_id == "t-long") | "\(.treat_verdict):\(.would_deny_class):\(.why):\(.inner_timeout_s):\(.cmd_head | length)"' "$CC_SUBAGENT_LONG_BASH_LOG")" \
    = "deny:poll-loop:poll-loop:null:200" ]
}

@test "6: a deny is reachable only for a unit whose arm reads treat (pct 50, holdback 20)" {
  flags live 50 20
  n_treat=0
  for i in $(seq 1 16); do
    a="agent-$i"; s="sid-$i"
    want="$(/usr/bin/python3 -I "$REPO/hooks/lib/lever_flags.py" arm D4 "$a" | jq -r .arm)"
    got="$(decision "$(vb "$POLL" 600000 "t$i" "$a")")"
    if [ "$want" = treat ]; then n_treat=$((n_treat + 1)); [ "$got" = deny ]; else [ "$got" != deny ]; fi
    want2="$(CC_LEVER_LINEAGE="$s" /usr/bin/python3 -I "$REPO/hooks/lib/lever_flags.py" arm D2 "$s" | jq -r .arm)"
    got2="$(decision "$(CC_LEVER_LINEAGE="$s" wf "$s" "w$i" 'await agent(`a`)')")"
    if [ "$want2" = treat ]; then [ "$got2" = deny ]; else [ "$got2" != deny ] || { echo "$s arm=$want2 denied"; false; }; fi
  done
  # the fixture spans both outcomes, else this test proves only one side
  [ "$n_treat" -gt 0 ] && [ "$n_treat" -lt 16 ] || false
}

@test "7: every kill switch wins over a raised flag file, and a stale heartbeat reads pct 0" {
  flags live 100
  k=0
  for kill in CC_WORKFLOW_SHADOW=off CC_LEVER_D2=off CC_LEVER_ALL=control CC_LEVER_EXCLUDE=1 CC_LEVER_D2=control; do
    k=$((k + 1))
    [ -z "$(env "$kill" bash -c 'jq -nc --arg c "$1" "{session_id:\"K$2\",tool_use_id:\"T\",cwd:\"/x\",tool_name:\"Workflow\",tool_input:{script:\$c}}" | /usr/bin/env python3 "$3"' _ 'await agent(`a`)' "$k" "$WF")" ] \
      || { echo "D2 denied under $kill"; false; }
  done
  for kill in CC_SUBAGENT_LONG_BASH=off CC_LEVER_D4=off CC_LEVER_ALL=off CC_LEVER_EXCLUDE=1; do
    k=$((k + 1))
    out="$(env "$kill" bash -c 'jq -nc --arg c "$1" "{tool_name:\"Bash\",session_id:\"s\",tool_use_id:\"t\",agent_id:\"ag-$2\",tool_input:{command:\$c,timeout:600000}}" | /bin/bash "$3"' _ "$POLL" "$k" "$VB")"
    [ "$(decision "$out")" != deny ] || { echo "D4 denied under $kill"; false; }
  done
  # the dead-man: a live lever whose guard heartbeat is older than 1800 s is pct 0
  touch -t 202001010000 "$CC_LEVER_STATE_DIR/guard.heartbeat"
  [ -z "$(wf S-dead T 'await agent(`a`)')" ]
  [ "$(decision "$(vb "$POLL" 600000 t-dead agent-dead)")" != deny ]
  [ "$(jq -r 'select(.session_id == "S-dead") | "\(.arm.flag_src):\(.would_treat):\(.denied)"' "$WLOG")" = "deadman:true:false" ]
}
