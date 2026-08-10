#!/usr/bin/env bats
# cc-premise --falsifier: the item re-asks its OWN question against today's tree.
#
# WHY THIS EXISTS. Every other signal in cc-premise reads words somebody wrote at filing time.
# This one runs a command NOW. The operator's requirement was that a backlog item must not fire
# unless it is provably current, and prose cannot be provably anything — so the falsifier is the
# only signal in the file that is a measurement rather than a claim.
#
# THE ASYMMETRY IS THE DESIGN, and every test below pins one half of it:
#   exit 0   ⇒ the condition is GONE      ⇒ REFUSE the claim (verdict=falsified, rc 3)
#   non-0    ⇒ the condition is STILL LIVE ⇒ allow, and carry the probe's output into the contract
#   unaskable ⇒ FAIL OPEN — a broken probe must never starve the queue, because an unread premise
#              is "I could not tell", never "it is finished" (cc-premise's own header).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  PREMISE="$REPO/bin/cc-premise"
  BACKLOG_BIN="$REPO/bin/cc-backlog"
  TMP="$(mktemp -d)"
  # HERMETIC $HOME, not merely a redirected store. CC_BACKLOG_FILE alone would be one unset
  # variable away from the operator's live ledger, because both subjects DEFAULT to
  # ~/.claude/autonomy/backlog.jsonl — a suite that only overrides the override is unhermetic by
  # construction, and this is what the land gate's test-hermeticity lint refused.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/autonomy"
  export CC_BACKLOG_FILE="$TMP/backlog.jsonl"
  # Pin the git arms INERT. They are not under test here, and leaving them live would make every
  # assertion below a function of whatever this worktree's HEAD happens to be.
  export CC_PREMISE_REPO=""
}

teardown() { rm -rf "$TMP"; }

add() { "$BACKLOG_BIN" add --project p --title "$1" ${2:+--falsifier "$2"} 2>/dev/null; }

@test "falsifier exits 0 (condition gone) -> REFUSES with verdict=falsified" {
  id="$(add 'a condition that has since been fixed' 'true')"
  run "$PREMISE" check "$id"
  [ "$status" -eq 3 ]
  [[ "$output" == *"verdict=falsified"* ]]
}

@test "falsifier exits non-zero (condition live) -> ALLOWS the claim" {
  id="$(add 'a condition that is still real' 'false')"
  run "$PREMISE" check "$id"
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=clear"* ]]
}

@test "the live-probe contract carries the probe's OWN output, not the filing-day text" {
  id="$(add 'still real' 'echo TODAYS_SYMPTOM; exit 1')"
  run "$PREMISE" check "$id"
  [ "$status" -eq 0 ]
  # `grep -q`, not a bare `[[ ]]`: a NON-FINAL [[ ]] is a shell keyword whose failure errexit does
  # not propagate here, so it would assert nothing at all. The land gate's dead-assertion lint
  # caught exactly this on line 53 of the first draft — two claims that could never fail.
  printf '%s' "$output" | grep -q "TODAYS_SYMPTOM"
  printf '%s' "$output" | grep -q "STILL LIVE"
}

@test "no falsifier stored -> behaviour is exactly as before" {
  id="$(add 'an ordinary item with no probe')"
  run "$PREMISE" check "$id"
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=clear"* ]]
}

@test "a HUNG probe fails OPEN — it must never block a claim" {
  id="$(add 'probe that hangs forever' 'sleep 60')"
  CC_PREMISE_FALSIFIER_TIMEOUT=2 run "$PREMISE" check "$id"
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=clear"* ]]
}

@test "an UNRUNNABLE probe fails OPEN" {
  id="$(add 'probe that cannot run' 'this-binary-does-not-exist-anywhere')"
  run "$PREMISE" check "$id"
  # sh returns 127; non-zero means STILL LIVE, which is the safe direction — never a refusal.
  [ "$status" -eq 0 ]
}

@test "kill-switch CC_PREMISE_FALSIFIER=off disables the probe entirely" {
  id="$(add 'condition gone but gate is off' 'true')"
  CC_PREMISE_FALSIFIER=off run "$PREMISE" check "$id"
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=clear"* ]]
}

# THE LOAD-BEARING ONE. A live falsifier says "this condition is real"; it says NOTHING about
# whether THIS item is the right place to work it. An early return here would let a healthy probe
# suppress the self-duplicate and superseded checks — making the gate WEAKER than before the
# feature existed. This test failed (clear/0 instead of self-duplicate/3) against the first draft.
@test "a LIVE falsifier does not suppress the self-duplicate refusal" {
  canon="$(add 'the canonical item that holds the work')"
  id="$(add "DUPLICATE of $canon but its own probe is live" 'false')"
  run "$PREMISE" check "$id"
  [ "$status" -eq 3 ]
  [[ "$output" == *"verdict=self-duplicate"* ]]
}

@test "the falsifier is NOT part of the id hash — improving a probe must not re-mint the row" {
  a="$("$BACKLOG_BIN" add --project p --title "same work" --falsifier "test -f /nope" 2>/dev/null)"
  b="$("$BACKLOG_BIN" add --project p --title "same work" --falsifier "test -f /also-nope" 2>/dev/null)"
  [ "$a" = "$b" ]
}
