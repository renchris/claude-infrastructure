#!/usr/bin/env bats
# git-identity-lint — the RATCHET that stops a fixture's git identity from escaping into the repo
# the process happens to be standing in.
#
# The failure is in-tree history, not a hypothetical. `git -C ""` is a documented NO-OP: it does not
# change directory and it does not error, so `git -C "$dir" config user.email t@t` with `$dir` empty
# writes the TEST identity into the caller's repo. This checkout is one repo with ~100 linked
# worktrees sharing a single .git/config, so one such call re-authors every session on the box —
# 9 commits on this trunk and 214 on reso-management-app are authored `t <t@t>`
# (docs/research/git-identity-leak-2026-08-05.md).
#
# Three properties are proved here, and all three matter:
#   • it DISCRIMINATES — red on both leaky shapes, green on every safe form the tree legitimately
#     uses, and green on a COMMENT that merely names the shape;
#   • the POSITIVE CONTROL is explicit — a fixture carrying the leaky shape must make the lint exit
#     NON-ZERO and NAME that file. A lint that cannot be SEEN to fire is indistinguishable from a
#     no-op, and a no-op that prints "clean" is worse than no lint at all;
#   • it is WIRED AT THE CHOKEPOINT — enforcement by its own suite alone is post-hoc detection, not
#     a gate (memory: enforcement-must-live-at-the-chokepoint), so ship-land's prelint block must
#     invoke it.
#
# The fixtures below carry the leaky shapes as LITERALS, which is safe only because the lint
# self-excludes this file by name; the suite writes its probes under $BATS_TEST_TMPDIR either way,
# so nothing here is reachable from the tree scan.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LINT="$REPO/scripts/git-identity-lint.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"   # dogfood the sibling hermeticity rule
  FIX="$BATS_TEST_TMPDIR/fix"; mkdir -p "$FIX"
}

# fixture <name> — reads a probe body on stdin into <FIX>/<name>/tests/probe.bats, and echoes the
# scan root. tests/ because that is one of the three populations the lint walks.
fixture() {
  mkdir -p "$FIX/$1/tests"
  cat > "$FIX/$1/tests/probe.bats"
  echo "$FIX/$1"
}

@test "1: the lint's own --selftest passes (36/36, both directions)" {
  run bash "$LINT" --selftest
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  # 22 → 29 (2026-08-06): the selftest grew rule-1 scope cases and the three proof-mutants; the
  # assertion was left at 22, so this test was RED on trunk. Updating it is the deliberate act the
  # message below asks for — the pin is here to force that choice, not to be silently loosened.
  # 29 -> 36: BOTH growths, and neither supersedes the other — trunk added the own-scope
  # collapse control and its bare-form control (backlog c1a29f8ee045: an own-set entry naming the
  # same basename under a DIFFERENT directory must not block, while a bare entry still matches
  # anywhere), and this change adds the five population-integrity cases (the basename-bijection
  # guard). The number below is MEASURED from a real --selftest run after the merge, never derived
  # The banner count is an AUTHORED literal, not a computed tally — which is why the two sides
  # disagreed (31 and 34) while both counted from the same base of 29. 29 + 2 + 5 = 36, and every
  # case behind both deltas is present and executing in the merged selftest.
  printf '%s' "$output" | grep -q '36/36' || { echo "selftest count changed — update this assertion deliberately: $output"; false; }
}

# ── THE POSITIVE CONTROL. If the lint were a no-op these two tests are the ones that fail. ────────

@test "2: POSITIVE CONTROL — a leaky fixture makes the lint exit non-zero AND names the file" {
  root="$(fixture leaky <<'F'
@test "seeds a repo" {
  git -C "$dir" config user.email t@t
}
F
)"
  run bash "$LINT" "$root"
  [ "$status" -eq 1 ] || { echo "the lint did not fire on the leaky shape — it is inert: $output"; false; }
  printf '%s' "$output" | grep -q 'tests/probe.bats' || { echo "the lint fired but did not NAME the file: $output"; false; }
  printf '%s' "$output" | grep -q 'tests/probe.bats:2' || { echo "the lint named the file but not the LINE: $output"; false; }
}

@test "3: POSITIVE CONTROL's pair — the same fixture in its SAFE form passes clean" {
  root="$(fixture safe <<'F'
@test "seeds a repo" {
  git -C "${dir:?repo path required}" config user.email t@t
}
F
)"
  run bash "$LINT" "$root"
  [ "$status" -eq 0 ] || { echo "a guarded -C was flagged — the lint is over-firing: $output"; false; }
  printf '%s' "$output" | grep -q 'git-identity-lint: clean' || { echo "no clean verdict: $output"; false; }
}

# ── RULE 1 — the bare -C argument ─────────────────────────────────────────────────────────────────

@test "4: RED on git -C \"\" — the literal no-op that caused the incident" {
  root="$(fixture empty <<'F'
@test "x" {
  git -C "" config user.name t
}
F
)"
  run bash "$LINT" "$root"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
}

@test "5: RED on a bare positional under -C" {
  root="$(fixture pos <<'F'
mkrepo() {
  git -C "$1" config user.email t@t
}
F
)"
  run bash "$LINT" "$root"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
}

@test "6: GREEN on an expansion with a literal suffix (the worst case is /repo, not the caller's cwd)" {
  root="$(fixture suffix <<'F'
@test "x" {
  git -C "$d/repo" config user.email t@t
}
F
)"
  run bash "$LINT" "$root"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "7: GREEN on a literal path under -C" {
  root="$(fixture lit <<'F'
@test "x" {
  git -C fixture-repo config user.name t
}
F
)"
  run bash "$LINT" "$root"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "8: GREEN on a COMMENT naming the shape — the lint keys on what a file DOES, not what it says" {
  root="$(fixture prose <<'F'
@test "x" {
  # never write git -C "$dir" config user.email t@t — see the incident doc
  true
}
F
)"
  run bash "$LINT" "$root"
  [ "$status" -eq 0 ] || { echo "the lint matched PROSE — the same vacuous shape three sibling rules shipped with: $output"; false; }
}

# ── RULE 2 — an identity write with no -C, after an unguarded cd ──────────────────────────────────

@test "9: RED on an identity write following an UNGUARDED cd" {
  root="$(fixture cdbare <<'F'
@test "x" {
  cd "$w"
  git config user.email t@e.com
}
F
)"
  run bash "$LINT" "$root"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  printf '%s' "$output" | grep -q 'UNGUARDED cd' || { echo "fired, but not for rule 2's reason: $output"; false; }
}

@test "10: RED once that cd is ||-guarded but its ARGUMENT is bare; GREEN once the argument cannot be empty" {
  # This test asserted the ||-guarded form was GREEN and was left at its creating commit while the
  # lint moved on: a92314e2 rekeyed rule 2 onto the ARGUMENT precisely because **`cd ""` RETURNS 0**
  # (rc=0, cwd unchanged). A `|| return 1` on a bare expansion therefore never fires — the guard is
  # INERT and the write still lands in the caller's repo — so scoring the PRESENCE of a guard would
  # green-light every empty-variable site. The lint's own selftest pins the same pair (fixtures
  # cd_guarded_bare / cd_guarded); the suite was stale, not the lint.
  #
  # BOTH directions in one test, deliberately: the RED half alone cannot distinguish "rule 2 keys on
  # the argument" from "rule 2 fires on any cd-preceded write", and test 11's no-cd control does not
  # separate those either — it only proves the rule needs A cd, not WHICH cd.
  inert="$(fixture cdguardbare <<'F'
@test "x" {
  cd "$w" || return 1
  git config user.email t@e.com
}
F
)"
  run bash "$LINT" "$inert"
  [ "$status" -eq 1 ] || { echo "the INERT guard passed — rule 2 is scoring the guard, not the argument: $output"; false; }

  safe="$(fixture cdguardsuffix <<'F'
@test "x" {
  cd "$w/repo" || return 1
  git config user.email t@e.com
}
F
)"
  run bash "$LINT" "$safe"
  [ "$status" -eq 0 ] || { echo "a guarded cd to a NON-EMPTIABLE path was flagged — rule 2 fires on every cd: $output"; false; }
}

@test "11: SCOPE CONTROL — an identity write with no -C and NO cd is never flagged" {
  # Without this, rule 2 could be firing on every `git config` in the tree, which would pass test 9
  # while proving nothing about scoping.
  root="$(fixture nocd <<'F'
@test "x" {
  git config user.email t@e.com
}
F
)"
  run bash "$LINT" "$root"
  [ "$status" -eq 0 ] || { echo "rule 2 is firing on writes it has no evidence about: $output"; false; }
}

# ── the ratchet, own-scope, and the non-verdict ───────────────────────────────────────────────────

@test "12: the grandfather list is consulted BOTH ways (listed ⇒ green, fixed-but-listed ⇒ red)" {
  bad="$(fixture rbad <<'F'
@test "x" {
  git -C "$dir" config user.email t@t
}
F
)"
  good="$(fixture rgood <<'F'
@test "x" {
  git -C "$dir/repo" config user.email t@t
}
F
)"
  CC_GITID_ALLOWLIST="probe.bats" run bash "$LINT" "$bad"
  [ "$status" -eq 0 ] || { echo "a grandfathered violation still blocked: $output"; false; }
  CC_GITID_ALLOWLIST="probe.bats" run bash "$LINT" "$good"
  [ "$status" -eq 1 ] || { echo "a clean-but-still-grandfathered file did not go RED — the ratchet is not shrinking: $output"; false; }
}

@test "13: own-scope blocks INSIDE the diff and advises OUTSIDE it" {
  root="$(fixture own <<'F'
@test "x" {
  git -C "$dir" config user.email t@t
}
F
)"
  CC_GITID_OWN="some-other-file.bats" run bash "$LINT" "$root"
  [ "$status" -eq 0 ] || { echo "a violation outside the own-set blocked: $output"; false; }
  printf '%s' "$output" | grep -q 'advisory' || { echo "it was stepped over but never REPORTED — advisory must not mean hidden: $output"; false; }
  CC_GITID_OWN="tests/probe.bats" run bash "$LINT" "$root"
  [ "$status" -eq 1 ] || { echo "a violation inside the own-set did not block: $output"; false; }
}

@test "14: CC_GITID_OWN set-but-EMPTY blocks on nothing (a land that touches nothing in scope)" {
  root="$(fixture ownempty <<'F'
@test "x" {
  git -C "$dir" config user.email t@t
}
F
)"
  CC_GITID_OWN="" run bash "$LINT" "$root"
  [ "$status" -eq 0 ] || { echo "an empty own-set was collapsed into strict — the fleet-wide hard stop is back: $output"; false; }
}

@test "15: an unusable scan root is a NON-VERDICT (exit 2), never a silent green" {
  run bash "$LINT" "$FIX/nothing-here"
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  # A `case`, not `grep -q … && { … }`: the latter is an and-absorbed assertion errexit cannot
  # reach, so its false result would be discarded and the test would pass regardless (the class
  # scripts/bats-assert-liveness.py exists to catch).
  case "$output" in
    *"git-identity-lint: clean"*) echo "an unusable root printed a clean verdict: $output"; false ;;
  esac
}

# ── the chokepoint ────────────────────────────────────────────────────────────────────────────────

@test "16: WIRED — ship-land's prelint block invokes the lint" {
  grep -q 'git-identity-lint.sh' "$REPO/scripts/ship-land.sh" || {
    echo "the lint is not wired into ship-land.sh — enforcement by this suite alone is detection, not a gate"
    false
  }
}

@test "17: the lint is executable (a non-executable gate is a silently skipped gate)" {
  [ -x "$LINT" ] || { echo "scripts/git-identity-lint.sh is not executable — ship-land's [[ -x ]] guard would step over it"; false; }
}

# ── the remedy the ratchet PRINTS ─────────────────────────────────────────────────────────────────

@test "18: every fix the RED message prescribes is a shape the lint ACCEPTS" {
  # A rule and the message that explains it rot INDEPENDENTLY. a92314e2 made a ||-guarded cd to a
  # bare expansion RED and left the message prescribing exactly `cd "$d" || return 1` — so a caller
  # who did precisely what the ratchet told them got the same RED back, quoting the same advice. A
  # remedy the gate rejects is not a weaker gate, it is an unexitable one. This closes the loop by
  # feeding the message's own prescriptions back through the lint.
  root="$(fixture msg <<'F'
@test "x" {
  git -C "$dir" config user.email t@t
}
F
)"
  run bash "$LINT" "$root"
  [ "$status" -eq 1 ] || { echo "$output"; false; }

  # Scoped to the `Fix:` block, NOT the whole message: the WHY block quotes `git -C ""` — the BUG —
  # by construction, and linting a deliberate statement of the bug would fail for the one reason
  # that proves nothing. `…` is the message's elision for the rest of a git call; a line carrying no
  # user.email/user.name is never scanned, so leaving it in would make that half pass vacuously.
  spans="$(printf '%s\n' "$output" | awk -F'`' '
      /^[[:space:]]*Fix:/      { infix = 1 }
      infix && /^[^[:space:]]/ { infix = 0 }
      infix { for (i = 2; i <= NF; i += 2) if ($i ~ /^(cd|git) /) print $i }' | sed 's/…/user.email t@t/')"
  [ -n "$spans" ] || { echo "no prescription found in the RED message — this test would pass vacuously: $output"; false; }

  n=0
  while IFS= read -r span; do
    [ -n "$span" ] || continue
    n=$((n + 1))
    case "$span" in
      # a bare `cd` is invisible to rule 2 until an identity write follows it — that pairing IS the
      # rule, so the prescription has to be judged in it.
      cd\ *) probe="$(printf '@test "x" {\n  %s\n  git config user.email t@t\n}\n' "$span")" ;;
      *)     probe="$(printf '@test "x" {\n  %s\n}\n' "$span")" ;;
    esac
    printf '%s' "$probe" | grep -q 'user\.email\|user\.name' || {
      echo "prescription $n is not scannable at all — the lint ignores it, so a GREEN proves nothing: $span"; false; }
    p="$(printf '%s' "$probe" | fixture "rx$n")"
    run bash "$LINT" "$p"
    [ "$status" -eq 0 ] || { echo "the ratchet prescribes a fix it REJECTS — following it returns the same RED: $span"; false; }
  done <<EOF
$spans
EOF
  [ "$n" -ge 2 ] || { echo "expected both prescriptions (the -C guard and the cd chain); found $n — the extraction, not the message, is what changed"; false; }
}

# ── POPULATION INTEGRITY: the basename bijection the lint's three keys silently assume ────────────
# The population is tests/*.bats + scripts/*.sh + bin/* — three flat globs over three directories —
# and a file's BASENAME is the key for self-exclusion (which DROPS it from the scan), the
# grandfather ratchet (which EXEMPTS it), and own-scope (which decides blocking vs advisory). None
# of that is sound unless basename determines path, which nothing stated and nothing checked.
#
# Measured on this tree 2026-08-15: 0 colliding basenames. The clean baseline is what makes the
# guard strict and allowlist-free, and it is why these cases are cheap.

# poproot <name> — a minimal scan root with all three population dirs, one inert suite so the
# root is never "nothing to judge" (which is exit 2 and would mask every verdict below).
poproot() {
  local r="$FIX/$1"
  mkdir -p "$r/tests" "$r/scripts" "$r/bin"
  printf '@test "x" {\n  : ok\n}\n' > "$r/tests/zz-fixture.bats"
  echo "$r"
}

@test "19: CONTROL — a collision-FREE population reads clean (the guard does not fire on everything)" {
  root="$(poproot popclean)"
  printf '#!/bin/bash\n: ok\n' > "$root/scripts/foo.sh"
  printf '#!/bin/bash\n: ok\n' > "$root/bin/bar.sh"
  run bash "$LINT" "$root"
  [ "$status" -eq 0 ] || { echo "a collision-free root did not read clean — the guard is over-firing: $output"; false; }
  # `! A || { …; false; }`, not `A && { …; false; }`: bash exempts `! cmd` from errexit, so the
  # `&&` spelling is ABSORBED and asserts nothing anywhere but the last line of a body. Caught here
  # by scripts/bats-assert-liveness.py on the very commit that wrote it.
  ! printf '%s' "$output" | grep -q 'COLLIDE' || { echo "a collision-free root reported COLLIDE: $output"; false; }
}

@test "20: one basename naming two files BLOCKS and names itself COLLIDE" {
  root="$(poproot popdup)"
  printf '#!/bin/bash\n: ok\n' > "$root/scripts/foo.sh"
  printf '#!/bin/bash\n: ok\n' > "$root/bin/foo.sh"
  run bash "$LINT" "$root"
  [ "$status" -eq 1 ] || { echo "a colliding basename did not block (status $status): $output"; false; }
  printf '%s' "$output" | grep -q 'COLLIDE' || { echo "it blocked without naming the class — triage cannot start from this: $output"; false; }
  printf '%s' "$output" | grep -q 'scripts/foo.sh' || { echo "the finding does not name BOTH paths, which is the only actionable part: $output"; false; }
  printf '%s' "$output" | grep -q 'bin/foo.sh' || { echo "the finding does not name BOTH paths, which is the only actionable part: $output"; false; }
}

@test "21: THE SILENT-GREEN — a leaky namesake of a SELF_EXCLUDE entry is REPORTED, not swallowed" {
  # SELF_EXCLUDE matches on basename, and a match DROPS the file from the population outright: it is
  # never scanned, never reported, and absent even from the census. Before the guard, this exact
  # tree reported "clean — 1 file(s)" with rc 0 while bin/git-identity-lint.sh carried a real
  # escaping identity write. Every SELF_EXCLUDE name maps to exactly one real file in this repo, so
  # a namesake is necessarily a collision — which is what makes the guard cover the whole reachable
  # class and not just this sample of it.
  root="$(poproot popself)"
  printf '#!/bin/bash\n: ok\n' > "$root/scripts/git-identity-lint.sh"
  printf '#!/bin/bash\ngit -C "$1" config user.email t@t\n' > "$root/bin/git-identity-lint.sh"
  run bash "$LINT" "$root"
  [ "$status" -eq 1 ] || { echo "the leaky namesake was swallowed — this is the silent green the guard exists to stop (status $status): $output"; false; }
  printf '%s' "$output" | grep -q 'COLLIDE' || { echo "blocked, but not for the collision — check what actually fired: $output"; false; }
}

@test "22: the collision is OWN-SCOPED — it gates the land that adds the namesake, not the fleet" {
  # Without this the guard is a fleet-wide hard stop: every author refused over a file they never
  # touched, which is the failure mode own-scope exists to prevent (memory:
  # enforcement-must-live-at-the-chokepoint).
  root="$(poproot popown)"
  printf '#!/bin/bash\n: ok\n' > "$root/scripts/foo.sh"
  printf '#!/bin/bash\n: ok\n' > "$root/bin/foo.sh"

  CC_GITID_OWN="bin/foo.sh" run bash "$LINT" "$root"
  [ "$status" -eq 1 ] || { echo "a collision INSIDE the diff did not block — the gate is inert for its own author: $output"; false; }

  CC_GITID_OWN="tests/zz-fixture.bats" run bash "$LINT" "$root"
  [ "$status" -eq 0 ] || { echo "a collision OUTSIDE the diff blocked — every land on this tree is now refused: $output"; false; }
  printf '%s' "$output" | grep -q 'collide?' || { echo "advisory, but silent — an unreported collision is one nobody ever fixes: $output"; false; }
}

@test "23: the real tree HAS no colliding basename (the baseline the strict rule rests on)" {
  # If this ever goes red the guard is not wrong — the tree is. Rename the file, or promote the
  # three keys from basenames to paths.
  run bash "$LINT" "$REPO"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  ! printf '%s' "$output" | grep -q 'COLLIDE\|collide?' || { echo "the population acquired a basename collision: $output"; false; }
}
