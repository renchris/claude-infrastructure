#!/usr/bin/env bats
# Regression guard for PANE 882 (2026-09-28): a fired peer that RECYCLED could no longer retire, and
# the session that fired it had no sanctioned way to retire it either.
#
# THE INCIDENT, measured. Origin pane 845 fired 882 (05:53:01Z, stamp written). 882 recycled itself
# at 07:20:02Z — 87 minutes after the fire. cc-reaper's boot-tenancy rule ("the pane's current
# session booted within 1800 s of firedAt, else a later tenant reused the id") read the recycle's new
# session as an id-reuse tenant and GARBAGE-COLLECTED the stamp at 08:10:49Z. The finished, landed
# peer then ran `self-close --terminal` and was REFUSED as an ORIGIN session; the stamp-repair path
# could not re-derive it either, because its recycled brief carries HANDOFF-RECYCLE-…, never the
# HANDOFF-ENGAGE-… marker the proof demanded. And 845's `self-close --session-id 882` was refused by
# the ancestry gate ("an ASSERTION BY THE CALLER"). Pane 884 — same originator, recycled after only
# 19 minutes — kept its stamp and retired itself: the only variable was the clock.
#
# THREE FIXES, each pinned here with a test that is red on the pre-fix code:
#   1. the recycle re-anchors the stamp's boot-tenancy clock (hf_reanchor_peer_stamp → recycledAt),
#      and both time oracles take the later of firedAt/recycledAt (cc-reaper: tests/cc-reaper.bats
#      "recycled peer (pane 882)"; cc-classify: below);
#   2. the repair proof crosses recycles through handoff-fire's own recycle-engaged row;
#   3. `self-close --fired-peer P --terminal`: the pane that FIRED P may retire it, ownership proven
#      by the stamp's firedBy — never by process ancestry — with every peer-side guard intact.

setup() {
  export CC_FIRE_CAPACITY_GATE=off CC_FIRE_HEADROOM_GATE=off
  unset KITTY_WINDOW_ID
  export IT2_WRAPPER_NO_KITTY=1 CC_TERM=iterm2

  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"
  command -v jq >/dev/null || skip "jq required"

  # HERMETICITY — every default in the subject resolves under $HOME; pin it and the seams that do not.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/logs"
  export CC_FIRED_DIR="$BATS_TEST_TMPDIR/cc-fired"; mkdir -p "$CC_FIRED_DIR"
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg"; mkdir -p "$CC_REGISTRY_DIR"
  export CC_PROJECTS_DIRS="$BATS_TEST_TMPDIR/projects"; mkdir -p "$CC_PROJECTS_DIRS"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/cfg"; mkdir -p "$CLAUDE_CONFIG_DIR/projects"
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/sweep-stamp.json"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-lock-"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/absent-claude-accounts"
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mailbox"
  export HF_HANDOFFS_LOG="$HOME/.claude/logs/handoffs.jsonl"
  # Seams that do NOT resolve under $HOME (test-hermeticity-lint 5a/5b): an absolute /tmp default and a
  # bare name the subject would run off the operator's PATH. ABSENT paths: these sensors fail open.
  export CC_PERMPEND_DIR="$BATS_TEST_TMPDIR/absent-permission-pending"
  export CC_CLASSIFY_SESSIONS_BIN="$BATS_TEST_TMPDIR/absent-cc-sessions"
  unset CLAUDE_CODE_SESSION_ID

  SHIM="$BATS_TEST_TMPDIR/shim"; mkdir -p "$SHIM"
  # osascript: as_tty's query answers "TTY-<uuid>" for any pane.
  cat > "$SHIM/osascript" <<'SH'
uuid=""
while [ $# -gt 0 ]; do
  case "$1" in -e) shift 2 2>/dev/null || shift ;; -) shift ;; *) uuid="$1"; shift ;; esac
done
[ -n "$uuid" ] && printf '%s' "TTY-$uuid"
exit 0
SH
  # git, per DIRECTORY: .GITCLEAN / .GITDIRTY make a work tree; .GITAHEAD holds commits ahead of
  # origin/main. No marker ⇒ "not a work tree", so the cwd-scoped guards are skipped hermetically.
  cat > "$SHIM/git" <<'SH'
dir=""
if [ "${1:-}" = "-C" ]; then dir="${2:-}"; shift 2; fi
[ -n "$dir" ] || dir="$PWD"
wt=0; { [ -f "$dir/.GITDIRTY" ] || [ -f "$dir/.GITCLEAN" ]; } && wt=1
case "${1:-}" in
  rev-parse)
    [ "$wt" = 1 ] || exit 1
    case "$*" in *--abbrev-ref*) echo "feat/peer" ;; esac
    exit 0 ;;
  symbolic-ref) exit 1 ;;
  status)    [ -f "$dir/.GITDIRTY" ] && printf ' M tracked-file\n'; exit 0 ;;
  rev-list)  if [ -f "$dir/.GITAHEAD" ]; then cat "$dir/.GITAHEAD"; else echo 0; fi; exit 0 ;;
esac
exit 0
SH
  # ps: PS_TTY_OUT answers `ps -o tty= -p …` (own_ancestry_ttys) — which is what makes the CALLER's
  # pane read `mine` to pane_ownership. Everything else answers empty (no teammates, no subagents).
  cat > "$SHIM/ps" <<'SH'
want=""
while [ $# -gt 0 ]; do
  case "$1" in -o) case "${2:-}" in tty=) want=tty ;; esac; shift 2 ;; *) shift ;; esac
done
[ "$want" = tty ] && [ -n "${PS_TTY_OUT:-}" ] && printf '%s\n' "$PS_TTY_OUT"
exit 0
SH
  chmod +x "$SHIM/osascript" "$SHIM/git" "$SHIM/ps"
  export PATH="$SHIM:$PATH"

  HEADING="$(sed -n "s/^SELF_RETIRE_CONTRACT_HEADING='\(.*\)'$/\1/p" "$HF" | head -1)"
  [ -n "$HEADING" ] || { echo "could not read SELF_RETIRE_CONTRACT_HEADING from $HF"; return 1; }

  FIRER="84500000-aaaa-4000-8000-000000000845"
  PEER="88200000-bbbb-4000-8000-000000000882"
  SID_ROOT="d64fb5fe-15b2-4c79-891b-43d5d1e443e7"     # the session the fire landed (882's first)
  SID_NOW="80ad696a-ef7c-4c29-845d-ef6f4079136f"      # the session the recycle booted
  ENGAGE="HANDOFF-ENGAGE-76863-1790574734-8667"
  RECYCLE="HANDOFF-RECYCLE-38645-1790579976-29906"
  PEER_WT="$BATS_TEST_TMPDIR/peer-wt"; mkdir -p "$PEER_WT"; : > "$PEER_WT/.GITCLEAN"
  PEER_WT="$(cd "$PEER_WT" && pwd -P)"
  SLUG="-Users-x-Development-peer-wt"
  mkdir -p "$CC_PROJECTS_DIRS/$SLUG"
}

# transcript <sid> <first-user-text> <brief-iso-ts> [tail: rest|busy]
transcript() {
  local sid="$1" first="$2" ts="$3" tail="${4:-rest}" f
  f="$CC_PROJECTS_DIRS/$SLUG/$sid.jsonl"
  {
    jq -nc '{type:"user", isMeta:true, message:{content:"hook context"}}'
    jq -nc --arg t "$first" --arg ts "$ts" '{type:"user", timestamp:$ts, message:{content:$t}}'
    jq -nc '{type:"assistant", message:{content:[{type:"text",text:"done"}], stop_reason:"end_turn"}}'
    if [ "$tail" = busy ]; then
      jq -nc '{type:"user", message:{content:"one more thing"}}'
    fi
  } > "$f"
}
root_brief() {
  printf 'TASK — make the film.\n\n## BACK-CHANNEL — ping the originator (hero-film-regrade-845)\nping it.\n\n%s\n  1. DRIVE it.\n\n<!-- handoff-fire engagement marker: %s (ignore) -->\n' "$HEADING" "$ENGAGE"
}
recycle_brief() {
  printf 'PHASE 2 — continue.\n\n%s\n  1. DRIVE it.\n\n<!-- handoff-fire recycle engagement marker: %s (ignore) -->\n' "$HEADING" "$RECYCLE"
}
row() { # $1=pane $2=sid $3=cwd $4=pid
  jq -nc --arg p "$1" --arg s "$2" --arg c "$3" --argjson pid "${4:-$$}" \
    '{paneUUID:$p, session_id:$s, cwd:$c, pid:$pid, startedAt:1790580002000}' > "$CC_REGISTRY_DIR/$1.json"
}
recycle_row() { # $1=pane $2=prev-sid $3=ts
  jq -nc --arg p "$1" --arg s "$2" --arg t "$3" \
    '{ts:$t, class:"recycle-engaged", gate:"recycle", engaged:true, target_pane:$p, prev_sid:$s}' >> "$HF_HANDOFFS_LOG"
}
# The 882 state: registry names the recycled session; both transcripts exist; the recycle row joins
# them; NO stamp.
state_882() {
  row "$PEER" "$SID_NOW" "$PEER_WT"
  transcript "$SID_ROOT" "$(root_brief)" "2026-09-28T05:52:50.000Z"
  transcript "$SID_NOW" "$(recycle_brief)" "2026-09-28T07:20:03.850Z"
  recycle_row "$PEER" "$SID_ROOT" "2026-09-28T07:20:13Z"
}
load_proof() {
  eval "$(sed -n '/^cc_sid_for_pane() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^transcript_for_sid() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^fired_contract_in_my_brief() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^_fcb_prove_sid() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^hf_recycle_predecessor() {/,/^}/p' "$HF")"
  export SELF_RETIRE_CONTRACT_HEADING="$HEADING" REG_DIR="$CC_REGISTRY_DIR"
}

# ── 2. THE REPAIR PROOF CROSSES A RECYCLE ─────────────────────────────────────────────────────────

@test "882 repro: the recycled session's contract is PROVEN through the recycle-engaged row" {
  load_proof
  state_882
  fired_contract_in_my_brief "$PEER" || { echo "a recycled fired peer was REFUSED — pane 882"; false; }
  [ "$FCB_MARKER" = "$ENGAGE" ]  || { echo "marker is not the ROOT fire's: '$FCB_MARKER'"; false; }
  [ "$FCB_NOTIFYBACK" = "hero-film-regrade-845" ] || { echo "back-channel lost: '$FCB_NOTIFYBACK'"; false; }
  [ "$FCB_VIA_RECYCLE" = "$SID_ROOT" ] || { echo "chain not reported: '$FCB_VIA_RECYCLE'"; false; }
}

@test "recycle chain: two recycles deep still resolves to the root fire" {
  load_proof
  local mid="11111111-2222-4333-8444-555555555555"
  row "$PEER" "$SID_NOW" "$PEER_WT"
  transcript "$SID_ROOT" "$(root_brief)" "2026-09-28T05:52:50.000Z"
  transcript "$mid" "$(recycle_brief)" "2026-09-28T06:30:00.000Z"
  transcript "$SID_NOW" "$(recycle_brief)" "2026-09-28T07:20:03.850Z"
  recycle_row "$PEER" "$SID_ROOT" "2026-09-28T06:30:09Z"
  recycle_row "$PEER" "$mid" "2026-09-28T07:20:13Z"
  fired_contract_in_my_brief "$PEER"
  [ "$FCB_MARKER" = "$ENGAGE" ]
  [ "$FCB_VIA_RECYCLE" = "$SID_ROOT $mid" ] || { echo "got '$FCB_VIA_RECYCLE'"; false; }
}

@test "recycle chain REFUSED: the predecessor was NOT a fired peer (an operator session that recycled)" {
  load_proof
  state_882
  transcript "$SID_ROOT" "just a normal operator session" "2026-09-28T05:52:50.000Z"
  ! fired_contract_in_my_brief "$PEER" || { echo "a quoted heading in a recycle brief authorised a close"; false; }
}

@test "recycle chain REFUSED: no recycle-engaged row joins the two sessions" {
  load_proof
  state_882
  : > "$HF_HANDOFFS_LOG"
  ! fired_contract_in_my_brief "$PEER"
}

@test "recycle chain REFUSED: the only row is OUTSIDE the window (a previous tenant of this pane id)" {
  load_proof
  state_882
  : > "$HF_HANDOFFS_LOG"
  recycle_row "$PEER" "$SID_ROOT" "2026-09-27T07:20:13Z"
  ! fired_contract_in_my_brief "$PEER"
}

@test "recycle chain REFUSED: a row for a DIFFERENT pane does not join" {
  load_proof
  state_882
  : > "$HF_HANDOFFS_LOG"
  recycle_row "99900000-0000-4000-8000-000000000999" "$SID_ROOT" "2026-09-28T07:20:13Z"
  ! fired_contract_in_my_brief "$PEER"
}

@test "recycle chain REFUSED: a recycle brief WITHOUT the self-retire trailer (the contract was not inherited)" {
  load_proof
  state_882
  transcript "$SID_NOW" "PHASE 2 — continue. <!-- handoff-fire recycle engagement marker: $RECYCLE (ignore) -->" "2026-09-28T07:20:03.850Z"
  ! fired_contract_in_my_brief "$PEER"
}

@test "recycle chain REFUSED: kill switch CC_SELFCLOSE_RECYCLE_CHAIN=0 (the direct proof is untouched)" {
  load_proof
  state_882
  ! CC_SELFCLOSE_RECYCLE_CHAIN=0 fired_contract_in_my_brief "$PEER" || false
  # control: the direct (non-recycled) proof still passes under the same switch
  row "$PEER" "$SID_ROOT" "$PEER_WT"
  CC_SELFCLOSE_RECYCLE_CHAIN=0 fired_contract_in_my_brief "$PEER"
}

@test "882 repro END-TO-END: the recycled peer's own self-close --terminal REPAIRS instead of refusing" {
  state_882
  export ITERM_SESSION_ID="w0t0p0:$PEER"
  cd "$PEER_WT" || return 1
  export CC_CLOSE_LEDGER_GUARD=0
  run bash "$HF" self-close --terminal --dry-run
  [[ "$output" != *"this is an ORIGIN session"* ]] || { echo "$output"; false; }
  [[ "$output" == *"REPAIRED across a recycle"* ]] || { echo "$output"; false; }
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(jq -r .repairedFrom "$CC_FIRED_DIR/$PEER.json")" = recycle-chain ]
  [ "$(jq -r .marker "$CC_FIRED_DIR/$PEER.json")" = "$ENGAGE" ]
  [ "$(jq -r '.recycledFromSids[0]' "$CC_FIRED_DIR/$PEER.json")" = "$SID_ROOT" ]
}

# ── 1. THE RECYCLE RE-ANCHORS THE STAMP (writer) + cc-classify's twin (reader) ─────────────────────

@test "hf_reanchor_peer_stamp: recycledAt written, recycles counted, the fire's own fields untouched" {
  eval "$(sed -n '/^_iso_now() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^hf_reanchor_peer_stamp() {/,/^}/p' "$HF")"
  printf '{"paneUUID":"%s","cwd":"%s","firedBy":"%s","firedAt":"2026-09-28T05:53:01Z","marker":"%s","selfRetire":true}\n' \
    "$PEER" "$PEER_WT" "$FIRER" "$ENGAGE" > "$CC_FIRED_DIR/$PEER.json"
  hf_reanchor_peer_stamp "$CC_FIRED_DIR" "$PEER" 2>/dev/null
  hf_reanchor_peer_stamp "$CC_FIRED_DIR" "$PEER" 2>/dev/null
  local s="$CC_FIRED_DIR/$PEER.json"
  [ "$(jq -r .recycles "$s")" = 2 ]
  [[ "$(jq -r .recycledAt "$s")" == 20*Z ]] || false
  [ "$(jq -r .firedAt "$s")" = "2026-09-28T05:53:01Z" ] || { echo "firedAt re-minted"; false; }
  [ "$(jq -r .firedBy "$s")" = "$FIRER" ]
  [ "$(jq -r .marker "$s")" = "$ENGAGE" ]
}

@test "the re-anchor runs on EVERY inheriting recycle, not only the relocating one" {
  # The migration above it is RECYCLE_RELOC-only by design; the clock moves on a same-dir recycle too
  # (882 recycled in place). Pinned structurally: the call is gated on RCY_INHERIT_PEER and DRY alone.
  run grep -nE '^if \[ "\$RCY_INHERIT_PEER" = 1 \] && \[ "\$DRY" = 0 \]; then$' "$HF"
  [ "$status" -eq 0 ]
  local n="${output%%:*}"
  run sed -n "$((n + 1))p" "$HF"
  [[ "$output" == *'hf_reanchor_peer_stamp "$FIRED_DIR" "$SID"'* ]] || { echo "$output"; false; }
}

@test "cc-classify: a recycle-re-anchored stamp is tenancy-VALID for a session that booted 87 min after the fire" {
  local CL="$REPO/bin/cc-classify"
  # shellcheck source=/dev/null
  . "$REPO/hooks/lib/origin-identity.sh"
  eval "$(sed -n '/^iso_to_epoch() {/,/^}/p' "$CL")"
  eval "$(sed -n '/^fired_peer() {/,/^}/p' "$CL")"
  eval "$(sed -n '/^fired_tenancy_epoch() {/,/^}/p' "$CL")"
  export FIRED_DIR="$CC_FIRED_DIR" FIRED_BOOT_MAX_S=1800
  local started=$(( ( $(date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "2026-09-28T07:20:02Z" +%s) ) * 1000 ))
  printf '{"paneUUID":"%s","cwd":"%s","firedAt":"2026-09-28T05:53:01Z","selfRetire":true}\n' "$PEER" "$PEER_WT" > "$CC_FIRED_DIR/$PEER.json"
  ! fired_peer "$PEER" "$started" "$PEER_WT" || { echo "control: without recycledAt the 87-min tenant must still read stale"; false; }
  printf '{"paneUUID":"%s","cwd":"%s","firedAt":"2026-09-28T05:53:01Z","recycledAt":"2026-09-28T07:19:50Z","selfRetire":true}\n' "$PEER" "$PEER_WT" > "$CC_FIRED_DIR/$PEER.json"
  fired_peer "$PEER" "$started" "$PEER_WT" || { echo "the recycled peer reads as a stale tenant"; false; }
}

@test "the two time oracles read ONE anchor expression (cc-reaper and cc-classify cannot drift apart)" {
  local a b
  a="$(grep -o "jq -r '\[.firedAt, .recycledAt\][^']*'" "$REPO/bin/cc-reaper")"
  b="$(grep -o "jq -r '\[.firedAt, .recycledAt\][^']*'" "$REPO/bin/cc-classify")"
  [ -n "$a" ] && [ "$a" = "$b" ] || { echo "reaper: $a"; echo "classify: $b"; false; }
}

# ── 3. THE FIRER RETIRES ITS PEER: self-close --fired-peer ───────────────────────────────────────

peer_stamp() { # [firedBy] [extra-json]
  jq -nc --arg p "$PEER" --arg c "$PEER_WT" --arg by "${1:-$FIRER}" --arg m "$ENGAGE" --argjson x "${2:-{\}}" \
    '{paneUUID:$p, cwd:$c, firedBy:$by, firedAt:"2026-09-28T05:53:01Z", selfRetire:true, schema:2, marker:$m, closedAt:null} + $x' \
    > "$CC_FIRED_DIR/$PEER.json"
}
as_firer() { # the CALLER is pane $FIRER, and its identity is PROVEN (ancestry tty = its pane's tty)
  export ITERM_SESSION_ID="w0t0p0:$FIRER" PS_TTY_OUT="TTY-$FIRER" CC_CLOSE_LEDGER_GUARD=0
  FIRER_WT="$BATS_TEST_TMPDIR/firer-wt"; mkdir -p "$FIRER_WT"; cd "$FIRER_WT" || return 1
}
peer_ready() { peer_stamp; row "$PEER" "$SID_NOW" "$PEER_WT"; transcript "$SID_NOW" "$(recycle_brief)" "2026-09-28T07:20:03.850Z"; }
retire() { run bash "$HF" self-close --fired-peer "$PEER" "$@"; }

@test "firer-retire: the pane that FIRED an idle, clean, landed peer is AUTHORIZED to retire it" {
  peer_ready; as_firer
  retire --terminal --dry-run
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"firer-retire AUTHORIZED: pane $PEER was fired by THIS pane $FIRER"* ]] || { echo "$output"; false; }
  [[ "$output" == *"pane:      $PEER"* ]] || { echo "the close is not aimed at the PEER: $output"; false; }
  [[ "$output" == *"retired by: its firer, pane $FIRER"* ]] || { echo "$output"; false; }
  [[ "$output" != *"--allow-origin-close"* ]] || { echo "$output"; false; }
}

@test "firer-retire CONTROL (the 845 refusal, unchanged): --session-id on another pane is still refused by ancestry" {
  peer_ready; as_firer
  run bash "$HF" self-close --session-id "$PEER" --terminal --dry-run
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [[ "$output" == *"ASSERTION BY THE CALLER"* ]] || { echo "$output"; false; }
}

@test "firer-retire REFUSED: not mine — the stamp names a DIFFERENT firer" {
  peer_stamp "99900000-0000-4000-8000-000000000999"; row "$PEER" "$SID_NOW" "$PEER_WT"
  transcript "$SID_NOW" "$(recycle_brief)" "2026-09-28T07:20:03.850Z"; as_firer
  retire --terminal --dry-run
  [ "$status" -eq 2 ]; [[ "$output" == *"was NOT fired by this pane"* ]] || { echo "$output"; false; }
  [[ "$output" != *"AUTHORIZED"* ]]
}

@test "firer-retire REFUSED: no stamp at all (ownership cannot be proven), and it names the peer-side repair" {
  row "$PEER" "$SID_NOW" "$PEER_WT"; transcript "$SID_NOW" "$(recycle_brief)" "2026-09-28T07:20:03.850Z"; as_firer
  retire --terminal --dry-run
  [ "$status" -eq 2 ]; [[ "$output" == *"has no fired-peer stamp"* ]] || { echo "$output"; false; }
  [ ! -e "$CC_FIRED_DIR/$PEER.json" ] || { echo "the firer path WROTE a stamp it then read"; false; }
}

@test "firer-retire REFUSED: a turn is IN FLIGHT in the peer" {
  peer_stamp; row "$PEER" "$SID_NOW" "$PEER_WT"
  transcript "$SID_NOW" "$(recycle_brief)" "2026-09-28T07:20:03.850Z" busy; as_firer
  retire --terminal --dry-run
  [ "$status" -eq 2 ]; [[ "$output" == *"turn IN FLIGHT"* ]] || { echo "$output"; false; }
}

@test "firer-retire REFUSED: the peer's worktree is DIRTY (the guard reads the PEER's tree, not the firer's)" {
  peer_ready; as_firer
  rm -f "$PEER_WT/.GITCLEAN"; : > "$PEER_WT/.GITDIRTY"
  : > "$FIRER_WT/.GITCLEAN"
  retire --terminal --dry-run
  [ "$status" -eq 1 ]; [[ "$output" == *"dirty git tree in $PEER_WT"* ]] || { echo "$output"; false; }
}

@test "firer-retire REFUSED: the peer has UNLANDED commits (stricter than the self form, which only warns)" {
  peer_ready; as_firer
  echo 2 > "$PEER_WT/.GITAHEAD"
  retire --terminal --dry-run
  [ "$status" -eq 8 ] || { echo "$output"; false; }
  [[ "$output" == *"2 commit(s) on feat/peer NOT landed"* ]] || { echo "$output"; false; }
}

@test "firer-retire REFUSED: the registry row's pid is dead (stale row)" {
  peer_stamp; row "$PEER" "$SID_NOW" "$PEER_WT" 999999
  transcript "$SID_NOW" "$(recycle_brief)" "2026-09-28T07:20:03.850Z"; as_firer
  retire --terminal --dry-run
  [ "$status" -eq 2 ]; [[ "$output" == *"not alive"* ]] || { echo "$output"; false; }
}

@test "firer-retire REFUSED: a SPENT stamp (the peer already retired)" {
  peer_stamp "$FIRER" '{"closedAt":"2026-09-28T09:00:00Z"}'; row "$PEER" "$SID_NOW" "$PEER_WT"
  transcript "$SID_NOW" "$(recycle_brief)" "2026-09-28T07:20:03.850Z"; as_firer
  retire --terminal --dry-run
  [ "$status" -eq 2 ]; [[ "$output" == *"tenancy spent"* ]] || { echo "$output"; false; }
}

@test "firer-retire REFUSED: a --no-self-retire peer (selfRetire false)" {
  peer_stamp "$FIRER" '{"selfRetire":false}'; row "$PEER" "$SID_NOW" "$PEER_WT"
  transcript "$SID_NOW" "$(recycle_brief)" "2026-09-28T07:20:03.850Z"; as_firer
  retire --terminal --dry-run
  [ "$status" -eq 2 ]; [[ "$output" == *"WITHOUT the self-retire contract"* ]] || { echo "$output"; false; }
}

@test "firer-retire REFUSED: the caller's own pane is UNPROVEN (no ancestry answer)" {
  peer_ready; as_firer; unset PS_TTY_OUT
  retire --terminal --dry-run
  [ "$status" -eq 2 ]; [[ "$output" == *"cannot PROVE this process lives in pane $FIRER"* ]] || { echo "$output"; false; }
}

@test "firer-retire REFUSED: no override is admissible with the class (--allow-dirty, --allow-origin-close)" {
  peer_ready; as_firer
  retire --terminal --dry-run --allow-dirty
  [ "$status" -eq 2 ]; [[ "$output" == *"takes --terminal"* ]] || { echo "$output"; false; }
  retire --terminal --dry-run --allow-origin-close
  [ "$status" -eq 2 ]; [[ "$output" == *"takes --terminal"* ]] || { echo "$output"; false; }
}

@test "firer-retire REFUSED: --terminal is required" {
  peer_ready; as_firer
  retire --dry-run
  [ "$status" -eq 2 ]; [[ "$output" == *"pass --terminal"* ]] || { echo "$output"; false; }
}

@test "firer-retire REFUSED: naming THIS pane" {
  peer_ready; as_firer
  run bash "$HF" self-close --fired-peer "$FIRER" --terminal --dry-run
  [ "$status" -eq 2 ]; [[ "$output" == *"that is THIS pane"* ]] || { echo "$output"; false; }
}

@test "firer-retire REFUSED: kill switch CC_FIRER_RETIRE=0" {
  peer_ready; as_firer
  CC_FIRER_RETIRE=0 retire --terminal --dry-run
  [ "$status" -eq 2 ]; [[ "$output" == *"CC_FIRER_RETIRE=0"* ]] || { echo "$output"; false; }
}
