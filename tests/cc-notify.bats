#!/usr/bin/env bats
# cc-notify (v2) — the NON-KEYSTROKE transport. Proves cc-notify ENQUEUES to the target's inbox
# (~/.claude/mailbox/<uuid>.md) and NEVER calls it2 `session send` (the v1 keystroke path that raced the
# user's live input — the exact bug v2 removes). Liveness decides the honest exit verdict cc-announce
# trusts: a LIVE session → "delivered to inbox"; a NOT-live target → "mailbox only"; unresolvable → 3;
# unwritable inbox → 5. Isolated via CC_REGISTRY_DIR / CC_MAILBOX_DIR and an IT2_BIN stub.
#
# Harness rules (learned from real escapes, v1 suite):
#   1. `|| false` on EVERY bare [[ ]] — bats does not trap a bare [[ ]] failure mid-body.
#   2. Assert the SPECIFIC verdict string, never a loose glob a degraded result also matches.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  NOTIFY="$REPO/bin/cc-notify"
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg"
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mbox"
  export IT2_LOG="$BATS_TEST_TMPDIR/it2.log"
  mkdir -p "$CC_REGISTRY_DIR" "$CC_MAILBOX_DIR"

  UUID="AAAAAAAA-1111-2222-3333-444444444444"
  # a LIVE registered peer: pid=$$ (this test proc, kill -0 succeeds) + the it2 stub lists its pane.
  printf '{"paneUUID":"%s","name":"peer","cwd":"/tmp","account":"next","pid":%s,"startedAt":1}' \
    "$UUID" "$$" > "$CC_REGISTRY_DIR/$UUID.json"

  # it2 stub: `session list --json` → the live pane set (peer UUID); `session send` → LOG it, so a test
  # can assert it is NEVER called. cc-notify v2 must only ever use `session list` (read-only), never send.
  STUB="$BATS_TEST_TMPDIR/it2"
  cat > "$STUB" <<SH
#!/bin/bash
if [ "\$1" = "session" ] && [ "\$2" = "list" ]; then
  printf '[{"id":"%s"}]\n' "$UUID"; exit 0
fi
if [ "\$1" = "session" ] && [ "\$2" = "send" ]; then
  printf 'SEND %s\n' "\$*" >> "$IT2_LOG"; exit 0
fi
exit 0
SH
  chmod +x "$STUB"
  export IT2_BIN="$STUB"
}

sent_count() { if [ -f "$IT2_LOG" ]; then grep -c '^SEND' "$IT2_LOG"; else echo 0; fi; }

@test "resolves a friendly NAME to a LIVE session → 'delivered to inbox', enqueues, NO keystroke" {
  run "$NOTIFY" peer "hello world"
  [ "$status" -eq 0 ]
  [[ "$output" == *"delivered to inbox"* ]] || false
  grep -q '\] hello world' "$CC_MAILBOX_DIR/$UUID.md"   # line is "<iso> [<sender>] hello world"
  [ "$(sent_count)" -eq 0 ]     # THE anti-keystroke invariant: session send was NEVER called
}

@test "raw pane UUID of a live pane passes through and enqueues" {
  run "$NOTIFY" "$UUID" "ping"
  [ "$status" -eq 0 ]
  [[ "$output" == *"delivered to inbox"* ]] || false
  grep -q '\] ping' "$CC_MAILBOX_DIR/$UUID.md"
  [ "$(sent_count)" -eq 0 ]
}

@test "NOT-live target (it2 lists no such pane, no registry row) → 'mailbox only', exit 0, still enqueued" {
  DEAD="DDDDDDDD-9999-8888-7777-666666666666"
  run "$NOTIFY" "$DEAD" "to a closed pane"
  [ "$status" -eq 0 ]
  [[ "$output" == *"mailbox only"* ]] || false
  [[ "$output" == *"NOT a live session"* ]] || false
  grep -q '\] to a closed pane' "$CC_MAILBOX_DIR/$DEAD.md"   # recorded even though not-live
  [ "$(sent_count)" -eq 0 ]
}

@test "liveness UNVERIFIABLE (it2 errors) → recorded degrade, exit 0, enqueued" {
  # break it2 so `session list` errors → liveness oracle unavailable → unknown, never a false not-live.
  printf '#!/bin/bash\nexit 1\n' > "$IT2_BIN"
  GHOST="EEEEEEEE-9999-8888-7777-666666666666"
  run "$NOTIFY" "$GHOST" "maybe live"
  [ "$status" -eq 0 ]
  [[ "$output" == *"UNVERIFIABLE"* ]] || false
  grep -q '\] maybe live' "$CC_MAILBOX_DIR/$GHOST.md"
}

@test "wake-path: a fresh .watching heartbeat → 'wake-path armed'; its absence → 'NO watcher armed' (F5)" {
  # no watcher armed → delivered but not a guaranteed wake
  run "$NOTIFY" "$UUID" "no watcher"
  [[ "$output" == *"NO watcher armed"* ]] || false
  # arm a fresh watcher heartbeat → wake-path armed (VERIFIED-worthy for cc-announce)
  : > "$CC_MAILBOX_DIR/$UUID.watching"
  run "$NOTIFY" "$UUID" "with watcher"
  [[ "$output" == *"wake-path armed"* ]] || false
}

@test "F4: inbox-unwritable self-escalates — a durable alarm record is written even though exit is swallowed" {
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/ro/deeper"
  export CC_COMMS_ALARM_DIR="$BATS_TEST_TMPDIR/comms-alarms"
  mkdir -p "$BATS_TEST_TMPDIR/ro"; chmod 500 "$BATS_TEST_TMPDIR/ro"
  run "$NOTIFY" "$UUID" "cannot persist"
  chmod 700 "$BATS_TEST_TMPDIR/ro"
  [ "$status" -eq 5 ]
  # the loud path does NOT depend on the mailbox it reports as broken — an alarm lands in a DIFFERENT dir
  [ -n "$(find "$CC_COMMS_ALARM_DIR" -name 'enqueue-fail-*.json' 2>/dev/null)" ]
}

@test "ALWAYS enqueues on success (the inbox is the durable transport, not a fallback)" {
  run "$NOTIFY" peer "durable record"
  [ "$status" -eq 0 ]
  [ -f "$CC_MAILBOX_DIR/$UUID.md" ]
  grep -q 'durable record' "$CC_MAILBOX_DIR/$UUID.md"
}

@test "unresolvable target → exit 3, no mailbox (unknown name, not a UUID)" {
  run "$NOTIFY" "not-a-name-or-uuid" "x"
  [ "$status" -eq 3 ]
  [ ! -f "$CC_MAILBOX_DIR/not-a-name-or-uuid.md" ]
}

@test "missing message (non-self target) → usage error exit 2" {
  run "$NOTIFY" peer
  [ "$status" -eq 2 ]
}

@test "inbox UNWRITABLE → exit 5 LOUD (a message that cannot persist is not delivered)" {
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/ro/deeper"
  mkdir -p "$BATS_TEST_TMPDIR/ro"; chmod 500 "$BATS_TEST_TMPDIR/ro"
  run "$NOTIFY" "$UUID" "cannot persist"
  chmod 700 "$BATS_TEST_TMPDIR/ro"     # restore for teardown
  [ "$status" -eq 5 ]
  [[ "$output" == *"FAILED to write inbox"* ]] || false
}

@test "--self prints own pane UUID and exits (no message)" {
  export ITERM_SESSION_ID="w0t0p0:$UUID"
  run "$NOTIFY" --self
  [ "$status" -eq 0 ]
  [ "$output" = "$UUID" ]
}

@test "--self <msg> enqueues into own inbox (self is always live)" {
  export ITERM_SESSION_ID="w0t0p0:$UUID"
  run "$NOTIFY" --self "note to self"
  [ "$status" -eq 0 ]
  grep -q 'note to self' "$CC_MAILBOX_DIR/$UUID.md"
  [ "$(sent_count)" -eq 0 ]
}

@test "--from attribution appears in the inbox line" {
  run "$NOTIFY" --from reaper "$UUID" "surface page"
  [ "$status" -eq 0 ]
  grep -q '\[reaper\] surface page' "$CC_MAILBOX_DIR/$UUID.md"
}

@test "--mailbox-only records but reports inbox-only, exit 0" {
  run "$NOTIFY" --mailbox-only "$UUID" "record only"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--mailbox-only"* ]] || false
  grep -q 'record only' "$CC_MAILBOX_DIR/$UUID.md"
  [ "$(sent_count)" -eq 0 ]
}

@test "a message with embedded newlines is collapsed to ONE inbox line (cursor invariant)" {
  run "$NOTIFY" "$UUID" "$(printf 'line-a\nline-b\nline-c')"
  [ "$status" -eq 0 ]
  # exactly ONE line was appended (one message = one line, so the .seen cursor counts messages)
  [ "$(grep -c '' "$CC_MAILBOX_DIR/$UUID.md")" -eq 1 ]
  grep -q 'line-a line-b line-c' "$CC_MAILBOX_DIR/$UUID.md"
}

@test "delivery-survives-busy-pane: a busy / bash-prompt pane still gets the message (mailbox → context, never keystrokes)" {
  # 'busy' is IRRELEVANT to delivery — there is no keystroke to race. cc-notify enqueues regardless of what
  # the pane is doing (mid-command, at a bash prompt, user actively typing) and touches NO composer.
  run "$NOTIFY" "$UUID" "reaper page while you were mid-command"
  [ "$status" -eq 0 ]
  grep -q 'reaper page while you were mid-command' "$CC_MAILBOX_DIR/$UUID.md"
  [ "$(sent_count)" -eq 0 ]     # zero keystrokes → nothing to corrupt / mis-run on the busy pane
  # and the drain surfaces it as CONTEXT at the next SAFE boundary — never as a command on the bash line.
  local drain="$REPO/hooks/mailbox-drain.sh" out
  out="$(ITERM_SESSION_ID="w0t0p0:$UUID" bash -c 'echo "{}" | "$0" prompt' "$drain")"
  printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext' | grep -q 'reaper page while you were mid-command'
}

@test "cc-notify NEVER invokes the keystroke transport across ALL send paths" {
  "$NOTIFY" peer "one" >/dev/null 2>&1
  "$NOTIFY" "$UUID" "two" >/dev/null 2>&1
  "$NOTIFY" --from x "$UUID" "three" >/dev/null 2>&1
  export ITERM_SESSION_ID="w0t0p0:$UUID"; "$NOTIFY" --self "four" >/dev/null 2>&1
  [ "$(sent_count)" -eq 0 ]     # zero it2 `session send` across name/uuid/from/self — no keystrokes, ever
}

# ── v3 ADDRESSING: --role · forward chains · dead-target reroute (D1/D2/D3) ───────────────────────
# These pin the class that lost ~78% of all mail ever sent: an address frozen at producer start-up,
# a pane that recycled out from under it, and a "success" exit that looped for three days.

@test "--role resolves the role file at SEND time (not a snapshot) and enqueues to that pane" {
  export CC_ROLES_DIR="$BATS_TEST_TMPDIR/roles"; mkdir -p "$CC_ROLES_DIR"
  printf '%s\n' "$UUID" > "$CC_ROLES_DIR/desk"
  run "$NOTIFY" --role desk "role addressed"
  [ "$status" -eq 0 ]
  [[ "$output" == *"delivered to inbox"* ]] || false
  grep -q '\] role addressed' "$CC_MAILBOX_DIR/$UUID.md"
  [ "$(sent_count)" -eq 0 ]
}

@test "--role REPOINTED between sends follows the role, not the original pane (the anti-flood property)" {
  export CC_ROLES_DIR="$BATS_TEST_TMPDIR/roles"; mkdir -p "$CC_ROLES_DIR"
  local NEW="CCCCCCCC-9999-8888-7777-666666666666"
  printf '%s\n' "$UUID" > "$CC_ROLES_DIR/desk"
  "$NOTIFY" --role desk "before recycle" >/dev/null 2>&1
  printf '%s\n' "$NEW" > "$CC_ROLES_DIR/desk"          # the desk recycled; role repointed
  "$NOTIFY" --role desk "after recycle" >/dev/null 2>&1
  grep -q 'before recycle' "$CC_MAILBOX_DIR/$UUID.md"
  grep -q 'after recycle'  "$CC_MAILBOX_DIR/$NEW.md"
  ! grep -q 'after recycle' "$CC_MAILBOX_DIR/$UUID.md" || false   # the OLD box does not keep receiving
}

@test "--role with a MISSING role file → exit 3 with a hint, and nothing is enqueued" {
  export CC_ROLES_DIR="$BATS_TEST_TMPDIR/roles"; mkdir -p "$CC_ROLES_DIR"
  run "$NOTIFY" --role nosuch "x"
  [ "$status" -eq 3 ]
  [[ "$output" == *"role 'nosuch' is not set"* ]] || false
  [ -z "$(ls -A "$CC_MAILBOX_DIR")" ]
}

@test "--role with an EMPTY role file → exit 3 (an unset role is not a silent no-op)" {
  export CC_ROLES_DIR="$BATS_TEST_TMPDIR/roles"; mkdir -p "$CC_ROLES_DIR"
  : > "$CC_ROLES_DIR/desk"
  run "$NOTIFY" --role desk "x"
  [ "$status" -eq 3 ]
}

@test "a send to a pane with a .forward lands in the SUCCESSOR's box, not the dead one" {
  local DEAD="DEADBEEF-1111-2222-3333-444444444444"
  printf '%s\n' "$UUID" > "$CC_MAILBOX_DIR/$DEAD.forward"    # DEAD self-closed → UUID (live) continues
  run "$NOTIFY" "$DEAD" "follow the chain"
  [ "$status" -eq 0 ]
  [[ "$output" == *"following its forward chain"* ]] || false
  grep -q 'follow the chain' "$CC_MAILBOX_DIR/$UUID.md"
  [ ! -f "$CC_MAILBOX_DIR/$DEAD.md" ]                        # nothing written to the dead box
}

@test "dead target with NO forward → REROUTED to the desk role, tagged [for:<orig>]" {
  export CC_ROLES_DIR="$BATS_TEST_TMPDIR/roles"; mkdir -p "$CC_ROLES_DIR"
  printf '%s\n' "$UUID" > "$CC_ROLES_DIR/desk"               # UUID is the live desk
  local DEAD="DEADBEEF-1111-2222-3333-444444444444"          # not in the it2 stub's live list
  run "$NOTIFY" "$DEAD" "orphaned page"
  [ "$status" -eq 0 ]
  [[ "$output" == *"rerouted to desk"* ]] || false
  grep -q "\[for:$DEAD\] orphaned page" "$CC_MAILBOX_DIR/$UUID.md"   # the desk sees it, attributed
  grep -q 'orphaned page' "$CC_MAILBOX_DIR/$DEAD.md"                 # forensics stay in the dead box
}

@test "a reroute stays HONEST — stderr never upgrades it to a delivery to the original target" {
  export CC_ROLES_DIR="$BATS_TEST_TMPDIR/roles"; mkdir -p "$CC_ROLES_DIR"
  printf '%s\n' "$UUID" > "$CC_ROLES_DIR/desk"
  local DEAD="DEADBEEF-1111-2222-3333-444444444444"
  run "$NOTIFY" "$DEAD" "still undelivered"
  [[ "$output" == *"mailbox only"* ]] || false                       # the W5 verdict survives
  [[ "$output" == *"NOT a delivery to the original target"* ]] || false
  [[ "$output" != *"delivered to inbox [$DEAD]"* ]] || false         # never a false success
}

@test "dead target with NO desk role → says so plainly instead of claiming a reroute" {
  export CC_ROLES_DIR="$BATS_TEST_TMPDIR/roles"; mkdir -p "$CC_ROLES_DIR"
  local DEAD="DEADBEEF-1111-2222-3333-444444444444"
  run "$NOTIFY" "$DEAD" "nobody home"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no reroute"* ]] || false
  [[ "$output" != *"rerouted to desk"* ]] || false
}

@test "an UNKNOWN-liveness target is NOT rerouted (only an authoritative dead target is)" {
  export CC_ROLES_DIR="$BATS_TEST_TMPDIR/roles"; mkdir -p "$CC_ROLES_DIR"
  printf '%s\n' "$UUID" > "$CC_ROLES_DIR/desk"
  local UNK="DEADBEEF-1111-2222-3333-444444444444"
  printf '#!/bin/bash\nexit 1\n' > "$BATS_TEST_TMPDIR/it2-broken"    # no liveness oracle
  chmod +x "$BATS_TEST_TMPDIR/it2-broken"
  IT2_BIN="$BATS_TEST_TMPDIR/it2-broken" run "$NOTIFY" "$UNK" "unknown liveness"
  [ "$status" -eq 0 ]
  [[ "$output" == *"UNVERIFIABLE"* ]] || false
  [[ "$output" != *"rerouted"* ]] || false                           # would spam the desk on every it2 blip
  [ ! -f "$CC_MAILBOX_DIR/$UUID.md" ] || ! grep -q 'unknown liveness' "$CC_MAILBOX_DIR/$UUID.md"
}

# ── v4 RESOLVER AVAILABILITY: no blocking subprocess · honest rc · a round-tripping listing ───────
# These pin the class that cost 6 non-delivered advisories across 3 attempts and 2 wrong diagnoses:
# `it2 session list --json` (iTerm2 IPC) exceeded 120s under pane load, and BOTH cc-notify hot paths
# went through it — so a valid target came back as rc=3 "not a live session name or a pane UUID".
# The wrong diagnoses ("it times out", then "the short UUID is not accepted") were both symptoms; the
# fault was that the resolver could block at all, and that its failure was indistinguishable from a
# bad address. A stub that HANGS is therefore the load-bearing fixture here — a fast stub cannot tell
# a registry-direct resolver apart from the it2-shelling one it replaced.

# it2 stub that hangs far longer than any bound — stands in for iTerm2 under pane load 13-16.
# It also SPIES: every invocation is appended to $IT2_SPY before the stub does anything else, so a test
# can assert the strong claim ("this path never touches it2") DIRECTLY rather than inferring it from
# elapsed time. Timing alone is not sufficient here, and a green suite proved it: with the it2 call
# bounded at CC_IT2_TIMEOUT_S=5 and the hang tests asserting <10s, disabling the registry-direct
# target_live() — the SECOND of the two hang sites, and the one whose fix this suite exists to pin —
# still passed 40/40, because the fallback merely degraded to a 5s bounded call. The bound was pinned;
# the fix was not.
hanging_it2() {
  cat > "$BATS_TEST_TMPDIR/it2-hang" <<'SH'
#!/bin/bash
# Record FIRST — the assertion is "never invoked", so the spy must fire even on paths that then hang.
# `:?` rather than a default: a spy that silently failed to record would make every it2_untouched
# assertion pass vacuously, which is the exact failure mode this fixture exists to end.
printf '%s\n' "$*" >> "${IT2_SPY:?it2 stub invoked with no spy ledger wired}"
if [ "$1" = "session" ] && [ "$2" = "list" ]; then sleep 300; exit 0; fi
exit 0
SH
  chmod +x "$BATS_TEST_TMPDIR/it2-hang"
  export IT2_BIN="$BATS_TEST_TMPDIR/it2-hang"
  export IT2_SPY="$BATS_TEST_TMPDIR/it2-calls"
  : > "$IT2_SPY"
}

# Same spy, but it does NOT hang: records, then returns a valid (empty) pane list immediately. For the
# positive control, where the claim is only "the spy records" — never "it records within a bound".
spying_it2() {
  cat > "$BATS_TEST_TMPDIR/it2-spy" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >> "${IT2_SPY:?it2 stub invoked with no spy ledger wired}"
if [ "$1" = "session" ] && [ "$2" = "list" ]; then printf '[]\n'; exit 0; fi
exit 0
SH
  chmod +x "$BATS_TEST_TMPDIR/it2-spy"
  export IT2_BIN="$BATS_TEST_TMPDIR/it2-spy"
  export IT2_SPY="$BATS_TEST_TMPDIR/it2-calls"
  : > "$IT2_SPY"
}

# Effect-read of "off the blocking path entirely". Asserts the ledger EXISTS before asserting it is
# empty — an absent ledger would mean the fixture was never wired, not that it2 went untouched.
it2_untouched() {
  [ -f "$IT2_SPY" ] || { echo "spy ledger $IT2_SPY missing — hanging_it2 was not called"; return 1; }
  [ ! -s "$IT2_SPY" ] || { echo "it2 WAS invoked: $(cat "$IT2_SPY")"; return 1; }
}
secs() { local s e; s=$(date +%s); "$@" >/dev/null 2>&1; e=$(date +%s); echo $(( e - s )); }

@test "v4: a NAME send to a registered pane never touches it2 — completes fast even while it2 HANGS" {
  hanging_it2
  local t; t="$(secs "$NOTIFY" peer "under load")"
  [ "$t" -lt 10 ] || { echo "took ${t}s — the resolver is still going through the blocking it2 call"; false; }
  it2_untouched || false          # the actual claim: not merely "fast", but never on the IPC at all
  run "$NOTIFY" peer "under load 2"
  [ "$status" -eq 0 ]
  [[ "$output" == *"delivered to inbox"* ]] || false
  grep -q '\] under load' "$CC_MAILBOX_DIR/$UUID.md"
}

@test "v4: a full-UUID send to a registered pane is fast too (the liveness path was the SECOND hang)" {
  # The documented workaround — 'pass the full 36-char UUID' — only ever LOOKED reliable: resolution
  # short-circuits, but target_live() then shelled into the same it2 call. The enqueue had already
  # happened, so mail landed while the process hung. Both call sites must be off the blocking path.
  hanging_it2
  local t; t="$(secs "$NOTIFY" "$UUID" "full uuid under load")"
  [ "$t" -lt 10 ] || { echo "took ${t}s — target_live() is still on the blocking it2 call"; false; }
  # Load-bearing: a registered row must be decided from the REGISTRY, not via a bounded-but-still-taken
  # it2 call. Elapsed time cannot see that difference (a 5s bound also lands under 10s), so reverting
  # registry-direct target_live() is caught ONLY here.
  it2_untouched || false
  grep -q 'full uuid under load' "$CC_MAILBOX_DIR/$UUID.md"
}

@test "v4: an UNREGISTERED target still consults it2, but BOUNDED — degrades to UNVERIFIABLE, never hangs" {
  hanging_it2
  export CC_IT2_TIMEOUT_S=1
  local GHOST="FFFFFFFF-9999-8888-7777-666666666666"
  local t; t="$(secs "$NOTIFY" "$GHOST" "bounded")"
  [ "$t" -lt 20 ] || { echo "took ${t}s — the it2 call is unbounded"; false; }
  run "$NOTIFY" "$GHOST" "bounded 2"
  [ "$status" -eq 0 ]
  [[ "$output" == *"UNVERIFIABLE"* ]] || false      # a timeout is 'unknown', never a false not-live
  grep -q 'bounded' "$CC_MAILBOX_DIR/$GHOST.md"
}

@test "v4: POSITIVE CONTROL — the it2 spy really records, so it2_untouched cannot pass vacuously" {
  # Without this, the two "never touches it2" assertions above could be green because the stub never
  # writes at all rather than because the resolver stayed off the IPC. An UNREGISTERED target has no
  # registry row to decide liveness from, so it2 MUST be consulted here. Deliberately NOT the hanging
  # stub: a 1s bound racing the stub's own process startup made this assertion flaky under suite load,
  # and a flaky control is worse than none. The claim is "the spy records", not "it records fast".
  spying_it2
  local GHOST="FFFFFFFF-1234-5678-9999-000000000000"
  run "$NOTIFY" "$GHOST" "positive control"
  [ "$status" -eq 0 ]
  [ -s "$IT2_SPY" ] || { echo "spy recorded nothing even where it2 IS expected — the spy is blind"; false; }
  grep -q 'session list' "$IT2_SPY" || { echo "spy ledger holds: $(cat "$IT2_SPY")"; false; }
}

@test "v4: RESOLVER UNAVAILABLE (registry unreadable) → exit 4, NOT exit 3 — the target is unverified, not invalid" {
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/no-such-registry"
  run "$NOTIFY" peer "x"
  [ "$status" -eq 4 ]
  [[ "$output" == *"RESOLVER UNAVAILABLE"* ]] || false
  [[ "$output" == *"UNVERIFIED, not invalid"* ]] || false
  # the OLD lie must be gone: never blame the address when the resolver is what failed
  [[ "$output" != *"not a live session name or a pane UUID"* ]] || false
}

@test "v4: an existing-but-UNREADABLE registry is exit 4, not a phantom 'empty registry' exit 3" {
  local ro="$BATS_TEST_TMPDIR/ro-reg"; mkdir -p "$ro"; chmod 000 "$ro"
  CC_REGISTRY_DIR="$ro" run "$NOTIFY" peer "x"
  chmod 700 "$ro"
  [ "$status" -eq 4 ]
  [[ "$output" == *"RESOLVER UNAVAILABLE"* ]] || false
}

@test "v4: a genuinely UNKNOWN name is still exit 3, and says the registry WAS readable" {
  run "$NOTIFY" "not-a-name-or-uuid" "x"
  [ "$status" -eq 3 ]
  [[ "$output" == *"is UNKNOWN"* ]] || false
  [[ "$output" == *"readable"* ]] || false          # the distinguishing claim vs exit 4
  [[ "$output" != *"RESOLVER UNAVAILABLE"* ]] || false
}

@test "v4: the 8-char UUID prefix that --list prints ROUND-TRIPS into cc-notify's own input" {
  # `cc-sessions` printed .paneUUID[0:8] for years; cc-notify's own resolver rejected it.
  run "$NOTIFY" "AAAAAAAA" "prefix addressed"
  [ "$status" -eq 0 ]
  [[ "$output" == *"delivered to inbox"* ]] || false
  grep -q '\] prefix addressed' "$CC_MAILBOX_DIR/$UUID.md"
}

@test "v4: a prefix is matched case-insensitively (registry uuids are upper-case)" {
  run "$NOTIFY" "aaaaaaaa" "lower-case prefix"
  [ "$status" -eq 0 ]
  grep -q 'lower-case prefix' "$CC_MAILBOX_DIR/$UUID.md"
}

@test "v4: an AMBIGUOUS prefix fails LOUD (exit 6) and enqueues NOTHING — never a silent wrong pane" {
  local TWIN="AAAAAAAA-5555-6666-7777-888888888888"
  printf '{"paneUUID":"%s","name":"twin","cwd":"/tmp","account":"next","pid":%s,"startedAt":1}' \
    "$TWIN" "$$" > "$CC_REGISTRY_DIR/$TWIN.json"
  run "$NOTIFY" "AAAAAAAA" "who am i for"
  [ "$status" -eq 6 ]
  [[ "$output" == *"AMBIGUOUS"* ]] || false
  [ ! -f "$CC_MAILBOX_DIR/$UUID.md" ]
  [ ! -f "$CC_MAILBOX_DIR/$TWIN.md" ]
}

@test "v4: a name matching only a DEAD row stays unresolvable (the live-only addressing contract holds)" {
  local DEADROW="BBBBBBBB-1111-2222-3333-444444444444"
  printf '{"paneUUID":"%s","name":"ghostpeer","cwd":"/tmp","account":"next","pid":999999,"startedAt":1}' \
    "$DEADROW" > "$CC_REGISTRY_DIR/$DEADROW.json"
  run "$NOTIFY" ghostpeer "x"
  [ "$status" -eq 3 ]
  [ ! -f "$CC_MAILBOX_DIR/$DEADROW.md" ]
}

@test "v4: ONE corrupt registry row cannot take the whole resolver down" {
  # `jq -s` over the set fails wholesale on a single bad file; without the per-file fallback that
  # would turn one unparseable row into a total addressing outage.
  printf 'not json at all {{{' > "$CC_REGISTRY_DIR/CORRUPT.json"
  run "$NOTIFY" peer "resolved despite corruption"
  [ "$status" -eq 0 ]
  [[ "$output" == *"delivered to inbox"* ]] || false
  grep -q 'resolved despite corruption' "$CC_MAILBOX_DIR/$UUID.md"
}

@test "v4: cc-sessions prints the FULL paneUUID, and that column feeds straight back into cc-notify" {
  # The round-trip proven end to end: take what the listing prints, paste it in, and it must resolve.
  local out col
  out="$("$REPO/bin/cc-sessions" 2>/dev/null)"
  [[ "$out" == *"$UUID"* ]] || { echo "listing did not print the full uuid: $out"; false; }
  col="$(printf '%s\n' "$out" | awk '$1=="peer"{print $2}')"
  [ "$col" = "$UUID" ] || { echo "UUID column was '$col', not the full '$UUID'"; false; }
  run "$NOTIFY" "$col" "round-tripped from the listing"
  [ "$status" -eq 0 ]
  grep -q 'round-tripped from the listing' "$CC_MAILBOX_DIR/$UUID.md"
}

@test "v4: cc-sessions itself does not hang when it2 does (--list must work under the load that broke it)" {
  hanging_it2
  export CC_IT2_TIMEOUT_S=1
  local t; t="$(secs "$REPO/bin/cc-sessions" --json)"
  [ "$t" -lt 20 ] || { echo "cc-sessions took ${t}s — its it2 call is still unbounded"; false; }
  # and a timed-out pane list must NOT be read as 'no panes' → the live row survives on pid truth
  run "$REPO/bin/cc-sessions" --json
  [[ "$output" == *"$UUID"* ]] || false
}

@test "a REROUTE follows the desk's OWN forward chain (never tees into a self-closed desk box)" {
  # Without this the anti-stranding mechanism would itself strand mail: the desk role can name a pane
  # that has since self-closed, leaving a .forward to its successor.
  export CC_ROLES_DIR="$BATS_TEST_TMPDIR/roles"; mkdir -p "$CC_ROLES_DIR"
  local OLDDESK="ABCDEF01-1111-2222-3333-444444444444"
  local DEAD="DEADBEEF-1111-2222-3333-444444444444"
  printf '%s\n' "$OLDDESK" > "$CC_ROLES_DIR/desk"              # role still names the OLD desk…
  printf '%s\n' "$UUID"    > "$CC_MAILBOX_DIR/$OLDDESK.forward" # …which self-closed → live successor
  run "$NOTIFY" "$DEAD" "reroute me"
  [ "$status" -eq 0 ]
  [[ "$output" == *"rerouted to desk [$UUID]"* ]] || false      # landed on the SUCCESSOR
  grep -q "\[for:$DEAD\] reroute me" "$CC_MAILBOX_DIR/$UUID.md"
  [ ! -f "$CC_MAILBOX_DIR/$OLDDESK.md" ]                        # nothing written to the dead desk box
}
