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

# ══ KEYSET COVERAGE (2026-07-31) — the reader must cover the WRITER's key space ══════════════════
# One logical inbox, two physical keys. cc-notify addresses a target by role file / registry row /
# raw uuid — all PANE-keyed — and resolves no alias, so its line lands in <pane>.md. mailbox-drain.sh
# reads <session>.md and harvests the pane box by mailbox_migrate at each BOUNDARY. That merge hides
# the split from a session taking turns and is fatal to one that is waiting: a watcher parked on the
# session key sees nothing until a boundary runs, and causing that boundary is the watcher's whole job.
# It reports armed and is deaf — silent, because "armed" and "reachable" were never the same claim.
#
# Mail is seeded BEFORE the watcher runs so every case fires on the first poll in the FOREGROUND: no
# backgrounded watcher, so no fork can outlive the test and fabricate a `not ok` beside a passing body.
SESSKEY="bbbbbbbb-9999-8888-7777-666666666666"
alias_pane_to_session() {
  mkdir -p "$CC_MAILBOX_DIR/.alias"
  printf '2026-07-31T00:00:00+0000 %s\n' "$SESSKEY" > "$CC_MAILBOX_DIR/.alias/$UUID"
}

@test "keyset: a no-arg watcher wakes on a write to the PANE box (what cc-notify actually writes)" {
  alias_pane_to_session
  printf '2026-07-31T10:00:00+0000 [peer] addressed by pane\n' > "$CC_MAILBOX_DIR/$UUID.md"
  ITERM_SESSION_ID="w0t0p0:$UUID" run "$AWAIT" --interval 1 --timeout 4
  [ "$status" -eq 0 ]
  [[ "$output" == *"addressed by pane"* ]] || false
}

@test "keyset: the SAME no-arg watcher also wakes on a write to the SESSION box" {
  alias_pane_to_session
  printf '2026-07-31T10:00:00+0000 [peer] addressed by session\n' > "$CC_MAILBOX_DIR/$SESSKEY.md"
  ITERM_SESSION_ID="w0t0p0:$UUID" run "$AWAIT" --interval 1 --timeout 4
  [ "$status" -eq 0 ]
  [[ "$output" == *"addressed by session"* ]] || false
}

@test "keyset REVERSE: a watcher armed with the SESSION id still covers its pane box" {
  # No forward alias edge exists session→pane, so this direction is resolved by the tip lookup. It is
  # the form every already-running pane will paste from the OLD advisory text during the rollout.
  alias_pane_to_session
  printf '2026-07-31T10:00:00+0000 [peer] reverse edge\n' > "$CC_MAILBOX_DIR/$UUID.md"
  run "$AWAIT" "$SESSKEY" --interval 1 --timeout 4
  [ "$status" -eq 0 ]
  [[ "$output" == *"reverse edge"* ]] || false
}

@test "DISCRIMINATOR: a pane whose trail has MOVED ON is not adopted (tip, never containment)" {
  # $UUID's trail mentions SESSKEY but its current occupant is someone else — that box is the NEW
  # occupant's mail. Covering it would be a cross-session read, so the shortlist must be adjudicated.
  mkdir -p "$CC_MAILBOX_DIR/.alias"
  printf '2026-07-31T00:00:00+0000 %s\n2026-07-31T01:00:00+0000 %s\n' \
    "$SESSKEY" "cccccccc-5555-4444-3333-222222222222" > "$CC_MAILBOX_DIR/.alias/$UUID"
  printf '2026-07-31T10:00:00+0000 [peer] belongs to the NEW occupant\n' > "$CC_MAILBOX_DIR/$UUID.md"
  run "$AWAIT" "$SESSKEY" --interval 1 --timeout 3
  [ "$status" -eq 2 ]                                     # timed out — correctly did NOT take it
  [[ "$output" != *"NEW occupant"* ]] || false
}

@test "keyset: the .watching marker is written under EVERY key (either hook's check answers true)" {
  alias_pane_to_session
  ( sleep 3; printf '2026-07-31T10:00:00+0000 [peer] ping\n' >> "$MB" ) & local writer=$!
  ITERM_SESSION_ID="w0t0p0:$UUID" "$AWAIT" --interval 1 --timeout 10 >/dev/null 2>&1 & local watcher=$!
  sleep 2
  # mailbox-drain.sh asks about its SESSION key; session-continue.sh asks about the canonicalised key.
  # A single-key marker answers one and not the other, and the hook that misses re-nudges an armed
  # session forever — the mirror of the deafness this whole change closes.
  [ -f "$CC_MAILBOX_DIR/$UUID.watching" ]
  [ -f "$CC_MAILBOX_DIR/$SESSKEY.watching" ]
  wait "$watcher" 2>/dev/null || true
  wait "$writer" 2>/dev/null || true
  # and BOTH are cleared on exit, so a finished watcher stops claiming a wake path under either key
  [ ! -f "$CC_MAILBOX_DIR/$UUID.watching" ]
  [ ! -f "$CC_MAILBOX_DIR/$SESSKEY.watching" ]
}

# Pinned, never a moving ref: once this lands, a floating control IS the fixed tree and the proof
# inverts. Replays the REAL pre-fix artifact from git, never a hand-edited approximation.
CC_KEYSET_PREFIX_SHA="${CC_KEYSET_PREFIX_SHA:-0272e835}"
@test "RED-PROOF: the pre-fix watcher is DEAF to the box the writer actually writes" {
  local old="$BATS_TEST_TMPDIR/prekeyset"; mkdir -p "$old"
  git -C "$REPO" archive "$CC_KEYSET_PREFIX_SHA" bin hooks | tar -x -C "$old" \
    || skip "pre-fix tree $CC_KEYSET_PREFIX_SHA unavailable"
  [ -x "$old/bin/cc-await-ping" ]
  ! grep -q 'mailbox_keyset' "$old/hooks/lib/mailbox-pending.sh" || false   # genuinely predates the fix
  alias_pane_to_session
  printf '2026-07-31T10:00:00+0000 [peer] addressed by pane\n' > "$CC_MAILBOX_DIR/$UUID.md"
  # armed on the SESSION key — exactly what the pre-fix advisories told a session to do
  run "$old/bin/cc-await-ping" "$SESSKEY" --interval 1 --timeout 3
  [ "$status" -eq 2 ]                                     # RED: timed out with the mail one filename away
  [[ "$output" != *"addressed by pane"* ]] || false
}
