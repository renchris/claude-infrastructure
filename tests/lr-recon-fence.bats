#!/usr/bin/env bats
# scripts/limit-recover/lr-recon-fence.sh — the §C10 one-actuator-family predicate and the §C7
# mkdir lock helpers. One test per predicate branch, run under /bin/bash 3.2 explicitly because
# that is what hooks and the poller execute it with.
#
# HERMETIC: HOME, LR_STATE_DIR and LR_RECON_ROOT point into BATS_TEST_TMPDIR; the clock and the
# kernel wake time are seams (LR_RECON_NOW, LR_RECON_WAKETIME) so no verdict depends on when the
# machine last woke. The only processes touched are `sleep`s this file starts and kills itself.

SID="abcdef0123456789"
RID="recon:c1:abcdef01:1"
NOW=1790000500
OLD_PW=1790000000.1

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  S="$REPO/scripts/limit-recover/lr-recon-fence.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  export LR_STATE_DIR="$BATS_TEST_TMPDIR/lr"
  export LR_RECON_ROOT="$LR_STATE_DIR/recon"
  export LR_RECON_NOW="$NOW"
  export LR_RECON_WAKETIME=0
  unset LR_RECORD_ID LR_RECON_FENCE_FRESH_S
  mkdir -p "$HOME" "$LR_RECON_ROOT/owned"
  SLEEP_PID=""
}

teardown() {
  if [ -n "$SLEEP_PID" ]; then
    kill "$SLEEP_PID" 2>/dev/null || true
    wait "$SLEEP_PID" 2>/dev/null || true
  fi
}

lstart_of() {
  TZ=UTC LC_ALL=C ps -o lstart= -p "$1" | tr -s ' ' | sed -e 's/^ *//' -e 's/ *$//'
}

start_sleeper() {
  sleep 30 &
  SLEEP_PID=$!
  SLEEP_LSTART="$(lstart_of "$SLEEP_PID")"
  [ -n "$SLEEP_LSTART" ]
}

recon_on() { : >"$LR_STATE_DIR/recon.on"; }

# owned <role> <pid> <lstart> [...more triples]
owned() {
  local procs="" sep=""
  while [ $# -ge 3 ]; do
    procs="$procs$sep{\"role\":\"$1\",\"pid\":$2,\"lstart\":\"$3\",\"argv_hash\":\"\"}"
    sep=","
    shift 3
  done
  printf '{"record_id":"%s","attempt":1,"procs":[%s]}' "$RID" "$procs" >"$LR_RECON_ROOT/owned/$SID"
}

heartbeat() {
  printf '{"pid":1,"lstart":"Tue Sep 29 11:19:17 2026","progress":7,"wall":%s,"uptime_raw":12.0,"progress_wall":%s}' \
    "$1" "$1" >"$LR_RECON_ROOT/heartbeat"
}

defers() { run /bin/bash "$S" defers "$SID"; }

@test "statics: bash -n under /bin/bash 3.2 and shellcheck bare" {
  /bin/bash -n "$S"
  if ! command -v shellcheck >/dev/null 2>&1; then
    skip "shellcheck not installed"
  fi
  shellcheck "$S"
}

@test "recon.on absent ⇒ act (recon-off)" {
  owned actuator 1 x
  defers
  [ "$status" -eq 1 ]
  [[ "$output" == *"verdict=act sid=abcdef01 reason=recon-off"* ]]
}

@test "owned/<sid> absent ⇒ act (not-owned)" {
  recon_on
  defers
  [ "$status" -eq 1 ]
  [[ "$output" == *"reason=not-owned"* ]]
}

@test "caller's own record id ⇒ act (own-actuator), even with a fresh heartbeat" {
  recon_on; owned; heartbeat "$((NOW - 1))"
  LR_RECORD_ID="$RID" run /bin/bash "$S" defers "$SID"
  [ "$status" -eq 1 ]
  [[ "$output" == *"reason=own-actuator"* ]]
}

@test "fresh heartbeat ⇒ defer (heartbeat-fresh), stdout empty" {
  recon_on; owned; heartbeat "$((NOW - 100))"
  out="$(/bin/bash "$S" defers "$SID" 2>/dev/null)" && rc=0 || rc=$?
  [ "$rc" -eq 0 ]
  [ -z "$out" ]
  defers
  [[ "$output" == *"verdict=defer sid=abcdef01 reason=heartbeat-fresh"* ]]
}

@test "stale heartbeat + a live recorded proc ⇒ defer (proc-alive), stdout empty" {
  start_sleeper
  recon_on; owned watcher 1 never actuator "$SLEEP_PID" "$SLEEP_LSTART"; heartbeat "$OLD_PW"
  out="$(/bin/bash "$S" defers "$SID" 2>/dev/null)" && rc=0 || rc=$?
  [ "$rc" -eq 0 ]
  [ -z "$out" ]
  defers
  [[ "$output" == *"reason=proc-alive:actuator:$SLEEP_PID"* ]]
}

@test "stale heartbeat + dead recorded proc ⇒ act (lapsed)" {
  start_sleeper
  dead_pid="$SLEEP_PID"; dead_ls="$SLEEP_LSTART"
  kill "$dead_pid"; wait "$dead_pid" 2>/dev/null || true; SLEEP_PID=""
  recon_on; owned actuator "$dead_pid" "$dead_ls"; heartbeat "$OLD_PW"
  defers
  [ "$status" -eq 1 ]
  [[ "$output" == *"reason=lapsed"* ]]
}

@test "a wake 60 s ago restarts the clock on an old progress_wall ⇒ defer (sleep adjustment)" {
  recon_on; owned; heartbeat "$OLD_PW"
  LR_RECON_WAKETIME="$((NOW - 60))" run /bin/bash "$S" defers "$SID"
  [ "$status" -eq 0 ]
  [[ "$output" == *"reason=heartbeat-fresh"* ]] || false
  # control: the same tree without the wake is stale
  defers
  [ "$status" -eq 1 ]
}

@test "live pid with a mismatched lstart (pid reuse) ⇒ act (lapsed)" {
  start_sleeper
  recon_on; owned actuator "$SLEEP_PID" "Thu Jan  1 00:00:00 1970"; heartbeat "$OLD_PW"
  defers
  [ "$status" -eq 1 ]
  [[ "$output" == *"reason=lapsed"* ]]
}

@test "malformed owned ⇒ defer (owned-unreadable)" {
  recon_on; heartbeat "$OLD_PW"
  printf '{"record_id":"x","procs":[{"role":"a"' >"$LR_RECON_ROOT/owned/$SID"
  defers
  [ "$status" -eq 0 ]
  [[ "$output" == *"reason=owned-unreadable"* ]]
}

@test "unreadable heartbeat skips rule 4, it does not defer by itself" {
  recon_on; owned actuator 999999 "Tue Sep 29 11:19:17 2026"
  echo 'garbage' >"$LR_RECON_ROOT/heartbeat"
  defers
  [ "$status" -eq 1 ]
  [[ "$output" == *"reason=lapsed"* ]]
}

@test "sourcing defines functions only and leaks no errexit" {
  run /bin/bash -c '. "$1"; case $- in *e*) echo LEAK;; esac; type lr_recon_defers >/dev/null && echo OK' _ "$S"
  [ "$status" -eq 0 ]
  [ "$output" = "OK" ]
}

@test "lock: take ⇒ 0 and a compact holder naming the taker" {
  L="$LR_STATE_DIR/locks/$SID.launch"
  run /bin/bash "$S" lock-take "$L" "$RID" 2 watcher "$$"
  [ "$status" -eq 0 ]
  holder="$(cat "$L/holder")"
  [[ "$holder" == "{\"record_id\":\"$RID\",\"attempt\":2,\"role\":\"watcher\",\"pid\":$$,\"lstart\":\"$(lstart_of $$)\",\"at\":"*".0}" ]]
}

@test "lock: held by a live holder ⇒ 1, holder untouched" {
  L="$LR_STATE_DIR/locks/$SID.launch"
  /bin/bash "$S" lock-take "$L" r1 1 watcher "$$"
  before="$(cat "$L/holder")"
  run /bin/bash "$S" lock-take "$L" r2 1 actuator
  [ "$status" -eq 1 ]
  [ "$(cat "$L/holder")" = "$before" ]
}

@test "lock: a dead holder's exact (pid, lstart) is stolen at once" {
  start_sleeper
  L="$LR_STATE_DIR/locks/$SID.launch"
  /bin/bash "$S" lock-take "$L" r1 1 watcher "$SLEEP_PID"
  kill "$SLEEP_PID"; wait "$SLEEP_PID" 2>/dev/null || true; SLEEP_PID=""
  run /bin/bash "$S" lock-take "$L" r2 1 actuator "$$"
  [ "$status" -eq 0 ]
  [[ "$(cat "$L/holder")" == *"\"record_id\":\"r2\""*"\"pid\":$$,"* ]] || false
  [ -z "$(ls -d "$L".stolen.* 2>/dev/null)" ]
}

@test "lock: release removes only a lock whose holder names the pid" {
  L="$LR_STATE_DIR/locks/$SID.launch"
  /bin/bash "$S" lock-take "$L" r1 1 watcher "$$"
  run /bin/bash "$S" lock-release "$L"
  [ "$status" -eq 1 ]
  [ -d "$L" ]
  run /bin/bash "$S" lock-release "$L" "$$"
  [ "$status" -eq 0 ]
  [ ! -e "$L" ]
}

@test "lstart contract: collapsed form written, double-spaced date still matches (\"Sep  9\" = \"Sep 9\")" {
  start_sleeper
  [[ "$SLEEP_LSTART" != *"  "* ]] || false
  doubled="$(printf '%s' "$SLEEP_LSTART" | sed 's/ /  /')"
  [[ "$doubled" == *"  "* ]] || false
  run /bin/bash "$S" proc-alive "$SLEEP_PID" "$doubled"
  [ "$status" -eq 0 ]
  run /bin/bash -c '. "$1"; _lr_recon_lstart_norm "Wed Sep  9 01:02:03 2026  "' _ "$S"
  [ "$output" = "Wed Sep 9 01:02:03 2026" ]
  L="$LR_STATE_DIR/locks/$SID.launch"
  /bin/bash "$S" lock-take "$L" r1 1 watcher "$SLEEP_PID"
  [[ "$(cat "$L/holder")" == *"\"lstart\":\"$SLEEP_LSTART\""* ]] || false
  [[ "$(cat "$L/holder")" != *"  "* ]]
}

# ── W4 caller helpers: lr_recon_may_act / lr_recon_act_done / lr_recon_live ───────────────────────
# Each case runs in one /bin/bash so the exported LR_LAUNCH_LOCK and the release see the same $$.

@test "may_act: recon off acts with no lock; live is false" {
  run /bin/bash -c ". '$S'; lr_recon_may_act '$SID' t; echo rc=\$? lock=[\$LR_LAUNCH_LOCK]; lr_recon_live; echo live=\$?"
  [[ "$output" == *"rc=0 lock=[]"* ]] || false
  [[ "$output" == *"live=1"* ]] || false
  [ ! -e "$LR_STATE_DIR/locks/$SID.launch" ]
}

@test "may_act: fresh heartbeat defers and takes no lock; live is true" {
  recon_on; owned; heartbeat "$((NOW - 10)).0"
  run /bin/bash -c ". '$S'; lr_recon_may_act '$SID' t; echo rc=\$?; lr_recon_live; echo live=\$?"
  [[ "$output" == *"rc=1"* ]] || false
  [[ "$output" == *"gate=defer"* ]] || false
  [[ "$output" == *"live=0"* ]] || false
  [ ! -e "$LR_STATE_DIR/locks/$SID.launch" ]
}

@test "may_act: lapsed acts only under the launch lock, holder names the caller, done releases it" {
  recon_on; owned; heartbeat "$OLD_PW"
  run /bin/bash -c ". '$S'; lr_recon_may_act '$SID' t; echo rc=\$? me=\$\$; cat \"\$LR_LAUNCH_LOCK/holder\"; echo; lr_recon_act_done; lr_recon_act_done; ls '$LR_STATE_DIR/locks'"
  [[ "$output" == *"rc=0"* ]] || false
  [[ "$output" == *"lock=taken"* ]] || false
  me="$(printf '%s\n' "$output" | sed -n 's/.*me=\([0-9]*\).*/\1/p')"
  [[ "$output" == *"\"pid\":$me,"* ]] || false
  [ ! -e "$LR_STATE_DIR/locks/$SID.launch" ]
  grep -q "	$SID	t	taken	" "$LR_RECON_ROOT/launch.log"
}

@test "launch.log: a reconciler actuator's take carries its attempt and record; a legacy one does not (W5 audit)" {
  recon_on; owned; heartbeat "$OLD_PW"
  LR_ATTEMPT=3 LR_RECORD_ID=recon:c:x:1 /bin/bash -c ". '$S'; lr_recon_may_act '$SID' t; lr_recon_act_done" >/dev/null 2>&1
  /bin/bash -c "unset LR_ATTEMPT LR_RECORD_ID; . '$S'; lr_recon_may_act '$SID' u; lr_recon_act_done" >/dev/null 2>&1
  grep -q "	$SID	t	taken	pid=[0-9]*	attempt=3	record=recon:c:x:1\$" "$LR_RECON_ROOT/launch.log"
  grep -q "	$SID	u	taken	pid=[0-9]*\$" "$LR_RECON_ROOT/launch.log"
}

@test "may_act: a launch lock held by a live other process defers" {
  recon_on; owned; heartbeat "$OLD_PW"; start_sleeper
  /bin/bash -c ". '$S'; lr_recon_lock_take '$LR_STATE_DIR/locks/$SID.launch' other 0 x '$SLEEP_PID'"
  run /bin/bash -c ". '$S'; lr_recon_may_act '$SID' t; echo rc=\$?"
  [[ "$output" == *"rc=1"* ]] || false
  [[ "$output" == *"lock=held"* ]]
}

@test "may_act: always takes the lock with the reconciler off" {
  run /bin/bash -c ". '$S'; lr_recon_may_act '$SID' t always; echo rc=\$? lock=\$LR_LAUNCH_LOCK"
  [[ "$output" == *"rc=0 lock=$LR_STATE_DIR/locks/$SID.launch"* ]]
}

@test "may_act: a child inherits its parent's live lock and never releases it" {
  recon_on; owned; heartbeat "$OLD_PW"
  run /bin/bash -c ". '$S'; lr_recon_may_act '$SID' parent || exit 9
    /bin/bash -c \". '$S'; lr_recon_may_act '$SID' child; echo child=\\\$?; lr_recon_act_done\"
    if [ -d \"\$LR_LAUNCH_LOCK\" ]; then echo still-held; fi; lr_recon_act_done; if [ ! -d '$LR_STATE_DIR/locks/$SID.launch' ]; then echo released; fi"
  [[ "$output" == *"lock=inherited"* ]] || false
  [[ "$output" == *"child=0"* ]] || false
  [[ "$output" == *"still-held"* ]] || false
  [[ "$output" == *"released"* ]] || false
}

@test "may_act: the fence's own defer outranks an inherited lock" {
  recon_on; owned; heartbeat "$((NOW - 10)).0"
  mkdir -p "$LR_STATE_DIR/locks/$SID.launch"
  run /bin/bash -c ". '$S'; LR_LAUNCH_LOCK='$LR_STATE_DIR/locks/$SID.launch'; export LR_LAUNCH_LOCK; lr_recon_may_act '$SID' c; echo rc=\$?"
  [[ "$output" == *"rc=1"* ]]
}
