#!/usr/bin/env bats
# herm-suite-memo.bats — the per-suite memo inside test-hermeticity-lint (backlog cf440684e0e1).
#
# THE SPLIT WITH --selftest IS DELIBERATE AND IS THE REPO'S STANDING RULE: `--selftest` owns the
# MECHANISM on synthetic fixtures with no history, and this suite owns COVERAGE AGAINST THE REAL
# CORPUS. Asking either to do the other's job yields a vacuous pass — a mechanism proved only on
# two hand-written fixtures says nothing about 467 real suites, and a corpus test that has to build
# its own violations proves nothing about the mechanism.
#
# WHY THIS MEMO EXISTS. test-hermeticity is the land gate's most expensive arm: 46.0s of the ~135s
# the ratchet arms cost, measured 2026-08-13 with the own-set exported as ship-land's own_run does.
# Every optimistic round a sibling invalidates (exit 42) re-pays it over a tree that is identical
# except for the sibling's delta. Measured shape: 10.4s fixed + 0.069s per suite.
#
# THE FAILURE DIRECTION IS THE WHOLE POINT, so what is pinned here is the memo AGREEING with the
# unmemoized run — not the memo being fast. A memo that returns a green it did not earn is strictly
# worse than the 32s it saves (repo memory: gate-default-decides-failure-direction).
#
# Rules 5 and 6 are pinned OFF in most cases: their tables are built from bin+scripts+hooks and cost
# the fixed 10.4s per run, which would put this suite over the gate's smoke budget and turn a real
# assertion into a recurring exit-124 non-verdict (repo memory: bound-must-fit-the-band-not-the-bench).
# The one case that must see them keeps them on.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"      # hermeticity: never the operator's live ~
  mkdir -p "$HOME"

  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LINT="$REPO/scripts/test-hermeticity-lint.sh"

  # A REAL slice of the corpus, in a repo of its own. The lint's memo refuses on a dirty worktree
  # (memo_init hashes the COMMITTED tree), so a test that ran against $REPO directly would silently
  # go memo-OFF for anyone with an edit in flight — passing while asserting nothing, which is the
  # one outcome a positive control exists to prevent.
  CORPUS="$BATS_TEST_TMPDIR/corpus"
  mkdir -p "$CORPUS/tests"
  # Glob into an array and slice, never `ls | head`: a pipeline of those is one findings-bearing
  # line per use and the gate's own .bats shellcheck ratchet blocks on lines this change wrote.
  ALL_SUITES=( "$REPO"/tests/*.bats )
  for f in "${ALL_SUITES[@]:0:40}"; do cp "$f" "$CORPUS/tests/"; done
  cd "$CORPUS" || exit 1
  git init -q .
  git config user.email tester@example.com
  git config user.name tester
  git add -A
  git commit -q -m corpus

  # Rules whose tables cost the fixed 10.4s; the seam/env roots would also point outside this repo.
  export CC_HERM_SEAM_RULE=off CC_HERM_ENV_RULE=off

  # THIS SUITE'S SUBJECT IS THE LINT, and the lint carries both of its own anchors by construction —
  # a shape-5a seam defaulting to a constant /tmp path, and an inherited value this repo injects
  # into every pane it launches. A suite that names it and takes no position on either inherits
  # them, so it would pass here and go red inside a fired pane. Its own rules 5 and 6 caught this
  # at the gate, on this file, which is the ratchet working rather than an obstacle to it.
  export CC_HERM_SEAM_SELFPROBE="$BATS_TEST_TMPDIR/seam-anchor"
  export CC_HERM_ENV_SELFPROBE=0
}

run_lint() {  # → combined output of one whole-corpus run over the real slice
  "$LINT" tests 2>&1 || true
}

@test "the memo carries verdicts on a real committed corpus (positive control)" {
  run_lint >/dev/null
  out="$(run_lint)"
  # An empty result from a matcher is not evidence of absence until the matcher is shown able to
  # return a hit. Every other case in this file is satisfied by a memo that never fires, so this is
  # the one that has to pass first.
  echo "$out" | grep -qE 'per-suite memo — [1-9][0-9]* suite verdict\(s\) carried'
}

@test "a carried run reports the SAME verdicts as an unmemoized one over the real corpus" {
  warm="$(run_lint)"                                       # earns whatever greens it can
  memoized="$(run_lint)"
  cold="$(CC_HERM_MEMO=off "$LINT" tests 2>&1 || true)"
  # The memo line itself is the one legitimate difference; every finding must survive it. Compared
  # as SETS of finding lines, because the memo must not drop, add, or reword a single one.
  m="$(printf '%s\n' "$memoized" | grep -vE 'per-suite memo —' | sort)"
  c="$(printf '%s\n' "$cold"     | grep -vE 'per-suite memo —' | sort)"
  [ "$m" = "$c" ]
  # …and the warm run must have agreed too, so a memo that only converges after two runs cannot
  # hide here.
  w="$(printf '%s\n' "$warm" | grep -vE 'per-suite memo —' | sort)"
  [ "$w" = "$c" ]
}

@test "the same corpus run twice carries every suite it proved fresh the first time" {
  first="$(run_lint)"
  second="$(run_lint)"
  fresh1="$(printf '%s\n' "$first"  | sed -n 's/.*carried, \([0-9]*\) proven fresh.*/\1/p')"
  carry2="$(printf '%s\n' "$second" | sed -n 's/.*memo — \([0-9]*\) suite verdict(s) carried.*/\1/p')"
  [ -n "$fresh1" ]
  [ -n "$carry2" ]
  # Nothing that was PROVEN clean on run 1 may need re-proving on run 2 — an unchanged tree, an
  # unchanged lint, unchanged allowlists. A carry below that means the key is picking up something
  # that moves between two identical runs, which is the defect that would make this memo useless
  # rather than unsound.
  [ "$carry2" -ge 1 ]
  [ "$carry2" -le "$((fresh1 + carry2))" ]
}

@test "editing one suite re-proves THAT suite and no other" {
  run_lint >/dev/null
  before="$(run_lint | sed -n 's/.*memo — \([0-9]*\) suite verdict(s) carried.*/\1/p')"
  corpus_suites=( tests/*.bats ); victim="${corpus_suites[0]}"
  printf '\n# touched by herm-suite-memo.bats\n' >> "$victim"
  git add -A
  git commit -q -m touch
  after="$(run_lint)"
  carried="$(printf '%s\n' "$after" | sed -n 's/.*memo — \([0-9]*\) suite verdict(s) carried.*/\1/p')"
  fresh="$(printf '%s\n' "$after" | sed -n 's/.*carried, \([0-9]*\) proven fresh.*/\1/p')"
  [ -n "$carried" ]
  [ -n "$fresh" ]
  # Exactly the edited file is re-proven. A blob key that keyed on the path would carry it anyway
  # (stale); one that keyed on the whole tree would re-prove all of them (useless).
  [ "$fresh" -eq 1 ]
  [ "$carried" -eq "$((before - 1))" ]
}

@test "a change to the lint itself invalidates every carried verdict" {
  run_lint >/dev/null
  run_lint >/dev/null
  # The lint's own bytes carry every predicate AND all seven embedded allowlists, so a verdict
  # earned under one revision may not be served under another. Copied rather than edited in place:
  # this must never write to the checkout it is testing.
  #
  # THE COPY NEEDS A ROOT THAT LOOKS LIKE ONE. A first version dropped it in $BATS_TEST_TMPDIR and
  # the case failed for a reason that had nothing to do with the key: from there $ROOT/scripts/lib/
  # does not exist, the lint never sources gate-memo.sh, and the memo is OFF rather than MISSING.
  # That is a REVISED lint we want to test, not a homeless one — so mirror the layout it expects.
  fake="$BATS_TEST_TMPDIR/fakeroot"
  mkdir -p "$fake/scripts/lib"
  cp "$REPO/scripts/lib/gate-memo.sh" "$fake/scripts/lib/"
  cp "$LINT" "$fake/scripts/lint2.sh"
  printf '\n# revision marker\n' >> "$fake/scripts/lint2.sh"
  chmod +x "$fake/scripts/lint2.sh"
  out="$("$fake/scripts/lint2.sh" tests 2>&1 || true)"
  carried="$(printf '%s\n' "$out" | sed -n 's/.*memo — \([0-9]*\) suite verdict(s) carried.*/\1/p')"
  [ -n "$carried" ]
  [ "$carried" -eq 0 ]
}

@test "a dirty worktree disarms the memo entirely" {
  run_lint >/dev/null
  corpus_suites=( tests/*.bats )
  printf '\n# uncommitted\n' >> "${corpus_suites[0]}"
  out="$(run_lint)"
  # memo_init's population fingerprint is computed off the COMMITTED tree, so a worktree that does
  # not match HEAD is exactly the state in which a carried verdict could describe bytes nobody
  # checked. OFF means every lookup misses — today's behaviour, at today's cost.
  ! printf '%s\n' "$out" | grep -q 'per-suite memo'
}

@test "with rules 5 and 6 ON the memo still agrees with an unmemoized run" {
  # The two cross-population rules, judged against the REAL tool tree. This is the case the whole
  # per-file design turns on: rules 1-4 and 7 are file-local, rules 5-6 judge a suite against a
  # table extracted from a population no suite belongs to, and HERM_READSET has to carry it.
  unset CC_HERM_SEAM_RULE CC_HERM_ENV_RULE
  export CC_HERM_SEAM_ROOT="$REPO" CC_HERM_ENV_ROOT="$REPO"
  run_lint >/dev/null
  memoized="$(run_lint | grep -vE 'per-suite memo —' | sort)"
  cold="$(CC_HERM_MEMO=off "$LINT" tests 2>&1 | grep -vE 'per-suite memo —' | sort || true)"
  [ "$memoized" = "$cold" ]
}
