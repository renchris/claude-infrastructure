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
  # The key set gained tool_use_id when the archive learned to PROVE a grant rather than infer
  # one from tool names (adversarial review, 2026-07-31): the id of the prompted invocation has
  # to be captured HERE, at prompt time, or it is unrecoverable later. Reshaped deliberately —
  # this assertion is a contract claim about the producer, and the contract changed.
  [ "$(jq -rS 'keys|join(",")' "$b")" = "cwd,tool_input,tool_name,tool_use_id,ts" ]
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

@test "cleared_tool records WHICH tool cleared it, so a collateral clear is detectable" {
  # PostToolUse fires for every tool, not only the prompted one. After a DENIAL the turn can
  # continue and run some other tool whose PostToolUse clears this beacon — without cleared_tool
  # that denial is indistinguishable from an approval, and would be archived as one.
  #
  # RESHAPED 2026-09-09 with THE LIVE COLLATERAL-CLEAR GATE, and the reshape IS the contract change:
  # a mismatched PostToolUse no longer clears at all, so it can no longer reach the archive to be
  # attributed. The resolver here is therefore SessionEnd, which still clears unconditionally and
  # still carries a tool — the archive's attribution machinery is retained as defence-in-depth for
  # the resolvers that clear without checking. The live half (a collateral PostToolUse leaves the
  # beacon standing) is pinned in the LIVE GATE group below.
  jq -nc '{session_id:"s-coll",tool_name:"Bash",tool_input:{command:"rm -rf /"},cwd:"/w"}' | "$H" write
  jq -nc '{session_id:"s-coll",tool_name:"Read",hook_event_name:"SessionEnd"}' | "$H" clear
  row="$(arch_rows | jq -r 'select(.session_id=="s-coll")')"
  [ "$(printf '%s' "$row" | jq -r '.tool_name')"    = Bash ]        # what was PROMPTED for
  [ "$(printf '%s' "$row" | jq -r '.cleared_tool')" = Read ]        # what CLEARED it
}

@test "a genuine grant records the SAME tool in both fields" {
  # The clearing payload now carries the SAME tool_input as the prompt: since the live gate landed,
  # a PostToolUse only clears the invocation it is the PostToolUse OF, and a genuine grant is
  # exactly that case. Bare tool_name would be a COLLATERAL clear and is now refused.
  jq -nc '{session_id:"s-gr",tool_name:"Bash",tool_input:{command:"ls"},cwd:"/w"}' | "$H" write
  jq -nc '{session_id:"s-gr",tool_name:"Bash",tool_input:{command:"ls"},hook_event_name:"PostToolUse"}' | "$H" clear
  row="$(arch_rows | jq -r 'select(.session_id=="s-gr")')"
  [ "$(printf '%s' "$row" | jq -r '.tool_name')" = "$(printf '%s' "$row" | jq -r '.cleared_tool')" ]
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
  [[ "$CC_PERMARCHIVE_DIR" == "$BATS_TEST_TMPDIR"/* ]] || false
  [ "$CC_PERMARCHIVE_DIR" != "$HOME/.claude/autonomy/permission-archive" ]
}

# ── Adversarial-review fixes (verify-beacon/verify-audit, 2026-07-31) ────────────────────────────
@test "D2: two concurrent clears archive the prompt EXACTLY ONCE" {
  # `[[ -f ]]` → archive → rm had no mutual exclusion, so a trailing PostToolUse racing the turn's
  # Stop had both clears pass the test and both append: ONE prompt, TWO rows, landing in BOTH
  # buckets at once. Measured 40/40 before the atomic `mv` claim, 0/40 after.
  for i in 1 2 3 4 5 6 7 8; do
    printf '%s' "$(payload "race-$i" 'git push --force')" | "$H" write
    printf '%s' "$(jq -nc --arg s "race-$i" '{session_id:$s,hook_event_name:"PostToolUse",tool_name:"Bash"}')" | "$H" clear &
    printf '%s' "$(jq -nc --arg s "race-$i" '{session_id:$s,hook_event_name:"Stop"}')" | "$H" clear &
    wait
  done
  [ "$(arch_rows | wc -l | tr -d ' ')" -eq 8 ]
  [ "$(arch_rows | jq -r '.session_id' | sort -u | wc -l | tr -d ' ')" -eq 8 ]
}

@test "D2: the atomic claim file is invisible to the supervisor's *.json glob" {
  # A claim left visible would be paged as a phantom pending prompt.
  printf '%s' "$(payload s-claim x)" | "$H" write
  printf '%s' "$(payload s-claim x)" | "$H" clear
  found=0
  for f in "$CC_PERMPEND_DIR"/*.json; do [ -e "$f" ] && found=$((found + 1)); done
  [ "$found" -eq 0 ]
}

@test "D1: tool_use_id is captured from BOTH the prompt and the clear" {
  # The only evidence that distinguishes a real grant from a same-named collateral clear.
  jq -nc '{session_id:"s-id",tool_name:"Bash",tool_input:{command:"ls"},cwd:"/w",tool_use_id:"toolu_P"}' | "$H" write
  # tool_input added to the clearing side when the live gate landed — see the note on s-gr above.
  jq -nc '{session_id:"s-id",hook_event_name:"PostToolUse",tool_name:"Bash",tool_input:{command:"ls"},tool_use_id:"toolu_C"}' | "$H" clear
  row="$(arch_rows | jq -r 'select(.session_id=="s-id")')"
  [ "$(printf '%s' "$row" | jq -r '.tool_use_id')"         = toolu_P ]
  [ "$(printf '%s' "$row" | jq -r '.cleared_tool_use_id')" = toolu_C ]
}

# ── THE INVOCATION SIGNATURE — the discriminator that is actually populated ──────────────────────
# WHY: the D1 arm above pins that tool_use_id is CAPTURED from both sides, and it passed for five
# weeks over a field the harness never populates. PermissionRequest ships tool_use_id as "" in 0 of
# 3,641 archived records, so the id rule the consumer prefers could never once fire and every real
# row fell through to the tool-NAME path the code explicitly rejects (`approved 0 · unknown 3359`
# over 3,763 prompts). These arms pin the replacement, and each one is RED against the pre-fix
# handler, which emits no signature at all. Every payload below therefore carries tool_use_id:""
# EXACTLY as the live harness sends it — the point is a verdict reached without that field.
@test "SIG: a grant is provable with NO tool_use_id — identical invocation ⇒ matching signatures" {
  jq -nc '{session_id:"s-sig1",tool_name:"Bash",tool_input:{command:"git push --force"},cwd:"/w",tool_use_id:""}' | "$H" write
  jq -nc '{session_id:"s-sig1",hook_event_name:"PostToolUse",tool_name:"Bash",tool_input:{command:"git push --force"},tool_use_id:"toolu_C"}' | "$H" clear
  row="$(arch_rows | jq -c 'select(.session_id=="s-sig1")')"
  [ -n "$row" ]
  [ "$(printf '%s' "$row" | jq -r '.tool_use_id')" = "" ]        # the field the old rule needed
  sb="$(printf '%s' "$row" | jq -r '.tool_sig')"
  sc="$(printf '%s' "$row" | jq -r '.cleared_tool_sig')"
  [ -n "$sb" ] && [ "$sb" != null ] || false
  [ "$sb" = "$sc" ]
}

@test "SIG: a COLLATERAL clear by the same tool with a different command does NOT match" {
  # The exact unsafe case: Bash→Bash is ~all this fleet's traffic, so tool NAMES agree here and
  # only the invocation separates a denied `git push --force` from a later `git status`. Measured
  # 2026-09-09: 19 of the 27 real mismatches in the archive are exactly this Bash > Bash shape.
  #
  # The resolver is SessionEnd since the live gate landed — a mismatched PostToolUse no longer
  # clears, so it can no longer produce a row to inspect. What this arm still pins is that the
  # SIGNATURE machinery separates the two invocations for the unconditional resolvers.
  jq -nc '{session_id:"s-sig2",tool_name:"Bash",tool_input:{command:"git push --force"},cwd:"/w",tool_use_id:""}' | "$H" write
  jq -nc '{session_id:"s-sig2",hook_event_name:"SessionEnd",tool_name:"Bash",tool_input:{command:"git status"},tool_use_id:"toolu_C"}' | "$H" clear
  row="$(arch_rows | jq -c 'select(.session_id=="s-sig2")')"
  [ "$(printf '%s' "$row" | jq -r '.tool_name')" = "$(printf '%s' "$row" | jq -r '.cleared_tool')" ]
  sb="$(printf '%s' "$row" | jq -r '.tool_sig')"
  sc="$(printf '%s' "$row" | jq -r '.cleared_tool_sig')"
  [ -n "$sb" ] && [ -n "$sc" ] || false
  [ "$sb" != "$sc" ]
}

@test "SIG: key ORDER in tool_input is not a difference (the canonical form sorts recursively)" {
  # The harness has no key-order guarantee across two events. If it did not sort, an identical
  # invocation would digest differently and a real grant would be recorded as collateral —
  # failure in the SAFE direction, but a permanently unusable dataset all the same.
  jq -nc '{session_id:"s-sig3",tool_name:"Write",tool_input:{file_path:"/x.ts",content:"z",opts:{b:1,a:2}},cwd:"/w",tool_use_id:""}' | "$H" write
  jq -nc '{session_id:"s-sig3",hook_event_name:"PostToolUse",tool_name:"Write",tool_input:{opts:{a:2,b:1},content:"z",file_path:"/x.ts"},tool_use_id:""}' | "$H" clear
  row="$(arch_rows | jq -c 'select(.session_id=="s-sig3")')"
  sb="$(printf '%s' "$row" | jq -r '.tool_sig')"
  # NON-VACUITY, and it is not decoration: an equality between two ABSENT fields is `null = null`,
  # which passed against the pre-fix handler that emits no signature at all. Pinning the value
  # present is what makes this arm test the canonicalisation instead of the absence.
  [ -n "$sb" ] && [ "$sb" != null ] || false
  [ "$sb" = "$(printf '%s' "$row" | jq -r '.cleared_tool_sig')" ]
}

@test "SIG: two UNREADABLE sides never digest to the same value (no grant made of two errors)" {
  # The trap in the naive form: `printf '' | shasum` yields a perfectly good digest of the empty
  # string, so a payload the hook could not parse would match another payload it could not parse
  # and manufacture an approval. A canonical form is emitted only when tool_name is non-empty.
  # Resolved by Stop since the live gate landed: an unsignable beacon can no longer be cleared by
  # PostToolUse at all (that arm is in the LIVE GATE group), and Stop is what drains it in the wild.
  jq -nc '{session_id:"s-sig4",tool_input:{command:"x"},cwd:"/w"}' | "$H" write      # no tool_name
  jq -nc '{session_id:"s-sig4",hook_event_name:"Stop"}' | "$H" clear                 # no tool_name
  row="$(arch_rows | jq -c 'select(.session_id=="s-sig4")')"
  [ -n "$row" ]                                            # the row is still archived, not dropped
  [ "$(printf '%s' "$row" | jq -r '.tool_sig')" = "" ]
  [ "$(printf '%s' "$row" | jq -r '.cleared_tool_sig')" = "" ]
}

@test "SIG: an over-long payload keeps its signatures — truncation drops INPUT, never attribution" {
  # The truncated fallback used to drop cleared_tool and cleared_tool_use_id outright, so an
  # over-cap prompt was unattributable by construction. Attribution is 32 bytes and always fits.
  big="$(python3 -c 'print("x"*4000)')"
  jq -nc --arg c "$big" '{session_id:"s-sig5",tool_name:"Bash",tool_input:{command:$c},cwd:"/w",tool_use_id:""}' | "$H" write
  jq -nc --arg c "$big" '{session_id:"s-sig5",hook_event_name:"PostToolUse",tool_name:"Bash",tool_input:{command:$c},tool_use_id:""}' | "$H" clear
  row="$(arch_rows | jq -c 'select(.session_id=="s-sig5")')"
  [ "$(printf '%s' "$row" | jq -r '.tool_input_truncated')" = true ]
  sb="$(printf '%s' "$row" | jq -r '.tool_sig')"
  [ -n "$sb" ] && [ "$sb" != null ] || false
  [ "$sb" = "$(printf '%s' "$row" | jq -r '.cleared_tool_sig')" ]
}

# ── THE LIVE COLLATERAL-CLEAR GATE — a mismatched PostToolUse must not blind the board ──────────
# WHY: the SIG group above pins that a collateral clear is DETECTABLE after the fact. It is, and the
# archive is correct. But the same collateral clear also DELETED the live beacon, so the supervisor
# went blind to a prompt still on screen — the header's "dir present, no <sid>.json ⇒ genuinely
# nothing pending" was false for that population. Measured 2026-09-09: 27 of 110 signed archive rows
# (24%) were cleared by a different invocation, every one of them resolved_by PostToolUse (0 Stop,
# 0 SessionEnd); pane 616 sat on an unanswered `rm -r` across two screen samples with no beacon at
# all. The first arm below is the RED-proof — it FAILS against the pre-fix handler, which deletes
# the beacon here. The vector (background task vs. a second foreground tool in the same turn) is
# UNMEASURED and deliberately not named: the gate keys on signature equality either way.
#
# WHICH ARMS ARE THE RED-PROOF, stated so the group cannot be mistaken for one. Run against the
# pre-fix hook (git HEAD before this commit) in a shape-identical scratch tree, with the SAME .bats
# file: the three unlabelled arms go RED (the beacon was deleted, so it is gone before Stop can
# drain it and no Stop-resolved row is ever written); the three labelled "green both ways BY DESIGN"
# pass on both sides, because they guard the fix from OVER-reaching — a gate that also blocked Stop,
# SessionEnd, or the heartbeats would leak a beacon forever or invert the existence-evidence split.
@test "LIVE GATE: a MISMATCHED PostToolUse does NOT clear — the beacon SURVIVES for the board" {
  jq -nc '{session_id:"s-live1",tool_name:"Bash",tool_input:{command:"rm -r $CH"},cwd:"/w",tool_use_id:""}' | "$H" write
  [ -f "$(beacon s-live1)" ]
  run bash -c 'printf "%s" "$1" | "$2" clear' _ \
    "$(jq -nc '{session_id:"s-live1",hook_event_name:"PostToolUse",tool_name:"Bash",tool_input:{command:"git status"},tool_use_id:"toolu_C"}')" "$H"
  [ "$status" -eq 0 ]                                   # still fail-quiet: it refuses, it never errors
  [ -f "$(beacon s-live1)" ]                            # ← RED pre-fix: the beacon was deleted here
  # and it is still READABLE as the original prompt, not a husk — this is what the board renders
  [ "$(jq -r '.tool_input.command' "$(beacon s-live1)")" = 'rm -r $CH' ]
  # no phantom row either: an unresolved prompt has not been resolved, so nothing is archived yet
  [ -z "$(arch_rows | jq -r 'select(.session_id=="s-live1")')" ]
}

@test "LIVE GATE (green both ways BY DESIGN): the MATCHING PostToolUse still clears — the GRANT path" {
  jq -nc '{session_id:"s-live2",tool_name:"Bash",tool_input:{command:"rm -r $CH"},cwd:"/w",tool_use_id:""}' | "$H" write
  jq -nc '{session_id:"s-live2",hook_event_name:"PostToolUse",tool_name:"Bash",tool_input:{command:"rm -r $CH"},tool_use_id:"toolu_C"}' | "$H" clear
  [ ! -f "$(beacon s-live2)" ]                          # the gated tool ran ⇒ the fast clear survives
  row="$(arch_rows | jq -c 'select(.session_id=="s-live2")')"
  [ -n "$row" ]
  [ "$(printf '%s' "$row" | jq -r '.resolved_by')" = PostToolUse ]
  # by construction of the gate, a PostToolUse-resolved row can now only ever carry matching sigs
  [ "$(printf '%s' "$row" | jq -r '.tool_sig')" = "$(printf '%s' "$row" | jq -r '.cleared_tool_sig')" ]
}

@test "LIVE GATE: Stop clears a MISMATCHED invocation unconditionally — the DENY path still drains" {
  # The property the gate must not break. A DENIED prompt fires no matching PostToolUse EVER, so if
  # Stop were gated too the beacon would leak forever and the board would page a phantom. The turn
  # cannot Stop until the human answers, so Stop remains the universal clearer.
  jq -nc '{session_id:"s-live3",tool_name:"Bash",tool_input:{command:"git push --force"},cwd:"/w",tool_use_id:""}' | "$H" write
  jq -nc '{session_id:"s-live3",hook_event_name:"PostToolUse",tool_name:"Bash",tool_input:{command:"git status"},tool_use_id:""}' | "$H" clear
  [ -f "$(beacon s-live3)" ]                            # the collateral PostToolUse was refused…
  jq -nc '{session_id:"s-live3",hook_event_name:"Stop"}' | "$H" clear
  [ ! -f "$(beacon s-live3)" ]                          # …and the turn's Stop drained it
  [ "$(arch_rows | jq -r 'select(.session_id=="s-live3") | .resolved_by')" = Stop ]
}

@test "LIVE GATE (green both ways BY DESIGN): SessionEnd clears unconditionally — the no-Stop backstop" {
  jq -nc '{session_id:"s-live4",tool_name:"Bash",tool_input:{command:"a"},cwd:"/w",tool_use_id:""}' | "$H" write
  jq -nc '{session_id:"s-live4",hook_event_name:"SessionEnd",tool_name:"Bash",tool_input:{command:"b"}}' | "$H" clear
  [ ! -f "$(beacon s-live4)" ]
  [ "$(arch_rows | jq -r 'select(.session_id=="s-live4") | .resolved_by')" = SessionEnd ]
}

@test "LIVE GATE: an UNSIGNABLE beacon is never cleared by PostToolUse (no clear out of two errors)" {
  # The same trap CANON's guard exists for, one layer up: "" == "" must not read as proof the gated
  # tool ran, or two unparseable payloads would manufacture a clear and blind the board. Leaving it
  # for Stop is the safe direction and leaks nothing.
  jq -nc '{session_id:"s-live5",tool_input:{command:"x"},cwd:"/w"}' | "$H" write      # no tool_name
  jq -nc '{session_id:"s-live5",hook_event_name:"PostToolUse"}' | "$H" clear          # no tool_name
  [ -f "$(beacon s-live5)" ]
  jq -nc '{session_id:"s-live5",hook_event_name:"Stop"}' | "$H" clear
  [ ! -f "$(beacon s-live5)" ]
}

@test "LIVE GATE (green both ways BY DESIGN): the refused clear still stamps BOTH heartbeats" {
  # The refusal returns early. If it returned before beat/arch_beat, a session whose only traffic
  # was collateral clears would look INERT — the three-state split inverted by the fix meant to
  # protect it.
  jq -nc '{session_id:"s-live6",tool_name:"Bash",tool_input:{command:"a"},cwd:"/w"}' | "$H" write
  rm -f "$CC_PERMPEND_DIR/.beacon-alive" "$CC_PERMARCHIVE_DIR/.archive-alive"
  jq -nc '{session_id:"s-live6",hook_event_name:"PostToolUse",tool_name:"Bash",tool_input:{command:"b"}}' | "$H" clear
  [ -f "$CC_PERMPEND_DIR/.beacon-alive" ]
  [ -f "$CC_PERMARCHIVE_DIR/.archive-alive" ]
}

# ── THE APPEND MUTEX MUST BE ABLE TO RECOVER FROM ITS OWN ORPHAN ─────────────────────────────────
# WHY: `mkdir` is atomic, but a process killed between the mkdir and the rmdir leaves the lock dir
# standing with no owner and no age bound, and from that instant every later resolution loses the
# lock and takes the sidecar fallback. That is not hypothetical — it happened. Measured on the live
# archive 2026-09-07: `.append.lock` was an EMPTY directory dated 2026-08-07 17:35, the first
# sidecar appeared 22 minutes later, and the split since was 546 rows in the month files against
# 3,223 rows across 3,221 sidecars, with no `2026-09.jsonl` in existence. Nothing was lost, which
# is precisely why nobody saw it: the fallback hid that the mechanism it falls back FROM was dead.
lockdir() { printf '%s/.append.lock' "$CC_PERMARCHIVE_DIR"; }
month_file() { printf '%s/%s.jsonl' "$CC_PERMARCHIVE_DIR" "$(date +%Y-%m)"; }
# Count the per-process fallback files. GLOB, never `ls | grep` (SC2010): a sidecar is
# `<month>.<sid>.<pid>.jsonl` — three literal dots — while a month file is `<month>.jsonl` with
# one, so the pattern separates them without parsing ls output.
sidecars() {
  local n=0 f
  for f in "$CC_PERMARCHIVE_DIR"/*.*.*.jsonl; do [ -e "$f" ] && n=$(( n + 1 )); done
  printf '%s' "$n"
}

@test "LOCK: an ORPHANED append lock is broken, and the row lands in the MONTH file" {
  mkdir -p "$CC_PERMARCHIVE_DIR"
  mkdir "$(lockdir)"                                  # the orphan: empty, no owner
  touch -t 202601010000 "$(lockdir)"                  # …and far older than the staleness bound
  printf '%s' "$(payload s-lk1 'git push --force')" | "$H" write
  printf '%s' "$(payload s-lk1 'git push --force')" | "$H" clear
  [ -f "$(month_file)" ]
  [ "$(grep -c s-lk1 "$(month_file)")" -eq 1 ]
  [ "$(sidecars)" -eq 0 ]                             # nothing took the failure path
  [ ! -d "$(lockdir)" ]                               # …and the lock was released, not left behind
}

@test "LOCK: a lock held by a LIVE owner is NOT broken — the row takes the sidecar instead" {
  # The safety direction, and the one that matters: breaking a lock someone is holding re-admits
  # the torn line the mutex exists to prevent. Green against the pre-fix handler too (it never
  # breaks anything) — this arm guards the FIX, not the bug.
  mkdir -p "$CC_PERMARCHIVE_DIR"
  mkdir "$(lockdir)"
  printf '%s' "$$" > "$(lockdir)/owner"               # this very bats process: provably alive
  touch -t 202601010000 "$(lockdir)"                  # old enough that ONLY liveness can save it
  printf '%s' "$(payload s-lk2 x)" | "$H" write
  printf '%s' "$(payload s-lk2 x)" | "$H" clear
  [ -d "$(lockdir)" ]                                 # the live holder kept it
  [ "$(sidecars)" -eq 1 ]
  ! grep -q s-lk2 "$(month_file)" 2>/dev/null
}

@test "LOCK (green both ways BY DESIGN): a FRESH ownerless lock is NOT broken — the age bound" {
  # Between `mkdir` and the owner file being written, a legitimate holder has no owner recorded.
  # Without an age bound a racing breaker would delete a lock taken microseconds ago. Like the
  # live-owner arm above, this cannot go red against the pre-fix handler, which never breaks
  # anything — it guards the FIX from becoming over-eager, and is not part of the red-proof set.
  mkdir -p "$CC_PERMARCHIVE_DIR"
  mkdir "$(lockdir)"                                  # ownerless, but brand new
  printf '%s' "$(payload s-lk3 x)" | "$H" write
  printf '%s' "$(payload s-lk3 x)" | "$H" clear
  [ -d "$(lockdir)" ]
  [ "$(sidecars)" -eq 1 ]
}

@test "LOCK (green both ways BY DESIGN): the release removes the owner file, not just the dir" {
  # `rmdir` refuses a non-empty directory. A release that only rmdir'd would leave the lock
  # standing forever — re-creating by hand the exact orphan this whole group cures. Green against
  # the pre-fix handler because it writes no owner file to begin with; this arm exists so the
  # owner file the FIX introduces can never become the next orphan.
  mkdir -p "$CC_PERMARCHIVE_DIR"
  printf '%s' "$(payload s-lk4 x)" | "$H" write
  printf '%s' "$(payload s-lk4 x)" | "$H" clear
  [ ! -d "$(lockdir)" ]
  [ "$(sidecars)" -eq 0 ]
  [ "$(grep -c s-lk4 "$(month_file)")" -eq 1 ]
  # and a SECOND resolution still lands in the month file, which is what proves the release worked
  printf '%s' "$(payload s-lk5 x)" | "$H" write
  printf '%s' "$(payload s-lk5 x)" | "$H" clear
  [ "$(grep -c s-lk5 "$(month_file)")" -eq 1 ]
  [ "$(sidecars)" -eq 0 ]
}

@test "D5: the archive gets its own heartbeat, so dir-exists means the archiver RAN" {
  # Without this, ARCHDIR was created only by an append, so a running archiver with nothing to
  # record left no evidence and the consumer's three-state split was mapped the wrong way round.
  printf '%s' "$(payload s-hbA x)" | "$H" clear          # nothing pending
  [ -f "$CC_PERMARCHIVE_DIR/.archive-alive" ]
  [ -z "$(arch_rows)" ]                                   # ...and still no phantom row
}

@test "D1 REGRESSION: an unset HOME must not take down the whole beacon" {
  # ARCHDIR's $HOME default sits ABOVE the mode dispatch under `set -u`, so an unset HOME aborted
  # the ENTIRE hook at rc=1 — `write` never ran and the supervisor went blind to a real prompt.
  # An archive convenience may never break the beacon it is a side-car to.
  run env -u HOME CC_PERMPEND_DIR="$CC_PERMPEND_DIR" CC_PERMARCHIVE_DIR="$CC_PERMARCHIVE_DIR" \
      bash -c 'printf "%s" "$1" | "$2" write' _ "$(payload s-nohome 'git push --force')" "$H"
  [ "$status" -eq 0 ]
  [ -f "$(beacon s-nohome)" ]
}

@test "D2a: the size bound is in BYTES, so multibyte payloads are truncated too" {
  # ${#line} counts CHARACTERS: 3,000 CJK characters measured 3,215 against the 3500 cap while
  # occupying 9,215 bytes, so truncation never fired and the row was 2.25x the atomicity regime.
  cjk="$(python3 -c "print('中'*3000)")"
  printf '%s' "$(payload s-cjk "$cjk")" | "$H" write
  printf '%s' "$(payload s-cjk "$cjk")" | "$H" clear
  row="$(arch_rows)"
  [ "$(printf '%s' "$row" | jq -r '.tool_input_truncated')" = true ]
  [ "$(printf '%s' "$row" | LC_ALL=C wc -c | tr -d ' ')" -lt 4096 ]
}

@test "D2b: concurrent clears at 1.2 KB rows produce no torn lines" {
  # "a single small write under O_APPEND does not interleave" measured FALSE: 10 of 720 lines tore
  # at this size, merging two sessions into one unparseable row. Appends are serialized now.
  big="$(python3 -c "print('y'*1200)")"
  for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
    printf '%s' "$(payload "tear-$i" "$big")" | "$H" write
  done
  for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
    printf '%s' "$(jq -nc --arg s "tear-$i" '{session_id:$s,hook_event_name:"Stop"}')" | "$H" clear &
  done
  wait
  [ "$(arch_rows | wc -l | tr -d ' ')" -eq 12 ]
  while read -r ln; do printf '%s' "$ln" | jq -e . >/dev/null; done < <(arch_rows)
}

@test "D3: a failed archive PRESERVES the record instead of deleting it" {
  # rm ran unconditionally, so an unwritable archive destroyed the very evidence it exists to keep.
  printf '%s' "$(payload s-lost 'git reset --hard')" | "$H" write
  chmod 500 "$CC_PERMARCHIVE_DIR" 2>/dev/null || mkdir -p "$CC_PERMARCHIVE_DIR"
  chmod 500 "$CC_PERMARCHIVE_DIR"
  printf '%s' "$(jq -nc '{session_id:"s-lost",hook_event_name:"Stop"}')" | "$H" clear
  chmod 755 "$CC_PERMARCHIVE_DIR"
  # the claim is retained (dot-prefixed, so it cannot re-page) — the record still exists on disk
  n=0
  for f in "$CC_PERMPEND_DIR"/.claimed-s-lost.*; do [ -e "$f" ] && n=$((n + 1)); done
  [ "$n" -ge 1 ]
}
