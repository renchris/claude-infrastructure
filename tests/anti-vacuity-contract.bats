#!/usr/bin/env bats
# anti-vacuity-contract — the red-proof harnesses under tests/ are part of the TEST CONTRACT.
#
# THE DEFECT THIS CLOSES (grok-wiki tests shard, rank 1, backlog 9ea31151dd94). This repo's answer
# to the vacuous pass is the red-proof: a harness that MUTATES the real artifact and requires a
# NAMED test to go red. Two of them exist — tests/cc-queue-redproof.py and tests/cc-pane-redproof.sh
# — and nothing ran either one. Measured repo-wide 2026-08-11: outside their own bodies both names
# appear ONLY in comments and plan docs. `bats tests/*.bats` stayed green with no opinion about
# whether the proofs still applied, which is the same shape as the vacuous pass they exist to
# prevent, one level up.
#
# WHAT IS WIRED HERE, and why it is the ANCHOR check rather than the full run. The full proof costs
# one bats run per case (15 + 15) and it is genuinely expensive; making every land pay that is not
# the trade. But the rot the finding names — "harnesses rot into comments" — happens in exactly one
# place: an anchor stops matching its subject. An anchor is a literal line the mutation replaces, so
# 0 matches means the subject moved out from under the proof, which is the moment the assertion it
# backs may have quietly gone vacuous. That check needs no bats run at all. The finding's own
# failure scenario is covered by it: "bin/cc-queue drops the cap notice" IS the
# cap-stops-announcing-what-it-withheld anchor going to 0.
#
# So: the cheap half is now unconditional, and the expensive half stays explicit and is named in the
# failure message. What is NOT covered — and it is stated rather than implied — is a subject that
# keeps every anchored line but breaks the behaviour some OTHER way; only the full run catches that.
#
# OUT OF SCOPE, deliberately: scripts/banner-gate-redproof.py is the same class and equally unwired
# (nightly's globs are scripts/*gate*.sh and scripts/*lint*.sh, and it is a .py), but it belongs to
# the banner subsystem and has no --check-anchors mode. Filed rather than smuggled in here.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  unset KITTY_WINDOW_ID
  # cc-queue's shape-5a seams, pinned because this suite NAMES that tool. --check-anchors never
  # reads them — it only counts substrings — but the last case runs the harness against a copied
  # tree, and the seam a suite forgets is the one a later case starts exercising. Caught by the
  # land gate's test-hermeticity ratchet on the first attempt to land this file, which is the
  # ratchet doing exactly its job to the suite that was written to stop vacuous passes.
  export CC_PERMPEND_DIR="$BATS_TEST_TMPDIR/pend" \
         CC_TELEMETRY_DIR="$BATS_TEST_TMPDIR/tel" \
         CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg"
}

@test "cc-queue-redproof: every anchor still matches bin/cc-queue exactly once" {
  run python3 "$REPO/tests/cc-queue-redproof.py" --check-anchors
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'anchors live in cc-queue' || false
  # a floor, so an emptied CASES table cannot pass this by having nothing to check
  n="$(echo "$output" | sed -n 's/.*: \([0-9]*\)\/[0-9]* anchors live.*/\1/p')"
  [ -n "$n" ] || false
  [ "$n" -ge 10 ] || false
}

@test "cc-pane-redproof: every anchor still matches bin/cc-pane{,-headless} exactly once" {
  run bash "$REPO/tests/cc-pane-redproof.sh" --check-anchors
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q 'STALE ANCHOR' || false
  n="$(echo "$output" | sed -n 's/.*--check-anchors: \([0-9]*\) live.*/\1/p')"
  [ -n "$n" ] || false
  [ "$n" -ge 10 ] || false
}

@test "CENSUS: every red-proof harness under tests/ is wired into THIS suite" {
  # The recurrence guard. Wiring the two that exist today fixes today; the class reproduces the next
  # time someone writes a third harness and references it in a comment, which is precisely how these
  # two ended up unrun. Membership is by GLOB so a new harness is in scope on the day it is created,
  # with nobody's cooperation (the same argument permission-gate-lint records for its own globs).
  cd "$REPO"
  seen=0
  unwired=""
  for h in tests/*redproof*; do
    [ -e "$h" ] || continue
    seen=$((seen + 1))
    b="$(basename "$h")"
    grep -q -- "$b" "$BATS_TEST_FILENAME" || unwired="$unwired $h"
  done
  # A glob that matched nothing would make this test pass while asserting nothing — the exact
  # vacuity the file is about. Two harnesses exist; require at least two.
  [ "$seen" -ge 2 ] || false
  if [ -n "$unwired" ]; then
    echo "UNWIRED red-proof harness(es) —$unwired"
    echo "Each must be invoked by a case in $BATS_TEST_FILENAME, not merely mentioned in a comment."
    false
  fi
}

@test "both harnesses REFUSE a stale anchor — the check can fail, on the real artifact" {
  # Without this the two cases above would pass just as well for a --check-anchors that returns 0
  # unconditionally. Sabotage a real anchored line in a COPY of the tree and require the refusal.
  cp -R "$REPO/bin" "$REPO/tests" "$BATS_TEST_TMPDIR/"
  mkdir -p "$BATS_TEST_TMPDIR/scripts"

  # cc-queue: the cap notice, whose disappearance is the finding's own named failure scenario.
  python3 - "$BATS_TEST_TMPDIR/bin/cc-queue" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
a = "… $(( n - OPT_LIMIT )) more not shown"
assert s.count(a) == 1, s.count(a)
open(p, "w").write(s.replace(a, "more not shown"))
PY
  run python3 "$BATS_TEST_TMPDIR/tests/cc-queue-redproof.py" --check-anchors
  [ "$status" -eq 1 ]
  echo "$output" | grep -q 'cap-stops-announcing-what-it-withheld' || false
  echo "$output" | grep -q 'ANCHOR MATCHED 0x' || false

  # cc-pane: same proof for the shell harness, which counts anchors by a different code path.
  python3 - "$BATS_TEST_TMPDIR/bin/cc-pane" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
a = 'session close -f -s "$1"'
assert s.count(a) == 1, s.count(a)
open(p, "w").write(s.replace(a, 'session close -s "$1"'))
PY
  run bash "$BATS_TEST_TMPDIR/tests/cc-pane-redproof.sh" --check-anchors
  [ "$status" -eq 1 ]
  echo "$output" | grep -q 'STALE ANCHOR' || false
  echo "$output" | grep -q 'close-drops-the-force-flag' || false
}
