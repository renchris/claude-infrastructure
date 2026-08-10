#!/usr/bin/env bats
# Regression guard for the UNSTAMPED FIRED PEER — handoff-fire.sh, backlog item c163f42390a3.
#
# THE DEFECT. The self-close origin gate's oracle is the fired-peer stamp
# ~/.claude/cc-fired/<pane>.json, written by mark_fired_peer at fire time. But the stamp is
# BOOKKEEPING written by the FIRING process after the fact, while a pane's fired-peer status is a
# FACT about the pane established the moment it ingests a composed brief — and the two come apart
# whenever a fire lands a live, engaged peer and then aborts before its own bookkeeping. The pane is
# then told it is "an ORIGIN session, not a fired peer", which is the strongest possible wrong
# answer: it is a genuine dispatched worker that has finished its item and has no way to retire.
#
# MEASURED, on this repo's own dispatcher, 2026-08-10. cc-dispatch fired item c163f42390a3; the
# session registered at 17:45:49 with {"disposition":"reclaimed","basis":"dispatcher hand-over"};
# 23 seconds LATER the fire exited rc=1 announcing `Closed the untyped pane 165 — NOTHING launched`.
# The pane was neither closed nor nothing — it was already running the item. Corroboration that the
# stamp was never WRITTEN rather than deleted: of the fourteen panes in the filed evidence, the seven
# unstamped ones carry NEITHER <pane>.json NOR <pane>.prompt, and BOTH stamp deleters in cc-reaper
# (clear_fired_marker :560, the stale-tenancy GC :877) remove only the .json and leave the sidecar.
#
# WHAT THIS SUITE PINS, in two halves that fail for different reasons:
#   A. the CONSUMER — fired_contract_in_my_brief re-derives the contract from the session's own FIRST
#      USER MESSAGE, and the origin gate REPAIRS the stamp rather than exempting the close.
#   B. the PRODUCER — fire_cleanup's landed/not-landed discriminator no longer misses a pane whose
#      survival was positively observed before $SPAWNED_PANE was assigned.
#
# THE LOAD-BEARING NEGATIVE is "later-message" below. Both proof tokens appear in the transcript of
# any session that merely DISCUSSES this mechanism — the session that drove this very item quotes the
# self-retire trailer verbatim while investigating it — so a whole-transcript grep would authorise
# every such session to close itself. That test is the mutant control for the first-user-message
# extraction: replace the jq with `grep -qF` over the file and it is the one that goes red.

setup() {
  REPO_SRC="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO_SRC/scripts/handoff-fire.sh"
  command -v jq >/dev/null || skip "jq required"

  # HERMETICITY (M11). Every default in the subject is `${VAR:-$HOME/...}`, so pinning the three
  # explicit dirs below is NOT enough on its own — one unpinned fallback and this suite reads, or
  # writes, the operator's live state. $HOME first, then the seams that do NOT resolve under it:
  # an ABSOLUTE /tmp default and a BARE NAME the subject would execute off the operator's PATH.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_FIRE_CAPACITY_GATE=off      # else handoff-fire refuses by ambient box load, not by subject
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/account-sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/no-such-claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"

  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg"
  export CC_FIRED_DIR="$BATS_TEST_TMPDIR/fired"
  export CC_PROJECTS_DIRS="$BATS_TEST_TMPDIR/projects"
  mkdir -p "$CC_REGISTRY_DIR" "$CC_FIRED_DIR" "$CC_PROJECTS_DIRS"

  PANE="AAAABBBB-1111-2222-3333-444455556666"
  SID="deadbeef-0000-1111-2222-333344445555"
  printf '{"paneUUID":"%s","session_id":"%s","cwd":"%s"}\n' "$PANE" "$SID" "$PWD" \
    > "$CC_REGISTRY_DIR/$PANE.json"

  # The trailer heading is read from the SCRIPT, never retyped here. A test carrying its own copy of
  # the subject's constant is a control calibrated to today's implementation: the heading could change
  # on both sides and this suite would keep passing over a string nothing emits any more
  # (memory: control-calibrated-to-implementation-decays).
  HEADING="$(sed -n "s/^SELF_RETIRE_CONTRACT_HEADING='\(.*\)'$/\1/p" "$HF" | head -1)"
  [ -n "$HEADING" ] || { echo "could not read SELF_RETIRE_CONTRACT_HEADING from $HF"; return 1; }
  MARKER="HANDOFF-ENGAGE-4242-1786383932-7"
}

# write_transcript <first-user-text> [later-user-text] — a minimal CC transcript for $SID.
#
# THE FIXTURE WRITES THE NESTED LAYOUT, AND THAT IS THE POINT. Claude Code stores transcripts at
# <root>/projects/<project-slug>/<sid>.jsonl — counted on this box, 0 flat vs 3148 nested. Every
# lookup here used to test `$pdir/<sid>.jsonl` directly and therefore matched nothing in production,
# while its suites passed because their fixtures wrote the flat path the code was looking for. A
# fixture that agrees with the bug proves the bug (memory: control-must-replay-the-real-artifact).
# The "flat layout" test below is the control that keeps the fast path honest.
TJ_DIR() { printf '%s/-Users-chrisren-Development-fixture' "$CC_PROJECTS_DIRS"; }
write_transcript() {
  local first="$1" later="${2:-}"
  mkdir -p "$(TJ_DIR)"
  : > "$(TJ_DIR)/$SID.jsonl"
  # An isMeta turn FIRST, so the suite also pins that the extraction skips the harness's own injected
  # context blocks — ".[0]" must be the BRIEF, not a SessionStart hook's payload.
  jq -nc --arg t "session context injected by a hook" \
    '{type:"user", isMeta:true, message:{content:$t}}' >> "$(TJ_DIR)/$SID.jsonl"
  jq -nc --arg t "$first" '{type:"user", message:{content:$t}}' >> "$(TJ_DIR)/$SID.jsonl"
  jq -nc '{type:"assistant", message:{content:[{type:"text",text:"working"}]}}' >> "$(TJ_DIR)/$SID.jsonl"
  [ -n "$later" ] && jq -nc --arg t "$later" '{type:"user", message:{content:$t}}' >> "$(TJ_DIR)/$SID.jsonl"
  return 0
}

load_proof_fn() {
  eval "$(sed -n '/^cc_sid_for_pane() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^transcript_for_sid() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^fired_contract_in_my_brief() {/,/^}/p' "$HF")"
  SELF_RETIRE_CONTRACT_HEADING="$HEADING"
}

# ── A. the CONSUMER: what counts as proof ────────────────────────────────────────────────────────

@test "proof: trailer + marker in the FIRST user message ⇒ fired peer, marker captured" {
  load_proof_fn
  write_transcript "TASK — drive the item.

$HEADING
  1. DRIVE any trivial step to a clean terminal state.

<!-- handoff-fire engagement marker: $MARKER (ignore) -->"
  fired_contract_in_my_brief "$PANE" || { echo "a genuine fired brief was REFUSED"; false; }
  [ "$FCB_MARKER" = "$MARKER" ] || { echo "marker not captured: '$FCB_MARKER'"; false; }
  [ -z "$FCB_NOTIFYBACK" ] || { echo "invented a back-channel: '$FCB_NOTIFYBACK'"; false; }
}

@test "proof: the brief's BACK-CHANNEL address is carried out for the repaired stamp" {
  # This is what makes the repair strictly better than --allow-origin-close, which the filed item
  # names as closing "without pinging any originator, which is exactly what the stamp encodes".
  load_proof_fn
  write_transcript "TASK — drive the item.

## BACK-CHANNEL — ping the originator (ORIGIN-PANE-77)
On completion, ping the session that fired this handoff.

$HEADING
  1. DRIVE any trivial step.

<!-- handoff-fire engagement marker: $MARKER (ignore) -->"
  fired_contract_in_my_brief "$PANE"
  [ "$FCB_NOTIFYBACK" = "ORIGIN-PANE-77" ] || { echo "back-channel not recovered: '$FCB_NOTIFYBACK'"; false; }
}

@test "proof REFUSED: the self-retire trailer ALONE (a pasted bridge carries no fire marker)" {
  load_proof_fn
  write_transcript "TASK — do the thing.

$HEADING
  1. DRIVE any trivial step."
  ! fired_contract_in_my_brief "$PANE" || { echo "the trailer alone authorised a close"; false; }
}

@test "proof REFUSED: a fire marker ALONE (every --no-self-retire fire carries one)" {
  # The polarity that matters: --no-self-retire exists precisely so a fired pane may NOT retire, and
  # it still gets an engagement marker. Marker-only must therefore never be sufficient.
  load_proof_fn
  write_transcript "TASK — do the thing, and do not retire.

<!-- handoff-fire engagement marker: $MARKER (ignore) -->"
  ! fired_contract_in_my_brief "$PANE" || { echo "a --no-self-retire fire authorised its own close"; false; }
}

@test "proof REFUSED: both tokens present, but only in a LATER message (the discussion case)" {
  # THE MUTANT CONTROL. Swap the first-user-message jq for a whole-transcript grep and this is the
  # test that goes red — every session investigating this mechanism quotes both tokens.
  load_proof_fn
  write_transcript "Please look into why dispatched panes cannot self-close." \
                   "I found it. The brief carries:

$HEADING

and <!-- handoff-fire engagement marker: $MARKER (ignore) -->"
  ! fired_contract_in_my_brief "$PANE" \
    || { echo "a session that merely DISCUSSED the contract was granted it"; false; }
}

@test "proof REFUSED: the kill switch CC_SELFCLOSE_BRIEF_CONTRACT=0" {
  load_proof_fn
  write_transcript "TASK.

$HEADING

<!-- handoff-fire engagement marker: $MARKER (ignore) -->"
  CC_SELFCLOSE_BRIEF_CONTRACT=0 fired_contract_in_my_brief "$PANE" \
    && { echo "the R8 kill switch did not disable the path"; false; } || true
}

@test "proof REFUSED: no transcript for this pane (nothing was asked ⇒ nothing is proven)" {
  load_proof_fn
  ! fired_contract_in_my_brief "$PANE" || { echo "proved a contract with no transcript at all"; false; }
}

# ── the LAYOUT the resolver must actually survive ────────────────────────────────────────────────

@test "layout: transcript_for_sid finds the NESTED path CC really writes" {
  # 0 flat vs 3148 nested, counted across all five account roots on this box. This is the assertion
  # whose absence let every marker-proof chain in this file be inert in production for as long as it
  # existed — adoption and the spent-stamp retry arm included — while their suites stayed green.
  eval "$(sed -n '/^transcript_for_sid() {/,/^}/p' "$HF")"
  mkdir -p "$(TJ_DIR)"; : > "$(TJ_DIR)/$SID.jsonl"
  [ "$(transcript_for_sid "$SID")" = "$(TJ_DIR)/$SID.jsonl" ] \
    || { echo "nested transcript NOT found — the real layout is unreachable"; false; }
}

@test "layout: the FLAT fast path still resolves, and is preferred" {
  # The one stat that costs nothing. Keeping it is what makes the find a fallback rather than a
  # replacement, so no caller or fixture that really is flat changes behaviour.
  eval "$(sed -n '/^transcript_for_sid() {/,/^}/p' "$HF")"
  : > "$CC_PROJECTS_DIRS/$SID.jsonl"
  mkdir -p "$(TJ_DIR)"; : > "$(TJ_DIR)/$SID.jsonl"
  [ "$(transcript_for_sid "$SID")" = "$CC_PROJECTS_DIRS/$SID.jsonl" ] \
    || { echo "flat path not preferred: $(transcript_for_sid "$SID")"; false; }
}

@test "layout: an unknown sid resolves to NOTHING, and a sid can never be a path fragment" {
  eval "$(sed -n '/^transcript_for_sid() {/,/^}/p' "$HF")"
  [ -z "$(transcript_for_sid "no-such-session")" ] || { echo "invented a transcript"; false; }
  [ -z "$(transcript_for_sid "../../etc/passwd")" ] || { echo "a sid escaped its directory"; false; }
}

@test "layout: fired_marker_is_mine (adoption's proof) works over the NESTED layout too" {
  # The pre-existing caller. Its breakage is why the origin gate's adoption path and its spent-stamp
  # retry arm could never fire — the same one-level-too-shallow lookup, in the function whose header
  # calls the transcript "the PROOF channel".
  eval "$(sed -n '/^cc_sid_for_pane() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^transcript_for_sid() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^fired_marker_is_mine() {/,/^}/p' "$HF")"
  write_transcript "TASK.

<!-- handoff-fire engagement marker: $MARKER (ignore) -->"
  fired_marker_is_mine "$MARKER" "$PANE" || { echo "adoption's proof channel is inert"; false; }
  ! fired_marker_is_mine "HANDOFF-ENGAGE-someone-else" "$PANE" \
    || { echo "proved a marker that is not in the transcript"; false; }
}

# ── the REPAIR itself: the stamp the fire owed is written, and marked as a repair ─────────────────

@test "repair: an absent stamp is WRITTEN from the brief, flagged repairedFrom, tenancy VALID" {
  eval "$(sed -n '/^_iso_now() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^mark_fired_peer() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^fired_stamp_tenancy() {/,/^}/p' "$REPO_SRC/hooks/lib/origin-identity.sh")"
  [ ! -e "$CC_FIRED_DIR/$PANE.json" ] || { echo "fixture already stamped — the test proves nothing"; false; }

  FIRE_MARKER="$MARKER" NB_ARMED_TARGET="ORIGIN-PANE-77"
  mark_fired_peer "$CC_FIRED_DIR" "$PANE" "$PWD" "" ""
  jq --arg at "$(_iso_now)" '. + {repairedAt:$at, repairedFrom:"brief-contract"}' \
     "$CC_FIRED_DIR/$PANE.json" > "$BATS_TEST_TMPDIR/r.json"
  mv -f "$BATS_TEST_TMPDIR/r.json" "$CC_FIRED_DIR/$PANE.json"

  [ "$(jq -r .selfRetire   "$CC_FIRED_DIR/$PANE.json")" = true ]          || { echo "not a self-retiring record"; false; }
  [ "$(jq -r .originClass  "$CC_FIRED_DIR/$PANE.json")" = fired-peer ]    || { echo "wrong originClass"; false; }
  [ "$(jq -r .marker       "$CC_FIRED_DIR/$PANE.json")" = "$MARKER" ]     || { echo "marker not recorded"; false; }
  [ "$(jq -r .notifyBack   "$CC_FIRED_DIR/$PANE.json")" = "ORIGIN-PANE-77" ] \
    || { echo "back-channel lost ⇒ announce-before-retire cannot enforce the ping"; false; }
  [ "$(jq -r .repairedFrom "$CC_FIRED_DIR/$PANE.json")" = "brief-contract" ] \
    || { echo "a repaired stamp is indistinguishable from one a fire wrote"; false; }
  [ "$(jq -r .closedAt     "$CC_FIRED_DIR/$PANE.json")" = null ]          || { echo "born spent"; false; }
  [ "$(fired_stamp_tenancy "$CC_FIRED_DIR/$PANE.json" "$PWD")" = valid ] \
    || { echo "the repaired stamp does not read VALID to the gate's own oracle"; false; }
}

# ── B. the PRODUCER: fire_cleanup must not mistake a live pane for no pane ────────────────────────

run_cleanup() { ( set +e; false; fire_cleanup ) > "$1" 2>&1 || true; }

@test "cleanup: a pane that SURVIVED its close is registered + stamped, worktree KEPT" {
  # The case measured on item c163f42390a3: restore_focus_or_fail closed the pane, the close did not
  # take, and $SPAWNED_PANE was never assigned — so cleanup took its "no pane landed" arm and queued
  # the worktree for deletion under a live session, leaving it with no row and no stamp.
  eval "$(sed -n '/^ensure_registration() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^mark_fired_peer() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^fire_cleanup() {/,/^}/p' "$HF")"
  local wt="$BATS_TEST_TMPDIR/wt-live"
  mkdir -p "$wt"

  FIRE_CLEAN_DONE=0; FIRE_CLEAN_POOL=""; FIRE_CLEAN_WT="$wt"; FIRE_CLEAN_BRANCH="wt-live"
  REPO="$BATS_TEST_TMPDIR"; SPAWNED_PANE=""; FIRE_LIVE_PANE="$PANE"
  REG_DIR="$CC_REGISTRY_DIR"; FIRED_DIR="$CC_FIRED_DIR"; LAUNCH_DIR="$wt"; CMD="claude"
  FIRING_SID="ORIGIN-PANE"; PROMPT_FILE=""; WANT_SELF_RETIRE=1
  run_cleanup "$BATS_TEST_TMPDIR/live.out"

  [ -f "$CC_FIRED_DIR/$PANE.json" ] \
    || { echo "no stamp ⇒ the live peer can never self-close"; cat "$BATS_TEST_TMPDIR/live.out"; false; }
  [ -d "$wt" ] || { echo "the worktree was removed from under a LIVE pane"; false; }
  grep -q "made VISIBLE" "$BATS_TEST_TMPDIR/live.out"
}

@test "cleanup CONTROL: with neither pane variable set, the no-pane arm still runs" {
  # The fallback must only ever move a case from "destroy the resources" to "keep and stamp them".
  # This is the arm it must not have swallowed: a fire that genuinely landed nothing.
  eval "$(sed -n '/^fire_cleanup() {/,/^}/p' "$HF")"
  local wt="$BATS_TEST_TMPDIR/wt-cold"
  mkdir -p "$wt"

  FIRE_CLEAN_DONE=0; FIRE_CLEAN_POOL=""; FIRE_CLEAN_WT="$wt"; FIRE_CLEAN_BRANCH="wt-cold"
  REPO="$BATS_TEST_TMPDIR"; SPAWNED_PANE=""; FIRE_LIVE_PANE=""
  REG_DIR="$CC_REGISTRY_DIR"; FIRED_DIR="$CC_FIRED_DIR"
  run_cleanup "$BATS_TEST_TMPDIR/cold.out"

  [ ! -f "$CC_FIRED_DIR/$PANE.json" ] || { echo "stamped a pane that was never created"; false; }
  grep -q "fire-cleanup" "$BATS_TEST_TMPDIR/cold.out" \
    || { echo "the no-pane arm did not run at all"; cat "$BATS_TEST_TMPDIR/cold.out"; false; }
}

@test "cleanup: FIRE_FAILED_CLOSE_PANE does NOT re-close a pane that already survived one" {
  # A close that just refused (anchor / not-agent-owned) refuses for a reason that has not changed,
  # and a close that just failed has already been verified as failed. Re-issuing it is noise at best.
  eval "$(sed -n '/^ensure_registration() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^mark_fired_peer() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^fire_cleanup() {/,/^}/p' "$HF")"
  hf_close_pane() { echo "HF_CLOSE_CALLED $1" >&2; return 0; }
  local wt="$BATS_TEST_TMPDIR/wt-noreclose"
  mkdir -p "$wt"

  FIRE_CLEAN_DONE=0; FIRE_CLEAN_POOL=""; FIRE_CLEAN_WT="$wt"; FIRE_CLEAN_BRANCH="wt-noreclose"
  REPO="$BATS_TEST_TMPDIR"; SPAWNED_PANE=""; FIRE_LIVE_PANE="$PANE"
  REG_DIR="$CC_REGISTRY_DIR"; FIRED_DIR="$CC_FIRED_DIR"; LAUNCH_DIR="$wt"; CMD="claude"
  FIRING_SID="ORIGIN-PANE"; PROMPT_FILE=""; WANT_SELF_RETIRE=1; FIRE_FAILED_CLOSE_PANE=1
  run_cleanup "$BATS_TEST_TMPDIR/noreclose.out"

  ! grep -q "HF_CLOSE_CALLED" "$BATS_TEST_TMPDIR/noreclose.out" \
    || { echo "re-closed a pane whose close had already been observed to fail"; false; }
}
