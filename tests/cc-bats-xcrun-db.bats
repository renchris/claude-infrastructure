#!/usr/bin/env bats
# cc-bats-xcrun-db.bats — the warm per-day xcrun_db cc-bats exports to every suite (X3, 2026-10-17).
#
# WHAT IS UNDER TEST. When /usr/bin/git is Apple's xcrun shim, every git a test forks pays an xcrun
# cache miss (~77M instructions, ~30 ms sys, an xcodebuild child), because suites rewrite or ignore the
# shared cache. bin/cc-bats exports `xcrun_db` at one dated path per day, set-default: a value already
# in the environment passes through verbatim. It must hold on EVERY exec path of the shim — the
# kill switch, the re-entrancy hand-off and the final exec — so each path gets its own case.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  SHIM="$REPO/bin/cc-bats"
  TMP="$BATS_TEST_TMPDIR"
  export HOME="$TMP/home"
  mkdir -p "$HOME/.claude/state" "$TMP/td"
  unset CC_BATS_ACTIVE CC_BATS_QOS CC_BATS_QUIET CC_BATS_REAL CC_BATS_BAND CC_BATS_TASKPOLICY \
        CC_BATS_MAX_ROOTS CC_BATS_ROOTS_DIR CC_BATS_ADMIT_SKIP
  # The stub reports what it inherited; `UNSET` is distinguishable from set-but-empty.
  STUB="$TMP/realbats"
  # shellcheck disable=SC2016  # the STUB expands it at run time; expanding it here is the bug
  printf '#!/bin/bash\necho "XCRUN_DB=${xcrun_db-UNSET}"\n' > "$STUB"
  chmod 755 "$STUB"
  WANT="$TMP/td/cc-test-xcrun_db.$(/bin/date +%Y%m%d)"
}

# shim <extra env...> — xcrun_db REMOVED from the inherited env (this suite itself runs under
# cc-bats, so the ambient value is exactly the thing that must not decide the verdict).
shim() {
  run env -u xcrun_db TMPDIR="$TMP/td/" CC_BATS_ROOTS_DIR="$TMP/roots" CC_BATS_REAL="$STUB" "$@" \
      /bin/bash "$SHIM" tests/does-not-need-to-exist.bats
}

@test "the final exec path exports the dated db under TMPDIR, trailing slash normalised" {
  shim
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"XCRUN_DB=$WANT"* ]] || false
}

@test "the CC_BATS_QOS=off kill-switch path exports it too" {
  shim CC_BATS_QOS=off
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"XCRUN_DB=$WANT"* ]] || false
}

@test "the re-entrancy hand-off (CC_BATS_ACTIVE=1) exports it too" {
  shim CC_BATS_ACTIVE=1
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"XCRUN_DB=$WANT"* ]] || false
}

@test "a pre-set xcrun_db passes through verbatim (set-default, never overwritten)" {
  shim xcrun_db=/somewhere/else.db
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"XCRUN_DB=/somewhere/else.db"* ]] || false
}

@test "a SET-BUT-EMPTY xcrun_db is honoured verbatim, like every value seam in the shim" {
  shim xcrun_db=
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"XCRUN_DB="$'\n'* || "$output" == *"XCRUN_DB=" ]] || false
}
