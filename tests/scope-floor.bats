#!/usr/bin/env bats
# scope-floor.bats — the SCOPE FLOOR in hooks/session-continue.sh (ruling d610f8473106; design
# docs/research/lead-keeps-working-2026-10-24.md §3.4 (i), test plan §7.3 S1-S23).
#
# The floor CONSUMES wrap-ledger's verdict, so the ledger is a stub driven by STUB_* env (the idiom of
# tests/ship-floor.bats). Its defaults are the B13 F1 close: ⛔ on two open class-C packets, an own open
# loop scope, nothing in flight. The in-flight lib and context-econ lib are sourced stubs by default;
# the cases that need the REAL in-flight lib point INFLIGHT_LIB at hooks/lib/inflight.sh.
# Every stub goes through cc_stub (no kernel #! exec; test-stub-lint baseline 0 for a new suite).

load helpers/cc-stub

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/session-continue.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/state"
  unset CLAUDE_CODE_SESSION_ID CLAUDE_SESSION_ID WRAP_SESSION_ID CC_PANE_ID
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/cfg"; mkdir -p "$CLAUDE_CONFIG_DIR"
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mbox"; mkdir -p "$CC_MAILBOX_DIR"
  export CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CONTINUE_IDL="$BATS_TEST_TMPDIR/continue-idl.jsonl"
  export CONTINUE_LOG="$BATS_TEST_TMPDIR/continue.log"
  export CC_TEARDOWN_DIR="$BATS_TEST_TMPDIR/teardown"
  export ITERM_SESSION_ID="w0t0p0:DDDDDDDD-1111-2222-3333-444444444444"
  # Isolate the floor under test. The SHIP floor stays ON on purpose: it must decline ⛔ by itself.
  export CC_WAKE_FLOOR=0 CC_MECH_CONTINUE=0
  # The assignee oracle reads the RUNNING process's ancestry; a missing file yields "not an assignee",
  # which is these fixtures' truth whoever runs the suite (tests/ship-floor.bats:17-23).
  export AGENT_IDENTITY_LIB="$BATS_TEST_TMPDIR/no-such-agent-identity.sh"
  CWD="$BATS_TEST_TMPDIR/wt"; mkdir -p "$CWD"
  ( cd "$CWD" && git init -q && git -c user.email=t@e.com -c user.name=t commit -q --allow-empty -m c1 ) >/dev/null 2>&1
  # Ledger stub: every field the floor reads, each overridable by STUB_<KEY> (set-but-empty counts).
  cc_stub "$BATS_TEST_TMPDIR/bin" wrap-ledger - <<'EOF'
#!/bin/bash
[ -n "${STUB_ARGV_LOG:-}" ] && printf '%s\n' "$*" >> "$STUB_ARGV_LOG"
if [ -n "${STUB_OLD:-}" ]; then printf 'RUNG=⛔\nBLOCKED=2\nBLOCKED_SRC=env\nDIRTY=0\n'; exit 0; fi
for kv in "RUNG=⛔" "BLOCKED=2" "BLOCKED_SRC=env" "BLOCKED_RECHECKED=0" "RECHECKED_IDS=" "RECHECKED_SRC=none" \
  "BLOCKED_IDS=290215743799,e869fac7eb34" "LOOP_SCOPE=1" "LOOP_OPEN=1" "LOOP_SRC=own" "LOOP_RUNG=0" \
  "OWN_REMAINDER=0" "HELD=0" "HELD_SRC=absent" "HELD_UNTIL=" "SCOPE_UNGATED=1" "CUSTODY_OPEN=0" \
  "CUSTODY_SRC=ok" "LANDING=0" "RESIDENT_MINE=0" "RESEARCH_PROGRAM=none" "GOAL_SRC=absent" "DIRTY=0" \
  "UNLANDED=0" "REMAINDER=0" "TRUNK=origin/main" "AHEAD=0" \
  "LOOP_HEAD=Loop until dry. Each round = one Dynamic Workflow; repeat until a round confirms nothing new." \
  "HELD_WHY=" "BLOCKED_GLOSS=290215743799 (\"send committed code to the Codex plan\"); e869fac7eb34 (\"stop the loop now\")"; do
  k="${kv%%=*}"; n="STUB_$k"
  if [ -n "${!n+y}" ]; then printf '%s=%s\n' "$k" "${!n}"; else printf '%s\n' "$kv"; fi
done
EOF
  # the hook runs `bash "$WRAP_LEDGER_BIN"`, so hand it the stub's BODY (under cc-shim DIR/NAME is a Mach-O link)
  WRAP_LEDGER_BIN="$(cc_stub_body "$BATS_TEST_TMPDIR/bin" wrap-ledger)"; export WRAP_LEDGER_BIN
  # In-flight lib stub (sourced, not exec'd): counts driven by env.
  printf '%s\n' 'inflight_waves() { printf "%s" "${STUB_WAVES:-0}"; }' \
                'inflight_bg_tasks() { printf "%s" "${STUB_BG:-0}"; }' > "$BATS_TEST_TMPDIR/inflight-stub.sh"
  export INFLIGHT_LIB="$BATS_TEST_TMPDIR/inflight-stub.sh"
  printf '%s\n' 'ce_size() { printf "%s" "${STUB_CE_SIZE:-0 0}"; }' \
                'ce_burn() { printf "%s" "${STUB_CE_BURN:-0 -1}"; }' > "$BATS_TEST_TMPDIR/ce-stub.sh"
  export CONTEXT_ECON_LIB="$BATS_TEST_TMPDIR/ce-stub.sh"
  export CC_TELEMETRY_DIR="$BATS_TEST_TMPDIR/tel"; mkdir -p "$CC_TELEMETRY_DIR"
  tel 64
  # capture-loop CLI stub: records argv, prints STUB_CAPTURE
  cc_stub "$BATS_TEST_TMPDIR/bin" dod-persist - <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$BATS_TEST_TMPDIR/dp-argv"
printf '%s\n' "\${STUB_CAPTURE:-own-exists}"
EOF
  DOD_PERSIST_BIN="$(cc_stub_body "$BATS_TEST_TMPDIR/bin" dod-persist)"; export DOD_PERSIST_BIN
  SFSTATE="$CLAUDE_CONFIG_DIR/state/scope-floor"
}

tel() { jq -nc --argjson u "$1" '{used_pct:$u,input_tokens:($u*10000)}' > "$CC_TELEMETRY_DIR/${2:-sidA}.json"; }
actuate() { printf '{"cwd":"%s","session_id":"%s","transcript_path":"%s"}' "$CWD" "${1:-sidA}" "${2:-}" | bash "$HOOK" 2>/dev/null; }
blocked() { printf '%s' "$1" | grep -q '"decision":"block"'; }
reason_of() { printf '%s' "$1" | jq -r '.reason // ""'; }
row() { grep -F "\"reason\":\"$1\"" "$CONTINUE_IDL" 2>/dev/null | tail -1; }
rows_like() { [ -f "$CONTINUE_IDL" ] || { echo 0; return 0; }; grep -c "\"reason\":\"scope-floor" "$CONTINUE_IDL" || true; }
key_of() { row scope-floor | jq -r '.key'; }

# transcript records
u_str()  { jq -nc --arg t "$1" '{type:"user",message:{content:$t}}'; }
u_meta() { jq -nc --arg t "$1" '{type:"user",isMeta:true,message:{content:$t}}'; }
a_txt()  { jq -nc --arg t "$1" '{type:"assistant",message:{content:[{type:"text",text:$t}]}}'; }
a_edit() { jq -nc '{type:"assistant",message:{content:[{type:"tool_use",id:"t9",name:"Edit",input:{file_path:"/x",old_string:"a",new_string:"b"}}]}}'; }
F1_CLOSE='❌ Good to close: no — round 26 landed; round 27 waits on decision e869fac7eb34. Nothing more runs until you answer.'
NOTE=$'<task-notification>\n<task-id>bx1</task-id>\n<status>completed</status>\n</task-notification>'
SFB=$'Stop hook feedback:\n⟳ SCOPE FLOOR — you are going idle on ⛔ while in-scope work your open decision(s) do not gate remains'
# B13 F1: the scope stated by a human, then a turn opened by a task notification that closes idle
tx_f1() {
  local p="$BATS_TEST_TMPDIR/tx-$RANDOM.jsonl"
  { u_str $'recycle brief\n\n\n\nScope (frozen): Loop until dry. Each round = one Dynamic Workflow.'
    a_txt "round 26 running"; u_str "$NOTE"; a_txt "$F1_CLOSE"; } > "$p"
  printf '%s' "$p"
}

# ── S1 / S2 — the B13 closes block, whatever the prose says ──
@test "S1: F1 — ⛔ with an own open loop and nothing in flight BLOCKS, with the fixed template" {
  out="$(actuate sidA "$(tx_f1)")"
  blocked "$out"
  r="$(reason_of "$out")"
  for s in '⟳ SCOPE FLOOR' 290215743799 e869fac7eb34 'run the next round as scoped' 'dod-persist.sh hold' \
           'dod-persist.sh done' 'an armed watcher wakes you only on mail' '(scope floor 1/3'; do
    [[ "$r" == *"$s"* ]] || { echo "missing: $s"; false; }
  done
  for s in 'Scope (frozen):' 'cc-decide action' 'nothing else will wake you' 'no status quo'; do
    [[ "$r" != *"$s"* ]] || { echo "forbidden: $s"; false; }
  done
  r1="$(row scope-floor)"
  [ "$(printf '%s' "$r1" | jq -r '.disposition')" = fired ]
  [ "$(printf '%s' "$r1" | jq -r '.ungated')" = 1 ]
  [ "$(printf '%s' "$r1" | jq -r '.kind')" = blocked ]
  [ "$(printf '%s' "$r1" | jq -r '.held')" = false ]
  [ "$(printf '%s' "$r1" | jq -r '.key | length')" = 12 ]
  [ "$(printf '%s' "$r1" | jq -r '.ids')" = "290215743799,e869fac7eb34" ]
  grep -q ' scope-floor$' "$CLAUDE_CONFIG_DIR"/state/continue-*.blocked
}

@test "S2: F3 shape — verdict on line 3, watcher torn down — same block (prose independence)" {
  p="$BATS_TEST_TMPDIR/f3.jsonl"
  { u_str 'Scope (frozen): Loop until dry.'; u_str "$NOTE"
    a_txt $'Round 26 is landed.\nI am stopping the inbox watcher.\n❌ Good to close: no — waiting on you.'; } > "$p"
  out="$(actuate sidA "$p")"
  blocked "$out"
  [[ "$(reason_of "$out")" == *'⟳ SCOPE FLOOR'* ]]
}

# ── S3 — the floor's own forced turn cannot loop ──
@test "S3: a re-close of a turn the floor's block opened does not fire again, even with a write" {
  p="$BATS_TEST_TMPDIR/s3.jsonl"
  { u_str "$NOTE"; a_txt "$F1_CLOSE"; u_meta "$SFB"; a_edit; a_txt "$F1_CLOSE"; } > "$p"
  out="$(actuate sidA "$p")"
  ! blocked "$out" || false
  [ "$(row scope-floor-reclose | jq -r '.ungated')" = 1 ]
}

@test "S3b: a re-close through another hook's block (completion-assert, then anti-deference) is still a re-close" {
  p="$BATS_TEST_TMPDIR/s3b.jsonl"
  { u_str "$NOTE"; a_txt "$F1_CLOSE"; u_meta "$SFB"; a_txt "$F1_CLOSE"
    u_meta $'Stop hook feedback:\n⛔ completion-assert: your close claims done while …'; a_txt "$F1_CLOSE"; } > "$p"
  out="$(actuate sidA "$p")"
  ! blocked "$out" || false
  [ -n "$(row scope-floor-reclose)" ]
  { u_meta $'Stop hook feedback:\nanti-deference: offering is a defect'; a_txt "$F1_CLOSE"; } >> "$p"
  out="$(actuate sidA "$p")"
  ! blocked "$out" || false
  [ "$(grep -c '"reason":"scope-floor-reclose"' "$CONTINUE_IDL")" = 2 ]
}

@test "S3c: minimum gap — a second fire 60 s after the first is refused; 700 s after, it fires" {
  p="$(tx_f1)"
  actuate sidA "$p" >/dev/null
  k="$(key_of)"
  printf 'F %s %s\n' "$(( $(date +%s) - 60 ))" "$k" > "$SFSTATE/sidA"
  out="$(actuate sidA "$p")"
  ! blocked "$out" || false
  [ -n "$(row scope-floor-gap)" ]
  printf 'F %s %s\n' "$(( $(date +%s) - 700 ))" "$k" > "$SFSTATE/sidA"
  out="$(actuate sidA "$p")"
  blocked "$out"
}

# ── S4-S7 — the budget: per key, per session, per sid ──
@test "S4: per-key window cap — 3 fires, the 4th is key-cap; after the window it fires again" {
  export CC_SCOPE_FLOOR_GAP_S=0
  p="$(tx_f1)"
  for i in 1 2 3; do out="$(actuate sidA "$p")"; blocked "$out" || { echo "fire $i"; false; }; done
  out="$(actuate sidA "$p")"
  ! blocked "$out" || false
  [ -n "$(row scope-floor-key-cap)" ]
  # the window is the only thing that releases a key: age every fire past a 2 s window
  sed -E "s/^F [0-9]+ /F $(( $(date +%s) - 5 )) /" "$SFSTATE/sidA" > "$SFSTATE/sidA.t" && mv "$SFSTATE/sidA.t" "$SFSTATE/sidA"
  out="$(CC_SCOPE_FLOOR_WINDOW_S=2 actuate sidA "$p")"
  blocked "$out"
}

@test "S5: A→B→A — revisiting key A sees its history (a map, not a single slot)" {
  export CC_SCOPE_FLOOR_GAP_S=0
  p="$(tx_f1)"
  for i in 1 2 3; do actuate sidA "$p" >/dev/null; done
  out="$(STUB_BLOCKED_IDS=aaaaaaaaaaaa actuate sidA "$p")"
  blocked "$out"
  out="$(actuate sidA "$p")"
  ! blocked "$out" || false
  [ -n "$(row scope-floor-key-cap)" ]
}

@test "S6: per-session day ceiling — 6 distinct keys fire, the 7th is day-cap" {
  export CC_SCOPE_FLOOR_GAP_S=0
  p="$(tx_f1)"
  for i in 1 2 3 4 5 6; do
    out="$(STUB_BLOCKED_IDS="00000000000$i" actuate sidA "$p")"; blocked "$out" || { echo "key $i"; false; }
  done
  out="$(STUB_BLOCKED_IDS=000000000007 actuate sidA "$p")"
  ! blocked "$out" || false
  [ -n "$(row scope-floor-day-cap)" ]
}

@test "S7: two sessions in one cwd keep separate budgets" {
  export CC_SCOPE_FLOOR_GAP_S=0
  p="$(tx_f1)"
  for i in 1 2 3; do actuate sidA "$p" >/dev/null; done
  ! blocked "$(actuate sidA "$p")" || false
  tel 64 sidB
  out="$(actuate sidB "$p")"
  blocked "$out"
}

# ── S8 — in flight (stubbed lib; the real lib's detection has its own suite, tests/inflight.bats) ──
@test "S8: custody, land, teammate, live wave, live bg task, live agent — each abstains inflight with what" {
  p="$(tx_f1)"
  for c in "STUB_CUSTODY_OPEN=1:custody" "STUB_LANDING=1:land" "STUB_RESIDENT_MINE=1:teammate" \
           "STUB_WAVES=1:wave" "STUB_BG=1 bg:bg" "STUB_BG=1 agent:agent"; do
    : > "$CONTINUE_IDL"
    out="$(env "${c%%:*}" bash -c 'printf "{\"cwd\":\"%s\",\"session_id\":\"sidA\",\"transcript_path\":\"%s\"}" "$1" "$2" | bash "$3" 2>/dev/null' _ "$CWD" "$p" "$HOOK")"
    ! blocked "$out" || { echo "blocked: $c"; false; }
    [ "$(row scope-floor-inflight | jq -r '.what')" = "${c##*:}" ] || { echo "what: $c"; cat "$CONTINUE_IDL"; false; }
  done
}

# ── S8 / S8b / S9 / S9b with the REAL in-flight lib (hooks/lib/inflight.sh) ──
# tx_bg <command> [<extra record>…]: F1, plus one background Bash task started by <command> whose
# output file is fresh; the turn that closes idle was opened by an unrelated task notification.
tx_bg() {
  local p="$BATS_TEST_TMPDIR/bg-$RANDOM.jsonl" out="$BATS_TEST_TMPDIR/b1.output" c="$1"; shift
  : > "$out"
  { u_str 'Scope (frozen): Loop until dry.'
    jq -nc --arg c "$c" '{type:"assistant",message:{content:[{type:"tool_use",id:"tb1",name:"Bash",input:{command:$c,run_in_background:true}}]}}'
    jq -nc --arg o "$out" '{type:"user",message:{content:[{type:"tool_result",tool_use_id:"tb1",content:("Command running in background with ID: b1. Output is being written to: " + $o + ". You will be notified when it completes.")}]},toolUseResult:{backgroundTaskId:"b1"}}'
    for r in "$@"; do printf '%s\n' "$r"; done
    u_str "$NOTE"; a_txt "$F1_CLOSE"; } > "$p"
  printf '%s' "$p"
}
tx_agent() { # $1 = extra record (or ""); the async agent a8e552e552430265c, its transcript fresh
  local p="$BATS_TEST_TMPDIR/ag-$RANDOM.jsonl"
  { u_str 'Scope (frozen): Loop until dry.'
    jq -nc '{type:"assistant",message:{content:[{type:"tool_use",id:"ta1",name:"Agent",input:{prompt:"x",run_in_background:true}}]}}'
    jq -nc '{type:"user",message:{content:[{type:"tool_result",tool_use_id:"ta1",content:[{type:"text",text:"Async agent launched successfully.\nagentId: a8e552e552430265c (internal ID - do not mention to user.)\nThe agent is working in the background."}]}]}}'
    [ -n "${1:-}" ] && printf '%s\n' "$1"
    u_str "$NOTE"; a_txt "$F1_CLOSE"; } > "$p"
  mkdir -p "${p%.jsonl}/subagents"; : > "${p%.jsonl}/subagents/agent-a8e552e552430265c.jsonl"
  printf '%s' "$p"
}

@test "S8 (real lib): a live non-watcher bg task and a live async agent each abstain inflight (bg / agent)" {
  export INFLIGHT_LIB="$REPO/hooks/lib/inflight.sh"
  ! blocked "$(actuate sidA "$(tx_bg 'bash scripts/ship-land.sh')")" || false
  [ "$(row scope-floor-inflight | jq -r '.what')" = bg ]
  : > "$CONTINUE_IDL"
  ! blocked "$(actuate sidA "$(tx_agent "")")" || false
  [ "$(row scope-floor-inflight | jq -r '.what')" = agent ]
}

@test "S8b (real lib): a finished agent, and an unfinished one whose transcript is 3 h old, are not in flight" {
  export INFLIGHT_LIB="$REPO/hooks/lib/inflight.sh"
  blocked "$(actuate sidA "$(tx_agent "$(u_str $'<task-notification>\n<task-id>a8e552e552430265c</task-id>\n<status>completed</status>')")")"
  p="$(tx_agent "")"; touch -t "$(date -v-3H +%Y%m%d%H%M.%S)" "${p%.jsonl}/subagents/agent-a8e552e552430265c.jsonl"
  blocked "$(CC_SCOPE_FLOOR_GAP_S=0 actuate sidB "$p")"
}

@test "S9 (real lib): an armed watcher alone is not in flight — absolute path, timeout prefix, env prefix" {
  export INFLIGHT_LIB="$REPO/hooks/lib/inflight.sh" CC_SCOPE_FLOOR_GAP_S=0
  for c in '/Users/someone/.claude/bin/cc-await-ping 134 --timeout 3300 --interval 15' \
           'timeout 3400 /x/cc-await-ping 134' 'CC_X=1 cc-await-ping 134'; do
    out="$(STUB_BLOCKED_IDS="$(printf '%s' "$c" | cksum | cut -c1-12)" actuate sidA "$(tx_bg "$c")")"
    blocked "$out" || { echo "not blocked: $c"; cat "$CONTINUE_IDL"; false; }
  done
}

@test "S9b (real lib): finished whatever record carries it (queued_command, queue-operation); a stale output file is not live" {
  export INFLIGHT_LIB="$REPO/hooks/lib/inflight.sh" CC_SCOPE_FLOOR_GAP_S=0
  qc="$(jq -nc '{type:"attachment",attachment:{type:"queued_command",prompt:"<task-notification>\n<task-id>b1</task-id>\n<status>completed</status>"}}')"
  qo="$(jq -nc '{type:"queue-operation",operation:"enqueue",content:"<task-notification>\n<task-id>b1</task-id>\n<status>completed</status>"}')"
  blocked "$(STUB_BLOCKED_IDS=aaaaaaaaaaa1 actuate sidA "$(tx_bg 'bash scripts/ship-land.sh' "$qc")")"
  blocked "$(STUB_BLOCKED_IDS=aaaaaaaaaaa2 actuate sidA "$(tx_bg 'bash scripts/ship-land.sh' "$qo")")"
  p="$(tx_bg 'bash scripts/ship-land.sh')"; touch -t "$(date -v-3H +%Y%m%d%H%M.%S)" "$BATS_TEST_TMPDIR/b1.output"
  blocked "$(STUB_BLOCKED_IDS=aaaaaaaaaaa3 actuate sidA "$p")"
}

# ── S10 / S11 — unknowns abstain; held / nothing ungated ──
@test "S10: unknowns abstain — ledger error, custody skipped under ungated ⛔, in-flight lib missing" {
  p="$(tx_f1)"
  ! blocked "$(STUB_BLOCKED_SRC=error actuate sidA "$p")" || false
  [ -n "$(row scope-floor-unknown)" ]
  : > "$CONTINUE_IDL"
  ! blocked "$(STUB_CUSTODY_SRC=skip actuate sidA "$p")" || false
  [ -n "$(row scope-floor-unknown)" ]
  : > "$CONTINUE_IDL"
  ! blocked "$(INFLIGHT_LIB="$BATS_TEST_TMPDIR/none.sh" actuate sidA "$p")" || false
  [ -n "$(row scope-floor-unknown)" ]
  : > "$CONTINUE_IDL"
  ! blocked "$(STUB_BG='?' actuate sidA "$p")" || false
  [ -n "$(row scope-floor-unknown)" ]
}

@test "S11: a recorded hold — nothing ungated, logged with held:true" {
  out="$(STUB_HELD=1 STUB_SCOPE_UNGATED=0 STUB_HELD_WHY='Scope (held): e869fac7eb34 — every round needs it' actuate sidA "$(tx_f1)")"
  ! blocked "$out" || false
  r="$(row scope-floor-nothing-ungated)"
  [ "$(printf '%s' "$r" | jq -r '.held')" = true ]
  [ "$(printf '%s' "$r" | jq -r '.held_id')" = e869fac7eb34 ]
  [ "$(printf '%s' "$r" | jq -r '.ungated')" = 0 ]
}

@test "S11b: a lapsed hold fires again once its prior fires are past the window" {
  p="$(tx_f1)"
  actuate sidA "$p" >/dev/null; k="$(key_of)"; old=$(( $(date +%s) - 25000 ))
  printf 'F %s %s\nF %s %s\nF %s %s\n' "$old" "$k" "$((old+700))" "$k" "$((old+1400))" "$k" > "$SFSTATE/sidA"
  : > "$CONTINUE_IDL"
  out="$(STUB_HELD=0 STUB_HELD_SRC=lapsed STUB_HELD_UNTIL=$(( $(date +%s) - 10 )) actuate sidA "$p")"
  blocked "$out"
  [ "$(row scope-floor | jq -r '.disposition')" = fired ]
}

# ── S12 — operator signals ──
@test "S12: kill phrase, operator hold phrase, and a read-only answer to a human prompt all abstain" {
  p="$BATS_TEST_TMPDIR/k.jsonl"; { u_str "$NOTE"; a_txt x; u_str "review it and stop"; a_txt "$F1_CLOSE"; } > "$p"
  ! blocked "$(actuate sidA "$p")" || false
  [ -n "$(row scope-floor-kill-switch)" ]
  p="$BATS_TEST_TMPDIR/h.jsonl"; { u_str "wait for my answer before round 27"; a_txt "$F1_CLOSE"; } > "$p"
  ! blocked "$(actuate sidA "$p")" || false
  [ -n "$(row scope-floor-operator-hold)" ]
  p="$BATS_TEST_TMPDIR/c.jsonl"; { u_str "$NOTE"; a_txt x; u_str "what did round 26 find?"; a_txt "nine defects"; } > "$p"
  ! blocked "$(actuate sidA "$p")" || false
  [ -n "$(row scope-floor-conversation)" ]
}

# ── S13 — the other abstains ──
# An assignee or a torn-down session never forks the ledger (the floor returns before its read, design
# §3.4 D-8), and the mechanical arm releases both before ITS read, so for them the floor is SILENT: no
# block and no row. Research program and live /goal are decided on ledger facts and are logged.
@test "S13a: assignee (rc 0 and rc 2) and teardown are silent; research program and live /goal abstain logged" {
  p="$(tx_f1)"
  for rc in 0 2; do
    printf '%s\n' "agent_assignee_argv() { printf 'lkw-x'; return 0; }" "agent_team_member_confirms() { return $rc; }" \
      > "$BATS_TEST_TMPDIR/ai.sh"
    : > "$CONTINUE_IDL"
    ! blocked "$(AGENT_IDENTITY_LIB="$BATS_TEST_TMPDIR/ai.sh" actuate sidA "$p")" || false
    [ "$(rows_like)" = 0 ] || { echo "rc $rc"; cat "$CONTINUE_IDL"; false; }
  done
  mkdir -p "$CC_TEARDOWN_DIR"; printf '{"sid":"sidA"}' > "$CC_TEARDOWN_DIR/sidA.json"
  : > "$CONTINUE_IDL"
  ! blocked "$(actuate sidA "$p")" || false
  [ "$(rows_like)" = 0 ]
  rm -f "$CC_TEARDOWN_DIR/sidA.json"
  ! blocked "$(STUB_RESEARCH_PROGRAM=tm2 actuate sidA "$p")" || false
  [ -n "$(row scope-floor-research)" ]
  ! blocked "$(STUB_GOAL_SRC=live actuate sidA "$p")" || false
  [ -n "$(row scope-floor-goal)" ]
}

@test "S13b: context-high on each of boundary-handoff's five axes abstains (fill, tokens, size, RSS, forecast)" {
  p="$(tx_f1)"
  ax() { [ "$(row scope-floor-context-high | jq -r '.axis')" = "$1" ] || { echo "axis $1"; cat "$CONTINUE_IDL"; false; }; }
  tel 80; ! blocked "$(actuate sidA "$p")" || false; ax fill
  tel 64; : > "$CONTINUE_IDL"
  ! blocked "$(CC_BOUNDARY_TOK_K=600 actuate sidA "$p")" || false; ax tokens
  : > "$CONTINUE_IDL"
  ! blocked "$(STUB_CE_SIZE='2097152 0' CC_BOUNDARY_SIZE_MB=1 actuate sidA "$p")" || false; ax size
  : > "$CONTINUE_IDL"
  ! blocked "$(STUB_CE_SIZE='0 1600000' actuate sidA "$p")" || false; ax rss
  tel 60; : > "$CONTINUE_IDL"
  ! blocked "$(STUB_CE_BURN='150 10' actuate sidA "$p")" || false; ax forecast
  # control: a forecast at 64% with the wall far away does not abstain
  tel 64; : > "$CONTINUE_IDL"
  blocked "$(STUB_CE_BURN='10 300' actuate sidA "$p")"
}

@test "S13c: headless (CC_PANE_ID, no ITERM_SESSION_ID) and pane-less (neither) abstain" {
  p="$(tx_f1)"
  out="$(env -u ITERM_SESSION_ID CC_PANE_ID=hdl-x bash -c 'printf "{\"cwd\":\"%s\",\"session_id\":\"sidA\",\"transcript_path\":\"%s\"}" "$1" "$2" | bash "$3" 2>/dev/null' _ "$CWD" "$p" "$HOOK")"
  ! blocked "$out" || false
  [ -n "$(row scope-floor-headless)" ]
  : > "$CONTINUE_IDL"
  out="$(env -u ITERM_SESSION_ID bash -c 'printf "{\"cwd\":\"%s\",\"session_id\":\"sidA\",\"transcript_path\":\"%s\"}" "$1" "$2" | bash "$3" 2>/dev/null' _ "$CWD" "$p" "$HOOK")"
  ! blocked "$out" || false
  [ -n "$(row scope-floor-headless)" ]
}

# ── S14-S16 — kinds, irrelevant rungs, an old ledger ──
@test "S14: the loop 🔧 arm blocks with the loop text; any other 🔧 writes no scope-floor row" {
  out="$(STUB_RUNG=🔧 STUB_LOOP_RUNG=1 STUB_BLOCKED=0 STUB_BLOCKED_IDS= actuate sidA "$(tx_f1)")"
  blocked "$out"
  r="$(reason_of "$out")"
  [[ "$r" == *'your frozen scope is a loop with no recorded stop'* ]] || false
  [[ "$r" == *'dod-persist.sh done'* ]] || false
  [[ "$r" == *'--class needs-human'* ]] || false
  [ "$(row scope-floor | jq -r '.kind')" = loop ]
  : > "$CONTINUE_IDL"
  out="$(STUB_RUNG=🔧 STUB_LOOP_RUNG=0 STUB_DIRTY=1 actuate sidB "$(tx_f1)")"   # a fresh sid: sidA's fire would rightly draw one clear row
  ! blocked "$out" || false
  [ "$(rows_like)" = 0 ]
}

@test "S15: irrelevant rungs are silent; after a fire, the first ✅ writes ONE scope-floor-clear" {
  p="$(tx_f1)"
  for r in ✅ 📦 🚀 👤; do STUB_RUNG="$r" STUB_LOOP_SRC=own CC_SHIP_FLOOR=0 actuate sidA "$p" >/dev/null; done
  [ "$(rows_like)" = 0 ]
  blocked "$(actuate sidA "$p")"
  STUB_RUNG=✅ actuate sidA "$p" >/dev/null
  STUB_RUNG=✅ actuate sidA "$p" >/dev/null
  [ "$(grep -c '"reason":"scope-floor-clear"' "$CONTINUE_IDL")" = 1 ]
}

@test "S16: an old ledger without the new fields — no row, no block (fail open)" {
  out="$(STUB_OLD=1 actuate sidA "$(tx_f1)")"
  ! blocked "$out" || false
  [ "$(rows_like)" = 0 ]
}

# ── S17 / S18 — fail closed; kill switches ──
@test "S17: an unwritable state dir never blocks (fail closed) and says so" {
  mkdir -p "$SFSTATE"; chmod 555 "$SFSTATE"
  out="$(actuate sidA "$(tx_f1)")"
  chmod 755 "$SFSTATE"
  ! blocked "$out" || false
  [ -n "$(row scope-floor-unwritable)" ]
}

@test "S18: CC_SCOPE_FLOOR=0 and scope-floor.off are silent; shadow logs, spends no real budget" {
  p="$(tx_f1)"
  ! blocked "$(CC_SCOPE_FLOOR=0 actuate sidA "$p")" || false
  touch "$HOME/.claude/state/scope-floor.off"
  ! blocked "$(actuate sidA "$p")" || false
  rm -f "$HOME/.claude/state/scope-floor.off"
  [ "$(rows_like)" = 0 ]
  ! blocked "$(CC_SCOPE_FLOOR=shadow actuate sidA "$p")" || false
  [ -n "$(row scope-floor-shadow)" ]
  [ ! -e "$SFSTATE/sidA" ]
  [ -f "$SFSTATE/sidA.shadow" ]
  out="$(CC_SCOPE_FLOOR_GAP_S=0 actuate sidA "$p")"
  blocked "$out"
  [[ "$(reason_of "$out")" == *'(scope floor 1/3'* ]]
}

# ── S19 — C1, the capture trigger ──
@test "S19: LOOP_SRC=none on ⛔ runs capture-loop once; an unchanged Scope-line count never re-runs it" {
  p="$(tx_f1)"
  STUB_LOOP_SRC=none STUB_SCOPE_UNGATED=0 STUB_LOOP_OPEN=0 actuate sidA "$p" >/dev/null
  [ "$(grep -c '^capture-loop ' "$BATS_TEST_TMPDIR/dp-argv")" = 1 ]
  grep -qF "capture-loop $p" "$BATS_TEST_TMPDIR/dp-argv"
  STUB_LOOP_SRC=none STUB_SCOPE_UNGATED=0 STUB_LOOP_OPEN=0 actuate sidA "$p" >/dev/null
  [ "$(grep -c '^capture-loop ' "$BATS_TEST_TMPDIR/dp-argv")" = 1 ]
  # a captured result is logged; a non-loop rung (📦) never triggers it
  printf '\n%s\n' "$(u_str 'Scope (frozen): loop until green')" >> "$p"
  STUB_CAPTURE=captured STUB_LOOP_SRC=none STUB_SCOPE_UNGATED=0 actuate sidA "$p" >/dev/null
  [ -n "$(row scope-capture)" ]
  printf '%s\n' "$(u_str 'Scope (frozen): loop until done')" >> "$p"
  STUB_RUNG=📦 STUB_LOOP_SRC=none CC_SHIP_FLOOR=0 actuate sidA "$p" >/dev/null
  [ "$(grep -c '^capture-loop ' "$BATS_TEST_TMPDIR/dp-argv")" = 2 ]
}

# ── S21 — /bin/bash 3.2 (the `{\}` default trap) ──
@test "S21: under /bin/bash the F1 block and the fail-closed abstain behave the same; IDL rows parse" {
  p="$(tx_f1)"
  out="$(printf '{"cwd":"%s","session_id":"sidA","transcript_path":"%s"}' "$CWD" "$p" | /bin/bash "$HOOK" 2>/dev/null)"
  blocked "$out"
  chmod 555 "$SFSTATE"
  out="$(printf '{"cwd":"%s","session_id":"sidB","transcript_path":"%s"}' "$CWD" "$p" | /bin/bash "$HOOK" 2>/dev/null)"
  chmod 755 "$SFSTATE"
  ! blocked "$out" || false
  [ -n "$(row scope-floor-unwritable)" ]
  jq -e . "$CONTINUE_IDL" >/dev/null
}

# ── S20 / S23 — composition with the other Stop arms on ONE Stop (real completion-assert, anti-deference) ──
other_hooks_env() {
  export COMPLETION_IDL="$BATS_TEST_TMPDIR/ca-idl.jsonl" COMPLETION_STATE_DIR="$BATS_TEST_TMPDIR/ca-state"
  export ANTIDEF_IDL="$BATS_TEST_TMPDIR/ad-idl.jsonl" ANTIDEF_STATE_DIR="$BATS_TEST_TMPDIR/ad-state" CC_JEV=0
  export CC_DECISIONS_DIR="$BATS_TEST_TMPDIR/decisions"
}
run_hook_as() { printf '{"cwd":"%s","session_id":"sidA","transcript_path":"%s"}' "$CWD" "$2" | bash "$REPO/hooks/$1" 2>/dev/null; }
tx_close() {
  local p="$BATS_TEST_TMPDIR/close-$RANDOM.jsonl"
  { u_str 'Scope (frozen): Loop until dry.'; u_str "$NOTE"; a_txt "$1"; } > "$p"; printf '%s' "$p"
}

@test "S20: the floor composes with completion-assert — its ⛔ contradiction yields to the floor's block (one message)" {
  other_hooks_env
  p="$(tx_close '✅ Good to close: yes — nothing left to do.')"
  out="$(run_hook_as session-continue.sh "$p")"
  blocked "$out"
  run_hook_as completion-assert.sh "$p" >/dev/null
  grep -q 'double-block-yield:session-continue-scope-floor' "$COMPLETION_IDL" || { cat "$COMPLETION_IDL"; false; }
}

@test "S23: a loop 🔧 under a 'yes' close — the floor blocks; anti-deference and completion-assert add no ledger block" {
  other_hooks_env
  export STUB_RUNG=🔧 STUB_LOOP_RUNG=1 STUB_BLOCKED=0 STUB_BLOCKED_IDS= STUB_BLOCKED_GLOSS=
  p="$(tx_close '✅ Good to close: yes — nothing left to do')"
  out="$(run_hook_as session-continue.sh "$p")"
  blocked "$out"
  [[ "$(reason_of "$out")" == *'dod-persist.sh done'* ]] || false
  [ "$(row scope-floor | jq -r .kind)" = loop ]
  ad="$(run_hook_as anti-deference-nudge.sh "$p")"
  ! blocked "$ad" || false
  ! grep -q '"false-done"' "$ANTIDEF_IDL" 2>/dev/null || false
  # the double-block yield would mask a contradiction, so judge completion-assert WITHOUT it
  ca="$(CC_DOUBLE_BLOCK_GUARD=0 run_hook_as completion-assert.sh "$p")"
  ! blocked "$ca" || { cat "$COMPLETION_IDL"; false; }
}

@test "S24: the ledger is asked with the Stop payload's session id (a Stop env need not carry one)" {
  export STUB_ARGV_LOG="$BATS_TEST_TMPDIR/wl-argv"
  out="$(actuate sidA "$(tx_f1)")"
  blocked "$out"
  grep -q -- '--machine --session sidA' "$STUB_ARGV_LOG" || { cat "$STUB_ARGV_LOG"; false; }
}
