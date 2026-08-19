#!/usr/bin/env bats
# Phase 1 — cross-session comms registry:
#   hooks/session-register.sh · hooks/session-deregister.sh · bin/cc-sessions
#
# Isolated via CC_REGISTRY_DIR (temp) and IT2_BIN (a stub that fakes
# `it2 session list --json`). No real iTerm2 / ~/.claude state is touched.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  # Rule-2 pin (scripts/test-hermeticity-lint.sh). This suite drives no fire — it is in scope only
  # because `references_fire()` greps the whole file for the literal `handoff-fire`, and a comment
  # below names it as the writer of provisional rows. Pinning is the lint's prescribed fix and is
  # inert here; rewording the comment to fall out of scope would be evading the ratchet, and it
  # would leave the suite unpinned if it ever does reach the fire.
  export CC_FIRE_CAPACITY_GATE=off
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

  # The write-side tenancy gate journals its refusals. Without this the suite would append to the
  # operator's live ~/.claude/autonomy/idl.jsonl — a test that writes production state is not
  # hermetic, and cc-audit/cc-digest read that file.
  export SESSION_REGISTER_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
}

# helper: write a registry entry file directly
mkentry() { # $1=uuid $2=name $3=pid [$4=session_id]
  mkdir -p "$CC_REGISTRY_DIR"
  if [ -n "${4:-}" ]; then
    printf '{"paneUUID":"%s","name":"%s","cwd":"/tmp","account":"next","pid":%s,"startedAt":1,"session_id":"%s"}' \
      "$1" "$2" "$3" "$4" > "$CC_REGISTRY_DIR/$1.json"
  else
    # No $4 ⇒ the sid-less shape: a provisional row (handoff-fire ensure_registration) or a
    # register() run whose hook input carried no session_id.
    printf '{"paneUUID":"%s","name":"%s","cwd":"/tmp","account":"next","pid":%s,"startedAt":1}' \
      "$1" "$2" "$3" > "$CC_REGISTRY_DIR/$1.json"
  fi
}

# helper: a definitely-dead pid
deadpid() { sleep 1 & local p=$!; kill "$p" 2>/dev/null || true; wait "$p" 2>/dev/null || true; echo "$p"; }

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

# --- P8 (7b2f701): PRESENCE MUST NOT ENCODE LIVENESS -------------------------------------
# A dead-pid / gone-pane entry is no longer rm -f'd on read (that deleted exactly the rows
# that prove a spawn-death). The three roles are split:
#   VIEW      -> the default lister emits LIVE rows only, so a dead pane is ABSENT from the
#                addressing view (--names/--json/table) and cc-notify can never resolve onto it.
#   RETENTION -> the FILE is kept for CC_REG_RETAIN_H (default 24h) so the spawn-death stays
#                investigable, THEN reaped for hygiene on AGE — never on the liveness signal.
#   FORENSIC  -> `cc-sessions --all` re-includes the retained-dead rows.
# These pin that contract; each goes RED against the pre-7b2f701 immediate-rm-f binary.

@test "cc-sessions: a dead-pid entry is hidden from addressing but RETAINED for forensics (even if pane present)" {
  dead="$(deadpid)"
  export IT2_STUB_PANES="BBBBBBBB-0000-0000-0000-000000000000"   # pane still listed — pid death is authoritative
  mkentry "BBBBBBBB-0000-0000-0000-000000000000" "ghost" "$dead"
  # addressing view (default): the dead entry is absent, so a name can't resolve onto a dead pane
  run bash "$CCS" --names
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
  # retention: its file survives (age < CC_REG_RETAIN_H) so the spawn-death stays investigable
  [ -f "$CC_REGISTRY_DIR/BBBBBBBB-0000-0000-0000-000000000000.json" ]
  # forensic view: --all re-includes it
  run bash "$CCS" --all --names
  [ "$status" -eq 0 ]
  [ "$output" = "ghost" ]
}

@test "cc-sessions: a gone-pane entry (pid alive) is hidden from addressing but RETAINED" {
  export IT2_STUB_PANES="OTHER-UUID"   # our uuid NOT in the list — pane-absence marks it non-live
  mkentry "CCCCCCCC-0000-0000-0000-000000000000" "detached" "$$"
  run bash "$CCS" --names
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
  [ -f "$CC_REGISTRY_DIR/CCCCCCCC-0000-0000-0000-000000000000.json" ]
  run bash "$CCS" --all --names
  [ "$status" -eq 0 ]
  [ "$output" = "detached" ]
}

@test "cc-sessions: a dead entry OLDER than CC_REG_RETAIN_H is reaped (retention keys on AGE, not liveness)" {
  dead="$(deadpid)"
  export IT2_STUB_PANES="EEEEEEEE-0000-0000-0000-000000000000"   # pane present; pid dead → stale
  # startedAt = 2h ago; shrink the retention window to 1h → past the window → reaped even from --all
  started_ms=$(( ($(date +%s) - 7200) * 1000 ))
  mkdir -p "$CC_REGISTRY_DIR"
  printf '{"paneUUID":"EEEEEEEE-0000-0000-0000-000000000000","name":"oldghost","cwd":"/tmp","account":"next","pid":%s,"startedAt":%s}' \
    "$dead" "$started_ms" > "$CC_REGISTRY_DIR/EEEEEEEE-0000-0000-0000-000000000000.json"
  export CC_REG_RETAIN_H=1
  run bash "$CCS" --all --names
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
  [ ! -f "$CC_REGISTRY_DIR/EEEEEEEE-0000-0000-0000-000000000000.json" ]
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

@test "deregister: removes the entry when the ending session OWNS the row" {
  mkentry "AAAAAAAA-1111-2222-3333-444444444444" "bye" "$$" "SID-OWNER"
  printf '{"reason":"exit","session_id":"SID-OWNER"}' \
    | ITERM_SESSION_ID="w1t0p0:AAAAAAAA-1111-2222-3333-444444444444" bash "$DEREG"
  [ ! -f "$CC_REGISTRY_DIR/AAAAAAAA-1111-2222-3333-444444444444.json" ]
}

@test "deregister: skips on reason=clear (pane persists, re-registers next)" {
  # Sid MATCHES deliberately: reason=clear must be the only thing keeping this row, or the test
  # passes on the tenancy gate and stops covering the clear-skip at all.
  mkentry "AAAAAAAA-1111-2222-3333-444444444444" "keep" "$$" "SID-OWNER"
  printf '{"reason":"clear","session_id":"SID-OWNER"}' \
    | ITERM_SESSION_ID="w1t0p0:AAAAAAAA-1111-2222-3333-444444444444" bash "$DEREG"
  [ -f "$CC_REGISTRY_DIR/AAAAAAAA-1111-2222-3333-444444444444.json" ]
}

# ── TENANCY: the `claude mcp list` phantom (2026-08-05) ───────────────────────────────────────
# hooks/session-start.sh:63 runs `claude mcp list` on every SessionStart; that subprocess emits a
# SessionEnd of its own — reason "other", a fresh session_id, NO matching SessionStart — carrying
# the live pane's inherited CC_PANE_ID/ITERM_SESSION_ID. Verbatim event shape, captured from a
# real run against the deployed hook. Pre-fix this deleted the row the pane had just written.
@test "deregister: refuses to remove a row owned by a DIFFERENT session (mcp-list phantom)" {
  mkentry "AAAAAAAA-1111-2222-3333-444444444444" "live" "$$" "SID-OWNER"
  printf '{"session_id":"17b8b21f-ce62-4233-ae6f-a11db5cb5d16","cwd":"/private/tmp","hook_event_name":"SessionEnd","reason":"other"}' \
    | CC_PANE_ID="AAAAAAAA-1111-2222-3333-444444444444" bash "$DEREG"
  [ -f "$CC_REGISTRY_DIR/AAAAAAAA-1111-2222-3333-444444444444.json" ]
  run jq -r '.session_id' "$CC_REGISTRY_DIR/AAAAAAAA-1111-2222-3333-444444444444.json"
  [ "$output" = "SID-OWNER" ]
}

@test "deregister: refuses when the ending session carries no session_id" {
  mkentry "AAAAAAAA-1111-2222-3333-444444444444" "live" "$$" "SID-OWNER"
  printf '{"reason":"other"}' | ITERM_SESSION_ID="w1t0p0:AAAAAAAA-1111-2222-3333-444444444444" bash "$DEREG"
  [ -f "$CC_REGISTRY_DIR/AAAAAAAA-1111-2222-3333-444444444444.json" ]
}

@test "deregister: refuses on a sid-less provisional row (tenancy unprovable)" {
  mkentry "AAAAAAAA-1111-2222-3333-444444444444" "prov" "$$"
  printf '{"reason":"other","session_id":"SID-ANY"}' \
    | ITERM_SESSION_ID="w1t0p0:AAAAAAAA-1111-2222-3333-444444444444" bash "$DEREG"
  [ -f "$CC_REGISTRY_DIR/AAAAAAAA-1111-2222-3333-444444444444.json" ]
}

@test "deregister: a null session_id in the row is unprovable, not a match" {
  mkdir -p "$CC_REGISTRY_DIR"
  printf '{"paneUUID":"AAAAAAAA-1111-2222-3333-444444444444","name":"n","pid":1,"session_id":null}' \
    > "$CC_REGISTRY_DIR/AAAAAAAA-1111-2222-3333-444444444444.json"
  printf '{"reason":"other","session_id":"SID-ANY"}' \
    | ITERM_SESSION_ID="w1t0p0:AAAAAAAA-1111-2222-3333-444444444444" bash "$DEREG"
  [ -f "$CC_REGISTRY_DIR/AAAAAAAA-1111-2222-3333-444444444444.json" ]
}

# ── WRITE-SIDE TENANCY (backlog 55e1e65c7548) ──────────────────────────────────────────────────
# The deregister cases above prove the REMOVE side cannot delete another session's row. These prove
# the WRITE side cannot overwrite one. Same hazard, other direction: CC_PANE_ID/ITERM_SESSION_ID are
# inherited by every child process, so a nested `claude` (a `claude -p` probe, an upgrade-gate check,
# any script that shells out to the CLI) arrives at register() holding the LIVE pane's id. Measured
# 2026-08-08 against the deployed hook: one such child replaced pane 841's row with its own pid and
# sid, and that pid was dead before the probe returned — a dead-pid corpse on a pane whose claude was
# alive throughout, which cc-sessions hides from the addressing view for up to CC_REG_RETAIN_H.
#
# The gate refuses ONLY when the row's owner is a live ANCESTOR of this process. The four controls
# below are the other half of the contract: a live-but-unrelated pid, a dead pid, an absent row and a
# pid-less provisional row must all still be written, or the gate would wedge panes it is meant to
# protect. They are not decoration — a gate that refuses everything passes the first test alone.

PANE_T="BBBBBBBB-1111-2222-3333-444444444444"
CHILD='{"cwd":"/tmp/child","session_id":"CHILD-SID","reason":"startup","hook_event_name":"SessionStart"}'

# helper: run the hook as a NESTED claude — outer `claude` seeds the pane row with its OWN pid (the
# tenant registering), then spawns an inner `claude` that runs the hook (the probe squatting).
#
# `ln -s /bin/bash …/claude` yields a process whose `ps -o comm=` basename is `claude`, which is what
# the hook's ancestor walk matches. It must be a SYMLINK: a copy of /bin/bash does not execute on
# this box (measured — it fails silently, which would make the fixture pass vacuously). And it must
# exist at all: without a fake tenant the walk climbs past the fixture into whatever real `claude` is
# running the suite, so the test's verdict would depend on how it was launched.
#
# The trailing `:` in each tier defeats bash's last-command exec optimisation. Without it the inner
# `claude` REPLACES the outer, both tiers collapse onto one pid, and the ancestor relation the test
# exists to exercise silently does not exist (measured: inner pid == outer pid).
nested_register() { # $1=pane $2=payload
  local fake="$BATS_TEST_TMPDIR/fake"
  mkdir -p "$fake" "$CC_REGISTRY_DIR"; ln -sf /bin/bash "$fake/claude"
  cat > "$BATS_TEST_TMPDIR/outer.sh" <<'OUT'
printf '{"paneUUID":"%s","name":"TENANT","cwd":"/tmp","account":"next","pid":%s,"startedAt":1,"session_id":"TENANT-SID"}' \
  "$NR_PANE" "$$" > "$CC_REGISTRY_DIR/$NR_PANE.json"
"$NR_FAKE/claude" "$NR_INNER"
:
OUT
  cat > "$BATS_TEST_TMPDIR/inner.sh" <<'IN'
printf '%s' "$NR_PAYLOAD" | ITERM_SESSION_ID="w1t0p0:$NR_PANE" bash "$NR_HOOK"
:
IN
  NR_PANE="$1" NR_PAYLOAD="$2" NR_FAKE="$fake" NR_HOOK="$REG" NR_INNER="$BATS_TEST_TMPDIR/inner.sh" \
    "$fake/claude" "$BATS_TEST_TMPDIR/outer.sh"
}

@test "register: a nested claude does NOT overwrite its live parent's row (headless-probe squat)" {
  nested_register "$PANE_T" "$CHILD"
  run jq -r '.session_id' "$CC_REGISTRY_DIR/$PANE_T.json"
  [ "$output" = "TENANT-SID" ]
}

@test "register: the tenancy refusal is journalled (a silent no-op reads as an inert gate)" {
  nested_register "$PANE_T" "$CHILD"
  # Existence first, as its own assertion, so "no record at all" cannot read as wrong content.
  # `run grep` + `[ ]`, never `[[ ]]`: bats bodies run under `set -eET` and bash EXEMPTS the `[[`
  # keyword from errexit, so a non-final `[[ ]]` evaluates, discards its false result, and the test
  # passes — scripts/bats-assert-liveness.py exists to catch exactly that, and caught it here.
  [ -s "$SESSION_REGISTER_IDL" ]
  run grep -Fc '"disposition":"refused"' "$SESSION_REGISTER_IDL"
  [ "$status" -eq 0 ]
  run grep -Fc '"sid":"CHILD-SID"' "$SESSION_REGISTER_IDL"
  [ "$status" -eq 0 ]
}

@test "register: a live incumbent that is NOT an ancestor is overwritten (pid reuse must not wedge)" {
  sleep 30 & local other=$!
  mkentry "$PANE_T" "stale" "$other" "OLD-SID"
  printf '%s' "$CHILD" | ITERM_SESSION_ID="w1t0p0:$PANE_T" bash "$REG"
  kill "$other" 2>/dev/null || true; wait "$other" 2>/dev/null || true
  run jq -r '.session_id' "$CC_REGISTRY_DIR/$PANE_T.json"
  [ "$output" = "CHILD-SID" ]
}

@test "register: a dead-pid row is overwritten (the pane's next tenant registers normally)" {
  mkentry "$PANE_T" "corpse" "$(deadpid)" "OLD-SID"
  printf '%s' "$CHILD" | ITERM_SESSION_ID="w1t0p0:$PANE_T" bash "$REG"
  run jq -r '.session_id' "$CC_REGISTRY_DIR/$PANE_T.json"
  [ "$output" = "CHILD-SID" ]
}

@test "register: a pid-less provisional row is upgraded (handoff-fire ensure_registration)" {
  mkdir -p "$CC_REGISTRY_DIR"
  printf '{"paneUUID":"%s","name":"prov","cwd":"/tmp","cmd":"x","provisional":true}' "$PANE_T" \
    > "$CC_REGISTRY_DIR/$PANE_T.json"
  printf '%s' "$CHILD" | ITERM_SESSION_ID="w1t0p0:$PANE_T" bash "$REG"
  run jq -r '.session_id' "$CC_REGISTRY_DIR/$PANE_T.json"
  [ "$output" = "CHILD-SID" ]
}

# ── HEADLESS ADDRESSES (backlog 4b9d5e93b40a) ────────────────────────────────────────────────────
# The address under test is the one bin/cc-pane-headless:124 mints (`hdl-` + 16 hex) and :197
# exports as CC_PANE_ID while unsetting ITERM_SESSION_ID. These cases construct that shape
# LITERALLY and never invoke cc-pane-headless: a red-proof fixture that calls into the subject
# cannot distinguish "pre-fix" from "fixture broken", and bats renders the resulting skip as `ok`
# (fleet memory: red-proof-fixture-must-not-call-the-subject). Nothing here calls a symbol the fix
# introduces, so every case below is a genuine verdict against origin/main.
HDL="hdl-a1b2c3d4e5f60718"

mkentry_headless() { # $1=id $2=name $3=pid
  mkdir -p "$CC_REGISTRY_DIR"
  printf '{"paneUUID":"%s","name":"%s","cwd":"/tmp","account":"next","pid":%s,"startedAt":1,"session_id":"HL-SID","surface":"headless"}' \
    "$1" "$2" "$3" > "$CC_REGISTRY_DIR/$1.json"
}

@test "register: a headless address (CC_PANE_ID set, ITERM_SESSION_ID unset) writes a row" {
  printf '{"cwd":"/tmp/hl","session_id":"HL-SID","reason":"startup"}' \
    | env -u ITERM_SESSION_ID CC_PANE_ID="$HDL" CC_SESSION_NAME="hl" bash "$REG"
  [ -f "$CC_REGISTRY_DIR/$HDL.json" ]
  run jq -r '.paneUUID' "$CC_REGISTRY_DIR/$HDL.json";   [ "$output" = "$HDL" ]
  run jq -r '.session_id' "$CC_REGISTRY_DIR/$HDL.json"; [ "$output" = "HL-SID" ]
}

@test "register: surface records WHICH variable supplied the address (headless vs pane)" {
  printf '{"cwd":"/tmp/hl","session_id":"HL-SID"}' \
    | env -u ITERM_SESSION_ID CC_PANE_ID="$HDL" bash "$REG"
  run jq -r '.surface' "$CC_REGISTRY_DIR/$HDL.json"; [ "$output" = "headless" ]
  printf '%s' "$CHILD" | ITERM_SESSION_ID="w1t0p0:$PANE_T" bash "$REG"
  run jq -r '.surface' "$CC_REGISTRY_DIR/$PANE_T.json"; [ "$output" = "pane" ]
}

@test "register: a path-unsafe or empty address is STILL refused (the widening opened no traversal)" {
  # The OVER-widening control. The old gate's real duty was path safety — this value becomes
  # "$reg_dir/$pane.json" — and "hex-shaped" was only ever a proxy for it. Each of these must leave
  # the registry empty. Failures are accumulated and asserted at the end rather than asserted inside
  # the loop, because a non-final bare assertion in a bats body is not trapped
  # (fleet memory: negated-assertion-dead-unless-final).
  bad_kept=""
  for bad in "../evil" "/etc/passwd" ".hidden" "." ".." "not a uuid" "a/b" ""; do
    rm -rf "${CC_REGISTRY_DIR:?}" 2>/dev/null || true
    printf '{"cwd":"/tmp/x","session_id":"X"}' \
      | env -u ITERM_SESSION_ID CC_PANE_ID="$bad" bash "$REG" || true
    n="$(find "$CC_REGISTRY_DIR" -name '*.json' 2>/dev/null | wc -l | tr -d ' ')"
    [ "${n:-0}" = 0 ] || bad_kept="$bad_kept [$bad->$n]"
  done
  [ -z "$bad_kept" ] || { printf 'accepted path-unsafe address(es):%s\n' "$bad_kept" >&2; false; }
}

@test "register: a nested session inheriting CC_PANE_ID must not squat the headless tenant" {
  # Credits the deliberate decision NOT to take spec E3's "skip the ancestor walk on the non-pane
  # branch". cc-pane-headless EXPORTS CC_PANE_ID, so a nested `claude` inherits the tenant's address
  # exactly as a pane child does; the write-side tenancy gate must therefore still fire here.
  fake="$BATS_TEST_TMPDIR/fakeh"; mkdir -p "$fake" "$CC_REGISTRY_DIR"; ln -sf /bin/bash "$fake/claude"
  cat > "$BATS_TEST_TMPDIR/outer-h.sh" <<'OUT'
printf '{"paneUUID":"%s","name":"TENANT","cwd":"/tmp","account":"next","pid":%s,"startedAt":1,"session_id":"TENANT-SID","surface":"headless"}' \
  "$NR_PANE" "$$" > "$CC_REGISTRY_DIR/$NR_PANE.json"
"$NR_FAKE/claude" "$NR_INNER"
:
OUT
  cat > "$BATS_TEST_TMPDIR/inner-h.sh" <<'IN'
printf '%s' "$NR_PAYLOAD" | env -u ITERM_SESSION_ID CC_PANE_ID="$NR_PANE" bash "$NR_HOOK"
:
IN
  NR_PANE="$HDL" NR_PAYLOAD='{"cwd":"/tmp/child","session_id":"CHILD-SID","reason":"startup"}' \
    NR_FAKE="$fake" NR_HOOK="$REG" NR_INNER="$BATS_TEST_TMPDIR/inner-h.sh" \
    "$fake/claude" "$BATS_TEST_TMPDIR/outer-h.sh"
  run jq -r '.session_id' "$CC_REGISTRY_DIR/$HDL.json"
  [ "$output" = "TENANT-SID" ]
}

@test "cc-sessions: a headless row is NOT hidden by absence from the terminal pane list" {
  # A pane list can only ever MISS a headless address, so cross-checking against it would convert
  # the registration fix into a hidden row — the same false death one layer down
  # (fleet memory: lookup-miss-is-not-absence). The scoping control is the existing pane-row case
  # "a gone-pane entry (pid alive) is hidden from addressing but RETAINED", which must stay green.
  export IT2_STUB_PANES="SOME-OTHER-PANE"
  mkentry_headless "$HDL" "hl-agent" "$$"
  run bash "$CCS" --names
  [ "$status" -eq 0 ]
  [ "$output" = "hl-agent" ]
}

@test "cc-sessions: a headless row with a DEAD pid is still hidden (liveness is not waived)" {
  export IT2_STUB_PANES="SOME-OTHER-PANE"
  mkentry_headless "$HDL" "hl-corpse" "$(deadpid)"
  run bash "$CCS" --names
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
  [ -f "$CC_REGISTRY_DIR/$HDL.json" ]      # RETAINED for forensics, as any dead row is
}

@test "deregister: removes a headless row (writer and remover share one keyspace)" {
  # A remover narrower than its writer does not fail, it ORPHANS — the row would survive to
  # CC_REG_RETAIN_H with nothing able to remove it. This is why both moved in one diff.
  mkentry_headless "$HDL" "hl-agent" "$$"
  printf '{"session_id":"HL-SID","reason":"other"}' \
    | env -u ITERM_SESSION_ID CC_PANE_ID="$HDL" bash "$DEREG"
  [ ! -f "$CC_REGISTRY_DIR/$HDL.json" ]
}

# ── PID-REUSE GUARD: identity is (pid,lstart), never pid alone ────────────────────────────────────
# `kill -0` answers "is SOME process holding this pid", never "is THAT process still this session",
# and a row is RETAINED for CC_REG_RETAIN_H (24h) after its session dies — so the recycled-pid
# window IS the retention window. Sharper for a headless row: the live-pane cross-check that would
# be a second opinion on a pane row is deliberately skipped for `surface:headless`, leaving `kill -0`
# alone. Note every mkentry above writes NO lstart, so the whole suite ABOVE this block is the
# backward-compatibility control: those rows must keep behaving exactly as they did.

# a live process we control, plus its TZ-pinned start time
mklive() { sleep 300 & LIVE_PID=$!; LIVE_LSTART="$(TZ=UTC ps -o lstart= -p "$LIVE_PID" | tr -s ' ' | sed 's/^ *//;s/ *$//')"; }
# `|| true`, not a trailing `; return 0`: the kill is the LAST command of the AND-list, so errexit
# is NOT exempt there, and a child already reaped under load returns 1 and aborts the test body
# before `return 0` can run — a green test going red only under load (scripts/bats-kill-guard-lint.sh).
killlive() { [ -n "${LIVE_PID:-}" ] && { kill "$LIVE_PID" 2>/dev/null || true; }; return 0; }
# $1=uuid $2=name $3=pid $4=lstart (omit $4 ⇒ the legacy shape, no field at all)
mkentry_ls() {
  mkdir -p "$CC_REGISTRY_DIR"
  if [ -n "${4:-}" ]; then
    jq -n --arg u "$1" --arg n "$2" --arg l "$4" --argjson p "$3" \
      '{paneUUID:$u,name:$n,cwd:"/tmp",account:"next",pid:$p,startedAt:1,surface:"headless",lstart:$l}' \
      > "$CC_REGISTRY_DIR/$1.json"
  else
    jq -n --arg u "$1" --arg n "$2" --argjson p "$3" \
      '{paneUUID:$u,name:$n,cwd:"/tmp",account:"next",pid:$p,startedAt:1,surface:"headless"}' \
      > "$CC_REGISTRY_DIR/$1.json"
  fi
}

@test "register: the row records the ancestor pid's start time, TZ-pinned" {
  printf '{"cwd":"/tmp/demo"}' \
    | ITERM_SESSION_ID="w1t0p0:AAAAAAAA-1111-2222-3333-444444444444" CC_SESSION_NAME="demo" bash "$REG"
  f="$CC_REGISTRY_DIR/AAAAAAAA-1111-2222-3333-444444444444.json"
  [ -f "$f" ] || { echo "no row written — the write side never ran"; false; }
  rec="$(jq -r '.lstart // ""' "$f")"
  [ -n "$rec" ] || { echo "row carries no lstart: $(cat "$f")"; false; }
  # ANTI-VACUITY: the value must be the recorded pid's ACTUAL start time, not merely non-empty.
  rpid="$(jq -r '.pid' "$f")"
  want="$(TZ=UTC ps -o lstart= -p "$rpid" | tr -s ' ' | sed 's/^ *//;s/ *$//')"
  [ -n "$want" ] || { echo "could not read the recorded pid $rpid — instrument, not subject"; false; }
  [ "$rec" = "$want" ] || { echo "recorded [$rec] != live [$want]"; false; }
}

@test "register: the recorded start time is ambient-TZ invariant (the DST false-death class)" {
  # `ps -o lstart=` renders through the AMBIENT timezone: the same live pid prints three different
  # strings under three TZs. Unpinned, a DST flip — or a reader running under a different TZ than the
  # writer, which is every launchd daemon — changes the string for a process that NEVER RESTARTED,
  # and every reader convicts every row at once. That is a fleet-wide false DEATH, strictly worse
  # than the false life this field exists to stop; tests/watchdog-census.bats:197-221 is this repo
  # already paying for it once in lead-crash-watchdog.
  printf '{"cwd":"/tmp/a"}' | TZ=Asia/Tokyo ITERM_SESSION_ID="w1t0p0:11111111-1111-1111-1111-111111111111" bash "$REG"
  printf '{"cwd":"/tmp/b"}' | TZ=UTC        ITERM_SESSION_ID="w1t0p0:22222222-2222-2222-2222-222222222222" bash "$REG"
  a="$CC_REGISTRY_DIR/11111111-1111-1111-1111-111111111111.json"
  b="$CC_REGISTRY_DIR/22222222-2222-2222-2222-222222222222.json"
  # TWO assertions, not `[ -f "$a" ] && [ -f "$b" ] || {…}`. That form is the analyzer's
  # `and-absorbed` class (scripts/bats-assert-liveness.py), and it also cannot say WHICH row is
  # missing — the diagnostic collapses exactly when you need it.
  [ -f "$a" ] || { echo "the Tokyo-ambient run wrote no row"; false; }
  [ -f "$b" ] || { echo "the UTC-ambient run wrote no row"; false; }
  # Only comparable while both runs resolved the SAME ancestor pid; assert that first so a pid
  # difference reports itself instead of masquerading as a TZ failure.
  pa="$(jq -r '.pid' "$a")"; pb="$(jq -r '.pid' "$b")"
  [ "$pa" = "$pb" ] || skip "the two runs resolved different ancestor pids ($pa/$pb) — nothing to compare"
  # `// ""` is load-bearing, not tidiness: a BARE `jq -r '.lstart'` on a row without the field
  # prints the STRING "null", which is non-empty and equal to the other row's "null" — so this case
  # passed against pristine origin/main, asserting nothing. Caught by running it there.
  la="$(jq -r '.lstart // ""' "$a")"; lb="$(jq -r '.lstart // ""' "$b")"
  [ -n "$la" ] || { echo "Tokyo run recorded no lstart"; false; }
  [ "$la" = "$lb" ] || { echo "ambient TZ changed the pin: Tokyo [$la] vs UTC [$lb]"; false; }
}

@test "cc-sessions: a row whose start time no longer matches its live pid is NOT live" {
  mklive
  mkentry_ls "AAAAAAAA-1111-2222-3333-444444444444" "recycled" "$LIVE_PID" "Wed 01 Jan 00:00:00 2020"
  run bash "$CCS" --names
  killlive
  [ "$status" -eq 0 ]
  # The pid IS alive — `kill -0` says live — so only the start-time check can exclude this row.
  [ "$output" = "" ] || { echo "a recycled-pid row was offered as addressable: $output"; false; }
}

@test "cc-sessions: a matching start time still reads live (the guard does not over-convict)" {
  mklive
  mkentry_ls "AAAAAAAA-1111-2222-3333-444444444444" "genuine" "$LIVE_PID" "$LIVE_LSTART"
  run bash "$CCS" --names
  killlive
  [ "$status" -eq 0 ]
  [ "$output" = "genuine" ] || { echo "a genuinely live row was convicted: [$output]"; false; }
}

@test "cc-sessions: a row with no recorded start time is judged exactly as before (fail-open)" {
  mklive
  mkentry_ls "AAAAAAAA-1111-2222-3333-444444444444" "legacy" "$LIVE_PID"
  run bash "$CCS" --names
  killlive
  [ "$status" -eq 0 ]
  [ "$output" = "legacy" ] || { echo "a pre-field row was convicted on a value nobody wrote: [$output]"; false; }
}

@test "cc-sessions: the liveness verdict is identical under a different ambient TZ" {
  mklive
  mkentry_ls "AAAAAAAA-1111-2222-3333-444444444444" "genuine" "$LIVE_PID" "$LIVE_LSTART"
  run env TZ=Asia/Tokyo bash "$CCS" --names
  tokyo="$output"
  run env TZ=UTC bash "$CCS" --names
  utc="$output"
  killlive
  [ "$tokyo" = "genuine" ] || { echo "under TZ=Asia/Tokyo a live session read dead: [$tokyo]"; false; }
  [ "$tokyo" = "$utc" ] || { echo "ambient TZ changed the verdict: Tokyo [$tokyo] vs UTC [$utc]"; false; }
}
