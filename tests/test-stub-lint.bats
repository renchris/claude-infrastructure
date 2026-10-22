#!/usr/bin/env bats
# test-stub-lint — proves rule R4 (scripts/test-stub-lint.sh) goes RED on each inline #! stub-write form
# and stays GREEN on everything the ratchet grandfathers or must not claim.
#
# Why the rule exists: on macOS 15.8.1 every exec of a #! script by path retains ~1.1 KiB of kernel
# memory until reboot, and inline test stubs are exec'd thousands of times a run. cc_stub DIR NAME BODY
# (tests/helpers/cc-stub.bash) is the cure; the ratchet stops new inline stubs while old ones convert.
#
# Fixture lines spell the shebang as "${SB}" so THIS file never matches the rule it tests — a literal
# one here would count against this file's own baseline of 0 and redden the real-tree case.
# Assertions use the explicit `|| { …; false; }` form: a non-final `[[ ]]` is errexit-EXEMPT under bats.

SB='#!'

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  LINT="$REPO/scripts/test-stub-lint.sh"
  # Fixture $HOME: never read or write the operator's live ~/ (scripts/test-hermeticity-lint.sh).
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  R="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$R/tests/helpers" "$R/config"
  git -C "$R" init -q
  printf '# fixture baseline\n' > "$R/config/test-stub-baseline.tsv"
  unset TEST_STUB_LINT_BASELINE
}

# _put <repo-relative path> <line>... — write the lines and stage the file, so it is in the population.
_put() {
  local p="$1"; shift
  mkdir -p "$(dirname "$R/$p")"
  printf '%s\n' "$@" > "$R/$p"
  git -C "$R" add -- "$p"
}

_base() { printf '%s\t%s\n' "$1" "$2" >> "$R/config/test-stub-baseline.tsv"; }

_lint() { run env TEST_STUB_LINT_ROOT="$R" /bin/bash "$LINT" "$@"; }

@test "the real tree passes against the committed baseline — a ratchet that ships standing-red is rot" {
  run /bin/bash "$LINT"
  [ "$status" -eq 0 ] || { echo "lint went red on the tree:"; echo "$output"; false; }
}

@test "--selftest discriminates (exit 0)" {
  run /bin/bash "$LINT" --selftest
  [ "$status" -eq 0 ] || { echo "selftest failed:"; echo "$output"; false; }
}

@test "RED: a printf stub write is caught and its line named" {
  _put tests/p.bats "${SB}/usr/bin/env bats" "x=1" "printf '${SB}/bin/sh\\nexit 0\\n' > stub"
  _lint
  [ "$status" -eq 1 ] || { echo "expected rc 1, got $status:"; echo "$output"; false; }
  [[ "$output" == *"tests/p.bats: 1 inline #! stub write(s), baseline 0"* ]] || { echo "$output"; false; }
  [[ "$output" == *"lines: 3"* ]] || { echo "offending line not named:"; echo "$output"; false; }
}

@test "RED: an echo stub write (double-quoted) is caught" {
  _put tests/e.bats "${SB}/usr/bin/env bats" "echo \"${SB}/bin/bash\" > stub"
  _lint
  [ "$status" -eq 1 ] || { echo "expected rc 1, got $status:"; echo "$output"; false; }
  [[ "$output" == *"tests/e.bats: 1 inline"* ]] || { echo "$output"; false; }
}

@test "RED: a #! line directly under each heredoc opener spelling is caught" {
  _put tests/h.bats "${SB}/usr/bin/env bats" \
    "cat > a <<'EOF'" "${SB}/bin/sh" "EOF" \
    "cat > b <<-EOF" "	${SB}/bin/sh" "	EOF" \
    "cat > c << \"SH\"" "${SB}/bin/bash" "SH" \
    "cat > d <<\\EOF" "${SB}/bin/sh" "EOF"
  _lint
  [ "$status" -eq 1 ] || { echo "expected rc 1, got $status:"; echo "$output"; false; }
  [[ "$output" == *"tests/h.bats: 4 inline"* ]] || { echo "not all four forms counted:"; echo "$output"; false; }
}

@test "CONTROL: a file's own line-1 shebang never counts" {
  _put tests/one.sh "${SB}/bin/bash" "true"
  _lint
  [ "$status" -eq 0 ] || { echo "line 1 counted:"; echo "$output"; false; }
}

@test "CONTROL: a heredoc NOT followed by #!, a here-string and a later #! line are not stub writes" {
  _put tests/n.bats "${SB}/usr/bin/env bats" \
    "cat > a <<EOF" "plain" "${SB} not directly under the opener" "EOF" \
    "read -r v <<< \"\$x\"" "${SB}/bin/sh after a here-string"
  _lint
  [ "$status" -eq 0 ] || { echo "false positive:"; echo "$output"; false; }
}

@test "EXEMPT: tests/helpers/cc-stub.bash may write #! — it is the cure" {
  _put tests/helpers/cc-stub.bash "${SB}/bin/bash" "printf '${SB}/bin/sh\\n' > out"
  _lint
  [ "$status" -eq 0 ] || { echo "the helper was convicted:"; echo "$output"; false; }
  _lint --files tests/helpers/cc-stub.bash
  [ "$status" -eq 0 ] || { echo "the helper was convicted under --files:"; echo "$output"; false; }
}

@test "EXEMPT: a body handed to cc_stub is the cure, in all three spellings" {
  _put tests/cc.bats "${SB}/usr/bin/env bats" \
    "cc_stub \"\$D\" x - <<'EOF'" "${SB}/bin/sh" "EOF" \
    "cc_stub \"\$D\" y \"\$(printf '${SB}/bin/sh\\nexit 0\\n')\"" \
    "cc_stub \"\$D\" z \\" "  \"\$(printf '${SB}/bin/sh\\nexit 0\\n')\""
  _lint
  [ "$status" -eq 0 ] || { echo "a cc_stub body was convicted:"; echo "$output"; false; }
  # …and a plain write next to them still counts
  _put tests/cc.bats "${SB}/usr/bin/env bats" "cc_stub \"\$D\" x - <<'EOF'" "${SB}/bin/sh" "EOF" \
    "printf '${SB}/bin/sh\\n' > \"\$D/w\""
  _lint
  [[ "$output" == *"tests/cc.bats: 1 inline"* ]] || { echo "$output"; false; }
}

@test "GRANDFATHERED: a file AT its baseline is green; one more stub turns it red" {
  _put tests/g.bats "${SB}/usr/bin/env bats" "echo '${SB}/bin/a' > a" "echo '${SB}/bin/b' > b"
  _base tests/g.bats 2
  _lint
  [ "$status" -eq 0 ] || { echo "grandfathered file convicted:"; echo "$output"; false; }
  _put tests/g.bats "${SB}/usr/bin/env bats" "echo '${SB}/bin/a' > a" "echo '${SB}/bin/b' > b" \
    "echo '${SB}/bin/c' > c"
  _lint
  [ "$status" -eq 1 ] || { echo "growth past the baseline passed:"; echo "$output"; false; }
  [[ "$output" == *"tests/g.bats: 3 inline #! stub write(s), baseline 2"* ]] || { echo "$output"; false; }
  [[ "$output" == *"lines: 2 3 4"* ]] || { echo "lines not listed:"; echo "$output"; false; }
}

@test "DECREASED: a file below its baseline is green and the lock-in is suggested" {
  _put tests/d.bats "${SB}/usr/bin/env bats" "echo '${SB}/bin/a' > a"
  _base tests/d.bats 3
  _lint
  [ "$status" -eq 0 ] || { echo "decreased file convicted:"; echo "$output"; false; }
  [[ "$output" == *"below baseline"* ]] || { echo "no lock-in hint:"; echo "$output"; false; }
}

@test "--files checks only the named paths" {
  _put tests/bad.bats "${SB}/usr/bin/env bats" "echo '${SB}/bin/sh' > s"
  _put tests/ok.bats "${SB}/usr/bin/env bats" "true"
  _lint --files tests/ok.bats
  [ "$status" -eq 0 ] || { echo "--files leaked past its scope:"; echo "$output"; false; }
  _lint --files tests/ok.bats tests/bad.bats
  [ "$status" -eq 1 ] || { echo "--files missed a named offender:"; echo "$output"; false; }
  _lint --files tests/gone.bats scripts/x.sh
  [ "$status" -eq 0 ] || { echo "an absent or out-of-population path was not skipped:"; echo "$output"; false; }
}

@test "--write-baseline records the tree's counts and the tree then passes" {
  _put tests/w.bats "${SB}/usr/bin/env bats" "echo '${SB}/bin/a' > a" "printf '${SB}/bin/b' > b"
  _lint --write-baseline
  [ "$status" -eq 0 ] || { echo "write failed:"; echo "$output"; false; }
  grep -qx "$(printf 'tests/w.bats\t2')" "$R/config/test-stub-baseline.tsv" \
    || { echo "row missing:"; cat "$R/config/test-stub-baseline.tsv"; false; }
  _lint
  [ "$status" -eq 0 ] || { echo "a freshly written baseline reads red:"; echo "$output"; false; }
}

@test "NO VERDICT: a missing baseline or a non-git root exits 2, never a false green" {
  run env TEST_STUB_LINT_ROOT="$R" TEST_STUB_LINT_BASELINE="$R/nope.tsv" /bin/bash "$LINT"
  [ "$status" -eq 2 ] || { echo "missing baseline: expected rc 2, got $status:"; echo "$output"; false; }
  mkdir -p "$BATS_TEST_TMPDIR/nogit"
  run env GIT_CEILING_DIRECTORIES="$BATS_TEST_TMPDIR" TEST_STUB_LINT_ROOT="$BATS_TEST_TMPDIR/nogit" /bin/bash "$LINT"
  [ "$status" -eq 2 ] || { echo "non-git root: expected rc 2, got $status:"; echo "$output"; false; }
}
