#!/usr/bin/env bats
# lr-transplant.sh — AN ADMIT THAT DIES MID-COPY RELEASES WHAT IT TOOK (lr-reliability-telemetry-speed
# 2026-10-10, wave C: ranked rows 8 and 9).
#
# The copy runs under `set -euo pipefail` after the lock is written and before the tombstone. A
# mid-rsync death (58d3640a: `mkstempat tool-results/… No such file`) used to leave the lock and a
# partial target copy behind, and the orphan lock later made the poller retire the request as
# "transplanted" while the session sat limited. A run that wrote a FRESH lock now releases it on a
# non-zero exit inside that window and moves the partial copy to an evidence dir (never deletes it).
# It leaves alone anything it did not create: a lock or target copy that predates the run.
#
# The death is real: a source session-dir file the copier cannot read makes rsync exit 23.

bats_require_minimum_version 1.5.0

setup() {
  [ "$(id -u)" -ne 0 ] || skip "root reads a mode-000 file, so rsync would not fail"
  T="$BATS_TEST_TMPDIR"
  export HOME="$T/home"
  export LR_STATE_DIR="$HOME/.reso/limit-recover"
  unset LR_CONFIG_DIRS LR_RECORD_ID LR_ATTEMPT LR_HOLDER_PID HF_WATCHER_RECORD LR_NOW LR_LOCK_TTL_S LR_LOCK_SLACK_S
  mkdir -p "$LR_STATE_DIR/locks" "$T/from/projects/slug" "$T/to/projects/slug"
  SID=11111111-2222-3333-4444-555555555555
  SRC="$T/from/projects/slug/$SID.jsonl"
  DST="$T/to/projects/slug/$SID.jsonl"
  TOMB="$T/from/projects/slug/$SID.HANDOFF.json"
  LOCK="$LR_STATE_DIR/locks/$SID.lock"
  ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LRT="$ROOT/scripts/limit-recover/lr-transplant.sh"
  printf '{"type":"user","uuid":"a1"}\n{"type":"assistant","uuid":"a2"}\n' > "$SRC"
  SRC_SHA="$(shasum -a 256 "$SRC" | cut -d' ' -f1)"
  mkdir -p "$T/from/projects/slug/$SID/tool-results"
  printf 'ok\n' > "$T/from/projects/slug/$SID/tool-results/a.txt"
  printf 'secret\n' > "$T/from/projects/slug/$SID/tool-results/b.txt"
  chmod 000 "$T/from/projects/slug/$SID/tool-results/b.txt"
}
teardown() { chmod -R u+rwx "$BATS_TEST_TMPDIR/from" 2>/dev/null || true; }

_admit() { run --separate-stderr "${SH:-bash}" "$LRT" --phase admit --sid "$SID" --from "$T/from" --to "$T/to" "$@"; }
_evidence() { local d last=""; for d in "$LR_STATE_DIR/locks/$SID".failed-admit-*; do [ -d "$d" ] && last="$d"; done; printf '%s' "$last"; }

# Mutant: drop the `trap 'lrt_admit_cleanup …' EXIT` line — the lock and the partial copy stay.
@test "a mid-rsync death releases this run's fresh lock and moves the partial copy to evidence; the source is untouched" {
  _admit --record-id R1
  [ "$status" -ne 0 ] || { echo "the copy was meant to fail: $output"; false; }
  [ ! -e "$LOCK" ] || { echo "orphan lock:"; cat "$LOCK"; false; }
  [ ! -e "$DST" ] || { echo "partial target copy left beside the source"; false; }
  [ ! -e "$T/to/projects/slug/$SID" ] || { echo "partial session dir left"; false; }
  [ ! -e "$TOMB" ] || { echo "a tombstone was written"; false; }
  local ev; ev="$(_evidence)"
  [ -n "$ev" ] || { ls -la "$LR_STATE_DIR/locks"; false; }
  [ -f "$ev/$SID.jsonl" ] && [ -d "$ev/$SID" ] && [ -f "$ev/lock" ] || { ls -laR "$ev"; false; }
  [ "$(shasum -a 256 "$SRC" | cut -d' ' -f1)" = "$SRC_SHA" ] || { echo "source changed"; false; }
  [[ "$stderr" == *"released the lock and moved the partial target copy to $ev"* ]] || { echo "$stderr"; false; }
}
@test "the same death under /bin/bash 3.2 (the interpreter the shebang names) releases the lock too" {
  SH=/bin/bash _admit
  [ "$status" -ne 0 ]
  [ ! -e "$LOCK" ] || { cat "$LOCK"; false; }
  [ ! -e "$DST" ]
}
@test "a retry after the cleanup is a fresh admit, not 'lock exists' or 'already exists'" {
  _admit
  [ "$status" -ne 0 ]
  chmod 644 "$T/from/projects/slug/$SID/tool-results/b.txt"
  _admit
  [ "$status" -eq 0 ] || { echo "status=$status $stderr"; false; }
  [ -e "$LOCK" ] && [ -e "$TOMB" ] && [ -f "$T/to/projects/slug/$SID/tool-results/b.txt" ]
}
@test "CONTROL: a lock that PREDATES the run (a --force over a stale lock) is not released by the failed copy" {
  printf '{"sid":"%s","from":"x","to":"y","pid":1}\n' "$SID" > "$LOCK"
  _admit --force
  [ "$status" -ne 0 ]
  [ -e "$LOCK" ] || { echo "a lock this run did not create was removed"; false; }
  [ -z "$(_evidence)" ] || { echo "cleanup ran over a pre-existing lock"; false; }
}
@test "CONTROL: a target copy that PREDATES the run (--force) is left where it is" {
  printf 'old\n' > "$DST"
  _admit --force
  [ "$status" -ne 0 ]
  [ -e "$DST" ] || { echo "a target copy this run did not create was moved"; false; }
}
@test "CONTROL: a copy that succeeds keeps its lock and tombstone (the cleanup is disarmed after the sha check)" {
  chmod 644 "$T/from/projects/slug/$SID/tool-results/b.txt"
  _admit --record-id R1
  [ "$status" -eq 0 ] || { echo "$stderr"; false; }
  [ -e "$LOCK" ] && [ -e "$TOMB" ] && [ -e "$DST" ]
  [ -z "$(_evidence)" ]
}
