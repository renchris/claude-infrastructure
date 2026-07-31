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
  # MUST be pinned: `clear` now archives the record it removes, and without this every write→clear
  # test would append synthetic rows to the operator's REAL permission archive — poisoning the very
  # dataset the archive exists to provide. (It did, once, before this line existed.)
  export CC_PERMARCHIVE_DIR="$BATS_TEST_TMPDIR/permarchive"
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
  # The invariant is "no leftover .s-re.XXXXXX temp", not "exactly one file": the heartbeat
  # (.beacon-alive, see the existence-evidence tests below) is an EXPECTED second entry, so the
  # heartbeat is filtered out rather than the temp-leak check being weakened.
  [ "$(ls -A "$CC_PERMPEND_DIR" | grep -v '^\.beacon-alive$' | tr '\n' ' ')" = "s-re.json " ]
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

# ── EXISTENCE EVIDENCE / heartbeat (cc-backlog 1e16815bac51) ─────────────────────────────────────
# WHY THESE EXIST: this hook shipped landed-but-registered-nowhere, so CC_PERMPEND_DIR was never
# created and "no pending approvals" was indistinguishable from "the hook has never fired once".
# A teammate sat blocked on an approval its dead lead could never answer while the board reported
# all-clear. The heartbeat makes the observer's own liveness observable, so absence stops being
# ambiguous: dir ABSENT ⇒ never ran; dir present with no <sid>.json ⇒ genuinely nothing pending.
heartbeat() { printf '%s/.beacon-alive' "$CC_PERMPEND_DIR"; }

@test "heartbeat: clear STAMPS existence evidence even with nothing pending" {
  [ ! -d "$CC_PERMPEND_DIR" ]                       # precondition: the observer has never run
  printf '%s' "$(payload s-hb1 x)" | "$H" clear     # a clear is the common case — no prompt pending
  [ -d "$CC_PERMPEND_DIR" ]
  [ -f "$(heartbeat)" ]
  [ ! -f "$(beacon s-hb1)" ]                        # ...and it did NOT invent a pending beacon
}

@test "heartbeat: write stamps it too" {
  printf '%s' "$(payload s-hb2 'git reset --hard')" | "$H" write
  [ -f "$(heartbeat)" ]
  [ -f "$(beacon s-hb2)" ]
}

@test "heartbeat SURVIVES the clear that removes the beacon (the two are independent)" {
  # The load-bearing pair: after a full write→clear cycle the dir is EMPTY OF BEACONS but still
  # proves the hook ran. Before this, that same state was byte-identical to 'never wired'.
  printf '%s' "$(payload s-hb3 x)" | "$H" write
  printf '%s' "$(payload s-hb3 x)" | "$H" clear
  [ ! -f "$(beacon s-hb3)" ]
  [ -f "$(heartbeat)" ]
}

@test "heartbeat is INVISIBLE to the supervisor's beacon glob (dotfile, no .json suffix)" {
  # lead-supervisor.sh sweeps "$dir"/*.json. A heartbeat that matched would be read as a beacon with
  # ts=0, age>=horizon, and get reaped every sweep — or worse, paged as a phantom pending prompt.
  printf '%s' "$(payload s-hb4 x)" | "$H" clear
  [ -f "$(heartbeat)" ]
  found=0
  for f in "$CC_PERMPEND_DIR"/*.json; do [ -e "$f" ] && found=$((found + 1)); done
  [ "$found" -eq 0 ]
}

@test "heartbeat is NOT stamped when the hook fail-opens (no sid ⇒ nothing ran to attest)" {
  # A heartbeat written on a payload the hook rejected would be a FALSE positive control: it would
  # claim the observer is working on exactly the inputs it could not read.
  printf '%s' '{"no":"sid"}' | "$H" write
  [ ! -f "$(heartbeat)" ]
  dir_empty
}

@test "heartbeat is NOT stamped when the kill switch is set (disabled means disabled)" {
  printf '%s' "$(payload s-hb5 x)" | CC_PERMISSION_BEACON_DISABLED=1 "$H" clear
  [ ! -f "$(heartbeat)" ]
}

# ── DURABLE ARCHIVE (§3 Stage A.4) ───────────────────────────────────────────────────────────────
# WHY THESE EXIST: `clear` used to rm -f the record outright, so no history of ACTUAL permission
# prompts existed anywhere on the box. bin/cc-permission-audit could therefore only ever report an
# UPPER bound, and the auto-mode classifier could never be tuned on real data — Step 3's own named
# guardrail. These pin that the record survives its own resolution, intact and attributable.
arch() { printf '%s/%s.jsonl' "$CC_PERMARCHIVE_DIR" "$(date +%Y-%m)"; }
arch_rows() { cat "$CC_PERMARCHIVE_DIR"/*.jsonl 2>/dev/null; }

@test "a resolved prompt is APPENDED to the durable archive before it is removed" {
  printf '%s' "$(payload s-arc 'git reset --hard origin/main')" | "$H" write
  printf '%s' "$(payload s-arc 'git reset --hard origin/main')" | "$H" clear
  [ ! -f "$(beacon s-arc)" ]                                   # still removed from the pending dir
  [ -f "$(arch)" ]
  run arch_rows
  [ "$(printf '%s' "$output" | jq -r '.session_id')" = s-arc ]
  [ "$(printf '%s' "$output" | jq -r '.tool_input.command')" = 'git reset --hard origin/main' ]
  [ "$(printf '%s' "$output" | jq -r '.cwd')" = /w/repo ]
  printf '%s' "$output" | jq -e '.ts and .resolved_ts and (.waited_s >= 0)'
}

@test "the archive is APPEND-ONLY — a second resolution never overwrites the first" {
  for s in s-a1 s-a2 s-a3; do
    printf '%s' "$(payload "$s" "cmd-$s")" | "$H" write
    printf '%s' "$(payload "$s" "cmd-$s")" | "$H" clear
  done
  [ "$(arch_rows | wc -l | tr -d ' ')" -eq 3 ]
  [ "$(arch_rows | jq -r '.session_id' | sort | tr '\n' ' ')" = "s-a1 s-a2 s-a3 " ]
}

@test "resolved_by distinguishes the GRANT path from the deny/abandon path" {
  # PostToolUse fires ONLY on grant; Stop fires on either. Without this field the archive cannot
  # tell an approval from a refusal, which is exactly what the classifier needs to learn from.
  jq -nc '{session_id:"s-grant",tool_name:"Bash",tool_input:{command:"x"},cwd:"/w",hook_event_name:"PostToolUse"}' | "$H" write
  jq -nc '{session_id:"s-grant",tool_name:"Bash",tool_input:{command:"x"},cwd:"/w",hook_event_name:"PostToolUse"}' | "$H" clear
  jq -nc '{session_id:"s-deny",tool_name:"Bash",tool_input:{command:"y"},cwd:"/w",hook_event_name:"Stop"}' | "$H" write
  jq -nc '{session_id:"s-deny",tool_name:"Bash",tool_input:{command:"y"},cwd:"/w",hook_event_name:"Stop"}' | "$H" clear
  [ "$(arch_rows | jq -r 'select(.session_id=="s-grant") | .resolved_by')" = PostToolUse ]
  [ "$(arch_rows | jq -r 'select(.session_id=="s-deny")  | .resolved_by')" = Stop ]
}

@test "waited_s carries the real block duration, not zero" {
  # The 17.7-hour block this work exists to surface must be measurable from the archive alone.
  printf '%s' "$(payload s-wait 'blocked')" | "$H" write
  b="$(beacon s-wait)"
  jq -c '.ts = (.ts - 3600)' "$b" > "$b.tmp" && mv "$b.tmp" "$b"    # backdate one hour
  printf '%s' "$(payload s-wait 'blocked')" | "$H" clear
  [ "$(arch_rows | jq -r 'select(.session_id=="s-wait") | .waited_s >= 3600')" = true ]
}

@test "a clear with NOTHING pending writes no archive row (no phantom prompts)" {
  printf '%s' "$(payload s-none x)" | "$H" clear
  [ -f "$(heartbeat)" ]                                        # the heartbeat still stamped...
  [ -z "$(arch_rows)" ]                                        # ...but the archive stays empty
}

@test "an over-long payload degrades to a bounded, EXPLICITLY-truncated row" {
  # Concurrent sessions append to one file; a multi-KB line risks a torn write. The row must stay
  # inside the atomic-append regime, and the truncation must be recorded rather than silent.
  big="$(printf 'y%.0s' $(seq 1 8000))"
  printf '%s' "$(payload s-big "$big")" | "$H" write
  printf '%s' "$(payload s-big "$big")" | "$H" clear
  row="$(arch_rows)"
  [ "${#row}" -lt 4096 ]
  [ "$(printf '%s' "$row" | jq -r '.tool_input_truncated')" = true ]
  printf '%s' "$row" | jq -e .                                 # still valid JSON, not a torn line
  [ "$(printf '%s' "$row" | jq -r '.session_id')" = s-big ]    # attribution survives truncation
}

@test "every archived row is valid JSON on its own line (jsonl contract)" {
  for s in j1 j2; do
    printf '%s' "$(payload "$s" 'a "quoted" \ backslash	tab')" | "$H" write
    printf '%s' "$(payload "$s" 'a "quoted" \ backslash	tab')" | "$H" clear
  done
  while read -r ln; do printf '%s' "$ln" | jq -e . >/dev/null; done < "$(arch)"
}

@test "the archive is NOT under CC_PERMPEND_DIR (which /tmp reboots away)" {
  # The record has to outlive the box's uptime or it can never accumulate the weeks of data the
  # classifier needs. Pinning this stops a future refactor from folding it back into /tmp.
  run bash -c 'grep -n "CC_PERMARCHIVE_DIR:-" "$1"' _ "$H"
  [ "$status" -eq 0 ]
  [[ "$output" != */tmp/* ]]
}

@test "ISOLATION CONTROL: the suite never writes the operator's real archive" {
  # This suite DID poison the live archive once, before CC_PERMARCHIVE_DIR was pinned in setup().
  [ -n "$CC_PERMARCHIVE_DIR" ]
  [[ "$CC_PERMARCHIVE_DIR" == "$BATS_TEST_TMPDIR"/* ]]
  [ "$CC_PERMARCHIVE_DIR" != "$HOME/.claude/autonomy/permission-archive" ]
}
