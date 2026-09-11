#!/usr/bin/env bats
# herm-memo-worktrees.bats — test-hermeticity-lint's per-suite memo must CARRY ACROSS WORKTREES.
#
# THE DEFECT THIS PINS (follow-on 3 of the cloud-lane redesign, 2026-09-11). The memo's read set
# includes the seam/env TABLES, and both were built with every row's tool as an ABSOLUTE path under
# the checkout, while the two table roots were hashed as themselves. So every worktree minted its own
# key, and a land from a fresh worktree — which is most lands — carried nothing any other worktree had
# earned. Measured: a real precheck carried 0 of 656 suites, at 85.8s the gate's second-largest arm,
# against a store holding 69 checker dirs of this lint's shape minted in the previous 24h. The store is
# already shared by every worktree of a repo (<git-common-dir>/ship-land-memo), so the carry was
# available all along and the KEY was what refused it.
#
# THE FIXTURE REPRODUCES THE PRODUCTION SHAPE, not an approximation of it: ONE repo, TWO worktrees,
# and each runs the lint from ITS OWN copy, so ROOT differs between them exactly as it does between two
# landing worktrees. Rules 5 and 6 stay ON — they are what put paths into the key — and are affordable
# here because the tables are built from this corpus's handful of tools, not the real bin+scripts+hooks.
#
# 🚨 CASE 1 IS A POSITIVE CONTROL AND COMES FIRST: it holds before AND after the fix, so a red on case 2
# means "the key refused the carry", never "the memo was never armed".

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"          # hermeticity: never the operator's live ~
  mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  MAIN="$BATS_TEST_TMPDIR/main"
  WT2="$BATS_TEST_TMPDIR/wt2"
  mkdir -p "$MAIN/scripts/lib" "$MAIN/tests" "$MAIN/bin" "$MAIN/hooks"
  # The library travels with the lint: it is sourced from the lint's own ROOT, so a copy without it
  # is a lint whose memo is fail-closed OFF — correct, and silent. Case 1 is what would catch that.
  cp "$REPO/scripts/test-hermeticity-lint.sh" "$MAIN/scripts/"
  cp "$REPO/scripts/lib/gate-memo.sh" "$MAIN/scripts/lib/"
  # Glob into an array and slice, never `ls | head` (the .bats shellcheck ratchet blocks SC2012).
  ALL_SUITES=( "$REPO"/tests/*.bats )
  for f in "${ALL_SUITES[@]:0:12}"; do cp "$f" "$MAIN/tests/"; done
  ( cd "$MAIN" && git init -q . && git add -A \
      && git -c user.email=t@e.x -c user.name=t commit -qm corpus \
      && git worktree add -q --detach "$WT2" HEAD )
  # This suite names the lint, which carries both of its own anchors — a shape-5a seam defaulting to a
  # constant /tmp path, and a variable this repo injects into every pane. Pinned here for the reason
  # tests/herm-suite-memo.bats pins them: a suite taking no position would be judged by rules 5 and 6.
  export CC_HERM_SEAM_SELFPROBE="$BATS_TEST_TMPDIR/seam-anchor"
  export CC_HERM_ENV_SELFPROBE=0
}

run_in() {  # $1=checkout → combined output of that checkout's OWN lint copy over its own tests/
  ( cd "$1" && bash scripts/test-hermeticity-lint.sh tests 2>&1 ) || true
}

# An ABSENT attestation answers -1, never the empty string: `[ "" -gt 0 ]` aborts the test with a
# usage error, which reads as a red for the wrong reason and hides which assertion failed.
carried() {
  local v; v="$(printf '%s\n' "$1" | sed -n 's/.*per-suite memo — \([0-9]*\) suite verdict(s) carried.*/\1/p' | tail -1)"
  printf '%s' "${v:--1}"
}
proven() {
  local v; v="$(printf '%s\n' "$1" | sed -n 's/.*carried, \([0-9]*\) proven fresh.*/\1/p' | tail -1)"
  printf '%s' "${v:--1}"
}

@test "POSITIVE CONTROL: the memo arms and carries within ONE worktree" {
  first="$(run_in "$MAIN")"
  [ "$(carried "$first")" -eq 0 ] || { echo "$first"; false; }
  second="$(run_in "$MAIN")"
  [ "$(carried "$second")" -gt 0 ] || { echo "MEMO NEVER CARRIED — every case below is vacuous"; echo "$second"; false; }
}

@test "a SIBLING WORKTREE carries every verdict the first one earned — the key is root-relative" {
  run_in "$MAIN" >/dev/null                     # earn, from MAIN's own copy at MAIN's own ROOT
  warm="$(run_in "$MAIN")"
  n="$(carried "$warm")"
  [ "$n" -gt 0 ]
  sib="$(run_in "$WT2")"                        # same commit, same shared store, a DIFFERENT ROOT
  [ "$(carried "$sib")" -eq "$n" ] || { echo "sibling carried $(carried "$sib") of $n"; echo "$sib"; false; }
}

@test "the sibling's carried run reports the SAME findings as its own unmemoized run" {
  run_in "$MAIN" >/dev/null
  sib="$(run_in "$WT2")"
  [ "$(carried "$sib")" -gt 0 ]                 # it really was carried, or this compares nothing
  cold="$( ( cd "$WT2" && CC_HERM_MEMO=off bash scripts/test-hermeticity-lint.sh tests 2>&1 ) || true )"
  s="$(printf '%s\n' "$sib"  | grep -vE 'per-suite memo —' | sort)"
  c="$(printf '%s\n' "$cold" | grep -vE 'per-suite memo —' | sort)"
  [ "$s" = "$c" ]
}

@test "a RELATIVE table change still invalidates — relative is not the same as absent" {
  run_in "$MAIN" >/dev/null
  warm="$(run_in "$MAIN")"
  [ "$(carried "$warm")" -gt 0 ]
  # A new tool with a shape-5a seam adds ONE seam-table row, and moves no byte of the lint or any suite.
  # shellcheck disable=SC2016  # the fixture tool must CONTAIN the literal ${…:-/tmp/…} the extractor reads
  printf '#!/bin/bash\nWT_STATE="${CC_WT_TOOL_DIR:-/tmp/cc-wt-tool}"\n' > "$MAIN/bin/cc-wt-tool"
  ( cd "$MAIN" && git add -A && git -c user.email=t@e.x -c user.name=t commit -qm tool )
  after="$(run_in "$MAIN")"
  [ "$(carried "$after")" -eq 0 ] || { echo "a table row was added and $(carried "$after") verdicts still carried"; false; }
  [ "$(proven "$after")" -gt 0 ]
}
