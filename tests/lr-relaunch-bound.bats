#!/usr/bin/env bats
# THE OUTER BOUND MUST EXCEED THE SUM OF THE INNER ONES — as arithmetic, not as a comment.
#
# THE DEFECT THIS EXISTS FOR (U05 §3.4, measured 2026-09-19). The recycle watcher typed the
# launcher, waited 45 s, retyped once, waited 45 s: exactly TWO launcher attempts inside 90 s.
# capacity-admit's refusal budget releases on attempt THREE, at ~150 s. 150 > 90, so the release —
# the one mechanism that guarantees a limit recovery is "delayable but never permanently blockable"
# — was STRUCTURALLY UNREACHABLE inside the window that contained it, and four recoveries stranded
# at exactly two refusals. Two individually-correct bounds, one nested inside the other, the inner
# one sized larger than the outer: docs/lessons/inner-bound-outer-bound-starves-the-tail.md.
#
# THE SAME SHAPE, ONE LAYER UP, IS WHAT THIS SUITE PINS. `recycle_await_verdict` is the bound the
# INTERACTIVE caller (lr-handoff --in-place --await, and the fleet through it) waits under, and it
# wraps four stages that each have their own bound. Until W2 it was 600 + 180 + 120 = 900 s against
# stages that can legitimately consume 180 + 600 + 180 + 180 = 1140 s, so a recycle that was still
# working could be reported as "no verdict inside 900s" — the caller giving up on a live recovery.
#
# READ FROM THE SAME VARIABLES, and that is the property. A test that re-typed the numbers would go
# stale the first time a constant moved and would then certify the inversion it exists to prevent.
# Both cases below extract the DEFAULTS from the source and require the outer expression to NAME
# each inner variable, so a later edit moves the bound with the stage it belongs to.
#
# RED at 6a6f9a129: the max expression is `HF_RECYCLE_SHELL_WAIT_S + RCY_ENGAGE_TIMEOUT + 120`,
# which names neither the composer gate nor the boot bound — case 1 fails on the missing names and
# case 2 fails on 900 < 1140.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"
  # The `max=` line of recycle_await_verdict, extracted from the function's own body so a sibling
  # assignment elsewhere in a 12k-line file cannot answer for it.
  BODY="$(awk '/^recycle_await_verdict\(\) \{/{p=1} p{print} p&&/^\}$/{exit}' "$HF")"
  [ -n "$BODY" ] || { echo "recycle_await_verdict not found — the extractor, not the bound, is broken"; return 1; }
  MAXLINE="$(printf '%s\n' "$BODY" | grep -m1 '^[[:space:]]*max=')"
}

# the DEFAULT baked into a `${VAR:-N}` expansion, wherever the subject reads it
default_of() { # $1=variable name → its default, from the source
  grep -o "\${$1:-[0-9]*}" "$HF" | head -1 | sed 's/.*:-//; s/}//'
}

@test "the await bound is COMPOSED of the stage bounds it wraps, by name" {
  [ -n "$MAXLINE" ] || { echo "no max= line in recycle_await_verdict"; false; }
  for v in CC_RECYCLE_DRAFT_WAIT HF_RECYCLE_SHELL_WAIT_S RCY_BOOT_STALE_S RCY_ENGAGE_TIMEOUT; do
    printf '%s' "$MAXLINE" | grep -q "$v" \
      || { echo "the await bound does not read $v — a stage it waits for is missing from its own sum: $MAXLINE"; false; }
  done
}

@test "the await bound EXCEEDS the sum of the inner bounds (both sides read from the source)" {
  draft="$(default_of CC_RECYCLE_DRAFT_WAIT)"
  shell="$(default_of HF_RECYCLE_SHELL_WAIT_S)"
  boot="$(default_of RCY_BOOT_STALE_S)"
  engage="$(default_of RCY_ENGAGE_TIMEOUT)"
  for n in "$draft" "$shell" "$boot" "$engage"; do
    [ -n "$n" ] || { echo "a stage bound has no readable default (draft=$draft shell=$shell boot=$boot engage=$engage)"; false; }
  done
  inner=$(( draft + shell + boot + engage ))
  # evaluate the subject's OWN expression, with nothing in the environment, so the defaults decide
  outer="$(env -i bash -c "$(printf '%s\n' "$MAXLINE"); printf %s \"\$max\"")"
  [ -n "$outer" ] || { echo "the max expression did not evaluate: $MAXLINE"; false; }
  [ "$outer" -gt "$inner" ] \
    || { echo "await max=${outer}s does NOT exceed its inner stages (${draft}+${shell}+${boot}+${engage}=${inner}s) — a live recycle can be reported as 'no verdict'"; false; }
}

@test "the await loop polls at 0.5s and is DATE-bounded, not counter-bounded" {
  # 0.5 s is the interval §11.5 specifies; a counter would have to do `t=$((t + 0.5))`, which bash
  # cannot evaluate — so the shape and the interval are one decision, not two.
  printf '%s\n' "$BODY" | grep -q 'HF_RECYCLE_AWAIT_IVL:-0.5' \
    || { echo "the await interval is no longer 0.5s"; false; }
  printf '%s\n' "$BODY" | grep -q 'deadline' \
    || { echo "the await loop is not date-bounded — a 0.5s counter cannot work in bash"; false; }
}

@test "the await loop RECOGNISES the boot arm's terminal states" {
  # A verdict the watcher writes and the awaiting caller does not read is a 1200 s hang that ends in
  # "no verdict", which is the opposite of what the boot arm was built to produce.
  printf '%s\n' "$BODY" | grep -q 'FAILED:relaunch' \
    || { echo "the await loop does not recognise FAILED:relaunch"; false; }
  printf '%s\n' "$BODY" | grep -q 'STALE:boot' \
    || { echo "the await loop does not recognise STALE:boot"; false; }
}
