#!/usr/bin/env bats
# bg-fd-inherit-lint.sh — a backgrounded child in a hook must not inherit stdout.
# backlog 50627335fe9b (the 54-minute Stop-hook wedge on pane 113).
#
# WHAT MAKES THIS SUBJECT WORTH A LINT AND NOT A RUNTIME ALARM. The row prescribed a detector keyed
# on the conjunction "hook frame displayed AND no hook child". Axis A does not exist: measured
# against the 2.1.220 binary every pane on this box runs, the only hook frame rendered is the
# PAST-TENSE `Ran <N> <Label> hooks` — a count with no denominator — and hooksRunning /
# runningHooks / pendingHooks / hookProgress have zero hits anywhere. There is no in-flight
# fraction to key on, so the prescribed anchor is unbuildable and any detector on it would be a
# heuristic wearing an exact detector's clothes. The condition IS statically visible, so it is
# checked statically.
#
# THE CASES BELOW ARE MOSTLY ABOUT THE LINT'S OWN BLINDNESS, because that is how it fails. A lint
# that cannot catch its motivating bug runs clean and certifies the defect — which this one did on
# its first draft: the stdout test matched the second `>` of `2>>`, so `afplay … 2>>LOG &` (the
# actual pane-113 line) was waved through as "already redirected". Its own selftest positive
# control is what caught that, which is why the control is asserted here before anything else.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LINT="$REPO/scripts/bg-fd-inherit-lint.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  D="$BATS_TEST_TMPDIR/hooks"; mkdir -p "$D"
}

@test "the lint's own positive controls pass — it can catch the real pre-fix line" {
  # Asserted FIRST and by name. If this regresses, every other case in this file is measuring a
  # lint that cannot fail, and a green run below would mean nothing at all.
  run bash "$LINT" --selftest
  [ "$status" -eq 0 ]
  [[ "$output" == *"6/6 GREEN"* ]]
}

@test "the exact line that wedged pane 113 is caught — 2>> is not a stdout redirect" {
  # `afplay … 2>>"$LOG" &`. stderr resolved, stdout inherited. The first draft read the second `>`
  # of `2>>` as stdout going somewhere and passed it.
  # shellcheck disable=SC2016  # literal shell SOURCE written into a fixture, not to expand here
  printf '%s\n' '#!/bin/bash' 'afplay "$S" 2>> "$LOG" &' 'disown' > "$D/notify.sh"
  run bash "$LINT" --dir "$D"
  [ "$status" -eq 1 ]
  [[ "$output" == *"notify.sh"* ]]
}

@test "an unredirected backgrounded SUBSHELL is caught, redirects on its inner lines notwithstanding" {
  # Four of the five live findings had this shape, and it is the one a line-oriented scan is most
  # likely to miss: the inner commands carry `2>/dev/null`, so the block LOOKS handled while the
  # subshell still holds the pipe. A subshell holds the descriptor whether or not it ever writes,
  # which is why these read as harmless.
  printf '%s\n' '#!/bin/bash' '(' '  git commit -m x 2>/dev/null' ') &' > "$D/plan.sh"
  run bash "$LINT" --dir "$D"
  [ "$status" -eq 1 ]
  [[ "$output" == *"plan.sh"* ]]
}

@test "a redirected background is clean — the lint is not merely allergic to the ampersand" {
  # The over-wide failure. hooks/session-beat.sh is the live version of this shape.
  # shellcheck disable=SC2016  # literal shell SOURCE written into a fixture, not to expand here
  printf '%s\n' '#!/bin/bash' 'sleep 1 >>"$OUT" 2>&1 &' > "$D/beat.sh"
  printf '%s\n' '#!/bin/bash' '(' '  work' ') >/dev/null &' > "$D/sub-ok.sh"
  run bash "$LINT" --dir "$D"
  [ "$status" -eq 0 ]
}

@test "a COMMENTED example is never a finding" {
  # This lint's own header quotes the bad shape. A lint that convicts documentation of the bug it
  # documents cannot be kept.
  # shellcheck disable=SC2016  # literal shell SOURCE written into a fixture, not to expand here
  printf '%s\n' '#!/bin/bash' '# afplay "$S" 2>>"$LOG" &' 'true' > "$D/doc.sh"
  run bash "$LINT" --dir "$D"
  [ "$status" -eq 0 ]
}

@test "&& at end of line is a continuation, not a background" {
  printf '%s\n' '#!/bin/bash' 'true &&' '  echo hi' > "$D/cont.sh"
  run bash "$LINT" --dir "$D"
  [ "$status" -eq 0 ]
}

@test "a missing directory is a NON-VERDICT (exit 2), never a clean claim" {
  # memory: null-result-must-not-use-the-error-channel, inverted — here the danger is the opposite,
  # an unrunnable lint reporting clean. Absence of evidence must not print as evidence of absence.
  run bash "$LINT" --dir "$BATS_TEST_TMPDIR/no-such-dir"
  [ "$status" -eq 2 ]
  [[ "$output" == *"NON-VERDICT"* ]]
}

@test "the live hooks/ tree is clean, and every historical site stays fixed" {
  # The regression guard for the five sites fixed alongside this lint. Any new unredirected
  # background in a hook reds here, which is the whole point of shipping the lint with the fix.
  run bash "$LINT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"0 backgrounded child inherits stdout"* ]]
}

@test "the five historical sites carry an explicit stdout redirect on the backgrounding line" {
  # Pinned by CONTENT rather than by the lint's own verdict: if the lint ever went blind again, the
  # verdict above would go quiet while these files silently regressed. Two instruments, one fact.
  grep -q 'afplay .* >/dev/null' "$REPO/hooks/notify.sh"
  grep -q 'PRUNE_SCRIPT" >/dev/null &' "$REPO/hooks/session-start.sh"
  grep -q ') >/dev/null &' "$REPO/hooks/plan-version-commit.sh"
  grep -q ') >/dev/null &' "$REPO/hooks/session-index-start.sh"
  [ "$(grep -c ') >/dev/null &' "$REPO/hooks/session-end.sh")" -eq 2 ]
}
