#!/usr/bin/env bats
# fleet-manifest-lint — the CHOKEPOINT that stops a launchd plist from landing UNDECLARED.
#
# THE SCAR, AND IT IS THE SIXTH OF ITS SHAPE (backlog 62f54195c398, cure landed 307f9749d).
# bd016b0a0 committed launchd/com.claude.browse-mirror.plist with no row in launchd/fleet.manifest.
# cc-fleet's unit of coverage is A LINE IN THAT MANIFEST (DAEMON_FLEET_V2 §4.1), so the label was not
# merely unalarmed — every leg of the tool was blind to it. tests/cc-fleet.bats caught it correctly
# and caught it POST-land, where it sat RED on trunk for 92 commits, tripping every lander after it,
# until postland-verify bisected it and dispatched a worker to repair it forward. Its five
# predecessors are named in fleet.manifest's own comment blocks (capacity-alarm, scratchpad-reaper,
# devserver-gc, browser-spin-guard 438883e365ec, permission-harvest c893ce32210b).
#
# WHY A LINT AND NOT JUST THAT SUITE. tests/cc-fleet.bats is a `--direct` suite of any diff touching
# launchd/, so the land gate in principle already ran it — but the land's smoke is LOAD-SHED on a busy
# box (R7), and the box was at load 244 for 438883e365ec, from the very wedge that plist existed to
# catch. The land most likely to add a plist is the one least able to afford a suite. DAEMON_FLEET_V2
# §4.4 already specified the answer — "the manifest lint runs in `run_gate` so an undeclared or
# unmirrored plist cannot land" — and fleet.manifest's header asserted for months that such a lint
# existed. It did not (memory: spec-named-mechanism-may-be-prose-only). This suite guards the one
# that now does.
#
# Harness laws: L1 the fixtures are real directory trees driven through the real script — nothing
# about the predicate is stubbed; L2 every assertion is failure-distinct (a mutant that deletes the
# row FAILS and the same tree with the row PASSES, so neither "always red" nor "always green"
# survives); L3 `[ ]` / `grep -q` only; L4 the fail-closed rc-2 path is tested in every direction,
# because a lint that reports health when it cannot read its subject is worse than no lint.
#
# HERMETICITY. Nothing here spawns git, reads $HOME, or touches launchd — the subject is a pure
# function of a directory tree, which is exactly why it is admissible in a land gate at all (the
# LIVE-ONLY / CONTENT-DRIFT half of §4.4 reads host state and deliberately stays in
# `bin/cc-fleet --plist-parity`).

setup() {
  # Fixture $HOME even though the subject never reads it: scripts/test-hermeticity-lint.sh requires
  # it of every suite, and the requirement is right in general — a suite that runs against the live
  # ~/ can mutate operator state, and "this one happens not to" is a property that rots with the
  # next edit. (Caught by the land gate on this very commit, which is the arm working.)
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LINT="$REPO/scripts/fleet-manifest-lint.sh"
  R="$BATS_TEST_TMPDIR/tree"
  mkdir -p "$R/launchd"
}

# A MINIMAL well-formed fixture: one committed plist, one legal row declaring it.
mkfix() {
  : > "$R/launchd/com.claude.alpha.plist"
  printf '# header comment\n\n' > "$R/launchd/fleet.manifest"
  printf 'com.claude.alpha | run | 600 | auto | 11 | 18-fleet-activate.sh\n' >> "$R/launchd/fleet.manifest"
}

@test "the lint exists and is executable" {
  [ -x "$LINT" ]
}

# THE INSTRUMENT'S OWN DISCRIMINATION PROOF. run_gate refuses to trust a clean verdict from a lint
# whose --selftest fails, so this is the assertion that keeps the gate arm meaningful rather than
# decorative.
@test "--selftest passes: the lint discriminates in both directions" {
  run "$LINT" --selftest
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'both directions proven'
}

# ── the GREEN control. Without it every RED case below could pass for the wrong reason ────────────
@test "a well-formed tree is GREEN, and the verdict states its denominator" {
  mkfix
  run "$LINT" "$R"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'OK   fleet-manifest'
  # A clean result whose population nobody stated is not auditable: a glob that matched NOTHING
  # would otherwise read exactly like a pass (memory: police-the-denominator).
  printf '%s' "$output" | grep -q '1 committed plist(s) all declared across 1 manifest row(s)'
}

# ── THE INCIDENT ITSELF, replayed as a mutant ─────────────────────────────────────────────────────
@test "an undeclared com.claude plist is RED and the output NAMES it" {
  mkfix
  : > "$R/launchd/com.claude.browse-mirror.plist"
  run "$LINT" "$R"
  [ "$status" -eq 1 ]
  printf '%s' "$output" | grep -q "no row for 'com.claude.browse-mirror'"
}

@test "the com.chrisren family is walked too, not only com.claude" {
  mkfix
  : > "$R/launchd/com.chrisren.beta.plist"
  run "$LINT" "$R"
  [ "$status" -eq 1 ]
  printf '%s' "$output" | grep -q "no row for 'com.chrisren.beta'"
}

# ── the ANCHOR's two directions. Both of these were WRITTEN BACKWARDS first and a mutation run
# caught it: dropping the `^...  *|` anchor left the original fixture red either way, so the test
# proved nothing about the anchor at all. These are the two mutants that actually kill it
# (memory: green-in-both-arms-is-an-equivalence-guard-not-a-red-proof).
#
# DIRECTION 1 — the ` *|` column tail. Without it, `^com.claude.alpha` is a PREFIX of the row
# `com.claude.alpha-extra | ...`, so a LONGER row silently discharges a SHORTER label and the lint
# passes over a genuinely undeclared plist (memory: greedy-anchor-matches-the-longer-token).
@test "a LONGER row does not discharge a shorter label" {
  : > "$R/launchd/com.claude.alpha.plist"
  printf 'com.claude.alpha-extra | run | 600 | auto | 11 | 18-fleet-activate.sh\n' > "$R/launchd/fleet.manifest"
  run "$LINT" "$R"
  [ "$status" -eq 1 ]
  printf '%s' "$output" | grep -q "no row for 'com.claude.alpha'"
}

# DIRECTION 2 — the `^` anchor. Without it the label matches ANYWHERE on a line, so a comment that
# merely MENTIONS the label declares it — the detector matching its own documentation, and
# fleet.manifest's header is full of prose naming real labels.
@test "a COMMENT mentioning the label does not declare it" {
  : > "$R/launchd/com.claude.alpha.plist"
  printf '# see com.claude.alpha | run | 600 | auto | 11 | 18-fleet-activate.sh\n' > "$R/launchd/fleet.manifest"
  run "$LINT" "$R"
  [ "$status" -eq 1 ]
  printf '%s' "$output" | grep -q "no row for 'com.claude.alpha'"
}

# ── one mutant per LEGAL-VALUE constraint, so a green suite credits each site ──────────────────────
# (memory: per-site-mutation-attributes-coverage — a suite green over three constraints at once
# credits none of them individually.)
@test "an illegal expect is RED" {
  mkfix
  printf 'com.claude.g | running | 60 | auto | 1 | x.sh\n' >> "$R/launchd/fleet.manifest"
  run "$LINT" "$R"
  [ "$status" -eq 1 ]
  printf '%s' "$output" | grep -q "illegal expect 'running'"
}

@test "a non-numeric interval_s is RED" {
  mkfix
  printf 'com.claude.g | run | 10m | auto | 1 | x.sh\n' >> "$R/launchd/fleet.manifest"
  run "$LINT" "$R"
  [ "$status" -eq 1 ]
  printf '%s' "$output" | grep -q "illegal interval_s '10m'"
}

@test "interval_s of 0 is LEGAL — it is the calendar-scheduled sentinel, not a missing value" {
  mkfix
  printf 'com.claude.g | run | 0 | - | 1 | x.sh\n' >> "$R/launchd/fleet.manifest"
  run "$LINT" "$R"
  [ "$status" -eq 0 ]
}

@test "a missing activate script is RED" {
  mkfix
  printf 'com.claude.g | run | 60 | auto | 1 |\n' >> "$R/launchd/fleet.manifest"
  run "$LINT" "$R"
  [ "$status" -eq 1 ]
  printf '%s' "$output" | grep -q 'no activate script'
}

@test "an activate that is not a .sh is RED" {
  mkfix
  printf 'com.claude.g | run | 60 | auto | 1 | activate\n' >> "$R/launchd/fleet.manifest"
  run "$LINT" "$R"
  [ "$status" -eq 1 ]
  printf '%s' "$output" | grep -q "is not a .sh"
}

@test "every legal expect value is accepted" {
  mkfix
  printf 'com.claude.g | staged | 60 | auto | 1 | x.sh\n'  >> "$R/launchd/fleet.manifest"
  printf 'com.claude.h | retired | 0 | - | 1 | x.sh\n'     >> "$R/launchd/fleet.manifest"
  run "$LINT" "$R"
  [ "$status" -eq 0 ]
}

# The detector must not match its own documentation — fleet.manifest's header carries worked example
# rows in comments, and a lint that judged them would be permanently red on the real file.
@test "a commented-out row is neither counted nor judged" {
  mkfix
  printf '# com.claude.ghost | bogus | later | auto | 1 | nope\n' >> "$R/launchd/fleet.manifest"
  run "$LINT" "$R"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'across 1 manifest row(s)'
}

# A label with NO plist in this repo is legal and must stay legal: homebrew.mxcl.postgresql@14 is a
# real row whose plist is brew's. The manifest->plist direction adds no obligation, exactly as
# tests/cc-fleet.bats does not assert it either.
@test "a row whose plist this repo does not own is NOT a finding" {
  mkfix
  printf 'homebrew.mxcl.postgresql@14 | run | 0 | - | 12 | 42-postgresql14-activate.sh\n' >> "$R/launchd/fleet.manifest"
  run "$LINT" "$R"
  [ "$status" -eq 0 ]
}

# ── L4: the fail-closed arm, in every direction it can be reached ─────────────────────────────────
# rc 2 is CANNOT DETERMINE and must never collapse into a silent 0 — an indeterminate check that
# passes is indistinguishable from a working one (memory: null-result-must-not-use-the-error-channel).
@test "an absent root is rc 2, not a pass" {
  run "$LINT" "$BATS_TEST_TMPDIR/no-such-dir"
  [ "$status" -eq 2 ]
  printf '%s' "$output" | grep -q 'CANNOT DETERMINE'
}

@test "an unreadable manifest is rc 2, not a pass" {
  run "$LINT" "$R"
  [ "$status" -eq 2 ]
  printf '%s' "$output" | grep -q 'CANNOT DETERMINE'
}

@test "an absent plist directory is rc 2, not a pass" {
  mkfix
  rm -rf "$R/launchd"
  mkdir -p "$R"; : > "$R/fleet.manifest"
  CC_FLEETMAN_MANIFEST=fleet.manifest run "$LINT" "$R"
  [ "$status" -eq 2 ]
}

# SET-BUT-EMPTY must be honored verbatim and reach the loud arm, never collapse into the default —
# otherwise an operator who blanked the variable gets a full-strength run and never learns it was
# ignored (memory: harness-default-collapses-the-states-under-test).
@test "a SET-BUT-EMPTY manifest variable is rc 2, never silently the default" {
  mkfix
  CC_FLEETMAN_MANIFEST='' run "$LINT" "$R"
  [ "$status" -eq 2 ]
  printf '%s' "$output" | grep -q 'judges nothing'
}

# ── THE REAL TREE. The baseline this arm is admitted on: ZERO offenders at the commit that adds it.
# If this ever fails, the manifest rotted — repair it as its own commit rather than sitting on a
# standing refusal that accumulates silent lands behind it.
@test "the REAL repo is clean — the arm's zero-offender baseline" {
  run "$LINT" "$REPO"
  [ "$status" -eq 0 ]
}

# ...and the lint AGREES with tests/cc-fleet.bats over the same population. Two enforcers over one
# population that do not share a state model disagree in the gap (memory:
# sibling-auditors-must-share-the-state-model); this pins that they walk the identical glob.
@test "the lint's population matches the coverage loop in tests/cc-fleet.bats" {
  n_lint="$("$LINT" "$REPO" | sed -n 's/.*  \([0-9][0-9]*\) committed plist(s).*/\1/p')"
  # Counted with the GLOB ITSELF, not `ls | grep`: that is the stronger control (this test exists to
  # prove the lint walks the IDENTICAL glob tests/cc-fleet.bats walks, so the comparison must BE that
  # glob) and it is also correct for names `ls` would mangle. `[ -f ]` rejects an unmatched glob,
  # which expands to itself.
  n_glob=0
  for f in "$REPO"/launchd/com.claude.*.plist "$REPO"/launchd/com.chrisren.*.plist; do
    [ -f "$f" ] && n_glob=$((n_glob + 1))
  done
  [ -n "$n_lint" ]
  [ "$n_lint" = "$n_glob" ]
}
