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
  # the capacity gate is not this suite's subject: the poller cases choose its verdict through
  # tests/fixtures/lr-poller-capacity-stub.sh, and nothing here may read this box's live load
  export CC_ADMIT_GATE=off
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
  [ "${lines[0]}" = "cc-lr: QUEUED for the reconciler aaaaaaaa → $REQ" ] || { echo "$output"; false; }
  [[ "${lines[1]}" == "cc-lr: a verdict is due by "*"; if no verdict by then: cc-lr status aaaaaaaa" ]] || { echo "$output"; false; }
  [ "$(req_field sid)" = "$SID" ]
  [ "$(req_field requested_by)" = cc-lr ]
  [ "$(req_field requester_pane)" = "" ]
  [ "$(req_field requester_sid)" = "" ]
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

@test "recover, reconciler LIVE: the request names its CALLER as requester_pane + requester_sid" {
  # Cross-wave contract (lr-reliability D3, 2026-10-11): the reply-to is the caller, never the subject.
  recon_on; heartbeat "$NOW"
  run env CC_PANE_ID=223 CLAUDE_CODE_SESSION_ID=ecb81dfc-0000-4000-8000-000000000009 bash "$LR" recover 117
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(req_field requester_pane)" = 223 ]
  [ "$(req_field requester_sid)" = ecb81dfc-0000-4000-8000-000000000009 ]
  [ "$(req_field pane)" = 117 ]
  [ "$(req_field requested_by)" = cc-lr ]
}

@test "recover, reconciler LIVE with no --target: the request carries no target key" {
  recon_on; heartbeat "$NOW"
  run bash "$LR" recover 117
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert "target" not in d, d' "$REQ"
}

# The move lane's census, for the switch → move delegation (R4/R5): one row for this session, `self`
# only when the caller pinned LRU_SELF_SID to it (a plain `move` here would move a session mid-call).
move_lane_stubs() {
  export CC_LR_UPGRADE_BIN="$BATS_TEST_TMPDIR/lr-upgrade.sh"
  cat > "$CC_LR_UPGRADE_BIN" <<SH
#!/usr/bin/env bash
echo "\$* self=\${LRU_SELF_SID-unset}" >> "$BATS_TEST_TMPDIR/census.argv"
d=move; [ "\${LRU_SELF_SID:-}" = "$SID" ] && d=self
printf '417\t%s\tnext\t%s\t%s\t4242\t%s\n' "$SID" "$HOME/.claude-next" "$HOME/wt" "\$d"
SH
  printf '#!/usr/bin/env bash\necho "$*" >> "%s/ranker.argv"\nprintf "next3 0.9\\nnext2 0.4\\n"\n' "$BATS_TEST_TMPDIR" > "$CC_ACCOUNTS_BIN"
  chmod +x "$CC_LR_UPGRADE_BIN" "$CC_ACCOUNTS_BIN"
}
nmovereq() { local f n=0; for f in "$LR_STATE_DIR"/move/requests/*.json; do [ -e "$f" ] && n=$((n + 1)); done; printf '%s' "$n"; }

@test "[RED] switch, reconciler LIVE: the SELF verb hands the session to the move lane — a batch, no mode=switch request, no lr-handoff" {
  # R4/R5: the reconciler has no switch lane, and the refusal that replaced the silent no-op pointed
  # at `cc-lr move`, whose plan held the caller as hold:self. Now the move lane's worker waits for
  # this turn to end and moves it from outside.
  recon_on; heartbeat "$NOW"; move_lane_stubs
  self_switch --target next3
  [ "$status" -eq 0 ] || { echo "rc $status: $output"; false; }
  [[ "$output" == *"the reconciler is live and has no switch lane — handing this session to the move lane (cc-lr move)"* ]] || { echo "$output"; false; }
  [[ "$output" == *"queued THIS session (aaaaaaaa) in batch "*"end your turn now"* ]] || { echo "$output"; false; }
  [ "$(nmovereq)" -eq 1 ]
  grep -q -- "--target next3 --sid $SID self=$SID" "$BATS_TEST_TMPDIR/census.argv" || { cat "$BATS_TEST_TMPDIR/census.argv"; false; }
  b="$(basename "$LR_STATE_DIR"/move/requests/*.json .json)"
  [ "$(jq -r '.rows[0].disposition' "$LR_STATE_DIR/move/$b/plan.json")" = wait:self ]
  [ "$(jq -r '.until_idle_s' "$LR_STATE_DIR/move/$b/plan.json")" -ge 900 ]
  [ ! -e "$REQ" ]
  [ ! -d "$LR_STATE_DIR/requests" ]
  not_called lr-handoff.sh
  [ ! -e "$MUTEX" ]
}

@test "[RED] switch --dry-run, reconciler LIVE: prints the move lane's dry run, the same disposition, and writes nothing" {
  recon_on; heartbeat "$NOW"; move_lane_stubs
  self_switch --target next3 --dry-run
  [ "$status" -eq 0 ] || { echo "rc $status: $output"; false; }
  [[ "$output" == *"handing this session to the move lane"* ]] || { echo "$output"; false; }
  [[ "$output" == *"wait:self"*"DRY RUN: nothing was written or typed"* ]] || { echo "$output"; false; }
  [[ "$output" != *"would QUEUE"* ]] || { echo "$output"; false; }
  [ ! -e "$LR_STATE_DIR/move" ]
  [ ! -d "$LR_STATE_DIR/requests" ]
  [ ! -e "$BATS_TEST_TMPDIR/launchctl.argv" ]
  not_called lr-handoff.sh
}

@test "CONTROL — CC_LR_SWITCH_MOVE_LANE=off: switch, reconciler LIVE: mode=switch is REFUSED rc 2 and nothing is written" {
  # The reconciler has no switch lane, so the request this used to write was a silent no-op.
  recon_on; heartbeat "$NOW"; move_lane_stubs
  export CC_LR_SWITCH_MOVE_LANE=off
  self_switch --target next3
  [ "$status" -eq 2 ] || { echo "rc $status: $output"; false; }
  [[ "$output" == *"cc-lr move --from A --to B"* ]] || { echo "$output"; false; }
  [[ "$output" != *"QUEUED"* ]] || { echo "$output"; false; }
  [ ! -e "$REQ" ]
  [ ! -d "$LR_STATE_DIR/requests" ]
  [ ! -e "$LR_STATE_DIR/move" ]
  not_called lr-handoff.sh
  [ ! -e "$MUTEX" ]
}

@test "CONTROL — CC_LR_RECON_SWITCH_REFUSE=off: the SELF verb queues mode=switch and never runs lr-handoff" {
  recon_on; heartbeat "$NOW"
  export CC_LR_RECON_SWITCH_REFUSE=off
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
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *aaaaaaaa* ]] || { echo "$output"; false; }
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

repair_bundle() { mkdir -p "$LR_STATE_DIR/$SID/bundle-20261001T000000Z"; printf '%s' "$LR_STATE_DIR/$SID/bundle-20261001T000000Z"; }

@test "repair --mode prompt with no --source-pane writes the pane cc-find resolves" {
  b="$(repair_bundle)"
  run bash "$LR" repair "$b" --mode prompt
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  REQ="$LR_STATE_DIR/requests/cc-lr-repair-$SID.json"
  [ "$(req_field source_pane)" = 117 ]
  [ "$(req_field mode)" = prompt ]
}

@test "repair --mode prompt REFUSES rc 2 and writes nothing when no live pane holds the session" {
  printf '#!/usr/bin/env bash\nexit 1\n' > "$CC_LR_FIND_BIN"
  b="$(repair_bundle)"
  run bash "$LR" repair "$b" --mode prompt
  [ "$status" -eq 2 ]
  [[ "$output" == *"pass --source-pane"* ]] || { echo "$output"; false; }
  [ ! -e "$LR_STATE_DIR/requests/cc-lr-repair-$SID.json" ]
}

@test "repair --mode prompt keeps an explicit --source-pane and relaunch still needs none" {
  b="$(repair_bundle)"
  run bash "$LR" repair "$b" --mode prompt --source-pane 42
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  REQ="$LR_STATE_DIR/requests/cc-lr-repair-$SID.json"
  [ "$(req_field source_pane)" = 42 ]
  printf '#!/usr/bin/env bash\nexit 1\n' > "$CC_LR_FIND_BIN"
  run bash "$LR" repair "$b"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(req_field source_pane)" = "" ]
}

# ── THE POLLER'S CAPACITY LANE (lr-wake incident 2026-10-18, REPORT §4 Wave B step 5, K3/K5) ───
# A launch the in-pane gate refused leaves ONE durable requests/<sid>.cc-lr.json (cause:capacity),
# and the poller is the only thing that retries it: probe first, and open a pane only on an admit,
# carrying the admission as LR_ADMIT_TOKEN. Overnight the alternative was 25 hand fires and 12
# refusal husks (c2 §2.5), and the poller's own autofire opened 509e3aad a second time while pid
# 7301 held it live in pane 28 (c2 Correction 3). The poller runs with the shared capacity stub
# (tests/fixtures/lr-poller-capacity-stub.sh), so the verdict is the case's, never this box's.
cap_lane_setup() {
  POLLER="$REPO/scripts/limit-recover/lr-reset-poller.sh"
  PSTATE="$HOME/.reso/limit-recover"
  mkdir -p "$PSTATE/requests" "$PSTATE/parked" "$PSTATE/resumed" "$BATS_TEST_TMPDIR/wt" "$BATS_TEST_TMPDIR/launchers"
  PREQ="$PSTATE/requests/$SID.cc-lr.json"
  export LR_UPGRADE_AUTO=off LR_POLLER_NO_CENSUS=1 IT2_WRAPPER_NO_KITTY=1 LR_POLLER_SPAWN=tmux
  export CC_ACCOUNT_MAP="$REPO/lib/account-map.generated.sh" CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg"
  export CC_KITTY_SOCKET_BIN="$BATS_TEST_TMPDIR/no-kitty-socket" CC_BEAT_DIR="$BATS_TEST_TMPDIR/beats"
  export LR_POLLER_LAUNCH_DIR="$BATS_TEST_TMPDIR/launchers"
  export LR_POLLER_CAPACITY_LIB="$REPO/tests/fixtures/lr-poller-capacity-stub.sh" LR_FAKE_CA_LOG="$BATS_TEST_TMPDIR/ca.log"
  # spawn_resume's only effect in this lane is `tmux new-session … /bin/bash <launcher>`: the stub
  # records it, so "spawn_resume was never called" is an empty tmux.argv
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> %q\nexit 0\n' "$BATS_TEST_TMPDIR/tmux.argv" > "$STUBBIN/tmux"
  printf '#!/bin/bash\nexit 1\n' > "$STUBBIN/osascript"
  chmod +x "$STUBBIN/tmux" "$STUBBIN/osascript"
  jq -n --arg sid "$SID" --arg cwd "$BATS_TEST_TMPDIR/wt" --argjson t "$(( $(date +%s) - 120 ))" \
    '{sid:$sid, mode:"recover", cause:"capacity", account:"next2", target:"next2", cwd:$cwd,
      prompt:"/limit-recover", first_refused_at:$t, refusals:1, requested_by:"lr-fire-resume"}' > "$PREQ"
}
poll() { run bash "$POLLER" --once; }
plog() { cat "$PSTATE/poller.log" 2>/dev/null; }

@test "capacity lane: the probe REFUSES — spawn_resume is never called, REQUEST-STAY backs off, no attempt is spent" {
  cap_lane_setup
  LR_FAKE_PROBE=refuse poll
  [ "$status" -eq 0 ] || { echo "$output"; plog; false; }
  [ ! -s "$BATS_TEST_TMPDIR/tmux.argv" ] || { cat "$BATS_TEST_TMPDIR/tmux.argv"; false; }
  [ -z "$(ls "$BATS_TEST_TMPDIR/launchers")" ]
  grep -q "REQUEST-STAY $SID (next2) — capacity: .*next probe in 60s, no attempt spent" "$PSTATE/poller.log" || { plog; false; }
  [ "$(jq -r '.attempts // 0' "$PREQ")" = 0 ]
  [ "$(jq -r .cap_k "$PREQ")" = 1 ]
  [ "$(jq -r .next_at "$PREQ")" -gt "$(date +%s)" ]
  # the probe ran on the QUEUE's clock, and no token was minted for a refusal
  grep -q "probe caller=lr-reset-poller .*queued_since=$(jq -r .first_refused_at "$PREQ")" "$LR_FAKE_CA_LOG"
  ! grep -q '^mint ' "$LR_FAKE_CA_LOG"
  # the next tick is inside the backoff: nothing is probed again
  LR_FAKE_PROBE=refuse poll
  [ "$(grep -c '^probe ' "$LR_FAKE_CA_LOG")" -le 2 ]
  [ ! -s "$BATS_TEST_TMPDIR/tmux.argv" ]
}

@test "capacity lane: the probe ADMITS — exactly one spawn, and its launcher carries LR_ADMIT_TOKEN" {
  cap_lane_setup
  poll
  [ "$status" -eq 0 ] || { echo "$output"; plog; false; }
  [ "$(grep -c 'new-session' "$BATS_TEST_TMPDIR/tmux.argv")" = 1 ] || { cat "$BATS_TEST_TMPDIR/tmux.argv"; plog; false; }
  launcher="$(ls "$BATS_TEST_TMPDIR/launchers"/lr-poller-launch-*.sh)"
  [ "$(printf '%s\n' "$launcher" | wc -l | tr -d ' ')" = 1 ]
  tok="$(sed -n 's/^export CC_ADMIT_ACTOR=poller LR_ADMIT_TOKEN=//p' "$launcher")"
  [ -f "$tok" ] || { cat "$launcher"; false; }
  grep -q '^export CC_ADMIT_ACTOR=poller ' "$launcher"
  ! grep -q 'LR_RUN_DIR' "$launcher"              # K3: no run-dir owner, so a pane refusal re-queues HERE
  grep -q -- "--prompt /limit-recover" "$launcher"
  grep -q "^mint sid=$SID kind=turn run=\$" "$LR_FAKE_CA_LOG"
  grep -q "REQUEST-SPAWNED $SID on next2 (capacity queue, tmux)" "$PSTATE/poller.log" || { plog; false; }
  [ "$(jq -r .spawned_at "$PREQ")" -gt 0 ]
  # the request stays queued until a holder is seen, and a second tick does not spawn again
  poll
  [ "$(grep -c 'new-session' "$BATS_TEST_TMPDIR/tmux.argv")" = 1 ]
}

@test "capacity lane: a LIVE beat holder means nothing spawns (the 509e3aad replay) — the request retires" {
  cap_lane_setup
  # 509e3aad: pid 7301 held it live in pane 28, started WITHOUT --resume and with no registry row.
  # Here the holder is this bats process: alive, under its own start time.
  mkdir -p "$CC_BEAT_DIR"
  jq -n --arg sid "$SID" --argjson pid "$$" --arg ls "$(TZ=UTC ps -o lstart= -p $$ | tr -s ' ' | sed 's/^ *//; s/ *$//')" \
    '{sid:$sid, pane:"28", pid:$pid, lstart:$ls, t:1, kind:"prompt", who:"auto"}' > "$CC_BEAT_DIR/$SID.json"
  poll
  [ "$status" -eq 0 ] || { echo "$output"; plog; false; }
  [ ! -s "$BATS_TEST_TMPDIR/tmux.argv" ] || { cat "$BATS_TEST_TMPDIR/tmux.argv"; false; }
  [ ! -s "$LR_FAKE_CA_LOG" ]                      # not even probed: the holder check comes first (K5)
  grep -q "REQUEST-RETIRED $SID — capacity queue: a live holder runs it (pane 28, pid $$)" "$PSTATE/poller.log" || { plog; false; }
  [ ! -e "$PREQ" ]
  [ -f "$PSTATE/claimed/$SID.cc-lr.recovered.json" ]
}

@test "capacity lane CONTROL: the same beat naming a DEAD pid is no holder — the lane goes on to probe" {
  cap_lane_setup
  mkdir -p "$CC_BEAT_DIR"
  jq -n --arg sid "$SID" '{sid:$sid, pane:"28", pid:4194105, lstart:"Thu Jan  1 00:00:00 1970", t:1, kind:"prompt"}' > "$CC_BEAT_DIR/$SID.json"
  LR_FAKE_PROBE=refuse poll
  grep -q '^probe ' "$LR_FAKE_CA_LOG"
  [ -e "$PREQ" ]
}
