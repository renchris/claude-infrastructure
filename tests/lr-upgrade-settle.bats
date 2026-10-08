#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2016  # stubs are written verbatim; each @test is its own subshell; per-test exports are the intent
# lr-upgrade × CRASH SETTLE and BOUNDED RETRY (the STATE RECORD block of 2026-10-08).
# Subject: scripts/limit-recover/lr-upgrade.sh — lru_settle_one / lru_settle_all (a drainer killed
# mid-session), lru_relaunch_gated (the only relaunch path: handoff-fire --relaunch-at-shell, else
# cc-resume-debt settle), exit-pending (the pane-37 shape: /exit sent, old claude alive),
# lru_st_verdict (readback / interrupted classes, backoff, terminals), lru_st_eligible through
# refill and --auto-enqueue, --reset, and lru_clear_own_exit (our own /exit left in a composer).
# Every case runs the subject under /bin/bash (launchd's 3.2).
#
# Hermetic: HOME, LRU_STATE, the registry, the config root and every store are fixtures under
# $BATS_TEST_TMPDIR; `ps` is a snapshot FILE (LRU_PS_SNAPSHOT); time is LRU_NOW. handoff-fire,
# it2, cc-notify, cc-resume-debt, cc-find, kill (watcher TERM), capacity-admit, lr-lib and the TUI
# library are stubs that record their calls. No real terminal, pane, kitty socket, registry, mailbox
# or ~/.reso is reached; the it2 recorder must stay EMPTY in every case (nothing types raw).

setup() {
  command -v jq >/dev/null || skip "jq required"
  export CC_FIRE_CAPACITY_GATE=off
  export CC_ADMIT_GATE=off
  unset CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID CC_SESSION_ID
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LRU="$REPO/scripts/limit-recover/lr-upgrade.sh"
  T="$BATS_TEST_TMPDIR"
  export HOME="$T/home"; mkdir -p "$HOME"
  export LRU_STATE="$HOME/.reso/limit-recover"; mkdir -p "$LRU_STATE"
  export LR_STATE_DIR="$LRU_STATE"
  export LRU_REG_DIR="$T/reg"; mkdir -p "$LRU_REG_DIR"
  export LRU_CFG_ROOT="$T/cfgroot"; mkdir -p "$LRU_CFG_ROOT/.claude-t/projects/-x"
  CFG="$LRU_CFG_ROOT/.claude-t"
  export LRU_PS_SNAPSHOT="$T/ps.txt"; : > "$LRU_PS_SNAPSHOT"
  export LRU_KITTY_LS="$T/kitty-ls.json"; echo '[]' > "$LRU_KITTY_LS"
  export CC_COMPOSER_RESIDUE_DIR="$T/residue"; mkdir -p "$CC_COMPOSER_RESIDUE_DIR"
  export LRU_COMPOSER=off
  export LRU_SELF_SID=""
  export LR_UPGRADE_AUTO=off
  export LRU_NOW=1791500000; NOW0=1791500000
  export LRU_DRAIN_MAX_S=3600 LRU_CENSUS_TIMEOUT_S=60
  export LRU_EXIT_LINGER_S=0 LRU_READY_S=0 LRU_RELAUNCH_UP_S=0 LRU_PROVE_HOLD_S=0 LRU_PROVE_GAP_S=0
  export LRU_CLEAR_SETTLE_S=0
  STUBS="$T/stubs"; mkdir -p "$STUBS"
  printf '#!/bin/bash\necho "$*" >> %s\n' "$T/it2.log" > "$STUBS/it2"; chmod +x "$STUBS/it2"
  export LRU_IT2_BIN="$STUBS/it2" LRU_RETYPE_MAX=0 LRU_RETYPE_GAP_S=0 LRU_ENGAGE_S=0 LRU_GAP_S=0
  # cc-notify: a recorder.
  export LRU_NOTIFY_BIN="$STUBS/cc-notify"
  printf '#!/bin/bash\necho "$*" >> %s/notify.log\nexit 0\n' "$T" > "$LRU_NOTIFY_BIN"; chmod +x "$LRU_NOTIFY_BIN"
  # cc-resume-debt: rc of surface/prove/settle read from $T/<verb>-rc (default 0); every call logged.
  export CC_RESUME_DEBT_BIN="$STUBS/cc-resume-debt"
  printf '#!/bin/bash
echo "$*" >> %s/rd.log
case "$1" in surface|prove|settle) exit "$(cat "%s/$1-rc" 2>/dev/null || echo 0)" ;; esac
exit 0
' "$T" "$T" > "$CC_RESUME_DEBT_BIN"; chmod +x "$CC_RESUME_DEBT_BIN"
  # kill: the watcher TERM seam — a recorder that never signals anything.
  export LRU_KILL_BIN="$STUBS/kill"
  printf '#!/bin/bash\necho "$*" >> %s/kill.log\nexit 0\n' "$T" > "$LRU_KILL_BIN"; chmod +x "$LRU_KILL_BIN"
  # cc-find: nothing is bound (only the prompt-free prove leg reads it).
  export LRU_CCFIND_BIN="$STUBS/cc-find"
  printf '#!/bin/bash\necho "$*" >> %s/ccfind.log\nexit 0\n' "$T" > "$LRU_CCFIND_BIN"; chmod +x "$LRU_CCFIND_BIN"
  NEW="/opt/cc/.claude-280/node_modules/.bin/claude"
  OLD="/opt/cc/.claude-260/node_modules/.bin/claude"
  printf '#!/bin/bash\necho %s\n' "$NEW" > "$STUBS/cc-claude-bin"; chmod +x "$STUBS/cc-claude-bin"
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
  # capacity-admit: admits, and mints a token path (the file itself is never created by the stub).
  export LRU_CA_LIB="$T/ca.sh"
  cat > "$LRU_CA_LIB" <<EOF
cc_capacity_probe() { echo "probe \$*" >> "$T/ca.log"; return 0; }
cc_capacity_admit_reason() { echo admitted; }
cc_capacity_token_mint() { echo "$T/tok-\$1"; }
EOF
  # lr-lib: lr_resume_procs reads the SNAPSHOT (argv[0] a claude binary, --model present).
  export LRU_LR_LIB="$T/lr-lib.sh"
  cat > "$LRU_LR_LIB" <<'EOF'
lr_resume_procs() {
  LR_RP_SID="$1" awk 'index($0, "--resume " ENVIRON["LR_RP_SID"]) && index($0, "--model ") { n = split($8, a, "/"); if (a[n] == "claude") print $1 }' "$LRU_PS_SNAPSHOT"
}
lr_engaged_after() { return 1; }
EOF
  # TUI: the composer of pane P is $T/composer-P; $T/composer-unreadable makes it unreadable (rc 1).
  # send-text is logged (control bytes visible through cat -v) and empties the composer.
  export LRU_TUI_LIB="$T/tui.sh"
  cat > "$LRU_TUI_LIB" <<EOF
cc_tui_composer() { [ -f "$T/composer-unreadable" ] && return 1; cat "$T/composer-\$1" 2>/dev/null; return 0; }
cc_tui_rpc() {
  printf 'rpc %s\n' "\$*" | cat -v >> "$T/tui.log"
  case "\$1" in send-text) : > "$T/composer-\${3#id:}" ;; esac
  return 0
}
EOF
  # handoff-fire: --recycle prints $T/hf-recycle.out and exits $T/hf-recycle-rc (default 1); it may
  # leave $T/hf-composer-after in the pane's composer. --relaunch-at-shell prints $T/hf-ras.out and
  # appends $T/hf-ras-append (the relaunched process) to the snapshot.
  export LRU_HF_BIN="$STUBS/hf"
  cat > "$LRU_HF_BIN" <<EOF
#!/bin/bash
echo "hf \$* KITTY=\${CC_TERM_KITTY_TO:-}" >> "$T/hf.log"
P=""; a=("\$@"); for ((i = 0; i < \${#a[@]}; i++)); do [ "\${a[i]}" = --source-pane ] && P="\${a[i+1]}"; done
[ -f "$T/hf-hook.sh" ] && . "$T/hf-hook.sh"
case "\$1" in
  --recycle)
    [ -f "$T/hf-composer-after" ] && cp "$T/hf-composer-after" "$T/composer-\$P"
    cat "$T/hf-recycle.out" 2>/dev/null
    exit "\$(cat "$T/hf-recycle-rc" 2>/dev/null || echo 1)" ;;
  --relaunch-at-shell)
    cat "$T/hf-ras.out" 2>/dev/null
    [ -f "$T/hf-ras-append" ] && cat "$T/hf-ras-append" >> "$LRU_PS_SNAPSHOT"
    exit 0 ;;
esac
exit 1
EOF
  chmod +x "$LRU_HF_BIN"
  N=0
}

teardown() {
  local p
  for p in ${LIVE_PID:-} ${HF_LIVE:-}; do kill "$p" 2>/dev/null || true; done
}

LST="Tue Sep 22 06:47:13 2026"
DEAD1=99991   # pids no snapshot line ever names: a dead drainer, a dead handoff-fire, a gone claude
DEAD2=99992
DEAD3=99993
OPEN_LINE='→ resume-debt open: rc 0'
READBACK_LINE="!! recycle ABORTED before /exit (held: exit-readback): the composer read back '<unreadable>', not '/exit'"

# sess <pane> <sid> <argv> — registry row (with a kitty socket) + ps line + an at-rest transcript
sess() {
  local pane="$1" sid="$2" argv="$3" pid
  N=$((N + 1)); pid="${SESS_PID:-$((50000 + N))}"
  printf '{"paneUUID":"%s","pid":%d,"session_id":"%s","account":"claude-t","cwd":"%s","lstart":"%s","kitty_listen_on":"unix:/tmp/kitty-4242"}\n' \
    "$pane" "$pid" "$sid" "$T" "$LST" > "$LRU_REG_DIR/$pane.json"
  printf '%d 1 %s %s\n' "$pid" "$LST" "$argv" >> "$LRU_PS_SNAPSHOT"
  local tx="$CFG/projects/-x/$sid.jsonl"
  printf '%s\n' '{"type":"user","message":{"content":"hi"}}' \
    '{"type":"assistant","message":{"stop_reason":"end_turn","content":[{"type":"text"}]}}' > "$tx"
}
# rec <sid> <pane> [jq filter] — the record a drainer killed at step fire leaves behind; RUN is its run dir
rec() {
  local sid="$1" pane="$2" f="${3:-.}"
  RUN="$LRU_STATE/upgrade/${sid:0:8}-20261008T000000Z"; mkdir -p "$RUN" "$LRU_STATE/upgrade-state"
  printf '{"window_id":"%s","kitty_pid":"4242"}\n' "$pane" > "$RUN/identity.json"
  jq -n --arg sid "$sid" --arg pane "$pane" --arg run "$RUN" --arg cfg "$CFG" --arg cwd "$T" --arg new "$NEW" \
        --arg lst "$LST" --argjson now "$NOW0" --argjson d1 "$DEAD1" --argjson d2 "$DEAD2" --argjson d3 "$DEAD3" '
    {v: 1, sid: $sid, pane: $pane, role: "plain", account: "claude-t", cfg: $cfg, cwd: $cwd, team: "", team_held: 0,
     effort: "high", perm: "auto", launch_role: "",
     from: {bin: ".claude-260", model: "claude-opus-5"},
     target: {bin: $new, binlabel: ".claude-280", model: "claude-opus-5-5"},
     req: {id: "r-1", by: "op-x", origin: "auto", claimed_file: "", scrub_exact: ""},
     disposition: "in-flight", terminal: null, step: "fire", step_since: ($now - 120),
     attempts: 0, readbacks: 0, interrupted: 0, relaunch_attempts: 0, cap_refusals: 0, next_eligible: 0,
     run: $run, token: "", receipt: "", identity: ($run + "/identity.json"), identity_strong: 1,
     kitty_sock: "unix:/tmp/kitty-4242",
     old: {pid: $d3, lstart: $lst, had_watcher: 0}, hf: {pid: $d2, lstart: $lst},
     exit_sent: 0, last_alive_ts: ($now - 10), paged: 0,
     owner: {pid: $d1, lstart: $lst, kind: "drainer"}, canary: 0, updated: ($now - 120)}
    | '"$f" > "$LRU_STATE/upgrade-state/$sid.json"
  : > "$LRU_STATE/upgrade-state/$sid.open"
}
st() { jq -r "$2" "$LRU_STATE/upgrade-state/$1.json"; }
result() { printf '%s' "$LRU_STATE/results/upgrade-$1.json"; }
cnt() { if [ -f "$2" ]; then grep -c -- "$1" "$2" || true; else echo 0; fi; }
resumed_line() { printf '77001 1 %s %s --permission-mode auto --model claude-opus-5-5 --effort high --resume %s\n' "$LST" "$NEW" "$1"; }
queue_req() { # queue_req <name> <sid> <pane> [requested_by]
  mkdir -p "$LRU_STATE/upgrade-queue"
  jq -n --arg sid "$2" --arg pane "$3" --arg by "${4:-op-x}" --arg req "req-$1" \
    '{kind: "upgrade", sid: $sid, source_pane: $pane, requested_by: $by, req_id: $req}' > "$LRU_STATE/upgrade-queue/$1.json"
}
nothing_typed() {
  [ ! -s "$T/it2.log" ] || { echo "it2 typed:"; cat "$T/it2.log"; false; }
}

# ── S2-S4: a drainer killed AFTER /exit (debt opened, old claude gone) ─────────────────────────────

@test "S2 drain killed between /exit and relaunch: settle relaunches at the shell once, with a fresh launcher, and proves it" {
  SID=52525252-0000-4000-8000-000000000001
  rec "$SID" 702
  printf '%s\n' "$OPEN_LINE" > "$RUN/handoff-fire.log"
  echo "verdict: OK" > "$T/hf-ras.out"
  resumed_line "$SID" > "$T/hf-ras-append"
  [ ! -e "$RUN/launch.sh" ]
  run /bin/bash "$LRU" --drain
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(cnt '--relaunch-at-shell' "$T/hf.log")" = 1 ] || { cat "$T/hf.log"; false; }
  h="$(grep -- '--relaunch-at-shell' "$T/hf.log")"
  [[ "$h" == *"--source-pane 702 --source-session $SID --resume-launcher $RUN/launch.sh"* ]] || { echo "$h"; false; }
  [[ "$h" == *"--expect-identity $RUN/identity.json"* ]] || { echo "$h"; false; }
  [[ "$h" == *"KITTY=unix:/tmp/kitty-4242" ]] || { echo "$h"; false; }
  # freshly minted in the SAME run dir, carrying the new admission token
  grep -q "^export LR_ADMIT_TOKEN=$T/tok-$SID" "$RUN/launch.sh" || { cat "$RUN/launch.sh"; false; }
  grep -q -- '--model claude-opus-5-5 --effort high --permission-mode auto' "$RUN/launch.sh"
  [ "$(cnt '--recycle' "$T/hf.log")" = 0 ]
  [ "$(jq -r .verdict "$(result "$SID")")" = upgraded ] || { cat "$(result "$SID")"; false; }
  [[ "$(jq -r .reason "$(result "$SID")")" == *"after drainer death"* ]] || { cat "$(result "$SID")"; false; }
  [ "$(st "$SID" .terminal)" = upgraded ]
  [ "$(st "$SID" .disposition)" = upgraded ]
  [ ! -e "$LRU_STATE/upgrade-state/$SID.open" ]
  # the closed step is in the run's ledger
  jq -e -s 'map(select(.state == "lru-step" and .stage == "settle:relaunch" and (.detail | startswith("outcome=ok")))) | length == 1' "$RUN/events.jsonl" >/dev/null \
    || { cat "$RUN/events.jsonl"; false; }
  nothing_typed
}

@test "S3a REFUSED at the shell: not retried; cc-resume-debt settle once; rc 1 is terminal stranded with a mail" {
  SID=53535353-0000-4000-8000-000000000001
  rec "$SID" 703
  printf '%s\n' "$OPEN_LINE" > "$RUN/handoff-fire.log"
  echo "verdict: REFUSED:pane:claude" > "$T/hf-ras.out"
  echo 1 > "$T/settle-rc"
  run /bin/bash "$LRU" --drain
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(cnt '--relaunch-at-shell' "$T/hf.log")" = 1 ] || { cat "$T/hf.log"; false; }
  [ "$(cnt "^settle --sid $SID\$" "$T/rd.log")" = 1 ] || { cat "$T/rd.log"; false; }
  [ "$(jq -r .verdict "$(result "$SID")")" = failed ] || { cat "$(result "$SID")"; false; }
  [[ "$(jq -r .reason "$(result "$SID")")" == *"REFUSED:pane:claude"* ]] || false
  [ "$(st "$SID" .disposition)" = terminal ]
  [ "$(st "$SID" .terminal)" = stranded ]
  [ ! -e "$LRU_STATE/upgrade-state/$SID.open" ]
  grep -q "TERMINAL stranded" "$T/notify.log" || { cat "$T/notify.log" 2>/dev/null; false; }
  grep -q "pane 703" "$T/notify.log"
  nothing_typed
}

@test "S3b REFUSED at the shell, cc-resume-debt settle rc 0: upgraded into a NEW window" {
  SID=53535353-0000-4000-8000-000000000002
  rec "$SID" 704
  printf '%s\n' "$OPEN_LINE" > "$RUN/handoff-fire.log"
  echo "verdict: REFUSED:pane:claude" > "$T/hf-ras.out"
  echo 0 > "$T/settle-rc"
  run /bin/bash "$LRU" --drain
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(cnt '--relaunch-at-shell' "$T/hf.log")" = 1 ]
  [ "$(cnt "^settle --sid $SID\$" "$T/rd.log")" = 1 ]
  [ "$(jq -r .verdict "$(result "$SID")")" = upgraded ] || { cat "$(result "$SID")"; false; }
  [[ "$(jq -r .reason "$(result "$SID")")" == *"NEW window"* ]] || { cat "$(result "$SID")"; false; }
  [ "$(st "$SID" .terminal)" = upgraded ]
  nothing_typed
}

@test "S3c a settle verdict carries the record's requester (requested_by), not an empty one" {
  SID=53535353-0000-4000-8000-000000000003
  rec "$SID" 705
  printf '%s\n' "$OPEN_LINE" > "$RUN/handoff-fire.log"
  echo "verdict: REFUSED:pane:claude" > "$T/hf-ras.out"
  echo 1 > "$T/settle-rc"
  run /bin/bash "$LRU" --drain
  [ "$(st "$SID" .req.by)" = op-x ]
  [ "$(jq -r .requested_by "$(result "$SID")")" = op-x ] || { cat "$(result "$SID")"; false; }
  grep -q '^op-x CC-LR-UPGRADE pane 705' "$T/notify.log" || { cat "$T/notify.log" 2>/dev/null; false; }
}

@test "S4a an identity older than LRU_SETTLE_TYPE_MAX_AGE_S is never typed into: straight to cc-resume-debt" {
  SID=54545454-0000-4000-8000-000000000001
  rec "$SID" 706 '.last_alive_ts = ($now - 901)'
  printf '%s\n' "$OPEN_LINE" > "$RUN/handoff-fire.log"
  echo "verdict: OK" > "$T/hf-ras.out"
  LRU_SETTLE_TYPE_MAX_AGE_S=900 run /bin/bash "$LRU" --drain
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(cnt '--relaunch-at-shell' "$T/hf.log")" = 0 ] || { cat "$T/hf.log"; false; }
  [ "$(cnt "^settle --sid $SID\$" "$T/rd.log")" = 1 ] || { cat "$T/rd.log"; false; }
  [[ "$(jq -r .reason "$(result "$SID")")" == *"NEW window"*"901 s old"* ]] || { cat "$(result "$SID")"; false; }
  nothing_typed
}

@test "S4b identity_strong=0 is never typed into: straight to cc-resume-debt" {
  SID=54545454-0000-4000-8000-000000000002
  rec "$SID" 707 '.identity_strong = 0'
  printf '%s\n' "$OPEN_LINE" > "$RUN/handoff-fire.log"
  echo "verdict: OK" > "$T/hf-ras.out"
  run /bin/bash "$LRU" --drain
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(cnt '--relaunch-at-shell' "$T/hf.log")" = 0 ] || { cat "$T/hf.log"; false; }
  [ "$(cnt "^settle --sid $SID\$" "$T/rd.log")" = 1 ] || { cat "$T/rd.log"; false; }
  [[ "$(jq -r .reason "$(result "$SID")")" == *"identity was never read"* ]] || { cat "$(result "$SID")"; false; }
  nothing_typed
}

# ── S5-S7: a drainer killed BEFORE the commit point ──────────────────────────────────────────────

@test "S5 pre-commit crash: the orphan watcher is TERMed, our token and receipt removed, retry-wait interrupted=1" {
  SID=55555555-0000-4000-8000-000000000001
  sleep 300 & LIVE_PID=$!
  printf '%d 1 %s %s --permission-mode auto --model claude-opus-5 --effort high\n' "$LIVE_PID" "$LST" "$OLD" >> "$LRU_PS_SNAPSHOT"
  OLS="$(awk -v p="$LIVE_PID" '$1 == p { print $3" "$4" "$5" "$6" "$7 }' "$LRU_PS_SNAPSHOT")"
  WPID=88801
  {
    printf '%d 1 %s bash /x/handoff-fire.sh __recycle 37 /dev/ttys001 next3 %s /x/launch.sh\n' "$WPID" "$LST" "$SID"
    # another pane's watcher of the same sid, and this pane's watcher of another sid: neither is ours
    printf '88802 1 %s bash /x/handoff-fire.sh __recycle 38 /dev/ttys002 next3 %s /x/launch.sh\n' "$LST" "$SID"
    printf '88803 1 %s bash /x/handoff-fire.sh __recycle 37 /dev/ttys001 next3 deadbeef-0000 /x/launch.sh\n' "$LST"
  } >> "$LRU_PS_SNAPSHOT"
  TOK="$T/tok-crashed"; : > "$TOK"
  printf '1791499000\tOPUS55-UPGRADE(junk)\n' > "$CC_COMPOSER_RESIDUE_DIR/37"
  rec "$SID" 37
  jq --arg p "$LIVE_PID" --arg ls "$OLS" --arg tok "$TOK" \
     '.old = {pid: ($p | tonumber), lstart: $ls, had_watcher: 0} | .token = $tok | .receipt = "OPUS55-UPGRADE(junk)"' \
     "$LRU_STATE/upgrade-state/$SID.json" > "$T/r.json" && mv "$T/r.json" "$LRU_STATE/upgrade-state/$SID.json"
  [ "$(st "$SID" .old.pid)" = "$LIVE_PID" ] || { cat "$LRU_STATE/upgrade-state/$SID.json"; false; }
  printf '→ composer gate: clean\n' > "$RUN/handoff-fire.log"   # no debt-open line
  run /bin/bash "$LRU" --drain
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(cat "$T/kill.log")" = "-TERM $WPID" ] || { cat "$T/kill.log"; false; }
  [ ! -e "$TOK" ] || { echo "token left behind"; false; }
  [ ! -e "$CC_COMPOSER_RESIDUE_DIR/37" ] || { echo "receipt left behind"; false; }
  [ "$(st "$SID" .disposition)" = retry-wait ] || { cat "$LRU_STATE/upgrade-state/$SID.json"; false; }
  [ "$(st "$SID" .interrupted)" = 1 ]
  [ "$(st "$SID" .attempts)" = 1 ]
  [ "$(st "$SID" .next_eligible)" = "$((NOW0 + 600))" ]
  [ ! -e "$LRU_STATE/upgrade-state/$SID.open" ]
  [[ "$(jq -r .reason "$(result "$SID")")" == *"interrupted at step fire before /exit"*"watcher $WPID ended"* ]] || { cat "$(result "$SID")"; false; }
  jq -e -s 'map(select(.state == "lru-step" and .stage == "settle:fire" and (.detail | startswith("outcome=interrupted")))) | length == 1' "$RUN/events.jsonl" >/dev/null \
    || { cat "$RUN/events.jsonl"; false; }
  [ ! -s "$T/hf.log" ]
  nothing_typed
}

@test "S5b a receipt someone rewrote since is kept" {
  SID=55555555-0000-4000-8000-000000000002
  sleep 300 & LIVE_PID=$!
  printf '%d 1 %s %s --model claude-opus-5\n' "$LIVE_PID" "$LST" "$OLD" >> "$LRU_PS_SNAPSHOT"
  printf '1791499000\tsomeone else wrote this\n' > "$CC_COMPOSER_RESIDUE_DIR/38"
  rec "$SID" 38
  jq --arg p "$LIVE_PID" --arg ls "$LST" '.old = {pid: ($p | tonumber), lstart: $ls, had_watcher: 0} | .receipt = "OPUS55-UPGRADE(junk)"' \
     "$LRU_STATE/upgrade-state/$SID.json" > "$T/r.json" && mv "$T/r.json" "$LRU_STATE/upgrade-state/$SID.json"
  run /bin/bash "$LRU" --drain
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -f "$CC_COMPOSER_RESIDUE_DIR/38" ] || { echo "a receipt that is not ours was removed"; false; }
  [ "$(st "$SID" .disposition)" = retry-wait ]
  nothing_typed
}

@test "S6 handoff-fire's foreground still alive: the record stays in flight, owned by hf; nothing typed, no verdict" {
  SID=56565656-0000-4000-8000-000000000001
  sleep 300 & HF_LIVE=$!
  printf '%d 1 %s bash /x/handoff-fire.sh --recycle --same-account --source-pane 708 --source-session %s --await\n' "$HF_LIVE" "$LST" "$SID" >> "$LRU_PS_SNAPSHOT"
  HLS="$(awk -v p="$HF_LIVE" '$1 == p { print $3" "$4" "$5" "$6" "$7 }' "$LRU_PS_SNAPSHOT")"
  rec "$SID" 708
  jq --arg p "$HF_LIVE" --arg l "$HLS" '.hf = {pid: ($p | tonumber), lstart: $l}' \
     "$LRU_STATE/upgrade-state/$SID.json" > "$T/r.json" && mv "$T/r.json" "$LRU_STATE/upgrade-state/$SID.json"
  run /bin/bash "$LRU" --drain
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(st "$SID" .disposition)" = in-flight ]
  [ "$(st "$SID" .owner.kind)" = hf ]
  [ "$(st "$SID" .owner.pid)" = "$HF_LIVE" ]
  [ -e "$LRU_STATE/upgrade-state/$SID.open" ]
  [ ! -e "$(result "$SID")" ] || { cat "$(result "$SID")"; false; }
  [ ! -s "$T/hf.log" ]
  [ ! -s "$T/kill.log" ]
  nothing_typed
}

@test "S7 crash at step capacity: token removed, the manual request requeued (and not re-driven in that drain)" {
  SID=57575757-0000-4000-8000-000000000001
  mkdir -p "$LRU_STATE/claimed"
  TOK="$T/tok-cap"; : > "$TOK"
  jq -n --arg sid "$SID" '{kind: "upgrade", sid: $sid, source_pane: "709", requested_by: "op-x", req_id: "req-m"}' > "$LRU_STATE/claimed/req-m.json"
  rec "$SID" 709 '.step = "capacity"'
  jq --arg tok "$TOK" --arg cf "$LRU_STATE/claimed/req-m.json" '.token = $tok | .req = {id: "req-m", by: "op-x", origin: "manual", claimed_file: $cf, scrub_exact: ""}' \
     "$LRU_STATE/upgrade-state/$SID.json" > "$T/r.json" && mv "$T/r.json" "$LRU_STATE/upgrade-state/$SID.json"
  run /bin/bash "$LRU" --drain
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ ! -e "$TOK" ] || { echo "token left behind"; false; }
  [ -f "$LRU_STATE/upgrade-queue/req-m.json" ] || { ls -R "$LRU_STATE"; false; }
  [ ! -e "$LRU_STATE/claimed/req-m.json" ]
  [[ "$(jq -r .reason "$(result "$SID")")" == "interrupted at step capacity by the drainer's death (nothing typed; settled)" ]] || { cat "$(result "$SID")"; false; }
  [ "$(st "$SID" .disposition)" = retry-wait ]
  [ "$(st "$SID" .interrupted)" = 1 ]
  [ ! -s "$T/hf.log" ] || { echo "the requeued request was driven in the same drain"; cat "$T/hf.log"; false; }
  nothing_typed
}

# ── S9: exit-pending — /exit sent, the old claude still alive (the pane-37 shape) ─────────────────

s9_drive() { # a live drive whose handoff-fire opened the debt, exited 1, and left the old claude alive
  SID=59595959-0000-4000-8000-000000000001
  sleep 300 & LIVE_PID=$!
  SESS_PID="$LIVE_PID" sess 37 "$SID" "$OLD --permission-mode auto --model claude-opus-5 --effort high"
  printf '%s\n' "$OPEN_LINE" > "$T/hf-recycle.out"; echo 1 > "$T/hf-recycle-rc"
  run /bin/bash "$LRU" --drive "$SID" 37
  [ "$status" -eq 3 ] || { echo "$output"; cat "$(result "$SID")" 2>/dev/null; false; }
}

@test "S9a /exit sent and the old claude lingers: exit-pending at exit-wait, nothing typed; the next drain does nothing" {
  s9_drive
  [ "$(st "$SID" .disposition)" = exit-pending ] || { cat "$LRU_STATE/upgrade-state/$SID.json"; false; }
  [ "$(st "$SID" .step)" = exit-wait ]
  [ "$(st "$SID" .exit_sent)" = 1 ]
  [ -e "$LRU_STATE/upgrade-state/$SID.open" ]
  [[ "$(jq -r .reason "$(result "$SID")")" == "/exit sent; old claude pid $LIVE_PID still alive"* ]] || { cat "$(result "$SID")"; false; }
  [ "$(cnt '--recycle' "$T/hf.log")" = 1 ]
  : > "$T/notify.log"
  LRU_NOW=$((NOW0 + 60)) run /bin/bash "$LRU" --drain
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(st "$SID" .disposition)" = exit-pending ]
  [ "$(cnt '--relaunch-at-shell' "$T/hf.log")" = 0 ]
  [ "$(cnt '--recycle' "$T/hf.log")" = 1 ] || { echo "re-driven while exit-pending"; cat "$T/hf.log"; false; }
  [ ! -s "$T/notify.log" ] || { cat "$T/notify.log"; false; }
  nothing_typed
  [ ! -s "$T/tui.log" ]
}

@test "S9b exit-pending pages exactly once past LRU_EXIT_PENDING_PAGE_S, and is terminal exit-unanswered past MAX" {
  s9_drive
  : > "$T/notify.log"
  LRU_NOW=$((NOW0 + 1800)) run /bin/bash "$LRU" --drain
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(cnt 'pane 37' "$T/notify.log")" = 1 ] || { cat "$T/notify.log"; false; }
  grep -q "old claude pid $LIVE_PID still alive - look at the pane" "$T/notify.log"
  [ "$(st "$SID" .paged)" = 1 ]
  LRU_NOW=$((NOW0 + 1900)) run /bin/bash "$LRU" --drain
  [ "$(wc -l < "$T/notify.log" | tr -d ' ')" = 1 ] || { echo "paged twice"; cat "$T/notify.log"; false; }
  [ "$(st "$SID" .disposition)" = exit-pending ]
  LRU_NOW=$((NOW0 + 21600)) run /bin/bash "$LRU" --drain
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(st "$SID" .disposition)" = terminal ] || { cat "$LRU_STATE/upgrade-state/$SID.json"; false; }
  [ "$(st "$SID" .terminal)" = exit-unanswered ]
  [ ! -e "$LRU_STATE/upgrade-state/$SID.open" ]
  [[ "$(jq -r .reason "$(result "$SID")")" == "exit-unanswered: /exit sent 21600 s ago"*"pane 37" ]] || { cat "$(result "$SID")"; false; }
  grep -q "TERMINAL exit-unanswered" "$T/notify.log" || { cat "$T/notify.log"; false; }
  [ "$(cnt '--relaunch-at-shell' "$T/hf.log")" = 0 ]
  nothing_typed
}

@test "S9c exit-pending whose old claude dies within MAX: the gated relaunch is called" {
  s9_drive
  [ "$(st "$SID" .disposition)" = exit-pending ]
  kill "$LIVE_PID" 2>/dev/null || true
  { grep -v "^$LIVE_PID " "$LRU_PS_SNAPSHOT" || true; } > "$T/ps.new"; mv "$T/ps.new" "$LRU_PS_SNAPSHOT"
  echo "verdict: OK" > "$T/hf-ras.out"
  resumed_line "$SID" > "$T/hf-ras-append"
  LRU_NOW=$((NOW0 + 300)) run /bin/bash "$LRU" --drain
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(cnt '--relaunch-at-shell' "$T/hf.log")" = 1 ] || { cat "$T/hf.log"; cat "$LRU_STATE/upgrade-state/$SID.json"; false; }
  [ "$(jq -r .verdict "$(result "$SID")")" = upgraded ] || { cat "$(result "$SID")"; false; }
  [[ "$(jq -r .reason "$(result "$SID")")" == *"relaunched at its shell after drainer death"* ]] || false
  [ "$(st "$SID" .terminal)" = upgraded ]
  nothing_typed
}

# ── S10: exit-readback, bounded ───────────────────────────────────────────────────────────────────

@test "S10 readback unreadable three times: attempts 1,2,3 with 600/1200 s backoff, then terminal exit-readback" {
  SID=5a5a5a5a-0000-4000-8000-000000000001
  sleep 300 & LIVE_PID=$!
  SESS_PID="$LIVE_PID" sess 610 "$SID" "$OLD --permission-mode auto --model claude-opus-5 --effort high"
  printf '%s\n%s\n' "$OPEN_LINE" "$READBACK_LINE" > "$T/hf-recycle.out"; echo 1 > "$T/hf-recycle-rc"
  touch "$T/composer-unreadable"
  queue_req a1 "$SID" 610
  LRU_NOW=$NOW0 run /bin/bash "$LRU" --drain
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(st "$SID" .disposition)" = retry-wait ] || { cat "$LRU_STATE/upgrade-state/$SID.json"; false; }
  [ "$(st "$SID" .attempts)" = 1 ]; [ "$(st "$SID" .readbacks)" = 1 ]
  [ "$(st "$SID" .last_class)" = readback ]
  [ "$(st "$SID" .next_eligible)" = "$((NOW0 + 600))" ]
  T2=$((NOW0 + 601)); queue_req a2 "$SID" 610
  LRU_NOW=$T2 run /bin/bash "$LRU" --drain
  [ "$(st "$SID" .attempts)" = 2 ]; [ "$(st "$SID" .readbacks)" = 2 ]
  [ "$(st "$SID" .next_eligible)" = "$((T2 + 1200))" ]
  [ "$(cnt 'TERMINAL' "$T/notify.log")" = 0 ]
  T3=$((T2 + 1201)); queue_req a3 "$SID" 610
  LRU_NOW=$T3 run /bin/bash "$LRU" --drain
  [ "$(st "$SID" .disposition)" = terminal ] || { cat "$LRU_STATE/upgrade-state/$SID.json"; false; }
  [ "$(st "$SID" .terminal)" = exit-readback ]
  [ "$(st "$SID" .attempts)" = 3 ]; [ "$(st "$SID" .readbacks)" = 3 ]
  [ "$(cnt '--recycle' "$T/hf.log")" = 3 ]
  [ "$(cnt '^--role desk .*TERMINAL exit-readback' "$T/notify.log")" = 1 ] || { cat "$T/notify.log"; false; }
  [[ "$(jq -r .reason "$(result "$SID")")" == *"(held: exit-readback)"*"composer unreadable (nothing sent)"* ]] || { cat "$(result "$SID")"; false; }
  [ ! -s "$T/tui.log" ]
  nothing_typed
}

s10_terminal_record() { # a readback terminal written straight into the record (S10 drove there)
  SID=5a5a5a5a-0000-4000-8000-000000000002
  sleep 300 & LIVE_PID=$!
  SESS_PID="$LIVE_PID" sess 611 "$SID" "$OLD --permission-mode auto --model claude-opus-5 --effort high"
  rec "$SID" 611 '.disposition = "terminal" | .terminal = "exit-readback" | .terminal_ts = $now | .step = "done"
                  | .attempts = 3 | .readbacks = 3 | .next_eligible = ($now + 1200)'
  rm -f "$LRU_STATE/upgrade-state/$SID.open"
}

@test "S10b a readback terminal is not queued by --auto-enqueue or refill; --reset makes it eligible again" {
  s10_terminal_record
  export LR_UPGRADE_AUTO=on
  LRU_NOW=$((NOW0 + 3000)) run /bin/bash "$LRU" --auto-enqueue
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" != *"$SID"* ]] || { echo "$output"; false; }
  [ ! -e "$LRU_STATE/upgrade-queue/auto-upgrade-$SID.json" ]
  LRU_NOW=$((NOW0 + 3000)) run /bin/bash "$LRU" --drain
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ ! -s "$T/hf.log" ] || { echo "refill queued a terminal"; cat "$T/hf.log"; false; }
  [ "$(st "$SID" .terminal)" = exit-readback ]
  LRU_NOW=$((NOW0 + 3000)) run /bin/bash "$LRU" --reset "$SID"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(st "$SID" .terminal)" = null ]
  [ "$(st "$SID" .attempts)" = 0 ]; [ "$(st "$SID" .readbacks)" = 0 ]
  [ "$(st "$SID" .disposition)" = retry-wait ]
  LRU_NOW=$((NOW0 + 3000)) run /bin/bash "$LRU" --auto-enqueue
  [[ "$output" == *"611	$SID"* ]] || { echo "$output"; false; }
  [ -f "$LRU_STATE/upgrade-queue/auto-upgrade-$SID.json" ]
}

@test "S10c a readback terminal recorded for another target binary is eligible again through refill" {
  s10_terminal_record
  jq '.target.binlabel = ".claude-270"' "$LRU_STATE/upgrade-state/$SID.json" > "$T/r.json" && mv "$T/r.json" "$LRU_STATE/upgrade-state/$SID.json"
  printf '%s\n%s\n' "$OPEN_LINE" "$READBACK_LINE" > "$T/hf-recycle.out"; echo 1 > "$T/hf-recycle-rc"
  LR_UPGRADE_AUTO=on LRU_NOW=$((NOW0 + 60)) run /bin/bash "$LRU" --drain
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(cnt "--recycle --same-account --source-pane 611 --source-session $SID" "$T/hf.log")" = 1 ] || { echo "$output"; cat "$T/hf.log" 2>/dev/null; false; }
  [ "$(jq -r .requested_by "$(result "$SID")")" = poller-auto ]
  [ "$(st "$SID" .target.binlabel)" = .claude-280 ]
  [ "$(st "$SID" .terminal)" = null ]
  [ "$(st "$SID" .attempts)" = 1 ] || { cat "$LRU_STATE/upgrade-state/$SID.json"; false; }
  [ "$(st "$SID" .disposition)" = retry-wait ]
  nothing_typed
}

# ── S11: our own /exit left in the composer ───────────────────────────────────────────────────────

s11_drive() { # $1=pane $2=composer after handoff-fire ('' = unreadable)
  SID="5b5b5b5b-0000-4000-8000-00000000${1}0"
  sleep 300 & LIVE_PID=$!
  SESS_PID="$LIVE_PID" sess "$1" "$SID" "$OLD --permission-mode auto --model claude-opus-5 --effort high"
  printf '%s\n%s\n' "$OPEN_LINE" "$READBACK_LINE" > "$T/hf-recycle.out"; echo 1 > "$T/hf-recycle-rc"
  if [ -n "$2" ]; then printf '%s' "$2" > "$T/hf-composer-after"; else touch "$T/composer-unreadable"; fi
  run /bin/bash "$LRU" --drive "$SID" "$1"
  [ "$status" -eq 3 ] || { echo "$output"; cat "$(result "$SID")" 2>/dev/null; false; }
}

@test "S11a composer reads exactly /exit after a readback hold: ONE Ctrl-U, read back empty, 'our /exit cleared'" {
  s11_drive 612 /exit
  [ "$(cnt 'send-text' "$T/tui.log")" = 1 ] || { cat "$T/tui.log"; false; }
  grep -qx 'rpc send-text --match id:612 ^U' "$T/tui.log" || { cat "$T/tui.log"; false; }
  [ ! -s "$T/composer-612" ]
  [[ "$(jq -r .reason "$(result "$SID")")" == *"our /exit cleared"* ]] || { cat "$(result "$SID")"; false; }
  [ "$(st "$SID" .last_class)" = readback ]
  nothing_typed
}

@test "S11b composer '/exitx' after a readback hold: nothing sent" {
  s11_drive 613 /exitx
  [ "$(cnt 'send-text' "$T/tui.log")" = 0 ] || { cat "$T/tui.log"; false; }
  [ "$(cat "$T/composer-613")" = /exitx ]
  [[ "$(jq -r .reason "$(result "$SID")")" == *"the composer is not our /exit (nothing sent)"* ]] || { cat "$(result "$SID")"; false; }
  nothing_typed
}

@test "S11c composer holding a draft after a readback hold: nothing sent" {
  s11_drive 614 'please look at the login bug'
  [ "$(cnt 'send-text' "$T/tui.log")" = 0 ] || { cat "$T/tui.log"; false; }
  [[ "$(jq -r .reason "$(result "$SID")")" == *"not our /exit (nothing sent)"* ]] || { cat "$(result "$SID")"; false; }
  nothing_typed
}

@test "S11d composer unreadable (cc_tui_composer rc 1) after a readback hold: nothing sent" {
  s11_drive 615 ''
  [ "$(cnt 'send-text' "$T/tui.log")" = 0 ] || { cat "$T/tui.log"; false; }
  [[ "$(jq -r .reason "$(result "$SID")")" == *"composer unreadable (nothing sent)"* ]] || { cat "$(result "$SID")"; false; }
  nothing_typed
}

# ── S13: settle first, then drive ─────────────────────────────────────────────────────────────────

@test "S13 A in flight under a dead owner and B queued: A is settled before B is driven, and A is not driven again" {
  A=5c5c5c5c-0000-4000-8000-00000000000a
  B=5c5c5c5c-0000-4000-8000-00000000000b
  rec "$A" 716 '.step = "precheck"'
  sleep 300 & LIVE_PID=$!
  SESS_PID="$LIVE_PID" sess 717 "$B" "$OLD --permission-mode auto --model claude-opus-5 --effort high"
  queue_req qa "$A" 716
  queue_req qb "$B" 717
  # when B's handoff-fire runs, record what A's verdict was at that instant
  printf 'echo "A-at-B: $(jq -r .reason "%s" 2>/dev/null)" >> "%s/hf.log"\n' "$(result "$A")" "$T" > "$T/hf-hook.sh"
  run /bin/bash "$LRU" --drain
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$(jq -r .reason "$(result "$A")")" == "interrupted at step precheck by the drainer's death"* ]] || { cat "$(result "$A")"; false; }
  grep -q "^A-at-B: interrupted at step precheck" "$T/hf.log" || { cat "$T/hf.log"; false; }
  [ "$(cnt "--source-session $B" "$T/hf.log")" = 1 ]
  [ "$(cnt "--source-session $A" "$T/hf.log")" = 0 ] || { cat "$T/hf.log"; false; }
  [ -f "$LRU_STATE/upgrade-queue/qa.json" ] || { echo "A's request was claimed in the drain that settled it"; false; }
  [ "$(st "$A" .disposition)" = retry-wait ]
  [ "$(st "$A" .interrupted)" = 1 ]
  [ -f "$(result "$B")" ]
  nothing_typed
}
