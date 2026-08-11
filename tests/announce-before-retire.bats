#!/usr/bin/env bats
# F-1 — ANNOUNCE BEFORE RETIRE (2026-08-09).
#
# THE GAP. handoff-fire.sh's SELF-RETIRE trailer enforces DURABILITY (self-close refuses a dirty tree)
# and ORDERING (retire is step 2), but the announce was PROSE — "When your work is finished (and you
# have pinged back if asked to)". Two of the three steps were mechanical and the third was advice, so
# a peer that skipped its ping retired silently and left the originator waiting on an event that was
# never going to arrive. See docs/plans/TWO_WAY_SESSION_COMMS_PLAN.md § 2026-08-09.
#
# THE SHAPE UNDER TEST, and it is deliberately NOT a refusal. A dirty tree has a cure the closing pane
# fully controls; an announce does not — if the originator is gone or unresolvable, a gating peer could
# never satisfy it and would hold a pane and a worktree forever. So the mechanism DOES the announce and
# always proceeds. The tests below therefore pin BOTH halves: that it announces when it must, and that
# it never becomes a reason a pane cannot retire.
#
# Technique: sc_announce_before_retire is sed-extracted and driven directly (the same unit technique
# tests/handoff-selfclose.bats uses for its inventory checks). The self-close path ahead of it resolves
# pane identity, teammate liveness and origin class — none of which this decision reads.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"
  # HERMETIC. This suite drives cc-notify for real (the send-record case), and cc-notify resolves its
  # mailbox, registry and alarm dirs under $HOME by default — so an unfixtured run would write into
  # the operator's live store. Pinned before anything else reads it.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  # …and the seams that do NOT resolve under $HOME: an absolute /tmp default or a BARE NAME the
  # subject executes off the operator's PATH is untouched by fixturing $HOME (a514d3b0).
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/account-sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/claude-accounts-absent"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"
  # handoff-fire's capacity_gate refuses above 2.0/core and this box lives well above that, so an
  # unpinned suite would go red-by-load rather than by its subject.
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  PANE="DDDDDDDD-1111-2222-3333-444444444444"
  ORIG="EEEEEEEE-1111-2222-3333-444444444444"
  FIRED_DIR="$BATS_TEST_TMPDIR/cc-fired"; mkdir -p "$FIRED_DIR"
  MDIR="$BATS_TEST_TMPDIR/mbox";          mkdir -p "$MDIR"

  # Recording cc-notify stub — the auto-announce must be OBSERVABLE without touching the live store.
  export CC_NOTIFY_BIN="$BATS_TEST_TMPDIR/cc-notify-stub"
  cat > "$CC_NOTIFY_BIN" <<STUB
#!/bin/bash
printf '%s\n' "\$*" >> "$BATS_TEST_TMPDIR/notify.log"
exit 0
STUB
  chmod +x "$CC_NOTIFY_BIN"

  # Extract the function under test. It is self-contained (no globals) precisely so this works.
  sed -n '/^sc_announce_before_retire() {/,/^}/p' "$HF" > "$BATS_TEST_TMPDIR/fn.sh"
  [ -s "$BATS_TEST_TMPDIR/fn.sh" ]
  # shellcheck source=/dev/null
  . "$BATS_TEST_TMPDIR/fn.sh"
}

stamp_with_notifyback() {   # $1 = notifyBack value, or "null"
  if [ "$1" = "null" ]; then
    printf '{"paneUUID":"%s","schema":2,"originClass":"fired-peer","notifyBack":null}\n' "$PANE" \
      > "$FIRED_DIR/$PANE.json"
  else
    printf '{"paneUUID":"%s","schema":2,"originClass":"fired-peer","notifyBack":"%s"}\n' "$PANE" "$1" \
      > "$FIRED_DIR/$PANE.json"
  fi
}

@test "F-1: an armed back-channel with NO ping sent auto-announces to the originator" {
  stamp_with_notifyback "$ORIG"
  run sc_announce_before_retire "$PANE" "$FIRED_DIR" "$MDIR"
  [ "$status" -eq 0 ]                                   # never refuses the close
  grep -q "$ORIG" "$BATS_TEST_TMPDIR/notify.log"        # the originator WAS told
  grep -q 'unannounced retire' "$BATS_TEST_TMPDIR/notify.log"
}

@test "F-1: the auto-announce says the status is UNREPORTED, not that the peer reported it" {
  # The originator must be able to tell a real peer ping from the close path speaking on its behalf —
  # otherwise this mechanism manufactures a status report nobody wrote.
  stamp_with_notifyback "$ORIG"
  run sc_announce_before_retire "$PANE" "$FIRED_DIR" "$MDIR"
  grep -q 'UNREPORTED' "$BATS_TEST_TMPDIR/notify.log"
  grep -q 'auto' "$BATS_TEST_TMPDIR/notify.log"
}

@test "F-1 CONTROL: a peer that DID ping is not announced for (the guard is not always-on)" {
  stamp_with_notifyback "$ORIG"
  mkdir -p "$MDIR/.sent"
  printf '2026-08-09T00:56:08+0000 %s\n' "$ORIG" > "$MDIR/.sent/$PANE"
  run sc_announce_before_retire "$PANE" "$FIRED_DIR" "$MDIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"this pane pinged"* ]] || false
  [ ! -f "$BATS_TEST_TMPDIR/notify.log" ]               # nothing sent
}

@test "F-1 CONTROL: a send to a DIFFERENT target does not satisfy the armed back-channel" {
  # The record is per-target, not a bare "this pane sent something" bit — a peer that pinged the desk
  # about an unrelated matter has still not announced to its originator.
  stamp_with_notifyback "$ORIG"
  mkdir -p "$MDIR/.sent"
  printf '2026-08-09T00:50:00+0000 %s\n' "FFFFFFFF-9999-8888-7777-666666666666" > "$MDIR/.sent/$PANE"
  run sc_announce_before_retire "$PANE" "$FIRED_DIR" "$MDIR"
  grep -q "$ORIG" "$BATS_TEST_TMPDIR/notify.log"
}

@test "F-1 CONTROL: no armed back-channel ⇒ silent (an ordinary fire is not nagged)" {
  stamp_with_notifyback "null"
  run sc_announce_before_retire "$PANE" "$FIRED_DIR" "$MDIR"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -f "$BATS_TEST_TMPDIR/notify.log" ]
}

@test "F-1 CONTROL: no stamp at all (an ORIGIN session) ⇒ silent" {
  run sc_announce_before_retire "$PANE" "$FIRED_DIR" "$MDIR"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "F-1 FAIL-SAFE: an announce that FAILS still returns 0 — a pane that cannot ping must still retire" {
  # The load-bearing direction. An unretireable peer is a worse failure than an unannounced one, so a
  # broken/absent cc-notify must degrade to a loud warning, never to a refusal.
  stamp_with_notifyback "$ORIG"
  cat > "$CC_NOTIFY_BIN" <<'STUB'
#!/bin/bash
exit 1
STUB
  chmod +x "$CC_NOTIFY_BIN"
  run sc_announce_before_retire "$PANE" "$FIRED_DIR" "$MDIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"FAILED"* ]] || false
  [[ "$output" == *"retiring anyway"* ]] || false
}

@test "F-1 FAIL-SAFE: a cc-notify that does not exist at all is survivable" {
  stamp_with_notifyback "$ORIG"
  export CC_NOTIFY_BIN="$BATS_TEST_TMPDIR/definitely-not-here"
  run sc_announce_before_retire "$PANE" "$FIRED_DIR" "$MDIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"retiring anyway"* ]] || false
}

# ── the SEND RECORD this guard reads (bin/cc-notify) ─────────────────────────────────────────────
# Nothing recorded what a sender SENT — only what a target received — so no mechanism could answer
# "did this pane announce back?". The `[<from>]` tag on the delivered line cannot: it is a friendly
# NAME from the registry, not the sender's pane id.

@test "F-1: cc-notify records the send under the SENDER's own key, naming the target" {
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mbox2"; mkdir -p "$CC_MAILBOX_DIR"
  run env ITERM_SESSION_ID="w0t0p0:$PANE" CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg" \
    "$REPO/bin/cc-notify" --mailbox-only "$ORIG" "HANDOFF-PING test: done"
  [ -f "$CC_MAILBOX_DIR/$ORIG.md" ]                    # delivered, as before
  [ -f "$CC_MAILBOX_DIR/.sent/$PANE" ]                 # …and the SEND is now recorded
  grep -q "$ORIG" "$CC_MAILBOX_DIR/.sent/$PANE"
}

# ── LIVENESS_DETECTOR_FAILNEG (2026-08-11) — instances 1 and 4 ───────────────────────────────────
# The suite above has four tests labelled CONTROL and none of them could fail on the real defect,
# because every fixture uses ONE string ($ORIG) for both the armed address and the recorded target.
# In production those are two different spellings: the stamp carries the address as ARMED (a
# project-qualified session name, "claude-infrastructure-6") while cc-notify recorded only what that
# name RESOLVED to (the pane id, "6"). The fixture was vacuous on exactly the axis that fails.
#
# Taken from the operator's LIVE store, four days after the incident: cc-fired/11.json holds
# notifyBack="claude-infrastructure-6"; mailbox/.sent/11 holds two real delivered sends, both recorded
# as bare "6" — the two pings instance 1 says the pane sent and the detector denied.

@test "FAILNEG NEGATIVE CONTROL: the MEASURED instance — alias armed, send recorded under the resolved id — now reads PINGED" {
  stamp_with_notifyback "claude-infrastructure-6"
  mkdir -p "$MDIR/.sent"
  printf '2026-08-09T15:27:20-0700 6 claude-infrastructure-6\n2026-08-09T15:27:47-0700 6 claude-infrastructure-6\n' \
    > "$MDIR/.sent/$PANE"
  run sc_announce_before_retire "$PANE" "$FIRED_DIR" "$MDIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"this pane pinged"* ]] || false
  [ ! -f "$BATS_TEST_TMPDIR/notify.log" ]              # and it does NOT announce over a real ping
}

@test "FAILNEG POSITIVE CONTROL: a genuinely silent peer is STILL caught (the fix is not always-yes)" {
  # The mandatory other direction. This pane DID send — to someone else — in the NEW format, so the
  # negative is definite rather than merely unanswerable, and must still produce the UNREPORTED announce.
  stamp_with_notifyback "claude-infrastructure-6"
  mkdir -p "$MDIR/.sent"
  printf '2026-08-10T09:00:00-0700 99 claude-infrastructure-99\n' > "$MDIR/.sent/$PANE"
  run sc_announce_before_retire "$PANE" "$FIRED_DIR" "$MDIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"NO ping was ever sent"* ]] || false
  grep -q 'UNREPORTED' "$BATS_TEST_TMPDIR/notify.log"
}

@test "FAILNEG THIRD STATE: a LEGACY record (resolved id only) is UNKNOWN, never 'never pinged'" {
  # Every .sent file already on disk is in this format. Calling it "never pinged" would re-commit the
  # defect against the store's own history.
  stamp_with_notifyback "claude-infrastructure-6"
  mkdir -p "$MDIR/.sent"
  printf '2026-08-09T15:27:20-0700 6\n' > "$MDIR/.sent/$PANE"
  run sc_announce_before_retire "$PANE" "$FIRED_DIR" "$MDIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"predates the both-spellings format"* ]] || false
  [[ "$output" != *"NO ping was ever sent"* ]] || false
  grep -q 'UNVERIFIED' "$BATS_TEST_TMPDIR/notify.log"
  ! grep -q 'UNREPORTED' "$BATS_TEST_TMPDIR/notify.log"
}

@test "FAILNEG THIRD STATE: an UNREADABLE send record is UNKNOWN, never 'never pinged'" {
  stamp_with_notifyback "claude-infrastructure-6"
  mkdir -p "$MDIR/.sent"
  printf '2026-08-09T15:27:20-0700 6 claude-infrastructure-6\n' > "$MDIR/.sent/$PANE"
  chmod 000 "$MDIR/.sent/$PANE"
  if [ -r "$MDIR/.sent/$PANE" ]; then skip "running as a user that ignores mode 000"; fi
  run sc_announce_before_retire "$PANE" "$FIRED_DIR" "$MDIR"
  chmod 644 "$MDIR/.sent/$PANE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"could NOT BE READ"* ]] || false
  [[ "$output" != *"NO ping was ever sent"* ]] || false
}

@test "FAILNEG MUTATION: restoring the substring grep makes the legacy control assert the ORIGINAL bug" {
  # A control that cannot fail proves nothing. Rebuild the function with the PRE-FIX read (the
  # substring grep over the whole line) and replay the REAL pre-fix artifact — the legacy record. The
  # mutant must produce the exact false negative this item was filed about.
  a="$(grep -n '^      awk -v want=' "$BATS_TEST_TMPDIR/fn.sh" | cut -d: -f1)"
  [ -n "$a" ]
  b="$(awk -v s="$a" 'NR>s && /\$sent"$/ { print NR; exit }' "$BATS_TEST_TMPDIR/fn.sh")"
  [ -n "$b" ]
  { sed -n "1,$((a-1))p" "$BATS_TEST_TMPDIR/fn.sh"
    printf '      grep -qF "$nb" "$sent" 2>/dev/null\n'
    sed -n "$((b+1)),\$p" "$BATS_TEST_TMPDIR/fn.sh"
  } > "$BATS_TEST_TMPDIR/fn-mut.sh"
  # shellcheck source=/dev/null
  . "$BATS_TEST_TMPDIR/fn-mut.sh"                       # redefines sc_announce_before_retire

  stamp_with_notifyback "claude-infrastructure-6"
  mkdir -p "$MDIR/.sent"
  printf '2026-08-09T15:27:20-0700 6\n' > "$MDIR/.sent/$PANE"
  run sc_announce_before_retire "$PANE" "$FIRED_DIR" "$MDIR"
  [[ "$output" == *"NO ping was ever sent"* ]] || false  # ← the bug, reproduced on demand
  [[ "$output" != *"predates the both-spellings format"* ]] || false
}

@test "FAILNEG: cc-notify records BOTH spellings when they differ, and one when they do not" {
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mbox3"; mkdir -p "$CC_MAILBOX_DIR"
  # A bare uuid target resolves to itself ⇒ one token, no redundant duplicate.
  run env ITERM_SESSION_ID="w0t0p0:$PANE" CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg3" \
    "$REPO/bin/cc-notify" --mailbox-only "$ORIG" "HANDOFF-PING test: done"
  [ "$(awk 'NR==1{print NF}' "$CC_MAILBOX_DIR/.sent/$PANE")" = 2 ]
  grep -q "$ORIG" "$CC_MAILBOX_DIR/.sent/$PANE"
}

@test "F-1: the .sent record cannot be mistaken for an inbox (leading dot is refused as a box key)" {
  # `.sent/` sits beside the existing `.alias/` and `.watchers/` dirs. _mbx_valid_uuid refuses any key
  # beginning with `.`, which is what keeps this out of the box namespace BY CONSTRUCTION rather than
  # by nobody having globbed it yet.
  # shellcheck source=/dev/null
  . "$REPO/hooks/lib/mailbox-pending.sh"
  run mailbox_lines ".sent"
  [ "$output" = "0" ]
}
