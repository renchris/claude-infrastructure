#!/usr/bin/env bats
# Phase 3 — cc-await-ping: the mailbox pull-poller.
# Isolated via CC_MAILBOX_DIR (temp). Short --interval/--timeout keep runs quick.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  AWAIT="$REPO/bin/cc-await-ping"
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mbox"
  mkdir -p "$CC_MAILBOX_DIR"
  # FIXTURE THE PANE TRANSPORT (G10). cc-await-ping's owner-guard corroborator defaults to
  # ~/.claude/bin/it2, and this suite does NOT redirect $HOME — so left unset, any test reaching the
  # corroborator would fire a real IPC into the operator's LIVE iTerm2. Set-but-EMPTY is honored
  # verbatim as "no transport" ⇒ pane liveness UNKNOWN, which is the fail-closed branch, so this
  # default can only ever make exit 5 harder to reach. Tests needing a verdict stub it explicitly.
  export CC_AWAIT_IT2_BIN=
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
  # The stub mirrors the seam the tool actually drives. Since F-3 that is mailbox_take_from (a
  # reader-private window) seeded by mailbox_seen — NOT mailbox_has_pending/mailbox_take, which no
  # longer decide anything here. A stub left on the old names would silently fail the
  # `command -v mailbox_take_from` gate, drop the tool to its lib-free path, and pass this test
  # vacuously by never reaching an rc-2 branch at all.
  cat > "$root/hooks/lib/mailbox-pending.sh" <<'LIB'
mailbox_lines() { echo 1; }
mailbox_seen() { echo 0; }
mailbox_take_from() { printf '%s\n' "2026-07-10T10:00:00+0000 [peer] undroppable ping"; return 2; }
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
  # G10: this used to reach exit 5 on the dead registry pid ALONE. It no longer can — that single
  # cached field convicted a live pane in a116d60af388 — so the corroborating pane transport is now
  # stubbed to report the uuid ABSENT. Everything the test actually asserts (no consumption, cursors
  # untouched, marker cleared) is unchanged; only the premise it stands on got a second source.
  # Declared and assigned separately (SC2155): `export X="$(cmd)"` masks the command's exit status
  # behind export's own 0, so a stub builder that FAILED would read as a stub that was installed —
  # and the test would then attribute the missing corroboration to the subject rather than to itself.
  local it2bin
  it2bin="$(it2_stub SOMEONE-ELSE)"
  export CC_AWAIT_IT2_BIN="$it2bin"
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

# ── OVERLAP (def25802babf): two watchers, ONE marker slot ────────────────────────────────────────
# A single watcher's exit is the case the tests above cover, and it passes against the pre-fix code —
# it proves nothing about the defect. The measured incident is an OVERLAP: a session re-arms near the
# term-end of its old watcher, so two are armed on one key, and the first to exit used to rm the
# survivor's heartbeat. Both tests below make the exiting watcher the LAST BEATER (interval 1 beside
# a long-interval survivor), because that is the half of the overlaps a bare pid==$$ guard cannot
# fix: the slot legitimately names the exiting pid, so deleting blanks the survivor and keeping leaves
# a marker naming a pid that is dead — which readers score NOT armed either way.
@test "overlap def25802babf: an exiting watcher hands the marker to its LIVE sibling, never blanks it" {
  wf="$CC_MAILBOX_DIR/$UUID.watching"
  # B — the survivor. A LONG interval so its next beat cannot restore the marker inside the window
  # measured below; otherwise the assertion is satisfied by B's re-beat and the defect goes unseen.
  "$AWAIT" "$UUID" --interval 30 --timeout 90 >/dev/null 2>&1 & B=$!
  sleep 1
  "$AWAIT" "$UUID" --interval 1 --timeout 3 >/dev/null 2>&1 & A=$!
  wait "$A" 2>/dev/null || true                      # A times out ⇒ its EXIT trap runs
  ! kill -0 "$A" 2>/dev/null || false                 # …and A really is gone (not merely detached)
  [ -f "$wf" ]                                       # the survivor's heartbeat is STILL there
  wpid="$(sed -n 's/^pid=\([0-9][0-9]*\).*/\1/p' "$wf" | head -n1)"
  [ "$wpid" -eq "$B" ]                               # and the slot names B, not the pid that exited
  kill -0 "$wpid"                                    # which is alive ⇒ a reader scores ARMED, not DEAF
  kill "$B" 2>/dev/null || true; wait "$B" 2>/dev/null || true
}

# Pinned, never a moving ref — the same rule as the keyset RED-PROOF below: once this lands, a
# floating control IS the fixed tree and the proof inverts. Replays the REAL pre-fix artifact.
CC_AWAIT_OVERLAP_PREFIX_SHA="${CC_AWAIT_OVERLAP_PREFIX_SHA:-399ed0da}"
@test "RED-PROOF def25802babf: the pre-fix watcher blanks a LIVE sibling's heartbeat on exit" {
  local old="$BATS_TEST_TMPDIR/preoverlap"; mkdir -p "$old"
  git -C "$REPO" archive "$CC_AWAIT_OVERLAP_PREFIX_SHA" bin hooks | tar -x -C "$old" \
    || skip "pre-fix tree $CC_AWAIT_OVERLAP_PREFIX_SHA unavailable"
  [ -x "$old/bin/cc-await-ping" ]
  ! grep -q '_claim_live' "$old/bin/cc-await-ping" || false     # genuinely predates the fix
  "$old/bin/cc-await-ping" "$UUID" --interval 30 --timeout 90 >/dev/null 2>&1 & B=$!
  sleep 1
  "$old/bin/cc-await-ping" "$UUID" --interval 1 --timeout 3 >/dev/null 2>&1 & A=$!
  wait "$A" 2>/dev/null || true
  kill -0 "$B"                                       # positive control: the survivor IS still running
  [ ! -f "$CC_MAILBOX_DIR/$UUID.watching" ]          # RED: its wake path was cleared out from under it
  kill "$B" 2>/dev/null || true; wait "$B" 2>/dev/null || true
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

# ══ G10 — THE WAKE PATH: exit 5 needs TWO oracles, and a killed watcher stops being silent ════════
# Backlog a116d60af388 measured exit 5 claiming pane 700 was GONE while pane 700 was alive and typing:
# the pane id had been renumbered underneath the registry, so `<uuid>.json` named a pid that was dead
# while the session it addressed was not. A cached pid is ONE reading of ONE fact; it cannot carry a
# verdict this destructive on its own (exit 5 abandons a live session's wake path).
#
# The corroborator must not be a second reader of the same row. Two are used, in order:
#   B1  pane liveness — the uuid's presence in `it2 session list --json`, iTerm2's OWN answer.
#   B2  cwd occupancy — the row's cwd held by a live pid in a DIFFERENT registry row, which is the
#       renumbering signature the incident actually recorded (a sibling saw the same cwd, new id).
# Both are consulted only AFTER the pid oracle fires, and UNKNOWN never convicts (fail-closed, the
# same direction cc-reconcile's prune takes at :258).
#
# Every it2 answer here comes from a STUB: unstubbed, CC_AWAIT_IT2_BIN would resolve to the operator's
# real ~/.claude/bin/it2 and this suite would IPC into their live iTerm2.
it2_stub() {   # it2_stub <id>...   → a session-list transport reporting exactly these live panes
  local p="$BATS_TEST_TMPDIR/it2-stub" ids="" i
  for i in "$@"; do ids="$ids{\"id\":\"$i\"},"; done
  printf '#!/bin/bash\nprintf %%s %s\n' "'[${ids%,}]'" > "$p"; chmod +x "$p"; printf '%s' "$p"
}
it2_dead() {   # a transport that CANNOT answer (empty output, non-zero) — liveness UNKNOWN
  local p="$BATS_TEST_TMPDIR/it2-dead"; printf '#!/bin/bash\nexit 1\n' > "$p"; chmod +x "$p"; printf '%s' "$p"
}
reg_row() {    # reg_row <uuid> <pid> [cwd]
  printf '{"paneUUID":"%s","name":"peer","pid":%s,"startedAt":1%s}' "$1" "$2" \
    "$([ -n "${3:-}" ] && printf ',"cwd":"%s"' "$3")" > "$CC_REGISTRY_DIR/$1.json"
}
dead_pid() { local d; sleep 0.1 & d=$!; wait "$d" 2>/dev/null || true; printf '%s' "$d"; }

@test "G10 POSITIVE CONTROL: dead pid AND pane absent from iTerm2 ⇒ exit 5 is still reachable" {
  # Without this, every assertion below is satisfied by a guard that simply never fires.
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg"; mkdir -p "$CC_REGISTRY_DIR"
  reg_row "$UUID" "$(dead_pid)"
  printf '2026-08-08T10:00:00+0000 [desk] must not be consumed into the void\n' > "$MB"
  run env CC_AWAIT_IT2_BIN="$(it2_stub SOMEONE-ELSE)" "$AWAIT" "$UUID" --interval 1 --timeout 6
  [ "$status" -eq 5 ]
  [[ "$output" != *"consumed into the void"* ]] || false
  [ ! -f "$CC_MAILBOX_DIR/$UUID.seen" ]
}

@test "G10 REGRESSION a116d60af388: a dead registry pid beside a LIVE pane keeps watching, never 5" {
  # The measured incident. The pid oracle says gone; iTerm2 says the pane is right there. One stale
  # cached field must not abandon a live session's wake path.
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg"; mkdir -p "$CC_REGISTRY_DIR"
  reg_row "$UUID" "$(dead_pid)"
  run env CC_AWAIT_IT2_BIN="$(it2_stub "$UUID" OTHER)" "$AWAIT" "$UUID" --interval 1 --timeout 3
  [ "$status" -eq 2 ]                                   # timed out watching — NOT 5
  [[ "$output" != *"is GONE"* ]] || false
}

@test "G10: a dead pid + a live pane still WAKES on mail (the veto keeps the path armed, not merely open)" {
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg"; mkdir -p "$CC_REGISTRY_DIR"
  reg_row "$UUID" "$(dead_pid)"
  ( sleep 1; printf '2026-08-08T10:01:00+0000 [desk] the wake still lands\n' >> "$MB" ) & local w=$!
  run env CC_AWAIT_IT2_BIN="$(it2_stub "$UUID")" "$AWAIT" "$UUID" --interval 1 --timeout 10
  wait "$w" 2>/dev/null || true
  [ "$status" -eq 0 ]
  [[ "$output" == *"the wake still lands"* ]] || false
}

@test "G10 RENUMBERED: pane absent from iTerm2 but the row's cwd held by a LIVE sibling ⇒ keeps watching" {
  # The incident's own evidence: a sibling handoff-fire self-close saw the SAME cwd under a DIFFERENT
  # pane id. B1 alone convicts here (the id really is gone); B2 is what sees the session survived it.
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg"; mkdir -p "$CC_REGISTRY_DIR"
  local cwd="/Users/x/Development/.worktrees/g10"
  reg_row "$UUID" "$(dead_pid)" "$cwd"
  reg_row "DDDD0001-1111-2222-3333-444444444444" "$$" "$cwd"     # the renumbered sibling, alive
  run env CC_AWAIT_IT2_BIN="$(it2_stub NOBODY)" "$AWAIT" "$UUID" --interval 1 --timeout 3
  [ "$status" -eq 2 ]
  [[ "$output" != *"is GONE"* ]] || false
}

@test "G10 DISCRIMINATOR: same shape but the cwd sibling is DEAD ⇒ nothing vetoes, exit 5 fires" {
  # Proves the cwd oracle is reading liveness, not merely matching a string — without it the test
  # above would pass against a guard that vetoes on any cwd row at all.
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg"; mkdir -p "$CC_REGISTRY_DIR"
  local cwd="/Users/x/Development/.worktrees/g10"
  reg_row "$UUID" "$(dead_pid)" "$cwd"
  reg_row "DDDD0002-1111-2222-3333-444444444444" "$(dead_pid)" "$cwd"
  run env CC_AWAIT_IT2_BIN="$(it2_stub NOBODY)" "$AWAIT" "$UUID" --interval 1 --timeout 6
  [ "$status" -eq 5 ]
}

@test "G10 FAIL-CLOSED: an UNREADABLE pane transport is UNKNOWN, never 'every pane is gone'" {
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg"; mkdir -p "$CC_REGISTRY_DIR"
  reg_row "$UUID" "$(dead_pid)"
  run env CC_AWAIT_IT2_BIN="$(it2_dead)" "$AWAIT" "$UUID" --interval 1 --timeout 3
  [ "$status" -eq 2 ]
  [[ "$output" != *"is GONE"* ]] || false
}

# ── DEFECT 2: a group-TERMed watcher used to die SILENT, still advertising an armed wake path ─────
# The only trap in the file was EXIT, so an external SIGTERM printed nothing and could leave a
# .watching marker claiming a wake this process no longer provides. The sender is NOT recoverable
# from the exit code (143 = the watcher alone, 144 = the harness's process-GROUP sentinel — see the
# header), so this makes the death LEGIBLE; it does not prevent it.

@test "G10: a TERMed watcher prints a verdict on stderr instead of dying silent" {
  local log="$BATS_TEST_TMPDIR/term.log"
  "$AWAIT" "$UUID" --interval 1 --timeout 30 >"$log" 2>&1 & local watcher=$!
  sleep 2
  [ -f "$CC_MAILBOX_DIR/$UUID.watching" ]          # positive control: it WAS armed before the kill
  kill -TERM "$watcher" 2>/dev/null || true
  local rc=0; wait "$watcher" 2>/dev/null || rc=$?
  grep -q 'verdict=killed' "$log"
  [ "$rc" -eq 143 ]
}

@test "G10: a TERMed watcher clears .watching, so it stops advertising a wake it cannot deliver" {
  "$AWAIT" "$UUID" --interval 1 --timeout 30 >/dev/null 2>&1 & local watcher=$!
  sleep 2
  [ -f "$CC_MAILBOX_DIR/$UUID.watching" ]          # positive control for the absence asserted below
  kill -TERM "$watcher" 2>/dev/null || true
  wait "$watcher" 2>/dev/null || true
  [ ! -f "$CC_MAILBOX_DIR/$UUID.watching" ]
}

@test "G10: HUP is handled the same way (a closed pane is not a different kind of death)" {
  local log="$BATS_TEST_TMPDIR/hup.log"
  "$AWAIT" "$UUID" --interval 1 --timeout 30 >"$log" 2>&1 & local watcher=$!
  sleep 2
  kill -HUP "$watcher" 2>/dev/null || true
  local rc=0; wait "$watcher" 2>/dev/null || rc=$?
  grep -q 'verdict=killed' "$log"
  grep -q 'SIGHUP' "$log"
  [ "$rc" -eq 129 ]
  [ ! -f "$CC_MAILBOX_DIR/$UUID.watching" ]
}

@test "G10 CONTROL: an UNKILLED watcher never prints the killed verdict (the trap is not always-on)" {
  run "$AWAIT" "$UUID" --interval 1 --timeout 2
  [ "$status" -eq 2 ]
  [[ "$output" != *"verdict=killed"* ]] || false
  [[ "$output" == *"verdict=timeout"* ]] || false
}

# ── F-3: THE DRAIN AND THE WATCHER MUST NOT SHARE A TRIGGER (2026-08-09) ──────────────────────────
# Measured: a peer executed the protocol perfectly (landed content-verified → pinged → self-closed),
# hooks/mailbox-drain.sh surfaced the ping at a UserPromptSubmit and advanced ONLY .seen (its :13,
# ack_now=0), the Stop-fold then promoted .acked — and the lead's ARMED watcher, polling lines-.seen,
# saw an empty delta forever. Post-mortem: 886.seen=3, 886.acked=3, mailbox 3 lines, watcher alive.
# Delivered, but nobody woken. See docs/plans/TWO_WAY_SESSION_COMMS_PLAN.md § 2026-08-09.

@test "F-3: a drain that advances .seen past a new line does NOT starve an armed watcher" {
  # The interval is deliberately LONGER than the writer's delay so both of the writer's actions (the
  # append AND the drain's cursor advance) are in place before the next poll — otherwise the watcher
  # could catch the line pre-drain and the test would pass for the wrong reason.
  ( sleep 1
    printf '2026-08-09T00:56:08+0000 [peer] HANDOFF-PING: landed 9da394a9c, self-closing\n' >> "$MB"
    printf '1\n' > "$CC_MAILBOX_DIR/$UUID.seen"     # the drain surfaced it and advanced .seen
    printf '1\n' > "$CC_MAILBOX_DIR/$UUID.acked"    # ...and the Stop-fold promoted .acked to match
  ) &
  writer=$!
  run "$AWAIT" "$UUID" --interval 3 --timeout 15
  wait "$writer" 2>/dev/null || true
  [ "$status" -eq 0 ]                                # NOT 2 — a timeout here is the forever-hang
  [[ "$output" == *"landed 9da394a9c"* ]] || false   # and the body is still printed, not an empty fire
}

@test "F-3 CONTROL: mail drained BEFORE the arm does NOT fire (the seed, not a wake loop)" {
  # The other direction, and the reason the private cursor is SEEDED from .seen rather than from 0:
  # a watcher that fired on any non-empty box would return instantly on every arm, turning the wake
  # path into an arm→fire→arm busy loop. Already-consumed history must stay silent.
  printf '2026-08-09T00:50:00+0000 [peer] read in a previous turn\n' > "$MB"
  printf '1\n' > "$CC_MAILBOX_DIR/$UUID.seen"
  printf '1\n' > "$CC_MAILBOX_DIR/$UUID.acked"
  run "$AWAIT" "$UUID" --interval 1 --timeout 3
  [ "$status" -eq 2 ]
  [[ "$output" == *"verdict=timeout"* ]] || false
}

@test "F-3: the watcher advances .seen/.acked when IT is first, and never REGRESSES a further-ahead one" {
  # Two halves of mailbox_take_from's contract in one arm. A watcher is an ADDITIONAL consumer, so it
  # must reconcile the shared cursors on fire (or cc-inbox-guard alarms and receipts read `unread`)
  # while never writing a SMALLER value over another consumer's — which would un-deliver its mail and
  # re-create this same race in the opposite direction.
  printf 'line one\n' > "$MB"                       # history, already surfaced before we arm
  printf '1\n' > "$CC_MAILBOX_DIR/$UUID.seen"
  printf '0\n' > "$CC_MAILBOX_DIR/$UUID.acked"      # ...but not yet provably consumed
  ( sleep 1
    printf '2026-08-09T01:00:00+0000 [peer] second line\n' >> "$MB"
    printf '2\n' > "$CC_MAILBOX_DIR/$UUID.seen"     # the drain runs first and gets AHEAD of us
  ) &
  writer=$!
  run "$AWAIT" "$UUID" --interval 3 --timeout 15
  wait "$writer" 2>/dev/null || true
  [ "$status" -eq 0 ]
  [[ "$output" == *"second line"* ]] || false
  [ "$(cat "$CC_MAILBOX_DIR/$UUID.seen")" -eq 2 ]   # not regressed
  [ "$(cat "$CC_MAILBOX_DIR/$UUID.acked")" -eq 2 ]  # promoted by our reliable delivery
}

# ── F-2: THE DEAF LEAD (2026-08-09) ──────────────────────────────────────────────────────────────
# Measured the same night as F-3: the lead's watcher exited 144 (an external group-TERM) and the lead
# never noticed it had gone deaf. The verdict was correct and complete — it just rode stderr of a
# background task the harness renders as `failed`, which a lead triages as noise. The fix puts the
# same verdict on the channel this substrate already proves a lead consumes: its own inbox.

@test "F-2: a TERMed watcher writes WAKE-PATH-DOWN into the inbox it was watching" {
  "$AWAIT" "$UUID" --interval 1 --timeout 30 >/dev/null 2>&1 & local watcher=$!
  sleep 2
  [ -f "$CC_MAILBOX_DIR/$UUID.watching" ]            # positive control: it WAS armed before the kill
  kill -TERM "$watcher" 2>/dev/null || true
  wait "$watcher" 2>/dev/null || true
  grep -q 'WAKE-PATH-DOWN' "$MB"                     # …and the death is now ordinary, drainable mail
  grep -q "$UUID" "$MB"
}

@test "F-2: the WAKE-PATH-DOWN line is drain-shaped, so a boundary surfaces it as peer mail" {
  # hooks/mailbox-drain.sh parses `<ISO> [<from>] <msg>` for its operator-visible digest and counts a
  # line as PENDING off the cursor. A line that did not match would still be delivered, but it would
  # be attributed to nobody — so the shape is asserted, not assumed.
  "$AWAIT" "$UUID" --interval 1 --timeout 30 >/dev/null 2>&1 & local watcher=$!
  sleep 2
  kill -TERM "$watcher" 2>/dev/null || true
  wait "$watcher" 2>/dev/null || true
  grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[+-][0-9]{4} \[cc-await-ping\] WAKE-PATH-DOWN' "$MB"
  # and it is genuinely UNDRAINED — the whole point is that the next boundary still has it to surface
  [ ! -f "$CC_MAILBOX_DIR/$UUID.seen" ] || [ "$(cat "$CC_MAILBOX_DIR/$UUID.seen")" -eq 0 ]
}

@test "F-2 CONTROL: a clean TIMEOUT writes no WAKE-PATH-DOWN (an alarm that always fires says nothing)" {
  # A timeout is the DESIGNED end of a healthy watch, not a wake-path failure. Writing a line on
  # every 4-hour term would put this alarm on the normal path, where it would carry as few bits as
  # one that never fires. Only the anomaly — an external kill — is news.
  run "$AWAIT" "$UUID" --interval 1 --timeout 2
  [ "$status" -eq 2 ]
  [ ! -f "$MB" ] || ! grep -q 'WAKE-PATH-DOWN' "$MB"
}

# ── e2903b01dfdc: `elapsed=` IS A MEASUREMENT, NOT THE ARGUMENT ECHOED BACK ────────────────────────
# The timeout verdict printed `elapsed=${TIMEOUT}s` — the value the CALLER PASSED IN. The field is
# named `elapsed`, so it read as evidence the watch ran its full term, while being a restatement of
# the input: it would print the identical string for a watcher that exited instantly. That made the
# one question a `--notify-back` originator actually needs answerable unanswerable from the tool's own
# output — *was my wake path real, or was I deaf?* — and it matters because backlog #127 records a
# REAL early-exit mode (exit 144, the armed wake path silently disarms).
#
# Every test below is RED against that line. The helper is shared so a future exit path can be held to
# the same contract in one place.
_verdict_elapsed() {   # <stream-file|-> → the integer seconds in the FIRST `elapsed=<n>s` field
  sed -n 's/.*elapsed=\([0-9][0-9]*\)s.*/\1/p' "${1:--}" | head -n1
}

@test "e2903b01dfdc: the timeout verdict reports MEASURED wall time, labelled apart from the budget" {
  # --interval 3 with --timeout 2: the tick accumulator clears the budget after ONE sleep, so a
  # truthful measurement necessarily OVERSHOOTS what was configured. The pre-fix line could only ever
  # print 2 — so this asserts the two numbers are now separately sourced, not one value twice.
  run "$AWAIT" "$UUID" --interval 3 --timeout 2
  [ "$status" -eq 2 ]
  # Ordered so the RED lands on the CLAIM, not on a new field's absence: pre-fix this reads 2.
  local e; e="$(printf '%s\n' "$output" | _verdict_elapsed)"
  [ -n "$e" ]
  [ "$e" -ge 3 ]                                      # ≥ the one sleep it actually slept ⇒ measured
  [[ "$output" == *"budget=2s"* ]] || false           # the configured value, now correctly LABELLED
  [[ "$output" == *"term=full"* ]] || false           # it did hold its budget, and says which
}

@test "e2903b01dfdc RED-PROOF: a watch that COLLAPSES instantly says term=short, not a full term" {
  # THE FALSIFICATION. The loop is driven by a TICK ACCUMULATOR (+INTERVAL per pass) that assumes
  # every sleep slept; neuter `sleep` and the counter runs a full 60s term while the wall clock moves
  # ~0 — a watcher that armed and retired in the same second, with the wake path down for the whole
  # 60s its caller believed it was covered. That is backlog #127's class, and the pre-fix line
  # reported it as `elapsed=60s`: character-for-character identical to a watch that held for a minute.
  local shim="$BATS_TEST_TMPDIR/nosleep"; mkdir -p "$shim"
  printf '#!/bin/bash\nexit 0\n' > "$shim/sleep"; chmod +x "$shim/sleep"
  local t0; t0="$(date +%s)"
  run env PATH="$shim:$PATH" "$AWAIT" "$UUID" --interval 30 --timeout 60
  local wall=$(( $(date +%s) - t0 ))
  [ "$status" -eq 2 ]
  [ "$wall" -lt 10 ]                                  # positive control: it really did collapse
  # FIRST, so the pre-fix RED is the LIE itself and not a missing field: that build prints this exact
  # string for a watcher measured (above) to have lived under 10 seconds.
  [[ "$output" != *"elapsed=60s"* ]] || false
  [[ "$output" == *"term=short"* ]] || false           # …and the verdict names the collapse
  [[ "$output" == *"budget=60s"* ]] || false
  local e; e="$(printf '%s\n' "$output" | _verdict_elapsed)"
  [ -n "$e" ]
  [ "$e" -lt 10 ]                                      # the number tracks the clock, not the argument
}

@test "e2903b01dfdc: the KILLED verdict carries the measured slice of term it lost" {
  # 143/144 is the early exit an originator most needs sized: how much of the arm was actually covered
  # before something killed it. Both channels the death rides — stderr and the WAKE-PATH-DOWN inbox
  # line — now carry it, because a reader of either one is deciding whether to re-arm.
  local log="$BATS_TEST_TMPDIR/killed.log"
  "$AWAIT" "$UUID" --interval 1 --timeout 300 >"$log" 2>&1 & local watcher=$!
  sleep 3
  kill -TERM "$watcher" 2>/dev/null || true
  wait "$watcher" 2>/dev/null || true
  grep -q 'verdict=killed' "$log"
  grep -q 'budget=300s' "$log"
  local e; e="$(_verdict_elapsed "$log")"
  [ -n "$e" ]
  [ "$e" -ge 2 ]                                       # a real slice…
  [ "$e" -lt 300 ]                                     # …never the budget echoed back
  grep -q 'budget=300s' "$MB"                          # and the drainable inbox line says it too
}

@test "e2903b01dfdc: a DELIVERY states its duration, and never on the payload stream" {
  # A take used to say nothing about time at all, so a ping consumed 1s after arming — an already
  # pending line, or a re-arm racing a peer — was indistinguishable from one that proved a long watch.
  # Streams asserted SEPARATELY (not via bats' merged $output): the body on stdout is the payload and
  # a verdict leaking into it would corrupt every consumer that reads the mail.
  local out="$BATS_TEST_TMPDIR/take.out" err="$BATS_TEST_TMPDIR/take.err" rc=0
  printf '2026-07-10T09:00:00+0000 [peer] pending before the arm\n' > "$MB"
  "$AWAIT" "$UUID" --interval 1 --timeout 900 >"$out" 2>"$err" || rc=$?
  [ "$rc" -eq 0 ]
  grep -q 'pending before the arm' "$out"
  ! grep -q 'verdict=' "$out"                          # stdout is payload ONLY
  grep -q 'verdict=ping' "$err"
  grep -q 'budget=900s' "$err"
  local e; e="$(_verdict_elapsed "$err")"
  [ -n "$e" ]
  [ "$e" -lt 10 ]                                      # fired at once ⇒ says so, never 900
}
