#!/usr/bin/env bats
# scripts/lib/recycle-escalate.sh — a recycle failure's incident record and its bounded research fire
# (docs/research/selfrecycle-latency-2026-10-26/REPORT.md D5).
#
# Contracts: every call counts into <dir>/<class>.json; a class fires at most once per
# CC_RECYCLE_ESCALATE_CLASS_S, all classes at most CC_RECYCLE_ESCALATE_DAY_MAX times per rolling day;
# designed holds are counted and never fired; nothing fires under bats without an explicit fire bin;
# the kill switch touches nothing; the caller always gets rc 0.
# The fire bin is a stub that records its argv, so what is asserted is the command a real fire runs.
#
# RED-proof: the lib is new (1a0ee3658 has no incident record at all); the dedupe and cap cases were
# each run against a scratch copy with that guard deleted and went red.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO_SRC="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  # shellcheck source=../scripts/lib/recycle-escalate.sh
  # shellcheck disable=SC1091  # runtime-resolved source; the land gate runs shellcheck without -x
  . "$REPO_SRC/scripts/lib/recycle-escalate.sh"
  export CC_RECYCLE_INCIDENT_DIR="$BATS_TEST_TMPDIR/inc"
  export STUB_ARGV="$BATS_TEST_TMPDIR/fired.argv"
  export CC_RECYCLE_ESCALATE_FIRE_BIN="$BATS_TEST_TMPDIR/fire-stub"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s"\n' "$STUB_ARGV" > "$CC_RECYCLE_ESCALATE_FIRE_BIN"
  chmod +x "$CC_RECYCLE_ESCALATE_FIRE_BIN"
  EV="$BATS_TEST_TMPDIR/watcher.log"; printf 'log\n' > "$EV"
}

fires() { # the stub's recorded fires, after the detached child has had up to 5 s to run
  local i=0
  while [ "$i" -lt 50 ] && [ "$(wc -l < "$STUB_ARGV" 2>/dev/null || echo 0)" -lt "${1:-1}" ]; do sleep 0.1; i=$((i + 1)); done
  wc -l < "$STUB_ARGV" 2>/dev/null | tr -d ' ' || echo 0
}
rec() { jq -r "$1" "$CC_RECYCLE_INCIDENT_DIR/$2.json"; }

@test "the first failure of a class fires one research session with the brief, worktree and goal; a second within 24 h is deduped" {
  run hf_recycle_escalate recycle-held-bgwork 7 sid-1 "dialog held" "$EV" "$BATS_TEST_TMPDIR/missing"
  [ "$status" -eq 0 ]
  [[ "$output" == *"recycle-held-bgwork count=1 fire=fired pid="* ]]
  [ "$(fires 1)" = 1 ]
  d="$(date -u +%Y-%m-%d)"
  grep -qF -- "--prompt-file $CC_RECYCLE_INCIDENT_DIR/recycle-held-bgwork-$d.brief.md" "$STUB_ARGV"
  grep -qF -- "--worktree recycle-incident-recycle-held-bgwork-$(date -u +%Y%m%d)" "$STUB_ARGV"
  grep -qF -- "--goal docs/research/recycle-incident-recycle-held-bgwork-$d.md is on origin/main" "$STUB_ARGV"
  grep -qF "$EV" "$CC_RECYCLE_INCIDENT_DIR/recycle-held-bgwork-$d.brief.md"
  [ "$(rec '.evidence | join(",")' recycle-held-bgwork)" = "$EV" ]
  run hf_recycle_escalate recycle-held-bgwork 8 sid-2 "dialog held again" "$EV"
  [[ "$output" == *"count=2 fire=deduped-class"* ]]
  sleep 1
  [ "$(fires 1)" = 1 ]
  [ "$(rec '.count' recycle-held-bgwork)" = 2 ]
  [ "$(rec '.fires | length' recycle-held-bgwork)" = 1 ]
}

@test "the class window reopens after CC_RECYCLE_ESCALATE_CLASS_S" {
  hf_recycle_escalate recycle-dead 7 s d >/dev/null
  [ "$(fires 1)" = 1 ]
  jq '.last_fire_ts -= 90000' "$CC_RECYCLE_INCIDENT_DIR/recycle-dead.json" > "$BATS_TEST_TMPDIR/r" && mv "$BATS_TEST_TMPDIR/r" "$CC_RECYCLE_INCIDENT_DIR/recycle-dead.json"
  run hf_recycle_escalate recycle-dead 7 s d
  [[ "$output" == *"fire=fired"* ]]
}

@test "three classes fire in a day, the fourth is capped; a fire older than a day does not count" {
  for c in recycle-dead recycle-unverified recycle-held-bgwork; do hf_recycle_escalate "$c" 7 s d >/dev/null; done
  run hf_recycle_escalate recycle-watcher-orphaned 7 s d
  [[ "$output" == *"fire=day-cap"* ]]
  [ "$(fires 3)" = 3 ]
  # age every logged fire past the window: the next class fires again
  awk '{ $1 = $1 - 90000; print }' "$CC_RECYCLE_INCIDENT_DIR/fires.log" > "$BATS_TEST_TMPDIR/f" && mv "$BATS_TEST_TMPDIR/f" "$CC_RECYCLE_INCIDENT_DIR/fires.log"
  run hf_recycle_escalate recycle-held-delegated 7 s d
  [[ "$output" == *"fire=fired"* ]]
}

@test "a designed hold (an operator draft) is counted and never fired" {
  run hf_recycle_escalate recycle-held-draft 7 s "operator text in the composer"
  [[ "$output" == *"count=1 fire=skip-designed-hold"* ]]
  sleep 1
  [ ! -e "$STUB_ARGV" ]
}

@test "under bats with no fire bin set, nothing fires" {
  unset CC_RECYCLE_ESCALATE_FIRE_BIN
  run hf_recycle_escalate recycle-dead 7 s d
  [[ "$output" == *"fire=suppressed-under-test"* ]]
  [ "$(rec '.last_fire_ts' recycle-dead)" = 0 ]
}

@test "the kill switch writes nothing; an empty class after sanitising is ignored; rc is always 0" {
  CC_RECYCLE_ESCALATE=off run hf_recycle_escalate recycle-dead 7 s d
  [ "$status" -eq 0 ] && [ -z "$output" ]
  [ ! -e "$CC_RECYCLE_INCIDENT_DIR" ]
  run hf_recycle_escalate '../../ETC' 7 s d
  [ "$status" -eq 0 ] && [ -z "$output" ]
  run hf_recycle_escalate 'Recycle-Dead/x' 7 s d
  [[ "$output" == *"→ escalate: ecycle-eadx count=1"* ]]
}

@test "a corrupt record is moved aside and counting restarts" {
  mkdir -p "$CC_RECYCLE_INCIDENT_DIR"; printf 'not json' > "$CC_RECYCLE_INCIDENT_DIR/recycle-dead.json"
  run hf_recycle_escalate recycle-dead 7 s d
  [[ "$output" == *"count=1"* ]]
  ls "$CC_RECYCLE_INCIDENT_DIR"/recycle-dead.json.corrupt.* >/dev/null
}

@test "a fresh lock held by another writer leaves the record alone; a stale one is broken" {
  mkdir -p "$CC_RECYCLE_INCIDENT_DIR/.lock"
  run hf_recycle_escalate recycle-dead 7 s d
  [ "$output" = "→ escalate: recycle-dead lock-busy" ]
  [ ! -e "$CC_RECYCLE_INCIDENT_DIR/recycle-dead.json" ]
  touch -t "$(date -v-2M +%Y%m%d%H%M.%S)" "$CC_RECYCLE_INCIDENT_DIR/.lock"
  run hf_recycle_escalate recycle-dead 7 s d
  [[ "$output" == *"count=1"* ]]
}
