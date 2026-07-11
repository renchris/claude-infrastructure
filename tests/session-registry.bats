#!/usr/bin/env bats
# Phase 1 — cross-session comms registry:
#   hooks/session-register.sh · hooks/session-deregister.sh · bin/cc-sessions
#
# Isolated via CC_REGISTRY_DIR (temp) and IT2_BIN (a stub that fakes
# `it2 session list --json`). No real iTerm2 / ~/.claude state is touched.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  REG="$REPO/hooks/session-register.sh"
  DEREG="$REPO/hooks/session-deregister.sh"
  CCS="$REPO/bin/cc-sessions"
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg"

  # it2 stub: lists $IT2_STUB_PANES (space-separated UUIDs) as a JSON array.
  # IT2_STUB_PANES=__DOWN__ simulates it2 being unreadable (exit 1).
  STUB="$BATS_TEST_TMPDIR/it2"
  cat > "$STUB" <<'SH'
#!/bin/bash
if [ "$1 $2 $3" = "session list --json" ]; then
  [ "${IT2_STUB_PANES:-}" = "__DOWN__" ] && exit 1
  printf '['
  first=1
  for id in ${IT2_STUB_PANES:-}; do
    [ "$first" = 1 ] || printf ','
    printf '{"id":"%s"}' "$id"; first=0
  done
  printf ']\n'
fi
exit 0
SH
  chmod +x "$STUB"
  export IT2_BIN="$STUB"
}

# helper: write a registry entry file directly
mkentry() { # $1=uuid $2=name $3=pid
  mkdir -p "$CC_REGISTRY_DIR"
  printf '{"paneUUID":"%s","name":"%s","cwd":"/tmp","account":"next","pid":%s,"startedAt":1}' \
    "$1" "$2" "$3" > "$CC_REGISTRY_DIR/$1.json"
}

# helper: a definitely-dead pid
deadpid() { sleep 1 & local p=$!; kill "$p" 2>/dev/null; wait "$p" 2>/dev/null || true; echo "$p"; }

@test "register: writes a well-formed entry with the expected fields" {
  printf '{"cwd":"/tmp/demo","reason":"startup"}' \
    | ITERM_SESSION_ID="w1t0p0:AAAAAAAA-1111-2222-3333-444444444444" CC_SESSION_NAME="demo" bash "$REG"
  f="$CC_REGISTRY_DIR/AAAAAAAA-1111-2222-3333-444444444444.json"
  [ -f "$f" ]
  run jq -r '.paneUUID' "$f"; [ "$output" = "AAAAAAAA-1111-2222-3333-444444444444" ]
  run jq -r '.name' "$f";     [ "$output" = "demo" ]
  run jq -r '.cwd' "$f";      [ "$output" = "/tmp/demo" ]
  run jq -r '.startedAt|type' "$f"; [ "$output" = "number" ]
  run jq -r '.pid|type' "$f"; [ "$output" = "number" ]
}

@test "register: default name is <cwd-basename>-<short-uuid> when CC_SESSION_NAME unset" {
  printf '{"cwd":"/tmp/myproj"}' \
    | env -u CC_SESSION_NAME ITERM_SESSION_ID="w1t0p0:DEADBEEF-1111-2222-3333-444444444444" bash "$REG"
  run jq -r '.name' "$CC_REGISTRY_DIR/DEADBEEF-1111-2222-3333-444444444444.json"
  [ "$output" = "myproj-DEADBEEF" ]
}

@test "register: no-op when ITERM_SESSION_ID is absent (not an iTerm2 pane)" {
  printf '{"cwd":"/tmp/x"}' | env -u ITERM_SESSION_ID bash "$REG"
  run bash -c "ls '$CC_REGISTRY_DIR' 2>/dev/null | wc -l | tr -d ' '"
  [ "$output" = "0" ]
}

@test "register: no-op when ITERM_SESSION_ID is malformed (non-UUID)" {
  printf '{"cwd":"/tmp/x"}' | ITERM_SESSION_ID="not a uuid" bash "$REG"
  run bash -c "ls '$CC_REGISTRY_DIR' 2>/dev/null | wc -l | tr -d ' '"
  [ "$output" = "0" ]
}

@test "cc-sessions --json: lists a live entry (pid alive, pane present)" {
  export IT2_STUB_PANES="AAAAAAAA-1111-2222-3333-444444444444"
  mkentry "AAAAAAAA-1111-2222-3333-444444444444" "live" "$$"
  run bash "$CCS" --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.[0].name == "live"'
}

@test "cc-sessions --names: prints friendly names" {
  export IT2_STUB_PANES="AAAAAAAA-1111-2222-3333-444444444444"
  mkentry "AAAAAAAA-1111-2222-3333-444444444444" "alpha" "$$"
  run bash "$CCS" --names
  [ "$status" -eq 0 ]
  [ "$output" = "alpha" ]
}

@test "cc-sessions: sweeps an entry whose pid is dead (authoritative, even if pane present)" {
  dead="$(deadpid)"
  export IT2_STUB_PANES="BBBBBBBB-0000-0000-0000-000000000000"   # pane still listed
  mkentry "BBBBBBBB-0000-0000-0000-000000000000" "ghost" "$dead"
  run bash "$CCS" --names
  [ "$status" -eq 0 ]
  [ ! -f "$CC_REGISTRY_DIR/BBBBBBBB-0000-0000-0000-000000000000.json" ]
}

@test "cc-sessions: sweeps an entry whose pane is gone (pid alive, pane absent)" {
  export IT2_STUB_PANES="OTHER-UUID"   # our uuid NOT in the list
  mkentry "CCCCCCCC-0000-0000-0000-000000000000" "detached" "$$"
  run bash "$CCS" --names
  [ "$status" -eq 0 ]
  [ ! -f "$CC_REGISTRY_DIR/CCCCCCCC-0000-0000-0000-000000000000.json" ]
}

@test "cc-sessions: does NOT sweep on it2 outage when pid is alive (fail-safe)" {
  export IT2_STUB_PANES="__DOWN__"     # it2 unreadable
  mkentry "DDDDDDDD-0000-0000-0000-000000000000" "keepme" "$$"
  run bash "$CCS" --names
  [ "$status" -eq 0 ]
  [ -f "$CC_REGISTRY_DIR/DDDDDDDD-0000-0000-0000-000000000000.json" ]
  [ "$output" = "keepme" ]
}

@test "cc-sessions: sweeps a corrupt entry (missing paneUUID)" {
  mkdir -p "$CC_REGISTRY_DIR"
  echo '{"name":"broken"}' > "$CC_REGISTRY_DIR/corrupt.json"
  export IT2_STUB_PANES=""
  run bash "$CCS" --json
  [ "$status" -eq 0 ]
  [ ! -f "$CC_REGISTRY_DIR/corrupt.json" ]
  [ "$output" = "[]" ]
}

@test "cc-sessions --json: empty registry yields []" {
  run bash "$CCS" --json
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "deregister: removes the entry" {
  mkentry "AAAAAAAA-1111-2222-3333-444444444444" "bye" "$$"
  printf '{"reason":"exit"}' | ITERM_SESSION_ID="w1t0p0:AAAAAAAA-1111-2222-3333-444444444444" bash "$DEREG"
  [ ! -f "$CC_REGISTRY_DIR/AAAAAAAA-1111-2222-3333-444444444444.json" ]
}

@test "deregister: skips on reason=clear (pane persists, re-registers next)" {
  mkentry "AAAAAAAA-1111-2222-3333-444444444444" "keep" "$$"
  printf '{"reason":"clear"}' | ITERM_SESSION_ID="w1t0p0:AAAAAAAA-1111-2222-3333-444444444444" bash "$DEREG"
  [ -f "$CC_REGISTRY_DIR/AAAAAAAA-1111-2222-3333-444444444444.json" ]
}
