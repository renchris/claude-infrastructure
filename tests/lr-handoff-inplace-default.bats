#!/usr/bin/env bats
# lr-handoff.sh — IN-PLACE IS THE DEFAULT (W11, LIMIT_RECOVER_100P § 10).
#
# Operator's words: "recover split panes in place so we are never at this confused middle case of
# untouched limited original sessions being resumed elsewhere in a new session." The pane IS the
# continuation whenever there is a pane; the bare spawn survives only where there is NOT one.
#
# WHAT THIS SUITE PINS: lrh_resolve_implied_pane — the decision "is there a pane to recycle, and
# which one" — in all five of its outcomes. That function is where the flip can be WRONG in a way
# that matters: picking a pane that belongs to a different live writer, or declining one that was
# right there.
#
# 🚨 WHAT IT DOES NOT PIN, said out loud so nobody reads this file as more coverage than it is:
# the ENABLING CONDITIONS at the call site (--spawn / --print-only / --no-transplant /
# --close-source / no --launch / LR_INPLACE_DEFAULT=off) are a single guarded `if`, and driving each
# through the whole script needs the four-stub fire harness in tests/lr-handoff-close-source.bats.
# The kill switch below is therefore tested at the GUARD, by evaluating the same condition, not by
# firing. A future wave that moves the guard must re-pin it end to end.

setup() {
  # HERMETIC. The resolver itself reads no files, but lr-handoff.sh is INVOKED whole by the last
  # case, and it resolves lr-lib.sh, the registry and the state dir under $HOME — so an unfixtured
  # $HOME runs a test against the operator's live fleet.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export TMPDIR="$BATS_TEST_TMPDIR/tmp"; mkdir -p "$TMPDIR"
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/registry"; mkdir -p "$CC_REGISTRY_DIR"
  export CC_FIRE_CAPACITY_GATE=off CC_FIRE_HEADROOM_GATE=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd -P)"
  LRH="$REPO/scripts/limit-recover/lr-handoff.sh"
  SID=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee
  # Extract the resolver alone. It is a pure decision over one dependency (lr_registry_live_rows),
  # which is stubbed per case below — so the table it reads is owned by the test, never the box.
  sed -n '/^lrh_resolve_implied_pane() {/,/^}/p' "$LRH" > "$BATS_TEST_TMPDIR/resolver.sh"
  [ -s "$BATS_TEST_TMPDIR/resolver.sh" ] || { echo "the resolver did not extract — the subject moved"; false; }
  unset KITTY_WINDOW_ID ITERM_SESSION_ID CLAUDE_CODE_SESSION_ID
}

# $1 = rows the registry stub returns (TSV pane\tpid\tacct\tcwd), "" for none
_resolve() {
  local rows="$1"; shift
  SOURCE_PANE="${SOURCE_PANE:-}"
  # shellcheck disable=SC1091
  . "$BATS_TEST_TMPDIR/resolver.sh"
  lr_registry_live_rows() { [ -n "$rows" ] || return 1; printf '%s\n' "$rows"; }
  lrh_resolve_implied_pane
}

@test "resolve: an explicitly named --source-pane is the answer, and the registry is not consulted" {
  SOURCE_PANE=417
  run bash -c 'set -e; . "$1"; lr_registry_live_rows() { echo "SHOULD-NOT-BE-CALLED	1	a	/x"; }; SID=s; SOURCE_PANE=417; lrh_resolve_implied_pane; echo "pane=$SOURCE_PANE"' _ "$BATS_TEST_TMPDIR/resolver.sh"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"pane=417"* ]] || { echo "$output"; false; }
}

@test "resolve: SELF — this process IS the session and sits in a pane, so no pane id is needed" {
  # The self-recycle form. lr-handoff's in-place block already spells this case
  # '${SOURCE_PANE:-<this pane>}', so an empty SOURCE_PANE with rc 0 is the correct answer, not a
  # failure to resolve. This is also the ONE question where the caller's own env is the right
  # subject — it is asking about itself.
  run bash -c 'set -e; . "$1"; SID=s; CLAUDE_CODE_SESSION_ID=s; KITTY_WINDOW_ID=198; SOURCE_PANE=""; lrh_resolve_implied_pane; echo "rc=0 pane=[$SOURCE_PANE]"' _ "$BATS_TEST_TMPDIR/resolver.sh"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"pane=[]"* ]] || { echo "$output"; false; }
}

@test "resolve: DRIVER — exactly one live registry row names the pane" {
  run bash -c 'set -e; . "$1"; SID=s; SOURCE_PANE=""; lr_registry_live_rows() { printf "126\t4242\tclaude-next\t/w\n"; }; lrh_resolve_implied_pane; echo "pane=$SOURCE_PANE"' _ "$BATS_TEST_TMPDIR/resolver.sh"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"pane=126"* ]] || { echo "$output"; false; }
}

@test "resolve: TWO live rows is REFUSED, never guessed — that is the DUPLICATE state" {
  # The case that protects a live writer. Two rows is not a pane to pick: recycling one of them
  # types /exit into a session somebody else is still using. lr-fleet --duplicates owns that
  # resolution, and the refusal says so.
  run bash -c '. "$1"; SID=s; SOURCE_PANE=""; lr_registry_live_rows() { printf "126\t1\ta\t/w\n150\t2\ta\t/w\n"; }; lrh_resolve_implied_pane; echo "rc=$?"' _ "$BATS_TEST_TMPDIR/resolver.sh"
  [[ "$output" == *"rc=1"* ]] || { echo "$output"; false; }
  [[ "$output" == *"ambiguous"* || "$output" == *"live registry rows"* ]] || { echo "refused without naming why: $output"; false; }
}

@test "resolve: NO live row is rc 1 — the NO-PANE fallback, the one case a spawn is still right for" {
  run bash -c '. "$1"; SID=s; SOURCE_PANE=""; lr_registry_live_rows() { return 1; }; lrh_resolve_implied_pane; echo "rc=$?"' _ "$BATS_TEST_TMPDIR/resolver.sh"
  [[ "$output" == *"rc=1"* ]] || { echo "$output"; false; }
}

@test "guard: LR_INPLACE_DEFAULT=off keeps spawn-by-default; --spawn and --in-place are exclusive" {
  # The guard's own terms, evaluated as the script evaluates them. Not a substitute for an
  # end-to-end fire (see the header) — it pins that the kill switch is IN the condition and that the
  # two dispositions cannot both be asked for.
  run bash -c 'IN_PLACE=0 SPAWN=0 LAUNCH=1 PRINT_ONLY=0 NO_TRANSPLANT=0 CLOSE_SOURCE=0 LR_INPLACE_DEFAULT=off
    if [[ $IN_PLACE -ne 1 && $SPAWN -ne 1 && $LAUNCH -eq 1 && $PRINT_ONLY -ne 1 && $NO_TRANSPLANT -ne 1 && $CLOSE_SOURCE -ne 1 && "${LR_INPLACE_DEFAULT:-on}" != off ]]; then echo IMPLIED; else echo SPAWN; fi'
  [[ "$output" == *"SPAWN"* ]] || { echo "$output"; false; }
  run bash "$LRH" --sid "$SID" --in-place --spawn --launch
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [[ "$output" == *"pass one"* ]] || { echo "$output"; false; }
}
