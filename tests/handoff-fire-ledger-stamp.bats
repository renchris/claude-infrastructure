#!/usr/bin/env bats
# handoff-fire.sh — THE LEDGER STAMP AT RETIREMENT (exhaustive-drive 2026-09-08, synthesis rank 5).
#
# WHY THIS EXISTS: 56% of this fleet's sessions end inside handoff-fire's self-close or --recycle,
# and until this change the only state either actuator asked about was "is the tree dirty". That is
# one rung of seven. A pane retiring on 📦 — commits that exist on this machine and nowhere else —
# retired exactly as quietly as a ✅ one, and neither the successor nor the originator reading the
# custody row inherited any record of it. Committed-but-unlanded wave members are the measured top
# loss class in this repo (62 content-stranded commits over 21 branches).
#
# 🚨 ANNOTATE, NEVER REFUSE — TRUE OF THE STAMP, AND STILL TRUE. The stamp itself may not change any
# exit path, and cases 3 and 4 are the two controls that hold that from both sides.
#
# ⚠ CORRECTED IN PLACE 2026-09-09 (wave W3-B1). The paragraph that stood here also said the REFUSE
# variant "is a separate, later decision gated on a measurement nobody has taken — it is deliberately
# not built, and nothing here asserts it". The first half was right and the deferral was discharged:
# W2-B1 took the measurement (54 self-closes, 44 with a frozen at-retire ledger) and a --terminal
# close now REFUSES (exit 8) on the stamp's UNLANDED>0 or REMAINDER≠0 fields — never on its RUNG, and
# never on ⛔, which fired 3/44 and was wrong all three times. That refusal is a DIFFERENT gate with
# its own suite (tests/handoff-fire-selfclose-refusal.bats); this one still owns the stamp.
#
# CONSEQUENCE FOR THIS FIXTURE, and it is the reason three cases below carry --allow-unlanded: this
# suite's subject tree is deliberately 📦, which is now exactly the state the new gate declines. The
# flag is the deliberate-park escape, and it clears the REFUSAL without silencing the STAMP — so
# these cases still assert what they always asserted, over the same tree, one gate further down.
#
# THE FIXTURE IS A REAL GIT REPO WITH A REAL UNLANDED COMMIT, driven through the REAL
# scripts/wrap-ledger.sh. A stubbed ledger would only prove this suite can read its own stub; the
# claim under test is that the rung a retiring session actually carries reaches a store, so the rung
# has to be computed by the renderer that owns it.

setup() {
  # M11 — the capacity gate reads the live box; pinned off so a busy machine cannot decide a verdict
  # here. tests/handoff-fire-capacity-gate.bats is the one place that gate runs on.
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"
  # HERMETICITY: this suite drives the REAL self-close path, which reads the operator's registry,
  # mailbox, custody and autonomy stores and whose alarm sites call the live cc-notify. Every one of
  # those is fixtured, in setup() rather than per-test — the same law as the CC_COMMS_ALARM_DIR leak
  # (backlog 817faf3a4968). wrap-ledger.sh is still the REAL one: handoff-fire resolves it relative
  # to its own path, so a fixtured $HOME cannot substitute a copy.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_FIRED_DIR="$BATS_TEST_TMPDIR/cc-fired";       mkdir -p "$CC_FIRED_DIR"
  export CC_CUSTODY_DIR="$BATS_TEST_TMPDIR/custody";      mkdir -p "$CC_CUSTODY_DIR"
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/cc-registry"; mkdir -p "$CC_REGISTRY_DIR"
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mailbox"
  export CC_COMMS_ALARM_DIR="$BATS_TEST_TMPDIR/comms-alarms"
  export CC_HANDOFF_ALARM_DIR="$BATS_TEST_TMPDIR/handoff-alarms"
  export CC_PROJECTS_DIRS="$BATS_TEST_TMPDIR/projects";   mkdir -p "$CC_PROJECTS_DIRS"
  # THE THREE SEAMS $HOME CANNOT REACH (test-hermeticity ratchet, class 5a/5b). Fixturing $HOME does
  # not redirect an ABSOLUTE /tmp default, and it does not stop a BARE NAME being executed off the
  # operator's live PATH — the account sweep on this close path would otherwise write the operator's
  # real /tmp stamp, run their deployed claude-accounts once per test, and take their heal lock.
  # ABSENT paths are the right pins here: every one of these sensors fails open on a missing file.
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/account-sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/no-such-claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-lock-"

  PANE="fake:LEDG-0001"
  SID="11111111-2222-3333-4444-555555555555"
  MARKER="HANDOFF-ENGAGE-LEDG-0001"

  # THE SUBJECT TREE: clean, one commit ahead of origin/main ⇒ UNLANDED=1 ⇒ RUNG=📦. `update-ref` +
  # `symbolic-ref` synthesise the remote-tracking side without a network or a second repo, which is
  # exactly the state a fired peer is in when it retires on an unlanded branch. Identity is passed
  # TRANSIENTLY (`git -c`) and never written to a config: this repo shares one .git/config across
  # ~100 linked worktrees, and a `git -C "$VAR" config` whose variable is empty is a documented
  # no-op that re-authors commits in the CURRENT repo (the 2026-08-05 leak).
  WORK="$BATS_TEST_TMPDIR/work"; mkdir -p "$WORK"
  git init -q -b main "$WORK"
  fixture_commit() { git -C "$BATS_TEST_TMPDIR/work" -c user.email=t@example.com -c user.name=Ledger commit -qm "$1"; }
  echo landed > "$WORK/landed.txt"
  git -C "$BATS_TEST_TMPDIR/work" add landed.txt && fixture_commit "landed"
  git -C "$BATS_TEST_TMPDIR/work" update-ref refs/remotes/origin/main HEAD
  git -C "$BATS_TEST_TMPDIR/work" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
  echo stranded > "$WORK/stranded.txt"
  git -C "$BATS_TEST_TMPDIR/work" add stranded.txt && fixture_commit "stranded — on this machine only"

  # ORIGIN GATE: self-close is available only to a session FIRED BY an originator, and the stamp is
  # tenancy-bound on cwd. The marker is what the custody discharge joins on.
  printf '{"paneUUID":"%s","cwd":"%s","firedBy":"ORIGINATOR","firedAt":"2026-09-08T18:00:00Z","selfRetire":true,"marker":"%s"}\n' \
    "$PANE" "$WORK" "$MARKER" > "$CC_FIRED_DIR/$PANE.json"
  # The registry row is what makes cc_sid_for_pane resolve — without it the stamp takes its
  # UNRESOLVABLE branch, which case 4 exercises on purpose.
  printf '{"paneUUID":"%s","session_id":"%s","cwd":"%s"}\n' "$PANE" "$SID" "$WORK" \
    > "$CC_REGISTRY_DIR/$PANE.json"
  # The originator's open custody row, so the close has a debt to discharge and a row to stamp.
  "$REPO/bin/cc-custody" open --cwd "$WORK" --target "$PANE" --marker "$MARKER" \
      --slug ledger-fixture --notify-back ORIGINATOR --originator-pane ORIGINATOR >/dev/null
  # A failed cd here would run every case against the bats CWD — this repo's own dirty worktree —
  # so the fixture must be the subject or nothing is: fail the setup rather than the assertion.
  cd "$WORK" || return 1
}

# The `why` of the custody row this close discharged — the ORIGINATOR's copy of the stamp.
custody_why() {
  cat "$CC_CUSTODY_DIR"/*.jsonl 2>/dev/null | jq -r 'select(.kind=="return") | .why // ""' | tail -1
}

@test "1 a self-close over an UNLANDED commit stamps 📦 onto the custody row the originator reads" {
  command -v jq >/dev/null 2>&1 || skip "the custody store is jsonl"
  run bash "$HF" self-close --terminal --session-id "$PANE" --allow-unlanded --dry-run
  [ "$status" -eq 0 ]
  why="$(custody_why)"
  [ -n "$why" ] || { echo "the custody return row carries NO why — the stamp never reached the originator's store"; false; }
  [[ "$why" == *"LEDGER AT RETIREMENT"* ]] || { echo "the custody row's why is not a ledger stamp: $why"; false; }
  # THE RUNG ITSELF. This is the whole point: the originator's store must say the retiring pane was
  # holding work that exists on this machine only.
  [[ "$why" == *"📦"* ]]                     || { echo "the stamp does not name the 📦 rung this fixture is in: $why"; false; }
  [[ "$why" == *"1 commit(s) NOT landed"* ]] || { echo "the stamp does not carry the unlanded COUNT: $why"; false; }
  [[ "$why" == *"frozen-DoD remainder 0"* ]] || { echo "the stamp does not carry the frozen-DoD remainder: $why"; false; }
  [[ "$why" == *"goal "* ]]                  || { echo "the stamp does not carry the goal state: $why"; false; }
}

@test "2 the stamp is on the close's own output too — a marker-less fire still surfaces it" {
  run bash "$HF" self-close --terminal --session-id "$PANE" --allow-unlanded --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"LEDGER AT RETIREMENT"* ]] || { echo "no stamp on the close output"; false; }
  [[ "$output" == *"📦"* ]] || { echo "the close output does not name the rung: $output"; false; }
}

@test "3 ANNOTATE, NEVER REFUSE — a ledger that cannot be read yields UNREAD and rc 0, never a refusal" {
  # The unit control. hf_ledger_stamp is sed-extracted (the technique announce-before-retire.bats
  # uses for the same reason: the decision under test does not depend on pane identity, teammate
  # liveness or the origin class, and a test that had to satisfy all three would be testing those).
  # A ledger that is killed, absent or broken is one observation: the stamp must degrade to a
  # warning that SAYS it is not a clean-state claim, and must still return 0 so its caller — a close
  # path — cannot inherit a failure from its own bookkeeping.
  fn="$BATS_TEST_TMPDIR/fn.sh"
  sed -n '/^hf_ledger_stamp() {/,/^}/p' "$HF" > "$fn"
  grep -q '^hf_ledger_stamp() {' "$fn" || { echo "hf_ledger_stamp is not extractable"; false; }
  run bash -c '
      _CC_KS="$1"
      transcript_for_sid() { printf ""; }
      hf_bounded_s() { return 124; }          # the killed-ledger observation
      . "$2"
      hf_ledger_stamp "'"$SID"'" "'"$WORK"'"; echo "rc=$?"' _ "$HF" "$fn"
  [ "$status" -eq 0 ]
  [[ "$output" == *"rc=0"* ]] \
    || { echo "an unreadable ledger returned non-zero — a close path would inherit a failure from its own bookkeeping: $output"; false; }
  [[ "$output" == *"LEDGER AT RETIREMENT: UNREAD"* ]] \
    || { echo "a stamp that could not be taken must SAY so — silence reads as a clean state: $output"; false; }
  [[ "$output" == *"NOT a clean-state claim"* ]] \
    || { echo "the UNREAD stamp does not say what it is NOT: $output"; false; }
  # POSITIVE CONTROL for this case: the same extraction over the same fixture with the ledger
  # REACHABLE must produce the real rung, so the assertions above are about the degradation and not
  # about an extraction that never worked.
  run bash -c '
      _CC_KS="$1"
      transcript_for_sid() { printf ""; }
      hf_bounded_s() { shift; "$@"; }
      . "$2"
      hf_ledger_stamp "'"$SID"'" "'"$WORK"'"' _ "$HF" "$fn"
  [ "$status" -eq 0 ]
  [[ "$output" == *"📦"* ]] || { echo "the reachable-ledger control did not produce a rung: $output"; false; }
}

@test "4 an UNRESOLVABLE sid warns and proceeds — the close exits exactly as it does when stamped" {
  # The end-to-end half of case 3, and the common case rather than an exotic one: a provisional
  # cc-registry row carries no session_id (measured 10 of 19 live rows). Removing the row IS that
  # state. The close must reach the same exit it reaches with a healthy ledger.
  # BOTH runs carry --allow-unlanded so the comparison is apples-to-apples: the W3-B1 refusal is a
  # separate gate over this same 📦 fixture, and letting it fire on one arm only would make this case
  # measure THAT gate's asymmetry instead of the stamp's exit-neutrality, which is its whole subject.
  run bash "$HF" self-close --terminal --session-id "$PANE" --allow-unlanded --dry-run
  [ "$status" -eq 0 ]
  stamped_status="$status"
  rm -f "$CC_REGISTRY_DIR/$PANE.json"
  run bash "$HF" self-close --terminal --session-id "$PANE" --allow-unlanded --dry-run
  [ "$status" -eq "$stamped_status" ] \
    || { echo "an unstampable close CHANGED the exit path ($status vs $stamped_status) — the stamp is refusing, which it may never do"; false; }
  [[ "$output" == *"LEDGER AT RETIREMENT: UNREAD"* ]] \
    || { echo "an unresolvable sid produced no stamp at all — indistinguishable from a clean ledger: $output"; false; }
}

@test "5 the --recycle successor brief inherits the stamp — and only the recycle brief does" {
  # The other actuator and the other consumer. A recycle destroys the predecessor's context by
  # design, so the brief is the successor's entire picture of the state it is inheriting. An
  # ordinary fire's successor is a NEW session with no predecessor state, so a stamp there would
  # assert a fact about the wrong session — the composer must gate on RECYCLE.
  run bash -c "grep -c 'STATE YOU ARE INHERITING' '$HF'"
  [ "$output" -ge 1 ] || { echo "the recycle brief composer embeds no stamp section"; false; }
  # A heading is not a stamp: the section must actually call the ledger, and it must sit inside the
  # `if [ "$RECYCLE" = 1 ]` guard that keeps it off an ordinary fire's brief.
  awk '/## STATE YOU ARE INHERITING/{found=1} found && /hf_ledger_stamp/{print "WIRED"; exit}' "$HF" \
    | grep -q WIRED || { echo "the stamp section exists but calls no ledger"; false; }
  awk '/if \[ "\$RECYCLE" = 1 \]; then/{g=NR} /## STATE YOU ARE INHERITING/{ if (g && NR-g < 6) print "GATED"; exit }' "$HF" \
    | grep -q GATED || { echo "the stamp section is not gated on RECYCLE — an ordinary fire's brief would claim its successor inherited a predecessor's rung"; false; }
}
