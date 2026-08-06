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

@test "1: the lint's own --selftest passes (29/29, both directions)" {
  run bash "$LINT" --selftest
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  # 22 → 29 (2026-08-06): the selftest grew rule-1 scope cases and the three proof-mutants; the
  # assertion was left at 22, so this test was RED on trunk. Updating it is the deliberate act the
  # message below asks for — the pin is here to force that choice, not to be silently loosened.
  printf '%s' "$output" | grep -q '29/29' || { echo "selftest count changed — update this assertion deliberately: $output"; false; }
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
