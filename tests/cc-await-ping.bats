#!/usr/bin/env bats
# Phase 3 — cc-await-ping: the mailbox pull-poller.
# Isolated via CC_MAILBOX_DIR (temp). Short --interval/--timeout keep runs quick.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  AWAIT="$REPO/bin/cc-await-ping"
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mbox"
  mkdir -p "$CC_MAILBOX_DIR"
  UUID="AAAAAAAA-1111-2222-3333-444444444444"
  MB="$CC_MAILBOX_DIR/$UUID.md"
}

@test "exits 0 and prints the new line when a ping lands mid-wait" {
  ( sleep 1; printf '2026-07-10T10:00:00+0000 [peer] HANDOFF-PING slug: done\n' >> "$MB" ) &
  writer=$!
  run "$AWAIT" "$UUID" --interval 1 --timeout 10
  wait "$writer" 2>/dev/null || true
  [ "$status" -eq 0 ]
  [[ "$output" == *"HANDOFF-PING slug: done"* ]]
}

@test "prints ONLY UNSEEN lines (already-consumed history is behind the .seen cursor — F6a)" {
  printf '2026-07-10T09:00:00+0000 [old] earlier message\n' > "$MB"   # history
  printf '1\n' > "$CC_MAILBOX_DIR/$UUID.seen"                          # already consumed up to line 1
  ( sleep 1; printf '2026-07-10T10:00:00+0000 [peer] fresh ping\n' >> "$MB" ) &
  writer=$!
  run "$AWAIT" "$UUID" --interval 1 --timeout 10
  wait "$writer" 2>/dev/null || true
  [ "$status" -eq 0 ]
  [[ "$output" == *"fresh ping"* ]] || false
  [[ "$output" != *"earlier message"* ]] || false
}

@test "F6a: mail ALREADY pending at arm time (unseen, .seen behind EOF) fires IMMEDIATELY" {
  printf '2026-07-10T09:00:00+0000 [reaper] arrived before the watcher armed\n' > "$MB"  # unseen (.seen=0)
  run "$AWAIT" "$UUID" --interval 1 --timeout 5
  [ "$status" -eq 0 ]                                # fires without waiting for the timeout
  [[ "$output" == *"arrived before the watcher armed"* ]] || false
  [ "$(cat "$CC_MAILBOX_DIR/$UUID.seen")" -eq 1 ]    # and advances the shared cursor on fire
}

@test "times out with exit 2 when no ping arrives" {
  run "$AWAIT" "$UUID" --interval 1 --timeout 2
  [ "$status" -eq 2 ]
}

@test "defaults the uuid to \$ITERM_SESSION_ID's pane" {
  DEF="BBBBBBBB-1111-2222-3333-444444444444"
  ( sleep 1; printf 'ping via default uuid\n' >> "$CC_MAILBOX_DIR/$DEF.md" ) &
  writer=$!
  run env ITERM_SESSION_ID="w5t0p2:$DEF" "$AWAIT" --interval 1 --timeout 10
  wait "$writer" 2>/dev/null || true
  [ "$status" -eq 0 ]
  [[ "$output" == *"ping via default uuid"* ]]
}

@test "exits 3 when no uuid given and no \$ITERM_SESSION_ID" {
  run env -u ITERM_SESSION_ID "$AWAIT" --timeout 1
  [ "$status" -eq 3 ]
}

@test "mailbox created AFTER the poller starts still triggers (baseline 0)" {
  rm -f "$MB"   # file absent at start
  ( sleep 1; printf 'appeared later\n' >> "$MB" ) &
  writer=$!
  run "$AWAIT" "$UUID" --interval 1 --timeout 10
  wait "$writer" 2>/dev/null || true
  [ "$status" -eq 0 ]
  [[ "$output" == *"appeared later"* ]]
}

# --- lead-glue: --role mode (SO-1 closer) ---

@test "role: --role resolves the role file and fires on a new mailbox line" {
  export CC_ROLES_DIR="$BATS_TEST_TMPDIR/roles"; mkdir -p "$CC_ROLES_DIR"
  RU="CCCC0001-1111-2222-3333-444444444444"   # role targets are real hex pane UUIDs
  echo "$RU" > "$CC_ROLES_DIR/desk"
  printf 'old\n' > "$CC_MAILBOX_DIR/$RU.md"; printf '1\n' > "$CC_MAILBOX_DIR/$RU.seen"   # history already seen
  ( sleep 1; printf 'PING role\n' >> "$CC_MAILBOX_DIR/$RU.md" ) &
  run "$AWAIT" --role desk --timeout 10 --interval 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"PING role"* ]] || false
}

@test "role: re-pointed role file mid-wait is followed (new mailbox)" {
  export CC_ROLES_DIR="$BATS_TEST_TMPDIR/roles"; mkdir -p "$CC_ROLES_DIR"
  RA="CCCC000A-1111-2222-3333-444444444444"; RB="CCCC000B-1111-2222-3333-444444444444"
  echo "$RA" > "$CC_ROLES_DIR/desk"
  printf 'stale\n' > "$CC_MAILBOX_DIR/$RA.md"; printf '1\n' > "$CC_MAILBOX_DIR/$RA.seen"  # A's history seen
  ( sleep 2; echo "$RB" > "$CC_ROLES_DIR/desk"; sleep 1; printf 'PING successor\n' >> "$CC_MAILBOX_DIR/$RB.md" ) &
  run "$AWAIT" --role desk --timeout 15 --interval 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"PING successor"* ]] || false
}

@test "role: missing role file exits 3 loud" {
  run "$AWAIT" --role nosuchrole --timeout 3 --interval 1
  [ "$status" -eq 3 ]
}

@test "role: --role plus positional uuid is refused" {
  run "$AWAIT" --role desk SOME-UUID --timeout 3 --interval 1
  [ "$status" -eq 2 ]
}

# ── PROVEN WAKE: the .watching claim must be falsifiable, not merely fresh ────────────────────────
@test "the .watching heartbeat records the watcher's OWN pid (a claim its readers can check)" {
  ( sleep 3; printf '2026-07-10T10:00:00+0000 [peer] ping\n' >> "$MB" ) & writer=$!
  "$AWAIT" "$UUID" --interval 1 --timeout 10 >/dev/null 2>&1 & watcher=$!
  sleep 2
  wf="$CC_MAILBOX_DIR/$UUID.watching"
  [ -f "$wf" ]
  wpid="$(sed -n 's/^pid=\([0-9][0-9]*\).*/\1/p' "$wf" | head -n1)"
  [ -n "$wpid" ]
  kill -0 "$wpid"                                  # the recorded pid is a LIVE process…
  [ "$wpid" -eq "$watcher" ]                       # …and it is this watcher, not some other
  wait "$watcher" 2>/dev/null || true
  wait "$writer" 2>/dev/null || true
}

@test "the marker is removed on exit, so a finished watcher stops claiming a wake path" {
  ( sleep 1; printf '2026-07-10T10:00:00+0000 [peer] ping\n' >> "$MB" ) & writer=$!
  run "$AWAIT" "$UUID" --interval 1 --timeout 10
  wait "$writer" 2>/dev/null || true
  [ "$status" -eq 0 ]
  [ ! -f "$CC_MAILBOX_DIR/$UUID.watching" ]
}

@test "F9: cursor-write failure still DELIVERS but exits LOUD (4) + alarms — never a silent clean take" {
  # mailbox_take rc 2 = "body printed, but the cursor write FAILED — the caller must escalate + still
  # deliver, never silently drop". cc-await-ping exited 0 regardless, so the lib's one escalation
  # contract had NO honorer: a broken cursor looked exactly like a clean take, and the same mail would
  # be re-delivered forever with nobody told. Exercised by standing the tool up beside a lib that
  # returns rc 2 (cc-await-ping resolves the lib relative to its own path, so a temp bin/+hooks/lib
  # tree drives the real code down its real rc-2 branch).
  local root="$BATS_TEST_TMPDIR/tree"
  mkdir -p "$root/bin" "$root/hooks/lib"
  cp "$AWAIT" "$root/bin/cc-await-ping"
  cat > "$root/hooks/lib/mailbox-pending.sh" <<'LIB'
mailbox_lines() { echo 1; }
mailbox_has_pending() { return 0; }
mailbox_take() { printf '%s\n' "2026-07-10T10:00:00+0000 [peer] undroppable ping"; return 2; }
LIB
  export CC_COMMS_ALARM_DIR="$BATS_TEST_TMPDIR/comms-alarms"
  printf '2026-07-10T10:00:00+0000 [peer] undroppable ping\n' > "$MB"
  run "$root/bin/cc-await-ping" "$UUID" --interval 1 --timeout 5
  [ "$status" -eq 4 ]
  [[ "$output" == *"undroppable ping"* ]] || false                 # still DELIVERED, never dropped
  [[ "$output" == *"cursor could NOT be advanced"* ]] || false     # …and said so
  [ -n "$(find "$CC_COMMS_ALARM_DIR" -name 'cursor-fail-*.json' 2>/dev/null | head -1)" ]
}

# ── OWNER GUARD — a watcher must never outlive the session it wakes ───────────────────────────────
# MEASURED 2026-07-29: an orphaned watcher is reparented to pid 1 and keeps polling. On the next mail
# it took the line with ack_now=1, advancing BOTH cursors, and printed the body to a stdout no model
# would ever read — marking it PROVABLY CONSUMED for a session that no longer exists. cc-inbox-guard
# then sees unacked=0 and never alarms; a read receipt reports `read`. A silent loss dressed as a
# successful delivery. The wake floor arms every session, so the guard has to hold fleet-wide.

@test "owner guard: an ORPHANED watcher exits WITHOUT consuming (mail stays unacked for the guard)" {
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg"; mkdir -p "$CC_REGISTRY_DIR"
  sleep 0.1 & local dead=$!; wait "$dead" 2>/dev/null || true       # a pid that is now provably dead
  printf '{"paneUUID":"%s","name":"peer","pid":%s,"startedAt":1}' "$UUID" "$dead" \
    > "$CC_REGISTRY_DIR/$UUID.json"
  printf '2026-07-29T14:10:00+0000 [desk] the land-lock blocker is STALE — retry\n' > "$MB"
  run "$AWAIT" "$UUID" --interval 1 --timeout 6
  [ "$status" -eq 5 ]
  # bats merges stderr into $output, so the guard's own message is here — assert the MAIL BODY is not.
  [[ "$output" != *"land-lock blocker is STALE"* ]] || false        # never delivered into the void
  [[ "$output" == *"is GONE"* ]] || false                           # ...and it said why, loudly
  # THE POINT: the cursors are untouched, so the line is still unacked — cc-inbox-guard can alarm on
  # it and the successor's adoption (which migrates from .acked) still inherits it.
  [ ! -f "$CC_MAILBOX_DIR/$UUID.seen" ]
  [ ! -f "$CC_MAILBOX_DIR/$UUID.acked" ]
  [ ! -f "$CC_MAILBOX_DIR/$UUID.watching" ]                         # and it stops claiming a wake path
}

@test "owner guard: a LIVE registered session is still woken (reparenting is NOT evidence of death)" {
  # The false-positive that would disarm the entire fleet: a legitimate run_in_background arm has its
  # launching shell exit immediately, so a HEALTHY watcher's ppid becomes 1 exactly like an orphan's.
  # The guard must key on the registry pid, never on $PPID.
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg"; mkdir -p "$CC_REGISTRY_DIR"
  printf '{"paneUUID":"%s","name":"peer","pid":%s,"startedAt":1}' "$UUID" "$$" \
    > "$CC_REGISTRY_DIR/$UUID.json"
  ( sleep 1; printf '2026-07-29T14:11:00+0000 [desk] retry now\n' >> "$MB" ) & local w=$!
  run "$AWAIT" "$UUID" --interval 1 --timeout 10
  wait "$w" 2>/dev/null || true
  [ "$status" -eq 0 ]
  [[ "$output" == *"retry now"* ]] || false
}

@test "owner guard: an UNREGISTERED pane keeps working — absence of proof is never proof of death" {
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg"; mkdir -p "$CC_REGISTRY_DIR"   # deliberately EMPTY
  ( sleep 1; printf '2026-07-29T14:12:00+0000 [desk] unregistered still wakes\n' >> "$MB" ) & local w=$!
  run "$AWAIT" "$UUID" --interval 1 --timeout 10
  wait "$w" 2>/dev/null || true
  [ "$status" -eq 0 ]                                               # NOT 5
  [[ "$output" == *"unregistered still wakes"* ]] || false
}

@test "owner guard: an UNREADABLE registry row is not death either (fail-safe direction)" {
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg"; mkdir -p "$CC_REGISTRY_DIR"
  printf 'not json at all' > "$CC_REGISTRY_DIR/$UUID.json"
  ( sleep 1; printf '2026-07-29T14:13:00+0000 [desk] corrupt row still wakes\n' >> "$MB" ) & local w=$!
  run "$AWAIT" "$UUID" --interval 1 --timeout 10
  wait "$w" 2>/dev/null || true
  [ "$status" -eq 0 ]
  [[ "$output" == *"corrupt row still wakes"* ]] || false
}
