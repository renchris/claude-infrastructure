#!/usr/bin/env bats
# handoff-fire.sh — a --recycle INHERITS a fired peer's self-retire contract (item fe740e799fd5).
#
# THE DEFECT, in two halves that fail for different reasons and needed different fixes:
#
#   A. THE RELOCATING FORM HARD-REFUSES. `--recycle --worktree/--cwd` (RECYCLE_RELOC=1) relaunches
#      THE SAME PANE in a NEW directory. The fired-peer stamp is pane-keyed and its oracle is cwd, so
#      an untouched stamp then names the OLD dir, fired_stamp_tenancy answers `stale`, and the
#      successor's self-close exits 2 — "the fired-peer stamp for pane X belongs to a DIFFERENT
#      session". Neither upstream rescue reaches it: adoption and the c163f42390a3 stamp repair both
#      run ONLY on `absent`, and deliberately never past a stamp that says something.
#
#   B. THE SAME-DIR FORM LOSES THE BRIEF, NOT THE PERMISSION. Measured 2026-09-09 while verifying
#      this item: a same-dir recycle leaves the stamp valid and untouched, so self-close is ALREADY
#      permitted there (case 1 below is that control, and it is why the filed claim "a recycled peer
#      can no longer self-close" is true of the relocating form ONLY). What it really loses is the
#      CONTRACT TEXT — WANT_SELF_RETIRE is forced 0 for any recycle, so the successor is never told
#      it is a fired peer that owes a ping and a close, and fired_contract_in_my_brief can never
#      re-derive its status if the stamp is later lost.
#
# THE DESIGN CALL, which the item correctly said had to be made before code: INHERIT, and only on
# `valid`. The receipts are in the subject's own header at hf_recycle_inherits_peer; the shortest is
# that inherit_recycle_goal already answers the identical question for the OTHER live contract a
# recycled pane holds, and two opposite answers in one script is drift.
#
# WHAT IS A RED-PROOF HERE AND WHAT IS NOT. Cases 1-2 are the pre/post arm and they use TWO REAL
# subjects — the real self-close origin gate decides, before and after the real migration helper
# runs — so the fixture cannot certify itself. Cases 3-6 are the gate's NEGATIVES, and they are the
# load-bearing half: a fix that conferred the contract on `absent` would restore every close in
# cases 1-2 and simultaneously hand every ORIGIN pane a self-retiring contract, which is the
# invariant this whole area exists to hold (memory: probe-that-acts-on-absence-must-confirm-presence).

setup() {
  command -v jq >/dev/null || skip "jq required"
  REPO_SRC="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO_SRC/scripts/handoff-fire.sh"
  # HERMETICITY (M11): $HOME first, then every seam whose default does NOT resolve under it.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_FIRE_CAPACITY_GATE=off CC_FIRE_HEADROOM_GATE=off
  export CC_FIRED_DIR="$BATS_TEST_TMPDIR/fired";        mkdir -p "$CC_FIRED_DIR"
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg";       mkdir -p "$CC_REGISTRY_DIR"
  export CC_PROJECTS_DIRS="$BATS_TEST_TMPDIR/projects"; mkdir -p "$CC_PROJECTS_DIRS"
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mailbox"
  export CC_CUSTODY_DIR="$BATS_TEST_TMPDIR/custody"
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/account-sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/no-such-claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"

  PANE="AAAABBBB-1111-2222-3333-444455556666"
  SID="deadbeef-0000-1111-2222-333344445555"
  mkdir -p "$BATS_TEST_TMPDIR/old" "$BATS_TEST_TMPDIR/new"
  OLD="$(cd "$BATS_TEST_TMPDIR/old" && pwd -P)"
  NEW="$(cd "$BATS_TEST_TMPDIR/new" && pwd -P)"
  printf '{"paneUUID":"%s","session_id":"%s","cwd":"%s"}\n' "$PANE" "$SID" "$NEW" \
    > "$CC_REGISTRY_DIR/$PANE.json"
}

# The stamp a REAL fire wrote for a peer dispatched into $1, carrying the fields a re-mint would
# lose. closedAt null unless $2 is given.
write_stamp() {
  jq -n --arg p "$PANE" --arg c "$1" --arg closed "${2:-}" \
    '{paneUUID:$p, cwd:$c, firedBy:"ORIGIN-PANE-77", firedAt:"2026-09-09T00:00:00Z",
      selfRetire:true, schema:2, originClass:"fired-peer", originator:"ORIGIN-PANE-77",
      notifyBack:"ORIGIN-PANE-77", marker:"HANDOFF-ENGAGE-4242-1786383932-7",
      closedAt:(if $closed == "" then null else $closed end), succession:null}' \
    > "$CC_FIRED_DIR/$PANE.json"
}

# The REAL origin gate, asked in $1, via the terminal self-close's own dry run.
selfclose_in() { ( cd "$1" && bash "$HF" self-close --terminal --session-id "$PANE" --dry-run 2>&1 ); }

# The predicate / migration functions, extracted from the subject and driven directly — the decision
# under test depends on the stamp and on nothing else, and a test that had to satisfy pane identity,
# teammate liveness and a live iTerm to reach one predicate would be testing those instead.
load_fns() {
  FN="$BATS_TEST_TMPDIR/fns.sh"
  {
    echo '. "'"$REPO_SRC"'/hooks/lib/origin-identity.sh"'
    echo '_iso_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }'
    awk '/^hf_recycle_inherits_peer\(\) \{/,/^\}/' "$HF"
    awk '/^hf_migrate_peer_stamp\(\) \{/,/^\}/'    "$HF"
  } > "$FN"
  # shellcheck disable=SC1090
  . "$FN"
}

@test "1 CONTROL: the pane still in the dir it was fired into is a peer — the close is permitted" {
  write_stamp "$OLD"
  run selfclose_in "$OLD"
  [ "$status" -eq 0 ] || { echo "a genuine peer was REFUSED at its own cwd"; echo "$output"; false; }
  ! printf '%s\n' "$output" | grep -q 'self-close REFUSED' || false
}

@test "2 RED-PROOF: relocated, the close is REFUSED — and the migration restores it" {
  write_stamp "$OLD"
  # PRE: exactly the filed defect, decided by the real gate. This half stays true forever — it is
  # what an UNMIGRATED relocation still does, and the reason the migration has to exist.
  run selfclose_in "$NEW"
  [ "$status" -eq 2 ] || { echo "expected the stale refusal, got rc=$status"; echo "$output"; false; }
  printf '%s\n' "$output" | grep -q 'belongs to a DIFFERENT session' \
    || { echo "refused for some other reason"; echo "$output"; false; }
  # POST: the real helper migrates the stamp exactly as the relocating recycle now calls it.
  load_fns
  hf_migrate_peer_stamp "$CC_FIRED_DIR" "$PANE" "$NEW"
  run selfclose_in "$NEW"
  [ "$status" -eq 0 ] || { echo "still refused after migration"; echo "$output"; false; }
}

@test "3 the migration MOVES the cwd and KEEPS the original fire's fields (never re-mints)" {
  write_stamp "$OLD"; load_fns
  hf_migrate_peer_stamp "$CC_FIRED_DIR" "$PANE" "$NEW"
  s="$CC_FIRED_DIR/$PANE.json"
  [ "$(jq -r .cwd "$s")" = "$NEW" ]                      || { echo "cwd not migrated"; false; }
  [ "$(jq -r .recycledFrom "$s")" = "$OLD" ]             || { echo "no provenance"; false; }
  [ "$(jq -r .recycledAt "$s")" != null ]                || { echo "no recycledAt"; false; }
  # THE FIELDS A RE-MINT WOULD LOSE. notifyBack is the address sc_announce_before_retire enforces the
  # ping to, so losing it turns an announced retire into a silent one.
  [ "$(jq -r .notifyBack "$s")" = "ORIGIN-PANE-77" ]     || { echo "back-channel lost"; false; }
  [ "$(jq -r .originator "$s")" = "ORIGIN-PANE-77" ]     || { echo "originator lost"; false; }
  [ "$(jq -r .marker "$s")" = "HANDOFF-ENGAGE-4242-1786383932-7" ] || { echo "marker lost"; false; }
  [ "$(jq -r .firedAt "$s")" = "2026-09-09T00:00:00Z" ]  || { echo "firedAt rewritten"; false; }
  # …and the by-cwd index now answers for the NEW dir.
  [ "$(read_fired_cwd_index "$CC_FIRED_DIR" "$NEW")" = "$PANE" ] || { echo "index not repointed"; false; }
}

@test "4 THE INVARIANT: an ABSENT stamp is never minted — an origin pane cannot recycle into a peer" {
  # MEASURED MUTANT POWER, stated because the two halves of this case are not the same kind of test.
  # The FIRST assertion is a red-proof: accepting any tenancy state instead of `valid` reddens it (and
  # cases 5 and 7 with it). The SECOND is an EQUIVALENCE GUARD — the never-mint property is held by
  # TWO redundant structural facts, the `-s` source guard AND the `. +` transform that cannot run
  # without an input file, so no single-guard mutant reaches it: dropping the `-s` guard alone leaves
  # jq failing on a missing file (reds=0), and rewriting the transform as a `jq -n` mint alone is
  # stopped by the `-s` guard (it reddens case 3 instead). Only removing BOTH mints a stamp. That is
  # defence in depth, and this assertion credits the PAIR rather than either site
  # (memory: green-in-both-arms-is-an-equivalence-guard; per-site-mutation-attributes-coverage).
  load_fns
  rm -f "$CC_FIRED_DIR/$PANE.json"
  ! hf_recycle_inherits_peer "$CC_FIRED_DIR" "$PANE" "$OLD" 0 \
    || { echo "an origin pane was handed a self-retire contract"; false; }
  hf_migrate_peer_stamp "$CC_FIRED_DIR" "$PANE" "$NEW"
  [ ! -e "$CC_FIRED_DIR/$PANE.json" ] || { echo "the migration MINTED a stamp"; cat "$CC_FIRED_DIR/$PANE.json"; false; }
}

@test "5 a STALE or SPENT stamp is not inherited — one pane never gets two contracts" {
  load_fns
  write_stamp "$OLD"                       # stale as read from $NEW
  ! hf_recycle_inherits_peer "$CC_FIRED_DIR" "$PANE" "$NEW" 0 \
    || { echo "inherited a stamp belonging to a different tenancy"; false; }
  write_stamp "$OLD" "2026-09-09T01:00:00Z"  # spent, at its own cwd
  ! hf_recycle_inherits_peer "$CC_FIRED_DIR" "$PANE" "$OLD" 0 \
    || { echo "inherited a contract already used up"; false; }
  write_stamp "$OLD"                       # valid, at its own cwd ⇒ the one YES
  hf_recycle_inherits_peer "$CC_FIRED_DIR" "$PANE" "$OLD" 0 \
    || { echo "a genuine live peer was refused its own contract"; false; }
}

@test "6 the REMOTE recycle form ABSTAINS — \$PWD there is the caller's, not the pane's" {
  load_fns
  write_stamp "$OLD"
  ! hf_recycle_inherits_peer "$CC_FIRED_DIR" "$PANE" "$OLD" 1 \
    || { echo "the remote form answered from the CALLER's cwd"; false; }
}

@test "7 the trailer is gated on the stamp, not on --recycle: no stamp ⇒ no contract text" {
  # The end-to-end half of case 4, through the REAL composer. A recycle of a pane with no peer stamp
  # must compose no self-retire trailer at all — the pre-existing assertion in notify-back.bats
  # ("--recycle: self-retire AND back-channel auto-excluded") is the same claim, and this pins that
  # the new gate did not quietly widen it.
  rm -f "$CC_FIRED_DIR/$PANE.json"
  printf 'CONTINUE the work.\n' > "$BATS_TEST_TMPDIR/p.md"
  run env ITERM_SESSION_ID="w1t0p0:$PANE" \
    bash "$HF" --prompt-file "$BATS_TEST_TMPDIR/p.md" --launcher claude-test --recycle --dry-run
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  ! printf '%s\n' "$output" | grep -q 'handoff-prompt-nb' \
    || { echo "a trailer copy was composed for a pane holding no peer stamp"; echo "$output"; false; }
}

@test "8 the call site is REACHABLE and gated exactly three ways (reloc + inherited + not-dry)" {
  # A STRUCTURAL pin, because the dry-run gate makes the migration unobservable end-to-end: a dry
  # run relaunches nothing, so migrating would describe a move that did not happen. What can be
  # asserted is that the one call site carries all three guards — dropping RECYCLE_RELOC would
  # rewrite a same-dir stamp, dropping RCY_INHERIT_PEER would reach past a stale/absent one, and
  # dropping DRY would mutate the store on a dry run.
  run bash -c "grep -n 'hf_migrate_peer_stamp \"\$FIRED_DIR\"' '$HF' | wc -l"
  [ "$(echo "$output" | tr -d ' ')" = 1 ] || { echo "expected exactly one call site"; false; }
  run bash -c "grep -B1 'hf_migrate_peer_stamp \"\$FIRED_DIR\"' '$HF' | grep -c 'RCY_INHERIT_PEER.*=.*1.*RECYCLE_RELOC.*=.*1.*DRY.*=.*0'"
  [ "$(echo "$output" | tr -d ' ')" = 1 ] || { echo "the call site lost one of its three guards"; false; }
}

@test "9 …and a recycle of a pane that IS a peer DOES compose the contract text" {
  # THE POSITIVE HALF OF CASE 7, and the case without which this suite would stay green over a
  # deleted fix: case 7 alone is satisfied by the pre-fix behaviour (no recycle ever gets a trailer).
  # Together they pin the discriminator — the STAMP, not the flag.
  export TMPDIR="$BATS_TEST_TMPDIR"          # so the composed copy lands where it can be read
  write_stamp "$(pwd -P)"                    # a live peer, in the dir this process is running in
  printf 'CONTINUE the work.\n' > "$BATS_TEST_TMPDIR/p.md"
  run env ITERM_SESSION_ID="w1t0p0:$PANE" \
    bash "$HF" --prompt-file "$BATS_TEST_TMPDIR/p.md" --launcher claude-test --recycle --dry-run
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  copy="$(printf '%s\n' "$output" | sed -n 's/.*\(handoff-prompt-nb-[A-Za-z0-9]*\).*/\1/p' | head -1)"
  [ -n "$copy" ] || { echo "no trailer copy composed for a pane holding a VALID peer stamp"; echo "$output"; false; }
  # The heading is read from the SUBJECT, never retyped here (memory: control-calibrated-to-
  # implementation-decays) — an edit on both sides must not leave this passing over a dead string.
  heading="$(sed -n "s/^SELF_RETIRE_CONTRACT_HEADING='\(.*\)'$/\1/p" "$HF" | head -1)"
  [ -n "$heading" ] || { echo "could not read the heading constant from the subject"; false; }
  grep -qF -- "$heading" "$BATS_TEST_TMPDIR/$copy" \
    || { echo "the copy carries no self-retire contract"; cat "$BATS_TEST_TMPDIR/$copy"; false; }
}
