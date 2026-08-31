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
