#!/usr/bin/env bats
# shellcheck disable=SC2016  # the bash -c bodies read $1/$2 as positional args, on purpose
# lever-idle-shadows — W7+ wave S2 (docs/plans/USAGE_LEVERS.md § W7+ §2 D1/D3, §3 "Telemetry rows"):
# the idle shadows' lever telemetry, still log-only at pct 0.
#
# Owns:
#   D3 arm rows   hooks/idle-keepalive.sh writes one kind=arm row (lever D3, unit "<sid>:<episode>")
#                 at each due time, BEFORE the would-wake row, from a flag file read AT the due time,
#                 in both arms; and nothing it does changes with the arm (exit 0, no output).
#   gap v2/wake v3  hooks/lib/idle_gap.py: episode_id/unit/ended_by/return_s/busy/watcher/arm on gap
#                 rows, lever/arm/variant/unit_id/eligible/fired on wake rows; an episode is carried
#                 across a gap a FIRED wake ended (the treatment wave's contract with this ledger).
#   IRS v2        hooks/boundary-handoff.sh: schema 2, the 200k field on every row, prompt sha + head,
#                 the D1 arm of the lineage root, every row ≤ 2 KB.
# The neighbouring contracts (gap pricing, the headless guard, the IRS predicate and its stdout/IDL
# parity) stay with tests/idle-keepalive.bats and tests/boundary-handoff-idle-shadow.bats.
#
# RED-proof (2026-10-25): case 3 measured against a mutant whose lf_arm runs at launch, before the
# settle sleep: it logs flag_rev 3, the hook 7. Case 6's multibyte half went red on the first build
# for a real defect: jq -R turned an é straddling its 4 KB read buffer into U+FFFD, so prompt_sha
# hashed the wrong text (fixed with --rawfile). Cases 1, 4 and 5 fail against the base hooks
# (git show c43f39d2b:…) by construction: no lever-arms row, wake v2, gap v1, no schema 2. Case 2 is
# the parity half and runs the base hook itself.
# Hooks run under /bin/bash (3.2 on macOS), as launchd/the harness run them.

load helpers/cc-stub

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude"
  export CLAUDE_CONFIG_DIR="$HOME/.claude-tertiary"; mkdir -p "$CLAUDE_CONFIG_DIR"
  export CC_LEVER_STATE_DIR="$BATS_TEST_TMPDIR/levers"; mkdir -p "$CC_LEVER_STATE_DIR"
  export CC_LEVER_LOG_DIR="$BATS_TEST_TMPDIR/logs"
  export CC_IDLE_KEEPALIVE_LOG="$BATS_TEST_TMPDIR/logs/lever-arms.jsonl"   # one file: row ORDER is observable
  export CC_IDLE_KEEPALIVE_STATE="$BATS_TEST_TMPDIR/state"
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mailbox"; mkdir -p "$CC_MAILBOX_DIR"
  export CC_TELEMETRY_DIR="$BATS_TEST_TMPDIR/tel"
  # idle_gap.py drops its row silently past this bound (4 s by default); a loaded box can spend that
  # just starting python, so the suite must not depend on the box's load
  export CC_IDLE_GAP_BOUND_S=120
  unset CC_IDLE_KEEPALIVE CLAUDE_CODE_ENTRYPOINT CC_PANE_ID ITERM_SESSION_ID CC_KEEPALIVE_WAKE_S CC_KEEPALIVE_MAX_WAKES \
    CC_LEVER_ALL CC_LEVER_D1 CC_LEVER_D3 CC_LEVER_EXCLUDE CC_LEVER_LINEAGE CC_LEVER_FLAGS CC_LEVER_HEARTBEAT CC_IRS
  TX="$BATS_TEST_TMPDIR/sess.jsonl"; : > "$TX"
  SID="0b5e1d2c-aaaa-bbbb-cccc-000000000002"
  PAYLOAD="$(jq -nc --arg s "$SID" --arg t "$TX" '{session_id:$s,transcript_path:$t,hook_event_name:"Stop"}')"
  flags 3 shadow 0
}

# flags <rev> <mode> <pct> — the flag file, D1 and D3 with fixed salts
flags() {
  jq -nc --argjson rev "$1" --arg m "$2" --argjson p "$3" '{v:1, rev:$rev, levers:{
    D1:{stage:"S0", mode:$m, pct:$p, holdback:0, salt:"saltD1", split_salt:"splitD1", params_id:"p0"},
    D3:{stage:"S0", mode:$m, pct:$p, holdback:0, salt:"saltD3", split_salt:"splitD3", params_id:"p0"}}}' \
    > "$CC_LEVER_STATE_DIR/flags.json"
}
iso() { date -u -r "$1" +%FT%TZ; }
asst_at() { # <epoch> <cache_write> <cache_read>
  printf '{"type":"assistant","timestamp":"%s","message":{"model":"claude-opus-5-5","usage":{"input_tokens":2,"cache_creation_input_tokens":%s,"cache_read_input_tokens":%s,"output_tokens":98}}}\n' \
    "$(iso "$1")" "$2" "$3" >> "$TX"
}
user_at() { printf '{"type":"user","timestamp":"%s","message":{"content":"go"}}\n' "$(iso "$1")" >> "$TX"; }
tracker() { run bash -c 'printf "%s" "$1" | /bin/bash "$2"' _ "$PAYLOAD" "$REPO/hooks/cache-expiry-tracker.sh"; }
# timer [hook] — the keepalive as an interactive session runs it, with a 1 s wake
timer() {
  run env CC_IDLE_KEEPALIVE_HARNESS_ARGV="claude --model x" CC_IDLE_KEEPALIVE_HARNESS_FD1=/dev/ttys009 \
    CC_KEEPALIVE_WAKE_S=1 CC_IDLE_KEEPALIVE_SETTLE_S=0 CC_IDLE_KEEPALIVE_POLL_S=1 \
    bash -c 'printf "%s" "$1" | /bin/bash "$2" 2>&1' _ "$PAYLOAD" "${1:-$REPO/hooks/idle-keepalive.sh}"
}
rows() { jq -c "select(.kind==\"$1\")" "$CC_IDLE_KEEPALIVE_LOG"; }
u6() { /usr/bin/python3 -I "$REPO/hooks/lib/lever_flags.py" hash "$1" "$2" | cut -d' ' -f2; }

@test "(1) D3: the arm row precedes the wake row, and arm, wake and gap rows join on one unit" {
  now=$(date +%s)
  asst_at $((now - 30)) 500 150000
  tracker
  start=$(jq -r '.start' "$CC_IDLE_KEEPALIVE_STATE/$SID.json")
  timer
  [ "$status" -eq 0 ]; [ -z "$output" ]
  [ "$(jq -r '.kind' "$CC_IDLE_KEEPALIVE_LOG" | tr '\n' ' ')" = "arm wake " ]
  unit="$SID:$start"
  [ "$(rows arm | jq -r '[.lever,.unit,.arm,.flag_src,.stage,.pct_eff,.flag_rev,.hook,.due_n,.acct] | map(tostring) | join(" ")')" \
    = "D3 $unit ctrl file S0 0 3 idle-keepalive 1 .claude-tertiary" ]
  # u is compared as a NUMBER: the wake row passes through python, which writes 0.12 for 0.120000
  want_u="$(u6 saltD3 "$unit")"
  rows arm | jq -e --argjson w "$want_u" '.u == $w' >/dev/null
  rows arm | jq -e '.ts | test("^[0-9-]{10}T[0-9:]{8}Z$")' >/dev/null
  [ "$(rows wake | jq -r '[.v,.lever,.arm,.unit_id,.fired,.eligible] | map(tostring) | join(" ")')" \
    = "3 D3 ctrl $unit false false" ]
  rows wake | jq -e --argjson w "$want_u" '.u == $w' >/dev/null
  # the operator returns 65 min after the gap opened: the gap row carries the decision and the unit
  user_at $((start + 3900)); asst_at $((start + 3905)) 150600 0
  tracker
  [ "$(rows gap | jq -r '[.v,.unit,.episode_id,.ended_by,(.return_s | if . then floor else . end),.busy,.watcher_armed,.eligible,.arm,.wake_req] | map(tostring) | join(" ")')" \
    = "2 $unit $(iso "$start") record 3900 false false false ctrl null" ]
  [ "$(rows arm | wc -l | tr -d ' ')" -eq 1 ]
}

@test "(2) pct 0 changes nothing the keepalive does: rc, output and the v2 wake row equal the base hook's" {
  base="$BATS_TEST_TMPDIR/base"; mkdir -p "$base/lib"
  cp "$REPO"/hooks/lib/mailbox-pending.sh "$base/lib/"
  # the base's idle_gap.py calls its own session_jobs API (S6b renamed state_at(jobs) to running_at)
  git -C "$REPO" show c43f39d2b:hooks/lib/session_jobs.py > "$base/lib/session_jobs.py"
  git -C "$REPO" show c43f39d2b:hooks/idle-keepalive.sh > "$base/idle-keepalive.sh"
  git -C "$REPO" show c43f39d2b:hooks/lib/idle_gap.py > "$base/lib/idle_gap.py"
  asst_at "$(date +%s)" 500 150000
  tracker
  timer "$base/idle-keepalive.sh"; b_rc=$status; b_out="$output"
  b_row="$(rows wake | jq -c 'del(.ts,.late_s,.gap_start,.v)')"
  : > "$CC_IDLE_KEEPALIVE_LOG"
  timer; [ "$status" -eq "$b_rc" ]; [ "$output" = "$b_out" ]; [ -z "$output" ]
  [ "$(rows wake | jq -c 'del(.ts,.late_s,.gap_start,.v,.lever,.arm,.variant,.unit_id,.flag_src,.u,.eligible,.fired,.pct_eff,.headless,.why_not)')" = "$b_row" ]
  # live at 100% with a fresh guard heartbeat: the arm says treat, and with no job busy nothing wakes
  # (the treatment wake itself is tests/lever-d1-d3-treatment.bats')
  flags 4 live 100; touch "$CC_LEVER_STATE_DIR/guard.heartbeat"
  : > "$CC_IDLE_KEEPALIVE_LOG"
  timer
  [ "$status" -eq 0 ]; [ -z "$output" ]
  [ "$(rows arm | jq -r '[.arm,.pct_eff] | map(tostring) | join(" ")')" = "treat 100" ]
  [ "$(rows wake | jq -r '[.arm,.fired,.mode] | map(tostring) | join(" ")')" = "treat false shadow" ]
}

@test "(3) the flag file is read at the due time, not at launch" {
  # the hook's first sleep is its settle, after launch and before the due time: rewrite the flags there
  cc_stub "$BATS_TEST_TMPDIR/bin" sleep "$(printf '#!/bin/bash\n[ -e "%s/once" ] || { : > "%s/once"; %s; }\nexec /bin/sleep "$@"\n' \
    "$BATS_TEST_TMPDIR" "$BATS_TEST_TMPDIR" \
    "jq '.rev = 7' '$CC_LEVER_STATE_DIR/flags.json' > '$BATS_TEST_TMPDIR/f' && mv '$BATS_TEST_TMPDIR/f' '$CC_LEVER_STATE_DIR/flags.json'")"
  asst_at "$(date +%s)" 500 150000
  tracker
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" timer
  [ "$status" -eq 0 ]
  [ -e "$BATS_TEST_TMPDIR/once" ]
  [ "$(rows arm | jq -r .flag_rev)" = 7 ]
}

@test "(4) gap v2: a gap a FIRED wake ended carries its episode into the next gap; return_s counts from the episode" {
  now=$(date +%s); s0=$((now - 7000))
  mkdir -p "$CC_IDLE_KEEPALIVE_STATE"
  jq -nc --arg s "$SID" --arg t "$TX" --argjson st "$s0" \
    '{sid:$s,start:$st,episode:$st,ctx:150000,acct:"x",transcript:$t,
      wake:{n:1,at:($st+3300),fired:true,arm:"treat",variant:null,busy:true,watcher_armed:false,
            watcher_fires_before_ttl:false,eligible:true}}' > "$CC_IDLE_KEEPALIVE_STATE/$SID.json"
  user_at $((s0 + 3301)); asst_at $((s0 + 3305)) 300 150000; asst_at $((s0 + 3310)) 100 150300
  CC_IDLE_KEEPALIVE_NOW=$((s0 + 3320)) tracker
  [ "$status" -eq 0 ]; [ -z "$output" ]
  [ "$(rows gap | jq -r '[.ended_by,(.return_s | if . then floor else . end),.wake_req,.wake_tokens.cw,.wake_tokens.cr,.unit,.arm] | map(tostring) | join(" ")')" \
    = "wake null 2 400 300300 $SID:$s0 treat" ]
  [ "$(jq -r '[.episode,.start] | map(tostring) | join(" ")' "$CC_IDLE_KEEPALIVE_STATE/$SID.json")" = "$s0 $((s0 + 3320))" ]
  : > "$CC_IDLE_KEEPALIVE_LOG"
  user_at $((s0 + 5000)); asst_at $((s0 + 5005)) 150600 0
  CC_IDLE_KEEPALIVE_NOW=$((s0 + 5010)) tracker
  [ "$(rows gap | jq -r '[.ended_by,(.return_s | if . then floor else . end),.episode_id,.unit,.wake_req,.arm] | map(tostring) | join(" ")')" \
    = "record 5000 $(iso "$s0") $SID:$s0 null null" ]
}

# ── IRS v2 ───────────────────────────────────────────────────────────────────────────────────────
irs_setup() {
  export CC_FIRE_CAPACITY_GATE=off CC_BOUNDARY_T_FREEWIN=0
  export CC_TELEMETRY_DIR="$BATS_TEST_TMPDIR/tel"; mkdir -p "$CC_TELEMETRY_DIR"
  export CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl" CC_BOUNDARY_LATCH_DIR="$BATS_TEST_TMPDIR/latch"
  export CC_CONTINUE_SENTINEL="$BATS_TEST_TMPDIR/no-such-sentinel" CC_RECYCLE_RETRY_DIR="$BATS_TEST_TMPDIR/rr"
  export CC_IRS_LOG="$BATS_TEST_TMPDIR/irs.jsonl"
  unset WRAP_SESSION_ID CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID
  NOW="$(date +%s)"; TP="$BATS_TEST_TMPDIR/t.jsonl"
  jq -nc --argjson ts "$NOW" --arg cwd "$BATS_TEST_TMPDIR" \
    '{ts:$ts,session_id:"sidS",cwd:$cwd,config_dir:"/cfg",used_pct:40,input_tokens:400000}' > "$CC_TELEMETRY_DIR/sidS.json"
}
ji() { jq -rn --argjson e "$1" '$e | todate | sub("Z$"; ".123Z")'; }
a_rec() { jq -nc --arg t "$(ji "$1")" --argjson c "$2" \
  '{type:"assistant",timestamp:$t,message:{model:"claude-opus-5-5",usage:{input_tokens:2,cache_read_input_tokens:($c-1002),cache_creation_input_tokens:1000}}}'; }
p_rec() { jq -nc --arg t "$(ji "$1")" --arg s "$2" '{type:"user",timestamp:$t,message:{role:"user",content:$s}}'; }
# idle_turn <idle s> <prompt> — 300k at idle, then the prompt that ended the gap
idle_turn() {
  local t0=$(( NOW - $1 - 120 ))
  { p_rec $(( t0 - 60 )) "first task"; a_rec "$t0" 300000; p_rec $(( t0 + $1 - 2 )) "$2"; a_rec $(( t0 + $1 )) 305000; } > "$TP"
}
boundary() { # one Stop, on fresh telemetry (a loaded box can outlast the hook's 180 s staleness bound)
  jq --argjson ts "$(date +%s)" '.ts = $ts' "$CC_TELEMETRY_DIR/sidS.json" > "$BATS_TEST_TMPDIR/tel.tmp" \
    && mv "$BATS_TEST_TMPDIR/tel.tmp" "$CC_TELEMETRY_DIR/sidS.json"
  jq -cn --arg t "$TP" '{session_id:"sidS",transcript_path:$t}' | /bin/bash "$REPO/hooks/boundary-handoff.sh" >/dev/null 2>&1; }

@test "(5) IRS v2: schema 2, prompt sha and head, the D1 arm of the lineage root, the 200k field on every row" {
  irs_setup
  idle_turn 1200 "next step, please"
  CC_LEVER_LINEAGE=rootLINE boundary
  [ "$(wc -l < "$CC_IRS_LOG" | tr -d ' ')" -eq 1 ]
  [ "$(jq -r '[.schema,.v,.lever,.arm,.variant,.lineage,.lineage_src,.d1.flag_src,.d1.stage,.k2_thousand,.would_advise_k2,.prompt_head] | map(tostring) | join("|")' "$CC_IRS_LOG")" \
    = "2|ok|D1|ctrl|null|rootLINE|env|file|S0|200|true|next step, please" ]
  [ "$(jq -r .prompt_sha "$CC_IRS_LOG")" = "$(printf '%s' 'next step, please' | shasum -a 256 | cut -c1-64)" ]
  jq -e --argjson w "$(u6 saltD1 rootLINE)" '.d1.u == $w' "$CC_IRS_LOG" >/dev/null
  jq -e '(.ts | type) == "number" and (.ts_z | test("Z$")) and (has("_p") | not)' "$CC_IRS_LOG" >/dev/null
  # a row with no readable gap (no request in reach) still carries the 200k field, and no prompt
  rm -f "$CC_IRS_LOG"
  p_rec $(( NOW - 30 )) "only a prompt" > "$TP"
  boundary
  [ "$(jq -r '[.v,.schema,.k2_thousand,.would_advise_k2,.prompt_sha,.arm] | map(tostring) | join(" ")' "$CC_IRS_LOG")" \
    = "no-request 2 200 null null ctrl" ]
}

@test "(6) IRS v2 rows are capped at 2 KB: a long prompt keeps 200 chars, an escape-heavy one shrinks its head" {
  irs_setup
  long="$(printf 'é%.0s' $(seq 1 3000))"
  idle_turn 1200 "$long"
  boundary
  [ "$(jq -r '.prompt_head | length' "$CC_IRS_LOG")" -eq 200 ]
  [ "$(jq -r .prompt_sha "$CC_IRS_LOG")" = "$(printf '%s' "$long" | shasum -a 256 | cut -c1-64)" ]
  [ "$(wc -c < "$CC_IRS_LOG" | tr -d ' ')" -le 2048 ]
  rm -f "$CC_IRS_LOG"
  esc="$(printf '\001%.0s' $(seq 1 400))"
  idle_turn 1200 "$esc"
  CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/$(printf 'c%.0s' $(seq 1 700))" boundary   # a long config_dir fills the row
  [ "$(wc -l < "$CC_IRS_LOG" | tr -d ' ')" -eq 1 ]
  [ "$(wc -c < "$CC_IRS_LOG" | tr -d ' ')" -le 2048 ]
  [ "$(jq -r '.prompt_head | length' "$CC_IRS_LOG")" -lt 200 ]
  jq -e '.schema == 2 and (.prompt_sha | length) == 64' "$CC_IRS_LOG" >/dev/null
}
