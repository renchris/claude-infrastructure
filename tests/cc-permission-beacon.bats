#!/usr/bin/env bats
# cc-permission-beacon.sh — the PermissionRequest BEACON (desk-anti-hitl §B2). On a permission prompt
# the harness writes an unspoofable {ts,tool_name,tool_input,cwd} record to CC_PERMPEND_DIR/<sid>.json
# that lead-supervisor.sh reads to page "PERMISSION-PENDING: <cmd>". The hook is a pure OBSERVER (emits
# NO permission decision) and MUST be fail-open + fail-quiet — a parse/IO error can never block the
# prompt. These tests pin both the happy path and every fail-safe (empty/malformed/no-sid/path-escape).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  H="$REPO/hooks/cc-permission-beacon.sh"
  export CC_PERMPEND_DIR="$BATS_TEST_TMPDIR/permpend"
  unset CC_PERMISSION_BEACON_DISABLED
}

# a well-formed harness PermissionRequest payload for session $1 running Bash command $2
payload() { jq -nc --arg sid "$1" --arg cmd "$2" \
  '{session_id:$sid,tool_name:"Bash",tool_input:{command:$cmd},cwd:"/w/repo"}'; }
beacon() { printf '%s/%s.json' "$CC_PERMPEND_DIR" "$1"; }
# nothing (not even a temp) exists under the beacon dir
dir_empty() { [ -z "$(ls -A "$CC_PERMPEND_DIR" 2>/dev/null)" ]; }

@test "hook is executable (a non-+x hook is silently skipped by the harness)" {
  [ -x "$H" ]
}

# ── WRITE — the happy path: a harness-authored beacon with exactly the four fields ────────────────
@test "write persists a beacon keyed by session_id with the harness fields" {
  printf '%s' "$(payload sess-ABC-123 'git reset --hard origin/main')" | "$H" write
  b="$(beacon sess-ABC-123)"
  [ -f "$b" ]
  [ "$(jq -r '.tool_name' "$b")" = Bash ]
  [ "$(jq -r '.tool_input.command' "$b")" = 'git reset --hard origin/main' ]
  [ "$(jq -r '.cwd' "$b")" = /w/repo ]
  jq -e '.ts | type == "number"' "$b"                      # ts is epoch seconds, a NUMBER
  [ "$(jq -rS 'keys|join(",")' "$b")" = "cwd,tool_input,tool_name,ts" ]   # exactly these keys
}

@test "tool_input is preserved as a structured object (not stringified)" {
  printf '%s' "$(jq -nc '{session_id:"s-obj",tool_name:"Write",tool_input:{file_path:"/x/y.ts",content:"z"},cwd:"/w"}')" | "$H" write
  b="$(beacon s-obj)"
  jq -e '.tool_input | type == "object"' "$b"
  [ "$(jq -r '.tool_input.file_path' "$b")" = /x/y.ts ]
}

@test "a re-prompt overwrites the beacon atomically (no stale first payload)" {
  printf '%s' "$(payload s-re 'first')"  | "$H" write
  printf '%s' "$(payload s-re 'second')" | "$H" write
  [ "$(jq -r '.tool_input.command' "$(beacon s-re)")" = second ]
  [ "$(ls -A "$CC_PERMPEND_DIR")" = "s-re.json" ]          # no leftover .s-re.XXXXXX temp
}

# ── CLEAR — resolution removes the beacon; absent is a no-op ──────────────────────────────────────
@test "clear removes the beacon and is idempotent when it is already gone" {
  printf '%s' "$(payload s-clr x)" | "$H" write
  [ -f "$(beacon s-clr)" ]
  printf '%s' "$(payload s-clr x)" | "$H" clear
  [ ! -f "$(beacon s-clr)" ]
  run bash -c 'printf "%s" "$1" | "$2" clear' _ "$(payload s-clr x)" "$H"   # second clear, no beacon
  [ "$status" -eq 0 ]
}

# ── FAIL-OPEN — a parse/IO problem NEVER blocks the prompt and NEVER writes garbage ───────────────
@test "empty stdin: exit 0, no beacon (fail-open)" {
  run bash -c 'printf "" | "$1" write' _ "$H"
  [ "$status" -eq 0 ]
  dir_empty
}

@test "malformed JSON: exit 0, no beacon (fail-open, no partial file)" {
  run bash -c 'printf "not json {{{" | "$1" write' _ "$H"
  [ "$status" -eq 0 ]
  dir_empty
}

@test "missing session_id: no beacon (nothing to key on)" {
  run bash -c 'printf "%s" "{\"tool_name\":\"Bash\"}" | "$1" write' _ "$H"
  [ "$status" -eq 0 ]
  dir_empty
}

# ── SECURITY — the session_id is a path component; a traversal/unsafe sid must never escape the dir ─
@test "path-traversal / unsafe session_id is rejected (no write escapes CC_PERMPEND_DIR)" {
  for bad in "../evil" "a/b" ".." "." "sp ace" 'semi;rm' '/abs' '~home'; do
    printf '%s' "$(jq -nc --arg s "$bad" '{session_id:$s,tool_name:"Bash",tool_input:{},cwd:"/w"}')" | "$H" write
  done
  dir_empty
  [ ! -e "$BATS_TEST_TMPDIR/evil.json" ]                   # the ../ never wrote a sibling
}

@test "a real uuid-shaped session_id (hex + hyphens) IS accepted" {
  printf '%s' "$(payload 873EC4E0-7F29-46FF-9443-6FC717BC1777 ok)" | "$H" write
  [ -f "$(beacon 873EC4E0-7F29-46FF-9443-6FC717BC1777)" ]
}

# ── KILL SWITCH + UNKNOWN MODE — both are no-ops ─────────────────────────────────────────────────
@test "kill switch CC_PERMISSION_BEACON_DISABLED=1 makes write a no-op" {
  printf '%s' "$(payload s-off x)" | CC_PERMISSION_BEACON_DISABLED=1 "$H" write
  [ ! -f "$(beacon s-off)" ]
}

@test "an unknown/absent mode is a fail-quiet no-op (never writes)" {
  printf '%s' "$(payload s-bogus x)" | "$H" bogus
  [ ! -f "$(beacon s-bogus)" ]
  printf '%s' "$(payload s-bogus x)" | "$H"
  [ ! -f "$(beacon s-bogus)" ]
}
