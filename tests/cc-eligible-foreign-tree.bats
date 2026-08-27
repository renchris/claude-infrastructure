#!/usr/bin/env bats
# cc-eligible — THE SUBJECT-FOREIGN ARM: the label is right and the work is somewhere else.
#
# tests/cc-eligible-cross-repo.bats guards the arm keyed on the pair (item's PROJECT, the lane).
# This suite guards the case that pair structurally cannot see: an item whose project label is
# ACCURATE — the plan really does live in this repo — while every wave it carries edits another
# tree. `8f59467c92b0` ("MASTER: product repos") is that row, and it burned three cloud slots
# (2026-08-15, 08-17, 08-24), the third AFTER the cross-repo arm had landed and passed it.
#
# WHY THE SIGNAL IS DECLARED AND NOT INFERRED. Two inferential repairs were filed before this one
# and both are refuted by measurement (recorded at FOREIGN_TREE in the subject):
#
#   · Reading the item's TEXT for another dispatch-set project cannot work — the text a classifier
#     gets is SPAN_FIELDS (title · dodRef · condition · source), and this row's four span fields
#     name no foreign tree. Only the plan BODY does.
#   · Reading the plan BODY cannot work either — 14 of the 45 open plans in docs/plans (31%) merely
#     MENTION reso-management-app or doc_classifier in passing, so a body scan refuses a third of
#     this repo's plan-derived work from cloud in order to catch one row. That is the subject's own
#     header failure: a denylist enumerates SPELLINGS, never the class.
#
# So the properties pinned here are the ones those two shapes could not give:
#
#   · IT BINDS IN BOTH DIRECTIONS. Every refusal case is paired with a control that must stay
#     eligible — an arm answering "foreign" unconditionally would satisfy every refusal assertion
#     in this file while refusing the entire store.
#   · A MENTION IS NOT A DECLARATION. Test 3 is the measured 31% guarded directly: a plan whose
#     BODY names both foreign trees and whose frontmatter declares nothing stays eligible.
#   · TWO TREES ARE EXPRESSIBLE. A cross-repo master targets two trees at once, which no
#     single-valued project field can route (MASTER_PRODUCT_REPOS.md, 2026-08-15). Test 4 pins both
#     in one refusal.
#   · IT FAILS OPEN ON EVERYTHING IT CANNOT MEASURE, this file's standing law: no dodRef, a dodRef
#     resolving to no file, a file with no frontmatter, a declared target that is a second checkout
#     of the lane's own origin.
#   · THE GATE ACTUALLY REFUSES. A verdict not in BLOCKING is a report, not a gate, so the exit
#     code is asserted alongside the token.
#
# Assertions use the explicit `|| { …; false; }` form: a non-final `[[ ]]` is errexit-EXEMPT under
# bats and would be a DEAD assertion that can never fail (memory: negated-assertion-dead-unless-final).
#
# RED-PROOF — MEASURED against the parent, not asserted, and pinned to a LITERAL parent sha rather
# than to the moving origin/main (a rebased land rewrites the object; a branch name does not stay
# put). That parent contains ZERO occurrences of `FOREIGN_TREE` and zero of `declared_targets` —
# counted with `grep -c`, never `grep -q`, which under pipefail fails on the very input it matched:
#
#     PAR=/tmp/cft-parent; mkdir -p $PAR/bin $PAR/tests
#     git show 7fbc0ffb7b2ba68bd47f6d7a667140710e4a2fdf:bin/cc-eligible > $PAR/bin/cc-eligible
#     chmod +x $PAR/bin/cc-eligible
#     cp bin/cc-backlog $PAR/bin/; cp "$BATS_TEST_FILENAME" $PAR/tests/
#     CC_BATS_MAX_ROOTS=0 bats $PAR/tests/cc-eligible-foreign-tree.bats
#
#   FAIL (5) — 1, 2, 4, 8, 9. These are the arm: each demands a refusal, a named tree, the class in
#              the census, or a blocked claim, and the parent has none of them.
#   PASS (5) — 3, 5, 6, 7, 10. All five assert the ELIGIBLE direction, which a parent that refuses
#              nothing gives away for free. They are NOT red-proofs; 5-7 are true fail-open controls
#              pinning behaviour this change had to preserve, and 3 and 10 become load-bearing only
#              once the arm exists, where they are the guard against the expensive false-positive
#              direction (memory: sibling-guard-makes-the-fixture-vacuous).

setup() {
  export CC_BACKLOG_PROJECT_WARN=off
  # Fixture $HOME FIRST — the subject resolves its store AND every project repo under it.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  CE="$REPO/bin/cc-eligible"
  CB="$REPO/bin/cc-backlog"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_BACKLOG_DISPATCH_BIN="$BATS_TEST_TMPDIR/absent-dispatch"
  # The history arm is NOT this suite's subject. Pinned so it certifies and stays silent; if it
  # ever fired it would shadow the verdict under test.
  export CC_ELIGIBLE_HISTORY_DEPTH=50
  DEV="$HOME/Development"; mkdir -p "$DEV"
}

# mkrepo <dir> <origin-url> → a real git repo with one commit and that origin.
#
# EVERY `git -C` takes a GUARDED expansion, never a bare "$d". `git -C ""` is a NO-OP, so an empty
# path would write user.email/user.name into whatever repo this process is standing in — and ~100
# worktrees on this box share ONE .git/config, so a single such call re-authors every session
# running. `${d:?…}` makes the empty case abort instead.
mkrepo() {
  local d="${1:?mkrepo: repo path required}" origin="${2:?mkrepo: origin url required}"
  mkdir -p "$d"
  git -C "${d:?mkrepo: repo path required}" init -q -b main
  git -C "${d:?mkrepo: repo path required}" config user.email t@t
  git -C "${d:?mkrepo: repo path required}" config user.name t
  echo x >"$d/f.txt"
  git -C "${d:?mkrepo: repo path required}" add f.txt
  git -C "${d:?mkrepo: repo path required}" -c commit.gpgsign=false commit -qm one
  git -C "${d:?mkrepo: repo path required}" remote add origin "$origin"
}

# The lane: a real repo whose origin is the one a VM would be given. The item's project IS the
# lane throughout this suite — that is the whole point, the label is never wrong here.
lane() {
  mkrepo "$DEV/lane" "git@github.com:acme/lane.git"
  export CC_ELIGIBLE_CLOUD_REPO="$DEV/lane"
}

# plan <relpath> <frontmatter-body> [prose] → writes a plan INTO the lane repo.
plan() {
  local rel="$1" fm="$2" prose="${3:-ordinary plan prose}"
  mkdir -p "$DEV/lane/$(dirname "$rel")"
  { echo '---'; printf '%s\n' "$fm"; echo '---'; echo; echo "$prose"; } >"$DEV/lane/$rel"
}

# additem <project> <title> [dodref] → echoes the id
additem() {
  if [ -n "${3:-}" ]; then
    "$CB" add --project "$1" --title "$2" --dod-ref "$3" 2>/dev/null | tr -d '[:space:]'
  else
    "$CB" add --project "$1" --title "$2" 2>/dev/null | tr -d '[:space:]'
  fi
}

@test "1: a DECLARED foreign tree is refused, though the item's own project IS the lane" {
  lane
  mkrepo "$DEV/other" "git@github.com:acme/other.git"
  plan docs/plans/M.md 'status: open
targets: other'
  id="$(additem lane 'MASTER: product repos' docs/plans/M.md)"
  run "$CE" check "$id"
  [ "$status" -eq 3 ] || { echo "expected exit 3, got $status: $output"; false; }
  [[ "${lines[0]}" == "verdict=ineligible-foreign-tree" ]] \
    || { echo "expected the foreign-tree verdict, got: ${lines[0]}"; false; }
}

@test "2: the refusal NAMES the tree, so a reader can act without opening the plan" {
  lane
  mkrepo "$DEV/other" "git@github.com:acme/other.git"
  plan docs/plans/M.md 'status: open
targets: other'
  id="$(additem lane 'MASTER: product repos' docs/plans/M.md)"
  run "$CE" why "$id"
  [[ "$output" == *"other"* ]] || { echo "the declared tree is not named: $output"; false; }
}

@test "3: A MENTION IS NOT A DECLARATION — the measured 31% stay eligible" {
  lane
  mkrepo "$DEV/other" "git@github.com:acme/other.git"
  # Body names the foreign tree repeatedly; frontmatter declares nothing. This is the shape of 14
  # of the 45 open plans in docs/plans, and refusing it would starve the cloud tap to catch one row.
  plan docs/plans/M.md 'status: open' \
    'This plan mentions other and other again, and compares itself to other at length.'
  id="$(additem lane 'tighten the ship rail' docs/plans/M.md)"
  run "$CE" check "$id"
  [ "$status" -eq 0 ] || { echo "a mere mention must not refuse, got $status: $output"; false; }
  [[ "${lines[0]}" == "verdict=eligible" ]] \
    || { echo "expected eligible, got: ${lines[0]}"; false; }
}

@test "4: TWO TREES are expressible in one refusal — the cross-repo master shape" {
  lane
  mkrepo "$DEV/alpha" "git@github.com:acme/alpha.git"
  mkrepo "$DEV/beta"  "git@github.com:acme/beta.git"
  plan docs/plans/M.md 'status: open
targets: alpha, beta'
  id="$(additem lane 'MASTER: product repos' docs/plans/M.md)"
  run "$CE" why "$id"
  [[ "$output" == *"alpha"* ]] || { echo "first tree missing: $output"; false; }
  [[ "$output" == *"beta"*  ]] || { echo "second tree missing: $output"; false; }
}

@test "5: FAIL-OPEN — a dodRef that resolves to no file is not measured, and does not refuse" {
  lane
  mkrepo "$DEV/other" "git@github.com:acme/other.git"
  id="$(additem lane 'MASTER: product repos' docs/plans/ABSENT.md)"
  run "$CE" check "$id"
  [ "$status" -eq 0 ] || { echo "an absent dodRef must fail open, got $status: $output"; false; }
  [[ "${lines[0]}" == "verdict=eligible" ]] || { echo "expected eligible, got: ${lines[0]}"; false; }
}

@test "6: FAIL-OPEN — no dodRef at all is not measured, and does not refuse" {
  lane
  id="$(additem lane 'ordinary in-repo work')"
  run "$CE" check "$id"
  [ "$status" -eq 0 ] || { echo "a dodRef-less item must fail open, got $status: $output"; false; }
  [[ "${lines[0]}" == "verdict=eligible" ]] || { echo "expected eligible, got: ${lines[0]}"; false; }
}

@test "7: TWO CHECKOUTS OF ONE REPO ARE ONE REPO — a declared target on the lane's origin is fine" {
  lane
  # Declared, but it is a second checkout of the LANE's own origin. Reachable after all; refusing
  # here is the expensive false-positive direction.
  mkrepo "$DEV/lane-wt" "git@github.com:acme/lane.git"
  plan docs/plans/M.md 'status: open
targets: lane-wt'
  id="$(additem lane 'MASTER: product repos' docs/plans/M.md)"
  run "$CE" check "$id"
  [ "$status" -eq 0 ] || { echo "same origin must stay eligible, got $status: $output"; false; }
  [[ "${lines[0]}" == "verdict=eligible" ]] || { echo "expected eligible, got: ${lines[0]}"; false; }
}

@test "8: the census carries the class, so it cannot be invisible in the report" {
  lane
  # The census needs a readable store, else it fails open with `unknown-store` and asserts nothing.
  additem lane 'ordinary in-repo work' >/dev/null
  run "$CE" sweep
  [[ "$output" == *"ineligible-foreign-tree"* ]] \
    || { echo "SWEEP_ROWS must carry the foreign-tree class: $output"; false; }
}

@test "9: THE GATE ACTUALLY REFUSES — claim --venue cloud is blocked, claim local is not" {
  lane
  mkrepo "$DEV/other" "git@github.com:acme/other.git"
  plan docs/plans/M.md 'status: open
targets: other'
  export CC_BACKLOG_ELIGIBLE_BIN="$CE"
  id="$(additem lane 'MASTER: product repos' docs/plans/M.md)"
  run "$CB" claim "$id" --by t --venue cloud
  [ "$status" -ne 0 ] || { echo "the cloud claim must be refused: $output"; false; }
  # The REFUSAL_NOTE's own promise: only --venue cloud is refused, the work is untouched locally.
  id2="$(additem lane 'MASTER: product repos two' docs/plans/M.md)"
  run "$CB" claim "$id2" --by t
  [ "$status" -eq 0 ] || { echo "the LOCAL claim must proceed untouched: $output"; false; }
}

@test "10: a target naming the item's OWN project is CROSS_REPO's case, not double-counted here" {
  lane
  plan docs/plans/M.md 'status: open
targets: lane'
  id="$(additem lane 'MASTER: product repos' docs/plans/M.md)"
  run "$CE" check "$id"
  [ "$status" -eq 0 ] || { echo "self-target must not refuse, got $status: $output"; false; }
  [[ "${lines[0]}" == "verdict=eligible" ]] || { echo "expected eligible, got: ${lines[0]}"; false; }
}
