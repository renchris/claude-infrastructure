#!/usr/bin/env bats
# bin/cc-lr — the reconciler-facing half (LIMIT_RECOVER_FLEET_V2 W4): while the reconciler is live,
# recover and switch QUEUE requests/<sid>.cc-lr.json and act on nothing; while it is not, the direct
# path runs behind the §C10 fence and hands its launch lock down to the actuator it fires. Plus the
# three read/ctl verbs: status --cohort, accounts --limited, cohort refire.
#
# HERMETIC: HOME, LR_STATE_DIR and LR_RECON_ROOT live in BATS_TEST_TMPDIR; cc-find, lr-fleet,
# lr-handoff, claude-accounts and launchctl are stubs; the fence's clock and wake time are seams.
# The only process touched is a `sleep` this file starts and kills itself. Nothing types anywhere.

NOW=1790000500

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LR="$REPO/bin/cc-lr"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export LR_STATE_DIR="$BATS_TEST_TMPDIR/state"; mkdir -p "$LR_STATE_DIR"
  export LR_RECON_ROOT="$LR_STATE_DIR/recon"; mkdir -p "$LR_RECON_ROOT/owned"
  export LR_RECON_NOW="$NOW" LR_RECON_WAKETIME=0
  unset LR_RECORD_ID LR_RECON_FENCE_FRESH_S LR_LAUNCH_LOCK
  SID="aaaaaaaa-1111-4000-8000-000000000001"
  MUTEX="$LR_STATE_DIR/runs/by-sid/$SID.active"
  REQ="$LR_STATE_DIR/requests/$SID.cc-lr.json"
  LOCK="$LR_STATE_DIR/locks/$SID.launch"
  export CC_LR_FIND_BIN="$BATS_TEST_TMPDIR/cc-find"
  export CC_LR_FLEET_BIN="$BATS_TEST_TMPDIR/lr-fleet.sh"
  export CC_LR_HANDOFF_BIN="$BATS_TEST_TMPDIR/lr-handoff.sh"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/claude-accounts"
  export CC_LR_POLLER_LABEL="com.reso.lr-reset-poller"
  STUBBIN="$BATS_TEST_TMPDIR/stubbin"; mkdir -p "$STUBBIN"
  PATH="$STUBBIN:$PATH"; export PATH
  printf '#!/usr/bin/env bash\necho "$*" >> "%s/launchctl.argv"\n' "$BATS_TEST_TMPDIR" > "$STUBBIN/launchctl"
  printf '#!/usr/bin/env bash\necho "$*" >> "%s/ranker.argv"\nexit 97\n' "$BATS_TEST_TMPDIR" > "$CC_ACCOUNTS_BIN"
  # cc-find: one LIMITED row for pane 117.
  printf '#!/usr/bin/env bash\nprintf "%%s\\t117\\tclaude-next\\t%s/.claude-next\\t%s/wt\\tLIVE\\tLIMITED\\n" "%s"\n' \
    "$HOME" "$HOME" "$SID" > "$CC_LR_FIND_BIN"
  # The actuators record that they ran AND the lock they ran under, and the fleet stub prints the
  # two lines cc-lr parses from lr-fleet --detach.
  for s in "$CC_LR_FLEET_BIN" "$CC_LR_HANDOFF_BIN"; do
    cat > "$s" <<SH
#!/usr/bin/env bash
echo "\$*" >> "$BATS_TEST_TMPDIR/\$(basename "\$0").argv"
{ echo "lock=\${LR_LAUNCH_LOCK:-}"
  [ -n "\${LR_LAUNCH_LOCK:-}" ] && echo "holder=\$(cat "\$LR_LAUNCH_LOCK/holder" 2>/dev/null)"
  echo "ppid=\$PPID"
  echo "gppid=\$(ps -o ppid= -p "\$PPID" | tr -d ' ')"
} > "$BATS_TEST_TMPDIR/\$(basename "\$0").env"
echo "lr-fleet: DETACHED — driver pid 424242 is recovering aaaaaaaa; the verdict arrives as mail. END YOUR TURN; do not poll."
echo "run=$LR_STATE_DIR/fleet/one-x log=$LR_STATE_DIR/fleet/one-x/detached.log"
exit 0
SH
  done
  chmod +x "$STUBBIN/launchctl" "$CC_ACCOUNTS_BIN" "$CC_LR_FIND_BIN" "$CC_LR_FLEET_BIN" "$CC_LR_HANDOFF_BIN"
  unset CLAUDE_CODE_SESSION_ID CC_PANE_ID ITERM_SESSION_ID KITTY_WINDOW_ID
  SLEEP_PID=""
}

teardown() {
  if [ -n "$SLEEP_PID" ]; then
    kill "$SLEEP_PID" 2>/dev/null || true
    wait "$SLEEP_PID" 2>/dev/null || true
  fi
}

recon_on() { : > "$LR_STATE_DIR/recon.on"; }
heartbeat() { printf '{"pid":1,"progress":7,"progress_wall":%s}' "$1" > "$LR_RECON_ROOT/heartbeat"; }
owned() { printf '{"record_id":"r1","procs":[{"role":"x","pid":%s,"lstart":"%s"}]}' "$1" "$2" > "$LR_RECON_ROOT/owned/$SID"; }
lstart_of() { TZ=UTC LC_ALL=C ps -o lstart= -p "$1" | tr -s ' ' | sed -e 's/^ *//' -e 's/ *$//'; }
not_called() { [ ! -e "$BATS_TEST_TMPDIR/$1.argv" ] || { echo "$1 was called:"; cat "$BATS_TEST_TMPDIR/$1.argv"; false; }; }
self_switch() { run env CLAUDE_CODE_SESSION_ID="$SID" CC_PANE_ID=417 CLAUDE_CONFIG_DIR="$HOME/.claude-next" bash "$LR" switch "$@"; }
req_field() { python3 -c 'import json,sys; v=json.load(open(sys.argv[1]))[sys.argv[2]]; print(v if not isinstance(v, bool) else str(v).lower())' "$REQ" "$1"; }

@test "statics: cc-lr parses under /bin/bash 3.2" {
  /bin/bash -n "$LR"
}

@test "recover, reconciler LIVE: writes <sid>.cc-lr.json with the fields, takes no mutex, fires nothing" {
  recon_on; heartbeat "$NOW"
  run bash "$LR" recover 117 --target next3
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" = "cc-lr: QUEUED for the reconciler aaaaaaaa → $REQ" ] || { echo "$output"; false; }
  [ "$(req_field sid)" = "$SID" ]
  [ "$(req_field requested_by)" = cc-lr ]
  [ "$(req_field mode)" = recover ]
  [ "$(req_field pane)" = 117 ]
  [ "$(req_field config_dir)" = "$HOME/.claude-next" ]
  [ "$(req_field target)" = next3 ]
  python3 -c 'import json,sys; a=json.load(open(sys.argv[1]))["at"]; assert isinstance(a, int) and a > 1700000000, a' "$REQ"
  not_called lr-fleet.sh; not_called lr-handoff.sh
  [ ! -e "$MUTEX" ]
  [ ! -e "$LOCK" ]
  [ -z "$(find "$LR_STATE_DIR/requests" -name '.*')" ]
}

@test "recover, reconciler LIVE with no --target: the request carries no target key" {
  recon_on; heartbeat "$NOW"
  run bash "$LR" recover 117
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert "target" not in d, d' "$REQ"
}

@test "switch, reconciler LIVE: the SELF verb queues mode=switch and never runs lr-handoff" {
  recon_on; heartbeat "$NOW"
  self_switch --target next3
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"QUEUED for the reconciler aaaaaaaa → $REQ"* ]] || { echo "$output"; false; }
  [ "$(req_field mode)" = switch ]
  [ "$(req_field pane)" = 417 ]
  [ "$(req_field config_dir)" = "$HOME/.claude-next" ]
  [ "$(req_field target)" = next3 ]
  not_called lr-handoff.sh
  [ ! -e "$MUTEX" ]
}

@test "recover, heartbeat STALE and the owned proc dead: cc-lr acts under the launch lock, then hands it to the detached driver" {
  recon_on; heartbeat $((NOW - 1000)); owned 1 "Thu Jan 1 00:00:00 1970"
  run bash "$LR" recover 117 --target next3
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ ! -e "$REQ" ]
  [ "$(cat "$BATS_TEST_TMPDIR/lr-fleet.sh.argv")" = "--one $SID --target next3 --source-pane 117 --detach" ]
  # cc-lr took the lock itself (the double-typer audit names it) …
  grep -q "	$SID	cc-lr	taken	" "$LR_RECON_ROOT/launch.log" || { cat "$LR_RECON_ROOT/launch.log"; false; }
  # … and released it BEFORE firing: the detached driver outlives cc-lr, so it must not inherit a lock
  # cc-lr's EXIT trap drops ~3 s later. lf_one re-takes it under the driver's own pid.
  env_f="$BATS_TEST_TMPDIR/lr-fleet.sh.env"
  [ -z "$(sed -n 's/^lock=//p' "$env_f")" ] || { cat "$env_f"; false; }
  # The fence's own verdict lines stay out of cc-lr's output: its consumers grep `verdict=`.
  [[ "$output" != *"lr-recon-fence:"* ]] || { echo "$output"; false; }
  [ ! -e "$LOCK" ] || { echo "the launch lock outlived cc-lr"; false; }
}

@test "recover, heartbeat STALE and an owned proc ALIVE: REFUSED rc 2, nothing fired, no mutex" {
  sleep 300 & SLEEP_PID=$!
  recon_on; heartbeat $((NOW - 1000)); owned "$SLEEP_PID" "$(lstart_of "$SLEEP_PID")"
  run bash "$LR" recover 117 --target next3
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [[ "$output" == *"REFUSED — the reconciler still owns aaaaaaaa (proc-alive:x:$SLEEP_PID)"* ]] || { echo "$output"; false; }
  [[ "$output" != *"verdict="* ]] || { echo "$output"; false; }
  not_called lr-fleet.sh
  [ ! -e "$MUTEX" ]
  [ ! -e "$REQ" ]
}

@test "switch, heartbeat STALE and an owned proc ALIVE: REFUSED rc 2, lr-handoff never runs" {
  sleep 300 & SLEEP_PID=$!
  recon_on; heartbeat $((NOW - 1000)); owned "$SLEEP_PID" "$(lstart_of "$SLEEP_PID")"
  self_switch --target next3
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  not_called lr-handoff.sh
  [ ! -e "$MUTEX" ]
}

@test "recover, recon.on ABSENT: today's direct path, no request and no launch lock handed down" {
  heartbeat "$NOW"; owned 1 "Thu Jan 1 00:00:00 1970"
  run bash "$LR" recover 117 --target next3
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ ! -e "$REQ" ]
  [ "$(cat "$BATS_TEST_TMPDIR/lr-fleet.sh.argv")" = "--one $SID --target next3 --source-pane 117 --detach" ]
  [ "$(sed -n 's/^lock=//p' "$BATS_TEST_TMPDIR/lr-fleet.sh.env")" = "" ]
  [ -d "$MUTEX" ]
}

@test "status --cohort prints each member's phase, age, attempt, error, next action and ETA" {
  mkdir -p "$LR_RECON_ROOT/cohorts"
  cat > "$LR_RECON_ROOT/cohorts/c1.json" <<JSON
{"cid":"c1","acct":"next2","scope":"5h","status":{"cid":"c1","acct":"next2","scope":"5h","at":$NOW,"tally":{"moving":0,"waiting":1,"held":0,"escalated":0,"done":0},"members":[{"sid":"$SID","pane":["iterm","117"],"cwd":"/x","phase":"WAIT","substate":"reset","bucket":"waiting","age_s":412.7,"attempt":2,"last_error":"rate_limit","next_action":"relaunch at reset","eta":1790003600,"outcome":null}]}}
JSON
  run bash "$LR" status --cohort
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"cohort c1  next2 5h  1 waiting"* ]] || { echo "$output"; false; }
  line="$(printf '%s\n' "$output" | grep aaaaaaaa)"
  for want in "pane iterm:117" "WAIT/reset" "age 412s" "attempt 2" "err rate_limit" "next: relaunch at reset" "eta 2026-09-21T"; do
    [[ "$line" == *"$want"* ]] || { echo "missing '$want' in: $line"; false; }
  done
  run bash "$LR" status --cohort c1
  [ "$status" -eq 0 ] && [[ "$output" == *aaaaaaaa* ]] || { echo "$output"; false; }
  run bash "$LR" status --cohort nope
  [ "$status" -eq 1 ]
}

@test "status --cohort with no cohorts says so, rc 0" {
  run bash "$LR" status --cohort
  [ "$status" -eq 0 ]
  [ "$output" = "cc-lr: no reconciler cohorts" ]
}

@test "accounts --limited prints a fact grouped under its account, and passes over an expired one" {
  mkdir -p "$LR_RECON_ROOT/facts"
  printf '{"acct":"next3","scope":"7d","status":"rejected","window":"seven_day","resets_at":4102444800,"observed_at":1,"src":"hook"}' \
    > "$LR_RECON_ROOT/facts/next3.7d.json"
  printf '{"acct":"next4","scope":"5h","status":"rejected","window":"five_hour","resets_at":1000,"observed_at":1,"src":"census"}' \
    > "$LR_RECON_ROOT/facts/next4.5h.json"
  run bash "$LR" accounts --limited
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == "next3   1 limited scope"* ]] || { echo "$output"; false; }
  [[ "$output" == *"  7d "*"resets 2100-01-01T00:00Z"*"src=hook"* ]] || { echo "$output"; false; }
  [[ "$output" != *next4* ]] || { echo "an expired fact was listed: $output"; false; }
  rm -f "$LR_RECON_ROOT/facts/next3.7d.json"
  run bash "$LR" accounts --limited
  [ "$status" -eq 0 ]
  [ "$output" = "cc-lr: no limited accounts in the reconciler facts" ]
}

@test "cohort refire <sid8> writes recon/ctl/<sid>.refire.json atomically and prints its path" {
  mkdir -p "$LR_RECON_ROOT/sessions"; echo '{}' > "$LR_RECON_ROOT/sessions/$SID.json"
  run bash "$LR" cohort refire aaaaaaaa
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  f="$LR_RECON_ROOT/ctl/$SID.refire.json"
  [ "$output" = "$f" ]
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["sid"]==sys.argv[2] and d["by"]=="cc-lr" and isinstance(d["at"], int), d' "$f" "$SID"
  [ -z "$(find "$LR_RECON_ROOT/ctl" -name '.*')" ]
  run bash "$LR" cohort refire bbbbbbbb
  [ "$status" -eq 1 ]
  [ ! -e "$LR_RECON_ROOT/ctl/bbbbbbbb.refire.json" ]
}

@test "cohort refire <pane> resolves through cc-find" {
  run bash "$LR" cohort refire 117
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -f "$LR_RECON_ROOT/ctl/$SID.refire.json" ]
}

@test "the usage block and the unknown-subcommand line name the three new verbs" {
  run bash "$LR" nope
  [ "$status" -eq 3 ]
  [[ "$output" == *"unknown subcommand 'nope'"*"status --cohort, accounts --limited, cohort refire"* ]] || { echo "$output"; false; }
  [[ "$output" == *"cc-lr status --cohort [cid]"* ]] || { echo "$output"; false; }
}
