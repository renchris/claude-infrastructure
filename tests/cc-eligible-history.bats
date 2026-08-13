#!/usr/bin/env bats
# cc-eligible — THE MEASURED ARM: can a cloud VM's shallow clone see the history an item cites?
#
# The sibling suite (tests/cc-eligible.bats) guards the SPELLING half and says in its own header
# that a suite asserting "launchd is refused" proves only that one string is in one array. This
# suite guards the half that is not a string at all, and the properties worth pinning are the ones
# an edit can silently break in the EXPENSIVE direction — a wrong ELIGIBLE puts a worker in a VM
# against history it cannot read, and it improvises a plausible answer rather than failing:
#
#   · the horizon test binds IN BOTH DIRECTIONS. Every refusal case is paired with a control that
#     must stay eligible, because a `sha not in set` that always answered "not in set" would pass
#     every refusal assertion here while refusing the entire store.
#   · A NON-RESOLVING HEX TOKEN IS NOT A REFUSAL. Backlog ids are 12 hex characters and the store
#     is full of items citing each other; an arm that convicted on "does not resolve" would route
#     almost nothing to cloud, and would look like a working classifier while doing it.
#   · THE SHALLOW GUARD IS A FACT ABOUT THE CLONE, NOT ABOUT THE SHA — pinned by running the SAME
#     item against a full clone and a shallow one and requiring the verdicts to differ. Without
#     that control, "shallow ⇒ no refusal" is indistinguishable from "this sha was reachable".
#   · THE GATE STAYS FAIL-OPEN. Every uncertified state exits 0. cc-venue is what fails closed on
#     them (tests/cc-venue.bats), and the two directions must be pinned in the files that own them.
#
# Assertions use the explicit `|| { …; false; }` form: a non-final `[[ ]]` is errexit-EXEMPT under
# bats and would be a DEAD assertion that can never fail.
#
# RED-PROOF (re-runnable): `git show origin/main:bin/cc-eligible` has no HistoryOracle, no `why`
# verb and none of the three new classes, so cases 1-8 and 11-15 fail against it — 1-8 because the
# measured arm does not exist (every item reads `eligible`), 11-15 because the tokens do not.
# Cases 9 and 10 are the fail-open controls and pass there too, which is correct: they pin
# behaviour this change had to PRESERVE.

setup() {
  # Project labels in this suite are FIXTURES, not projects — and `cc-backlog add` now WARNS on an
  # explicit --project outside the dispatch set (df2b6a40a5dc), which bats folds into $output. Off
  # here because dispatchability is not this suite's subject; tests/cc-backlog-project-dispatch.bats
  # owns it, unfixtured, in both directions.
  export CC_BACKLOG_PROJECT_WARN=off
  # Fixture $HOME FIRST — the subject resolves both its store (~/.claude/autonomy/backlog.jsonl)
  # AND its repo ($HOME/Development/<project>) under it, so an unfixtured HOME would classify the
  # operator's real 5,700-record ledger against the operator's real checkouts.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  CE="$REPO/bin/cc-eligible"
  CB="$REPO/bin/cc-backlog"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_BACKLOG_DISPATCH_BIN="$BATS_TEST_TMPDIR/absent-dispatch"
  # A 3-commit horizon over a 6-commit repo: small enough to read, wide enough that "inside" and
  # "outside" are both non-empty. The production default is 50, the measured depth of a real clone.
  export CC_ELIGIBLE_HISTORY_DEPTH=3
  # NO CAPACITY PIN, and its absence is the assertion. This suite's only mention of handoff-fire is
  # a FIXTURE TITLE — the specification of an item the classifier must REFUSE — and nothing here
  # fires anything. It used to carry `export CC_FIRE_CAPACITY_GATE=off` purely because the
  # hermeticity ratchet read that sentence as an invocation; the pin was a permanent no-op, which is
  # how a pin stops meaning anything. Fixed at the detector (scripts/test-hermeticity-lint.sh
  # § strip_prose): a name followed by two bare lowercase words is prose, not a reference. If that
  # regresses, this file goes red again — which makes its missing pin the live proof of the fix.
  G="$HOME/Development/probe"
}

# mkrepo → a real git repo at $G with 6 commits on main; sets $OLD (commit 1) and $NEW (commit 6).
mkrepo() {
  mkdir -p "$G"
  git -C "${G:?repo path required}" init -q -b main
  # THE ARGUMENT IS ASSERTED, not the chain. `git -C ""` is a documented NO-OP rather than an
  # error, so an empty $G would drop this identity into whatever repo the process is standing in —
  # and ~100 linked worktrees here share ONE .git/config, so a single such line re-authors every
  # session on the box. A `&&`/`||` guard does not rescue it either: `cd ""` exits 0.
  git -C "${G:?repo path required}" config user.email t@e.com
  git -C "${G:?repo path required}" config user.name t
  local i
  for i in 1 2 3 4 5 6; do
    echo "$i" > "$G/f$i"; git -C "$G" add "f$i"; git -C "$G" commit -qm "c$i"
  done
  # `origin/main` is what the oracle prefers, and it must be a REAL remote-tracking ref rather than
  # a branch named "origin/main" — the production path reads a clone, so a fixture that faked the
  # name would exercise a resolution the real one never takes.
  git -C "$G" update-ref refs/remotes/origin/main "$(git -C "$G" rev-parse main)"
  OLD="$(git -C "$G" rev-list main | tail -1)"
  NEW="$(git -C "$G" rev-parse main)"
}

add() { "$CB" add --title "$2" --project "${3:-probe}" --source "$1"; }
verdict() { "$CE" check "$1" 2>&1 | head -1; }

# ── the horizon, in both directions ─────────────────────────────────────────────────────────────

@test "1 a cited sha OUTSIDE the horizon is REFUSED under its own token" {
  mkrepo
  local id; id="$(add h "the fix landed in ${OLD:0:8} — check what it changed")"
  run "$CE" check "$id"
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  [[ "$output" == *"verdict=ineligible-deep-history"* ]] || { echo "$output"; false; }
  [[ "$output" == *"${OLD:0:8}"* ]] || { echo "named the class but not the sha: $output"; false; }
}

@test "2 CONTROL: a cited sha INSIDE the horizon stays ELIGIBLE — the pin can fail" {
  mkrepo
  local id; id="$(add h "the fix landed in ${NEW:0:8} — check what it changed")"
  run "$CE" check "$id"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"verdict=eligible"* ]] || { echo "$output"; false; }
}

@test "3 the horizon is a DEPTH, not a date — widening it retracts the refusal" {
  mkrepo
  local id; id="$(add h "the fix landed in ${OLD:0:8}")"
  run "$CE" check "$id"
  [ "$status" -eq 3 ] || { echo "narrow horizon should refuse: $output"; false; }
  CC_ELIGIBLE_HISTORY_DEPTH=99 run "$CE" check "$id"
  [ "$status" -eq 0 ] || { echo "a horizon covering the whole repo must not refuse: $output"; false; }
}

# ── the token that is NOT a sha — the arm that would otherwise convict the whole store ──────────

@test "4 a 12-hex token that resolves to NOTHING is NOT a refusal (backlog ids are 12 hex)" {
  mkrepo
  # Shaped exactly like the ids this ledger mints, and citing another item is the single commonest
  # thing a backlog title does. If this convicted, the cloud tap would be near-empty and would look
  # like a working classifier while it happened.
  local id; id="$(add h "supersedes backlog item 4f2eaa26ae83 — same root cause")"
  run "$CE" check "$id"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"verdict=eligible"* ]] || { echo "$output"; false; }
}

@test "5 CONTROL: the SAME item shape DOES refuse once that token names a real commit" {
  mkrepo
  # The discriminator is resolvability, not shape: same sentence, a real pre-horizon sha. Without
  # this pairing, case 4 would also pass over an arm that had simply stopped working.
  local id; id="$(add h "supersedes backlog item ${OLD:0:12} — same root cause")"
  run "$CE" check "$id"
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  [[ "$output" == *"verdict=ineligible-deep-history"* ]] || { echo "$output"; false; }
}

# ── THE SHALLOW GUARD ───────────────────────────────────────────────────────────────────────────

@test "6 THE GUARD, stated as a fact about the CLONE: same item, two clones, two verdicts" {
  mkrepo
  git clone -q --bare "$G" "$BATS_TEST_TMPDIR/origin"
  local id; id="$(add h "the fix landed in ${OLD:0:8}")"

  # (a) the FULL clone — the positive control. Without it, (b) proves only that nothing refused.
  run "$CE" check "$id"
  [ "$status" -eq 3 ] || { echo "full clone must refuse: $output"; false; }

  # (b) the SHALLOW clone of the very same history.
  rm -rf "$G"
  git clone -q --depth 2 "file://$BATS_TEST_TMPDIR/origin" "$G"
  [ "$(git -C "$G" rev-parse --is-shallow-repository)" = true ] \
    || skip "clone --depth did not produce a shallow repo here"
  run "$CE" check "$id"
  [ "$status" -eq 0 ] || { echo "shallow clone must abstain, not refuse: $output"; false; }
  run "$CE" why "$id"
  [[ "$output" == *"shallow"* ]] || { echo "the state must be NAMED, not merely silent: $output"; false; }
}

@test "7 why --json carries the certification, so a producer can fail closed on it" {
  mkrepo
  local id; id="$(add h "ordinary repo work")"
  run "$CE" why "$id" --json
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  echo "$output" | jq -e '.history.state == "ok"' >/dev/null \
    || { echo "$output"; false; }
  echo "$output" | jq -e '.history.depth == 3 and (.history.ref | test("origin/main"))' >/dev/null \
    || { echo "$output"; false; }
}

@test "8 why --json lists EVERY class that fired, not just the one check reports" {
  mkrepo
  # Both a spelling class and the measured one. `check` has only `head -1` and must pick; a producer
  # recording the reason must not lose the other half.
  local id; id="$(add h "restart the launchd daemon — regression from ${OLD:0:8}")"
  run "$CE" why "$id" --json
  echo "$output" | jq -e '[.classes[].verdict] | index("ineligible-box")' >/dev/null \
    || { echo "$output"; false; }
  echo "$output" | jq -e '[.classes[].verdict] | index("ineligible-deep-history")' >/dev/null \
    || { echo "$output"; false; }
  # …and the ORDER holds: the spelling leads, because it names a word a human can act on.
  echo "$output" | jq -e '.verdict == "ineligible-box"' >/dev/null || { echo "$output"; false; }
}

# ── fail-open: the gate must never be starved by an instrument outage ───────────────────────────

@test "9 FAIL-OPEN: no repo for the project ⇒ exit 0, and the state is NAMED" {
  local id; id="$(add h "the fix landed in deadbee — no repo exists for this project")"
  run "$CE" check "$id"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  run "$CE" why "$id" --json
  echo "$output" | jq -e '.history.state == "no-repo"' >/dev/null || { echo "$output"; false; }
}

@test "10 FAIL-OPEN: a projectless item is not measured, and does not refuse" {
  mkrepo
  # No project ⇒ no repo can be resolved ⇒ nothing to certify. It must abstain rather than measure
  # against whatever tree the process happens to be sitting in.
  printf '%s\n' '{"id":"noproj00","ts":"2026-01-01T00:00:00Z","event":"add","title":"work"}' \
    >> "$CC_BACKLOG_FILE"
  run "$CE" check noproj00
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  run "$CE" why noproj00 --json
  echo "$output" | jq -e '.history.state == "no-repo"' >/dev/null || { echo "$output"; false; }
}

# ── the three new spelling classes, each with a control that must stay eligible ─────────────────

@test "11 OFF-BOX LANE: the lane cannot verify a change to itself" {
  mkrepo
  local id; id="$(add l "off-box payload pushes to an invented branch name — call the cc-cloud preflight")"
  run "$CE" check "$id"
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  [[ "$output" == *"verdict=ineligible-offbox-lane"* ]] || { echo "$output"; false; }
}

@test "12 OFF-BOX LANE covers an item asking to edit the venue rule ITSELF" {
  mkrepo
  local id; id="$(add l "shrink the venue exclusion list with a census run")"
  run "$CE" check "$id"
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  [[ "$output" == *"verdict=ineligible-offbox-lane"* ]] || { echo "$output"; false; }
}

@test "13 SPAWN RAIL: its own token, and the SPACED spelling counts too" {
  mkrepo
  local a b
  a="$(add s "patch scripts/handoff-fire.sh so the recycle inherits the goal")"
  b="$(add s2 "the handoff fire queue re-fires a track whose branch was pruned")"
  run "$CE" check "$a"
  [[ "$output" == *"verdict=ineligible-spawn-rail"* ]] || { echo "$output"; false; }
  run "$CE" check "$b"
  [[ "$output" == *"verdict=ineligible-spawn-rail"* ]] || { echo "spaced spelling missed: $output"; false; }
}

@test "14 GITHUB: refused, and the PR spelling is CASE-SENSITIVE" {
  mkrepo
  local a b
  a="$(add g "open a pull request against the upstream repo")"
  b="$(add g2 "the pr counter in the dashboard is off by one")"
  run "$CE" check "$a"
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  [[ "$output" == *"verdict=ineligible-github"* ]] || { echo "$output"; false; }
  # CONTROL: lowercase `pr` is an ordinary two-letter token and must NOT refuse under `pr`.
  run "$CE" check "$b"
  [[ "$output" != *"named: pr"* ]] || { echo "lowercase pr must not fire: $output"; false; }
}

@test "15 ORDER: a self-referential class outranks box work; the MEASURED class comes last" {
  mkrepo
  local a b
  a="$(add o "the off-box lane needs a launchd plist to run its sweep")"
  b="$(add p "restart the launchd daemon — regression from ${OLD:0:8}")"
  run "$CE" check "$a"
  [[ "$output" == *"verdict=ineligible-offbox-lane"* ]] \
    || { echo "the lane must outrank box work: $output"; false; }
  run "$CE" check "$b"
  [[ "$output" == *"verdict=ineligible-box"* ]] \
    || { echo "a spelling must outrank the measured class: $output"; false; }
}

@test "16 CONTROL: ordinary repo work with no citation is ELIGIBLE under a certified horizon" {
  mkrepo
  # The bucket every refusal above is measured against. If this ever went red, every case in this
  # file would still pass while the classifier refused the whole store.
  local id; id="$(add c "add a bats case for the tsv-pad helper")"
  run "$CE" check "$id"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"verdict=eligible"* ]] || { echo "$output"; false; }
}
