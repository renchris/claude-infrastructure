#!/usr/bin/env bats
# cc-eligible — THE REACH ARM: is the item's project the ONE repo a cloud VM is given?
#
# The sibling suites guard the other two halves: tests/cc-eligible.bats guards the SPELLING table
# and says in its own header that asserting "launchd is refused" proves only that one string is in
# one array; tests/cc-eligible-history.bats guards the clone-depth measurement. This suite guards
# the half that is not a word and not a horizon — a property of the PAIR (item's project, the repo
# `cc-offload` attaches) — and it is the half that was missing while 106 of 133 cloud sessions were
# dispatched at a repo their VM never received.
#
# WHY THIS CLASS CANNOT BE A SPELLING. Every CLASSES entry is a regex over the item's text, so it
# refuses only an item that happens to SAY a refused word. An item can name another repo's files
# without naming the repo — which is exactly how `4abcbbbbc997` reached a VM by spelling its
# worktree `wt-bsm-gap` and never the word `worktree`. So the properties pinned here are the ones a
# spelling test structurally cannot reach:
#
#   · IT BINDS IN BOTH DIRECTIONS. Every refusal case is paired with a control that must stay
#     eligible. An arm that answered "elsewhere" unconditionally would satisfy every refusal
#     assertion here while refusing the entire store — the same trap the history suite names.
#   · TWO CHECKOUTS OF ONE REPO ARE ONE REPO. Compared by normalised ORIGIN, not by path, so a
#     worktree or a second clone is reachable. This is the false-positive direction and it is the
#     expensive one: it would refuse work that is in fact perfectly runnable off-box.
#   · THE ARM FAILS OPEN ON EVERYTHING IT CANNOT MEASURE, which is this file's standing law. The
#     unmeasurable states are a projectless item, an unresolvable lane, and a lane path that is not
#     a readable git repo. That last one is what a fixtured $HOME produces, and it is the reason
#     all seven sibling suites still pass unchanged.
#   · THE GATE ACTUALLY REFUSES. A verdict that is not in BLOCKING is a report, not a gate, so the
#     exit code is asserted alongside the token — `cc-backlog claim --venue cloud` reads `head -1`
#     and the exit status, and nothing else.
#
# Assertions use the explicit `|| { …; false; }` form: a non-final `[[ ]]` is errexit-EXEMPT under
# bats and would be a DEAD assertion that can never fail (memory: negated-assertion-dead-unless-final).
#
# RED-PROOF — MEASURED, not asserted, and pinned to a LITERAL parent sha rather than to the moving
# origin/main (a rebased land rewrites the object; a branch name does not stay put):
#
#     PAR=/tmp/ce-parent-repo; mkdir -p $PAR/bin $PAR/tests
#     git show 219697c323c539f16436175fe2cf19c7fcaa7a7a:bin/cc-eligible > $PAR/bin/cc-eligible
#     chmod +x $PAR/bin/cc-eligible; cp bin/cc-backlog $PAR/bin/; cp "$BATS_TEST_FILENAME" $PAR/tests/
#     CC_BATS_MAX_ROOTS=0 bats $PAR/tests/cc-eligible-cross-repo.bats
#
# That parent contains ZERO occurrences of `cross_repo` and zero of `CROSS_REPO` — counted with
# `grep -c`, never `grep -q`, which under pipefail fails on the very input it matched. Ran against
# it, the split is:
#
#   FAIL (5) — 1, 3, 9, 10, 11. These are the arm. Each demands a refusal, a named origin pair, a
#              class in the census or a blocked claim, and the parent has none of them.
#   PASS (6) — 2, 4, 5, 6, 7, 8. All six assert the ELIGIBLE direction, which a parent that refuses
#              nothing gives away for free, so none of them can be a red-proof.
#
# THOSE SIX ARE NOT INTERCHANGEABLE, and the difference is worth stating because it decides what
# they are worth. 6-8 are true fail-open controls: they pin behaviour this change had to PRESERVE,
# and they are load-bearing on BOTH sides of the fix. 2, 4 and 5 are VACUOUS against the parent by
# construction — with no arm present, "not refused" is the only answer available — and they become
# load-bearing only once the arm exists, where they are the guard against the expensive
# false-positive direction (memory: sibling-guard-makes-the-fixture-vacuous). Reading their green
# on the parent as evidence of anything would be the trap.

setup() {
  export CC_BACKLOG_PROJECT_WARN=off
  # Fixture $HOME FIRST — the subject resolves its store AND every project repo under it.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  CE="$REPO/bin/cc-eligible"
  CB="$REPO/bin/cc-backlog"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_BACKLOG_DISPATCH_BIN="$BATS_TEST_TMPDIR/absent-dispatch"
  # The history arm is NOT this suite's subject. Pinned to a repo-less project so it certifies
  # `no-repo` and stays silent; if it ever fired it would shadow the verdict under test.
  export CC_ELIGIBLE_HISTORY_DEPTH=50
  DEV="$HOME/Development"; mkdir -p "$DEV"
}

# mkrepo <dir> <origin-url> → a real git repo with one commit and that origin.
#
# EVERY `git -C` here takes a GUARDED expansion, never a bare "$d". `git -C ""` is a NO-OP, so an
# empty path would write user.email/user.name into whatever repo this process is standing in — and
# ~100 worktrees on this box share ONE .git/config, so a single such call re-authors every session
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

# additem <project> <title> → echoes the id
additem() {
  "$CB" add --project "$1" --title "$2" 2>/dev/null | tr -d '[:space:]'
}

# The lane: a real repo whose origin is the one a VM would be given.
lane() {
  mkrepo "$DEV/lane" "git@github.com:acme/lane.git"
  export CC_ELIGIBLE_CLOUD_REPO="$DEV/lane"
}

@test "1: an item whose project is ANOTHER repo is refused as ineligible-cross-repo" {
  lane
  mkrepo "$DEV/other" "git@github.com:acme/other.git"
  id="$(additem other 'rename the exported helpers')"
  run "$CE" check "$id"
  [ "$status" -eq 3 ] || { echo "expected exit 3, got $status: $output"; false; }
  [[ "${lines[0]}" == "verdict=ineligible-cross-repo" ]] \
    || { echo "expected the reach verdict, got: ${lines[0]}"; false; }
}

@test "2: CONTROL — an item in the LANE's own repo stays eligible" {
  lane
  id="$(additem lane 'rename the exported helpers')"
  run "$CE" check "$id"
  [ "$status" -eq 0 ] || { echo "expected exit 0, got $status: $output"; false; }
  [[ "${lines[0]}" == "verdict=eligible" ]] \
    || { echo "the lane's own repo must stay eligible, got: ${lines[0]}"; false; }
}

@test "3: the refusal names BOTH origins, so a reader can act without re-deriving them" {
  lane
  mkrepo "$DEV/other" "git@github.com:acme/other.git"
  id="$(additem other 'rename the exported helpers')"
  run "$CE" why "$id"
  [[ "$output" == *"acme/other"* ]] || { echo "no item origin in: $output"; false; }
  [[ "$output" == *"acme/lane"* ]]  || { echo "no lane origin in: $output"; false; }
}

@test "4: TWO CHECKOUTS OF ONE REPO ARE ONE REPO — same origin, different path, still eligible" {
  lane
  # A second checkout of the SAME origin under a different project name. Path differs; repo does not.
  mkrepo "$DEV/lane-wt" "git@github.com:acme/lane.git"
  id="$(additem lane-wt 'rename the exported helpers')"
  run "$CE" check "$id"
  [ "$status" -eq 0 ] || { echo "a second checkout of the lane must not be refused: $output"; false; }
  [[ "${lines[0]}" == "verdict=eligible" ]] || { echo "got: ${lines[0]}"; false; }
}

@test "5: origin SPELLING is normalised — https and scp forms of one repo are one repo" {
  mkrepo "$DEV/lane" "https://github.com/acme/lane"
  export CC_ELIGIBLE_CLOUD_REPO="$DEV/lane"
  mkrepo "$DEV/mirror" "git@github.com:acme/lane.git"
  id="$(additem mirror 'rename the exported helpers')"
  run "$CE" check "$id"
  [ "$status" -eq 0 ] \
    || { echo "https vs scp spelling of ONE repo must not read as two: $output"; false; }
}

@test "6: FAIL-OPEN — a lane that is not a readable git repo disables the arm" {
  export CC_ELIGIBLE_CLOUD_REPO="$DEV/not-a-repo"   # never created
  mkrepo "$DEV/other" "git@github.com:acme/other.git"
  id="$(additem other 'rename the exported helpers')"
  run "$CE" check "$id"
  [ "$status" -eq 0 ] || { echo "an unmeasurable lane must fail OPEN, got $status: $output"; false; }
}

@test "7: FAIL-OPEN — the empty kill switch disables the arm outright" {
  mkrepo "$DEV/lane" "git@github.com:acme/lane.git"
  mkrepo "$DEV/other" "git@github.com:acme/other.git"
  export CC_ELIGIBLE_CLOUD_REPO=""                  # set, but empty
  id="$(additem other 'rename the exported helpers')"
  run "$CE" check "$id"
  [ "$status" -eq 0 ] || { echo "the kill switch must fail OPEN, got $status: $output"; false; }
}

@test "8: FAIL-OPEN — a projectless item is not refused on reach" {
  lane
  # Written straight to the store: `add` resolves a project from cwd, and the state under test is
  # an item that carries NONE.
  printf '{"event":"add","id":"aaaaaaaaaaaa","title":"no project anywhere","ts":1}\n' \
    >>"$CC_BACKLOG_FILE"
  run "$CE" check aaaaaaaaaaaa
  [ "$status" -eq 0 ] || { echo "a projectless item must fail OPEN, got $status: $output"; false; }
}

@test "9: the SPELLING table still leads when both fire — reach does not shadow an actionable word" {
  lane
  mkrepo "$DEV/other" "git@github.com:acme/other.git"
  id="$(additem other 'the launchd plist needs its StartInterval raised')"
  run "$CE" check "$id"
  [ "$status" -eq 3 ] || { echo "expected a refusal, got $status: $output"; false; }
  [[ "${lines[0]}" == "verdict=ineligible-box" ]] \
    || { echo "the spelled class must lead; got: ${lines[0]}"; false; }
  # …and `why` must still report the reach class, or the census loses a real member.
  run "$CE" why "$id"
  [[ "$output" == *"ineligible-cross-repo"* ]] \
    || { echo "why must report every class that fired: $output"; false; }
}

@test "10: the census renders the reach class — a measured class must not be invisible" {
  lane
  mkrepo "$DEV/other" "git@github.com:acme/other.git"
  # The census needs a readable store, else it fails open with `unknown-store` and asserts nothing.
  additem other 'rename the exported helpers' >/dev/null
  run "$CE" sweep
  [[ "$output" == *"ineligible-cross-repo"* ]] \
    || { echo "SWEEP_ROWS must carry the reach class: $output"; false; }
}

@test "11: THE GATE ACTUALLY REFUSES — claim --venue cloud is blocked, claim local is not" {
  lane
  mkrepo "$DEV/other" "git@github.com:acme/other.git"
  export CC_BACKLOG_ELIGIBLE_BIN="$CE"
  id="$(additem other 'rename the exported helpers')"
  run "$CB" claim "$id" --by t --venue cloud
  [ "$status" -ne 0 ] || { echo "the cloud claim must be refused: $output"; false; }
  # The REFUSAL_NOTE's own promise: only --venue cloud is refused, the work is untouched locally.
  id2="$(additem other 'rename the other exported helpers')"
  run "$CB" claim "$id2" --by t
  [ "$status" -eq 0 ] || { echo "a LOCAL claim must proceed untouched: $output"; false; }
}
