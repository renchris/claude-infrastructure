#!/usr/bin/env bats
# self-path-lint — the RATCHET that stops a script from deriving its repo root from an UNRESOLVED $0.
#
# The failure it exists for is in-tree history, not a hypothetical. ~/.claude/{scripts,hooks,bin}/ are
# real directories of PER-FILE SYMLINKS into this checkout, so through the live layer
# `dirname "$0"/..` is ~/.claude — which has no tests/, no docs/, no .git. Three scars, one shape:
#   · ship-land.sh (f8e40b4c577d → f0a7f35) resolved GATE_SELECT to ~/.claude/scripts/gate-select.sh,
#     which had no symlink yet, took the "missing ⇒ treating as FULL (fail-closed)" branch, and ran
#     the whole ~1630-test suite on EVERY live-path land, unserialized across every landing worktree
#     — the amplifier in the 2026-07-26 machine-wide gate runaway. It looked INTERMITTENT because a
#     worktree invocation found its siblings and went scoped while the live symlink did not.
#   · deploy-parity-assert.sh (816015ecb30b) — same shape.
#   · test-hermeticity-lint.sh — its own ROOT landed in ~/.claude, so --selftest failed for a reason
#     unrelated to the ratchet it enforces.
#
# Four properties are proved here, and all four matter:
#   • it DISCRIMINATES — red on the real scar shapes, green on every legitimate form the tree uses
#     (a resolved $0 doing the SAME '..' traversal, self re-exec, guarded fallback ladders, prose);
#   • the GUARDED/UNGUARDED distinction holds in BOTH directions — the one judgement the rule turns
#     on, and the one a "a $HOME/.claude path appears nearby" shortcut would silently get wrong;
#   • it is GREEN on the tree as it stands — a lint that ships standing-red is rot, and the nightly
#     runs every scripts/*lint*.sh, so a false red here poisons the whole nightly signal;
#   • it is WIRED AT THE CHOKEPOINT — enforcement by its own suite alone is detection, not a gate
#     (memory: enforcement-must-live-at-the-chokepoint), so run_gate must invoke it.
#
# Assertions use the explicit `|| { …; false; }` form throughout: a non-final `[[ ]]` is
# errexit-EXEMPT under bats and would be a DEAD assertion that can never fail
# (memory: bats-dead-assertions-errexit-exemptions).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LINT="$REPO/scripts/self-path-lint.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"   # dogfood the sibling hermeticity rule
  FIX="$BATS_TEST_TMPDIR/fix"; mkdir -p "$FIX"
}

# mk <case> <body> — a scan root $FIX/<case> holding one shell file under scripts/
mk() {
  mkdir -p "$FIX/$1/scripts"
  { printf '#!/bin/bash\n'; printf '%s\n' "$2"; } > "$FIX/$1/scripts/probe.sh"
}

@test "1: the lint's own --selftest passes, and reports every case it ran" {
  run bash "$LINT" --selftest
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  # The count is COMPUTED by the selftest, so this asserts the FORM (n/n, all passed) and a floor,
  # rather than a literal that would drift every time a case is added.
  n="$(printf '%s' "$output" | sed -n 's/.*--selftest: \([0-9]*\)\/\([0-9]*\) .*/\1 \2/p')"
  [ -n "$n" ] || { echo "no n/n count in selftest output: $output"; false; }
  ran="${n% *}"; total="${n#* }"
  [ "$ran" = "$total" ] || { echo "selftest reported $ran/$total — not all cases passed"; false; }
  [ "$ran" -ge 25 ] || { echo "selftest shrank to $ran cases — coverage was removed, not added"; false; }
}

@test "2: RED on a repo root derived from an unresolved \$0 (the f8e40b4c577d scar shape)" {
  mk scar 'ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GATE_SELECT="$ROOT/scripts/gate-select.sh"'
  run bash "$LINT" "$FIX/scar"
  [ "$status" -eq 1 ] || { echo "expected rc 1, got $status: $output"; false; }
  printf '%s' "$output" | grep -q 'SELF-PATH' || { echo "no SELF-PATH verdict: $output"; false; }
}

@test "3: RED on a bare \`cd \$(dirname \$0)/..\` (the 816015ecb30b scar shape)" {
  mk cdparent 'cd "$(dirname "$0")/.." || exit 2'
  run bash "$LINT" "$FIX/cdparent"
  [ "$status" -eq 1 ] || { echo "expected rc 1, got $status: $output"; false; }
}

@test "4: GREEN once \$0 is resolved — the SAME '..' traversal, so the rule keys on resolvedness" {
  mk fixed 'SELF="$0"
while [ -L "$SELF" ]; do SELF="$(readlink "$SELF")"; done
ROOT="$(cd "$(dirname "$SELF")/.." && pwd)"'
  run bash "$LINT" "$FIX/fixed"
  [ "$status" -eq 0 ] || { echo "a resolved \$0 was flagged: $output"; false; }
}

@test "5: GREEN on self re-exec and on an own-directory sibling (no '..', so out of scope)" {
  mk selfexec 'SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
HF="$(cd "$(dirname "$0")" && pwd)/handoff-fire.sh"'
  run bash "$LINT" "$FIX/selfexec"
  [ "$status" -eq 0 ] || { echo "a no-'..' self reference was flagged: $output"; false; }
}

@test "6: GREEN on a guarded candidate — the if/elif/else resolver the tree actually uses" {
  mk guarded 'resolve_announce() {
  local sd; sd="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/.."
  if   [ -x "$sd/bin/cc-announce" ]; then echo "$sd/bin/cc-announce"
  else echo "$HOME/.claude/bin/cc-announce"; fi
}'
  run bash "$LINT" "$FIX/guarded"
  [ "$status" -eq 0 ] || { echo "a guarded fallback resolver was flagged: $output"; false; }
}

@test "7: RED on an UNGUARDED root with unrelated \$HOME/.claude lines beside it" {
  # The other half of test 6, and the case the whole rule turns on. nightly-regression.sh:55 derives
  # REPO with no existence test and merely happens to assign PAGEDIR/LOG under $HOME/.claude on the
  # next two lines. If tolerance keyed on "an anchor appears nearby" this would pass, and the rule
  # would be worthless — a path nobody tests is a path nobody can fall back from.
  mk unguarded 'REPO="${CC_NIGHTLY_REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
PAGEDIR="${CC_NIGHTLY_PAGEDIR:-$HOME/.claude/autonomy/pages}"
LOG="${CC_NIGHTLY_LOG:-$HOME/.claude/autonomy/regression.log}"
BATS_DIR="${CC_NIGHTLY_BATS_DIR:-$REPO/tests}"'
  run bash "$LINT" "$FIX/unguarded"
  [ "$status" -eq 1 ] || { echo "an unconditional self-derived root went green: $output"; false; }
}

@test "8: PROSE about the defect is not a finding" {
  # Six files in this repo discuss `dirname \"\$0\"` in comments. A detector that matches text ABOUT
  # the defect reports the fix as the bug (memory: detector-matching-its-own-skill-description).
  mk prose '# a bare `cd "$(dirname "$0")/.."` here would be the 816015ecb30b scar
ROOT="$(cd "$(dirname "$SELF")/.." && pwd)"'
  run bash "$LINT" "$FIX/prose"
  [ "$status" -eq 0 ] || { echo "prose was reported as a violation: $output"; false; }
}

@test "9: the self_path_ok hatch suppresses inline and on the line above — a bare comment does not" {
  mk hatch1 'EXAMPLE="cd dirname-zero-dotdot"  # self_path_ok
ROOT="$(cd "$(dirname "$0")/.." && pwd)"  # self_path_ok — reviewed'
  run bash "$LINT" "$FIX/hatch1"
  [ "$status" -eq 0 ] || { echo "an inline hatch did not suppress: $output"; false; }

  mk hatch2 '# self_path_ok — reviewed: guarded by the branch above
ROOT="$(cd "$(dirname "$0")/.." && pwd)"'
  run bash "$LINT" "$FIX/hatch2"
  [ "$status" -eq 0 ] || { echo "a preceding-line hatch did not suppress: $output"; false; }

  mk hatch3 '# an ordinary explanatory comment
ROOT="$(cd "$(dirname "$0")/.." && pwd)"'
  run bash "$LINT" "$FIX/hatch3"
  [ "$status" -eq 1 ] || { echo "any comment now works as an exemption: $output"; false; }
}

@test "10: the ratchet SHRINKS — grandfathered is green, fixed-but-still-listed is RED" {
  mk shrink 'cd "$(dirname "$0")/.." || exit 2'
  CC_SELFPATH_ALLOWLIST="scripts/probe.sh" run bash "$LINT" "$FIX/shrink"
  [ "$status" -eq 0 ] || { echo "a grandfathered violation blocked: $output"; false; }

  mk shrink2 'ROOT="$(cd "$(dirname "$SELF")/.." && pwd)"'
  CC_SELFPATH_ALLOWLIST="scripts/probe.sh" run bash "$LINT" "$FIX/shrink2"
  [ "$status" -eq 1 ] || { echo "a fixed file kept its allowlist line and still passed — the ratchet is a permanent exemption list: $output"; false; }
  printf '%s' "$output" | grep -q 'RATCHET' || { echo "no RATCHET verdict: $output"; false; }
}

@test "11: own-scope blocks INSIDE the diff and only advises OUTSIDE it" {
  mk own 'cd "$(dirname "$0")/.." || exit 2'
  CC_SELFPATH_OWN="scripts/probe.sh" CC_SELFPATH_ALLOWLIST="" run bash "$LINT" "$FIX/own"
  [ "$status" -eq 1 ] || { echo "a violation inside the own-set did not block: $output"; false; }

  CC_SELFPATH_OWN="scripts/other.sh" CC_SELFPATH_ALLOWLIST="" run bash "$LINT" "$FIX/own"
  [ "$status" -eq 0 ] || { echo "a violation outside the own-set blocked — one author's omission is every author's outage: $output"; false; }
  printf '%s' "$output" | grep -q 'selfpath?' || { echo "an out-of-scope violation was HIDDEN rather than labelled: $output"; false; }
}

@test "12: own-set ABSENT is strict, own-set SET-BUT-EMPTY blocks nothing (three states, not two)" {
  mk arity 'cd "$(dirname "$0")/.." || exit 2'
  # The docs-only land: an empty own-set legitimately means "I change no file in these layers".
  # `${VAR:-}` would collapse this into the unset case and silently reinstate the hard stop.
  CC_SELFPATH_OWN="" CC_SELFPATH_ALLOWLIST="" run bash "$LINT" "$FIX/arity"
  [ "$status" -eq 0 ] || { echo "an EMPTY own-set blocked: $output"; false; }

  CC_SELFPATH_ALLOWLIST="" run bash "$LINT" "$FIX/arity"
  [ "$status" -eq 1 ] || { echo "an ABSENT own-set did not block — strict default lost: $output"; false; }
}

@test "13: an unrunnable detector is a NON-VERDICT (exit 2), never a named violation" {
  # A check whose own tool cannot run must not answer. The sibling hermeticity ratchet fabricated
  # leaks NAMING GOOD FILES under fork pressure, which reads as an attributable RED and sends people
  # to fix code that was never broken (memory: named-failure-vs-no-verdict).
  mk killed 'cd "$(dirname "$0")/.." || exit 2'
  stub="$BATS_TEST_TMPDIR/stub"; mkdir -p "$stub"
  printf '#!/bin/bash\nexit 2\n' > "$stub/awk"; chmod +x "$stub/awk"
  PATH="$stub:$PATH" CC_SELFPATH_ALLOWLIST="" run bash "$LINT" "$FIX/killed"
  [ "$status" -eq 2 ] || { echo "expected the non-verdict rc 2, got $status: $output"; false; }
  # GUARD, not an assertion: finding NO 'SELF-PATH' is the PASS case. As `A && {…; false; } || false`
  # this returned 1 on BOTH branches (grep miss short-circuits straight into `|| false`), so it failed
  # exactly when the detector behaved correctly. `if` form, so a dead-assertion sweep cannot re-break it.
  if printf '%s' "$output" | grep -q 'SELF-PATH'; then
    echo "an unrunnable detector fabricated a finding: $output"; false
  fi
  printf '%s' "$output" | grep -q 'UNUSABLE' || { echo "the non-verdict was not announced: $output"; false; }
}

@test "14: LOUD (exit 2) on a missing scan root and on a root with no deployed layers" {
  run bash "$LINT" "$FIX/does-not-exist"
  [ "$status" -eq 2 ] || { echo "a missing root did not exit 2: $output"; false; }

  mkdir -p "$FIX/nolayers/docs"
  run bash "$LINT" "$FIX/nolayers"
  [ "$status" -eq 2 ] || { echo "a root with no deployed layers did not exit 2: $output"; false; }
}

@test "15: a tests/ subtree is out of jurisdiction — never symlink-deployed" {
  mkdir -p "$FIX/subtree/hooks/tests"
  printf '#!/bin/bash\nROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"\n' > "$FIX/subtree/hooks/tests/t.sh"
  printf '#!/bin/bash\ntrue\n' > "$FIX/subtree/hooks/ok.sh"
  run bash "$LINT" "$FIX/subtree"
  [ "$status" -eq 0 ] || { echo "a tests/ subtree file was scanned: $output"; false; }
}

@test "16: GREEN on the real tree — a lint that ships standing-red is rot" {
  run bash "$LINT"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s' "$output" | grep -q 'clean' || { echo "no clean verdict on the real tree: $output"; false; }
}

@test "17: WIRED AT THE CHOKEPOINT — run_gate invokes the lint and its --selftest" {
  # Enforcement by this suite alone would be post-hoc DETECTION: gate-select will not pick this suite
  # up when the edited file is a PRODUCER rather than the lint itself
  # (memory: enforcement-must-live-at-the-chokepoint).
  grep -q 'self-path-lint.sh' "$REPO/scripts/ship-land.sh" \
    || { echo "ship-land.sh does not reference the lint — it is detection, not a gate"; false; }
  grep -q 'SELFPATH_LINT.*--selftest' "$REPO/scripts/ship-land.sh" \
    || { echo "the gate runs the lint without its --selftest — an unverified detector's clean verdict means nothing"; false; }
  grep -q 'CC_SELFPATH_OWN=' "$REPO/scripts/ship-land.sh" \
    || { echo "the gate does not pass an own-set — a whole-tree block is a fleet-wide hard stop"; false; }
}

@test "18: the lint resolves its OWN \$0 — it must not carry the defect it enforces" {
  # The reason this is not merely cute: invoked as ~/.claude/scripts/self-path-lint.sh, an unresolved
  # ROOT would land in ~/.claude, find none of the layers, and exit 2 forever.
  link="$BATS_TEST_TMPDIR/linked-lint.sh"
  ln -s "$LINT" "$link"
  run bash "$link" --selftest
  [ "$status" -eq 0 ] || { echo "the lint failed when invoked through a symlink: $output"; false; }
}
