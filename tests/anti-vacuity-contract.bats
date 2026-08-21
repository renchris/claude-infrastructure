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
# NOW IN SCOPE — the exclusion above was DISCHARGED, not overridden. This comment used to read:
# "OUT OF SCOPE, deliberately: scripts/banner-gate-redproof.py is the same class and equally unwired
# … but it belongs to the banner subsystem and has no --check-anchors mode. Filed rather than
# smuggled in here." That reason had two clauses and only one was a preference. The operative clause
# was MECHANISM — no self-check mode — and it is now false: the harness carries --check-cases
# (backlog 5d6dcbe8d462). The remaining clause, subsystem membership, cannot survive on its own here,
# because this file's contract is about RED-PROOFS AS A CLASS and not about a directory.
#
# Its check is NOT --check-anchors and must not be described as one. Those two harnesses are
# declarative — anchors are literal lines in the subject, counted. This one is procedural: 37 cases
# that mutate live module state, only 3 doing any text substitution, so there are no anchors to
# count. --check-cases instead AST-derives each case's `g.<NAME>` reads and requires each to still
# exist, and requires each case's `want` still to be emitted somewhere in gen.py's assertion
# vocabulary. Same goal, different mechanism; the module docstring records why the port did not apply.
#
# So the CENSUS glob below now covers scripts/ as well as tests/ — stated here because a glob that
# widens without its comment widening is how a scoping decision becomes an accident.
#
# THE FOURTH HARNESS — scripts/redproof-lstart-dialect.sh, and it arrived the way the census was
# built to catch. It landed on trunk in 33c462990b2c with no case here, the glob picked it up on the
# day it was created exactly as designed, and the CENSUS went red IN THE TRUNK VERIFIER rather than
# in anyone's head. That is the recurrence guard working; the fix is to wire it, never to widen the
# glob past it.
#
# Its mechanism is a THIRD kind again. cc-queue/cc-pane are declarative-anchor; banner-gate is
# AST-derived cases. This one is a five-arm procedural proof that mutates six bin/ tools and three
# registry sites in `git archive` scratch trees, one bats run per site — far too expensive to live
# here. So it grew a --check-anchors mode over ONE table that its own mutators read: every literal
# is counted here, and every mutation below is DERIVED from its anchor by a further replace, so the
# cheap screen cannot go green over a run that is already broken. A screen keeping a private copy of
# the literals would be the vacuous pass one level up — the thing this whole file is about.
#
# The table also pins two things an anchor count is the only cheap way to reach: the two suites the
# harness RUNS (a deleted one made tally() print `plan=?`, which reads like a quiet zero), and the
# two function headers ARM 5b extracts by name (a rename yielded an EMPTY extraction whose error was
# swallowed by a 2>/dev/null and printed as a blank verdict).

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

@test "banner-gate-redproof: every case still reaches gen.py, and every want is still emitted" {
  run python3 "$REPO/scripts/banner-gate-redproof.py" --check-cases
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'cases live in tools/banner/gen.py' || false
  # Floors, so a gutted CASES table or an AST walk that stopped seeing `g.<NAME>` cannot pass this
  # by having nothing to check. The harness enforces its own floor too; this is the outer one.
  n="$(echo "$output" | sed -n 's/.*: \([0-9]*\)\/[0-9]* cases live.*/\1/p')"
  [ -n "$n" ] || false
  [ "$n" -ge 30 ] || false
  r="$(echo "$output" | sed -n 's/.* \([0-9]*\) module read(s) resolve.*/\1/p')"
  [ -n "$r" ] || false
  [ "$r" -ge 40 ] || false
}

@test "redproof-lstart-dialect: every literal the harness pins still matches its subject" {
  run bash "$REPO/scripts/redproof-lstart-dialect.sh" --check-anchors
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q 'STALE ANCHOR' || false
  # A floor and never an equality, so a row added to the anchor table cannot red this — the one
  # direction nobody needs protecting from. It is high enough that a gutted table (the migration
  # markers alone are 5 rows) cannot pass by having nothing left to check.
  n="$(echo "$output" | sed -n 's/.*--check-anchors: \([0-9]*\) live.*/\1/p')"
  [ -n "$n" ] || false
  [ "$n" -ge 11 ] || false
}

@test "CENSUS: every red-proof harness under tests/ or scripts/ is wired into THIS suite" {
  # The recurrence guard. Wiring the two that exist today fixes today; the class reproduces the next
  # time someone writes a third harness and references it in a comment, which is precisely how these
  # two ended up unrun. Membership is by GLOB so a new harness is in scope on the day it is created,
  # with nobody's cooperation (the same argument permission-gate-lint records for its own globs).
  cd "$REPO"
  seen=0
  unwired=""
  for h in tests/*redproof* scripts/*redproof*; do
    [ -e "$h" ] || continue
    seen=$((seen + 1))
    b="$(basename "$h")"
    # COMMENT LINES ARE STRIPPED FIRST, because the failure message below promises exactly that —
    # "invoked by a case, not merely mentioned in a comment" — and a whole-file grep does not
    # deliver it. Measured 2026-08-13: deleting this suite's banner-gate-redproof CASE left the
    # census GREEN, because the header paragraph explaining the harness names it four times. A guard
    # whose prose states a stricter rule than its code enforces is the vacuous pass it exists to
    # catch, one level up — and the more carefully a harness is documented here, the more thoroughly
    # its own census entry was disarmed.
    grep -v '^[[:space:]]*#' "$BATS_TEST_FILENAME" | grep -q -- "$b" || unwired="$unwired $h"
  done
  # A glob that matched nothing would make this test pass while asserting nothing — the exact
  # vacuity the file is about. Four harnesses exist; require at least four. A FLOOR and never an
  # equality: `-eq 4` would go red on a fifth harness being written, which is the one direction
  # nobody needs protecting from. (Raised 3→4 when the lstart harness landed; the floor tracks what
  # is on disk, so a harness DELETED without its case being removed is still caught here.)
  [ "$seen" -ge 4 ] || false
  if [ -n "$unwired" ]; then
    echo "UNWIRED red-proof harness(es) —$unwired"
    echo "Each must be invoked by a case in $BATS_TEST_FILENAME, not merely mentioned in a comment."
    false
  fi
}

@test "all four harnesses REFUSE a stale case — the check can fail, on the real artifact" {
  # Without this the cases above would pass just as well for a --check-anchors that returns 0
  # unconditionally. Sabotage a real anchored line in a COPY of the tree and require the refusal.
  cp -R "$REPO/bin" "$REPO/tests" "$BATS_TEST_TMPDIR/"
  mkdir -p "$BATS_TEST_TMPDIR/scripts" "$BATS_TEST_TMPDIR/hooks"

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

  # banner-gate-redproof: no anchors to sabotage, so the equivalent damage is RENAMING a table the
  # cases read. `--check-cases` must NAME the inert cases rather than pass over them. Without this
  # arm the case above would pass just as well for a --check-cases wired to return 0 unconditionally
  # — the same vacuity, one level up, that this whole file exists to prevent.
  cp "$REPO/scripts/banner-gate-redproof.py" "$BATS_TEST_TMPDIR/scripts/"
  mkdir -p "$BATS_TEST_TMPDIR/tools/banner"
  cp "$REPO/tools/banner/gen.py" "$BATS_TEST_TMPDIR/tools/banner/gen.py"

  # CONTROL FIRST: the untouched copy must PASS. A refusal with no passing control proves only that
  # the copy is broken, not that the check discriminates.
  run python3 "$BATS_TEST_TMPDIR/scripts/banner-gate-redproof.py" --check-cases
  [ "$status" -eq 0 ]

  python3 - "$BATS_TEST_TMPDIR/tools/banner/gen.py" <<'PYSAB'
import re, sys
p = sys.argv[1]
s = open(p).read()
assert len(re.findall(r"\bWORLD_MOD\b", s)) > 0
open(p, "w").write(re.sub(r"\bWORLD_MOD\b", "WORLD_MOD_RENAMED", s))
PYSAB
  run python3 "$BATS_TEST_TMPDIR/scripts/banner-gate-redproof.py" --check-cases
  [ "$status" -eq 1 ]
  echo "$output" | grep -q 'STALE CASE' || false
  echo "$output" | grep -q 'READS g.WORLD_MOD, which gen.py no longer defines' || false

  # redproof-lstart-dialect: no anchors of its own to sabotage in bin/cc-queue or bin/cc-pane, so
  # the equivalent damage is RENAMING a function ARM 5b extracts BY NAME from bin/cc-notify. That is
  # the rot this mode exists for and the one the harness itself was silent about: the extraction
  # came back empty, the error went to /dev/null, and the arm printed a blank where a verdict goes.
  cp "$REPO/scripts/redproof-lstart-dialect.sh" "$BATS_TEST_TMPDIR/scripts/"
  cp "$REPO/hooks/session-register.sh" "$BATS_TEST_TMPDIR/hooks/"

  # CONTROL FIRST, for the same reason as above: an untouched copy must PASS, or a refusal proves
  # only that the copy is short a file. bin/ and tests/ were copied whole at the top of this case.
  run bash "$BATS_TEST_TMPDIR/scripts/redproof-lstart-dialect.sh" --check-anchors
  [ "$status" -eq 0 ]

  python3 - "$BATS_TEST_TMPDIR/bin/cc-notify" <<'PYLS'
import sys
p = sys.argv[1]
s = open(p).read()
a = "reg_lstart_norm() {"
assert s.count(a) == 1, s.count(a)
open(p, "w").write(s.replace(a, "reg_lstart_norm_RENAMED() {"))
PYLS
  run bash "$BATS_TEST_TMPDIR/scripts/redproof-lstart-dialect.sh" --check-anchors
  [ "$status" -eq 1 ]
  echo "$output" | grep -q 'STALE ANCHOR registry-norm-fn' || false
  echo "$output" | grep -q 'must be exactly 1' || false
}
