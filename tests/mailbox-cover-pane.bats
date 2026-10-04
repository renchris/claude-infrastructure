#!/usr/bin/env bats
# mailbox-cover-pane.bats — the COVERAGE FOLD: a session reads its own PANE box at EVERY boundary,
# not only at SessionStart.
#
# THE DEFECT. Every sender resolves a target to a PANE key (role file, registry row, raw uuid) and
# none calls mailbox_resolve_key, so mail lands in <pane>.md. hooks/mailbox-drain.sh reads
# <session>.md. The reconciling migrate lived inside the `MODE = session-start` branch, so a session
# picked its pane box up ONCE, at birth, and never again — a line delivered to a live session was
# invisible for that session's whole life. Measured 2026-08-09: 14,763 unacked lines, 99.4% under a
# pane key. Finding 3, docs/plans/CROSS_SESSION_COMMS_V2.md §10.
#
# HERMETIC: $HOME is fixtured (scripts/test-hermeticity-lint.sh enforces this at the land gate).
#
# BATS ERREXIT DISCIPLINE (memory bats-dead-assertions-errexit-exemptions): a non-final `[[ ]]`,
# `(( ))`, `!` or `A && B` is errexit-EXEMPT and therefore a DEAD assertion. Every such assertion
# here carries `|| false`. `[ ]` as the final command in a body is live and needs no suffix.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  DRAIN="$REPO/hooks/mailbox-drain.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/bin"
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mbox"
  mkdir -p "$CC_MAILBOX_DIR"
  # The kitty-start seal reads $KITTY_PID, inherited from the operator's kitty on a pane run. Pinned
  # off: the kitty is UNKNOWN unless a SEAL test sets it.
  unset KITTY_PID KITTY_LISTEN_ON KITTY_WINDOW_ID

  PANE="AAAAAAAA-1111-2222-3333-444444444444"
  SESS="11111111-aaaa-bbbb-cccc-000000000001"
  export ITERM_SESSION_ID="w0t0p0:$PANE"
  PANE_BOX="$CC_MAILBOX_DIR/$PANE.md"
  SESS_BOX="$CC_MAILBOX_DIR/$SESS.md"

  # The alias trail the drain maintains on every boundary. Seeded directly so each test starts from
  # the steady state of a session that has already taken at least one boundary — which is exactly the
  # live case the defect strands (a session mid-life, not one being born).
  mkdir -p "$CC_MAILBOX_DIR/.alias"
  printf '2026-08-09T00:00:00-0700 %s\n' "$SESS" > "$CC_MAILBOX_DIR/.alias/$PANE"
}

# Run the drain at a boundary, with the harness stdin payload that carries the durable session id.
drain() { # <mode>
  printf '{"session_id":"%s"}' "$SESS" | "$DRAIN" "$1" 2>/dev/null
}

pane_mail() { printf '2026-08-09T10:00:00-0700 [peer] %s\n' "$1" >> "$PANE_BOX"; }
sess_mail() { printf '2026-08-09T10:00:00-0700 [peer] %s\n' "$1" >> "$SESS_BOX"; }

# ── THE HEADLINE ─────────────────────────────────────────────────────────────────────────────────

@test "COVER: pane-keyed mail is delivered at a PROMPT boundary, not only at SessionStart" {
  pane_mail "a seam ruling you asked for"
  run drain prompt
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'a seam ruling you asked for' || false
}

@test "COVER: pane-keyed mail is delivered at a POST-TOOL boundary (the cheap pre-gate must span both keys)" {
  # The pre-gate `mailbox_has_pending "$own_uuid" || exit 0` asks about the SESSION box only. With
  # mail in the pane box it returned false and the hook exited BEFORE the fold could run — the cheap
  # path became a cheap DROP. This is a distinct code path from the prompt boundary above, not a
  # restatement of it: the prompt boundary has no pre-gate.
  pane_mail "post-tool reachable"
  run drain post-tool
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'post-tool reachable' || false
}

# ── POSITIVE CONTROL — a null above must mean "not delivered", never "the assertion cannot see" ───

@test "CONTROL: session-keyed mail is delivered at a prompt boundary (the assertion can see a delivery)" {
  sess_mail "already correctly addressed"
  run drain prompt
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'already correctly addressed' || false
}

@test "CONTROL: an EMPTY inbox delivers no body (the assertion can also see a non-delivery)" {
  # Without this, every negative assertion below is vacuous: a grep that never matches would pass
  # whether the fold was broken or the harness simply emits nothing readable.
  run drain prompt
  [ "$status" -eq 0 ]
  # the wake-nudge path may still emit JSON; what must NOT appear is a delivered body block
  [ "$(printf '%s' "$output" | grep -c 'peer mail ◀')" = "0" ]
}

# ── THE KILL SWITCH ──────────────────────────────────────────────────────────────────────────────

@test "KILL SWITCH: CC_MBX_COVER_PANE=0 restores SessionStart-only behaviour verbatim" {
  pane_mail "should stay stranded under the switch"
  CC_MBX_COVER_PANE=0 run drain prompt
  [ "$status" -eq 0 ]
  # …and the line is still on disk, unconsumed — the switch strands it, it does not destroy it
  grep -q 'should stay stranded under the switch' "$PANE_BOX" || false
  [ "$(printf '%s' "$output" | grep -c 'should stay stranded under the switch')" = "0" ]
}

@test "KILL SWITCH: with the switch OFF, SessionStart still folds the pane box (degrades to today, not to nothing)" {
  pane_mail "session-start must still work"
  CC_MBX_COVER_PANE=0 run drain session-start
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'session-start must still work' || false
}

# ── SAFETY: the fold must not double-deliver, and must be bounded ────────────────────────────────

@test "IDEMPOTENT: a folded line is delivered EXACTLY once across two boundaries" {
  pane_mail "deliver me once"
  run drain prompt
  printf '%s' "$output" | grep -q 'deliver me once' || false
  # second boundary: the cursor advanced, so nothing new
  run drain prompt
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | grep -c 'deliver me once')" = "0" ]
}

@test "BOUNDED: no alias (pane == its own key) is a clean no-op, never an error" {
  rm -f "$CC_MAILBOX_DIR/.alias/$PANE"
  printf '2026-08-09T10:00:00-0700 [peer] unaliased\n' >> "$PANE_BOX"
  # no session_id on stdin ⇒ own_uuid degrades to the pane; the fold's `own_pane != own_uuid` guard
  # must short-circuit rather than migrate a box onto itself.
  run bash -c "printf '{}' | '$DRAIN' prompt 2>/dev/null"
  [ "$status" -eq 0 ]
  # the line is still readable exactly once, from the pane box the session is now keyed on
  [ "$(grep -c 'unaliased' "$PANE_BOX")" = "1" ]
}

@test "BOUNDED: the fold does no directory scan — an absent pane box costs nothing and exits clean" {
  rm -f "$PANE_BOX"
  run drain prompt
  [ "$status" -eq 0 ]
}

# ── KITTY SEAL (2026-10-04): pane-box mail from before this kitty started is not ours ─────────────
# The pane key is the kitty window id, renumbered on every kitty restart, so <pane>.md can hold mail
# addressed to whoever had this window number in an EARLIER kitty (incident aee462b0: two Sep 11
# lines folded into a session born Oct 4). The fold seals such lines instead of migrating them.
# "This kitty" is the test process ($$), which started moments ago; the real ps path runs.
# RED-proof: on the pre-fix drain the first test delivers both Sep 11 lines.
other_then_me() { # a predecessor held the window in an earlier kitty; I hold it now
  printf '2026-09-11T09:24:14-0500 %s\n%s %s\n' "99999999-aaaa-bbbb-cccc-000000000009" \
    "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$SESS" > "$CC_MAILBOX_DIR/.alias/$PANE"
}

@test "SEAL: pane lines from before this kitty are sealed, and fresh mail behind them still folds" {
  other_then_me
  printf '2026-09-11T10:35:38-0500 [cc-await-ping] old notice one\n2026-09-11T10:36:25-0500 [cc-await-ping] old notice two\n' > "$PANE_BOX"
  pane_now="$(date '+%Y-%m-%dT%H:%M:%S%z')"
  printf '%s [peer] fresh after birth\n' "$pane_now" >> "$PANE_BOX"
  KITTY_PID=$$ run drain prompt
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'fresh after birth' || { echo "fresh mail lost: $output"; false; }
  [ "$(printf '%s' "$output" | grep -c 'old notice')" = 0 ] || { echo "delivered pre-kitty mail: $output"; false; }
  # exactly-once: all 3 consumed (2 sealed + 1 migrated); nothing deleted; the seal is logged
  [ "$(cat "$CC_MAILBOX_DIR/$PANE.acked")" = 3 ]
  [ "$(grep -c '' "$PANE_BOX")" = 3 ]
  grep -q "sealed 2 line(s) 1..2 of $PANE" "$CC_MAILBOX_DIR/$PANE.sealed" || false
  [ "$(grep -c 'old notice' "$SESS_BOX")" = 0 ]
}

@test "SEAL CONTROL: the same box with the kitty UNKNOWN folds everything, as before" {
  other_then_me
  printf '2026-09-11T10:35:38-0500 [cc-await-ping] old notice one\n' > "$PANE_BOX"
  run drain prompt
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'old notice one' || false
  [ ! -f "$CC_MAILBOX_DIR/$PANE.sealed" ]
}

@test "SEAL never touches the session's OWN box: old session-keyed mail is still delivered" {
  other_then_me
  sess_mail "addressed to me by session id"          # stamped 2026-08-09, long before $$ started
  KITTY_PID=$$ run drain prompt
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'addressed to me by session id' || false
}

@test "SEAL keeps pane mail from MY OWN earlier occupancy (resumed into the same number after a kitty restart)" {
  # setup's trail: this session held the window since 2026-08-09, so a 2026-08-09 pane line was
  # addressed to it even though it predates this kitty.
  pane_mail "sent while I held this window before the restart"
  KITTY_PID=$$ run drain prompt
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'sent while I held this window before the restart' || false
  [ ! -f "$CC_MAILBOX_DIR/$PANE.sealed" ]
}
