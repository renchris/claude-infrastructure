#!/usr/bin/env bats
# deploy-parity-assert.sh — the LIVE-LAYER half. Asserts the operator's real deployment.
#
# WHY THIS FILE EXISTS AT ALL — it is the other half of a SPLIT, not a new suite (2026-07-31).
# scripts/host-suites.manifest partitions the corpus per FILE: a listed suite is excluded from the
# tree verdict (postland-verify.sh runs tests/*.bats MINUS the manifest) AND from the land gate
# smoke (ship-land.sh filter_host_suites), and runs ONLY post-deploy via deploy-live.sh. That is
# right for a suite whose subject is ~/.claude — the tree under verification is by definition ahead
# of what is deployed, so pre-deploy such a suite can only fail while the deploy waits on the very
# verdict it is failing. It is WRONG as a unit of measure when one file mixes the two kinds.
#
# tests/deploy-parity.bats was exactly that mixed file: 31 tests, of which 29 were fully hermetic
# (fixture repo + fixture bindir + fixture live root under $BATS_TEST_TMPDIR) and 2 — the two below
# — read the operator's real ~/bin and ~/.claude. Listing the FILE therefore rode all 31 out of the
# gate on the coat-tails of these 2. Measured on the tree at 09a0214a: a land touching
# scripts/deploy-parity-assert.sh selected exactly one direct suite, tests/deploy-parity.bats, and
# filter_host_suites removed it — the land ran ZERO tests, and the exit-3 third-state regression
# guards (7a40d5a8 — "could not compare" is not parity) were first exercised only AFTER the change
# was already live. Splitting the file makes the file boundary match the partition boundary, which
# is the manifest's own frozen contract rather than a change to it.
#
# THE ADMISSION RULE for this file, so the split cannot quietly reverse: a test belongs HERE iff it
# lets the assert resolve the REAL ~/bin or the REAL ~/.claude — i.e. it runs with CC_PARITY_BINDIR
# and CC_PARITY_LIVE unset. Everything else belongs in tests/deploy-parity.bats, which now runs in
# the tree verdict and in the land smoke and is pinned hermetic by scripts/test-hermeticity-lint.sh.
# tests/deploy-parity.bats asserts both directions of that partition against the manifest, so
# neither file can drift back without a named RED.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export ASSERT="$REPO_ROOT/scripts/deploy-parity-assert.sh"
  # STRUCTURAL, not per-test: the whole POINT of this file is that the assert resolves the real
  # ~/bin and ~/.claude. An inherited CC_PARITY_* from the calling environment would silently
  # re-point it at somebody else's fixture and every test below would pass while asserting nothing
  # about the host — a fail-open of the file's entire purpose. The per-test `env -u` guards stay as
  # they were; this makes the contract hold for the file rather than one test at a time.
  unset CC_PARITY_REPO CC_PARITY_BINDIR CC_PARITY_STRICT CC_PARITY_COPY CC_PARITY_LIVE
}

@test "the real repo passes its own assertion (guards the live host deployment)" {
  run env -u CC_PARITY_REPO -u CC_PARITY_BINDIR -u CC_PARITY_STRICT -u CC_PARITY_COPY "$ASSERT"
  # Exit 3 is the assert's NO-VERDICT state: a `diff` or the tracked-file listing could not RUN. That
  # is a fact about the machine, not about the live layer — and it is reachable here, because
  # deploy-live.sh runs this suite post-deploy at `nice -n 19` next to a corpus (fork exhaustion at
  # loadavg 15-48 is measured in scripts/host-suites.manifest). Letting it fall through to the
  # `-eq 0` below would turn a non-verdict into a live-layer RED that PAGES and files a backlog
  # packet — the same fabricated-verdict class this suite pins one level down, re-created in its own
  # consumer. A new third state has to be taught to everything that reads the exit code.
  # Exit 1 is NOT covered by this: real drift still fails here, loudly, as it must.
  [ "$status" -ne 3 ] || skip "assert returned NO VERDICT (exit 3), no claim about the host: $output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"claude-accounts"* ]]
}

# Regression, measured 2026-07-27 minutes after the existence leg landed: invoked by its DEPLOYED
# path the assert returned RC=1 "claude-accounts must be a symlink" while the same file returned
# RC=0 from the checkout — opposite verdicts, and the DRIFT claim was the false one. Cause: a bare
# dirname "$0" yields ~/.claude (not a git repo), so REPO became ~/.claude and every correctly
# linked tool was compared against ~/.claude/bin/<tool>. A guard that false-REDs through its own
# deployed path trains readers to ignore it — which is how the drift it exists to catch survived.
#
# LIVE by necessity, not by accident: the divergence under the bug comes from the strict-tool
# comparison against the REAL ~/bin (a fixture bindir makes both invocations agree trivially, which
# is the vacuity the non-vacuity assertions below exist to refuse). The MECHANISM half of this pair
# — that the $0-resolution loop is present in the script at all — is a pure text grep, so it stays
# in tests/deploy-parity.bats and keeps running in the land gate. Outcome here, mechanism there.
@test "the assert agrees with itself through a DEPLOYED symlink (\$0 resolved, not dirname'd)" {
  # CC_PARITY_REPO must be UNSET here: it short-circuits the very derivation under test.
  # The bin/ link is what makes the two verdicts DIVERGE under the bug: without it the strict-tool
  # comparison is skipped and both invocations agree trivially, so the assertion could not fail.
  d="$BATS_TEST_TMPDIR/dep"; mkdir -p "$d/scripts" "$d/bin"
  ln -s "$REPO_ROOT/bin/claude-accounts" "$d/bin/claude-accounts"
  ln -s "$ASSERT" "$d/scripts/deploy-parity-assert.sh"
  run env -u ITERM_SESSION_ID -u CC_PARITY_REPO -u CC_PARITY_BINDIR -u CC_PARITY_STRICT -u CC_PARITY_COPY -u CC_PARITY_LIVE bash "$d/scripts/deploy-parity-assert.sh"
  via_symlink="$status"; via_out="$output"
  run env -u ITERM_SESSION_ID -u CC_PARITY_REPO -u CC_PARITY_BINDIR -u CC_PARITY_STRICT -u CC_PARITY_COPY -u CC_PARITY_LIVE bash "$ASSERT"
  [ "$via_symlink" -eq "$status" ] || false
  # NON-VACUITY (2026-07-29). Two agreeing exit codes prove nothing if NEITHER invocation compared
  # anything — and a vacuous agreement is precisely the fail-open the exit-3 tests in the hermetic
  # sibling pin. So require evidence that a comparison actually happened: a named verdict, and not
  # the no-verdict state. Deliberately NOT pinned to 0 — the real host legitimately reads 1 while a
  # landed file awaits its live symlink, and this test is about AGREEMENT, not about the host being
  # clean (the test above owns that).
  [ "$via_symlink" -ne 3 ] || false
  [[ "$via_out" == *"claude-accounts"* ]] || false
}
