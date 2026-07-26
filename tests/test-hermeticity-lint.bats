#!/usr/bin/env bats
# test-hermeticity-lint — the RATCHET that stops NEW bats suites from running against the operator's
# live ~/. Two properties matter and both are proved here: it discriminates (RED on a new leak, RED on
# an entry that stayed grandfathered after being fixed), and it is GREEN on the tree as it stands —
# a lint that ships standing-RED is the rot this repo is killing, and the nightly auto-runs every
# scripts/*lint*.sh, so a false RED here poisons the whole nightly signal.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LINT="$REPO/scripts/test-hermeticity-lint.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"    # dogfood: this suite obeys its own rule
  FIX="$BATS_TEST_TMPDIR/fix"; mkdir -p "$FIX"
}

# write a fixture suite whose setup() body is $2, into a fresh dir $1
mk_suite() {
  mkdir -p "$FIX/$1"
  { echo '#!/usr/bin/env bats'; echo 'setup() {'; echo "  $2"; echo '}'; echo '@test "x" { true; }'; } \
    > "$FIX/$1/zz-fixture.bats"
}

@test "the real tree is CLEAN (exit 0) — the embedded allowlist matches HEAD, nightly stays green" {
  run bash "$LINT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'test-hermeticity-lint: clean'
}

@test "--selftest is GREEN and every discriminating case is exercised" {
  run bash "$LINT" --selftest
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE -e '--selftest: [0-9]+/[0-9]+'
}

@test "--selftest is GREEN through a SYMLINK to the script (the DEPLOYED ~/.claude path)" {
  # ~/.claude/scripts/test-hermeticity-lint.sh is a per-file symlink into this checkout, and that is
  # the path an agent naturally reaches for. Before $0 was resolved through symlinks, ROOT became
  # ~/.claude — which has no tests/ — so the real-tree case failed and reported it as "the embedded
  # allowlist is stale": a false RED on a self-evidencing proof, misnaming its own cause. Found
  # 2026-07-26 by running the deployed copy immediately after landing it.
  ln -s "$LINT" "$FIX/linked-lint.sh"
  run bash "$FIX/linked-lint.sh" --selftest
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE -e '--selftest: [0-9]+/[0-9]+'
}

@test "a bad ROOT is reported as a NON-VERDICT, never as a stale allowlist" {
  # The discrimination that makes the failure above self-explaining rather than misleading: exit 2
  # (could not scan) and exit 1 (allowlist really is stale) are different claims. CC_HERM_SELFTEST_ROOT
  # is not a seam the script has — so drive it the honest way, through a symlink whose parent has no
  # tests/ dir, which is exactly the real-world shape.
  mkdir -p "$FIX/noroot/scripts"
  ln -s "$LINT" "$FIX/noroot/scripts/test-hermeticity-lint.sh"
  # $FIX/noroot has no tests/ ⇒ case (e) gets exit 2. Resolution now follows the symlink to the real
  # checkout, so this must still be GREEN — the assertion is that we do not fabricate a stale-allowlist
  # verdict out of a path problem.
  run bash "$FIX/noroot/scripts/test-hermeticity-lint.sh" --selftest
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | grep -c 'allowlist is stale')" -eq 0 ]
}

@test "RED: a NEW non-hermetic suite fails (an unlisted suite must fixture \$HOME)" {
  mk_suite leak 'REPO="$(pwd)"'
  CC_HERM_ALLOWLIST="" run bash "$LINT" "$FIX/leak"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q 'LEAK'
  echo "$output" | grep -q 'Do NOT add to the allowlist'
}

@test "RED: an allowlisted suite that is now hermetic fails (the ratchet only ever shrinks)" {
  mk_suite herm 'export HOME="$BATS_TEST_TMPDIR/home"'
  CC_HERM_ALLOWLIST="zz-fixture.bats" run bash "$LINT" "$FIX/herm"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q 'RATCHET'
  echo "$output" | grep -q 'delete their lines'
}

@test "GREEN: a hermetic, unlisted suite passes — and so does a grandfathered non-hermetic one" {
  mk_suite herm 'export HOME="$BATS_TEST_TMPDIR/home"'
  CC_HERM_ALLOWLIST="" run bash "$LINT" "$FIX/herm"
  [ "$status" -eq 0 ]
  mk_suite leak 'REPO="$(pwd)"'
  CC_HERM_ALLOWLIST="zz-fixture.bats" run bash "$LINT" "$FIX/leak"
  [ "$status" -eq 0 ]
}

@test "a per-TEST \$HOME does not count as hermetic (every other test still hits the live ~/)" {
  mkdir -p "$FIX/pertest"
  { echo '#!/usr/bin/env bats'; echo 'setup() {'; echo '  REPO="$(pwd)"'; echo '}'
    echo '@test "a" { export HOME="$BATS_TEST_TMPDIR/home"; true; }'; echo '@test "b" { true; }'; } \
    > "$FIX/pertest/zz-fixture.bats"
  CC_HERM_ALLOWLIST="" run bash "$LINT" "$FIX/pertest"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q 'LEAK'
}

@test "LOUD: an unusable scan dir exits 2, never a silent green" {
  CC_HERM_ALLOWLIST="" run bash "$LINT" "$FIX/does-not-exist"
  [ "$status" -eq 2 ]
  CC_HERM_ALLOWLIST="" run bash "$LINT" "$FIX"                # exists, but holds zero .bats suites
  [ "$status" -eq 2 ]
}

@test "the nightly picks it up automatically (name matches *lint*.sh AND supports_selftest)" {
  case "$(basename "$LINT")" in *lint*.sh) ;; *) false ;; esac    # scripts/*lint*.sh glob
  grep -qE -- '--selftest|selftest\)' "$LINT"                     # nightly's supports_selftest() probe
}
