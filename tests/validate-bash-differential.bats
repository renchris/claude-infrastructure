#!/usr/bin/env bats
# validate-bash-differential — the differential corpus backlog row 8942f3b1506d blocks itself on.
#
# THE ROW. It proposes replacing hooks/validate-bash.sh's ~30 `grep -qE` pattern tests with
# bash-native `[[ =~ ]]` (one fork saved per site on the hottest path in the fleet), and blocks
# itself on its own terms: "a differential corpus proving identical verdicts on every DANGER
# pattern first". THE CORPUS IS THE DELIVERABLE. This suite is its re-runnable form.
#
# WHAT IT PINS — not "the conversion works", but the MEASURED verdict per site, in both directions:
#   · a site pinned EQUIVALENT that starts diverging  ⇒ the conversion authorisation is void
#   · a site pinned DIVERGENT that stops diverging    ⇒ the corpus lost its counterexample, i.e.
#                                                       the control went vacuous (memory:
#                                                       sibling-guard-makes-the-fixture-vacuous)
#   · a grep site added to, removed from, or MOVED IN the hook ⇒ UNTESTED, which is a failure
#     (memory: unfixed-file-is-not-a-sound-file — silence is not a verdict)
#
# THE ANSWER IT ENCODES (2026-08-17, /usr/bin/grep 2.6.0-FreeBSD + bash 3.2.57): 10 of the 30 sites
# are safe to convert; 20 are NOT. The row's optimisation is retired for the majority of its own
# population — see docs/research/validate-bash-grep-differential-2026-08-17.md.
#
# The controls file is not decoration: it mutates the pinned verdicts and asserts the harness reds.
# A suite that cannot fail is not a control.

setup() {
  # Fixture $HOME before anything else: the harness invokes hooks/validate-bash.sh, which appends to
  # ~/.claude/logs — against the operator's live tree unless this is set, and two concurrent runs
  # would then collide on the same path. Caught by the test-hermeticity ratchet at land time.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  HARNESS="$ROOT/scripts/validate-bash-differential.sh"
  CONTROLS="$ROOT/scripts/validate-bash-differential-controls.sh"
  SITES="$ROOT/tests/fixtures/validate-bash-sites.tsv"
  CORPUS="$ROOT/tests/fixtures/validate-bash-corpus.txt"
}

@test "fixtures and harness are present" {
  [ -r "$HARNESS" ]
  [ -r "$CONTROLS" ]
  [ -r "$SITES" ]
  [ -r "$CORPUS" ]
}

@test "every pattern site's measured verdict still matches its pinned verdict" {
  run bash "$HARNESS"
  [ "$status" -eq 0 ] || {
    printf '%s\n' "$output"
    false
  }
}

@test "coverage: every code-level grep site in the hook is in the inventory" {
  run bash "$HARNESS"
  [ "$status" -eq 0 ]
  # the harness prints this section only on a coverage failure
  [[ "$output" != *"COVERAGE FAILURE"* ]] || false
  [[ "$output" != *"UNTESTED grep sites"* ]]
}

@test "drift: every pinned pattern still appears literally on its hook line" {
  run bash "$HARNESS"
  [ "$status" -eq 0 ]
  [[ "$output" != *"DRIFT FAILURE"* ]]
}

@test "the corpus actually exercises the divergence axes (non-vacuous)" {
  run bash "$HARNESS"
  [ "$status" -eq 0 ]
  # A corpus with zero diverging pairs would mean the axes were never reached — the exact
  # failure this deliverable exists to prevent. Floor, not an exact count, so the suite does not
  # tripwire on its own growth (memory: exact-count-assertion-tripwires-its-own-subject).
  div="$(printf '%s\n' "$output" | sed -n 's/.*diverging pairs: \([0-9][0-9]*\).*/\1/p' | head -1)"
  [ -n "$div" ]
  [ "$div" -ge 40 ]
}

@test "the majority verdict is DIVERGENT — the row's remedy does not clear its own gate" {
  run bash "$HARNESS"
  [ "$status" -eq 0 ]
  line="$(printf '%s\n' "$output" | /usr/bin/grep 'SAFE TO CONVERT')"
  [ -n "$line" ]
  safe="$(printf '%s\n' "$line" | sed -n 's/SAFE TO CONVERT: \([0-9][0-9]*\) of.*/\1/p')"
  total="$(printf '%s\n' "$line" | sed -n 's/.* of \([0-9][0-9]*\) sites.*/\1/p')"
  [ -n "$safe" ] && [ -n "$total" ] || false
  # strictly fewer than half convertible: this is the finding, and if a future change made most
  # sites convertible that is NEWS and should be re-adjudicated, not silently absorbed.
  [ $(( safe * 2 )) -lt "$total" ]
}

@test "positive control: the harness fails on every mutated pinning" {
  run bash "$CONTROLS"
  [ "$status" -eq 0 ] || {
    printf '%s\n' "$output"
    false
  }
  [[ "$output" == *"all controls held"* ]]
}
