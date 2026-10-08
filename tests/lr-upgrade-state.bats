#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2016  # stubs are written verbatim; each @test is its own subshell; per-test exports are the intent
# lr-upgrade × the per-session STATE RECORD, the STEP LEDGER, BOUNDED RETRY, --status, --reset, the
# self-bounded drain and its refill, and the prompt-free proof (2026-10-08 design, sections 3-9).
# Subject: scripts/limit-recover/lr-upgrade.sh — lru_st_put/lru_st_get, lru_step (lru-step rows in
# <run>/events.jsonl), lru_class_of/lru_st_verdict, lru_st_eligible, lru_drive/_lru_drive_run,
# lru_prove_verdict, lru_drain + lru_refill, lru_status, lru_reset. Run under /bin/bash (3.2), the
# interpreter launchd gives the drainer.
#
# Hermetic: HOME, LRU_STATE, the registry, the config root and `ps` (LRU_PS_SNAPSHOT, a file) are
# fixtures; time is LRU_NOW; handoff-fire, it2, cc-notify, cc-resume-debt, cc-find, capacity-admit,
# lr-lib (lr_resume_procs / lr_engaged_after), the TUI lib, kill and the binary resolver are stubs
# that record their calls. No real terminal, pane, kitty socket, registry, mailbox or ~/.reso is
# touched; the it2 recorder must stay EMPTY in every case (nothing here types raw).

setup() {
  command -v jq >/dev/null || skip "jq required"
  export CC_FIRE_CAPACITY_GATE=off
  export CC_ADMIT_GATE=off
  unset CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID CC_SESSION_ID LR_UPGRADE_AUTO LRU_CONFIRM_TURN LR_STATE_DIR
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LRU="$REPO/scripts/limit-recover/lr-upgrade.sh"
  T="$BATS_TEST_TMPDIR"
  export STUB_T="$T"
  export HOME="$T/home"; mkdir -p "$HOME"
  export LRU_STATE="$HOME/.reso/limit-recover"; mkdir -p "$LRU_STATE"
  ST="$LRU_STATE/upgrade-state"
  export LRU_REG_DIR="$T/reg"; mkdir -p "$LRU_REG_DIR"
  export LRU_CFG_ROOT="$T/cfgroot"; mkdir -p "$LRU_CFG_ROOT"
  CFG="$LRU_CFG_ROOT/.claude-t"; mkdir -p "$CFG/projects/-x"
  export LRU_PS_SNAPSHOT="$T/ps.txt"; : > "$LRU_PS_SNAPSHOT"
  export LRU_KITTY_LS="$T/kitty-ls.json"; echo '[]' > "$LRU_KITTY_LS"
  export CC_COMPOSER_RESIDUE_DIR="$T/residue"
  export LRU_COMPOSER=off
  export LRU_SELF_SID=""
  export NOW=1791500000 LST="Tue Sep 22 06:47:13 2026"
  export LRU_NOW="$NOW"
  STUBS="$T/stubs"; mkdir -p "$STUBS"
  # it2: a recorder that must stay empty.
  printf '#!/bin/bash\necho "$*" >> %s\n' "$T/it2.log" > "$STUBS/it2"; chmod +x "$STUBS/it2"
  export LRU_IT2_BIN="$STUBS/it2" LRU_RETYPE_MAX=0 LRU_RETYPE_GAP_S=0 LRU_ENGAGE_S=0 LRU_GAP_S=0
  export LRU_PROVE_GAP_S=0 LRU_PROVE_HOLD_S=0 LRU_EXIT_LINGER_S=0 LRU_READY_S=0 LRU_RELAUNCH_UP_S=0
  export LRU_CLEAR_SETTLE_S=0 LRU_CENSUS_TIMEOUT_S=120
  export LRU_KILL_BIN="$STUBS/kill"
  printf '#!/bin/bash\necho "$*" >> %s\n' "$T/kill.log" > "$LRU_KILL_BIN"; chmod +x "$LRU_KILL_BIN"
  export LRU_NOTIFY_BIN="$STUBS/cc-notify"
  printf '#!/bin/bash\necho "$*" >> %s\nexit 0\n' "$T/notify.log" > "$LRU_NOTIFY_BIN"; chmod +x "$LRU_NOTIFY_BIN"
  # cc-resume-debt: surface/prove/settle rcs come from $T/<verb>-rc (default 0); every call logged.
  export CC_RESUME_DEBT_BIN="$STUBS/cc-resume-debt"
  cat > "$CC_RESUME_DEBT_BIN" <<'EOF'
#!/bin/bash
echo "$*" >> "$STUB_T/rd.log"
case "$1" in surface|prove|settle) exit "$(cat "$STUB_T/$1-rc" 2>/dev/null || echo 0)" ;; esac
exit 0
EOF
  chmod +x "$CC_RESUME_DEBT_BIN"
  # The binary resolver: logs the argv of whoever asked, so a census (`--census …`) is countable.
  export NEW="/opt/cc/.claude-280/node_modules/.bin/claude"
  OLD="/opt/cc/.claude-260/node_modules/.bin/claude"
  cat > "$STUBS/cc-claude-bin" <<'EOF'
#!/bin/bash
echo "$(ps -o args= -p "$PPID" 2>/dev/null)" >> "$STUB_T/claude-bin.log"
echo "$NEW"
EOF
  chmod +x "$STUBS/cc-claude-bin"
  export LRU_CLAUDE_BIN_CMD="$STUBS/cc-claude-bin"
  export LRU_SA_PROBE="$STUBS/sa-probe"
  printf '#!/bin/bash\necho "live_subagents: 0"\n' > "$LRU_SA_PROBE"; chmod +x "$LRU_SA_PROBE"
  export LRU_MODEL_CONFIG="$T/model-config.yaml"
  cat > "$LRU_MODEL_CONFIG" <<'Y'
versions:
  frontier_latest: claude-fable-5-1
  opus_latest: claude-opus-5-5
  opus_prior: claude-opus-5
frontier_access:
  active: true
  model: claude-fable-5-1
Y
  # capacity-admit: the probe logs (with the residue receipts present at that moment) and answers
  # $T/probe-rc; the mint CREATES a token file, so a leak or a drop is a file on disk.
  export LRU_CA_LIB="$T/ca.sh"
  cat > "$LRU_CA_LIB" <<'EOF'
cc_capacity_probe() {
  echo "probe $* receipts=$(ls "$CC_COMPOSER_RESIDUE_DIR" 2>/dev/null | tr '\n' ' ')" >> "$STUB_T/probe.log"
  return "$(cat "$STUB_T/probe-rc" 2>/dev/null || echo 0)"
}
cc_capacity_admit_reason() { echo "load 9.9/core over 1.5"; }
cc_capacity_token_mint() { mkdir -p "$STUB_T/tokens"; : > "$STUB_T/tokens/tok-$1"; echo "$STUB_T/tokens/tok-$1"; }
EOF
  # lr-lib: a --resume leaf is any snapshot line naming `--resume <sid>`; a fresh turn is $T/engaged.
  export LRU_LR_LIB="$T/lr-lib.sh"
  cat > "$LRU_LR_LIB" <<'EOF'
lr_resume_procs() { LRP_S="$1" awk 'index($0, "--resume " ENVIRON["LRP_S"]) { print $1 }' "$LRU_PS_SNAPSHOT"; }
lr_engaged_after() { echo "engaged $*" >> "$STUB_T/engaged.log"; [ -f "$STUB_T/engaged" ]; }
EOF
  # cc-tui: the composer comes from $T/composer-<pane> (from the 2nd read on, $T/composer-<pane>.after
  # when present); send-text is logged, never sent.
  export LRU_TUI_LIB="$T/tui.sh"
  cat > "$LRU_TUI_LIB" <<'EOF'
cc_tui_composer() {
  local n; n=$(( $(cat "$STUB_T/composer-$1.n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$STUB_T/composer-$1.n"
  if [ "$n" -ge 2 ] && [ -f "$STUB_T/composer-$1.after" ]; then cat "$STUB_T/composer-$1.after"; else cat "$STUB_T/composer-$1" 2>/dev/null; fi
  return 0
}
cc_tui_rpc() { echo "$*" >> "$STUB_T/tui-rpc.log"; }
EOF
  # cc-find: TSV from $T/ccfind-<sid>.
  export LRU_CCFIND_BIN="$STUBS/cc-find"
  printf '#!/bin/bash\ncat "%s/ccfind-$1" 2>/dev/null\n' "$T" > "$LRU_CCFIND_BIN"; chmod +x "$LRU_CCFIND_BIN"
  # handoff-fire: per-sid behaviour from files — $T/hf-<sid>.out (printed), .resume (a pid: a target
  # --resume leaf is appended to the snapshot), .state (an lr-fire-resume state appended to the run's
  # events.jsonl), .sh (sourced), .rc (exit; default 1). Every call and its env are logged.
  export LRU_HF_BIN="$STUBS/hf"
  cat > "$LRU_HF_BIN" <<'EOF'
#!/bin/bash
MODE=""; S=""; L=""; P=""
while [ $# -gt 0 ]; do
  case "$1" in
    --recycle|--relaunch-at-shell) MODE="$1" ;;
    --source-session) S="$2"; shift ;;
    --resume-launcher) L="$2"; shift ;;
    --source-pane) P="$2"; shift ;;
  esac
  shift
done
echo "hf $MODE $S $P engage=${HF_ENGAGE_BY_PROCESS:-unset} launcher=$L" >> "$STUB_T/hf.log"
for f in "$CC_COMPOSER_RESIDUE_DIR"/*; do
  [ -f "$f" ] && printf '%s\t%s\n' "${f##*/}" "$(cut -f2- "$f")" >> "$STUB_T/receipts-at-hf.log"
done
[ -f "$STUB_T/hf-$S.out" ] && cat "$STUB_T/hf-$S.out"
if [ -f "$STUB_T/hf-$S.resume" ]; then
  printf '%s 1 %s %s --permission-mode auto --model claude-opus-5-5 --effort high --resume %s\n' \
    "$(cat "$STUB_T/hf-$S.resume")" "$LST" "$NEW" "$S" >> "$LRU_PS_SNAPSHOT"
fi
if [ -f "$STUB_T/hf-$S.state" ] && [ -n "$L" ]; then
  printf '{"state":"%s"}\n' "$(cat "$STUB_T/hf-$S.state")" >> "$(dirname "$L")/events.jsonl"
fi
# shellcheck disable=SC1090
[ -f "$STUB_T/hf-$S.sh" ] && . "$STUB_T/hf-$S.sh"
exit "$(cat "$STUB_T/hf-$S.rc" 2>/dev/null || echo 1)"
EOF
  chmod +x "$LRU_HF_BIN"
  N=0
}

teardown() {
  local p
  if [ -f "$BATS_TEST_TMPDIR/live.pids" ]; then
    while read -r p; do kill "$p" 2>/dev/null || true; done < "$BATS_TEST_TMPDIR/live.pids"
  fi
}

# A REAL live process for the old claude (kill -0 must see it); reaped in teardown.
live() { sleep 300 >/dev/null 2>&1 3>&- & LIVE_PID=$!; echo "$LIVE_PID" >> "$BATS_TEST_TMPDIR/live.pids"; }
sess() { # sess <pane> <sid> <argv> — registry row + ps line + an at-rest transcript (account claude-t)
  local pane="$1" sid="$2" argv="$3" pid
  N=$((N + 1)); pid="${SESS_PID:-$((50000 + N))}"
  printf '{"paneUUID":"%s","pid":%d,"session_id":"%s","account":"claude-t","cwd":"%s","lstart":"%s"}\n' \
    "$pane" "$pid" "$sid" "$BATS_TEST_TMPDIR" "$LST" > "$LRU_REG_DIR/$pane.json"
  printf '%d 1 %s %s\n' "$pid" "$LST" "$argv" >> "$LRU_PS_SNAPSHOT"
  local tx="$CFG/projects/-x/$sid.jsonl"
  printf '%s\n' '{"type":"user","message":{"content":"hi"}}' \
    '{"type":"assistant","message":{"stop_reason":"end_turn","content":[{"type":"text"}]}}' > "$tx"
  SPID="$pid"
}
old_sess() { live; SESS_PID="$LIVE_PID" sess "$1" "$2" "$OLD --permission-mode auto --model claude-opus-5 --effort high"; }
result() { printf '%s' "$LRU_STATE/results/upgrade-$1.json"; }
recf() { printf '%s' "$ST/$1.json"; }
st() { jq -r "($2) | tostring" "$(recf "$1")"; }
run_of() { jq -r .run "$(recf "$1")"; }
rec() { # rec <sid> <jq object, $now bound> — a record written directly, with its .open sentinel
  mkdir -p "$ST"
  jq -n --arg sid "$1" --argjson now "$NOW" --arg lst "$LST" --arg cfg "$CFG" "{v: 1, sid: \$sid} + ($2)" > "$(recf "$1")"
  case "$(jq -r .disposition "$(recf "$1")")" in in-flight|exit-pending) : > "$ST/$1.open" ;; esac
}
queue() { # queue <file> <sid> <pane> [by]
  mkdir -p "$LRU_STATE/upgrade-queue"
  printf '{"kind":"upgrade","sid":"%s","source_pane":"%s","requested_by":"%s","req_id":"r-%s"}\n' \
    "$2" "$3" "${4:-op-pane}" "${2:0:8}" > "$LRU_STATE/upgrade-queue/$1"
}
hf_resumes() { echo "$((99000 + N))" > "$T/hf-$1.resume"; echo 0 > "$T/hf-$1.rc"; }
hf_holds() { # hf_holds <sid> <hold reason> [debt-open: 1]
  { [ "${3:-0}" = 1 ] && echo '→ resume-debt open: rc 0'
    printf "!! recycle ABORTED before /exit (held: %s): the composer read back '<unreadable>'\n" "$2"; } > "$T/hf-$1.out"
  echo 1 > "$T/hf-$1.rc"
}
no_raw_typing() { [ ! -s "$T/it2.log" ] || { echo "it2 was used:"; cat "$T/it2.log"; false; }; }
census_count() { [ -f "$T/claude-bin.log" ] || { echo 0; return 0; }; grep -c -- '--census --all' "$T/claude-bin.log" || true; }

# ── S1 LIFECYCLE ─────────────────────────────────────────────────────────────────────────────────

@test "S1 lifecycle: a plain drive ends upgraded/done/0 with one ok lru-step row per step" {
  SID=51515151-0000-4000-8000-000000000001
  old_sess 501 "$SID"
  hf_resumes "$SID"; : > "$T/engaged"
  LRU_CONFIRM_TURN=on run /bin/bash "$LRU" --drive "$SID" 501
  [ "$status" -eq 0 ] || { echo "$output"; cat "$(result "$SID")"; false; }
  [ "$(jq -r .verdict "$(result "$SID")")" = upgraded ] || { cat "$(result "$SID")"; false; }
  [[ "$(jq -r .reason "$(result "$SID")")" == *"confirmed by a fresh assistant turn"* ]] || { cat "$(result "$SID")"; false; }
  [ "$(st "$SID" .disposition)" = upgraded ] || { cat "$(recf "$SID")"; false; }
  [ "$(st "$SID" .step)" = "done" ]
  [ "$(st "$SID" .attempts)" = 0 ]
  [ "$(st "$SID" .terminal)" = upgraded ]
  [ ! -e "$ST/$SID.open" ] || { echo "a final record kept its .open sentinel"; false; }
  ev="$(run_of "$SID")/events.jsonl"
  stages="$(jq -r 'select(.state == "lru-step") | .stage' "$ev" | tr '\n' ' ')"
  # The fast path (resumed + proven straight out of handoff-fire) goes fire -> confirm: no prove step.
  [ "$stages" = "claim census precheck capacity fire confirm " ] || { echo "stages: $stages"; cat "$ev"; false; }
  [ "$(jq -r 'select(.state == "lru-step") | .detail' "$ev" | grep -cE '^outcome=ok dur_s=[0-9]+ attempt=1 sid=51515151 pane=501 ')" -eq 6 ] \
    || { cat "$ev"; false; }
  [ "$(grep -c "^hf --recycle $SID 501 engage=0 " "$T/hf.log")" -eq 1 ] || { cat "$T/hf.log"; false; }
  no_raw_typing
}

@test "S1 lru_submit_state skips lru-step rows: a FAILED:submit before the last ledger row is still the state" {
  SID=51515151-0000-4000-8000-000000000002
  old_sess 502 "$SID"
  hf_resumes "$SID"; echo FAILED:submit > "$T/hf-$SID.state"      # no $T/engaged: no fresh turn
  LRU_CONFIRM_TURN=on run /bin/bash "$LRU" --drive "$SID" 502
  ev="$(run_of "$SID")/events.jsonl"
  # the file's order: lru-step rows, then lr-fire-resume's FAILED:submit, then more lru-step rows
  fl="$(grep -n '^{"state":"FAILED:submit"}$' "$ev" | cut -d: -f1)"
  ll="$(grep -n '"lru-step"' "$ev" | tail -1 | cut -d: -f1)"
  [ -n "$fl" ] || { cat "$ev"; false; }
  [ "$ll" -gt "$fl" ] || { cat "$ev"; false; }
  [ "$(jq -r .verdict "$(result "$SID")")" = upgraded ] || { cat "$(result "$SID")"; false; }
  [[ "$(jq -r .reason "$(result "$SID")")" == *"UNCONFIRMED (lr-fire-resume: FAILED:submit)"* ]] || { cat "$(result "$SID")"; false; }
  no_raw_typing
}

# ── S12 SERIAL: ONE FAILS, THE NEXT PROCEEDS ─────────────────────────────────────────────────────

@test "S12 serial drain: A holds on exit-readback (retry-wait 1/3), B upgrades, --status shows both, drain exits 0" {
  A=52525252-0000-4000-8000-00000000000a; B=52525252-0000-4000-8000-00000000000b
  old_sess 521 "$A"; old_sess 522 "$B"
  hf_holds "$A" exit-readback 1
  hf_resumes "$B"; : > "$T/engaged"
  queue a.json "$A" 521; touch -t 202601010000 "$LRU_STATE/upgrade-queue/a.json"
  queue b.json "$B" 522; touch -t 202601010001 "$LRU_STATE/upgrade-queue/b.json"
  LR_UPGRADE_AUTO=off run /bin/bash "$LRU" --drain
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  # serial: A was fired first, B second
  [ "$(awk '{ print $3 }' "$T/hf.log" | tr '\n' ' ')" = "$A $B " ] || { cat "$T/hf.log"; false; }
  [ "$(jq -r .verdict "$(result "$A")")" = skipped ] || { cat "$(result "$A")"; false; }
  [[ "$(jq -r .reason "$(result "$A")")" == *"(held: exit-readback)"*"session untouched"* ]] || { cat "$(result "$A")"; false; }
  [ "$(st "$A" .disposition)" = retry-wait ] || { cat "$(recf "$A")"; false; }
  [ "$(st "$A" .attempts)" = 1 ] || { cat "$(recf "$A")"; false; }
  [ "$(st "$A" .readbacks)" = 1 ] || { cat "$(recf "$A")"; false; }
  [ "$(st "$A" .next_eligible)" = "$((NOW + 600))" ] || { cat "$(recf "$A")"; false; }
  [ "$(jq -r .verdict "$(result "$B")")" = upgraded ] || { cat "$(result "$B")"; false; }
  [ "$(st "$B" .disposition)" = upgraded ]
  run /bin/bash "$LRU" --status
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | awk '$1 == "521" && $2 == "52525252" && $5 == "retry-wait" && $8 == "1/3" { f = 1 } END { exit !f }' \
    || { echo "$output"; false; }
  printf '%s\n' "$output" | awk '$1 == "522" && $5 == "upgraded" && $8 == "0/3" { f = 1 } END { exit !f }' || { echo "$output"; false; }
  [ ! -s "$T/tui-rpc.log" ] || { echo "a composer that is not our /exit got a keystroke"; cat "$T/tui-rpc.log"; false; }
  no_raw_typing
}

# ── S14 CLASSES: A WAIT IS NOT CHARGED, AN UNKNOWN HOLD IS ──────────────────────────────────────

@test "S14 handoff-fire holding on busy is a wait: disposition waiting, attempts unchanged" {
  SID=54545454-0000-4000-8000-000000000001
  old_sess 541 "$SID"
  rec "$SID" '{pane: "541", disposition: "retry-wait", step: "done", attempts: 1, readbacks: 0, next_eligible: 0, terminal: null,
              target: {bin: env.NEW, binlabel: ".claude-280", model: "claude-opus-5-5"}}'
  hf_holds "$SID" busy
  run /bin/bash "$LRU" --drive "$SID" 541
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  [[ "$(jq -r .reason "$(result "$SID")")" == *"(held: busy)"* ]] || { cat "$(result "$SID")"; false; }
  [ "$(st "$SID" .disposition)" = waiting ] || { cat "$(recf "$SID")"; false; }
  [ "$(st "$SID" .attempts)" = 1 ] || { cat "$(recf "$SID")"; false; }
  [ "$(st "$SID" .last_class)" = wait ]
  [ "$(st "$SID" .next_eligible)" = 0 ]
  no_raw_typing
}

@test "S14 an UNKNOWN hold reason is a fault: retry-wait, attempts 1, backoff 600 s" {
  SID=54545454-0000-4000-8000-000000000002
  old_sess 542 "$SID"
  hf_holds "$SID" frobnicated
  run /bin/bash "$LRU" --drive "$SID" 542
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  [ "$(st "$SID" .disposition)" = retry-wait ] || { cat "$(recf "$SID")"; false; }
  [ "$(st "$SID" .attempts)" = 1 ] || { cat "$(recf "$SID")"; false; }
  [ "$(st "$SID" .readbacks)" = 0 ] || { cat "$(recf "$SID")"; false; }
  [ "$(st "$SID" .last_class)" = fault ]
  [ "$(st "$SID" .next_eligible)" = "$((NOW + 600))" ]
  [ "$(st "$SID" .terminal)" = null ]
  no_raw_typing
}

# ── S15 ORDERING: EVERY READ THAT CAN REFUSE RUNS BEFORE THE MINT ────────────────────────────────

@test "S15 an UNKNOWN relaunch surface (rc 3) refuses before capacity: no probe, no token file" {
  SID=55555555-0000-4000-8000-000000000001
  old_sess 551 "$SID"
  echo 3 > "$T/surface-rc"
  run /bin/bash "$LRU" --drive "$SID" 551
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  [[ "$(jq -r .reason "$(result "$SID")")" == "relaunch-surface-unverified: relaunch surface unknown"* ]] || { cat "$(result "$SID")"; false; }
  [ ! -e "$T/probe.log" ] || { echo "capacity was probed before the surface check refused"; cat "$T/probe.log"; false; }
  [ -z "$(ls -A "$T/tokens" 2>/dev/null)" ] || { echo "a token was minted"; ls "$T/tokens"; false; }
  [ ! -s "$T/hf.log" ]
  no_raw_typing
}

@test "S15 a composer occupied AFTER the census refuses before capacity: no probe, no token file" {
  SID=55555555-0000-4000-8000-000000000002
  export LRU_COMPOSER=on
  old_sess 552 "$SID"
  printf '' > "$T/composer-552"                       # the census's read: empty
  printf 'pleasefixthelogin' > "$T/composer-552.after"  # the precheck's read: a draft
  run /bin/bash "$LRU" --drive "$SID" 552
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  [ "$(jq -r .reason "$(result "$SID")")" = "composer-occupied (appeared after the census; nothing typed)" ] || { cat "$(result "$SID")"; false; }
  [ ! -e "$T/probe.log" ] || { cat "$T/probe.log"; false; }
  [ -z "$(ls -A "$T/tokens" 2>/dev/null)" ] || { ls "$T/tokens"; false; }
  [ "$(st "$SID" .disposition)" = waiting ] || { cat "$(recf "$SID")"; false; }
  no_raw_typing
}

LEAD_SID=abcd1234-0000-4000-8000-000000000001
MATE_SID=abcd1234-0000-4000-8000-000000000002
@test "S15 a team-hold refusal AFTER the mint (lead) gives the token back: the token file is removed" {
  td="$CFG/teams/session-abcd1234"; mkdir -p "$td/inboxes"
  printf '{"name":"session-abcd1234","leadSessionId":"%s","members":[{"agentId":"team-lead@session-abcd1234","name":"team-lead"},{"agentId":"m@session-abcd1234","name":"m","tmuxPaneId":"702","backendType":"iterm2"}]}\n' "$LEAD_SID" > "$td/config.json"
  printf '[]\n' > "$td/inboxes/m.json"
  # a previous hold that was never restored: lru_team_hold refuses to stack a second one
  mkdir -p "$CFG/teams/.session-abcd1234.lr-upgrade-hold"
  old_sess 701 "$LEAD_SID"
  sess 702 "$MATE_SID" "$NEW --agent-id m@session-abcd1234 --agent-name m --team-name session-abcd1234 --agent-color cyan --parent-session-id $LEAD_SID --agent-type general-purpose --permission-mode auto --effort high --model claude-opus-5-5"
  run /bin/bash "$LRU" --drive "$LEAD_SID" 701
  [ "$status" -eq 3 ] || { echo "$output"; cat "$(result "$LEAD_SID")"; false; }
  [[ "$(jq -r .reason "$(result "$LEAD_SID")")" == "team session-abcd1234 could not be held aside"* ]] || { cat "$(result "$LEAD_SID")"; false; }
  grep -q '^probe ' "$T/probe.log" || { echo "the lead never reached capacity"; false; }
  [ "$(st "$LEAD_SID" .token)" = "$T/tokens/tok-$LEAD_SID" ] || { echo "no token was minted"; cat "$(recf "$LEAD_SID")"; false; }
  [ ! -e "$T/tokens/tok-$LEAD_SID" ] || { echo "the minted token leaked past the hold refusal"; false; }
  [ ! -s "$T/hf.log" ] || { cat "$T/hf.log"; false; }
  [ "$(jq -r 'select(.state == "lru-step") | .stage' "$(run_of "$LEAD_SID")/events.jsonl" | tail -1)" = hold ]
  no_raw_typing
}

# ── S16 THE RAIL RECEIPT ─────────────────────────────────────────────────────────────────────────

JUNK='In-placeupgrade:thissessionwasrelaunchedbycc-lrupgradeonthecurrent'
@test "S16 the receipt is filed only immediately before handoff-fire, and removed after a refusal before /exit" {
  SID=56565656-0000-4000-8000-000000000001
  export LRU_COMPOSER=on
  old_sess 561 "$SID"
  printf '%s' "$JUNK" > "$T/composer-561"
  run /bin/bash "$LRU" --drive "$SID" 561
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  grep -q '^probe .*receipts=$' "$T/probe.log" || { echo "a receipt existed at capacity time"; cat "$T/probe.log"; false; }
  [ "$(awk -F'\t' '$1 == "561" { print $2 }' "$T/receipts-at-hf.log" 2>/dev/null)" = "$JUNK" ] \
    || { echo "no receipt at handoff-fire time"; cat "$T/receipts-at-hf.log" 2>/dev/null; false; }
  [ ! -e "$CC_COMPOSER_RESIDUE_DIR/561" ] || { echo "the refused recycle left its receipt"; false; }
  [[ "$(jq -r .reason "$(result "$SID")")" == "handoff-fire refused before /exit"* ]] || { cat "$(result "$SID")"; false; }
  no_raw_typing
}

@test "S16 a receipt rewritten by someone else before the refusal is KEPT" {
  SID=56565656-0000-4000-8000-000000000002
  export LRU_COMPOSER=on
  old_sess 562 "$SID"
  printf '%s' "$JUNK" > "$T/composer-562"
  printf 'printf "%%s\\t%%s\\n" 2026-10-08T00:00:00Z someone-elses-stray > "$CC_COMPOSER_RESIDUE_DIR/562"\n' > "$T/hf-$SID.sh"
  run /bin/bash "$LRU" --drive "$SID" 562
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  [ -f "$CC_COMPOSER_RESIDUE_DIR/562" ] || { echo "a receipt someone else rewrote was removed"; false; }
  [ "$(cut -f2- "$CC_COMPOSER_RESIDUE_DIR/562")" = someone-elses-stray ] || { cat "$CC_COMPOSER_RESIDUE_DIR/562"; false; }
  no_raw_typing
}

# ── S17 PROMPT-FREE PROOF ────────────────────────────────────────────────────────────────────────

canary() { mkdir -p "$LRU_STATE/upgrade-canary"; echo "$NOW 00000000" > "$LRU_STATE/upgrade-canary/.claude-280__claude-opus-5-5__claude-t"; }

@test "S17 canary present: launcher --prompt '', HF_ENGAGE_BY_PROCESS=1; READY + pane-bound cc-find -> upgraded 'TUI READY'" {
  SID=57575757-0000-4000-8000-000000000001
  canary
  old_sess 571 "$SID"
  hf_resumes "$SID"; echo READY > "$T/hf-$SID.state"
  printf '%s\t571\tclaude-t\t%s\t%s\tLIVE\n' "$SID" "$CFG" "$T" > "$T/ccfind-$SID"
  run /bin/bash "$LRU" --drive "$SID" 571
  [ "$status" -eq 0 ] || { echo "$output"; cat "$(result "$SID")"; false; }
  L="$(run_of "$SID")/launch.sh"
  grep -q -- "--prompt ''" "$L" || { cat "$L"; false; }
  grep -qx "export LR_SUBMIT_TOKEN=''" "$L" || { cat "$L"; false; }
  grep -q "^hf --recycle $SID 571 engage=1 " "$T/hf.log" || { cat "$T/hf.log"; false; }
  [ "$(st "$SID" .launch_role)" = quiet ]
  r="$(jq -r .reason "$(result "$SID")")"
  [ "$(jq -r .verdict "$(result "$SID")")" = upgraded ] || { cat "$(result "$SID")"; false; }
  [[ "$r" == *"pane 571 bound, TUI READY; no prompt"* ]] || { echo "$r"; false; }
  [ ! -e "$T/engaged.log" ] || { echo "a prompt-free relaunch waited for a fresh turn"; false; }
  no_raw_typing
}

@test "S17 canary present, READY-NOT-SEEN: upgraded with 'TUI readiness UNPROVEN', nothing typed, the pane in the drain mail" {
  SID=57575757-0000-4000-8000-000000000002
  canary
  old_sess 572 "$SID"
  hf_resumes "$SID"; echo READY-NOT-SEEN > "$T/hf-$SID.state"
  printf '%s\t572\tclaude-t\t%s\t%s\tLIVE\n' "$SID" "$CFG" "$T" > "$T/ccfind-$SID"
  queue q.json "$SID" 572
  LR_UPGRADE_AUTO=off run /bin/bash "$LRU" --drain
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(jq -r .verdict "$(result "$SID")")" = upgraded ] || { cat "$(result "$SID")"; false; }
  [[ "$(jq -r .reason "$(result "$SID")")" == *"TUI readiness UNPROVEN (lr-fire-resume: READY-NOT-SEEN)"* ]] || { cat "$(result "$SID")"; false; }
  grep -q 'CC-LR-UPGRADE drain: pane 572 57575757: upgraded, but its TUI readiness is UNPROVEN' "$T/notify.log" \
    || { cat "$T/notify.log"; false; }
  [ ! -s "$T/tui-rpc.log" ] || { cat "$T/tui-rpc.log"; false; }
  no_raw_typing
}

@test "S17 no canary file: the launcher carries the prompt, and a fresh turn writes the canary file" {
  SID=57575757-0000-4000-8000-000000000003
  old_sess 573 "$SID"
  hf_resumes "$SID"; : > "$T/engaged"
  run /bin/bash "$LRU" --drive "$SID" 573
  [ "$status" -eq 0 ] || { echo "$output"; cat "$(result "$SID")"; false; }
  L="$(run_of "$SID")/launch.sh"
  ! grep -q -- "--prompt ''" "$L" || { cat "$L"; false; }
  grep -q -- '--prompt In-place\\ upgrade:' "$L" || { cat "$L"; false; }
  grep -q "^hf --recycle $SID 573 engage=0 " "$T/hf.log" || { cat "$T/hf.log"; false; }
  [[ "$(jq -r .reason "$(result "$SID")")" == *"(the canary for this binary, model and account)"* ]] || { cat "$(result "$SID")"; false; }
  c="$LRU_STATE/upgrade-canary/.claude-280__claude-opus-5-5__claude-t"
  [ "$(cat "$c" 2>/dev/null)" = "$NOW $SID" ] || { ls -la "$LRU_STATE/upgrade-canary" 2>&1; false; }
  no_raw_typing
}

# ── S19 --status ─────────────────────────────────────────────────────────────────────────────────

status_fixture() {
  rec 61616161-0000-4000-8000-000000000006 '{pane: "6", disposition: "in-flight", step: "fire", step_since: ($now - 72), attempts: 0,
       from: {bin: ".claude-260"}, target: {binlabel: ".claude-280", model: "claude-opus-5-5"},
       owner: {pid: 4242, lstart: $lst, kind: "drainer"}, hf: {pid: 0, lstart: ""}}'
  rec 61616161-0000-4000-8000-000000000037 '{pane: "37", disposition: "exit-pending", step: "exit-wait", step_since: ($now - 3720), attempts: 1,
       from: {bin: ".claude-260"}, target: {binlabel: ".claude-280", model: "claude-opus-5-5"},
       last_reason: "/exit sent; old claude pid 16694 still alive"}'
  rec 61616161-0000-4000-8000-000000000033 '{pane: "33", disposition: "retry-wait", step: "done", step_since: ($now - 483), attempts: 2,
       next_eligible: ($now + 717), from: {bin: ".claude-260"}, target: {binlabel: ".claude-280", model: "claude-opus-5-5"},
       last_reason: "exit-readback"}'
  rec 61616161-0000-4000-8000-000000000012 '{pane: "12", disposition: "terminal", terminal: "exhausted", terminal_ts: $now, step: "done",
       step_since: ($now - 60), attempts: 3, from: {bin: ".claude-260"}, target: {binlabel: ".claude-280", model: "claude-opus-5-5"},
       last_reason: "relaunch-surface-unverified"}'
  { printf '# ts=%s dur_s=13 load1=41.2\n' "$((NOW - 190))"
    printf '1\taaaa\t/opt/cc/.claude-280/node_modules/.bin/claude\tclaude-opus-5-5\tclaude-opus-5-5\thigh\tauto\t%s\t/x\t1\tcurrent\n' "$CFG"
    printf '2\tbbbb\t/opt/cc/.claude-280/node_modules/.bin/claude\tclaude-opus-5-5\tclaude-opus-5-5\thigh\tauto\t%s\t/x\t2\tcurrent\n' "$CFG"
    printf '3\tcccc\t/opt/cc/.claude-260/node_modules/.bin/claude\tclaude-opus-5\tclaude-opus-5-5\thigh\tauto\t%s\t/x\t3\tupgrade\n' "$CFG"
  } > "$ST/.census.tsv"
}

@test "S19 --status: ORPHANED@step, exit-pending, retry-wait, TERMINAL rows, census age and the fleet line; no census run" {
  status_fixture
  run /bin/bash "$LRU" --status
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -q '^lr-upgrade  .* · drainer idle$' || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -qx 'census 3m10s ago (13 s, load1 41.2)' || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -qE '^PANE +SID8 +FROM +TO +DISPOSITION +STEP +IN-STEP +ATT +LAST REASON$' || { echo "$output"; false; }
  rows="$(printf '%s\n' "$output" | awk '$2 ~ /^61616161$/')"
  # in-flight first, exit-pending next, then by pane
  [ "$(printf '%s\n' "$rows" | awk '{ print $1 }' | tr '\n' ' ')" = "6 37 12 33 " ] || { echo "$output"; false; }
  printf '%s\n' "$rows" | awk '$1 == "6" && $3 == ".claude-260" && $4 == ".claude-280" && $5 == "ORPHANED@fire" && $6 == "fire" && $7 == "1m12s" && $8 == "0/3" { f = 1 } END { exit !f }' \
    || { echo "$output"; false; }
  printf '%s\n' "$rows" | awk '$1 == "37" && $5 == "exit-pending" && $6 == "exit-wait" && $7 == "1h02m" && $8 == "1/3" { f = 1 } END { exit !f }' || { echo "$output"; false; }
  printf '%s\n' "$rows" | grep -qE '^33 .* retry-wait +done +8m03s +2/3 +exit-readback \(next try in 11m57s\)$' || { echo "$output"; false; }
  printf '%s\n' "$rows" | grep -qE '^12 .* TERMINAL +done +1m00s +3/3 +exhausted: relaunch-surface-unverified \(expires in 6h00m\)$' || { echo "$output"; false; }
  printf '%s\n' "$output" | grep -qx 'fleet (cached census): .claude-260 1 · .claude-280 2 — exit-pending 1 · in-flight 1 · retry-wait 1 · terminal 1' \
    || { echo "$output"; false; }
  [ ! -e "$T/claude-bin.log" ] || { echo "--status ran a census"; cat "$T/claude-bin.log"; false; }
  # read-only: the orphan is reported, not settled
  [ "$(st 61616161-0000-4000-8000-000000000006 .disposition)" = in-flight ]
  [ -e "$ST/61616161-0000-4000-8000-000000000006.open" ]
}

@test "S19 --status --json parses, with sessions and fleet keys" {
  status_fixture
  run /bin/bash "$LRU" --status --json
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s' "$output" | jq -e 'has("sessions") and has("fleet")' >/dev/null || { echo "$output"; false; }
  printf '%s' "$output" | jq -e '(.sessions | length) == 4' >/dev/null || { echo "$output"; false; }
  printf '%s' "$output" | jq -e '.fleet.by_binary[".claude-280"] == 2 and .fleet.by_binary[".claude-260"] == 1' >/dev/null || { echo "$output"; false; }
  printf '%s' "$output" | jq -e '.fleet.by_disposition["in-flight"] == 1 and .fleet.by_disposition.terminal == 1' >/dev/null || { echo "$output"; false; }
  printf '%s' "$output" | jq -e --arg ts "$((NOW - 190))" '.census.ts == $ts and .census.dur_s == "13" and .drainer == null' >/dev/null || { echo "$output"; false; }
  [ ! -e "$T/claude-bin.log" ] || { cat "$T/claude-bin.log"; false; }
}

# ── S20 SELF-BOUND ───────────────────────────────────────────────────────────────────────────────

@test "S20 LRU_DRAIN_MAX_S=0: --drain drives nothing, leaves the queue, says 'budget spent'" {
  SID=60606060-0000-4000-8000-000000000001
  old_sess 600 "$SID"
  queue q.json "$SID" 600
  LRU_DRAIN_MAX_S=0 run /bin/bash "$LRU" --drain
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"budget spent (0 s); 1 request(s) left queued for the next drain"* ]] || { echo "$output"; false; }
  [ -f "$LRU_STATE/upgrade-queue/q.json" ] || { echo "the queue was consumed"; false; }
  [ ! -e "$(result "$SID")" ] || { echo "something was driven"; false; }
  [ ! -e "$(recf "$SID")" ] || { echo "something was driven"; false; }
  [ ! -s "$T/hf.log" ] || { echo "something was driven"; false; }
  [ "$(census_count)" -eq 0 ] || { cat "$T/claude-bin.log"; false; }
  [ ! -e "$LRU_STATE/upgrade-drain.lock" ]
  no_raw_typing
}

# ── S21 REFILL ───────────────────────────────────────────────────────────────────────────────────

S21_E1=62626262-0000-4000-8000-0000000000e1   # no record
S21_E2=62626262-0000-4000-8000-0000000000e2   # waiting (uncharged), eligible now
S21_TM=62626262-0000-4000-8000-0000000000a1   # terminal exhausted, not expired
S21_XP=62626262-0000-4000-8000-0000000000a2   # exit-pending, old claude alive
S21_IF=62626262-0000-4000-8000-0000000000a3   # in-flight under a live owner
S21_BO=62626262-0000-4000-8000-0000000000a4   # retry-wait, backing off
refill_fixture() {
  local tgt='target: {bin: env.NEW, binlabel: ".claude-280", model: "claude-opus-5-5"}'
  sess 621 "$S21_E1" "$OLD --permission-mode auto --model claude-opus-5 --effort high"
  sess 622 "$S21_E2" "$OLD --permission-mode auto --model claude-opus-5 --effort high"
  rec "$S21_E2" "{pane: \"622\", disposition: \"waiting\", step: \"done\", attempts: 0, next_eligible: 0, terminal: null, $tgt}"
  sess 623 "$S21_TM" "$OLD --permission-mode auto --model claude-opus-5 --effort high"
  rec "$S21_TM" "{pane: \"623\", disposition: \"terminal\", terminal: \"exhausted\", terminal_ts: \$now, step: \"done\", attempts: 3, $tgt}"
  sess 624 "$S21_XP" "$OLD --permission-mode auto --model claude-opus-5 --effort high"
  mkdir -p "$T/run-xp"; echo '→ resume-debt open: rc 0' > "$T/run-xp/handoff-fire.log"
  rec "$S21_XP" "{pane: \"624\", disposition: \"exit-pending\", step: \"exit-wait\", step_since: \$now, attempts: 0, run: \"$T/run-xp\",
                  old: {pid: $SPID, lstart: \$lst}, exit_sent: 1, $tgt}"
  sess 625 "$S21_IF" "$OLD --permission-mode auto --model claude-opus-5 --effort high"
  printf '70001 1 %s /bin/bash lr-upgrade.sh --drive\n' "$LST" >> "$LRU_PS_SNAPSHOT"
  rec "$S21_IF" "{pane: \"625\", disposition: \"in-flight\", step: \"fire\", step_since: \$now, attempts: 0,
                  owner: {pid: 70001, lstart: \$lst, kind: \"drainer\"}, $tgt}"
  sess 626 "$S21_BO" "$OLD --permission-mode auto --model claude-opus-5 --effort high"
  rec "$S21_BO" "{pane: \"626\", disposition: \"retry-wait\", step: \"done\", attempts: 1, next_eligible: (\$now + 600), terminal: null, $tgt}"
}

@test "S21 refill: an empty queue with auto on runs a fleet census and queues ONLY eligible rows, each sid driven once" {
  refill_fixture
  echo 9 > "$T/probe-rc"            # every queued drive stops at capacity (a wait): nothing is typed
  # --auto-enqueue shares the eligibility rule and has no settle pass: it isolates the rule itself
  run /bin/bash "$LRU" --auto-enqueue
  [ "$(cd "$LRU_STATE/upgrade-queue" && printf "%s\n" * | sort | tr '\n' ' ')" = "auto-upgrade-$S21_E1.json auto-upgrade-$S21_E2.json " ] \
    || { echo "$output"; ls "$LRU_STATE/upgrade-queue"; false; }
  rm -f "$LRU_STATE/upgrade-queue"/*.json "$T/claude-bin.log"
  run /bin/bash "$LRU" --drain
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(cd "$LRU_STATE/claimed" && printf "%s\n" * | sort | tr '\n' ' ')" = "auto-upgrade-$S21_E1.json auto-upgrade-$S21_E2.json " ] \
    || { echo "$output"; ls "$LRU_STATE/claimed"; false; }
  [ "$(grep -c 'in-place upgrade of 62626262' "$T/probe.log")" -eq 2 ] || { cat "$T/probe.log"; false; }
  [ "$(jq -r .reason "$(result "$S21_E1")")" = "capacity: load 9.9/core over 1.5 (nothing typed; re-run later)" ] || { cat "$(result "$S21_E1")"; false; }
  [ -f "$(result "$S21_E2")" ]
  for s in "$S21_TM" "$S21_IF" "$S21_BO" "$S21_XP"; do
    [ ! -e "$(result "$s")" ] || { echo "ineligible ${s:0:8} was driven or settled to a verdict"; cat "$(result "$s")"; false; }
  done
  # one fleet census per refill: the first queued two; the second found nothing new and ended the drain
  [ "$(census_count)" -eq 2 ] || { cat "$T/claude-bin.log"; false; }
  head -1 "$ST/.census.tsv" | grep -qE '^# ts=[0-9]+ dur_s=[0-9]+ load1=[0-9.]* rc=0$' || { head -1 "$ST/.census.tsv"; false; }
  [[ "$output" == *"refill: 2 session(s) queued"* && "$output" == *"refill: 0 session(s) queued"* ]] || { echo "$output"; false; }
  [ "$(st "$S21_IF" .disposition)" = in-flight ] && [ "$(st "$S21_XP" .disposition)" = exit-pending ] && [ "$(st "$S21_TM" .terminal)" = exhausted ] || false
  [ ! -s "$T/hf.log" ]
  no_raw_typing
}

@test "S21 with upgrade-auto.off the drain runs NO census and queues nothing" {
  refill_fixture
  touch "$LRU_STATE/upgrade-auto.off"
  run /bin/bash "$LRU" --drain
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(census_count)" -eq 0 ] || { cat "$T/claude-bin.log"; false; }
  [ ! -e "$ST/.census.tsv" ]
  [ -z "$(ls -A "$LRU_STATE/upgrade-queue" 2>/dev/null)" ] || { ls -R "$LRU_STATE"; false; }
  [ -z "$(ls -A "$LRU_STATE/claimed" 2>/dev/null)" ] || { ls -R "$LRU_STATE"; false; }
  [[ "$output" == *"drain done: 0 session(s)"* ]] || { echo "$output"; false; }
  no_raw_typing
}

# ── S22 --reset ──────────────────────────────────────────────────────────────────────────────────

@test "S22 --reset refuses while upgrade-drain.lock exists and changes nothing" {
  S=63636363-0000-4000-8000-000000000001
  rec "$S" '{pane: "631", disposition: "terminal", terminal: "exit-readback", terminal_ts: $now, attempts: 3, readbacks: 3}'
  before="$(cat "$(recf "$S")")"
  # A LIVE holder (a real pid) refuses; a dead holder's lock is stolen, as lru_drain does.
  sleep 300 & LIVE_PID=$!
  mkdir -p "$LRU_STATE/upgrade-drain.lock"; echo "$LIVE_PID" > "$LRU_STATE/upgrade-drain.lock/pid"
  run /bin/bash "$LRU" --reset all
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [[ "$output" == *"REFUSED: a drainer holds"*"(pid $LIVE_PID) - nothing reset"* ]] || { echo "$output"; false; }
  [ "$(cat "$(recf "$S")")" = "$before" ] || { cat "$(recf "$S")"; false; }
  [ -d "$LRU_STATE/upgrade-drain.lock" ] && [ "$(cat "$LRU_STATE/upgrade-drain.lock/pid")" = "$LIVE_PID" ] || false
  kill "$LIVE_PID" 2>/dev/null || true; wait "$LIVE_PID" 2>/dev/null || true
  run /bin/bash "$LRU" --reset all
  [ "$status" -eq 0 ] || { echo "a dead holder's lock blocked --reset: $output"; false; }
  [ "$(jq -r .attempts "$(recf "$S")")" = 0 ] || { cat "$(recf "$S")"; false; }
}

@test "S22 --reset refuses an in-flight record and clears a terminal to retry-wait with attempts 0" {
  F=63636363-0000-4000-8000-000000000002; TM=63636363-0000-4000-8000-000000000003
  rec "$F" '{pane: "632", disposition: "in-flight", step: "fire", attempts: 1, owner: {pid: 4242, lstart: $lst}}'
  rec "$TM" '{pane: "633", disposition: "terminal", terminal: "exit-readback", terminal_ts: ($now - 10), attempts: 3, readbacks: 3, interrupted: 1}'
  fbefore="$(cat "$(recf "$F")")"
  run /bin/bash "$LRU" --reset all
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"REFUSED: 63636363 is in-flight - settle owns it"* ]] || { echo "$output"; false; }
  [[ "$output" == *"reset 1 record(s)"* ]] || { echo "$output"; false; }
  [ "$(cat "$(recf "$F")")" = "$fbefore" ] || { cat "$(recf "$F")"; false; }
  [ -e "$ST/$F.open" ] || { cat "$(recf "$F")"; false; }
  [ "$(st "$TM" .disposition)" = retry-wait ] || { cat "$(recf "$TM")"; false; }
  [ "$(st "$TM" .attempts)" = 0 ] || { cat "$(recf "$TM")"; false; }
  [ "$(st "$TM" .readbacks)" = 0 ] || { cat "$(recf "$TM")"; false; }
  [ "$(st "$TM" .interrupted)" = 0 ] || { cat "$(recf "$TM")"; false; }
  [ "$(st "$TM" .terminal)" = null ]
  [ "$(st "$TM" .next_eligible)" = "$NOW" ]
  [ ! -e "$LRU_STATE/upgrade-drain.lock" ] || { echo "--reset left the drain lock behind"; false; }
}
