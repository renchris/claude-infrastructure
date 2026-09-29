#!/usr/bin/env bats
# lr-transplant.sh custody phases — unconfirm, fold-stub, abort, link-then-unlink, record-id claims.
#
# Custody is the part of limit-recover that can lose a transcript, so every refusal below is checked
# the same way: shasum every file before, run, shasum after, and demand byte identity. Fixtures come
# from the REAL writer (`--phase admit`), and a holder is a real process: a `sleep` whose pid and
# `ps -o lstart=` are written into <cfg>/sessions/<n>.json, exactly the shape the harness writes.
# A dead holder is a process that was started, sampled and waited on.

bats_require_minimum_version 1.5.0

setup() {
  T="$BATS_TEST_TMPDIR"
  export HOME="$T/home"
  export LR_STATE_DIR="$HOME/.reso/limit-recover"
  unset LR_CONFIG_DIRS LR_RECORD_ID LR_ATTEMPT LR_HOLDER_PID HF_WATCHER_RECORD LR_NOW LR_LOCK_TTL_S LR_LOCK_SLACK_S
  mkdir -p "$LR_STATE_DIR/locks" "$T/from/projects/slug" "$T/to/projects/slug"
  SID=11111111-2222-3333-4444-555555555555
  SRC="$T/from/projects/slug/$SID.jsonl"
  RET="$SRC.handed-off"
  DST="$T/to/projects/slug/$SID.jsonl"
  TOMB="$T/from/projects/slug/$SID.HANDOFF.json"
  LOCK="$LR_STATE_DIR/locks/$SID.lock"
  ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LRT="$ROOT/scripts/limit-recover/lr-transplant.sh"
  LRL="$ROOT/scripts/limit-recover/lr-lock.py"
  printf '{"type":"user","uuid":"a1"}\n{"type":"assistant","uuid":"a2"}\n' > "$SRC"
  HOLDER_PIDS=""
}

teardown() {
  local p
  for p in $HOLDER_PIDS; do kill "$p" 2>/dev/null || true; done
}

_lstart() { TZ=UTC LC_ALL=C ps -o lstart= -p "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'; }
_live() { # → LIVE_PID / LIVE_LSTART: a running process, killed in teardown
  sleep 300 >/dev/null 2>&1 3>&- &
  LIVE_PID=$!
  HOLDER_PIDS="$HOLDER_PIDS $LIVE_PID"
  LIVE_LSTART="$(_lstart "$LIVE_PID")"
}
_dead() { # → DEAD_PID / DEAD_LSTART: a process that ran and has been reaped
  sleep 0.2 >/dev/null 2>&1 3>&- &
  DEAD_PID=$!
  DEAD_LSTART="$(_lstart "$DEAD_PID")"
  wait "$DEAD_PID" || true
}
_register() { # <cfg> <name> <pid> <lstart> → a sessions/*.json naming $SID
  mkdir -p "$1/sessions"
  printf '{"pid":%s,"sessionId":"%s","procStart":"%s","cwd":"/tmp"}\n' "$3" "$SID" "$4" > "$1/sessions/$2.json"
}
_admit() { run bash "$LRT" --phase admit --sid "$SID" --from "$T/from" --to "$T/to" "$@"; }
_phase() { local p="$1"; shift; run --separate-stderr bash "$LRT" --phase "$p" --sid "$SID" --from "$T/from" --to "$T/to" "$@"; }
_sha() { shasum -a 256 "$1" | cut -d' ' -f1; }
_field() { # <key> → that field of the JSON on stdout (the whole of it, else its last line)
  printf '%s\n' "$output" | python3 -c 'import json,sys
s=sys.stdin.read().strip()
try: d=json.loads(s)
except ValueError: d=json.loads(s.splitlines()[-1])
v=d.get(sys.argv[1]); print("" if v is None else v)' "$1"
}
_lockf() { python3 -c 'import json,sys;d=json.load(open(sys.argv[1]))
for k in sys.argv[2].split("."): d=d.get(k) if isinstance(d,dict) else None
print("" if d is None else d)' "$LOCK" "$1"; }
_snap() { local f; for f in "$@"; do if [[ -e "$f" ]]; then _sha "$f"; else echo "absent $f"; fi; done; }
_confirmed() { # admit + confirm: the source retired, the target a full copy
  _admit; [ "$status" -eq 0 ] || { echo "$output"; false; }
  _phase confirm; [ "$status" -eq 0 ] || { echo "$output $stderr"; false; }
  [ -f "$RET" ] && [ ! -e "$SRC" ]
}

@test "custody 1: confirm with a stub beside .handed-off refuses stub-beside-retired and touches nothing" {
  _confirmed
  printf '{"type":"assistant","uuid":"tail1"}\n' > "$SRC"
  local before; before="$(_snap "$RET" "$SRC" "$DST" "$TOMB" "$LOCK")"
  _phase confirm
  [ "$status" -eq 2 ] || { echo "$output $stderr"; false; }
  [ "$(_field reason)" = stub-beside-retired ] || { echo "$output"; false; }
  [[ "$stderr" == *"REFUSED (stub-beside-retired)"* ]] || { echo "$stderr"; false; }
  [ "$(_snap "$RET" "$SRC" "$DST" "$TOMB" "$LOCK")" = "$before" ] || { echo "a refusal changed a file"; false; }
}

@test "custody 2: confirm's retire never overwrites a .handed-off that is already there" {
  _admit; [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf 'planted\n' > "$RET"
  local planted src; planted="$(_sha "$RET")"; src="$(_sha "$SRC")"
  _phase confirm
  [ "$status" -eq 2 ] || { echo "$output $stderr"; false; }
  [ "$(_field reason)" = stub-beside-retired ] || { echo "$output"; false; }
  [ "$(_sha "$RET")" = "$planted" ] || { echo "the planted .handed-off was overwritten"; false; }
  [ "$(_sha "$SRC")" = "$src" ] || { echo "the source changed"; false; }
}

@test "custody 3: unconfirm restores a live source, files the target copy as evidence, drops the lock" {
  local pre; pre="$(_sha "$SRC")"
  _confirmed
  _live; _register "$T/from" s1 "$LIVE_PID" "$LIVE_LSTART"
  _phase unconfirm
  [ "$status" -eq 0 ] || { echo "$output $stderr"; false; }
  [ -f "$SRC" ] || { echo "the source was not restored"; false; }
  [ ! -e "$RET" ] || { echo "the source was not restored"; false; }
  [ "$(_sha "$SRC")" = "$pre" ] || { echo "the restored source differs from the pre-confirm source"; false; }
  [ ! -e "$DST" ] || { echo "the target copy is still resumable"; false; }
  local ev; ev="$(_field evidence)"
  [[ "$ev" == "$LR_STATE_DIR/locks/$SID.unconfirmed-"* ]] || { echo "evidence=$ev"; false; }
  [ -f "$ev/$SID.jsonl" ] || { echo "no target copy in $ev"; false; }
  [ ! -e "$LOCK" ] || { echo "the lock survived"; false; }
  [ -f "$TOMB.unconfirmed" ] || { echo "the tombstone was not retired"; false; }
  [ ! -e "$TOMB" ] || { echo "the tombstone was not retired"; false; }
  _phase unconfirm
  [ "$status" -eq 0 ] && [ "$(_field already_unconfirmed)" = True ] || { echo "re-run: $output $stderr"; false; }
}

@test "custody 4: unconfirm with a stub present refuses stub-present, every file byte-identical" {
  _confirmed
  _live; _register "$T/from" s1 "$LIVE_PID" "$LIVE_LSTART"
  printf '{"type":"assistant","uuid":"tail1"}\n' > "$SRC"
  local before; before="$(_snap "$RET" "$SRC" "$DST" "$TOMB" "$LOCK")"
  _phase unconfirm
  [ "$status" -eq 2 ] || { echo "$output $stderr"; false; }
  [ "$(_field reason)" = stub-present ] || { echo "$output"; false; }
  [ "$(_snap "$RET" "$SRC" "$DST" "$TOMB" "$LOCK")" = "$before" ] || { echo "a refusal changed a file"; false; }
}

@test "custody 4b: unconfirm refuses source-dead for a dead source and target-held for a held target" {
  _confirmed
  _dead; _register "$T/from" s1 "$DEAD_PID" "$DEAD_LSTART"
  local before; before="$(_snap "$RET" "$DST" "$TOMB" "$LOCK")"
  _phase unconfirm
  [ "$status" -eq 2 ] || { echo "$output $stderr"; false; }
  [ "$(_field reason)" = source-dead ] || { echo "$output $stderr"; false; }
  _live; _register "$T/from" s1 "$LIVE_PID" "$LIVE_LSTART"
  _register "$T/to" s2 "$LIVE_PID" "$LIVE_LSTART"
  _phase unconfirm
  [ "$status" -eq 2 ] || { echo "$output $stderr"; false; }
  [ "$(_field reason)" = target-held ] || { echo "$output $stderr"; false; }
  [ "$(_snap "$RET" "$DST" "$TOMB" "$LOCK")" = "$before" ] || { echo "a refusal changed a file"; false; }
}

@test "custody 5: fold-stub appends the stub to both copies, they match, and the stub is gone" {
  _confirmed
  printf '{"type":"assistant","uuid":"tail1"}\n' > "$SRC"
  local expect; expect="$(cat "$RET" "$SRC" | shasum -a 256 | cut -d' ' -f1)"
  _phase fold-stub
  [ "$status" -eq 0 ] || { echo "$output $stderr"; false; }
  [ ! -e "$SRC" ] || { echo "the stub survived"; false; }
  [ "$(_sha "$DST")" = "$(_sha "$RET")" ] || { echo "target and retired differ"; false; }
  [ "$(_sha "$RET")" = "$expect" ] || { echo "the retired copy is not old ∥ stub"; false; }
  [ "$(_field sha256)" = "$expect" ] || { echo "$output"; false; }
  [ "$(_field confirm_len)" = "$(wc -c < "$DST" | tr -d ' ')" ] || { echo "$output"; false; }
  _phase fold-stub
  [ "$status" -eq 0 ] && [ "$(_field nothing_to_fold)" = True ] || { echo "$output"; false; }
}

@test "custody 5b: fold-stub finishes a fold that crashed after the retired append only" {
  _confirmed
  printf '{"type":"assistant","uuid":"tail1"}\n' > "$SRC"
  cat "$SRC" >> "$RET"                      # the crash: R got the stub, T did not
  _phase fold-stub
  [ "$status" -eq 0 ] || { echo "$output $stderr"; false; }
  [ "$(_sha "$DST")" = "$(_sha "$RET")" ] || { echo "target and retired differ"; false; }
  [ "$(grep -c tail1 "$RET")" -eq 1 ] || { echo "the stub was appended twice"; false; }
}

@test "custody 6: fold-stub refuses when a resume wrote to the target, nothing changed" {
  _confirmed
  printf '{"type":"assistant","uuid":"tail1"}\n' > "$SRC"
  printf '{"type":"assistant","uuid":"resumed"}\n' >> "$DST"
  local before; before="$(_snap "$RET" "$SRC" "$DST" "$LOCK")"
  _phase fold-stub
  [ "$status" -eq 2 ] || { echo "$output $stderr"; false; }
  [ "$(_field reason)" = target-held ] || { echo "$output"; false; }
  [ "$(_field detail)" = target-advanced ] || { echo "$output"; false; }
  [ "$(_snap "$RET" "$SRC" "$DST" "$LOCK")" = "$before" ] || { echo "a refusal changed a file"; false; }
}

@test "custody 7: a same-target admit by another record refuses while its actuator lives, takes over once dead" {
  _live
  LR_HOLDER_PID="$LIVE_PID" LR_ATTEMPT=1 _admit --record-id R1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(_lockf record_id)" = R1 ] || { cat "$LOCK"; false; }
  [ "$(_lockf holder.pid)" = "$LIVE_PID" ] || { cat "$LOCK"; false; }
  [ "$(_lockf holder.attempt)" = 1 ] || { cat "$LOCK"; false; }
  [ "$(_lockf holder.role)" = actuator ] || { cat "$LOCK"; false; }
  local lock_before; lock_before="$(cat "$LOCK")"
  _phase admit --record-id R2
  [ "$status" -eq 2 ] || { echo "$output $stderr"; false; }
  [ "$(_field reason)" = lock-mismatch ] || { echo "$output"; false; }
  [ "$(_field detail)" = live-actuator ] || { echo "$output"; false; }
  [ "$(cat "$LOCK")" = "$lock_before" ] || { echo "a refusal rewrote the lock"; false; }
  # control: the same claim once its actuator is gone
  kill "$LIVE_PID" 2>/dev/null || true; wait "$LIVE_PID" 2>/dev/null || true
  _phase admit --record-id R2
  [ "$status" -eq 0 ] || { echo "$output $stderr"; false; }
  [ "$(_field already_transplanted)" = True ] || { echo "$output"; false; }
  [ "$(_lockf record_id)" = R2 ] || { cat "$LOCK"; false; }
  [ "$(_lockf holder.record_id)" = R2 ] || { cat "$LOCK"; false; }
  [ "$(_lockf owner)" = "$(cd "$T/to" && pwd)" ] || { cat "$LOCK"; false; }
}

@test "custody 8: abort refuses while the recorded actuator lives; once dead it files the target and keeps the source" {
  _live
  LR_HOLDER_PID="$LIVE_PID" _admit --record-id R1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  local before src; before="$(_snap "$SRC" "$DST" "$TOMB" "$LOCK")"; src="$(_sha "$SRC")"
  _phase abort --record-id R1
  [ "$status" -eq 2 ] || { echo "$output $stderr"; false; }
  [ "$(_field reason)" = target-held ] || { echo "$output"; false; }
  [ "$(_field detail)" = live-actuator ] || { echo "$output"; false; }
  [ "$(_snap "$SRC" "$DST" "$TOMB" "$LOCK")" = "$before" ] || { echo "a refusal changed a file"; false; }
  # control: a dead recorded actuator
  kill "$LIVE_PID" 2>/dev/null || true; wait "$LIVE_PID" 2>/dev/null || true
  _phase abort --record-id R1
  [ "$status" -eq 0 ] || { echo "$output $stderr"; false; }
  local ev; ev="$(_field evidence)"
  [[ "$ev" == "$LR_STATE_DIR/locks/$SID.aborted-"* ]] || { echo "evidence=$ev"; false; }
  [ -f "$ev/$SID.jsonl" ] || { echo "evidence=$ev"; false; }
  [ ! -e "$DST" ] || { echo "target or lock survived"; false; }
  [ ! -e "$LOCK" ] || { echo "target or lock survived"; false; }
  [ "$(_sha "$SRC")" = "$src" ] || { echo "abort touched the source"; false; }
  [ -f "$TOMB.aborted" ] || { echo "the tombstone was not retired"; false; }
  [ ! -e "$TOMB" ] || { echo "the tombstone was not retired"; false; }
  _phase abort --record-id R1
  [ "$status" -eq 0 ] && [ "$(_field already_aborted)" = True ] || { echo "$output"; false; }
}

@test "custody 8b: abort refuses a live watcher and a retired source" {
  _admit; [ "$status" -eq 0 ] || { echo "$output"; false; }
  _live
  printf '{"pid":%s,"lstart":"%s"}\n' "$LIVE_PID" "$LIVE_LSTART" > "$T/watcher.json"
  _phase abort --watcher-record "$T/watcher.json"
  [ "$status" -eq 2 ] || { echo "$output $stderr"; false; }
  [ "$(_field detail)" = live-watcher ] || { echo "$output $stderr"; false; }
  _phase confirm; [ "$status" -eq 0 ] || { echo "$output $stderr"; false; }
  _phase abort
  [ "$status" -eq 2 ] || { echo "$output $stderr"; false; }
  [ "$(_field reason)" = lock-mismatch ] || { echo "$output $stderr"; false; }
  [ "$(_field detail)" = source-retired ] || { echo "$output $stderr"; false; }
}

@test "custody 8c: a live watcher recorded with padded lstart spacing is still live" {
  # `ps` pads a one-digit day (`Sep  9`) and the lr_recon store writes it collapsed; either writer's
  # form must read as the SAME live process, or abort would move a target a live watcher still owns.
  _admit; [ "$status" -eq 0 ] || { echo "$output"; false; }
  _live
  printf '{"pid":%s,"lstart":"  %s "}\n' "$LIVE_PID" "${LIVE_LSTART// /  }" > "$T/watcher.json"
  _phase abort --watcher-record "$T/watcher.json"
  [ "$status" -eq 2 ] || { echo "$output $stderr"; false; }
  [ "$(_field detail)" = live-watcher ] || { echo "$output $stderr"; false; }
  [ -e "$DST" ] || { echo "abort moved the target of a live watcher"; false; }
}

@test "custody 9: lr-lock classifies a stub beside the retired transcript as CUSTODY and reap keeps it" {
  _confirmed
  printf '{"type":"assistant","uuid":"tail1"}\n' > "$SRC"
  local ts; ts="$(python3 -c 'import json,sys,calendar,time;print(calendar.timegm(time.strptime(json.load(open(sys.argv[1]))["ts"],"%Y-%m-%dT%H:%M:%SZ")))' "$LOCK")"
  # the stub was written well after the move: without the rule this lock reads ABANDONED and expires
  python3 -c 'import os,sys;t=int(sys.argv[2]);os.utime(sys.argv[1],(t,t))' "$SRC" $((ts + 1800))
  export LR_NOW=$((ts + 30000))
  run python3 "$LRL" status "$SID" --json
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(_field class)" = CUSTODY ] || { echo "$output"; false; }
  [[ "$(_field why)" == *"stub sits beside the retired transcript"* ]] || { echo "$output"; false; }
  run python3 "$LRL" reap
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -f "$LOCK" ] || { echo "reap expired an unresolved custody lock"; false; }
}

@test "custody: the confirm receipt and tombstone carry confirm_len equal to the target's size" {
  _admit; [ "$status" -eq 0 ] || { echo "$output"; false; }
  _phase confirm
  [ "$status" -eq 0 ] || { echo "$output $stderr"; false; }
  local n; n="$(wc -c < "$DST" | tr -d ' ')"
  [ "$(_field confirm_len)" = "$n" ] || { echo "$output"; false; }
  [ "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["confirm_len"])' "$TOMB")" = "$n" ] || { cat "$TOMB"; false; }
  python3 -c 'import json,sys;k=list(json.load(open(sys.argv[1])));sys.exit(k[0]!="handed_off_to")' "$TOMB" || { cat "$TOMB"; false; }
  _phase confirm
  [ "$(_field already_confirmed)" = True ] && [ "$(_field confirm_len)" = "$(wc -c < "$RET" | tr -d ' ')" ] || { echo "$output"; false; }
}

@test "custody: confirm with a record id and no lock refuses lock-mismatch; without one it stays the legacy single step" {
  local src; src="$(_sha "$SRC")"
  _phase confirm --record-id R1
  [ "$status" -eq 2 ] || { echo "$output $stderr"; false; }
  [ "$(_field reason)" = lock-mismatch ] || { echo "$output"; false; }
  [ "$(_field detail)" = no-lock ] || { echo "$output"; false; }
  [ "$(_sha "$SRC")" = "$src" ] || { echo "a refusal moved something"; false; }
  [ ! -e "$RET" ] || { echo "a refusal moved something"; false; }
  [ ! -e "$DST" ] || { echo "a refusal moved something"; false; }
  # control: lr-handoff's single-step confirm (no admit, no record id) still retires
  _phase confirm
  [ "$status" -eq 0 ] && [ -f "$RET" ] || { echo "$output $stderr"; false; }
}

@test "custody: with no record id the lock keeps today's shape — no record_id, no holder" {
  _admit; [ "$status" -eq 0 ] || { echo "$output"; false; }
  run python3 -c 'import json,sys;print(",".join(json.load(open(sys.argv[1]))))' "$LOCK"
  [ "$output" = "sid,from,to,ts,pid,host,owner,ts_first,chain" ] || { echo "keys: $output"; cat "$LOCK"; false; }
  ! grep -q record_id "$LOCK" || { cat "$LOCK"; false; }
}

@test "custody: --record-id with no value is usage (rc 3)" {
  run bash "$LRT" --sid "$SID" --from "$T/from" --to "$T/to" --record-id
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  [ ! -e "$LOCK" ] || { echo "a usage error left a lock"; false; }
}
