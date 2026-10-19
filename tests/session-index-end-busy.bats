#!/usr/bin/env bats
# hooks/session-index-end.sh under SQLITE_BUSY (lr-wake 2026-10-18, a-failed-self-recycle F6):
# a locked DB queues the SessionEnd and prints NOTHING into the closing pane; a later SessionEnd
# that gets its write through replays the queue; any other DB error still surfaces as before.

bats_require_minimum_version 1.5.0

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/logs" "$HOME/.claude/projects"
  export CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  HOOK="$REPO/hooks/session-index-end.sh"
  DB="$HOME/.claude/session-index.db"
  Q="$HOME/.claude/session-index-queue"
  STUB="$BATS_TEST_TMPDIR/stub"; mkdir -p "$STUB"
  REAL_SQLITE="$(command -v sqlite3)"
}

stub_sqlite() { # <stderr line> <rc> — every sqlite3 call fails this way
  printf '#!/bin/bash\necho "%s" >&2\nexit %s\n' "$1" "$2" > "$STUB/sqlite3"
  chmod +x "$STUB/sqlite3"
}
end_json() { printf '{"session_id":"%s","transcript_path":"","cwd":"/Users/x/proj"}' "$1"; }
rows()     { "$REAL_SQLITE" "$DB" "SELECT count(*) FROM sessions WHERE session_id='$1';" 2>/dev/null || echo 0; }

@test "SQLITE_BUSY: the SessionEnd is queued, the hook exits 0, and nothing reaches the pane" {
  stub_sqlite "Error: in prepare, database is locked (5)" 5
  run --separate-stderr env PATH="$STUB:$PATH" bash "$HOOK" <<< "$(end_json aaaa-1111)"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ] || { echo "pane saw: $stderr"; false; }
  [ -f "$Q/aaaa-1111.json" ]
  jq -e '.session_id == "aaaa-1111"' "$Q/aaaa-1111.json" >/dev/null
  grep -q '"reason":"busy-queued"' "$CC_IDL" || { cat "$CC_IDL"; false; }
}

@test "the next SessionEnd that writes drains the queue: both sessions are indexed, the queue is empty" {
  stub_sqlite "Error: database is locked" 5
  env PATH="$STUB:$PATH" bash "$HOOK" <<< "$(end_json aaaa-2222)"
  [ -f "$Q/aaaa-2222.json" ]
  run bash "$HOOK" <<< "$(end_json bbbb-3333)"           # real sqlite3: the DB takes a write
  [ "$status" -eq 0 ]
  [ "$(rows bbbb-3333)" = 1 ]
  [ "$(rows aaaa-2222)" = 1 ] || { ls -la "$Q"; false; }
  [ ! -e "$Q/aaaa-2222.json" ]
}

@test "CONTROL: a DB error that is not SQLITE_BUSY still fails loudly and queues nothing" {
  stub_sqlite "Error: unable to open database file" 1
  run --separate-stderr env PATH="$STUB:$PATH" bash "$HOOK" <<< "$(end_json cccc-4444)"
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"unable to open database file"* ]] || { echo "$stderr"; false; }
  [ ! -e "$Q/cccc-4444.json" ]
}
