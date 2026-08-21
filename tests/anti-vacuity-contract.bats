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
# THE FOURTH HARNESS, and the proof that the CENSUS is not decorative. scripts/redproof-lstart-dialect.sh
# was added by 33c46299 and matched the scripts/*redproof* glob the same day — and was not wired, so
# this suite went RED post-land (backlog 464c856d6799; the auto-revert then failed, rc=90). That is
# the recurrence guard working exactly as its comment promises: a new harness is in scope on the day
# it is created, with nobody's cooperation, and the census refused to stay green over it. The remedy
# is forward, and it is the same one that discharged the banner exclusion above — give the harness a
# cheap self-check, then wire it.
#
# Its check is --check-anchors, and unlike cc-queue's and cc-pane's it spans ELEVEN subjects rather
# than one, in four classes with different predicates: MUTANT (a literal an ARM-4/5e mutator
# replaces — 0 matches makes that site an absent control), FIX (a symbol the fix introduced, whose
# absence-at-the-parent is the arm's non-vacuity claim), PROBE (a definition ARM 5b awk-lifts out of
# this tree), SUITE (a bats file the PRE/POST tallies run). The full harness stays an explicit
# invocation and could never be anything else: it needs a parent sha, a `git archive` per arm, a
# bats run per mutant, and a real live pid. Same trade as the other three, one file wider.

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

@test "redproof-lstart-dialect: every anchor still matches its subject across all eleven files" {
  run bash "$REPO/scripts/redproof-lstart-dialect.sh" --check-anchors
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q 'STALE ANCHOR' || false
  echo "$output" | grep -q 'anchors live across' || false
  # Floors, so a gutted CASES table cannot pass this by having nothing to check. The harness
  # enforces its own floors too (>=18 cases, >=9 of them MUTANT); these are the outer ones, and the
  # subject count is here because this harness's distinguishing risk is a subject going MISSING —
  # eleven files across bin/, hooks/ and tests/, any one of which a later refactor could move.
  n="$(echo "$output" | sed -n 's/.*: \([0-9]*\)\/[0-9]* anchors live.*/\1/p')"
  [ -n "$n" ] || false
  [ "$n" -ge 18 ] || false
  s="$(echo "$output" | sed -n 's/.*anchors live across \([0-9]*\) subjects.*/\1/p')"
  [ -n "$s" ] || false
  [ "$s" -ge 10 ] || false
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
  # nobody needs protecting from. (Raised 3 -> 4 when scripts/redproof-lstart-dialect.sh was wired;
  # the floor tracks the count that exists, so it stays a floor and never a ceiling.)
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
  # redproof-lstart-dialect anchors hooks/session-register.sh too, so the copy must carry it or its
  # arm below would refuse for a missing file rather than for the sabotage — a refusal that proves
  # the copy is incomplete, not that the check discriminates.
  cp "$REPO/hooks/session-register.sh" "$BATS_TEST_TMPDIR/hooks/"

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

  # redproof-lstart-dialect: sabotage the ONE anchor whose loss is worst — the kqueue overlay tuple
  # that ARM 4's mutant replaces. Lose it and `assert new != s` makes that site an absent control,
  # which is this harness's version of the vacuous pass. The literal used here is the mutator's own,
  # so this arm also pins the CASES/mutate() coupling the harness header calls out.
  cp "$REPO/scripts/redproof-lstart-dialect.sh" "$BATS_TEST_TMPDIR/scripts/"

  # CONTROL FIRST, for the same reason the banner arm above needs one: a refusal with no passing
  # control proves only that the copied tree is broken.
  run bash "$BATS_TEST_TMPDIR/scripts/redproof-lstart-dialect.sh" --check-anchors
  [ "$status" -eq 0 ]

  python3 - "$BATS_TEST_TMPDIR/bin/cc-deathwatch-kqueue" <<'PYK'
import sys
p = sys.argv[1]
s = open(p).read()
a = 'for overlay in ({"TZ": "UTC", "LC_ALL": "C"}, None, {"LC_ALL": "C"}):'
assert s.count(a) == 1, s.count(a)
open(p, "w").write(s.replace(a, 'for overlay in ({"TZ": "UTC", "LC_ALL": "C"},):'))
PYK
  run bash "$BATS_TEST_TMPDIR/scripts/redproof-lstart-dialect.sh" --check-anchors
  [ "$status" -eq 1 ]
  echo "$output" | grep -q 'STALE ANCHOR' || false
  echo "$output" | grep -q 'kqueue-overlay-tuple' || false
  echo "$output" | grep -q 'MATCHED 0x' || false
}
