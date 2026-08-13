#!/usr/bin/env bats
# M3 — NO CLOSE LOSES MAIL. Inherited seam: row 3 wrote the contract
# (docs/plans/CROSS_SESSION_COMMS_V2.md §4 M3), row 2 owns the call site (scripts/handoff-fire.sh).
# Coordinator ruling 2026-07-29. Row 2 implements; row 2 does NOT redesign the contract.
#
# THE DEFECT (row 3's F4, verbatim): "close path WARNED about undrained mail and closed anyway." The
# pre-close inventory counted unread messages and printed a warning, then proceeded — so a warn with
# no actuator behind it was the defect, not the fix. Live cost (F1, 2026-07-29): a lead died holding
# 2 unread messages — the coordinator's ACK and a seam ruling that session had explicitly ASKED for —
# and cc-notify had reported "delivered to inbox" for both. Delivered, read and acted-on are three
# different events.
#
# CONTRACT, ordered, quoted from §4 M3: "successor named → mailbox_migrate to it (mandatory, not
# advisory); no successor → append to a dead-letter store that is itself SURFACED on the operator
# board with existence evidence, never a silent file." Kill switch named by the contract:
# CC_CLOSE_MAIL_GUARD=0.
#
# NOTE ON ROW 3's OWN PRIMITIVE: §8 A13 claims `mailbox_close_disposition` is "landed and tested
# standalone". It does not exist — grep over scripts/ hooks/ bin/ finds it only in that doc; row 3's
# map cell ("SPECIFIED, NOT BUILT") is the accurate one. So the mechanics are row 2's, built on row
# 3's REAL primitive `mailbox_migrate`.
#
# The seam is exercised with row 3's ACTUAL library against a fixtured CC_MAILBOX_DIR rather than a
# stub: a stubbed migrate would prove only that this file calls something, and the whole point of an
# inherited seam is that the two halves compose.

setup() {
  # M11 (MACHINE_CAPACITY_V2 §11.3) — a test's environment is PINNED, not ambient. handoff-fire.sh's
  # capacity_gate reads the box's live loadavg AND (M10) its memory headroom, exiting 9 when either is
  # past its bar, so an unpinned suite goes RED purely because the box is busy — the corpus deciding a
  # verdict on machine state instead of on the tree. Both terms are pinned off here (they are the two
  # TERMS of one exit 9, handoff-fire.sh:4487); tests/handoff-fire-capacity-gate.bats is the ONE place
  # the gate runs ON, against synthetic inputs.
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  hf_bounded() { "$@"; }
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"

  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude"
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mailbox"; mkdir -p "$CC_MAILBOX_DIR"
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg";    mkdir -p "$CC_REGISTRY_DIR"
  export CC_FIRED_DIR="$BATS_TEST_TMPDIR/cc-fired";  mkdir -p "$CC_FIRED_DIR"
  FIRED_DIR="$CC_FIRED_DIR"

  MYSID="mysess-11112222"
  SUCC_PANE="BBBB1111-2222-3333-4444-555566667777"
  SUCC_SID="succsess-33334444"
  printf '{"paneUUID":"%s","session_id":"%s","pid":%s}\n' "$SUCC_PANE" "$SUCC_SID" "$$" \
    > "$CC_REGISTRY_DIR/$SUCC_PANE.json"

  # row 3's REAL lib + row 2's units under test
  # shellcheck disable=SC1091
  . "$REPO/hooks/lib/mailbox-pending.sh"
  {
    grep '^_iso_now() {' "$HF" || true
    sed -n '/^cc_sid_for_pane() {/,/^}/p'              "$HF"
    sed -n '/^selfclose_mail_disposition() {/,/^}/p'   "$HF"
    sed -n '/^record_close_succession() {/,/^}/p'      "$HF"
  } > "$BATS_TEST_TMPDIR/units.sh"
  bash -n "$BATS_TEST_TMPDIR/units.sh" || { echo "extraction from $HF is not valid bash" >&2; return 1; }
  # shellcheck disable=SC1091
  . "$BATS_TEST_TMPDIR/units.sh"
  MAIL_DISPOSITION="none"
}

# N unread lines in <uuid>'s inbox, cursor at 0 (nothing seen).
seed_inbox() { # $1=uuid $2=n
  local i=1
  : > "$CC_MAILBOX_DIR/$1.md"
  while [ "$i" -le "$2" ]; do printf 'message %s for %s\n' "$i" "$1" >> "$CC_MAILBOX_DIR/$1.md"; i=$((i+1)); done
}

# ── the contract's FIRST branch: successor named → migrate, mandatory ───────────────────────────

@test "successor named: undrained mail is MIGRATED to the successor's live inbox, and the close proceeds" {
  seed_inbox "$MYSID" 3
  run mailbox_pending_count "$MYSID"
  [ "$output" = "3" ]                                   # positive control on the fixture itself
  run selfclose_mail_disposition "$MYSID" "$SUCC_PANE" "$BATS_TEST_TMPDIR/log"
  [ "$status" -eq 0 ]
  [[ "$output" == *"3 undrained message(s) migrated"* ]] || false
  # delivered to the SESSION box the successor is actually reading, not its pane box: row 3's
  # pane→session alias reconciliation runs at SESSION-START ONLY, so a live successor would never
  # see mail dropped under its pane key.
  [[ "$output" == *"$SUCC_SID"* ]] || false
  run mailbox_pending_count "$SUCC_SID"
  [ "$output" = "3" ]
  # exactly-once by cursor advance — the closing box is now drained, so a re-run is a no-op.
  run mailbox_pending_count "$MYSID"
  [ "$output" = "0" ]
}

@test "MANDATORY, not advisory: a migration that moves NOTHING blocks the close (return 1)" {
  # Row 2's contract branch is "migrate moved <1 ⇒ refuse the close"; row 3's primitive owns WHICH
  # conditions produce that, so the collaborator is stubbed here rather than coerced. Two earlier
  # attempts are recorded because each taught something:
  #   · chmod 500 on the mailbox dir → row 3's mkdir-based lock spins its full stale-wait on every
  #     call and the SUITE HANGS instead of failing (measured, not theorised).
  #   · a truncated "TRUNCATED" target → migrate ACCEPTS it and reports 2 lines moved, because
  #     _mbx_valid_uuid is a PATH-SAFETY validator (rejects . / .. / separators), not a uuid-shape
  #     one. Worth knowing and reported to row 3 as a seam observation: a truncated address delivers
  #     into a dead box and reports success. It is row 3's surface, so it is not patched here.
  seed_inbox "$MYSID" 2
  mailbox_migrate() { echo 0; return 1; }
  run selfclose_mail_disposition "$MYSID" "$SUCC_PANE" "$BATS_TEST_TMPDIR/log"
  [ "$status" -eq 1 ]
  [[ "$output" == *"M3 FAILED"* ]] || false
  [[ "$output" == *"refusing the close"* ]] || false
  # a blocked close loses nothing (R2) — the mail is still exactly where it was
  unset -f mailbox_migrate
  run mailbox_pending_count "$MYSID"
  [ "$output" = "2" ]
}

@test "mailbox_migrate ABSENT with mail owed: blocks rather than closing over it" {
  seed_inbox "$MYSID" 2
  unset -f mailbox_migrate
  run selfclose_mail_disposition "$MYSID" "$SUCC_PANE" "$BATS_TEST_TMPDIR/log"
  [ "$status" -eq 1 ]
  [[ "$output" == *"mailbox_migrate is unavailable"* ]] || false
}

@test "exactly-once: re-running the disposition after a successful migrate is a silent no-op" {
  seed_inbox "$MYSID" 2
  selfclose_mail_disposition "$MYSID" "$SUCC_PANE" "$BATS_TEST_TMPDIR/log"
  run selfclose_mail_disposition "$MYSID" "$SUCC_PANE" "$BATS_TEST_TMPDIR/log"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run mailbox_pending_count "$SUCC_SID"
  [ "$output" = "2" ]                                   # not doubled
}

# ── the contract's SECOND branch: no successor → dead-letter WITH existence evidence ────────────

@test "terminal close: mail is DEAD-LETTERED and the store carries EXISTENCE EVIDENCE" {
  seed_inbox "$MYSID" 4
  run selfclose_mail_disposition "$MYSID" "" "$BATS_TEST_TMPDIR/log"
  [ "$status" -eq 0 ]
  [[ "$output" == *"DEAD-LETTERED"* ]] || false
  [ -s "$CC_MAILBOX_DIR/dead-letter/$MYSID.md" ]
  run grep -c 'message' "$CC_MAILBOX_DIR/dead-letter/$MYSID.md"
  [ "$output" = "4" ]
  # R4 — the `.ran` stamp is what makes "no dead letters" distinguishable from "the store never ran".
  # cc-permission-beacon reported "none pending" while never having been invoked once; a store with
  # no existence evidence is that same defect with a different name.
  [ -s "$CC_MAILBOX_DIR/dead-letter/.ran" ]
  run grep -c "sid=$MYSID pending=4" "$CC_MAILBOX_DIR/dead-letter/.ran"
  [ "$output" = "1" ]
}

# R-6 CLOSED 2026-08-13. This test used to assert the message NAMED a surface that would one day show
# the store ("the operator board … row 10 owns that row"). That surface now exists — the store is the
# D-series' fifth escalation store — so the assertion moves from a promise to the DRAIN: a close that
# tells the operator only where the bytes went leaves them a path and no next action.
@test "terminal close names the DRAIN for the store, not just the file it wrote" {
  seed_inbox "$MYSID" 1
  run selfclose_mail_disposition "$MYSID" "" "$BATS_TEST_TMPDIR/log"
  [ "$status" -eq 0 ]
  [[ "$output" == *"DELIVERED but never READ"* ]] || false
  [[ "$output" == *"cc-escalations list"* ]] || false          # the read
  [[ "$output" == *"cc-escalations ack $MYSID.md"* ]] || false # …and the exact off switch
  [[ "$output" == *"mail-deadletter"* ]] || false              # the class it will appear under
  [[ "$output" == *"/dead-letter/.ran"* ]] || false            # existence evidence still named (R4)
}

@test "an undisposable dead-letter store BLOCKS the close rather than dropping the mail" {
  seed_inbox "$MYSID" 2
  # make the store uncreatable
  printf 'not-a-dir\n' > "$CC_MAILBOX_DIR/dead-letter"
  run selfclose_mail_disposition "$MYSID" "" "$BATS_TEST_TMPDIR/log"
  [ "$status" -eq 1 ]
  [[ "$output" == *"M3 FAILED"* ]] || false
}

# ── the quiet path, the kill switch, and the seam being dark ────────────────────────────────────

@test "nothing owed: the disposition is SILENT (zero counts must not add noise to every close)" {
  seed_inbox "$MYSID" 0
  run selfclose_mail_disposition "$MYSID" "$SUCC_PANE" "$BATS_TEST_TMPDIR/log"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "A11 kill switch: CC_CLOSE_MAIL_GUARD=0 reverts to WARN-only and does NOT disposition" {
  seed_inbox "$MYSID" 3
  CC_CLOSE_MAIL_GUARD=0 run selfclose_mail_disposition "$MYSID" "$SUCC_PANE" "$BATS_TEST_TMPDIR/log"
  [ "$status" -eq 0 ]
  [[ "$output" == *"DISABLED"* ]] || false
  run mailbox_pending_count "$MYSID"
  [ "$output" = "3" ]                                   # untouched — the switch really is off
  # POSITIVE CONTROL: with the switch ON the identical call DOES migrate, so the no-op above is the
  # switch acting rather than a broken fixture.
  selfclose_mail_disposition "$MYSID" "$SUCC_PANE" "$BATS_TEST_TMPDIR/log"
  run mailbox_pending_count "$MYSID"
  [ "$output" = "0" ]
}

@test "R5 fail-soft: with row 3's lib unavailable the close is NOT blocked, and says so LOUD" {
  # A missing library must not strand a finished session forever — but it must never read as success
  # either. This is the one place the implementation degrades below the contract, so it is pinned
  # explicitly rather than left as an accident.
  #
  # CLAUDE_CONFIG_DIR MUST BE UNSET, not merely HOME fixtured. selfclose_mail_disposition resolves
  # row 3's lib from three candidates and the SECOND is
  # "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/lib/mailbox-pending.sh" — so on any box that exports
  # CLAUDE_CONFIG_DIR (this one: ~/.claude-secondary, whose hooks/lib is a symlink into the live
  # checkout) the REAL lib is found despite the fixture, mailbox_pending_count gets defined, the
  # unavailable-lib branch is never taken, and the function returns 0 with EMPTY output. The test then
  # fails on a missing "M3 SKIPPED" while the implementation is entirely correct — i.e. it was red on
  # this box from the day it landed (b10ac9a7) and green anywhere else, blocking every land whose
  # gate selects this suite. Fixturing $HOME alone cannot close a seam that has its OWN env override.
  # (The repo's test-hermeticity ratchet covers HOME and the capacity gate; CLAUDE_CONFIG_DIR is a
  # third seam of the same class that it does not yet police.)
  run env -u CC_MAILBOX_DIR -u CLAUDE_CONFIG_DIR bash -c '
    set -uo pipefail
    unset -f mailbox_pending_count mailbox_migrate 2>/dev/null || true
    export HOME="'"$BATS_TEST_TMPDIR"'/nolib-home"; mkdir -p "$HOME/.claude"
    _iso_now() { printf "T"; }
    cc_sid_for_pane() { printf ""; }
    '"$(sed -n '/^selfclose_mail_disposition() {/,/^}/p' "$HF")"'
    selfclose_mail_disposition "sid-x" "" ""
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"M3 SKIPPED"* ]] || false
}

# ── the close half of the lifecycle record (V2 §5.1) ───────────────────────────────────────────

@test "record_close_succession writes closedAt + succession onto a schema-2 record" {
  printf '{"paneUUID":"P","schema":2,"selfRetire":true}\n' > "$FIRED_DIR/P.json"
  record_close_succession "$FIRED_DIR" "P" "successor" "$SUCC_PANE" "migrated:3"
  # NB the parentheses around `.closedAt|type` are load-bearing: `[.closedAt|type,.succession.kind]`
  # parses as `[.closedAt | (type, .succession.kind)]`, so `.succession` gets applied to the STRING
  # that `type` returned and jq dies "Cannot index string with string". That was a bug in this test,
  # not in the record — the written JSON was correct all along.
  run jq -r '[(.closedAt|type),.succession.kind,.succession.successorPane,.succession.mailDisposition]|@tsv' \
    "$FIRED_DIR/P.json"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'string\tsuccessor\t%s\tmigrated:3' "$SUCC_PANE")" ]
}

@test "record_close_succession records a TERMINAL close with a null successor, not an empty string" {
  printf '{"paneUUID":"P","schema":2,"selfRetire":true}\n' > "$FIRED_DIR/P.json"
  record_close_succession "$FIRED_DIR" "P" "terminal" "" "deadletter:2"
  run jq -r '[.succession.kind,(.succession.successorPane|type),.succession.mailDisposition]|@tsv' \
    "$FIRED_DIR/P.json"
  [ "$output" = "$(printf 'terminal\tnull\tdeadletter:2')" ]
}

@test "an ORIGIN session has no record, and the close annotator must not invent one" {
  # Creating a cc-fired file here would license cc-reaper to auto-reap an operator session — the file's
  # PRESENCE is the auto-reap key. So absence must stay absence.
  record_close_succession "$FIRED_DIR" "NOSUCHPANE" "terminal" "" "none"
  [ ! -e "$FIRED_DIR/NOSUCHPANE.json" ]
  # POSITIVE CONTROL: the same function DOES annotate when a record exists.
  printf '{"paneUUID":"Q","schema":2}\n' > "$FIRED_DIR/Q.json"
  record_close_succession "$FIRED_DIR" "Q" "terminal" "" "none"
  run jq -r '.succession.kind' "$FIRED_DIR/Q.json"
  [ "$output" = "terminal" ]
}
