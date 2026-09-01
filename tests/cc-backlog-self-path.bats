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

# ── THE ADMIT PATH: dispatch 24's finding ────────────────────────────────────────────────────────
#
# Everything above instruments the gate being ABSENT. This section instruments the gate being
# PRESENT, which is the branch that actually fires and the one no dispatch had ever recorded.
#
# `cc-eligible check` used to end a non-blocking assessment with `verdict=eligible` on stdout and
# NOTHING on stderr, so three outcomes arrived at bin/cc-backlog as one silence:
#
#   park=none          there is genuinely no park on trunk for this id
#   park=not-measured  the arm could NOT MEASURE — an uncertified (shallow / ref-less) checkout, so
#                      a landed park is UNREAD rather than absent and cannot refuse
#   park=honoured      a park is on trunk and the desk retired it (the interlock working correctly)
#
# Only the middle one is a leak and it looked exactly like the other two. It is candidate (d) of
# docs/research/tenant-drift-venue-refusal-2026-08-24.md §337, listed there with
# `git rev-parse --is-shallow-repository` as its only discriminator — a command somebody has to
# think to run, on the box, at the right moment, about the right repo. `refresh_trunk` fixed the
# ref being STALE; nothing reported the ref being UNCERTIFIABLE.
#
# THE CONTROLS CARRY THE WEIGHT HERE MORE THAN ANYWHERE ABOVE, because the failure mode of a
# "did it speak" assertion is a binary that speaks on every path. So the refused claim, the local
# claim and the skip-only stderr are each asserted to carry NO admit token, in both readers.

# add_plain <bin> [nonce] → an item whose title names nothing local-only, so the gate ADMITS it.
#
# THE NONCE IS LOAD-BEARING, not cosmetic. Two rows with the SAME title are the same WORK to
# cc-backlog's condition lease, so a test that adds two and claims both gets `verdict=sibling-held`
# rc 4 on the second — a correct refusal that never reaches the gate under test. Any test needing a
# second admissible item must give it a distinct one.
add_plain() {
  "$1" add --title "tidy a docstring in the backlog parser ${2:-alpha}" \
      --project probe --source "self-path-admit-$BATS_TEST_NUMBER" 2>/dev/null | tr -d '\n'
}

@test "ADMIT NAMES WHAT IT SAW: a gate that runs and admits reports its park state" {
  # THE REGRESSION TEST for this section. Pre-fix the claim succeeded in total silence.
  local link id; link="$(rel_link)"; id="$(add_plain "$link")"
  [ -n "$id" ] || { echo "add produced no id"; false; }
  cd /
  run "$link" claim "$id" --by cloudvm-20 --venue cloud
  [ "$status" -eq 0 ] || { echo "the gate refused a plain item (rc=$status): $output"; false; }
  [[ "$output" == *"gate=eligibility-admitted"* ]] \
    || { echo "the gate ran and admitted in silence — the defect: $output"; false; }
  # the STATE, not merely the token: a line that always said `park=` and never a value would pass a
  # presence test while answering nothing.
  [[ "$output" =~ park=[a-z-]+ ]] \
    || { echo "no park state on the admit line: $output"; false; }
}

@test "ADMIT: an UNCERTIFIABLE repo reports not-measured, not absence" {
  # The whole reason this section exists. This fixture's project resolves to a directory that is
  # not a git repo at all, so `certify()` cannot succeed and `_park_doc` returns None — the exact
  # shape of a shallow or ref-less checkout on the box. The arm must say it could not look, rather
  # than reporting the same thing it reports when it looked and found nothing.
  local link id; link="$(rel_link)"; id="$(add_plain "$link")"
  cd /
  run "$link" claim "$id" --by cloudvm-21 --venue cloud
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"park=not-measured"* ]] \
    || { echo "an unreadable park is indistinguishable from no park: $output"; false; }
}

@test "ADMIT CONTROL: a REFUSED cloud claim carries no admit token" {
  # Without this, an admit line printed unconditionally would pass every assertion above while
  # journalling "the gate admitted" over the dispatcher's own refusals.
  local link id; link="$(rel_link)"; id="$(add_boxy "$link")"
  cd /
  run "$link" claim "$id" --by cloudvm-22 --venue cloud
  [ "$status" -eq 4 ] || { echo "the control item was not refused (rc=$status): $output"; false; }
  [[ "$output" != *"gate=eligibility-admitted"* ]] || { echo "$output"; false; }
}

@test "ADMIT CONTROL: a --venue local claim carries no gate token at all" {
  # The gate is venue-scoped and must stay so: a local claim is byte-for-byte what it was.
  local link id; link="$(rel_link)"; id="$(add_plain "$link")"
  cd /
  run "$link" claim "$id" --by localbox-20 --venue local
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" != *"gate=eligibility-"* ]] || { echo "$output"; false; }
}

@test "OFF: the kill switch now leaves a RECORD, while still not warning" {
  # EXTENDS the incumbent decision above rather than reversing it. That test pins "an override is
  # not an outage, so it must not WARN", and it still passes untouched: no `SKIPPED` alarm is
  # emitted here. What is added is the machine token alone, because a switched-off gate was
  # otherwise byte-identical on every channel to one that ran and admitted — candidate (a) of
  # tenant-drift-venue-refusal-2026-08-24.md §337, whose only discriminator is a daemon's
  # environment at a moment that has already passed.
  local link id; link="$(rel_link)"; id="$(add_plain "$link")"
  cd /
  run env CC_BACKLOG_ELIGIBLE_GATE=off "$link" claim "$id" --by cloudvm-23 --venue cloud
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"gate=eligibility-disabled"* ]] \
    || { echo "a deliberately disabled gate is still an unrun gate: $output"; false; }
  [[ "$output" != *"eligibility gate SKIPPED"* ]] \
    || { echo "an override was reported as an outage: $output"; false; }
  [[ "$output" != *"gate=eligibility-admitted"* ]] \
    || { echo "a gate that never ran claimed to have admitted: $output"; false; }
}

@test "PRE-TOKEN HELPER: a silent admit is reported as unreported, never as a measurement" {
  # Candidate (c) of that same table — "the cc-eligible actually executed predates the park arm".
  # A helper whose bytes are older than the admit line answers rc 0 and says nothing, which is
  # indistinguishable from a modern helper that measured and found nothing unless the caller says
  # so positively. The stub IS the old contract: line 1 verdict, silence after it.
  printf '#!/bin/bash\necho "verdict=eligible"\nexit 0\n' > "$BATS_TEST_TMPDIR/old-eligible"
  chmod +x "$BATS_TEST_TMPDIR/old-eligible"
  local id; id="$(add_plain "$CB_REAL")"
  cd /
  run env CC_BACKLOG_ELIGIBLE_BIN="$BATS_TEST_TMPDIR/old-eligible" \
      "$CB_REAL" claim "$id" --by cloudvm-24 --venue cloud
  [ "$status" -eq 0 ] || { echo "fail-open lost: $output"; false; }
  [[ "$output" == *"park=unreported"* ]] \
    || { echo "an old helper's silence was passed off as a reading: $output"; false; }
}

# seam_state_lib → claim_gate_state extracted from the real bin/cc-dispatch, same idiom as seam_lib.
seam_state_lib() {
  local out="$BATS_TEST_TMPDIR/seam-state.sh"
  sed -n '/^claim_gate_state()/,/^}/p' "$REPO/bin/cc-dispatch" > "$out"
  grep -q '^claim_gate_state()' "$out" || return 1
  printf '%s' "$out"
}

@test "SEAM: cc-dispatch extracts the ADMIT state from a claim's stderr" {
  local lib; lib="$(seam_state_lib)" || skip "no claim_gate_state in bin/cc-dispatch"
  local link id; link="$(rel_link)"; id="$(add_plain "$link")"
  cd /
  "$link" claim "$id" --by cloudvm-25 --venue cloud >/dev/null 2>"$BATS_TEST_TMPDIR/err"
  run bash -c ". '$lib'; claim_gate_state '$BATS_TEST_TMPDIR/err'"
  [ "$status" -eq 0 ] || { echo "rc=$status"; false; }
  [[ "$output" == *"gate=eligibility-admitted"* ]] \
    || { echo "the dispatcher cannot see what its gate measured: $output"; false; }
  [ "${#output}" -le 200 ] || { echo "unbounded excerpt: ${#output} chars"; false; }
}

@test "SEAM: claim_gate_skip also matches the DISABLED token" {
  # Two causes, one consequence: the park arm was not consulted. A reader that only knew the
  # outage spelling would journal `claimed` over a gate somebody had switched off.
  local lib; lib="$(seam_lib)" || skip "could not extract claim_gate_skip from bin/cc-dispatch"
  local link id; link="$(rel_link)"; id="$(add_plain "$link")"
  cd /
  env CC_BACKLOG_ELIGIBLE_GATE=off "$link" claim "$id" --by cloudvm-26 --venue cloud \
      >/dev/null 2>"$BATS_TEST_TMPDIR/err"
  run bash -c ". '$lib'; claim_gate_skip '$BATS_TEST_TMPDIR/err'"
  [[ "$output" == *"gate=eligibility-disabled"* ]] \
    || { echo "a disabled gate reads as a healthy one: $output"; false; }
}

@test "SEAM CONTROL: the two readers are mutually exclusive on one stderr" {
  # The dispatcher chains them with elif, which is only sound if no single claim can produce both.
  # Asserted on the real artifact in both directions rather than argued from the source.
  local lskip lstate; lskip="$(seam_lib)" || skip "no claim_gate_skip"
  lstate="$(seam_state_lib)" || skip "no claim_gate_state"
  local link id; link="$(rel_link)"; id="$(add_plain "$link")"
  cd /
  # a healthy gate: admit token, no skip token
  "$link" claim "$id" --by cloudvm-27 --venue cloud >/dev/null 2>"$BATS_TEST_TMPDIR/ok-err"
  run bash -c ". '$lskip'; claim_gate_skip '$BATS_TEST_TMPDIR/ok-err'"
  [ -z "$output" ] || { echo "skip reader cried wolf on a healthy gate: $output"; false; }
  # an unresolvable helper: skip token, no admit token
  local id2; id2="$(add_plain "$CB_REAL" bravo)"
  env CC_BACKLOG_ELIGIBLE_BIN="$BATS_TEST_TMPDIR/nope/cc-eligible" \
      "$CB_REAL" claim "$id2" --by cloudvm-28 --venue cloud >/dev/null 2>"$BATS_TEST_TMPDIR/no-err"
  run bash -c ". '$lstate'; claim_gate_state '$BATS_TEST_TMPDIR/no-err'"
  [ -z "$output" ] || { echo "a skipped gate reported a measurement: $output"; false; }
}

@test "SEAM: the rc-0 path JOURNALS the admit — what the arm saw reaches a store" {
  # The same structural assertion the skip record earned, for the same reason: reaching this line
  # in a live pass needs a whole fixture fleet, and the defect was never a missing word but a
  # capture ordered AFTER the only copy of the stderr is destroyed.
  local src="$REPO/bin/cc-dispatch"
  local cap rm_ln
  cap="$(grep -n 'cgate="\$(claim_gate_state' "$src" | head -1 | cut -d: -f1)"
  rm_ln="$(grep -n 'rm -f "\$cerrf"' "$src" | head -1 | cut -d: -f1)"
  [ -n "$cap" ] || { echo "the admit state is never captured from the claim's stderr"; false; }
  [ -n "$rm_ln" ] || { echo "could not locate the cerrf cleanup"; false; }
  [ "$cap" -lt "$rm_ln" ] || { echo "captured at line $cap, AFTER the rm at $rm_ln"; false; }
  grep -q 'admission gate RAN' "$src" \
    || { echo "the state is captured and never journalled — dropped exactly as before"; false; }
  # and it must be the ALTERNATIVE to the skip record, never a second unconditional one
  grep -q 'elif \[ -n "\$cgate" \]' "$src" \
    || { echo "the two records are not exclusive — a skipped gate could journal both"; false; }
}
