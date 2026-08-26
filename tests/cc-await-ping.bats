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
  # FIXTURE THE BEAT DIR for the same reason: --idle-scoped reads ~/.claude/cc-beats/<sid>.json to
  # decide whether its session has taken a new turn, and this suite does not redirect $HOME. Pinned
  # here rather than per-test so no future test can read the operator's live beats by omission.
  export CC_BEAT_DIR="$BATS_TEST_TMPDIR/beats"
  mkdir -p "$CC_BEAT_DIR"
  UUID="AAAAAAAA-1111-2222-3333-444444444444"
  MB="$CC_MAILBOX_DIR/$UUID.md"
  SID="sidGOAL"
}

# ── beat fixtures (the C2 oracle) ────────────────────────────────────────────────────────────────
# One attestation per turn boundary, exactly the shape hooks/session-beat.sh writes:
# kind=prompt at UserPromptSubmit, kind=stop at Stop, `seq` monotone across both.
#
# `who` is the fourth field and it is load-bearing, not decoration (backlog b60eb29e97dd): the hook
# computes it from the auto-traffic regex, so a Stop-hook-forced continuation beats `auto` and only a
# typed message beats `operator`. The watcher uses exactly that distinction to tell the arming turn's
# own completion chain from a genuine wake. Default stays `auto` — the forced-turn case is the one
# every pre-existing test in this file was modelling.
beat() { # <seq> <kind> [age-seconds] [who]
  local age="${3:-0}" who="${4:-auto}"
  jq -nc --arg k "$2" --arg w "$who" --argjson s "$1" --argjson t "$(( $(date +%s) - age ))" \
    '{sid:"sidGOAL",pane:"p0",cwd:"/tmp",pid:1,lstart:"x",t:$t,kind:$k,who:$w,operatorT:null,seq:$s}' \
    > "$CC_BEAT_DIR/$SID.json"
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
  # NO `-` OPERAND. `"${1:--}"` spelled stdin the GNU way and this box is BSD, where sed reads `-`
  # as a literal FILENAME and dies `sed: -: No such file or directory`. So `$e` came back EMPTY and
  # both piped call sites failed on `[ -n "$e" ]` — the helper measured nothing, in the two cases
  # whose whole subject is a MEASURED elapsed. Omitting the operand is the portable spelling of
  # stdin, and it is exactly what those call sites need.
  if [ -n "${1:-}" ] && [ "$1" != "-" ]; then
    sed -n 's/.*elapsed=\([0-9][0-9]*\)s.*/\1/p' "$1" | head -n1
  else
    sed -n 's/.*elapsed=\([0-9][0-9]*\)s.*/\1/p' | head -n1
  fi
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
  ! grep -q 'verdict=' "$out" || false                 # stdout is payload ONLY
  grep -q 'verdict=ping' "$err"
  grep -q 'budget=900s' "$err"
  local e; e="$(_verdict_elapsed "$err")"
  [ -n "$e" ]
  [ "$e" -lt 10 ]                                      # fired at once ⇒ says so, never 900
}

# ── --idle-scoped: THE THIRD IDLE MODE (2026-08-16) ───────────────────────────────────────────────
# docs/research/goal-safe-2way-comms-2026-08-13.md §4, backlog 6290f0ee6b52.
#
# A session holding a live /goal has exactly two idle modes and needs a third. Park a background
# task and CC defers the goal's evaluation for as long as the task lives (the STARVATION pole: 47 of
# 84 goal sessions never evaluated once). Stay bare and every unmet evaluation blocks the stop (the
# SPIN pole: 90 unmet evaluations in 76 minutes on the type specimen, one forced turn every ~51 s,
# all re-judging a world in which nothing had changed). `--idle-scoped` is the third: it dies on
# peer mail AND on any new turn of its own session, so the deferral spans exactly the idle window.
#
# The two RED-PROOFS at the foot of this block are the load-bearing tests. Everything above them
# asserts a behaviour; those two assert that the behaviour is what SEPARATES this shape from the two
# failures it exists to replace — a mutant that never self-cancels must starve a fixture goal, and a
# session with no watcher at all must spin one, on the identical timeline.

@test "idle-scoped: stands down (exit 0, verdict=stood-down) when its session takes a new turn" {
  # Armed on a Stop that has already STOOD 5 s: the idle window is open on the first poll, so the
  # next boundary is unambiguously a new turn rather than the arming turn's own completion.
  export CC_AWAIT_SETTLE_DWELL_S=2
  beat 6 stop 5
  ( sleep 2; beat 7 prompt ) &
  local writer=$!
  run "$AWAIT" "$UUID" --idle-scoped --sid "$SID" --interval 1 --timeout 15
  wait "$writer" 2>/dev/null || true
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=stood-down reason=new-turn"* ]] || false
}

@test "idle-scoped: the stand-down carries NO body — there is no mail, and a fake one would be a lie" {
  export CC_AWAIT_SETTLE_DWELL_S=2
  beat 6 stop 5
  ( sleep 2; beat 7 prompt ) &
  local writer=$!
  run "$AWAIT" "$UUID" --idle-scoped --sid "$SID" --interval 1 --timeout 15
  wait "$writer" 2>/dev/null || true
  [ "$status" -eq 0 ]
  [ ! -f "$MB" ] || [ ! -s "$MB" ]
}

@test "idle-scoped: the ARM TURN's own trailing Stop does NOT self-cancel it" {
  # The arm happens inside a turn, so that turn's Stop beat lands moments later. Cancelling on it
  # would make the mode useless: the watcher would die before the idle it was scoped to even began.
  beat 10 prompt
  ( sleep 1; beat 11 stop ) &
  local writer=$!
  run "$AWAIT" "$UUID" --idle-scoped --sid "$SID" --interval 1 --timeout 4
  wait "$writer" 2>/dev/null || true
  [ "$status" -eq 2 ]                                  # still watching → ran its term
  [[ "$output" != *"stood-down"* ]] || false
}

# ── b60eb29e97dd: THE ARMING TURN IS NOT OVER AT ARM TIME ─────────────────────────────────────────
# The three tests below are the regression the whole rewrite exists for, and the first is the one
# that was RED. `baseline + 1` assumed the arming turn's completion emits exactly one boundary. It
# does not: the arm is instructed BY a Stop hook that BLOCKED, and any of this fleet's other Stop
# arms can block the arming turn's own Stop in turn — each block writing a Stop beat AND the
# UserPromptSubmit beat of the turn it forces, i.e. +2 per block. Measured 2/2 live arms stood down
# on their own arming turn (banners `beat seq > 3`, `beat seq > 6`), which made the arm the wake
# floor DEMANDS a deterministic no-op and spent that floor's 2-attempt budget on nothing.

@test "idle-scoped REGRESSION: a BLOCKED arming-turn completion does not stand the watcher down" {
  export CC_AWAIT_SETTLE_DWELL_S=3
  beat 20 prompt                                       # armed inside the floor-forced turn
  (
    sleep 1; beat 21 stop                              # its Stop …
    sleep 1; beat 22 prompt                            # … BLOCKED — hook feedback forces another turn
    sleep 1; beat 23 stop                              # that turn's Stop …
    sleep 1; beat 24 prompt                            # … blocked again
  ) &
  local writer=$!
  run "$AWAIT" "$UUID" --idle-scoped --sid "$SID" --interval 1 --timeout 7
  wait "$writer" 2>/dev/null || true
  [ "$status" -eq 2 ]                                  # survived its own arming turn
  [[ "$output" != *"stood-down"* ]] || false
}

@test "idle-scoped: a TYPED turn cancels even before the window opens — Phase A is not a deaf spot" {
  # The one wake that can arrive mid-chain and must never be sat on. hooks/session-beat.sh already
  # separates it from every forced turn: its `who` predicate is the auto-traffic regex, which matches
  # `Stop hook feedback:` and the task/advisory prefixes by construction.
  export CC_AWAIT_SETTLE_DWELL_S=30                    # keep the watcher firmly inside Phase A
  beat 20 prompt
  ( sleep 1; beat 21 stop; sleep 1; beat 22 prompt 0 operator ) &
  local writer=$!
  run "$AWAIT" "$UUID" --idle-scoped --sid "$SID" --interval 1 --timeout 15
  wait "$writer" 2>/dev/null || true
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=stood-down reason=operator-turn"* ]] || false
}

@test "idle-scoped: Phase A is BOUNDED — a chain that never settles stands down, never parks forever" {
  # The fail-safe that keeps the fix from re-creating the starvation pole it replaces. A session that
  # never reaches a standing Stop is taking turns continuously, so it is not idle and not deaf.
  export CC_AWAIT_SETTLE_DWELL_S=30
  export CC_AWAIT_SETTLE_MAX_S=3
  beat 20 prompt
  run "$AWAIT" "$UUID" --idle-scoped --sid "$SID" --interval 1 --timeout 20
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=stood-down reason=never-settled"* ]] || false
}

@test "idle-scoped: a jumped Stop beat RE-BASELINES — the sampling hole, closed the other way" {
  # The beat file holds only the LATEST boundary, so a whole turn can complete inside one poll and
  # leave the watcher looking at a Stop-kind beat whose prompt predecessor it never sampled. The old
  # rule stood down on it, which is what the blocked-completion chain above turned into a no-op.
  # Adopting it as the window's floor instead keeps the anti-starvation property — the watcher tracks
  # the session's CURRENT position rather than standing down over a stale one — without dying on its
  # own arming turn.
  export CC_AWAIT_SETTLE_DWELL_S=2
  beat 10 prompt
  ( sleep 1; beat 13 stop ) &
  local writer=$!
  run "$AWAIT" "$UUID" --idle-scoped --sid "$SID" --interval 1 --timeout 6
  wait "$writer" 2>/dev/null || true
  [ "$status" -eq 2 ]                                  # the jump itself is NOT a stand-down …
  [[ "$output" == *"SETTLED at beat seq 13"* ]] || false   # … it becomes the floor
}

@test "idle-scoped: once re-baselined on a jumped Stop, the NEXT boundary does cancel" {
  export CC_AWAIT_SETTLE_DWELL_S=2
  beat 10 prompt
  ( sleep 1; beat 13 stop; sleep 4; beat 14 prompt ) &
  local writer=$!
  run "$AWAIT" "$UUID" --idle-scoped --sid "$SID" --interval 1 --timeout 15
  wait "$writer" 2>/dev/null || true
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=stood-down reason=new-turn"* ]] || false
}

@test "idle-scoped C1: MAIL still wins — a ping is delivered, never traded for a silent stand-down" {
  beat 5 prompt
  # both events land inside ONE poll interval, and the mail check runs first within an iteration:
  # a delivered ping is the thing the session must not lose, and delivering it also ends the watch.
  ( sleep 1; printf '2026-08-16T10:00:00+0000 [peer] HANDOFF-PING slug: landed\n' >> "$MB"; beat 6 prompt ) &
  local writer=$!
  run "$AWAIT" "$UUID" --idle-scoped --sid "$SID" --interval 3 --timeout 15
  wait "$writer" 2>/dev/null || true
  [ "$status" -eq 0 ]
  [[ "$output" == *"HANDOFF-PING slug: landed"* ]] || false
}

@test "idle-scoped C5: --timeout defaults to 3600 and --interval to 5, and both stay overridable" {
  beat 5 prompt
  run "$AWAIT" "$UUID" --idle-scoped --sid "$SID" --timeout 1 --interval 1
  [ "$status" -eq 2 ]
  [[ "$output" == *"timeout 1s, every 1s"* ]] || false     # the override is honoured
  # and the defaults are the MODE's, not the bare form's 1800/15
  run timeout 3 "$AWAIT" "$UUID" --idle-scoped --sid "$SID"
  [[ "$output" == *"timeout 3600s, every 5s"* ]] || false
}

@test "idle-scoped CONTROL: the bare form's defaults are untouched (1800/15), and rejects --sid" {
  run timeout 3 "$AWAIT" "$UUID"
  [[ "$output" == *"timeout 1800s, every 15s"* ]] || false
  run "$AWAIT" "$UUID" --sid "$SID" --timeout 1
  [ "$status" -eq 2 ]
  [[ "$output" == *"only meaningful with --idle-scoped"* ]] || false
}

# ── the three refusals: exit 6, and NOTHING parked ────────────────────────────────────────────────
# A refusal is not an exit. An exit is a watch that did its job; a refusal is a watch that was never
# safe to start, so it must create no deferral at all — which is why each of these asserts the exit
# code AND the absence of any heartbeat left behind.

@test "idle-scoped C4: REFUSES to arm while mail is already pending (you have work, not an idle)" {
  beat 5 prompt
  printf '2026-08-16T09:00:00+0000 [peer] already waiting for you\n' > "$MB"
  run "$AWAIT" "$UUID" --idle-scoped --sid "$SID" --interval 1 --timeout 10
  [ "$status" -eq 6 ]
  [[ "$output" == *"reason=pending-mail"* ]] || false
  [ ! -f "$CC_MAILBOX_DIR/$UUID.watching" ]            # nothing parked ⇒ no goal deferral created
  [ ! -f "$CC_MAILBOX_DIR/$UUID.seen" ]                # and the mail is untouched, still to be read
}

@test "idle-scoped C3: REFUSES while a live SIBLING watcher already claims the key" {
  beat 5 prompt
  mkdir -p "$CC_MAILBOX_DIR/.watchers"
  sleep 60 & local sib=$!
  : > "$CC_MAILBOX_DIR/.watchers/$UUID.$sib"
  run "$AWAIT" "$UUID" --idle-scoped --sid "$SID" --interval 1 --timeout 10
  kill "$sib" 2>/dev/null || true
  wait "$sib" 2>/dev/null || true
  [ "$status" -eq 6 ]
  [[ "$output" == *"reason=sibling-watcher"* ]] || false
  [[ "$output" == *"pid $sib"* ]] || false
}

@test "idle-scoped C3 CONTROL: a DEAD sibling's claim is no claim — the arm proceeds" {
  # the discrimination, not just the refusal: a stale claim file that outlived its watcher must not
  # be able to make this session permanently unable to arm a wake path.
  beat 5 prompt
  mkdir -p "$CC_MAILBOX_DIR/.watchers"
  sleep 0.1 & local gone=$!
  wait "$gone" 2>/dev/null || true
  : > "$CC_MAILBOX_DIR/.watchers/$UUID.$gone"
  run "$AWAIT" "$UUID" --idle-scoped --sid "$SID" --interval 1 --timeout 2
  [ "$status" -eq 2 ]                                  # armed and ran its term
}

@test "idle-scoped: REFUSES when the beat oracle is missing — fail-closed is the whole licence" {
  # Without a readable beat there is no way to learn a new turn happened, so C2 could never fire and
  # this would be an ordinary parked task wearing the safe mode's name. That is the starvation pole,
  # armed deliberately. Refusing is what makes the flag mean something the chokepoint can admit.
  run "$AWAIT" "$UUID" --idle-scoped --sid "$SID" --interval 1 --timeout 10
  [ "$status" -eq 6 ]
  [[ "$output" == *"reason=no-beat"* ]] || false
  [ ! -f "$CC_MAILBOX_DIR/$UUID.watching" ]
}

@test "idle-scoped: REFUSES on a STALE beat (the producer is not running, or the sid is not ours)" {
  beat 5 prompt 5000
  run "$AWAIT" "$UUID" --idle-scoped --sid "$SID" --interval 1 --timeout 10
  [ "$status" -eq 6 ]
  [[ "$output" == *"reason=stale-beat"* ]] || false
}

@test "idle-scoped: REFUSES when no sid can be resolved at all" {
  run env -u CC_AWAIT_SID -u ITERM_SESSION_ID -u CC_PANE_ID "$AWAIT" "$UUID" --idle-scoped --interval 1 --timeout 10
  [ "$status" -eq 6 ]
  [[ "$output" == *"reason=no-session-id"* ]] || false
}

@test "idle-scoped: resolves the sid by PANE when --sid is omitted (the convenience path)" {
  beat 5 prompt
  run env ITERM_SESSION_ID="w0t0p0:$UUID" CC_PANE_ID=p0 "$AWAIT" "$UUID" --idle-scoped --interval 1 --timeout 2
  [ "$status" -eq 2 ]                                  # armed → the pane fallback found sidGOAL
  [[ "$output" == *"armed at beat seq 5 of [$SID]"* ]] || false
}

@test "idle-scoped: a REFUSAL never prints the watching banner (it would report the opposite)" {
  run "$AWAIT" "$UUID" --idle-scoped --sid "$SID" --interval 1 --timeout 10
  [ "$status" -eq 6 ]
  [[ "$output" != *"watching $UUID inbox"* ]] || false
}

# ── RED-PROOF, BOTH POLES ────────────────────────────────────────────────────────────────────────
# The fixture goal models exactly two measured harness facts and nothing else:
#   A2  at a Stop where a NON-TERMINAL background task exists, CC deletes the /goal Stop hook before
#       the runner sees it and restores it in a `finally` — the goal is silently NOT evaluated.
#   A3  otherwise the goal IS evaluated; unmet blocks the stop and the session takes another turn.
# So "is a background task alive at this stop attempt?" is the entire model, and `kill -0` answers
# it. Every variant below runs the IDENTICAL timeline — same attempt count, same event at the same
# point — so the only thing that differs is the shape of the watcher.

stop_attempts() { # <pid|0> <count> → the number of those stops at which the goal would EVALUATE
  local pid="$1" n="$2" i=0 ev=0
  while [ "$i" -lt "$n" ]; do
    sleep 1
    if [ "$pid" = 0 ] || ! kill -0 "$pid" 2>/dev/null; then ev=$(( ev + 1 )); fi
    i=$(( i + 1 ))
  done
  printf '%s' "$ev"
}

@test "RED-PROOF pole 1 (STARVATION): a mutant that never self-cancels leaves the fixture goal at ZERO evaluations" {
  # A bin/ + hooks/lib/ tree, not a bare copy: the tool resolves its mailbox lib relative to its own
  # path, and --idle-scoped REFUSES to arm without it (exit 6, reason=no-mailbox-lib). A bare copy in
  # a tmpdir would therefore refuse instantly and this proof would "pass" on a watcher that never ran.
  local root="$BATS_TEST_TMPDIR/starve" mut
  mkdir -p "$root/bin" "$root/hooks/lib"
  cp "$REPO/hooks/lib/mailbox-pending.sh" "$root/hooks/lib/"
  mut="$root/bin/cc-await-ping"
  sed 's/^  if _turn_moved; then$/  if false; then/' "$AWAIT" > "$mut"
  chmod +x "$mut"
  # THE MUTATION MUST HAVE BITTEN. A sed that matched nothing yields a copy of the real script and
  # this red-proof silently becomes a second green test — the failure mode that makes a mutation
  # proof worse than no proof at all.
  ! grep -q '^  if _turn_moved; then$' "$mut" || false

  # Armed on a Stop that has already STOOD, so the idle window is open from the first poll and the
  # ONLY thing separating this mutant from the green case below is the self-cancel it lost.
  export CC_AWAIT_SETTLE_DWELL_S=2
  beat 6 stop 5
  "$mut" "$UUID" --idle-scoped --sid "$SID" --interval 1 --timeout 60 >/dev/null 2>&1 &
  local w=$!
  sleep 1
  local before; before="$(stop_attempts "$w" 3)"
  beat 7 prompt                                        # the external event: this session woke
  local after; after="$(stop_attempts "$w" 4)"
  # positive control: it is still alive, so this is the MUTATION and not a crashed watcher
  kill -0 "$w" 2>/dev/null || false
  kill "$w" 2>/dev/null || true
  wait "$w" 2>/dev/null || true

  [ "$before" -eq 0 ]                                  # correct: nothing had changed, nothing judged
  [ "$after" -eq 0 ]                                   # RED: the world CHANGED and the goal never learned
}

@test "GREEN pole 1: the real idle-scoped watcher lets the goal evaluate ONCE the world has changed" {
  export CC_AWAIT_SETTLE_DWELL_S=2
  beat 6 stop 5
  "$AWAIT" "$UUID" --idle-scoped --sid "$SID" --interval 1 --timeout 60 >/dev/null 2>&1 &
  local w=$!
  sleep 1
  local before; before="$(stop_attempts "$w" 3)"
  beat 7 prompt
  local after; after="$(stop_attempts "$w" 4)"
  kill "$w" 2>/dev/null || true
  wait "$w" 2>/dev/null || true

  [ "$before" -eq 0 ]                                  # quiet while genuinely idle — no spin
  [ "$after" -ge 1 ]                                   # and judged once the world moved — no starvation
}

@test "RED-PROOF pole 2 (SPIN): with NO watcher armed, every stop re-judges an unchanged world" {
  # This is the state today's chokepoint forces on a goal-armed session: bare. On the SAME timeline,
  # the goal is evaluated at every single stop attempt — 7 evaluations for 1 event, which is the
  # 90-evaluations-in-76-minutes specimen in miniature. Measured economics: 82% of met goals are met
  # on evaluation #1 and the met rate falls to 27% at ≥10, so evaluations 2..7 here carry nothing.
  beat 5 prompt
  local before; before="$(stop_attempts 0 3)"
  beat 6 prompt
  local after; after="$(stop_attempts 0 4)"
  [ "$before" -eq 3 ]
  [ "$after" -eq 4 ]
  [ "$(( before + after ))" -eq 7 ]                     # 7 evaluations, 1 event — the spin pole
}

# ── E1: THE CORPSE MUST NOT PRESCRIBE THE ACT THE CHOKEPOINT DENIES (2026-08-15) ──────────────────
# docs/research/goal-safe-2way-comms-2026-08-13.md §8 E1. The screenshot that opened that
# investigation: a session with a LIVE /goal killed its own pre-goal watcher (correct), and this
# notice told it to RE-ARM — the exact shape hooks/validate-bash.sh DENIES under a live goal, because
# a parked background Bash makes CC skip goal evaluation at every Stop. The watcher cannot read the
# goal (no transcript path, and a multi-MB grep inside a SIGTERM handler is not an option), and the
# state can change between this WRITE and the boundary that READS it — so the line must be correct
# under BOTH states rather than pick one.

@test "E1: the WAKE-PATH-DOWN line names the LIVE-/goal branch and tells it NOT to re-arm" {
  "$AWAIT" "$UUID" --interval 1 --timeout 30 >/dev/null 2>&1 & local watcher=$!
  sleep 2
  [ -f "$CC_MAILBOX_DIR/$UUID.watching" ]            # positive control: it WAS armed before the kill
  kill -TERM "$watcher" 2>/dev/null || true
  wait "$watcher" 2>/dev/null || true
  grep -q 'A /goal IS LIVE' "$MB"
  grep -q 'do NOT re-arm' "$MB"
  # ...and it says WHY, so the reader is not asked to take the refusal on faith
  grep -q 'skips /goal evaluation at every Stop' "$MB"
}

@test "E1: the no-goal branch still carries the exact re-arm command (the fix is not a deletion)" {
  # The failure mode of a goal-aware rewrite is over-correction: a session with NO goal that is told
  # nothing is deaf until someone types at it, which is the defect the notice existed to prevent.
  "$AWAIT" "$UUID" --interval 1 --timeout 30 >/dev/null 2>&1 & local watcher=$!
  sleep 2
  kill -TERM "$watcher" 2>/dev/null || true
  wait "$watcher" 2>/dev/null || true
  grep -q 'NO live /goal' "$MB"
  grep -qF 'cc-await-ping --timeout 14400 --interval 15' "$MB"
}

@test "E1: the notice is still ONE mailbox line (a line IS a message on this substrate)" {
  # Both branches in one message, not two: the box is line-oriented, so a second line would be
  # delivered as a second peer message — counted separately, cursor-advanced separately, and
  # attributable to nobody if it lost the `<ISO> [from]` prefix the drain parses.
  "$AWAIT" "$UUID" --interval 1 --timeout 30 >/dev/null 2>&1 & local watcher=$!
  sleep 2
  kill -TERM "$watcher" 2>/dev/null || true
  wait "$watcher" 2>/dev/null || true
  [ "$(grep -c '' "$MB")" -eq 1 ]
  [ "$(grep -c 'WAKE-PATH-DOWN' "$MB")" -eq 1 ]
}

# PINNED TO A SHA, NEVER A MOVING REF. `origin/main` was the pre-fix tree only until E1 landed on it
# (e8c2435aa); from that moment the staleness guard matched and this case reported
# `ok … # skip control is not pre-fix` on every run — green, and proving nothing. A stale control does
# not fail, it SKIPS, and bats renders a skip as `ok`; the guard is therefore a hard FAILURE now.
# tests/wake-floor.bats:164-170 documents the hazard.  f704bf8aa = e8c2435aa~1.
CC_AWAIT_PING_E1_PREFIX_SHA="${CC_AWAIT_PING_E1_PREFIX_SHA:-f704bf8aa}"
@test "E1 RED-PROOF: the pre-fix watcher (pinned sha) instructs RE-ARM with no /goal branch" {
  local old="$BATS_TEST_TMPDIR/pre"; mkdir -p "$old"
  git -C "$REPO" archive "$CC_AWAIT_PING_E1_PREFIX_SHA" bin/cc-await-ping | tar -x -C "$old" \
    || skip "pre-fix tree $CC_AWAIT_PING_E1_PREFIX_SHA unavailable"
  [ -f "$old/bin/cc-await-ping" ] || false
  ! grep -q 'A /goal IS LIVE' "$old/bin/cc-await-ping" || false
  "$old/bin/cc-await-ping" "$UUID" --interval 1 --timeout 30 >/dev/null 2>&1 & local watcher=$!
  sleep 2
  kill -TERM "$watcher" 2>/dev/null || true
  wait "$watcher" 2>/dev/null || true
  grep -q 'WAKE-PATH-DOWN' "$MB"                     # positive control: the control DID write a notice
  ! grep -q 'do NOT re-arm' "$MB" || false           # RED: its only instruction was the denied one
}

# ── F5: THE NOTICE MUST NAME THE CHECK, NOT ONLY THE DECISION (2026-08-22) ────────────────────────
# docs/research/handoff-high-value-capture-2026-08-19.md §5 F5 · backlog 3078f45dded4.
# E1 above made the line CORRECT UNDER BOTH STATES. It did not make the reader able to tell WHICH
# state it is in: the text said "check before you act" and named no check. Measured: this notice and
# mailbox-drain.sh's goal-aware arm landed in the SAME commit (e8c2435aa, 2026-08-17), and all six
# goal-hunt sessions the wave found START AFTER it, each having received the notice 4-12 times — so
# the read-time evaluation was already live for every one of them and they hunted anyway. Naming the
# check is NOT the remedy bin/cc-await-ping's own comment refuses (evaluating/branching HERE); it
# costs one interpolated string and blocks nothing in the SIGTERM handler.

@test "F5: the WAKE-PATH-DOWN line names a RUNNABLE check, not only the decision" {
  "$AWAIT" "$UUID" --interval 1 --timeout 30 >/dev/null 2>&1 & local watcher=$!
  sleep 2
  [ -f "$CC_MAILBOX_DIR/$UUID.watching" ]            # positive control: it WAS armed before the kill
  kill -TERM "$watcher" 2>/dev/null || true
  wait "$watcher" 2>/dev/null || true
  grep -qF 'WHICH REPAIR APPLIES DEPENDS ON YOUR /goal' "$MB"   # the decision — unchanged by this fix
  grep -qF 'goal_live_condition' "$MB"                          # …and now the predicate that answers it
  grep -qF 'hooks/lib/goal-state.sh' "$MB"                      # …with the file that defines it
}

@test "F5: the named check carries its FAIL DIRECTION (rc 1 is not a confident no)" {
  # goal_live_condition returns 1 for "no goal", for "met/failed", AND for "could not read"
  # (goal-state.sh header § FAIL DIRECTION). A reader who reads rc 1 as a confident "no goal" and
  # re-arms under a live goal re-creates the E1 defect from the other side, so the notice that hands
  # over the predicate must hand over its polarity in the same breath.
  "$AWAIT" "$UUID" --interval 1 --timeout 30 >/dev/null 2>&1 & local watcher=$!
  sleep 2
  kill -TERM "$watcher" 2>/dev/null || true
  wait "$watcher" 2>/dev/null || true
  grep -qF 'FAILS CLOSED' "$MB"
  grep -qF 'never a confident no' "$MB"
}

@test "F5: naming the check did not cost the zero-cost observable (the drain header IS the verdict)" {
  # The cheapest branch discriminator needs no command at all: the drain that delivers this line
  # evaluates goal-liveness at that same boundary, so the header the reader is already looking at is
  # the answer. A fix that shipped only the shell one-liner would leave the common case paying for it.
  "$AWAIT" "$UUID" --interval 1 --timeout 30 >/dev/null 2>&1 & local watcher=$!
  sleep 2
  kill -TERM "$watcher" 2>/dev/null || true
  wait "$watcher" 2>/dev/null || true
  grep -qF 'the header above it IS the verdict' "$MB"
  [ "$(grep -c '' "$MB")" -eq 1 ]                    # and it is STILL one line — a line IS a message
}

# PINNED TO A SHA, NEVER A MOVING REF — same hazard E1's guard above documents: once this fix lands on
# origin/main a moving ref would match the post-fix tree, the staleness guard would SKIP, and bats
# renders a skip as `ok`. 950328c8c is the trunk tip this fix was written against, i.e. F5-pre-fix.
CC_AWAIT_PING_F5_PREFIX_SHA="${CC_AWAIT_PING_F5_PREFIX_SHA:-950328c8c}"
@test "F5 RED-PROOF: the pre-fix notice (pinned sha) names the decision and NO check" {
  local old="$BATS_TEST_TMPDIR/pre-f5"; mkdir -p "$old"
  git -C "$REPO" archive "$CC_AWAIT_PING_F5_PREFIX_SHA" bin/cc-await-ping | tar -x -C "$old" \
    || skip "pre-fix tree $CC_AWAIT_PING_F5_PREFIX_SHA unavailable"
  [ -f "$old/bin/cc-await-ping" ] || false
  # HARD staleness guard, never a skip: if the pinned tree already names the check, the pin has
  # drifted onto a post-fix commit and this control is proving nothing.
  # KEYED ON A STRING THAT LIVES ONLY IN THE NOTICE, not on `goal_live_condition` — the pre-fix file
  # already contains that identifier, in the COMMENT at :636 explaining why the predicate is not
  # evaluated here. Guarding on it convicted the pinned tree of being post-fix and the RED-PROOF
  # failed on its own control (measured, first run of this case). The subject of this test is the
  # emitted LINE, so the guard must be keyed on the line, not on the file that prints it.
  ! grep -qF 'the header above it IS the verdict' "$old/bin/cc-await-ping" || false
  "$old/bin/cc-await-ping" "$UUID" --interval 1 --timeout 30 >/dev/null 2>&1 & local watcher=$!
  sleep 2
  kill -TERM "$watcher" 2>/dev/null || true
  wait "$watcher" 2>/dev/null || true
  grep -qF 'WAKE-PATH-DOWN' "$MB"                            # positive control: it DID write a notice
  grep -qF 'WHICH REPAIR APPLIES DEPENDS ON YOUR /goal' "$MB" # …and it DID name the decision
  ! grep -q 'goal_live_condition' "$MB" || false             # RED: the decision, and no check
}

# ══ THE SENDER RECORDER (backlog b38279c10c55) ═══════════════════════════════════════════════════
# A killed watcher used to say it was killed but never BY WHOM, because an exit code carries no
# sender. These cases pin the SA_SIGINFO side-car that reads si_pid.
#
# 🚨 THE TEST HAZARD, PAID FOR ONCE ALREADY. Exercising the 144 shape means `kill -TERM -<pgid>`,
# and under the harness a backgrounded task and everything it spawns share ONE process group led by
# the wrapper — so a group kill aimed at "the child" takes the runner with it. Recycle #53's probe
# did exactly that and the harness reported it as exit 144: the probe reproduced the very defect it
# was investigating, on itself. Defence, in two parts, both mandatory:
#   1. spawn_isolated() puts the victim in a NEW SESSION via os.setsid(), so its pgid is its own.
#   2. group_term() REFUSES to signal any group whose pgid is not provably different from ours.
# Never signal a group this process belongs to. Never weaken part 2 to make a case pass.
#
# WHICH MUTANT REDS WHICH CASE — published so a green suite cannot silently credit nothing.
# All eight were RUN, not reasoned about: 8/8 applied, 8/8 reddened at least one case, 0 green,
# 0 anchor drift, 0 non-verdicts, and every result matched the prediction written before the run.
#   N1 (drop the `_sigrecord_arm` call)                     → R1, R3, R4, R6, R8
#   N2 (flip the kill-switch default from 1 to 0)           → R1, R3, R4, R6, R8   [over-wide: PREDICTED]
#   N3 (drop the sender clause from the stderr verdict)     → R3
#   N4 (drop the sender arg passed to _wake_down_notice)    → R4
#   N5 (drop the recorder's parent-death poll)              → R8
#   N6 (make _sigrecord_arm ignore CC_AWAIT_PING_SIGRECORD) → R2
#   N7 (drop _sigrecord_disarm from the EXIT trap)          → R6
#   N8 (drop the honest "no sender was captured" fallback)  → R5
# R7 IS CREDITED BY NO MUTANT, and that is stated rather than hidden. Its subject is the
# `command -v python3` fail-open guard, whose branch is unreachable here: /usr/bin/python3 exists on
# this box, so PATH cannot be made python3-free without also removing the binaries the watcher needs.
# R7 pins the SPAWN-FAILS branch instead, which converges on the same state (no recorder armed), and
# stands as a regression guard rather than as proof. Do not read its green as coverage.

# Launch cc-await-ping in its OWN session, so its process group is its own and can be signalled
# without touching ours. Optional 3rd arg prefixes the WATCHER's PATH only (not this launcher's,
# which needs the real python3). Echoes the victim pid; returns 1 if it never appeared.
spawn_isolated() { # <uuid> <capfile> [watcher-PATH-prefix]
  local i pid
  python3 - "$AWAIT" "$1" "$2" "${3:-}" <<'PYSPAWN' &
import os, sys
exe, uuid, cap = sys.argv[1], sys.argv[2], sys.argv[3]
pathpfx = sys.argv[4] if len(sys.argv) > 4 else ""
os.setsid()
fd = os.open(cap, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o644)
os.dup2(fd, 2); os.dup2(fd, 1)
if pathpfx:
    os.environ["PATH"] = pathpfx + ":" + os.environ.get("PATH", "")
os.execv("/bin/bash", ["/bin/bash", exe, uuid, "--timeout", "60", "--interval", "2"])
PYSPAWN
  for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
    sleep 1
    # NOT pgrep, deliberately: pgrep excludes the caller's own ancestors, and this lookup runs from
    # inside the very process tree it is enumerating. Matching on argv keeps the victim visible.
    # shellcheck disable=SC2009
    pid="$(ps -axo pid=,command= | grep -F "cc-await-ping $1" | grep -vF grep | awk '{print $1}' | head -1)"
    if [ -n "$pid" ]; then printf '%s' "$pid"; return 0; fi
  done
  return 1
}

# ANTI-VACUITY: a case that never got a live watcher must FAIL, not quietly assert about nothing.
assert_victim() { # <pid>
  [ -n "${1:-}" ] || false
  kill -0 "$1" 2>/dev/null || false
}

# THE SAFETY GATE. Refuses unless the victim's pgid is provably not ours.
group_term() { # <victim pid>
  local vpg ourpg
  vpg="$(ps -o pgid= -p "$1" 2>/dev/null | tr -d ' ')"
  ourpg="$(ps -o pgid= -p $$ 2>/dev/null | tr -d ' ')"
  [ -n "$vpg" ] || return 1
  [ -n "$ourpg" ] || return 1
  [ "$vpg" != "$ourpg" ] || return 1
  kill -TERM -"$vpg" 2>/dev/null || true
  return 0
}

recorder_pid() { # <watcher pid> -> pid of its python side-car, empty if none
  ps -axo pid=,ppid=,command= | awk -v v="$1" '$2==v && /[Pp]ython/ {print $1; exit}'
}

@test "R1: a watcher arms an SA_SIGINFO recorder side-car by default" {
  local u="RECORD-R1-$$" cap="$BATS_TEST_TMPDIR/r1.out" v r
  v="$(spawn_isolated "$u" "$cap")" || false
  assert_victim "$v"
  r="$(recorder_pid "$v")"
  group_term "$v" || false
  [ -n "$r" ] || false
}

@test "R2: CC_AWAIT_PING_SIGRECORD=0 arms no recorder, and the watch is otherwise unchanged" {
  local u="RECORD-R2-$$" cap="$BATS_TEST_TMPDIR/r2.out" v r
  export CC_AWAIT_PING_SIGRECORD=0
  v="$(spawn_isolated "$u" "$cap")" || false
  assert_victim "$v"
  r="$(recorder_pid "$v")"
  group_term "$v" || false
  sleep 2
  [ -z "$r" ] || false
  # the kill-switch must cost nothing else: the verdict still lands
  run grep -cF 'verdict=killed' "$cap"
  [ "$output" = "1" ] || false
}

@test "R3: a GROUP TERM makes the stderr verdict name the sender's si_pid" {
  local u="RECORD-R3-$$" cap="$BATS_TEST_TMPDIR/r3.out" v n
  v="$(spawn_isolated "$u" "$cap")" || false
  assert_victim "$v"
  group_term "$v" || false
  sleep 3
  n="$(grep -cF 'SENDER IDENTIFIED' "$cap" 2>/dev/null)"
  [ "${n:-0}" -ge 1 ] || false
  run grep -oE 'si_pid=[0-9]+' "$cap"      # a real pid, not a literal
  [ "$status" -eq 0 ] || false
}

@test "R4: the WAKE-PATH-DOWN inbox line carries the sender too, not only stderr" {
  local u="RECORD-R4-$$" cap="$BATS_TEST_TMPDIR/r4.out" v n
  v="$(spawn_isolated "$u" "$cap")" || false
  assert_victim "$v"
  group_term "$v" || false
  sleep 3
  [ -f "$CC_MAILBOX_DIR/$u.md" ] || false
  n="$(grep -cF 'SENDER IDENTIFIED' "$CC_MAILBOX_DIR/$u.md" 2>/dev/null)"
  [ "${n:-0}" -ge 1 ] || false
}

@test "R5: a single-pid TERM never reaches the recorder, so the verdict says so honestly" {
  local u="RECORD-R5-$$" cap="$BATS_TEST_TMPDIR/r5.out" v
  v="$(spawn_isolated "$u" "$cap")" || false
  assert_victim "$v"
  kill -TERM "$v" 2>/dev/null || true  # THIS PROCESS ALONE — deliberately not the group
  sleep 3
  # `run`, not $(...): grep -c prints 0 and EXITS 1 on no-match, which under bats errexit aborts the
  # assignment and reds the case before it ever asserts. Only a case expecting ZERO matches can trip
  # that — which is exactly this one.
  run grep -cF 'SENDER IDENTIFIED' "$cap"
  [ "$output" = "0" ] || false         # no sender, because none was deliverable
  run grep -cF 'sender was not captured' "$cap"
  [ "$output" -ge 1 ] || false         # and it SAYS so, rather than staying silent
}

@test "R6: an ordinary wake reaps the recorder and leaves no capture file behind" {
  local u="RECORD-R6-$$" cap="$BATS_TEST_TMPDIR/r6.out" v r
  v="$(spawn_isolated "$u" "$cap")" || false
  assert_victim "$v"
  r="$(recorder_pid "$v")"
  [ -n "$r" ] || false                 # anti-vacuity: there must BE a recorder to reap
  printf '2026-08-19T10:00:00+0000 [peer] R6 wake body\n' >> "$CC_MAILBOX_DIR/$u.md"
  # Wait for the WATCHER to go, then check the recorder IMMEDIATELY. A fixed sleep would not
  # discriminate: an un-disarmed recorder self-exits on its own parent poll within ~5s, so a late
  # check reads clean either way and the disarm path would be credited for the poll's work.
  for _i in 1 2 3 4 5 6 7 8 9 10; do
    kill -0 "$v" 2>/dev/null || break
    sleep 1
  done
  run kill -0 "$v"
  [ "$status" -ne 0 ] || false         # anti-vacuity: the watcher really did exit
  run grep -cF 'R6 wake body' "$cap"   # and it exited because the ping was consumed
  [ "$output" = "1" ] || false
  # keyed on the recorder's OWN pid: an orphan is reparented to pid 1, so a ppid-based check here
  # would match nothing either way and pass vacuously.
  run kill -0 "$r"
  [ "$status" -ne 0 ] || false
  [ ! -f "${TMPDIR:-/tmp}/cc-await-ping-sender.$v" ] || false
}

@test "R8: a SIGKILLed watcher runs no trap, so the recorder must self-exit on parent death" {
  local u="RECORD-R8-$$" cap="$BATS_TEST_TMPDIR/r8.out" v r
  v="$(spawn_isolated "$u" "$cap")" || false
  assert_victim "$v"
  r="$(recorder_pid "$v")"
  [ -n "$r" ] || false
  kill -KILL "$v" 2>/dev/null || true  # no EXIT trap, no disarm — only the parent poll can save us
  sleep 8                              # the poll slices at 5s
  run kill -0 "$r"
  [ "$status" -ne 0 ] || false
  rm -f "${TMPDIR:-/tmp}/cc-await-ping-sender.$v" 2>/dev/null || true
}

@test "R7: a recorder that cannot arm FAILS OPEN — the watch runs and still verdicts" {
  # SCOPE, stated rather than implied: this exercises the SPAWN-FAILS branch, not the
  # `command -v python3` branch — see the mutant-map note at the head of this block.
  local u="RECORD-R7-$$" cap="$BATS_TEST_TMPDIR/r7.out" v r
  mkdir -p "$BATS_TEST_TMPDIR/stub"
  printf '#!/bin/sh\nexit 1\n' > "$BATS_TEST_TMPDIR/stub/python3"
  chmod +x "$BATS_TEST_TMPDIR/stub/python3"
  v="$(spawn_isolated "$u" "$cap" "$BATS_TEST_TMPDIR/stub")" || false
  assert_victim "$v"
  r="$(recorder_pid "$v")"
  [ -z "$r" ] || false                 # nothing armed
  group_term "$v" || false
  sleep 2
  run grep -cF 'verdict=killed' "$cap" # but the watcher itself was untouched
  [ "$output" = "1" ] || false
}

# ══ A SIGNAL AFTER THE TERM EXPIRED IS NOT A KILL (task #173, 2026-08-21) ═══════════════════════
#
# The whole _sig_verdict path had NO coverage in this file, which is how the defect below survived.
#
# THE DEFECT: the wait loop re-tests `elapsed < TIMEOUT` only once per --interval (15s in the
# recommended arm), and bash additionally defers a trap until the current foreground command
# returns. So there is a window of up to one interval in which the budget is spent but the loop has
# not yet said so. A signal landing there took the TERM path and emitted, verbatim, "it did NOT time
# out" — about a watcher whose own MEASURED elapsed had already reached its budget — and wrote a
# WAKE-PATH-DOWN anomaly into the inbox. The successor then reads that and goes hunting for an
# external killer that never existed.
#
# MEASURED over the 552 WAKE-PATH-DOWN lines in ~/.claude/mailbox (271 carry a parseable
# elapsed/budget pair): 19, i.e. 7%, report elapsed >= budget. Every one asserts something false
# about itself, and none of them needs a killer to explain.
#
# THE HANDLE IS THE .watching MARKER, not a pgrep: the watcher records its OWN pid there (see the
# heartbeat case above), so the killer below targets a pid the subject itself published. `pgrep -f`
# would match any process whose argv merely MENTIONS the name — including this suite's own bats
# runner — which is the instrument error that cost this session a false reading earlier today.

@test "#173 a SIGTERM arriving AFTER the budget expired reports the TIMEOUT it reached, not a kill" {
  # budget 1s, interval 60s: after the first check the loop sleeps far past its own deadline, so the
  # signal is guaranteed to land inside the window the defect lives in.
  # INTERVAL 5, NOT 60 — and the reason is the very mechanism under test. bash defers a trap until
  # the current foreground command returns, and that command is the poll `sleep`. With --interval 60
  # each case sat a full minute waiting for its OWN SIGTERM to be delivered: the two cases took 125s
  # together, blowing ship-land's 120s smoke budget by themselves and getting the whole suite cut.
  # 5s still exceeds the 1s budget, so the loop cannot re-test before the signal lands — which is the
  # only property this case needs from the interval.
  "$AWAIT" "$UUID" --interval 5 --timeout 1 >/dev/null 2>"$BATS_TEST_TMPDIR/err" & watcher=$!
  wf="$CC_MAILBOX_DIR/$UUID.watching"
  for _ in 1 2 3 4 5 6 7 8 9 10; do [ -f "$wf" ] && break; sleep 0.3; done
  [ -f "$wf" ] || { echo "watcher never published its .watching marker"; false; }
  sleep 2                                    # the 1s budget is now definitively spent
  kill -TERM "$watcher" 2>/dev/null || true
  # `set -e` is on in bats: a bare `wait` returning non-zero aborts the test BEFORE $? is read,
  # so the status must be captured on the failure branch or the case can only ever "fail" with the
  # very value it wanted to assert (memory: negated-assertion-dead-unless-final).
  status=0; wait "$watcher" 2>/dev/null || status=$?
  err="$(cat "$BATS_TEST_TMPDIR/err")"

  [ "$status" -eq 2 ] || { echo "expected the documented timeout status 2, got $status"; echo "$err"; false; }
  [[ "$err" == *"verdict=timeout"* ]] || { echo "did not report a timeout: $err"; false; }
  # the false sentence must be gone…
  [[ "$err" != *"did NOT time out"* ]] || { echo "still claims it did not time out: $err"; false; }
  # …and no anomaly may be filed into the inbox for a watch that simply ended
  [ ! -f "$CC_MAILBOX_DIR/$UUID.md" ] || \
    ! grep -q 'WAKE-PATH-DOWN' "$CC_MAILBOX_DIR/$UUID.md" || \
    { echo "filed a WAKE-PATH-DOWN anomaly for a completed term"; false; }
}

@test "#173 CONTROL — a SIGTERM WELL INSIDE the term is still a kill, loudly and on the record" {
  # The other half, and the one that stops the fix widening into "nothing is ever a kill": at 1s
  # elapsed against a 600s budget the term plainly has NOT expired, so the killed verdict, the
  # inbox anomaly and the 128+15 exit must all survive untouched.
  # Same interval reasoning as the case above: the trap cannot fire until the poll sleep returns.
  "$AWAIT" "$UUID" --interval 5 --timeout 600 >/dev/null 2>"$BATS_TEST_TMPDIR/err2" & watcher=$!
  wf="$CC_MAILBOX_DIR/$UUID.watching"
  for _ in 1 2 3 4 5 6 7 8 9 10; do [ -f "$wf" ] && break; sleep 0.3; done
  [ -f "$wf" ] || { echo "watcher never published its .watching marker"; false; }
  kill -TERM "$watcher" 2>/dev/null || true
  # `set -e` is on in bats: a bare `wait` returning non-zero aborts the test BEFORE $? is read,
  # so the status must be captured on the failure branch or the case can only ever "fail" with the
  # very value it wanted to assert (memory: negated-assertion-dead-unless-final).
  status=0; wait "$watcher" 2>/dev/null || status=$?
  err="$(cat "$BATS_TEST_TMPDIR/err2")"

  [ "$status" -eq 143 ] || { echo "expected 128+15=143 for a real kill, got $status"; echo "$err"; false; }
  [[ "$err" == *"verdict=killed"* ]]     || { echo "a real kill lost its verdict: $err"; false; }
  [[ "$err" == *"did NOT time out"* ]]   || { echo "a real kill must still say so: $err"; false; }
  grep -q 'WAKE-PATH-DOWN' "$CC_MAILBOX_DIR/$UUID.md" \
    || { echo "a real kill must still file the inbox anomaly"; false; }
}

# ── F12: a watcher must not read its own predecessor's corpse as the ping it awaits ───────────────
# backlog b1a9e3142ee4. `_wake_down_notice` writes the WAKE-PATH-DOWN verdict into the watched box BY
# DESIGN (that placement is correct and stays). The defect is on the READ side: the take loop decided
# "a ping arrived" on line-count alone, so the arm that REPLACES a killed watcher fired on the dead
# one's own notice and exited verdict=ping elapsed=0s — a wake path that was never established,
# indistinguishable from one that delivered real mail.
#
# The notice's exact prefix, as `_wake_down_notice` interpolates it. Keyed on the uuid it names, which
# is what separates OUR corpse from a sibling's forwarded report.
wake_down_line() { # <uuid-it-was-armed-for>
  printf '2026-08-22T21:26:58-0700 [cc-await-ping] WAKE-PATH-DOWN: the watcher armed for [%s] was TERMINATED from outside (SIGTERM; elapsed=9531s budget=14340s — the MEASURED slice of the term it actually held) — it did NOT time out and consumed no ping. WHICH REPAIR APPLIES DEPENDS ON YOUR /goal, so check before you act.\n' "$1"
}

@test "F12: an arm meeting its OWN undrained WAKE-PATH-DOWN keeps WATCHING, not verdict=ping" {
  wake_down_line "$UUID" > "$MB"        # pending: .seen is absent ⇒ cursor 0, so the window holds it
  run "$AWAIT" "$UUID" --interval 1 --timeout 3

  # VACUITY CONTROL, and the reason this case can fail for the right reason only. The no-lib path
  # (`from line N`) computes its baseline at ARM time, so a pre-existing line would never fire there
  # and this test would pass against a subject that has no fix in it at all. Pin that we are on the
  # keyset/private-cursor path, which is the one that fires on already-pending mail (F6a).
  [[ "$output" == *"private cursor, seeded from .seen"* ]] \
    || { echo "not on the lib path — this case would be vacuous: $output"; false; }

  [ "$status" -eq 2 ] || { echo "expected the watch to run its term (exit 2), got $status"; echo "$output"; false; }
  [[ "$output" == *"verdict=timeout"* ]] || { echo "expected verdict=timeout: $output"; false; }
  [[ "$output" != *"verdict=ping"* ]] \
    || { echo "fired on its own corpse-notice — the wake path was never established: $output"; false; }
  [[ "$output" == *"skipped 1 WAKE-PATH-DOWN control line(s) of our own"* ]] \
    || { echo "the skip must be stated, or a live watch is indistinguishable from a swallowed ping: $output"; false; }

  # The notice is NOT consumed: it stays pending so the boundary drain still surfaces it as peer mail.
  [ ! -f "$CC_MAILBOX_DIR/$UUID.seen" ] || [ "$(cat "$CC_MAILBOX_DIR/$UUID.seen")" -eq 0 ] \
    || { echo "advanced .seen past a notice it never delivered"; false; }
}

@test "F12 CONTROL — a FORWARDED WAKE-PATH-DOWN naming ANOTHER pane is real mail and still fires" {
  # The too-strong direction, and the reason the discriminator is keyed on our own keyset rather than
  # on the marker text: a sibling telling us ITS wake path dropped is ordinary peer mail.
  wake_down_line "CCCCCCCC-9999-8888-7777-666666666666" > "$MB"
  run "$AWAIT" "$UUID" --interval 1 --timeout 5
  [ "$status" -eq 0 ] || { echo "suppressed a peer's report as if it were our own: $status / $output"; false; }
  [[ "$output" == *"verdict=ping"* ]] || { echo "expected a delivery: $output"; false; }
  [[ "$output" == *"CCCCCCCC-9999-8888-7777-666666666666"* ]] || { echo "body not delivered: $output"; false; }
}

@test "F12 CONTROL — our own notice ALONGSIDE real mail still delivers both" {
  # The other too-strong direction: the skip is a property of the WINDOW, not of the line. One real
  # line anywhere in it makes the whole window a delivery.
  wake_down_line "$UUID" > "$MB"
  printf '2026-08-22T21:30:00-0700 [peer] HANDOFF-PING recycle #162: real mail\n' >> "$MB"
  run "$AWAIT" "$UUID" --interval 1 --timeout 5
  [ "$status" -eq 0 ] || { echo "a window containing real mail must fire: $status / $output"; false; }
  [[ "$output" == *"HANDOFF-PING recycle #162: real mail"* ]] || { echo "lost the real line: $output"; false; }
}

@test "F12 RED-PROOF — the same fixture against the PINNED PRE-FIX subject exits verdict=ping" {
  # Arm 2. Without this the case above is an assertion nobody has watched fail: it must be shown to
  # DISCRIMINATE the fix, not merely to pass beside it. The pre-fix copy is planted at <root>/bin/ with
  # <root>/hooks symlinked to the repo's, because the script resolves its mailbox lib as
  # "$_bd/../hooks/lib/mailbox-pending.sh" and would otherwise silently fall back to the LIVE
  # ~/.claude copy — a different subject than the one under test.
  #
  # A LITERAL SHA, never a moving ref (moving-ref-control-lint, which caught this land). `origin/main`
  # advances past this fix the moment it lands, and the control then replays the FIXED file and
  # compares the fix to itself. 0fe052972 is the parent of the fix commit — the last sha at which this
  # defect is present — and it is already an ancestor of trunk, so it cannot move.
  local root="$BATS_TEST_TMPDIR/prefix"
  mkdir -p "$root/bin"
  git -C "$REPO" show 0fe052972:bin/cc-await-ping > "$root/bin/cc-await-ping" \
    || skip "pinned pre-fix copy unavailable"
  chmod +x "$root/bin/cc-await-ping"
  ln -s "$REPO/hooks" "$root/hooks"

  # The pinned copy must be the PRE-FIX one, or this proves nothing (control-must-replay-the-real-artifact).
  ! grep -q '_real_mail_after' "$root/bin/cc-await-ping" \
    || { echo "the pinned copy already carries the fix — this arm cannot red"; false; }

  wake_down_line "$UUID" > "$MB"
  run "$root/bin/cc-await-ping" "$UUID" --interval 1 --timeout 3
  [[ "$output" == *"private cursor, seeded from .seen"* ]] \
    || { echo "arm 2 not on the lib path — the red would be for the wrong reason: $output"; false; }
  [ "$status" -eq 0 ] || { echo "expected the pre-fix subject to fire on its own corpse: $status"; echo "$output"; false; }
  [[ "$output" == *"verdict=ping"* ]] \
    || { echo "expected pre-fix verdict=ping — the defect did not reproduce: $output"; false; }
}

# ══ (B) vs (C): DOES ANYTHING RE-ARM? (2026-08-24) ═══════════════════════════════════════════════
# backlog 95fcadde830e (C, the dangerous class) · 0e0da162f77c (B, the benign one).
# "Your watcher died" is two events. (B) is the arming session's own RECYCLE EXIT — a successor is
# coming up and will re-arm, so nothing is wrong. (C) is a sender that is STILL ALIVE and still
# taking turns — nothing re-arms, and the session is DEAF from that moment while every counter reads
# healthy. The notice used to classify both identically.
#
# THE THREE REFUTED DISCRIMINATORS ARE NOT RE-TESTED HERE BECAUSE THEY ARE NOT IN THE SUBJECT:
# registry identity (cc-registry is single-slot per pane — BOTH truth-table cells matched), "did the
# sender beat after the kill" (a cc-beats file is one row per session, so the answer is structurally
# 0 for everyone), and the beat `kind` field (n=1021: 1,010 dead sessions and 11 live ones all read
# kind=prompt). What survives is BEAT FRESHNESS across TWO READS SEPARATED IN TIME, which is why
# every case below drives CC_AWAIT_CLASS_DELAY_S and moves state INSIDE that window.
#
# WHICH MUTANT REDS WHICH CASE — one per site, each applied alone and the subject restored
# byte-identically (sha-compared) between applications:
#   M1 (drop the beat-advance arm)                       → W1
#   M2 (drop the sender-process-survived arm)            → W2
#   M3 (make the survived arm's condition unconditional) → W3
#   M4 (drop the `sid` empty guard, i.e. UNDETERMINED)   → W4
#   M5 (drop the pending-classification clause)          → W5
#   M6 (classify INLINE instead of in the detached child)→ W6
#   M7 (drop WAKE-PATH-CLASS from _own_wake_down_line)   → W7
#   M8 (ignore CC_AWAIT_CLASSIFY)                        → W8

# THE CONTROLLED SENDER. si_pid is the pid of whatever ran `kill`, so a case that must choose between
# "the sender exited" and "the sender is still running" has to OWN that process. This hands its pid
# back BEFORE it fires, which is what lets the pid→sid beat fixture be written first. It carries
# group_term()'s safety gate verbatim: it refuses to signal any group that is ours.
sender_go() { printf '%s/sender.go' "$BATS_TEST_TMPDIR"; }   # DERIVED, never a variable the spawn
# sets: sender_spawn runs inside a command substitution, so anything it assigns dies in that
# subshell — the caller would then fire on an empty path and every case would red on the helper
# rather than on the subject. BATS_TEST_TMPDIR is per-case, so this cannot collide across tests.

sender_spawn() { # <victim pid> <linger-seconds> → sender pid on stdout
  local v="$1" linger="$2" vpg ourpg go
  vpg="$(ps -o pgid= -p "$v" 2>/dev/null | tr -d ' ')"
  ourpg="$(ps -o pgid= -p $$ 2>/dev/null | tr -d ' ')"
  [ -n "$vpg" ] || return 1
  [ -n "$ourpg" ] || return 1
  [ "$vpg" != "$ourpg" ] || return 1
  go="$(sender_go)"
  rm -f "$go"
  # >/dev/null 2>&1 </dev/null IS LOAD-BEARING, not tidiness. This helper is called inside a command
  # substitution, and a background child INHERITS that substitution's stdout pipe — so `$(…)` blocks
  # until the child exits, while the child is itself blocked waiting for a go-file the caller can
  # only write AFTER the substitution returns. Measured: a clean deadlock that hangs the whole suite
  # on its first case. Detaching the child's descriptors is what makes the pid readable at all.
  # THE WAIT IS BOUNDED, and that is not defensive dressing — MEASURED: 9 of these were found spinning
  # after a run was killed mid-case, each waiting forever on a go-file in a BATS_TEST_TMPDIR that had
  # already been removed. An unbounded wait makes every interrupted run leak a process that nothing
  # will ever release. 600 iterations at 0.1s is ~60s, far longer than any case here needs to fire,
  # and it exits WITHOUT signalling — a helper that timed out must never fire a stale group kill at a
  # pgid the OS may since have reassigned.
  bash -c 'i=0
           while [ ! -f "$3" ]; do
             i=$((i + 1)); [ "$i" -gt 600 ] && exit 3
             sleep 0.1
           done
           kill -TERM -"$1" 2>/dev/null || true
           [ "$2" -gt 0 ] && sleep "$2"
           exit 0' _ "$vpg" "$linger" "$go" >/dev/null 2>&1 </dev/null &
  printf '%s' "$!"
}
sender_fire() { : > "$(sender_go)"; }

# `jq -n` WITHOUT `-c`, exactly like hooks/session-beat.sh: the real store is PRETTY-PRINTED, so a
# fixture written compact would let a `grep '"pid":<n>'` implementation pass a test the live store
# would fail. The fixture has to be able to catch that.
beat_for_pid() { # <sid> <pid> <seq> [age-seconds]
  jq -n --arg s "$1" --argjson p "$2" --argjson q "$3" \
        --argjson t "$(( $(date +%s) - ${4:-0} ))" \
    '{sid:$s,pane:"pW",cwd:"/tmp",pid:$p,lstart:"x",t:$t,kind:"prompt",who:"auto",operatorT:null,seq:$q}' \
    > "$CC_BEAT_DIR/$1.json"
}

# ANCHORED AT LINE START, never a bare substring. The corpse notice ANNOUNCES the follow-up ("a
# WAKE-PATH-CLASS line lands in this box in ~Ns"), so a substring match fires on the announcement
# itself: measured, and it made every wait return instantly and every "no class line yet" assertion
# vacuously true. A line IS a message on this substrate, so the marker only counts where a message
# starts. class_lines is the ONE reader; nothing below greps for the token by hand.
class_lines() { # <box> → how many real WAKE-PATH-CLASS messages the box holds
  grep -cE '^[^ ]+ \[cc-await-ping\] WAKE-PATH-CLASS:' "$1" 2>/dev/null || true
}
class_body() { # <box> → the class message(s) only, never the corpse notice that names them
  grep -E '^[^ ]+ \[cc-await-ping\] WAKE-PATH-CLASS:' "$1" 2>/dev/null || true
}
await_class() { # <box> → 0 once a real class message exists; 1 after ~25s
  local i
  for i in $(seq 1 25); do
    [ "$(class_lines "$1")" -gt 0 ] 2>/dev/null && return 0
    sleep 1
  done
  return 1
}
# The sender is spawned inside a command substitution, so it is a child of THAT subshell and this
# shell can never `wait` for it — a bare `wait` returns instantly and an immediate `kill -0` then
# reads the still-exiting process as alive. Poll for the death instead of asserting it.
await_gone() { # <pid> → 0 once the pid is gone; 1 after ~15s
  local i
  for i in $(seq 1 15); do
    kill -0 "$1" 2>/dev/null || return 0
    sleep 1
  done
  return 1
}

@test "W1: a sender that TOOK A TURN after the kill is (C) DEAF, on the beat advance" {
  local u="CLASS-W1-$$" cap="$BATS_TEST_TMPDIR/w1.out" v s box="$CC_MAILBOX_DIR/CLASS-W1-$$.md"
  export CC_AWAIT_CLASS_DELAY_S=5
  v="$(spawn_isolated "$u" "$cap")" || false
  assert_victim "$v"
  # ALIVE across the whole window on purpose: both (C) arms are then true, and asserting the REASON
  # is what attributes the verdict to the beat advance rather than to mere process survival.
  s="$(sender_spawn "$v" 12)" || false
  beat_for_pid "sidW1" "$s" 7
  sender_fire
  sleep 2
  beat_for_pid "sidW1" "$s" 8            # …a turn taken AFTER it killed the watcher
  await_class "$box" || { echo "no class line landed"; cat "$cap"; false; }
  class_body "$box" | grep -qF 'verdict=C-DEAF reason=sender-beat-advanced-after-the-kill' \
    || { echo "wrong verdict:"; class_body "$box"; false; }
  class_body "$box" | grep -qF 'seq 7→8' || false     # the evidence, not just the label
  kill "$s" 2>/dev/null || true
}

@test "W2: a sender STILL RUNNING after the kill is (C) DEAF even with a frozen beat" {
  local u="CLASS-W2-$$" cap="$BATS_TEST_TMPDIR/w2.out" v s box="$CC_MAILBOX_DIR/CLASS-W2-$$.md"
  export CC_AWAIT_CLASS_DELAY_S=5
  v="$(spawn_isolated "$u" "$cap")" || false
  assert_victim "$v"
  s="$(sender_spawn "$v" 12)" || false
  beat_for_pid "sidW2" "$s" 3            # frozen for the whole window — the beat says nothing
  sender_fire
  await_class "$box" || { echo "no class line landed"; cat "$cap"; false; }
  class_body "$box" | grep -qF 'verdict=C-DEAF reason=sender-process-survived-its-own-kill' \
    || { echo "wrong verdict:"; class_body "$box"; false; }
  class_body "$box" | grep -qF 'Re-arm before you go idle' || false   # a dangerous verdict acts
  kill "$s" 2>/dev/null || true
}

@test "W3: a sender that EXITED with a frozen beat is (B) BENIGN — and demands no act" {
  local u="CLASS-W3-$$" cap="$BATS_TEST_TMPDIR/w3.out" v s box="$CC_MAILBOX_DIR/CLASS-W3-$$.md"
  export CC_AWAIT_CLASS_DELAY_S=5
  v="$(spawn_isolated "$u" "$cap")" || false
  assert_victim "$v"
  s="$(sender_spawn "$v" 0)" || false     # fires and exits: the recycle-teardown shape
  beat_for_pid "sidW3" "$s" 3
  sender_fire
  await_gone "$s" || { echo "anti-vacuity: the sender never exited, so this is not the B case"; false; }
  await_class "$box" || { echo "no class line landed"; cat "$cap"; false; }
  class_body "$box" | grep -qF 'verdict=B-BENIGN reason=sender-session-exited-beat-frozen' \
    || { echo "wrong verdict:"; class_body "$box"; false; }
  # THE POINT OF THE WHOLE ROW: the one branch where "nothing is wrong" is earned is also the one
  # branch that must not tell a session to act. An alarm that fires identically on both classes says
  # as little as one that never fires.
  ! class_body "$box" | grep -qF 'Re-arm before you go idle' || false
}

@test "W4: a sender that binds to NO session beat is UNDETERMINED, and fails toward DEAF" {
  local u="CLASS-W4-$$" cap="$BATS_TEST_TMPDIR/w4.out" v s box="$CC_MAILBOX_DIR/CLASS-W4-$$.md"
  export CC_AWAIT_CLASS_DELAY_S=5
  v="$(spawn_isolated "$u" "$cap")" || false
  assert_victim "$v"
  s="$(sender_spawn "$v" 0)" || false
  # A NON-EMPTY store that does NOT hold this sender. An empty CC_BEAT_DIR would make the scan skip
  # without ever running, and the case would pass over an unexercised lookup.
  beat_for_pid "sidW4other" 1 3
  sender_fire
  await_class "$box" || { echo "no class line landed"; cat "$cap"; false; }
  class_body "$box" | grep -qF 'verdict=UNDETERMINED reason=sender-binds-to-no-session-beat' \
    || { echo "wrong verdict:"; class_body "$box"; false; }
  class_body "$box" | grep -qF 'ASSUME YOU ARE DEAF' || false
  kill "$s" 2>/dev/null || true
}

@test "W5: the WAKE-PATH-DOWN line announces the pending verdict and names the safe assumption" {
  local u="CLASS-W5-$$" cap="$BATS_TEST_TMPDIR/w5.out" v s box="$CC_MAILBOX_DIR/CLASS-W5-$$.md"
  export CC_AWAIT_CLASS_DELAY_S=20          # long: the corpse line must say this WITHOUT the verdict
  v="$(spawn_isolated "$u" "$cap")" || false
  assert_victim "$v"
  s="$(sender_spawn "$v" 0)" || false
  beat_for_pid "sidW5" "$s" 3
  sender_fire
  sleep 3
  grep -qF 'WHETHER THIS IS BENIGN IS BEING SAMPLED RIGHT NOW' "$box" || false
  grep -qF 'UNTIL THAT LINE ARRIVES, ASSUME (C)' "$box" || false
  [ "$(class_lines "$box")" = "0" ] || false   # …and it says it WITHOUT the verdict it is promising
  kill "$s" 2>/dev/null || true
}

@test "W5 CONTROL: a single-pid TERM captures no sender, and the line says THAT, not a false reason" {
  # R5's shape: a 143 never reaches the SA_SIGINFO recorder. The advice is the same (assume deaf) but
  # the REASON differs, and a line that blamed a missing si_pid for an operator's kill-switch — or
  # vice versa — is what sends the next reader hunting a recorder failure that never happened.
  local u="CLASS-W5C-$$" cap="$BATS_TEST_TMPDIR/w5c.out" v box="$CC_MAILBOX_DIR/CLASS-W5C-$$.md"
  v="$(spawn_isolated "$u" "$cap")" || false
  assert_victim "$v"
  kill -TERM "$v" 2>/dev/null || true       # THIS PROCESS ALONE — deliberately not the group
  sleep 3
  grep -qF 'NO (B)-vs-(C) CLASSIFICATION IS POSSIBLE FOR THIS KILL' "$box" || false
  grep -qF 'no si_pid was captured' "$box" || false
  [ "$(class_lines "$box")" = "0" ] || false   # nothing to sample ⇒ no follow-up promised or written
}

@test "W6: the handler does NOT block for the sampling window" {
  # The second read is the whole design, and it is also why the sampling cannot happen in the signal
  # handler: the disarm and the corpse notice are the safety-critical half and a killer may follow
  # with SIGKILL. The watcher must therefore be GONE while the window is still open.
  local u="CLASS-W6-$$" cap="$BATS_TEST_TMPDIR/w6.out" v s i box="$CC_MAILBOX_DIR/CLASS-W6-$$.md"
  export CC_AWAIT_CLASS_DELAY_S=20
  v="$(spawn_isolated "$u" "$cap")" || false
  assert_victim "$v"
  s="$(sender_spawn "$v" 0)" || false
  beat_for_pid "sidW6" "$s" 3
  sender_fire
  for i in 1 2 3 4 5 6 7 8; do kill -0 "$v" 2>/dev/null || break; sleep 1; done
  run kill -0 "$v"
  [ "$status" -ne 0 ] || { echo "the watcher was still alive inside the sampling window"; false; }
  grep -qF 'WAKE-PATH-DOWN' "$box" || false     # the guaranteed half landed…
  [ "$(class_lines "$box")" = "0" ] || false    # …while the sampled half is still, correctly, pending
  kill "$s" 2>/dev/null || true
}

@test "W7: a re-arm does NOT read its own WAKE-PATH-CLASS line as the ping it awaits (F12)" {
  # The classifier appends tens of seconds after the corpse notice — squarely inside the window where
  # the REPLACEMENT watcher is already armed. Left out of the F12 suppressor this is the identical
  # defect with a different marker: verdict=ping, exit 0, over a wake path never established.
  printf '2026-08-24T10:00:00+0000 [cc-await-ping] WAKE-PATH-CLASS: verdict=C-DEAF reason=sender-process-survived-its-own-kill — follow-up to the WAKE-PATH-DOWN line above: the watcher armed for [%s] was killed by pid 123, and TWO reads say so.\n' "$UUID" > "$MB"
  run "$AWAIT" "$UUID" --interval 1 --timeout 4
  [ "$status" -eq 2 ] || { echo "expected timeout (kept watching), got $status: $output"; false; }
  [[ "$output" == *"control line(s) of our own"* ]] || false
}

@test "W7 CONTROL: a FORWARDED WAKE-PATH-CLASS naming ANOTHER pane is real mail and still fires" {
  # The suppressor is keyed on OUR OWN keyset, never on the marker text. A sibling telling us its
  # wake path dropped is peer mail; a blanket marker skip would swallow it.
  printf '2026-08-24T10:00:00+0000 [cc-await-ping] WAKE-PATH-CLASS: verdict=C-DEAF reason=sender-process-survived-its-own-kill — follow-up to the WAKE-PATH-DOWN line above: the watcher armed for [SOMEONE-ELSE-9999] was killed by pid 123.\n' > "$MB"
  run "$AWAIT" "$UUID" --interval 1 --timeout 4
  [ "$status" -eq 0 ] || { echo "expected a fire on a forwarded report, got $status: $output"; false; }
  [[ "$output" == *"SOMEONE-ELSE-9999"* ]] || false
}

@test "W8 CONTROL: CC_AWAIT_CLASSIFY=0 samples nothing, and says so without inventing a reason" {
  local u="CLASS-W8-$$" cap="$BATS_TEST_TMPDIR/w8.out" v s box="$CC_MAILBOX_DIR/CLASS-W8-$$.md"
  export CC_AWAIT_CLASSIFY=0
  export CC_AWAIT_CLASS_DELAY_S=3
  v="$(spawn_isolated "$u" "$cap")" || false
  assert_victim "$v"
  s="$(sender_spawn "$v" 0)" || false
  beat_for_pid "sidW8" "$s" 3
  sender_fire
  sleep 8
  [ "$(class_lines "$box")" = "0" ] || false
  grep -qF 'NO (B)-vs-(C) CLASSIFICATION WILL FOLLOW' "$box" || false
  grep -qF 'CC_AWAIT_CLASSIFY=0' "$box" || false
  grep -qF 'ASSUME THE DANGEROUS READING' "$box" || false
  kill "$s" 2>/dev/null || true
}
