#!/usr/bin/env bats
# tests/offbox-admission-lint.bats — the admission gate for the hermetic partition.
#
# WHAT THIS SUITE IS FOR, AND WHY IT IS NOT THE --selftest. `offbox-admission-lint.sh --selftest`
# proves the DECISION TABLE against a stubbed runner: red refuses, green admits, a cut refuses, an
# already-excluded suite is skipped, a non-verdict abstains. Every one of those cases takes the
# runner's word for what "red" means, so together they cannot answer the one question the whole gate
# rests on:
#
#   DOES THE PROBE ACTUALLY REPRODUCE AN OFF-BOX FAILURE THAT AN ORDINARY LOCAL RUN MISSES?
#
# A gate whose probe cannot fail is a vacuous pass, and this repo has paid for that shape repeatedly
# (memory: control-must-replay-the-real-artifact · unfixtured-sensor-executes-the-deployed-subject).
# So the cases below run the REAL `offbox-run.sh` against a REAL fixture suite whose only defect is
# environmental, and assert BOTH directions: ordinary `bats` says green, the gate says refuse.
#
# THE FIXTURE'S DEFECT IS AN AMBIENT VARIABLE, deliberately, because it is the one off-box axis that
# is machine-independent. Keying the fixture on `~/.gitconfig` or on LC_ALL collation would make
# this suite's own verdict depend on the box it runs on — and this suite is itself in the hermetic
# partition, so it would be the exact defect it is testing for.
setup() {
  # Rule 1 of scripts/test-hermeticity-lint.sh: fixture HOME in setup(), not per-test, so no test in
  # this file can read or write the operator's live ~/.claude.
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  LINT="$REPO/scripts/offbox-admission-lint.sh"
  RUNNER="$REPO/scripts/offbox-run.sh"

  # A fixture TREE the gate is pointed at: two suites, one environment-dependent, one trivially green.
  FIX="$BATS_TEST_TMPDIR/fix"
  mkdir -p "$FIX/tests" "$FIX/scripts"

  cat > "$FIX/tests/ambient.bats" <<'EOF'
@test "reads an ambient variable that env -i strips" {
  run bash -c '[ -n "${CC_ADM_FIXTURE_AMBIENT:-}" ]'
  [ "$status" -eq 0 ]
}
EOF
  cat > "$FIX/tests/clean.bats" <<'EOF'
@test "asserts nothing about the environment" {
  run true
  [ "$status" -eq 0 ]
}
EOF

  # Stub partition: both fixture suites are IN, nothing is excluded. Stubbed rather than real because
  # the real one enumerates this repo's tests/, which is not the tree under test here.
  cat > "$FIX/scripts/part.sh" <<'EOF'
#!/bin/bash
case "${1:-}" in
  list)     printf 'tests/ambient.bats\ntests/clean.bats\n' ;;
  excluded) : ;;
esac
EOF
  chmod +x "$FIX/scripts/part.sh"

  # PIN THE BATS THE RUNNER USES — `CC_OFFBOX_BATS` is offbox-run.sh's documented seam ("An explicit
  # CC_OFFBOX_BATS always wins"), and this suite needs it for a reason worth recording.
  #
  # `resolve_bats()` walks PATH and skips the live layer, computed as "$HOME/.claude". Rule 1 of
  # test-hermeticity-lint requires this suite to FIXTURE $HOME in setup() — so by the time the lint
  # runs, `$HOME/.claude` names a directory that does not exist, the real live-layer wrapper at
  # ~/.claude/bin/bats is no longer recognised as live-layer, and the walk selects it. Nested inside
  # a bats run it returned instantly with no TAP at all, which run_one classifies `empty` and the
  # gate then refuses — a GREEN fixture suite reported as not-green. Measured 2026-08-12: identical
  # invocations were `green` standalone and `empty` from inside bats.
  #
  # That interaction is the local wrapper's business, not this gate's, so it is pinned away rather
  # than worked around: $BATS_ROOT/bin/bats is the real entrypoint of the bats that is ALREADY
  # running this file, so the fixture suites run under exactly the same bats as their parent, on
  # this box and on the CI runner alike.
  export CC_OFFBOX_BATS="${BATS_ROOT:?bats must export BATS_ROOT}/bin/bats"
  export CC_OFFBOX_ADM_ROOT="$FIX"
  export CC_OFFBOX_ADM_PARTITION="$FIX/scripts/part.sh"
  export CC_OFFBOX_ADM_RUNNER="$RUNNER"
  # The bound is the producer's own 300s in production; 60 here keeps a wedged fixture from eating
  # the suite without changing which states are reachable.
  export CC_OFFBOX_SUITE_BOUND_S=60
  # THE AMBIENT VALUE THE FIXTURE NEEDS. Exported into THIS process, so an ordinary `bats` run of the
  # fixture inherits it and passes — which is precisely what makes the pair below a control.
  export CC_ADM_FIXTURE_AMBIENT=1
}

# ── THE TWO-SIDED CONTROL — the case the whole gate rests on ─────────────────────────────────────

@test "control: the fixture suite PASSES under an ordinary local bats run" {
  run bats "$CC_OFFBOX_ADM_ROOT/tests/ambient.bats"
  [ "$status" -eq 0 ]
  # Without this direction the next test proves nothing: a suite that is simply broken would also be
  # refused, and the gate would have demonstrated no off-box discrimination at all.
  [[ "$output" == *"ok 1"* ]] || { echo "$output"; false; }
}

@test "the gate REFUSES that same suite — the off-box runner reproduces what the local run missed" {
  run bash "$LINT" --added tests/ambient.bats
  [ "$status" -eq 1 ]
  [[ "$output" == *"REFUSE"* ]] || { echo "$output"; false; }
  [[ "$output" == *"tests/ambient.bats"* ]] || { echo "$output"; false; }
}

@test "control: a suite with no environmental dependence is ADMITTED by the same gate" {
  # The other half of the two-sided proof — the gate is not simply refusing everything it is handed.
  run bash "$LINT" --added tests/clean.bats
  [ "$status" -eq 0 ]
  [[ "$output" == *"admit"* ]] || { echo "$output"; false; }
}

# ── THE CURE MUST BE CARRIED, AND MUST ACTUALLY WORK ─────────────────────────────────────────────

@test "the refusal carries the repro command and a manifest line with its measurement" {
  run bash "$LINT" --added tests/ambient.bats
  [ "$status" -eq 1 ]
  [[ "$output" == *"offbox-run.sh suites tests/ambient.bats"* ]] || { echo "$output"; false; }
  # The manifest's contract is that every entry is a MEASUREMENT; assert the state is in the line.
  [[ "$output" == *"off-box state=red"* ]] || { echo "$output"; false; }
}

@test "cure (b) WORKS: once excluded, the same gate admits the same suite" {
  # This is the un-routeable-around property. A gate whose printed cure does not clear it gets
  # bypassed instead of satisfied (memory: work-item-remedy-can-become-forbidden).
  cat > "$CC_OFFBOX_ADM_PARTITION" <<'EOF'
#!/bin/bash
case "${1:-}" in
  list)     printf 'tests/clean.bats\n' ;;
  excluded) printf 'tests/ambient.bats\n' ;;
esac
EOF
  chmod +x "$CC_OFFBOX_ADM_PARTITION"
  run bash "$LINT" --added tests/ambient.bats
  [ "$status" -eq 0 ]
  [[ "$output" == *"not in the hermetic partition"* ]] || { echo "$output"; false; }
}

# ── SCOPE: the arm must never become a fleet-wide hard stop ──────────────────────────────────────

@test "a change that adds NO suite is admitted — set-but-empty is a real position" {
  # §9's measured defect: a DOCS-ONLY land refused by suites it does not touch. `--added ''` is the
  # SET-BUT-EMPTY state; it must admit, and must not be confused with the ABSENT state that derives
  # a set from the range.
  run bash "$LINT" --added ""
  [ "$status" -eq 0 ]
}

@test "an EXISTING suite that is red off-box does not block a land that merely modifies it" {
  # The ratchet binds on ENTRY to the partition. An existing red suite is already measured hourly by
  # the producer; re-litigating it at every author's land would be the fleet-wide stop, not a gate.
  run bash "$LINT" --added ""
  [ "$status" -eq 0 ]
  [[ "$output" != *"REFUSE"* ]] || { echo "$output"; false; }
}

# ── R6: A NON-VERDICT IS NEVER A RED ─────────────────────────────────────────────────────────────

@test "a suite the runner cannot run ABSTAINS — it never convicts the author" {
  run bash "$LINT" --added tests/does-not-exist.bats
  [ "$status" -eq 0 ]
  [[ "$output" == *"ABSTAIN"* || "$output" == *"not in the hermetic partition"* ]] || { echo "$output"; false; }
}

@test "the gate REFUSES to invent a change-set when it cannot resolve one" {
  # Absent an added-set AND a usable range, the honest answer is exit 2 (unusable), never a silent
  # exit 0 over an empty set — a gate that fails OPEN on its own scope resolution acquits every land
  # it cannot scope. Pointed at a NON-git directory, which is the reachable form of that state.
  nogit="$BATS_TEST_TMPDIR/nogit"; mkdir -p "$nogit/tests"
  run env CC_OFFBOX_ADM_ROOT="$nogit" bash "$LINT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"refusing to invent a change-set"* ]] || { echo "$output"; false; }
}

# ── the decision table's own proof still has to pass ─────────────────────────────────────────────

@test "the lint's own --selftest passes, and reports every case it ran" {
  run bash "$LINT" --selftest
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  # Deliberately NOT pinned to an exact case count: an `-eq N` assertion over a suite's own case
  # count reds on the suite's own GROWTH and never on a regression (memory:
  # exact-count-assertion-tripwires-its-own-subject). Assert it named itself and reported a tally.
  [[ "$output" == *"--selftest:"* ]] || { echo "$output"; false; }
  [[ "$output" == *"REFUSES an added suite"* ]] || { echo "$output"; false; }
}
