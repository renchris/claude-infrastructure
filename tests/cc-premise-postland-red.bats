#!/usr/bin/env bats
# cc-premise, the `postland-verify` RED arm: a DERIVED falsifier keyed on trunk having gone green
# PAST the commit the RED was filed against.
#
# WHY THIS ARM EXISTS. A `post-land RED: <suite> @ <sha>` item's entire claim is "this suite fails at
# THAT commit". That is a snapshot of a commit trunk has since moved past, and nothing re-read it.
# Measured on `a3f4cc262e1c` (`tests/cc-relogin-status.bats @ 873e646b5d5a`): the remedy landed as
# `87f0f51c03b0` SIX MINUTES FORTY SECONDS after the RED was recorded — and a worker was still
# dispatched onto the item THREE DAYS later. The sha is kept in the title on purpose (cc-premise
# `_norm_title`, §S3 finding 3) so each RED stays distinct work; nothing ever asked it whether it was
# still the tip's problem.
#
# THE PREDICATE HAS TWO CLAUSES AND BOTH ARE TESTED AS CONTROLS:
#   the RED commit is an ANCESTOR of last-green   ⇒ a tree CONTAINING it ran the whole corpus green
#   AND the suite was IN the corpus at last-green ⇒ that green's SPAN actually covers this suite
# The second is not belt-and-braces. The tree corpus is `tests/*.bats` MINUS
# scripts/host-suites.manifest, so a green is silent about a host suite BY CONSTRUCTION, and silent
# about a suite that did not exist yet. Retracting on ancestry alone would assert a verdict over a
# run that never executed the subject (memory: assertion-span-must-equal-its-subject) — so there is a
# control for each half, and each must NOT refuse.
#
# THE FIXTURE REPO IS A REAL GIT REPO, not a stub. This arm's whole content is git ancestry plus a
# blob read at a historical ref; a stubbed `git` would let the ancestry direction silently invert
# while every assertion stayed green (memory: control-must-replay-the-real-artifact).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  PREMISE="$REPO/bin/cc-premise"
  BACKLOG_BIN="$REPO/bin/cc-backlog"
  TMP="$(mktemp -d)"
  # HERMETIC $HOME: POSTLAND_DIR's default is ~/.claude/autonomy/postland, so an unfixtured $HOME
  # would let the OPERATOR's live last-green decide these assertions — the suite would then pass or
  # fail on whatever trunk did last night. Every store this arm reads is redirected below.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/autonomy"
  export CC_BACKLOG_FILE="$TMP/backlog.jsonl"
  export CC_BACKLOG_IDL="$TMP/idl.jsonl"
  export CC_BACKLOG_KICK=off

  # ── the fixture repo ───────────────────────────────────────────────────────────────────────────
  # Three commits on one line: BASE ← RED ← GREEN. `last-green` points at GREEN, so RED is an
  # ancestor of it and the arm should refuse; a fourth commit AFTER green gives the primary control.
  GITR="$TMP/repo"; mkdir -p "$GITR/tests"
  git -C "$GITR" init -q -b main
  git -C "$GITR" config user.email t@t; git -C "$GITR" config user.name t
  git -C "$GITR" config commit.gpgsign false
  printf 'base\n' > "$GITR/tests/suite-a.bats"
  printf 'base\n' > "$GITR/tests/host-suite.bats"
  git -C "$GITR" add -A; git -C "$GITR" commit -qm base
  BASE="$(git -C "$GITR" rev-parse HEAD)"
  printf 'red\n' >> "$GITR/tests/suite-a.bats"
  git -C "$GITR" add -A; git -C "$GITR" commit -qm red
  RED="$(git -C "$GITR" rev-parse HEAD)"
  printf 'fixed\n' >> "$GITR/tests/suite-a.bats"
  git -C "$GITR" add -A; git -C "$GITR" commit -qm green
  GREEN="$(git -C "$GITR" rev-parse HEAD)"
  printf 'later\n' >> "$GITR/tests/suite-a.bats"
  git -C "$GITR" add -A; git -C "$GITR" commit -qm later
  LATER="$(git -C "$GITR" rev-parse HEAD)"
  # `_git_usable` resolves origin/main as its positive control — without this ref every arm here
  # fails open and the whole file would pass vacuously.
  git -C "$GITR" update-ref refs/remotes/origin/main "$LATER"
  export CC_PREMISE_REPO="$GITR"

  # ── the postland ledger ────────────────────────────────────────────────────────────────────────
  PL="$TMP/postland"; mkdir -p "$PL"
  export CC_PREMISE_POSTLAND_DIR="$PL"
  printf '%s\n' "$GREEN" > "$PL/last-green"
}

teardown() { rm -rf "$TMP"; }

# add <title> <source> [project] [falsifier] — through the SHIPPING verb, so the record shape
# (id = hash of project+title+source) is the real one rather than a hand-written approximation.
add() {
  "$BACKLOG_BIN" add --project "${3:-claude-infrastructure}" --title "$1" --source "$2" \
    ${4:+--falsifier "$4"} 2>/dev/null
}

verdict() { printf '%s' "$1" | sed -n 's/^verdict=//p'; }
# `! cmd` is exempt from errexit in bash, so a negative written that way only fails as the LAST line
# of a body. This returns non-zero directly and so fails anywhere.
refute_match() { [ "$(printf '%s' "$1" | grep -c "$2")" -eq 0 ]; }

# manifest <ref-commit-msg> <line…> — rewrites scripts/host-suites.manifest at the GREEN commit by
# committing it and re-pointing last-green, so the manifest under test is the one AT the green.
green_manifest() {
  mkdir -p "$GITR/scripts"
  printf '%s\n' "$@" > "$GITR/scripts/host-suites.manifest"
  git -C "$GITR" add -A; git -C "$GITR" commit -qm manifest
  GREEN="$(git -C "$GITR" rev-parse HEAD)"
  printf '%s\n' "$GREEN" > "$PL/last-green"
}

# ── the refusal ──────────────────────────────────────────────────────────────────────────────────

# MUTATION CONTROL for this test: invert the ancestry direction in run_derived_postland_falsifier —
# `merge-base --is-ancestor "$lg" "$redsha"` instead of `redsha lg` — verified RED (status 0,
# verdict=clear). Deleting the `run_derived_postland_falsifier(item_id, ent)` call in `assess`
# reddens it the same way.
@test "post-land RED whose commit is ANCESTOR of last-green -> REFUSES with verdict=falsified" {
  id="$(add "post-land RED: tests/suite-a.bats @ $RED" postland-verify)"
  run "$PREMISE" check "$id"
  [ "$status" -eq 3 ]
  [ "$(verdict "$output")" = falsified ]
  # the contract must say the probe was DERIVED and name BOTH shas plus the suite, or a reader
  # cannot tell a ledger read from a re-run of the suite — the whole difference between this arm
  # and a stored falsifier.
  printf '%s' "$output" | grep -q "DERIVED FALSIFIER"
  printf '%s' "$output" | grep -q "tests/suite-a.bats"
  printf '%s' "$output" | grep -q "${RED:0:12}"
  printf '%s' "$output" | grep -q "${GREEN:0:12}"
  # the retraction wording must say PREMISE, never "verified" — no suite was run by this arm.
  printf '%s' "$output" | grep -q "premise-retracted"
  printf '%s' "$output" | grep -q "no code verified by this retraction"
}

# THE PRIMARY CONTROL. Without it an arm that refused EVERY post-land RED item would pass the test
# above — and a blanket refusal retires exactly the live REDs the post-land net exists to surface.
@test "post-land RED filed AFTER last-green -> does NOT refuse (trunk has not gone green past it)" {
  id="$(add "post-land RED: tests/suite-a.bats @ $LATER" postland-verify)"
  run "$PREMISE" check "$id"
  [ "$status" -eq 0 ]
  [ "$(verdict "$output")" = clear ]
  refute_match "$output" "verdict=falsified"
}

# ── the SPAN controls: a green is only evidence about suites it actually RAN ─────────────────────

# THE LOAD-BEARING CONTROL OF THIS FILE. A host suite is excluded from the tree corpus by set
# difference, so a "full corpus green" is silent about it BY CONSTRUCTION. Retracting here would
# close a live RED citing a run that never executed the file.
@test "SPAN: a suite listed in host-suites.manifest at last-green -> does NOT refuse" {
  green_manifest '# host suites' 'tests/host-suite.bats'
  id="$(add "post-land RED: tests/host-suite.bats @ $RED" postland-verify)"
  run "$PREMISE" check "$id"
  [ "$status" -eq 0 ]
  refute_match "$output" "verdict=falsified"
  # …and the NON-excluded sibling in the very same tree still refuses, so this is a property of the
  # manifest entry rather than of the manifest merely existing.
  id2="$(add "post-land RED: tests/suite-a.bats @ $RED" postland-verify)"
  run "$PREMISE" check "$id2"
  [ "$status" -eq 3 ]
}

# A comment on the manifest line must not smuggle a suite past the exclusion — the manifest's frozen
# contract says `#` comments are ignored, so the parse has to strip them, not match whole lines.
@test "SPAN: a manifest entry with a trailing comment still excludes" {
  green_manifest 'tests/host-suite.bats   # lives against the deployed layer'
  id="$(add "post-land RED: tests/host-suite.bats @ $RED" postland-verify)"
  run "$PREMISE" check "$id"
  [ "$status" -eq 0 ]
  refute_match "$output" "verdict=falsified"
}

# An ABSENT manifest is the EMPTY set by the manifest's own frozen contract ("a missing manifest
# means EMPTY: the verifier then runs everything"), which is a real ANSWER and not a sensor failure.
# Collapsing it into "could not ask" would retire this arm on every tree predating the manifest.
@test "SPAN: an ABSENT manifest means the corpus was everything -> still refuses" {
  [ ! -e "$GITR/scripts/host-suites.manifest" ]
  id="$(add "post-land RED: tests/suite-a.bats @ $RED" postland-verify)"
  run "$PREMISE" check "$id"
  [ "$status" -eq 3 ]
  [ "$(verdict "$output")" = falsified ]
}

@test "SPAN: a suite that does not exist at last-green -> does NOT refuse" {
  # The green cannot have run a file that was not in its tree, whatever the ancestry says.
  id="$(add "post-land RED: tests/never-existed.bats @ $RED" postland-verify)"
  run "$PREMISE" check "$id"
  [ "$status" -eq 0 ]
  refute_match "$output" "verdict=falsified"
}

# ── scoping: whose premise this arm is entitled to judge ─────────────────────────────────────────

# THE SOURCE SCOPING TEST, the sibling of cc-premise-plan-open.bats's `791345455b58` case. The words
# "post-land RED" in a HUMAN's title describe a symptom; they are not a machine claim keyed to a
# commit, and a corpus green says nothing about them.
@test "source is NOT postland-verify -> an identical title proves nothing" {
  id="$(add "post-land RED: tests/suite-a.bats @ $RED" human-filed)"
  run "$PREMISE" check "$id"
  [ "$status" -eq 0 ]
  [ "$(verdict "$output")" = clear ]
  refute_match "$output" "verdict=falsified"
}

# postland-verify emits three title shapes. Only RED is refuted by "the corpus went green" — a HUNG
# is a property of the tree (an un-stubbed seam) and an AUTO-REVERT row is a record of an act.
@test "sibling SHAPES from the same producer are not parsed as RED" {
  a="$(add "post-land HUNG: tests/suite-a.bats wedged at 3 @ $RED — un-stubbed external seam, timeout-wrap it (NOT a peer pkill)" postland-verify)"
  b="$(add "post-land AUTO-REVERT FAILED(step=revert rc=90): tests/suite-a.bats @ $RED (revert none on postland-revert-x)" postland-verify)"
  c="$(add "post-land AUTO-REVERT INERT (retry-budget-spent): culprit $RED — the veto cannot actuate" postland-verify)"
  for id in "$a" "$b" "$c"; do
    run "$PREMISE" check "$id"
    [ "$status" -eq 0 ]
    refute_match "$output" "verdict=falsified"
  done
}

# THE ANCHOR ISOLATION TEST, and it exists because the three cases above did NOT prove what they
# claimed. Every shape the producer emits today happens to carry a trailing suffix — `— un-stubbed
# external seam…`, `(revert none on …)` — so they are rejected by the `@ <sha>$` requirement no
# matter what the prefix says. Loosening the anchor to `^post-land \w+.*?:` left all three GREEN
# (measured), i.e. the `RED` literal this arm documents as its discriminator was carrying no load.
#
# So this pins it directly: a HUNG-shaped title that DOES end in ` @ <sha>`. If the producer ever
# drops that suffix, the arm must still refuse to parse it — because a green does NOT dispose of a
# HUNG's remedy. Its claim is an un-stubbed external seam that needs timeout-wrapping; a corpus that
# happened not to wedge this time leaves that obligation exactly where it was (memory:
# work-item-remedy-can-become-forbidden — a symptom and its remedy rot independently).
@test "the RED literal is the discriminator, not the trailing sha: a HUNG ending in a sha is inert" {
  # The two titles differ in ONE WORD, so nothing but the anchor can explain the two verdicts.
  id="$(add "post-land HUNG: tests/suite-a.bats @ $RED" postland-verify)"
  run "$PREMISE" check "$id"
  [ "$status" -eq 0 ]
  refute_match "$output" "verdict=falsified"
  id2="$(add "post-land RED: tests/suite-a.bats @ $RED" postland-verify)"
  run "$PREMISE" check "$id2"
  [ "$status" -eq 3 ]
}

# postland-verify has genuinely filed `FAILING=(tests/)` when its TAP grammar could not attribute a
# failure. A directory has no single corpus membership, so it must read as "cannot tell".
@test "a DIRECTORY instead of a suite -> does NOT refuse" {
  id="$(add "post-land RED: tests/ @ $RED" postland-verify)"
  run "$PREMISE" check "$id"
  [ "$status" -eq 0 ]
  refute_match "$output" "verdict=falsified"
}

@test "another PROJECT's item -> does NOT refuse (its shas are not this checkout's)" {
  id="$(add "post-land RED: tests/suite-a.bats @ $RED" postland-verify reso-management-app)"
  run "$PREMISE" check "$id"
  [ "$status" -eq 0 ]
  refute_match "$output" "verdict=falsified"
}

# THE PARSE PROPERTY, and it is the one a naive regex gets wrong. A real title in the store is
# `…bats::one live kitty socket resolves to unix:<path> @ f60b7ca220ee` — the bats test NAME carries
# `@`, `:` and spaces, so the separator that matters is the LAST one. A `[^@]*` or non-anchored
# reading splits inside the test description and takes a sha out of a sentence.
@test "a ::test-name carrying '@' and ':' still resolves the LAST sha and the right file" {
  id="$(add "post-land RED: tests/suite-a.bats::resolves to unix:<path> @ sock, quickly @ $RED" postland-verify)"
  run "$PREMISE" check "$id"
  [ "$status" -eq 3 ]
  printf '%s' "$output" | grep -q "suite:      tests/suite-a.bats"
  printf '%s' "$output" | grep -q "red at:     ${RED:0:12}"
}

# ── fail-open, exhaustively ──────────────────────────────────────────────────────────────────────

@test "FAIL-OPEN: no last-green, a junk last-green, and an unresolvable sha cannot refuse" {
  id="$(add "post-land RED: tests/suite-a.bats @ $RED" postland-verify)"
  # sanity: it DOES refuse with the ledger intact, so each branch below separates "could not ask"
  # from "asked and got no" rather than observing an already-dead arm.
  run "$PREMISE" check "$id"; [ "$status" -eq 3 ]

  rm -f "$PL/last-green"
  run "$PREMISE" check "$id"
  [ "$status" -eq 0 ]; refute_match "$output" "verdict=falsified"

  printf 'not-a-sha\n' > "$PL/last-green"
  run "$PREMISE" check "$id"
  [ "$status" -eq 0 ]; refute_match "$output" "verdict=falsified"

  # a well-formed sha that is not an object in this repo — git ANSWERS, and the answer is no
  printf '%s\n' "$GREEN" > "$PL/last-green"
  id2="$(add "post-land RED: tests/suite-a.bats @ deadbeefdead" postland-verify)"
  run "$PREMISE" check "$id2"
  [ "$status" -eq 0 ]; refute_match "$output" "verdict=falsified"
}

@test "FAIL-OPEN positive control: an unreadable repo cannot refuse" {
  id="$(add "post-land RED: tests/suite-a.bats @ $RED" postland-verify)"
  run "$PREMISE" check "$id"; [ "$status" -eq 3 ]
  # explicitly EMPTY disables the git arms — how a suite pins them inert, matching the
  # CC_PREMISE_REPO discipline the sibling suites use.
  CC_PREMISE_REPO="" run "$PREMISE" check "$id"
  [ "$status" -eq 0 ]; refute_match "$output" "verdict=falsified"
  # …and a path that is not a git repo at all takes the same branch rather than convicting.
  CC_PREMISE_REPO="$TMP/not-a-repo" run "$PREMISE" check "$id"
  [ "$status" -eq 0 ]; refute_match "$output" "verdict=falsified"
}

# ── precedence and the kill switches ─────────────────────────────────────────────────────────────

# A STORED PROBE IS THE ITEM OWNER'S OWN QUESTION ABOUT THEIR OWN CONDITION; last-green is a coarser
# proxy. A proxy must never outrank the measurement it stands in for.
@test "a STORED falsifier wins over the derived one on a post-land RED item" {
  id="$(add "post-land RED: tests/suite-a.bats @ $RED" postland-verify claude-infrastructure 'false')"
  run "$PREMISE" check "$id"
  [ "$status" -eq 0 ]
  [ "$(verdict "$output")" = clear ]
  printf '%s' "$output" | grep -q "STILL LIVE"
  refute_match "$output" "DERIVED FALSIFIER"
}

@test "both kill switches disable the arm" {
  id="$(add "post-land RED: tests/suite-a.bats @ $RED" postland-verify)"
  # the SHARED switch — a derived probe is still a probe, so turning falsification off must not
  # leave one running.
  CC_PREMISE_FALSIFIER=off run "$PREMISE" check "$id"
  [ "$status" -eq 0 ]; refute_match "$output" "verdict=falsified"
  # …and the arm's OWN switch, so this one can be parked without disabling the plan arm too.
  CC_PREMISE_POSTLAND_FALSIFIER=off run "$PREMISE" check "$id"
  [ "$status" -eq 0 ]; refute_match "$output" "verdict=falsified"
}

# The contract verb is what cc-dispatch injects into a worker's brief; a refusal that appears only
# in `check` would never reach the enforcing store a worker actually reads.
@test "the refusal rides the CONTRACT, not just the check exit code" {
  id="$(add "post-land RED: tests/suite-a.bats @ $RED" postland-verify)"
  run "$PREMISE" contract "$id"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q "DERIVED FALSIFIER"
  printf '%s' "$output" | grep -q "tests/suite-a.bats"
}
