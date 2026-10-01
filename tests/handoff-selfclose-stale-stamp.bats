#!/usr/bin/env bats
# Pane-lifecycle fixes 2026-10-01, items 1 and 2 (docs/plans/pane-lifecycle-fixes-2026-10-01.md;
# evidence docs/research/selfclose-failures-2026-10-01.md M1 and M9).
#
# M1 — a STALE stamp (an earlier tenant's, under a reused kitty id) refused genuine fired peers
#   without trying the two proofs the gate already trusts on `absent`: adoption of an open stamp for
#   this cwd whose marker is in this session's transcript, and repair from the self-retire contract in
#   its first user message. 3 of 5 stale refusals in the week were genuine peers (pane 47).
#   Both proofs now run on `stale`, and the stale record is SET ASIDE, never overwritten.
# M9 — a `valid` or `unknown` stamp was trusted without asking whose it is. A stamp whose marker is
#   provably in no transcript of this session's chain now reads `stale`; an unprovable owner abstains.
#
# Every test drives the REAL gate end to end (`self-close --terminal --dry-run`); status 0 means the
# origin gate let the close through, status 2 means it refused.

setup() {
  command -v jq >/dev/null || skip "jq required"
  REPO_SRC="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO_SRC/scripts/handoff-fire.sh"
  # HERMETICITY (M11): $HOME first, then every seam whose default does NOT resolve under it.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  export CC_FIRED_DIR="$BATS_TEST_TMPDIR/fired";        mkdir -p "$CC_FIRED_DIR"
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg";       mkdir -p "$CC_REGISTRY_DIR"
  export CC_PROJECTS_DIRS="$BATS_TEST_TMPDIR/projects"; mkdir -p "$CC_PROJECTS_DIRS"
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mailbox"
  export CC_CUSTODY_DIR="$BATS_TEST_TMPDIR/custody"
  export CC_PANE_CLOSE_QUEUE_DIR="$BATS_TEST_TMPDIR/pane-close-queue"
  export HF_HANDOFFS_LOG="$BATS_TEST_TMPDIR/handoffs.jsonl"
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
  HEADING="$(sed -n "s/^SELF_RETIRE_CONTRACT_HEADING='\(.*\)'$/\1/p" "$HF" | head -1)"
  [ -n "$HEADING" ] || { echo "could not read SELF_RETIRE_CONTRACT_HEADING from $HF"; return 1; }
  M_OLD="HANDOFF-ENGAGE-1111-1786000000-1"   # the earlier tenant's fire
  M_NEW="HANDOFF-ENGAGE-2222-1790800000-2"   # this session's fire
}

stamp() { # <file-id> <cwd> <marker> [closedAt]
  jq -n --arg p "$1" --arg c "$2" --arg m "$3" --arg closed "${4:-}" \
    '{paneUUID:$p, cwd:$c, firedBy:"ORIGIN-PANE-77", firedAt:"2026-08-25T00:00:00Z",
      selfRetire:true, schema:2, originClass:"fired-peer", originator:"ORIGIN-PANE-77",
      notifyBack:"ORIGIN-PANE-77", marker:$m,
      closedAt:(if $closed == "" then null else $closed end), succession:null}' \
    > "$CC_FIRED_DIR/$1.json"
}

transcript() { # <first-user-text>  — the nested layout CC really writes
  local d="$CC_PROJECTS_DIRS/-fixture"; mkdir -p "$d"
  { jq -nc '{type:"user", isMeta:true, message:{content:"hook context"}}'
    jq -nc --arg t "$1" '{type:"user", timestamp:"2026-10-01T00:00:00Z", message:{content:$t}}'
    jq -nc '{type:"assistant", message:{content:[{type:"text",text:"working"}]}}'
  } > "$d/$SID.jsonl"
}
fired_brief() { printf 'TASK — drive it.\n\n%s\n  1. DRIVE.\n\n<!-- handoff-fire engagement marker: %s (ignore) -->' "$HEADING" "$1"; }

selfclose() { ( cd "$NEW" && bash "$HF" self-close --terminal --session-id "$PANE" --dry-run 2>&1 ); }
asides() { find "$CC_FIRED_DIR" -name "$PANE.json.superseded-*" | wc -l | tr -d ' '; }

# ── item 1 (M1): stale stamp, genuine peer ────────────────────────────────────────────────────────

@test "M1 repair: a STALE stamp + this session's own fired brief ⇒ close permitted, stamp repaired" {
  stamp "$PANE" "$OLD" "$M_OLD"
  transcript "$(fired_brief "$M_NEW")"
  run selfclose
  [ "$status" -eq 0 ] || { echo "a genuine peer was refused over a stale stamp"; echo "$output"; false; }
  [[ "$output" == *"stamp REPAIRED"* ]] || { echo "$output"; false; }
  [ "$(jq -r .cwd "$CC_FIRED_DIR/$PANE.json")" = "$NEW" ]       || { echo "stamp not this pane's"; false; }
  [ "$(jq -r .marker "$CC_FIRED_DIR/$PANE.json")" = "$M_NEW" ]  || { echo "wrong marker"; false; }
}

@test "M1 repair: the earlier tenant's stamp is SET ASIDE byte-for-byte, never overwritten" {
  stamp "$PANE" "$OLD" "$M_OLD"; cp "$CC_FIRED_DIR/$PANE.json" "$BATS_TEST_TMPDIR/orig.json"
  transcript "$(fired_brief "$M_NEW")"
  run selfclose
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(asides)" = 1 ] || { echo "expected exactly one aside"; ls "$CC_FIRED_DIR"; false; }
  cmp "$BATS_TEST_TMPDIR/orig.json" "$(find "$CC_FIRED_DIR" -name "$PANE.json.superseded-*")"
  [[ "$output" == *"set aside, not overwritten"* ]] || { echo "$output"; false; }
}

@test "M1 adoption: a STALE stamp + an open stamp for this cwd whose marker is mine ⇒ adopted" {
  stamp "$PANE" "$OLD" "$M_OLD"
  stamp "ORPHAN-PANE-9" "$NEW" "$M_NEW"
  transcript "plain operator words, then later it mentions $M_NEW"
  run selfclose
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"stamp ADOPTED"* ]] || { echo "$output"; false; }
  [ "$(jq -r .adoptedFrom "$CC_FIRED_DIR/$PANE.json")" = "ORPHAN-PANE-9" ] || { echo "not adopted"; false; }
  [ "$(asides)" = 1 ] || { echo "the stale stamp was overwritten, not set aside"; false; }
}

@test "M1 CONTROL: a STALE stamp and NO proof ⇒ still refused, and the stamp is put back untouched" {
  stamp "$PANE" "$OLD" "$M_OLD"; cp "$CC_FIRED_DIR/$PANE.json" "$BATS_TEST_TMPDIR/orig.json"
  transcript "an operator's own session, no contract"
  run selfclose
  [ "$status" -eq 2 ] || { echo "an origin session under a reused id was let through"; echo "$output"; false; }
  [[ "$output" == *"belongs to a DIFFERENT session"* ]] || { echo "$output"; false; }
  cmp "$BATS_TEST_TMPDIR/orig.json" "$CC_FIRED_DIR/$PANE.json"
  [ "$(asides)" = 0 ] || { echo "an aside was left behind on a refusal"; false; }
}

@test "M1 CONTROL: the trailer alone (a pasted bridge, no fire marker) does not unlock a stale stamp" {
  stamp "$PANE" "$OLD" "$M_OLD"
  transcript "$(printf 'TASK.\n\n%s\n  1. DRIVE.' "$HEADING")"
  run selfclose
  [ "$status" -eq 2 ] || { echo "$output"; false; }
}

# ── item 2 (M9): whose stamp is a valid/unknown one? ──────────────────────────────────────────────

@test "M9: an UNKNOWN-tenancy stamp (worktree gone) with a stranger's marker is refused, not trusted" {
  stamp "$PANE" "$BATS_TEST_TMPDIR/removed-worktree" "$M_OLD"
  transcript "an operator's own session, no contract"
  run selfclose
  [ "$status" -eq 2 ] || { echo "a stranger's stamp authorised this close"; echo "$output"; false; }
  [[ "$output" == *"is in no transcript of this session"* ]] || { echo "$output"; false; }
}

@test "M9: a VALID-tenancy stamp (same cwd) with a stranger's marker is refused, not trusted" {
  stamp "$PANE" "$NEW" "$M_OLD"
  transcript "an operator's own session, no contract"
  run selfclose
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [[ "$output" == *"belongs to a DIFFERENT session"* ]] || { echo "$output"; false; }
}

@test "M9: a stranger's unknown-tenancy stamp + this session's fired brief ⇒ repaired onto its own record" {
  stamp "$PANE" "$BATS_TEST_TMPDIR/removed-worktree" "$M_OLD"
  transcript "$(fired_brief "$M_NEW")"
  run selfclose
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(jq -r .marker "$CC_FIRED_DIR/$PANE.json")" = "$M_NEW" ] || { echo "close would land on the stranger's record"; false; }
}

@test "M9 CONTROL: a valid stamp whose marker IS in this transcript passes unchanged" {
  stamp "$PANE" "$NEW" "$M_NEW"
  transcript "$(fired_brief "$M_NEW")"
  run selfclose
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" != *"Treating it as stale"* ]] || { echo "$output"; false; }
  [ "$(asides)" = 0 ] || false
}

@test "M9 ABSTAINS: no transcript for this session ⇒ the stamp is trusted exactly as before" {
  stamp "$PANE" "$NEW" "$M_OLD"
  run selfclose
  [ "$status" -eq 0 ] || { echo "an unprovable owner was read as a stranger"; echo "$output"; false; }
}

@test "M9 ABSTAINS: a recycled peer (recycle brief, predecessor not joinable) keeps its root-marker stamp" {
  # A recycle migrates the stamp and keeps the ROOT fire's marker, while the recycled session's own
  # brief carries a HANDOFF-RECYCLE-… marker. With handoffs.jsonl rotated, the chain cannot be walked:
  # that is `unknown`, never `foreign`.
  stamp "$PANE" "$NEW" "$M_OLD"
  transcript "$(printf 'RECYCLE brief.\n\n%s\n<!-- HANDOFF-RECYCLE-3333-1790800000-3 -->' "$HEADING")"
  run selfclose
  [ "$status" -eq 0 ] || { echo "a recycled peer was refused"; echo "$output"; false; }
}

@test "M9 kill switch: CC_SELFCLOSE_MARKER_OWNER=0 restores the old trust" {
  stamp "$PANE" "$NEW" "$M_OLD"
  transcript "an operator's own session, no contract"
  run bash -c "cd '$NEW' && CC_SELFCLOSE_MARKER_OWNER=0 bash '$HF' self-close --terminal --session-id '$PANE' --dry-run 2>&1"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}
