#!/usr/bin/env bats
# scripts/limit-recover/lr-fleet.sh — the §C10 fence at its call sites (LIMIT_RECOVER_FLEET_V2 W4):
# lf_one asks lr_recon_may_act before any lock, rank or probe, and --enqueue writes the cc-lr
# request origin the reconciler and the poller both drain.
#
# HERMETIC: HOME, LR_STATE_DIR, LR_RECON_ROOT, the registry and the transcript stores all live in
# BATS_TEST_TMPDIR; lr-handoff and claude-accounts are PATH-free stubs through the seams lr-fleet
# already has (LR_HANDOFF_BIN, CC_ACCOUNTS_BIN). The clock and the wake time are fence seams, so no
# verdict depends on when the machine last woke. The only process touched is a `sleep` this file
# starts and kills itself. Nothing here types into a pane.

NOW=1790000500

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  FLEET="$REPO/scripts/limit-recover/lr-fleet.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/bin"
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg"; mkdir -p "$CC_REGISTRY_DIR"
  export LR_STATE_DIR="$BATS_TEST_TMPDIR/state"; mkdir -p "$LR_STATE_DIR/locks"
  export LR_RECON_ROOT="$LR_STATE_DIR/recon"; mkdir -p "$LR_RECON_ROOT/owned"
  export LR_RECON_NOW="$NOW" LR_RECON_WAKETIME=0
  unset LR_RECORD_ID LR_RECON_FENCE_FRESH_S LR_LAUNCH_LOCK
  export CC_ADMIT_GATE=off CC_FIRE_CAPACITY_GATE=off
  export CC_ACCOUNT_MAP="$BATS_TEST_TMPDIR/absent-map"
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/sweep.stamp"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-lock"
  unset CC_PANE_CMD_DIR CC_PANE_CMD_INTERACTIVE CC_PANE_CMD
  export LR_RECOVER_MAX_CONCURRENT=1 LR_POOL_POLL_S=0.05 LR_ADMIT_LOCK_WAIT_S=20
  export LF_SLOW_SCAN=1
  SEC="$HOME/.claude-secondary"; TER="$HOME/.claude-tertiary"
  SLUG="-Users-x-thing"; mkdir -p "$SEC/projects/$SLUG" "$TER/projects/$SLUG"
  export LR_CONFIG_DIRS="$SEC:$TER"
  CWD="$BATS_TEST_TMPDIR/wt"; mkdir -p "$CWD"
  # Per-test tail: lr-lib greps the REAL process table for `--resume <sid>`, so a sid shared with a
  # concurrent run of any suite would read as a second holder (tests/lr-fleet.bats setup says why).
  SID="7e11ce00-17e8-40f6-a54f-$(printf '%012d' "$(printf '%s' "$BATS_TEST_TMPDIR" | cksum | cut -d' ' -f1)")"
  # The actuator stub records what it was handed AND the lock it runs under: the fence's whole
  # contract at this site is "the actuator never runs on DEFER, and on a lapsed ACT it runs holding
  # locks/<sid>.launch taken by its caller".
  export LR_HANDOFF_BIN="$BATS_TEST_TMPDIR/lr-handoff"
  export LRH_LOG="$BATS_TEST_TMPDIR/lrh.log" LRH_ENV="$BATS_TEST_TMPDIR/lrh.env"
  : > "$LRH_LOG"
  cat > "$LR_HANDOFF_BIN" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >> "$LRH_LOG"
{
  printf 'lock=%s\n' "${LR_LAUNCH_LOCK:-}"
  [ -n "${LR_LAUNCH_LOCK:-}" ] && printf 'holder=%s\n' "$(cat "$LR_LAUNCH_LOCK/holder" 2>/dev/null)"
  printf 'ppid=%s\n' "$PPID"
  printf 'gppid=%s\n' "$(ps -o ppid= -p "$PPID" | tr -d ' ')"
} > "$LRH_ENV"
echo "lr-handoff: recycled IN PLACE — pane X continues session Y" >&2
echo "/bundle/path"
exit 0
SH
  chmod +x "$LR_HANDOFF_BIN"
  export CC_ACCOUNTS_BIN="$HOME/bin/claude-accounts"
  printf '#!/bin/bash\ncase "$*" in *--rank*) printf "next2 0.9\\nnext3 0.8\\n" ;; esac\n' > "$CC_ACCOUNTS_BIN"
  chmod +x "$CC_ACCOUNTS_BIN"
  SLEEP_PID=""
}

teardown() {
  if [ -n "$SLEEP_PID" ]; then
    kill "$SLEEP_PID" 2>/dev/null || true
    wait "$SLEEP_PID" 2>/dev/null || true
  fi
}

blocked_tx() { # $1=store $2=sid
  local f="$1/projects/$SLUG/$2.jsonl"
  printf '{"type":"user","cwd":"%s","timestamp":"2026-09-08T22:00:00.000Z","message":{"role":"user","content":"go"}}\n' "$CWD" > "$f"
  printf '{"type":"assistant","timestamp":"2026-09-08T22:30:00.000Z","effort":"high","message":{"role":"assistant","model":"claude-opus-5-5","content":[{"type":"text","text":"work"}]}}\n' >> "$f"
  printf '{"type":"assistant","timestamp":"2026-09-08T23:11:09.000Z","isApiErrorMessage":true,"message":{"role":"assistant","content":[{"type":"text","text":"You'"'"'ve hit your session limit · resets 7:50pm"}]}}\n' >> "$f"
}
row() { printf '{"paneUUID":"%s","session_id":"%s","pid":%d,"account":"claude-secondary","cwd":"%s"}\n' "$1" "$2" "$$" "$CWD" > "$CC_REGISTRY_DIR/$1.json"; }
lstart_of() { TZ=UTC LC_ALL=C ps -o lstart= -p "$1" | tr -s ' ' | sed -e 's/^ *//' -e 's/ *$//'; }
recon_on() { : > "$LR_STATE_DIR/recon.on"; }
heartbeat() { printf '{"pid":1,"progress":7,"progress_wall":%s}' "$1" > "$LR_RECON_ROOT/heartbeat"; }
owned() { # $1=pid $2=lstart
  printf '{"record_id":"r1","procs":[{"role":"x","pid":%s,"lstart":"%s"}]}' "$1" "$2" > "$LR_RECON_ROOT/owned/$SID"
}
one() { run bash "$FLEET" --one "$SID" --target next3 --source-pane 616; }
results() { cat "$LR_STATE_DIR"/fleet/*/results.tsv 2>/dev/null; }

@test "statics: lr-fleet.sh parses under /bin/bash 3.2" {
  /bin/bash -n "$FLEET"
}

@test "(a) recon.on + owned + fresh heartbeat: lf_one DEFERS — the actuator is never called" {
  blocked_tx "$SEC" "$SID"; row 616 "$SID"
  recon_on; heartbeat "$NOW"; owned 1 "Thu Jan 1 00:00:00 1970"
  one
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [ ! -s "$LRH_LOG" ] || { cat "$LRH_LOG"; false; }
  [[ "$(results)" == *"$SID	616	616	"*"	reconciler/DEFERRED	reconciler owns it	"* ]] || { results; false; }
  [[ "$output" == *"reason=heartbeat-fresh"* ]] || { echo "$output"; false; }
  [ ! -d "$LR_STATE_DIR/locks/$SID.launch" ]
}

@test "(b) stale heartbeat + an owned proc alive: lf_one DEFERS" {
  blocked_tx "$SEC" "$SID"; row 616 "$SID"
  sleep 300 & SLEEP_PID=$!
  recon_on; heartbeat $((NOW - 1000)); owned "$SLEEP_PID" "$(lstart_of "$SLEEP_PID")"
  one
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [ ! -s "$LRH_LOG" ] || { cat "$LRH_LOG"; false; }
  [[ "$output" == *"reason=proc-alive:x:$SLEEP_PID"* ]] || { echo "$output"; false; }
  [[ "$(results)" == *"reconciler/DEFERRED"* ]] || { results; false; }
}

@test "(c) stale heartbeat + owned proc dead (lapsed): acts under the launch lock its caller holds, released after" {
  blocked_tx "$SEC" "$SID"; row 616 "$SID"
  recon_on; heartbeat $((NOW - 1000)); owned 1 "Thu Jan 1 00:00:00 1970"
  one
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -q -- "--sid $SID " "$LRH_LOG" || { cat "$LRH_LOG"; false; }
  lock="$(sed -n 's/^lock=//p' "$LRH_ENV")"
  [ "$lock" = "$LR_STATE_DIR/locks/$SID.launch" ] || { cat "$LRH_ENV"; false; }
  hpid="$(sed -n 's/^holder=.*"pid":\([0-9]*\)[,}].*/\1/p' "$LRH_ENV")"
  ppid="$(sed -n 's/^ppid=//p' "$LRH_ENV")"; gppid="$(sed -n 's/^gppid=//p' "$LRH_ENV")"
  # The holder is lr-fleet itself: the stub's parent, or its grandparent when bash forks a
  # subshell for the command substitution rather than exec'ing the stub in it.
  [ -n "$hpid" ] && { [ "$hpid" = "$ppid" ] || [ "$hpid" = "$gppid" ]; } || { cat "$LRH_ENV"; false; }
  [[ "$output" == *"gate=act sid=${SID:0:8} role=lr-fleet lock=taken"* ]] || { echo "$output"; false; }
  [ ! -e "$LR_STATE_DIR/locks/$SID.launch" ] || { ls -la "$LR_STATE_DIR/locks"; false; }
}

@test "(d) recon.on absent: lf_one acts exactly as before, with no launch lock" {
  blocked_tx "$SEC" "$SID"; row 616 "$SID"
  heartbeat "$NOW"; owned 1 "Thu Jan 1 00:00:00 1970"
  one
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -q -- "--sid $SID --config-dir $SEC --cwd $CWD --target next3 --launch --in-place --source-pane 616" "$LRH_LOG" || { cat "$LRH_LOG"; false; }
  [ "$(sed -n 's/^lock=//p' "$LRH_ENV")" = "" ] || { cat "$LRH_ENV"; false; }
  [[ "$(results)" == *"recycle-in-place/RECOVERED"* ]] || { results; false; }
  [ -z "$(ls -A "$LR_STATE_DIR/locks")" ]
}

@test "--recover: a DEFERRED sid is owed nothing by the run — COMPLETE, not a gap" {
  blocked_tx "$SEC" "$SID"; row 616 "$SID"
  recon_on; heartbeat "$NOW"; owned 1 "Thu Jan 1 00:00:00 1970"
  run bash "$FLEET" --recover
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ ! -s "$LRH_LOG" ] || { cat "$LRH_LOG"; false; }
  [[ "$output" == *"RECOVERY COMPLETE"*"1 not owed"* ]] || { echo "$output"; false; }
}

@test "--enqueue writes the cc-lr origin <sid>.cc-lr.json with sid, at and requested_by — atomically" {
  blocked_tx "$SEC" "$SID"; row 616 "$SID"
  run bash "$FLEET" --enqueue --target next3
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  req="$LR_STATE_DIR/requests/$SID.cc-lr.json"
  [ -f "$req" ] || { echo "$output"; ls -la "$LR_STATE_DIR/requests"; false; }
  [ ! -e "$LR_STATE_DIR/requests/$SID.json" ]
  python3 - "$req" "$SID" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["sid"] == sys.argv[2], d
assert isinstance(d["at"], int) and d["at"] > 1700000000, d
assert d["requested_by"] == "lr-fleet --enqueue", d
assert d["target"] == "next3" and d["source_pane"] == "616", d
PY
  [ -z "$(find "$LR_STATE_DIR/requests" -name '*.tmp.*')" ]
  [[ "$output" == *"launchctl kickstart gui/"* ]] || { echo "$output"; false; }
}
