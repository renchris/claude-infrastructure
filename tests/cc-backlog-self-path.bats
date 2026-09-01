#!/usr/bin/env bats
# cc-backlog SELF-PATH — the co-versioned sibling must resolve through the deploy layer's own
# symlink shape, and a gate that cannot resolve its helper must SAY SO.
#
# THE DEFECT THIS SUITE PINS, reproduced 2026-08-31 while diagnosing backlog `e981656df348`
# (twenty-two dispatches of one row whose cure landed on 08-25). Three sites in bin/cc-backlog
# resolved $0 as:
#
#     s="$0"; [ -L "$s" ] && s="$(readlink "$s")"
#     bin="$(cd "$(dirname "$s")" 2>/dev/null && pwd)/<sibling>"
#
# `readlink` without `-f` returns the target VERBATIM, and a relative target is relative to the
# LINK'S directory — but the `cd` runs from the process's cwd. Production invokes this file as
# $HOME/.claude/bin/cc-backlog and that layer is per-file symlinks into the checkout
# (.claude/CLAUDE.md), so a target like `../../Development/claude-infrastructure/bin/cc-backlog`
# makes the `cd` fail, `$( )` collapse to "", and the sibling resolve to `/cc-eligible`.
#
# WHY IT IS WORTH A SUITE RATHER THAN A ONE-LINE FIX. The eligibility gate's response to an
# unresolvable helper is `[ -x "$ebin" ]` false ⇒ skip, which is the CORRECT fail-open (the
# predicate lives outside the ledger fold). But it was silent, so a skipped gate was
# indistinguishable from a gate that ran and admitted — including bin/cc-eligible's park arm, the
# one interlock built to stop a re-dispatch loop. The bug and its own diagnostic were the same
# blind spot, which is why the report below is asserted as behaviour and not left to a comment.
#
# THE CONTROLS ARE THE POINT (memory: control-must-replay-the-real-artifact). A suite that only
# proved "the relative link works now" would pass just as happily against a gate that had been
# deleted outright, or against one wired to refuse everything. So:
#   · every refusal case is paired with a `--venue local` control that must still ADMIT, and
#   · the ABSOLUTE-symlink case — the shape that always worked — is asserted too, so a regression
#     that broke resolution generally cannot hide behind a green relative-link test, and
#   · the no-helper case asserts rc 0 (fail-open preserved), never just the warning text.

setup() {
  export CC_BACKLOG_PROJECT_WARN=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_BACKLOG_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  printf '#!/bin/bash\necho "[]"\n' > "$BATS_TEST_TMPDIR/nosess"; chmod +x "$BATS_TEST_TMPDIR/nosess"
  export CC_BACKLOG_SESSIONS_BIN="$BATS_TEST_TMPDIR/nosess"
  # `add` ends in dispatch_kick(), whose kick_bin() consults $PATH BEFORE $HOME — so owning $HOME
  # does NOT stop this suite spawning the operator's DEPLOYED cc-dispatch, which would inherit these
  # fixtures and journal test decisions into the production idl.jsonl. All three are pinned rather
  # than just the switch, so a future test that turns the mechanism back on for a positive control
  # still cannot reach live state (tests/cc-backlog-needs.bats:38-40 is the pattern).
  export CC_BACKLOG_KICK=off
  export CC_BACKLOG_KICK_MARKER="$BATS_TEST_TMPDIR/.dispatch-kick"
  export CC_BACKLOG_KICK_BIN="$BATS_TEST_TMPDIR/no-such-dispatch"

  # A FAKE DEPLOY LAYER with the real production shape: bin/ is the checkout, live/ holds per-file
  # symlinks into it. Copies rather than links to the real bin/, so the link SHAPE under test is the
  # only variable and the suite cannot be fooled by however this checkout itself is arranged.
  CKO="$BATS_TEST_TMPDIR/checkout/bin"; LIVE="$BATS_TEST_TMPDIR/live/bin"
  mkdir -p "$CKO" "$LIVE"
  cp "$REPO/bin/cc-backlog" "$REPO/bin/cc-eligible" "$CKO/"
  CB_REAL="$CKO/cc-backlog"
}

# rel_link → $LIVE/cc-backlog as a RELATIVE per-file symlink into the fake checkout.
rel_link() {
  ( cd "$LIVE" && ln -sf ../../checkout/bin/cc-backlog cc-backlog )
  printf '%s' "$LIVE/cc-backlog"
}

# abs_link → the same, ABSOLUTE. The shape that always worked; the positive control.
abs_link() {
  ln -sf "$CB_REAL" "$LIVE/cc-backlog"
  printf '%s' "$LIVE/cc-backlog"
}

# add_boxy <bin> → the id of an item whose TITLE names local-only state, so bin/cc-eligible refuses
# it for --venue cloud on a pure spelling class. Chosen deliberately over a park fixture: this arm
# needs no git repo at all, so the assertion is about whether the helper RAN, never about whether a
# horizon could be certified.
add_boxy() {
  "$1" add --title "restart the launchd daemon and re-read its plist" \
      --project probe --source "self-path-$BATS_TEST_NUMBER" 2>/dev/null | tr -d '\n'
}

@test "RELATIVE LINK: the gate still runs — claim --venue cloud is refused from an unrelated cwd" {
  # THE REGRESSION TEST. Pre-fix this claimed rc 0: readlink yielded the relative target, the cd
  # from $BATS_TEST_TMPDIR failed, and ebin became `/cc-eligible`.
  local link id; link="$(rel_link)"; id="$(add_boxy "$link")"
  [ -n "$id" ] || { echo "add produced no id"; false; }
  cd /
  run "$link" claim "$id" --by cloudvm-1 --venue cloud
  [ "$status" -eq 4 ] || { echo "gate did not run (rc=$status): $output"; false; }
  [[ "$output" == *"verdict=cloud-ineligible"* ]] || { echo "$output"; false; }
}

@test "RELATIVE LINK CONTROL: the same item still claims fine with --venue local" {
  # Separates "the helper resolves" from "the gate refuses everything". The gate is venue-scoped;
  # local is exactly where a box-only row must stay claimable.
  local link id; link="$(rel_link)"; id="$(add_boxy "$link")"
  cd /
  run "$link" claim "$id" --by localbox-1 --venue local
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" != *"cloud-ineligible"* ]] || { echo "$output"; false; }
}

@test "ABSOLUTE LINK: the shape that always worked still works" {
  # The positive control for the fix itself. Without it, a self_path() that returned garbage for
  # BOTH shapes could still be reported green by a suite that only knew about relative links.
  local link id; link="$(abs_link)"; id="$(add_boxy "$link")"
  cd /
  run "$link" claim "$id" --by cloudvm-2 --venue cloud
  [ "$status" -eq 4 ] || { echo "$output"; false; }
  [[ "$output" == *"verdict=cloud-ineligible"* ]] || { echo "$output"; false; }
}

@test "CHAIN: a link to a link resolves to the real file, not the intermediate" {
  # The single `readlink` stopped at one hop. ~/.claude/bin entries have been re-pointed through an
  # intermediate before; one hop is an assumption about the deploy layer, not a property of it.
  mkdir -p "$BATS_TEST_TMPDIR/hop"
  ( cd "$BATS_TEST_TMPDIR/hop" && ln -sf ../checkout/bin/cc-backlog hop1 )
  ( cd "$LIVE" && ln -sf ../../hop/hop1 cc-backlog )
  local link="$LIVE/cc-backlog" id; id="$(add_boxy "$link")"
  cd /
  run "$link" claim "$id" --by cloudvm-3 --venue cloud
  [ "$status" -eq 4 ] || { echo "chain not walked (rc=$status): $output"; false; }
  [[ "$output" == *"verdict=cloud-ineligible"* ]] || { echo "$output"; false; }
}

@test "DIRECT: an unlinked invocation is unaffected" {
  # $0 is not a symlink at all here — the loop must be a no-op, not a mangling.
  local id; id="$(add_boxy "$CB_REAL")"
  cd /
  run "$CB_REAL" claim "$id" --by cloudvm-4 --venue cloud
  [ "$status" -eq 4 ] || { echo "$output"; false; }
}

@test "FAILS OPEN, BUT NAMES ITSELF: an unresolvable helper admits the claim and says so" {
  # Both halves in one test on purpose: they are one property. Fail-open alone was the incumbent
  # behaviour and is what let 22 dispatches happen unrecorded; a warning that came with a refusal
  # would starve the claim path this file's own header forbids starving.
  local id; id="$(add_boxy "$CB_REAL")"
  cd /
  run env CC_BACKLOG_ELIGIBLE_BIN="$BATS_TEST_TMPDIR/nope/cc-eligible" \
      "$CB_REAL" claim "$id" --by cloudvm-5 --venue cloud
  [ "$status" -eq 0 ] || { echo "an unresolvable helper starved the claim: $output"; false; }
  [[ "$output" == *"eligibility gate SKIPPED"* ]] \
    || { echo "skipped in silence — the defect this suite exists for: $output"; false; }
}

@test "QUIET ON THE NORMAL PATH: a resolvable helper emits no skip warning" {
  # An alarm that fires on every cloud claim is one a reader learns to skip.
  local link id; link="$(rel_link)"; id="$(add_boxy "$link")"
  cd /
  run "$link" claim "$id" --by cloudvm-6 --venue cloud
  [[ "$output" != *"eligibility gate SKIPPED"* ]] || { echo "$output"; false; }
}

@test "OFF: the kill switch still skips the gate entirely, and silently" {
  # CC_BACKLOG_ELIGIBLE_GATE=off is a deliberate override, not an outage — it must not warn.
  local link id; link="$(rel_link)"; id="$(add_boxy "$link")"
  cd /
  run env CC_BACKLOG_ELIGIBLE_GATE=off "$link" claim "$id" --by cloudvm-7 --venue cloud
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" != *"eligibility gate SKIPPED"* ]] || { echo "$output"; false; }
}

# ── THE DISPATCHER SEAM: the warning must survive its only production caller ──────────────────────
#
# THE TWENTY-THIRD DISPATCH'S FINDING. The suite above proves bin/cc-backlog NAMES an unresolvable
# helper. It does not prove anyone HEARS it, and the fix landed into a caller that drops it.
#
# bin/cc-dispatch runs the claim as `"$backlog" claim … >/dev/null 2>"$cerrf"`, reads $cerrf through
# claim_excerpt into $cexc, `rm -f`s the file on the next line, and then routes $cexc ONLY through
# arms guarded by `[ "$crc" -eq 4 ]` / `[ "$crc" -ne 0 ]`. A SKIPPED gate fails OPEN — rc 0 — which
# is precisely the exit code on which $cexc is computed and discarded. So the one sentence that says
# "the park arm never ran" is emitted on the only path that deletes it, and the IDL records a plain
# `claimed`.
#
# That is the 22nd dispatch's own lesson unclosed: a reader that cannot report its own absence is
# not a reader — and reporting to a channel the caller drops is the same absence one layer out.
#
# DISCRIMINATED ON A TOKEN, NEVER ON THE ENGLISH. `gate=eligibility-unresolved` is the machine half
# of the warning; the prose beside it is for a human and may be reworded. A latch that greps the
# sentence would re-break on the first rewording, which is the defect bin/cc-dispatch's own
# `claim_excerpt` header (and cloud-return.sh step 8) already names.
#
# Extracted with `sed` and sourced, the seam pattern tests/cc-backlog-condition-lease.bats:257
# established: the function is the contract, and running a whole dispatch pass to reach it would
# test the pass instead.

seam_lib() {
  local out="$BATS_TEST_TMPDIR/seam.sh"
  sed -n '/^claim_gate_skip()/,/^}/p' "$REPO/bin/cc-dispatch" > "$out"
  grep -q '^claim_gate_skip()' "$out" || return 1
  printf '%s' "$out"
}

@test "SEAM: the skip warning carries a machine token, not just prose" {
  local id; id="$(add_boxy "$CB_REAL")"
  cd /
  run env CC_BACKLOG_ELIGIBLE_BIN="$BATS_TEST_TMPDIR/nope/cc-eligible" \
      "$CB_REAL" claim "$id" --by cloudvm-8 --venue cloud
  [ "$status" -eq 0 ] || { echo "fail-open lost: $output"; false; }
  [[ "$output" == *"gate=eligibility-unresolved"* ]] \
    || { echo "no token — the caller can only latch on English: $output"; false; }
}

@test "SEAM: cc-dispatch extracts the skip from a claim's stderr" {
  local lib; lib="$(seam_lib)" || skip "could not extract claim_gate_skip from bin/cc-dispatch"
  # The REAL artifact, not a hand-typed approximation of it (memory:
  # control-must-replay-the-real-artifact): drive cc-backlog to produce the stderr under test.
  local id; id="$(add_boxy "$CB_REAL")"
  cd /
  env CC_BACKLOG_ELIGIBLE_BIN="$BATS_TEST_TMPDIR/nope/cc-eligible" \
      "$CB_REAL" claim "$id" --by cloudvm-9 --venue cloud >/dev/null 2>"$BATS_TEST_TMPDIR/err"
  run bash -c ". '$lib'; claim_gate_skip '$BATS_TEST_TMPDIR/err'"
  [ "$status" -eq 0 ] || { echo "rc=$status"; false; }
  [[ "$output" == *"gate=eligibility-unresolved"* ]] \
    || { echo "the dispatcher cannot see its own gate's absence: $output"; false; }
  [ "${#output}" -le 200 ] || { echo "unbounded excerpt: ${#output} chars"; false; }
}

@test "SEAM CONTROL: a clean claim yields no skip record" {
  # Without this, a claim_gate_skip that returned its whole input would pass the test above and
  # journal a gate-skipped record on every successful cloud claim.
  local lib; lib="$(seam_lib)" || skip "could not extract claim_gate_skip from bin/cc-dispatch"
  local link id; link="$(rel_link)"; id="$(add_boxy "$link")"
  cd /
  "$link" claim "$id" --by cloudvm-10 --venue cloud >/dev/null 2>"$BATS_TEST_TMPDIR/err" || true
  run bash -c ". '$lib'; claim_gate_skip '$BATS_TEST_TMPDIR/err'"
  [ -z "$output" ] || { echo "cried wolf on a healthy gate: $output"; false; }
}

@test "SEAM CONTROL: an absent or empty stderr file is silent, not an error" {
  local lib; lib="$(seam_lib)" || skip "could not extract claim_gate_skip from bin/cc-dispatch"
  run bash -c ". '$lib'; claim_gate_skip '$BATS_TEST_TMPDIR/no-such-file'"
  [ "$status" -eq 0 ] || { echo "rc=$status on a missing file"; false; }
  [ -z "$output" ] || { echo "$output"; false; }
  : > "$BATS_TEST_TMPDIR/empty"
  run bash -c ". '$lib'; claim_gate_skip '$BATS_TEST_TMPDIR/empty'"
  [ "$status" -eq 0 ] || { echo "rc=$status on an empty file"; false; }
  [ -z "$output" ] || { echo "$output"; false; }
}

@test "SEAM: the rc-0 path JOURNALS the skip — the arm's absence reaches a store" {
  # The whole point. cc-dispatch must not compute the warning and drop it: a skipped gate is a
  # fail-open ADMIT, so `crc` is 0 and every incumbent consumer of $cexc is unreachable. Asserted
  # against the source because reaching this line in a live pass needs a whole fixture fleet — but
  # asserted STRUCTURALLY, on the guard that was the defect, not on the presence of a word.
  local src="$REPO/bin/cc-dispatch"
  grep -q 'claim_gate_skip' "$src" \
    || { echo "no extractor at all"; false; }
  # the capture must happen BEFORE the stderr file is removed
  local cap rm_ln
  cap="$(grep -n 'cwarn="\$(claim_gate_skip' "$src" | head -1 | cut -d: -f1)"
  rm_ln="$(grep -n 'rm -f "\$cerrf"' "$src" | head -1 | cut -d: -f1)"
  [ -n "$cap" ] || { echo "the warning is never captured from the claim's stderr"; false; }
  [ -n "$rm_ln" ] || { echo "could not locate the cerrf cleanup"; false; }
  [ "$cap" -lt "$rm_ln" ] || { echo "captured at line $cap, AFTER the rm at $rm_ln"; false; }
  # and it must be journalled on a path that is reachable at rc 0
  grep -q 'idl gate-skipped' "$src" \
    || { echo "the skip is captured and never journalled — dropped exactly as before"; false; }
}
