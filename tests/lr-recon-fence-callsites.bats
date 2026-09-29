#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2016  # stubs are written verbatim; each @test is its own subshell; per-test exports are the intent
# The §C10 fence at its W4 call sites (LIMIT_RECOVER_FLEET_V2 § W4): lr-upgrade's two drives
# (lru_switch_drive, lru_drive), cc-resume-debt's relaunch, and boot-resume-launch. Each site gets
# the same four cases, keyed on the fence's own predicate rather than on a site's wording:
#   (a) recon.on + owned/<sid> + fresh heartbeat      → the site does NOT act (its actuator is not called)
#   (b) stale heartbeat + an owned proc alive         → does NOT act
#   (c) stale heartbeat + every owned proc dead       → acts ("lapsed"), and the actuator sees a
#       non-empty LR_LAUNCH_LOCK whose holder names the CALLER's pid; the lock is gone afterwards
#   (d) recon.on absent                               → acts as before (regression)
# The caller's pid is the `$!` of the process under test, so "names the caller" is a comparison
# between two independent reads, never the stub agreeing with itself.
#
# HERMETIC: HOME, LR_STATE_DIR, LR_RECON_ROOT, the registry, the ps snapshot and every actuator are
# fixtures under BATS_TEST_TMPDIR; the clock and wake time are seams. Nothing types into a pane,
# opens a window or reads the operator's state. The only processes touched are `sleep`s this file
# starts and kills itself.

NOW=1790000500

setup() {
  command -v jq >/dev/null || skip "jq required"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LRU="$REPO/scripts/limit-recover/lr-upgrade.sh"
  RD="$REPO/bin/cc-resume-debt"
  BRL="$REPO/scripts/boot-resume-launch.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export LR_STATE_DIR="$HOME/.reso/limit-recover" LRU_STATE="$HOME/.reso/limit-recover"
  export LR_RECON_ROOT="$LR_STATE_DIR/recon"; mkdir -p "$LR_RECON_ROOT/owned"
  export LR_RECON_NOW="$NOW" LR_RECON_WAKETIME=0
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/cc-registry"; mkdir -p "$CC_REGISTRY_DIR"
  export CC_FIRE_CAPACITY_GATE=off CC_ADMIT_GATE=off
  unset LR_RECORD_ID LR_RECON_FENCE_FRESH_S LR_LAUNCH_LOCK CLAUDE_CODE_SESSION_ID CC_BOOT_RESUME_MODE
  export CC_BOOT_RESUME_STATE_DIR="$BATS_TEST_TMPDIR/boot-resume"
  STUBS="$BATS_TEST_TMPDIR/stubs"; mkdir -p "$STUBS"
  export OBS="$BATS_TEST_TMPDIR/obs.log"
  SLEEPERS=""
}

teardown() {
  local p
  for p in $SLEEPERS; do kill "$p" 2>/dev/null || true; wait "$p" 2>/dev/null || true; done
}

sleeper() { sleep 300 & SLEEPERS="$SLEEPERS $!"; LAST_SLEEPER=$!; }
lstart_of() { TZ=UTC LC_ALL=C ps -o lstart= -p "$1" | tr -s ' ' | sed -e 's/^ *//' -e 's/ *$//'; }

# scenario a|b|c|d <sid> — the fence's four worlds for one sid.
scenario() {
  local sid="$2" pid=1 ls="not-this-process" pw=$((NOW - 1000))
  [ "$1" = d ] && return 0
  : > "$LR_STATE_DIR/recon.on"
  [ "$1" = a ] && pw="$NOW"
  if [ "$1" = b ]; then sleeper; pid="$LAST_SLEEPER"; ls="$(lstart_of "$pid")"; fi
  printf '{"record_id":"r1","procs":[{"role":"actuator","pid":%s,"lstart":"%s"}]}' "$pid" "$ls" \
    > "$LR_RECON_ROOT/owned/$sid"
  printf '{"pid":1,"progress":7,"progress_wall":%s}' "$pw" > "$LR_RECON_ROOT/heartbeat"
}

# The one observation line every actuator stub appends: the lock it saw, and that lock's holder pid.
OBS_LINE='printf "lock=%s holder=%s\n" "${LR_LAUNCH_LOCK:-}" "$(sed -n "s/.*\"pid\":\([0-9]*\).*/\1/p" "${LR_LAUNCH_LOCK:-/nonexistent}/holder" 2>/dev/null)" >> "$OBS"'

# bg <cmd…> — run the subject as its own process so $! IS the caller the lock must name.
bg() { "$@" > "$BATS_TEST_TMPDIR/out" 2>&1 & CALLER=$!; STATUS=0; wait "$CALLER" || STATUS=$?; }

acted() { [ -s "$OBS" ]; }
# (c): the actuator ran under the launch lock this very process took, and nothing outlived it.
assert_lapsed_lock() {
  local sid="$1"
  acted || { cat "$BATS_TEST_TMPDIR/out"; false; }
  [ "$(cat "$OBS")" = "lock=$LR_STATE_DIR/locks/$sid.launch holder=$CALLER" ] || { cat "$OBS"; echo "caller=$CALLER"; false; }
  [ ! -e "$LR_STATE_DIR/locks/$sid.launch" ] || { echo "launch lock outlived its taker"; false; }
}
assert_not_acted() { if acted; then echo "actuator ran:"; cat "$OBS"; cat "$BATS_TEST_TMPDIR/out"; false; fi; }

# ── lr-upgrade: lru_switch_drive ─────────────────────────────────────────────────────────────────
LST="Tue Sep 22 06:47:13 2026"
sw_fixture() { # the lr-switch-driver.bats world: one idle next3 session, cc_tui_submit a flip-recorder
  export LRU_REG_DIR="$BATS_TEST_TMPDIR/reg"; mkdir -p "$LRU_REG_DIR"
  export LRU_CFG_ROOT="$HOME" LRU_PS_SNAPSHOT="$BATS_TEST_TMPDIR/ps.txt" LRU_COMPOSER=off LRU_SELF_SID=""
  : > "$LRU_PS_SNAPSHOT"
  export LRU_LR_LIB="$BATS_TEST_TMPDIR/absent" CC_RESUME_DEBT_BIN="$BATS_TEST_TMPDIR/absent"
  export LRU_NOTIFY_BIN="$BATS_TEST_TMPDIR/absent" LRU_SA_PROBE="$STUBS/sa-probe"
  printf '#!/bin/bash\necho "live_subagents: 0"\n' > "$LRU_SA_PROBE"; chmod +x "$LRU_SA_PROBE"
  export LRU_SWITCH_POLL_S=0 LRU_SWITCH_VERIFY_S=3 LRU_GAP_S=0
  SWSID=50505050-0000-4000-8000-000000000001
  printf '{"paneUUID":"551","pid":50001,"session_id":"%s","account":"claude-tertiary","cwd":"%s","lstart":"%s"}\n' \
    "$SWSID" "$BATS_TEST_TMPDIR" "$LST" > "$LRU_REG_DIR/551.json"
  printf '50001 1 %s /opt/cc/.claude-280/node_modules/.bin/claude --model claude-opus-5-5 --effort high\n' "$LST" >> "$LRU_PS_SNAPSHOT"
  mkdir -p "$HOME/.claude-tertiary/projects/-x"
  printf '%s\n' '{"type":"user","message":{"content":"hi"}}' \
    '{"type":"assistant","message":{"stop_reason":"end_turn","content":[{"type":"text","text":"idle"}]}}' \
    > "$HOME/.claude-tertiary/projects/-x/$SWSID.jsonl"
  export LRU_TUI_LIB="$BATS_TEST_TMPDIR/tui.sh"
  cat > "$LRU_TUI_LIB" <<EOF
cc_tui_submit() {
  $OBS_LINE
  local reg="$LRU_REG_DIR/\$1.json" sid
  sid="\$(jq -r .session_id "\$reg")"
  mkdir -p "$HOME/.claude-secondary/projects/-x"
  cp "$HOME/.claude-tertiary/projects/-x/\$sid.jsonl" "$HOME/.claude-secondary/projects/-x/"
  jq '.account = "claude-secondary"' "\$reg" > "\$reg.t" && mv "\$reg.t" "\$reg"
  return 0
}
EOF
}
sw_run() { bg bash "$LRU" --switch-drive "$SWSID" 551 next2 --requested-by 999 --req-id rq; }
sw_result() { jq -r ".$1" "$LRU_STATE/results/switch-$SWSID.json"; }
sw_deferred() {
  [ "$STATUS" -eq 3 ] || { cat "$BATS_TEST_TMPDIR/out"; false; }
  assert_not_acted
  [ "$(sw_result verdict)" = NOTMOVED ] && [ "$(sw_result reason)" = "reconciler owns it" ] || { cat "$LRU_STATE/results/switch-$SWSID.json"; false; }
}

@test "lru_switch_drive (a) fresh heartbeat: NOTMOVED, reconciler owns it, nothing submitted" {
  sw_fixture; scenario a "$SWSID"; sw_run; sw_deferred
}
@test "lru_switch_drive (b) stale heartbeat, owned proc alive: NOTMOVED, nothing submitted" {
  sw_fixture; scenario b "$SWSID"; sw_run; sw_deferred
}
@test "lru_switch_drive (c) lapsed: submits under the launch lock the drive took, then releases it" {
  sw_fixture; scenario c "$SWSID"; sw_run
  [ "$STATUS" -eq 0 ] || { cat "$BATS_TEST_TMPDIR/out"; false; }
  assert_lapsed_lock "$SWSID"
  [ "$(sw_result verdict)" = SWITCHED ]
}
@test "lru_switch_drive (d) recon off: switches exactly as before, with no launch lock" {
  sw_fixture; scenario d "$SWSID"; sw_run
  [ "$STATUS" -eq 0 ] || { cat "$BATS_TEST_TMPDIR/out"; false; }
  [ "$(cat "$OBS")" = "lock= holder=" ] || { cat "$OBS"; false; }
  [ "$(sw_result verdict)" = SWITCHED ]
}

# ── lr-upgrade: lru_drive ────────────────────────────────────────────────────────────────────────
up_fixture() { # the lr-upgrade.bats D2 world: an admitted idle session whose old process stays alive
  export LRU_REG_DIR="$BATS_TEST_TMPDIR/reg"; mkdir -p "$LRU_REG_DIR"
  export LRU_CFG_ROOT="$BATS_TEST_TMPDIR/cfgroot" LRU_PS_SNAPSHOT="$BATS_TEST_TMPDIR/ps.txt"
  : > "$LRU_PS_SNAPSHOT"
  export LRU_COMPOSER=off LRU_SELF_SID="" LRU_LR_LIB="$BATS_TEST_TMPDIR/absent"
  export LRU_NOTIFY_BIN="$BATS_TEST_TMPDIR/absent" CC_RESUME_DEBT_BIN="$BATS_TEST_TMPDIR/absent"
  export LRU_IT2_BIN="$BATS_TEST_TMPDIR/absent" LRU_RETYPE_MAX=0 LRU_RETYPE_GAP_S=0 LRU_ENGAGE_S=0 LRU_GAP_S=0
  printf '#!/bin/bash\necho /opt/cc/.claude-280/node_modules/.bin/claude\n' > "$STUBS/cc-claude-bin"; chmod +x "$STUBS/cc-claude-bin"
  export LRU_CLAUDE_BIN_CMD="$STUBS/cc-claude-bin" LRU_SA_PROBE="$STUBS/sa-probe"
  printf '#!/bin/bash\necho "live_subagents: 0"\n' > "$LRU_SA_PROBE"; chmod +x "$LRU_SA_PROBE"
  export LRU_MODEL_CONFIG="$BATS_TEST_TMPDIR/model-config.yaml"
  printf 'versions:\n  opus_latest: claude-opus-5-5\n  opus_prior: claude-opus-5\nfrontier_access:\n  active: true\n  model: claude-fable-5-1\n' > "$LRU_MODEL_CONFIG"
  export LRU_CA_LIB="$BATS_TEST_TMPDIR/ca.sh"
  printf 'cc_capacity_probe() { return 0; }\ncc_capacity_admit_reason() { echo ok; }\ncc_capacity_token_mint() { echo "%s/tok"; }\n' \
    "$BATS_TEST_TMPDIR" > "$LRU_CA_LIB"
  export LRU_HF_BIN="$STUBS/hf"
  printf '#!/bin/bash\n%s\nexit 1\n' "$OBS_LINE" > "$LRU_HF_BIN"; chmod +x "$LRU_HF_BIN"
  UPSID=24242424-0000-4000-8000-000000000001
  sleeper
  printf '{"paneUUID":"542","pid":%d,"session_id":"%s","account":"claude-t","cwd":"%s","lstart":"%s"}\n' \
    "$LAST_SLEEPER" "$UPSID" "$BATS_TEST_TMPDIR" "$LST" > "$LRU_REG_DIR/542.json"
  printf '%d 1 %s /opt/cc/.claude-260/node_modules/.bin/claude --model claude-opus-5 --effort high\n' \
    "$LAST_SLEEPER" "$LST" >> "$LRU_PS_SNAPSHOT"
  mkdir -p "$LRU_CFG_ROOT/.claude-t/projects/-x"
  printf '%s\n' '{"type":"user","message":{"content":"hi"}}' \
    '{"type":"assistant","message":{"stop_reason":"end_turn","content":[{"type":"text"}]}}' \
    > "$LRU_CFG_ROOT/.claude-t/projects/-x/$UPSID.jsonl"
}
up_run() { bg bash "$LRU" --drive "$UPSID" 542 --requested-by 999 --req-id rq; }
up_result() { jq -r ".$1" "$LRU_STATE/results/upgrade-$UPSID.json"; }
up_deferred() {
  [ "$STATUS" -eq 3 ] || { cat "$BATS_TEST_TMPDIR/out"; false; }
  assert_not_acted
  [ "$(up_result verdict)" = skipped ] && [ "$(up_result reason)" = "reconciler owns it" ] || { cat "$LRU_STATE/results/upgrade-$UPSID.json"; false; }
}

@test "lru_drive (a) fresh heartbeat: skipped, reconciler owns it, handoff-fire never runs" {
  up_fixture; scenario a "$UPSID"; up_run; up_deferred
}
@test "lru_drive (b) stale heartbeat, owned proc alive: skipped, handoff-fire never runs" {
  up_fixture; scenario b "$UPSID"; up_run; up_deferred
}
@test "lru_drive (c) lapsed: handoff-fire runs under the drive's launch lock, released after" {
  up_fixture; scenario c "$UPSID"; up_run
  assert_lapsed_lock "$UPSID"
  [[ "$(up_result reason)" == "handoff-fire refused before /exit"* ]] || { cat "$LRU_STATE/results/upgrade-$UPSID.json"; false; }
}
@test "lru_drive (d) recon off: reaches handoff-fire exactly as before, with no launch lock" {
  up_fixture; scenario d "$UPSID"; up_run
  [ "$(cat "$OBS")" = "lock= holder=" ] || { cat "$OBS"; cat "$BATS_TEST_TMPDIR/out"; false; }
  [[ "$(up_result reason)" == "handoff-fire refused before /exit"* ]] || false
}

# ── cc-resume-debt: _relaunch ────────────────────────────────────────────────────────────────────
RDSID=11111111-2222-4333-8444-555555555555
rd_fixture() { # an OPEN debt past its grace, never proven: one `step` reaches _relaunch
  export CC_RESUME_DEBT_DIR="$BATS_TEST_TMPDIR/debt" CC_RESUME_DEBT_NOW=1000
  export CC_RESUME_DEBT_HOLD_S=0 CC_RESUME_DEBT_GRACE_S=240 CC_RESUME_DEBT_WAIT_S=0
  WT="$BATS_TEST_TMPDIR/wt"; mkdir -p "$WT" "$CC_RESUME_DEBT_DIR/meta"
  jq -n --arg sid "$RDSID" --arg cwd "$WT" '{sid:$sid, marker:("resume:"+$sid+":0"), pane:"42", mode:"resume",
    cfg:"/fx/.claude-next3", account:"next3", cwd:$cwd, by:"test", why:"t", opened_epoch:0, state:"open",
    attempts:0, attempt_epoch:0, relaunch_rc:null, backlog_id:"", page_verdict:"", events:[]}' \
    > "$CC_RESUME_DEBT_DIR/meta/$RDSID.json"
  printf '#!/bin/bash\nexit 0\n' > "$STUBS/find"
  printf '#!/bin/bash\n%s\nexit 0\n' "$OBS_LINE" > "$STUBS/relaunch"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s/hf.log"\n%s\nexit 0\n' "$BATS_TEST_TMPDIR" "$OBS_LINE" > "$STUBS/hf"
  printf '#!/bin/bash\n[ "$1" = state ] && echo "${PANE_STATE:-busy}"\nexit 0\n' > "$STUBS/pane"
  printf '#!/bin/bash\nexit 0\n' > "$STUBS/nop"
  chmod +x "$STUBS"/*
  export CC_RESUME_DEBT_FIND_BIN="$STUBS/find" CC_RESUME_DEBT_RELAUNCH="$STUBS/relaunch"
  export CC_RESUME_DEBT_PANE_BIN="$STUBS/pane" CC_RESUME_DEBT_HF_BIN="$STUBS/hf"
  export CC_RESUME_DEBT_BACKLOG_BIN="$STUBS/nop" CC_RESUME_DEBT_NOTIFY_BIN="$STUBS/nop" CC_RESUME_DEBT_CUSTODY_BIN="$STUBS/nop"
}
rd_run() { bg "$RD" step --sid "$RDSID"; }
rd_meta() { jq -r "$1" "$CC_RESUME_DEBT_DIR/meta/$RDSID.json"; }
rd_deferred() { # the debt is left exactly where it was, with one `deferred` event naming why
  assert_not_acted
  [ "$(rd_meta .state)" = open ] && [ "$(rd_meta .attempts)" = 0 ] || { cat "$CC_RESUME_DEBT_DIR/meta/$RDSID.json"; false; }
  [ "$(rd_meta '.events[-1].state')" = deferred ] && [ "$(rd_meta '.events[-1].note')" = "$1" ] || { rd_meta .events; false; }
}

@test "cc-resume-debt (a) fresh heartbeat: no relaunch, the debt stays open with a deferred event" {
  rd_fixture; scenario a "$RDSID"; rd_run; rd_deferred "reconciler owns it"
  # a second step does not stack a second identical event
  rd_run; [ "$(rd_meta '.events | length')" = 1 ] || { rd_meta .events; false; }
}
@test "cc-resume-debt (b) stale heartbeat, owned proc alive: no relaunch" {
  rd_fixture; scenario b "$RDSID"; rd_run; rd_deferred "reconciler owns it"
}
@test "cc-resume-debt (c) lapsed: the relaunch runs under the debt's launch lock, released after" {
  rd_fixture; scenario c "$RDSID"; rd_run
  assert_lapsed_lock "$RDSID"
  [ "$(rd_meta .state)" = retrying ] && [ "$(rd_meta .attempts)" = 1 ] || false
}
@test "cc-resume-debt (d) recon off: relaunches as before, under a lock of its own (always)" {
  rd_fixture; scenario d "$RDSID"; rd_run
  assert_lapsed_lock "$RDSID"
  [ "$(rd_meta .state)" = retrying ] || false
}
@test "cc-resume-debt: a live holder of the sid (H(sid) > 0) means no relaunch, and the lock is released" {
  rd_fixture; sleeper
  printf '{"paneUUID":"77","pid":%d,"session_id":"%s"}\n' "$LAST_SLEEPER" "$RDSID" > "$CC_REGISTRY_DIR/77.json"
  rd_run
  rd_deferred "H(sid)=1 live holder(s)"
  [ ! -e "$LR_STATE_DIR/locks/$RDSID.launch" ] || false
}
@test "cc-resume-debt: in-pane when handoff-fire carries --relaunch-at-shell and the pane is at a shell" {
  rd_fixture; printf '# supports --relaunch-at-shell\n' >> "$STUBS/hf"
  PANE_STATE=shell rd_run
  [ -s "$BATS_TEST_TMPDIR/hf.log" ] || { cat "$BATS_TEST_TMPDIR/out"; false; }
  h="$(cat "$BATS_TEST_TMPDIR/hf.log")"
  [[ "$h" == "--relaunch-at-shell --source-pane 42 --source-session $RDSID --resume-launcher "* ]] || { echo "$h"; false; }
  [[ "$h" == *"--resume-cfg /fx/.claude-next3 --resume-cwd $WT" ]] || { echo "$h"; false; }
  L="$(printf '%s' "$h" | sed -n 's/.*--resume-launcher \([^ ]*\).*/\1/p')"
  grep -q "reso-resume-one next3 .*$RDSID" "$L" || { cat "$L"; false; }
  [ "$(grep -c . "$OBS")" = 1 ]   # the in-pane path ran INSTEAD of the new window, not beside it
}
@test "cc-resume-debt: a new window when the pane is busy, or handoff-fire lacks the flag" {
  rd_fixture; printf '# supports --relaunch-at-shell\n' >> "$STUBS/hf"
  PANE_STATE=busy rd_run
  [ ! -e "$BATS_TEST_TMPDIR/hf.log" ] || { cat "$BATS_TEST_TMPDIR/out"; false; }
  acted || { cat "$BATS_TEST_TMPDIR/out"; false; }
  rd_fixture; : > "$OBS"
  PANE_STATE=shell rd_run    # the fixture rewrote hf WITHOUT the flag
  [ ! -e "$BATS_TEST_TMPDIR/hf.log" ] && acted || { cat "$BATS_TEST_TMPDIR/out"; false; }
}

# ── boot-resume-launch ───────────────────────────────────────────────────────────────────────────
BRSID=33333333-0000-4000-8000-000000000001
brl_fixture() { # inside kitty; kitty records its argv (one per line) and what lock it ran under
  export KITTY_WINDOW_ID=31; unset IT2_WRAPPER_NO_KITTY CC_TERM_KITTY_TO
  printf '#!/bin/bash\nprintf "%%s\\n" "$@" > "%s/kitty.argv"\n%s\necho 99\n' "$BATS_TEST_TMPDIR" "$OBS_LINE" > "$STUBS/kitty"
  printf '#!/bin/bash\nexit 0\n' > "$STUBS/resume-one"
  chmod +x "$STUBS"/*
  export CC_TERM_KITTY="$STUBS/kitty" CC_RESUME_ONE_BIN="$STUBS/resume-one" CC_RESUME_DEBT_BIN="$BATS_TEST_TMPDIR/absent"
  BRWT="$BATS_TEST_TMPDIR/wt"; mkdir -p "$BRWT"
}
brl_run() { bg bash "$BRL" next4 "$BRWT" "$BRSID"; }
brl_deferred() {
  [ "$STATUS" -eq 5 ] || { echo "status=$STATUS"; cat "$BATS_TEST_TMPDIR/out"; false; }
  assert_not_acted
}

@test "boot-resume-launch (a) fresh heartbeat: exit 5, no window" {
  brl_fixture; scenario a "$BRSID"; brl_run; brl_deferred
  grep -q 'reconciler owns it' "$BATS_TEST_TMPDIR/out"
}
@test "boot-resume-launch (b) stale heartbeat, owned proc alive: exit 5, no window" {
  brl_fixture; scenario b "$BRSID"; brl_run; brl_deferred
}
@test "boot-resume-launch (c) lapsed: the window opens under the launcher's lock, released on exit" {
  brl_fixture; scenario c "$BRSID"; brl_run
  [ "$STATUS" -eq 0 ] || { cat "$BATS_TEST_TMPDIR/out"; false; }
  assert_lapsed_lock "$BRSID"
}
@test "boot-resume-launch (d) recon off: launches as before (under its own lock), and the root is a shell" {
  brl_fixture; scenario d "$BRSID"; brl_run
  [ "$STATUS" -eq 0 ] || { cat "$BATS_TEST_TMPDIR/out"; false; }
  assert_lapsed_lock "$BRSID"
  # SHELL ROOT: argv after `--` is exactly zsh -ic '<the shq-quoted resume>; exec zsh -i'
  want="'$STUBS/resume-one' 'next4' '$BRWT' '$BRSID'; exec zsh -i"
  [ "$(sed -n '/^--$/{n;p;}' "$BATS_TEST_TMPDIR/kitty.argv")" = zsh ] || { cat "$BATS_TEST_TMPDIR/kitty.argv"; false; }
  [ "$(sed -n '/^--$/{n;n;p;}' "$BATS_TEST_TMPDIR/kitty.argv")" = -ic ] || false
  [ "$(tail -1 "$BATS_TEST_TMPDIR/kitty.argv")" = "$want" ] || { cat "$BATS_TEST_TMPDIR/kitty.argv"; false; }
}
@test "boot-resume-launch: a live holder of the sid refuses with exit 5" {
  brl_fixture; sleeper
  printf '{"paneUUID":"77","pid":%d,"session_id":"%s"}\n' "$LAST_SLEEPER" "$BRSID" > "$CC_REGISTRY_DIR/77.json"
  brl_run; brl_deferred
  [ ! -e "$LR_STATE_DIR/locks/$BRSID.launch" ] || false
}
@test "boot-resume-launch: PARKED-REBOOT is held in page mode and launched in resume mode" {
  brl_fixture; mkdir -p "$LR_RECON_ROOT/sessions"
  printf '{"sid":"%s","record_id":"r1","phase":"PRE-MOVE","substate":"PARKED-REBOOT"}\n' "$BRSID" > "$LR_RECON_ROOT/sessions/$BRSID.json"
  brl_run; brl_deferred
  grep -q 'parked-reboot' "$BATS_TEST_TMPDIR/out"
  mkdir -p "$CC_BOOT_RESUME_STATE_DIR"; echo resume > "$CC_BOOT_RESUME_STATE_DIR/mode"
  brl_run
  [ "$STATUS" -eq 0 ] && acted || { cat "$BATS_TEST_TMPDIR/out"; false; }
}
@test "cc-resume-debt → boot-resume-launch: the launcher child acts under its parent's inherited lock" {
  rd_fixture; brl_fixture; scenario c "$RDSID"
  export CC_RESUME_DEBT_RELAUNCH="bash $BRL"
  rd_run
  assert_lapsed_lock "$RDSID"
  grep -q 'lock=inherited' "$CC_RESUME_DEBT_DIR/log/$RDSID.log" || { cat "$CC_RESUME_DEBT_DIR/log/$RDSID.log"; false; }
}
