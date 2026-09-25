#!/bin/bash
# verify.sh <task-id> <fixture-dir> <plant-sha> — the code-checked half of F3 success.
# Prints lines ending in one verdict line "VERIFIER: PASS|FAIL|JUDGED <reason>"; exit 0 / 1 / 3.
# PASS needs the fix COMMITTED (a new commit on top of the plant, and a clean scripts/ + tests/),
# the task's own bats file green, and a hidden case the test does not cover. JUDGED = no code truth
# (the blind judge decides), after the mechanical preconditions below hold.
set -u
TASK=$1; FX=$2; PLANT=$3
cd "$FX" || { echo "VERIFIER: FAIL no fixture"; exit 1; }
fail() { echo "VERIFIER: FAIL $*"; exit 1; }
pass() { echo "VERIFIER: PASS $*"; exit 0; }

committed() {  # a new commit exists and the named paths are clean
  [ "$(git rev-parse HEAD)" != "$PLANT" ] || fail "no new commit on top of the planted one"
  [ -z "$(git status --porcelain -- "$@")" ] || fail "uncommitted changes under $*"
}
bats_green() {  # bats_green <file>
  local out
  # CC_BATS_MAX_ROOTS=0: the bats on PATH is cc-bats, which SHEDS (rc 75, no TAP) above 2 concurrent
  # suites; under a gate's own parallel runs that read as "did not run" on a correct fix (smoke r90).
  out=$(CC_BATS_MAX_ROOTS=0 timeout 180 bats "$1" 2>&1); echo "$out" | grep -E '^(1\.\.|ok|not ok)'
  echo "$out" | grep -q '^1\.\.[1-9]' || fail "$1 did not run (no plan line)"
  ! echo "$out" | grep -q '^not ok' || fail "$1 still red"
}

case "$TASK" in
  S01-tsv-empty-cell)
    committed scripts tests; bats_green tests/pane-table.bats
    h=$(mktemp); printf 's1\t%%7\t/a\ns2\t\t/b\ns3\t\t\n' > "$h"
    got=$(bash scripts/pane-table.sh "$h" | sed -n 3,4p); rm -f "$h"
    [ "$got" = "$(printf 's2         -      /b\ns3         -      -')" ] || fail "hidden case: rows with empty cells render wrong: $got"
    pass "test green, hidden empty-cell rows correct" ;;
  S02-wc-digit-guard)
    committed scripts tests; bats_green tests/queue-depth.bats
    h=$(mktemp); seq 12 > "$h"; got=$(bash scripts/queue-depth.sh "$h"); rm -f "$h"
    [ "$got" = "12 queued" ] || fail "hidden case: 12-line spool reads '$got'"
    pass "test green, hidden 12-line count correct" ;;
  S03-shift-past-end)
    committed scripts tests; bats_green tests/export-rows.bats
    timeout 10 bash scripts/export-rows.sh --format < /dev/null > /dev/null 2>&1; rc=$?
    [ "$rc" -eq 2 ] || fail "hidden case: '--format' with no value exits $rc (124 = hang)"
    pass "test green, hidden --format case exits 2" ;;
  S04-shebangless-stub)
    committed scripts tests; bats_green tests/stamp-version.bats
    git diff --quiet "$PLANT" HEAD -- scripts/stamp-version.py || fail "scripts/stamp-version.py was changed (the defect is in the test's stub)"
    pass "test green, script untouched" ;;
  S05-pipefail-dead-stage)
    committed scripts tests; bats_green tests/marker-scan.bats
    h=$(mktemp); echo x > "$h"; chmod 000 "$h"; bash scripts/marker-scan.sh "$h" > /dev/null 2>&1; rc=$?; rm -f "$h"
    [ "$rc" -eq 1 ] || fail "hidden case: unreadable file exits $rc"
    pass "test green, hidden unreadable-file case refused" ;;
  S06-feature-count)
    committed scripts tests
    want=$(find docs/lessons -maxdepth 1 -name '*.md' | wc -l | tr -d ' ')
    got=$(bash scripts/lesson-index.sh --count 2>&1)
    [ "$got" = "$want" ] || fail "--count prints '$got', want '$want'"
    git show "$PLANT:scripts/lesson-index.sh" > scripts/.verify-plant.sh
    a=$(bash scripts/.verify-plant.sh | shasum); b=$(bash scripts/lesson-index.sh | shasum)
    a2=$(bash scripts/.verify-plant.sh --grep shell | shasum); b2=$(bash scripts/lesson-index.sh --grep shell | shasum)
    rm -f scripts/.verify-plant.sh
    [ "$a" = "$b" ] && [ "$a2" = "$b2" ] || fail "default or --grep output changed"
    pass "--count = $want, existing output unchanged" ;;
  S07-question)
    [ "$(git rev-parse HEAD)" = "$PLANT" ] || fail "made a commit on a read-only question"
    [ -z "$(git status --porcelain)" ] || fail "left changes in the tree on a read-only question"
    echo "truth: $(grep -l '^# migration-class: c10' migrations/*.sh | wc -l | tr -d ' ') of $(find migrations -maxdepth 1 -name '*.sh' | wc -l | tr -d ' ') are c10; not c10: $(grep -L '^# migration-class: c10' migrations/*.sh | tr '\n' ' ')"
    echo "VERIFIER: JUDGED read-only, tree untouched"; exit 3 ;;
  S08-docs-readme)
    git cat-file -e HEAD:docs/lessons/README.md 2>/dev/null || fail "docs/lessons/README.md is not committed"
    [ -z "$(git status --porcelain -- docs)" ] || fail "uncommitted changes under docs/"
    echo "files changed since the plant: $(git diff --name-only "$PLANT" HEAD | tr '\n' ' ')"
    echo "VERIFIER: JUDGED README committed" ; exit 3 ;;
  *) echo "VERIFIER: FAIL unknown task $TASK"; exit 1 ;;
esac
