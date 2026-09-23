#!/usr/bin/env bats
# lr-lock.py — the TTL and the release verb for lr-transplant's split-brain lock
# (cc-backlog 4f8c73bbdb35, VOLUNTARY_ACCOUNT_SWITCH.md § 9).
#
# EVERY FIXTURE IS MADE BY THE REAL WRITER. The lock and tombstone below come out of
# lr-transplant.sh itself, never a hand-typed JSON, so a change to the lock's shape reaches this suite
# instead of leaving it green over a shape nobody writes. Time is then moved with LR_NOW and file
# mtimes with os.utime — never with sleep, and never with GNU/BSD-specific `touch` flags.
#
# THE PROPERTY THAT MATTERS MOST IS THE NEGATIVE ONE. A TTL on AGE would have been a one-line
# `find -mmin +N -delete`, and it would have disarmed the resume guard (lr_tombstone_verdict) on every
# long-quiet successor — the incident that guard exists for (24c9955d6c4f). So the CUSTODY/SPLIT/QUIET
# cases below are the mutation controls for "an age-only reaper": each is old far past the TTL and
# each must survive `reap`.

setup() {
  T="$BATS_TEST_TMPDIR"
  export HOME="$T/home"
  export LR_STATE_DIR="$HOME/.reso/limit-recover"
  mkdir -p "$LR_STATE_DIR/locks" "$T/from/projects/slug" "$T/to/projects/slug" "$T/third/projects/slug"
  SID=11111111-2222-3333-4444-555555555555
  SRC="$T/from/projects/slug/$SID.jsonl"
  DST="$T/to/projects/slug/$SID.jsonl"
  TOMB="$T/from/projects/slug/$SID.HANDOFF.json"
  LOCK="$LR_STATE_DIR/locks/$SID.lock"
  ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LRT="$ROOT/scripts/limit-recover/lr-transplant.sh"
  LRL="$ROOT/scripts/limit-recover/lr-lock.py"
  printf '{"type":"assistant","message":{"role":"assistant"}}\n' > "$SRC"
  # pinned: the runner's own environment must not move the clock or the policy under a case
  unset LR_NOW LR_LOCK_TTL_S LR_LOCK_SLACK_S
}

_admit() { bash "$LRT" --phase admit --sid "$SID" --from "$T/from" --to "$T/to" >/dev/null 2>&1; }
_lock_ts() { python3 -c 'import json,sys,calendar,time;print(calendar.timegm(time.strptime(json.load(open(sys.argv[1]))["ts"],"%Y-%m-%dT%H:%M:%SZ")))' "$LOCK"; }
_touch_at() { python3 -c 'import os,sys;t=int(sys.argv[2]);os.utime(sys.argv[1],(t,t))' "$1" "$2"; }
# "written N seconds after the move" — the move's own ts is the only clock these classes read
_ran() { _touch_at "$1" $(( $(_lock_ts) + ${2:-1800} )); }
_later() { export LR_NOW=$(( $(_lock_ts) + ${1:-7200} )); }
_lrl() { run python3 "$LRL" "$@"; }
_class() { python3 "$LRL" status "$SID" --json | python3 -c 'import json,sys;print(json.load(sys.stdin)["class"])'; }

@test "lr-lock: RED PROOF — an abandoned admit no longer holds custody forever; past the TTL a new move goes through" {
  # Against the pre-fix tree this fails at `python3 "$LRL"`: there is no expiry path at all, and the
  # second move below is refused by `lock exists … transplanted to $T/to` for as long as the file
  # lives. That refusal is asserted FIRST, so the case proves the lock was the obstacle.
  _admit
  _ran "$SRC"                               # the session kept working where it was
  run bash "$LRT" --sid "$SID" --from "$T/from" --to "$T/third"
  [ "$status" -eq 2 ] || { echo "precondition: the abandoned lock should refuse: $output"; false; }
  [[ "$output" == *"already transplanted"* ]] || { echo "$output"; false; }

  _later 7200
  [ "$(_class)" = ABANDONED ] || { echo "class=$(_class)"; false; }
  _lrl reap
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"expired 11111111 (ABANDONED"* ]] || { echo "$output"; false; }
  [ ! -e "$LOCK" ] || { echo "the lock survived its expiry"; false; }

  unset LR_NOW
  run bash "$LRT" --sid "$SID" --from "$T/from" --to "$T/third"
  [ "$status" -eq 0 ] || { echo "the move is still refused after the expiry: $output"; false; }
}

@test "lr-lock: the TTL guards an IN-FLIGHT move — an ABANDONED-looking admit younger than the TTL is kept" {
  # Between admit and confirm a healthy source keeps appending while the target sits still: exactly
  # the ABANDONED signature. Only the age separates the two, which is the whole job of the TTL.
  _admit
  _ran "$SRC" 120
  _later 600
  [ "$(_class)" = ABANDONED ]
  _lrl reap
  [ "$status" -eq 0 ] && [ -z "$output" ] || { echo "$output"; false; }
  [ -f "$LOCK" ] || { echo "a 10-minute-old admit was reaped"; false; }
  # and the TTL is a knob, not a constant
  LR_LOCK_TTL_S=300 run python3 "$LRL" reap
  [ ! -e "$LOCK" ] || { echo "LR_LOCK_TTL_S was ignored"; false; }
}

@test "lr-lock: ORPHAN — a lock whose owner holds no transcript expires after the TTL" {
  _admit
  rm -f "$DST"                               # the copy never landed / the successor is gone
  _later 7200
  [ "$(_class)" = ORPHAN ]
  _lrl reap
  [[ "$output" == *"(ORPHAN"* ]] || { echo "$output"; false; }
  [ ! -e "$LOCK" ]
  # an ORPHAN's release is not a claim the move didn't happen, so the tombstone is left alone
  [ -f "$TOMB" ] || { echo "reaping an ORPHAN retired the tombstone"; false; }
}

@test "lr-lock: CUSTODY is never reaped however old — the successor ran (age-only-TTL mutation control)" {
  _admit
  _ran "$DST"
  _later 3000000                             # ~35 days
  [ "$(_class)" = CUSTODY ]
  _lrl reap
  [ -z "$output" ] || { echo "$output"; false; }
  [ -f "$LOCK" ] || { echo "a custody lock was reaped on age alone"; false; }
  # and the guard it feeds still refuses a second live copy on the ORIGINAL account
  run bash -c ". '$ROOT/scripts/limit-recover/lr-lib.sh' >/dev/null 2>&1; lr_transplanted_to '$SID' '$T/from'"
  [ "$status" -eq 0 ] && [ "$output" = "$T/to" ] || { echo "rc=$status out=$output"; false; }
}

@test "lr-lock: CUSTODY is never reaped — a confirmed move (source retired) with a successor that never ran" {
  _admit
  bash "$LRT" --phase confirm --sid "$SID" --from "$T/from" --to "$T/to" >/dev/null 2>&1
  [ -f "$SRC.handed-off" ]
  _later 3000000
  [ "$(_class)" = CUSTODY ]
  _lrl reap
  [ -f "$LOCK" ] || { echo "a completed move lost its lock to the TTL"; false; }
}

@test "lr-lock: SPLIT is never reaped, and release refuses it without --force" {
  _admit
  _ran "$SRC"; _ran "$DST"
  _later 3000000
  [ "$(_class)" = SPLIT ]
  _lrl reap
  [ -f "$LOCK" ]
  _lrl release "$SID" --why "test"
  [ "$status" -eq 2 ] || { echo "rc=$status $output"; false; }
  [[ "$output" == *"REFUSED"*"SPLIT"* ]] || { echo "$output"; false; }
  [ -f "$LOCK" ]
  _lrl release "$SID" --why "operator: the $T/to copy is a test artefact" --force
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ ! -e "$LOCK" ]
  # a forced release gives up the LOCK; the move did happen, so its tombstone stays
  [ -f "$TOMB" ] || { echo "a forced SPLIT release retired the tombstone"; false; }
}

@test "lr-lock: QUIET never auto-expires, and release accepts it and retires this move's tombstone" {
  _admit
  _later 3000000
  [ "$(_class)" = QUIET ]
  _lrl reap
  [ -f "$LOCK" ] || { echo "QUIET was reaped — disk cannot say which copy is real"; false; }
  _lrl release "${SID:0:8}" --why "switch aborted after admit"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ ! -e "$LOCK" ]
  [ ! -e "$TOMB" ] && [ -f "$TOMB.released" ] || { echo "tombstone not retired"; ls "$T/from/projects/slug"; false; }
  # with the lock AND the tombstone gone, nothing still reads the live source pane as a husk
  run bash -c ". '$ROOT/scripts/limit-recover/lr-lib.sh' >/dev/null 2>&1; lr_transplant_target '$SID' '$T/from'"
  [ "$status" -eq 1 ] || { echo "still reported as moved: $output"; false; }
}

@test "lr-lock: release NEVER deletes — it archives out of every reader's glob and records who, why and what" {
  _admit
  _ran "$SRC"
  _later 7200
  orig="$(cat "$LOCK")"
  _lrl release "$SID" --why "abandoned switch"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  # the globs every reader uses: cc-limited / lr-fleet enumerate locks/*.lock
  n=0; for f in "$LR_STATE_DIR"/locks/*.lock; do [ -f "$f" ] && n=$((n+1)); done
  [ "$n" -eq 0 ] || { echo "a released lock is still visible to the readers"; false; }
  arch=( "$LR_STATE_DIR"/locks/released/"$SID".*.json )
  [ -f "${arch[0]}" ] || { echo "no archive"; false; }
  python3 - "${arch[0]}" "$orig" <<'PY'
import json, sys
a = json.load(open(sys.argv[1])); o = json.loads(sys.argv[2])
for k, v in o.items():
    assert a.get(k) == v, ("original field lost", k)
assert a["released_why"] == "abandoned switch", a
assert a["released_class"] == "ABANDONED", a
assert a["released_by"].startswith("release"), a
assert a["released_at"], a
PY
}

@test "lr-lock: release demands --why, and names no lock it cannot find" {
  _admit
  _lrl release "$SID"
  [ "$status" -eq 3 ] && [ -f "$LOCK" ] || { echo "rc=$status"; false; }
  _lrl release "$SID" --why "   "
  [ "$status" -eq 3 ] && [ -f "$LOCK" ]
  _lrl release deadbeef --why x
  [ "$status" -eq 1 ] || { echo "rc=$status $output"; false; }
}

@test "lr-lock: UNPARSEABLE fails closed — never reaped, release refuses without --force" {
  printf 'not json\n' > "$LOCK"
  _touch_at "$LOCK" 1
  export LR_NOW=$(( $(date +%s) + 3000000 ))
  [ "$(_class)" = UNPARSEABLE ]
  _lrl reap
  [ -f "$LOCK" ]
  _lrl release "$SID" --why x
  [ "$status" -eq 2 ] && [ -f "$LOCK" ] || { echo "rc=$status"; false; }
}

@test "lr-lock: reap --dry-run changes nothing and says what it would expire" {
  _admit
  rm -f "$DST"
  _later 7200
  _lrl reap --dry-run
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"would expire 11111111 (ORPHAN"* ]] || { echo "$output"; false; }
  [ -f "$LOCK" ]
  [ ! -d "$LR_STATE_DIR/locks/released" ]
}

@test "lr-lock: list renders every lock with its class and flags the expired ones" {
  _admit
  rm -f "$DST"
  _later 7200
  _lrl list
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == ORPHAN*"11111111"*"EXPIRED"* ]] || { echo "$output"; false; }
  _lrl list --json
  [[ "$output" == *'"expired": true'* ]] || { echo "$output"; false; }
}

@test "lr-lock: the refusals that name a stale lock point at the release verb" {
  _admit
  run bash "$LRT" --sid "$SID" --from "$T/from" --to "$T/third"
  [ "$status" -eq 2 ]
  # the LITERAL command, so a refusal that EXECUTED it (backticks inside the double-quoted echo) fails
  [[ "$output" == *"lr-lock.py status $SID"*"lr-lock.py release $SID --why"* ]] || { echo "the refusal names no way to release: $output"; false; }
  # refusal site two — the bare `lock exists`, reached when the lock names THIS target but no copy is there
  rm -f "$DST"
  run bash "$LRT" --sid "$SID" --from "$T/from" --to "$T/to"
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [[ "$output" == *"lock exists"*"lr-lock.py release $SID --why"* ]] || { echo "$output"; false; }
}
