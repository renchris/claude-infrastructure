#!/usr/bin/env bats
# design-review-perception — the acceptance tests for bench/'s perception pipeline.
#
# WHAT THIS EXISTS TO PIN. The whole substrate this pipeline is built on
# (docs/research/cv-design-review-2026-08-26/) argues one thing over and over:
# **classical CV fails by returning an obviously wrong number, a learned model
# fails by returning a plausible one, and a plausible wrong number is the defect
# that kills a review tool.** Every arm here was written, shipped, and only THEN
# found to be producing a plausible number nobody had checked:
#
#   · X2 measured a mark's ink against the mark's OWN post-transform box, which
#     is invariant under the compensation it exists to verify, and took the
#     modal colour of a square crop as the background, so a round button's
#     corners counted as ink. It reported an offset. The offset meant nothing.
#   · X3 took the modal colour of a band as the backdrop. On a gradient every
#     backdrop pixel is nearly unique and every glyph pixel is exactly the text
#     colour, so on greyscale antialiasing THE TEXT WINS THE MODE and the arm
#     compares white to white: 1.00:1 both ends, spread 0.00, silence. The
#     README reports this arm as validated; it found nothing at all here.
#   · type-scale inferred the page's scale from its own histogram, so a size
#     used once was a defect -- including the page's own section heading. It
#     stayed hidden only because a glyph coincidentally shared 16px with it.
#
# So the tests below are not "does it find the defect". Two of them are, and the
# other four are the negative controls that would have caught all three of the
# above. The FP gate in particular is the ship gate for every future rule:
# absolute zero on a page with no defect, enforceable at n = 1, unweighted, with
# no profile able to demote a rule out of it.
#
# NOT HERMETIC in the usual sense: it runs the real detectors over the real
# committed corpus. That is deliberate -- the corpus IS the fixture, and a mock
# of it would be a second corpus with no control run of its own.

setup() {
  unset CC_BATS_ACTIVE
  # Nothing here reads $HOME, but a suite that runs against the operator's live
  # home is one edit away from doing so, and the ratchet is right to refuse the
  # distinction. Fixture it unconditionally.
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"

  BENCH="${BATS_TEST_DIRNAME}/../bench"
  CORPUS="${BENCH}/corpus/out"
  # The corpus IS the fixture and it is a tracked directory, so the one test that
  # has to take a file away restores it here even if it dies mid-way. A suite
  # that can leave the repo missing an artifact is a suite that reds the next
  # run for a reason that has nothing to do with the next run.
  HELD="${BATS_TEST_TMPDIR}/findings_xcheck.held.json"
}

teardown() {
  if [ -f "$HELD" ] && [ ! -f "${CORPUS}/findings_xcheck.json" ]; then
    mv "$HELD" "${CORPUS}/findings_xcheck.json"
  fi
}

# The detectors need numpy/pillow and a captured corpus. Neither is a repo
# invariant, and a red for a missing dependency is a false red -- it says the
# rules are broken when nothing has been measured at all.
need_corpus() {
  python3 -c 'import numpy, PIL' 2>/dev/null || skip "numpy/pillow not installed"
  [ -d "${CORPUS}/snapshots" ] || skip "corpus not captured (run capture.py)"
  [ -d "${CORPUS}/shots" ] || skip "corpus not captured (run capture.py)"
}

@test "FP gate: zero findings on the clean control, and it exits 0" {
  need_corpus
  run bash -c "cd '${BENCH}' && python3 fp_budget.py corpus/out"
  [ "$status" -eq 0 ]
  [[ "$output" == *"GATE: PASS"* ]]
}

@test "FP gate: RED-proves -- a defect page passed in as a control must FAIL it" {
  # The positive control on the instrument itself. A gate that has never been
  # seen to fail is a gate nobody has evidence works.
  need_corpus
  run bash -c "cd '${BENCH}' && python3 fp_budget.py corpus/out --controls clean,contrast-plain --json '${BATS_TEST_TMPDIR}/fp.json'"
  [ "$status" -eq 1 ]
  [[ "$output" == *"GATE: FAIL"* ]]
}

@test "FP gate: refuses to print a rate below n=16 clean pages" {
  # 0 findings over 1 page bounds the rate at 300%. Printing that as evidence is
  # how a bound becomes a measurement in someone's summary.
  need_corpus
  run bash -c "cd '${BENCH}' && python3 fp_budget.py corpus/out"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RATE: NOT COMPUTED"* ]] || false
  [[ "$output" == *"DEFICIT"* ]] || false
  [[ "$output" == *"per 1,000 subject-checks"* ]]
}

@test "X2 measures against the container, so it is NOT invariant under the compensation" {
  # The clean control carries translateX(2px); the variant removes it. An
  # own-box measurement returns the same number for both -- that was the bug.
  need_corpus
  run bash -c "cd '${BENCH}' && python3 detect_xcheck.py corpus/out"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CONTROL clean.html -> 0 finding(s)"* ]] || false
  [[ "$output" == *"optical-centering"* ]] || false
  [[ "$output" == *"xcheck-optical-centre"* ]]
}

@test "X3 resolves the gradient abstention from the glyphs, not from the box" {
  need_corpus
  run bash -c "cd '${BENCH}' && python3 detect_xcheck.py corpus/out"
  [ "$status" -eq 0 ]
  [[ "$output" == *"xcheck-contrast-real"* ]] || false
  [[ "$output" == *"abstentions resolved by the cross-check: 2"* ]]
}

@test "router: T1 GROWS when the cross-check file is absent" {
  # The one place where a LARGER model queue is the correct response to a layer
  # failure. An empty resolution file resolves nothing and looks exactly like
  # nothing needing resolution, so the subtraction must test for the FILE.
  need_corpus
  [ -f "${CORPUS}/findings_xcheck.json" ] || skip "no findings_xcheck.json"

  run bash -c "cd '${BENCH}' && python3 route.py corpus/out --profile bench --page contrast-on-gradient --no-crops"
  [ "$status" -eq 0 ]
  [[ "$output" == *"cross-check: present"* ]] || false
  with_xcheck="$(python3 -c "
import json,sys
p=json.load(open('${CORPUS}/route_plan.json'))
print(p['pages']['contrast-on-gradient']['coverage']['abstention_classes'])")"

  mv "${CORPUS}/findings_xcheck.json" "$HELD"
  run bash -c "cd '${BENCH}' && python3 route.py corpus/out --profile bench --page contrast-on-gradient --no-crops"
  status_without="$status"
  output_without="$output"
  without_xcheck="$(python3 -c "
import json
p=json.load(open('${CORPUS}/route_plan.json'))
print(p['pages']['contrast-on-gradient']['coverage']['abstention_classes'])")"
  mv "$HELD" "${CORPUS}/findings_xcheck.json"

  [ "$status_without" -eq 0 ]
  [[ "$output_without" == *"cross-check: absent"* ]] || false
  [ "$with_xcheck" -eq 0 ]
  [ "$without_xcheck" -gt 0 ]
}

@test "router: the NEVER list is enforced in code, not in discipline" {
  # If the answer has a number in it, the model does not get the question.
  need_corpus
  run bash -c "cd '${BENCH}' && python3 route.py corpus/out --profile bench --page clean --no-crops --ask 'How many pixels of padding are on the primary button?'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"NEVER-list violation"* ]]
}

@test "profiles: no profile may weight a rule to zero" {
  # A weight may rank and demote. It may never suppress, and it may never reach
  # the FP gate -- otherwise the per-app knob is a knob for hiding evidence.
  run python3 -c "
import json, pathlib
cfg = json.loads(pathlib.Path('${BENCH}/profiles.json').read_text())
bad = [(n, r) for n, p in cfg['profiles'].items()
       for r, w in p.get('weights', {}).items() if float(w) <= 0]
print('BAD' if bad else 'OK', bad)
"
  [ "$status" -eq 0 ]
  [[ "$output" == "OK"* ]] || false
}

@test "profiles: the two named apps really do weight conformance differently" {
  # The whole point of the per-app split. If these ever converge, the split is
  # ceremony and should be deleted rather than maintained.
  run python3 -c "
import json, pathlib
p = json.loads(pathlib.Path('${BENCH}/profiles.json').read_text())['profiles']
land = p['reso-landing']['weights']['token-drift']
mgmt = p['reso-management']['weights']['token-drift']
assert land < mgmt, (land, mgmt)
assert p['reso-landing']['weights']['contrast'] == 1.0
assert p['reso-management']['weights']['contrast'] == 1.0
print('OK', land, mgmt)
"
  [ "$status" -eq 0 ]
  [[ "$output" == "OK"* ]]
}
