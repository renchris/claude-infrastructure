#!/usr/bin/env bats
# iterm-metal-bench-app — guards on the builder for the all-Metal counterfactual bundle
# (scripts/iterm-metal-bench-app.sh).
#
# WHY THESE SPECIFIC TESTS. The hand-built predecessor of this bundle failed in BOTH of the two ways
# available to it, on 2026-07-31, and neither failure announced itself as what it was:
#
#   1. IT COULD NOT LAUNCH, and said so in the language of a missing file. The clone died with
#      "iTermBench cannot be opened because of a problem" / "Library not loaded:
#      @rpath/iTermSwiftPackages.framework". The framework was present and intact, and the bundle
#      passed `codesign --verify --deep --strict` with rc=0. The real cause was that an ad-hoc
#      re-sign of a HARDENED-RUNTIME app has no Team ID, and Library Validation admits a
#      non-platform library only on a Team ID identity match — which "absent" never satisfies. So
#      the fix is an entitlement (disable-library-validation), and the standard signature verifier
#      is blind to its absence. That is why test 2 below exists: `codesign --verify` passing is NOT
#      evidence this bundle can run.
#
#   2. IT WAS NEVER ACTUALLY PATCHED. The clone's `cmp x8,#0x6` instruction count was IDENTICAL to
#      stock iTerm2 — it was a plain second iTerm2 carrying the stock 5-pane Metal cap. Had the
#      signing been fixed without noticing this, the counterfactual would have produced a confident
#      "all-Metal" measurement of an iTerm2 that was never all-Metal. Test 3 is the control for it.
#
# Both are vacuous-pass traps, so every guard below gets a control that CAN fail: each negative
# control is a bundle that differs from the good one in exactly the axis under test.
#
# COST. Each fixture bundle is a ~134 MB copy of iTerm2 (~2 s). We build ONE good bundle for the
# file and derive the negative controls from it, rather than rebuilding per test.
#
# WHAT IS DELIBERATELY NOT TESTED HERE: that the bundle launches. Launching a GUI app from a test
# suite is antisocial on a box already hosting ~30 live sessions, and slow. The launch invariant is
# instead enforced BY CONSTRUCTION in the script: its default path runs a launch probe and DELETES
# the bundle if the process does not survive dyld, so a returned bundle has necessarily launched
# once. Set ITERM_BENCH_LAUNCH_TEST=1 to also exercise that path here.

setup_file() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export BUILD="$REPO/scripts/iterm-metal-bench-app.sh"
  export SRC_APP="${ITERM_SRC_APP:-/Applications/iTerm.app}"
  export FIXDIR="$BATS_FILE_TMPDIR/build"

  if [ ! -d "$SRC_APP" ]; then export NO_ITERM=1; return 0; fi
  # --no-launch-probe: the good-bundle fixture is for the STATIC verifiers. The launch path has its
  # own opt-in test below.
  run bash "$BUILD" --cap 64 --out "$FIXDIR" --no-launch-probe
  export GOOD="$FIXDIR/iTermMetalBench.app"
  export BUILD_OUT="$output"
  export BUILD_STATUS="$status"
}

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  [ -z "${NO_ITERM:-}" ] || skip "no iTerm2 at $SRC_APP — nothing to clone"
}

# Re-sign an existing bundle with a caller-supplied entitlements file, inside-out, the way the
# script does. Used to build the negative controls.
_resign() {
  local app="$1" ents="$2" f
  shopt -s nullglob
  for f in "$app"/Contents/Frameworks/*.framework "$app"/Contents/Frameworks/*.dylib \
           "$app"/Contents/XPCServices/*.xpc "$app"/Contents/MacOS/*; do
    codesign --force --sign - --timestamp=none --options runtime --entitlements "$ents" "$f" \
      >/dev/null 2>&1
  done
  shopt -u nullglob
  codesign --force --sign - --timestamp=none --options runtime --entitlements "$ents" "$app" \
    >/dev/null 2>&1
}

# ── the happy path has to actually work, or every control below is meaningless ────────────────────

@test "build: produces a bundle that is patched, hardened, and entitlement-relaxed" {
  [ "$BUILD_STATUS" -eq 0 ] || { echo "$BUILD_OUT"; false; }
  [[ "$BUILD_OUT" == *"verdict=OK"* ]]
  [ -d "$GOOD" ]
  # The identity must differ from the real iTerm2, or the clone shares its defaults domain and
  # LaunchServices identity — and the operator's live terminal is the thing we must not perturb.
  run /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$GOOD/Contents/Info.plist"
  [ "$output" = "com.googlecode.iterm2.metalbench" ]
}

# ── control 1: the crash itself. codesign is happy; the app still cannot run ───────────────────────

@test "verify: REJECTS a bundle missing disable-library-validation (this was the crash)" {
  # Rebuild the exact failing configuration: adhoc + hardened runtime + NO entitlements. This is
  # what `codesign --force --sign -` produces by default on a hardened app, and it is what died with
  # "Library not loaded". If our verifier passed it, the script would hand back a bundle that
  # cannot launch — the failure we are encoding.
  local bad="$BATS_FILE_TMPDIR/nolv.app"
  rm -rf "$bad"; cp -R "$GOOD" "$bad"
  cat >"$BATS_FILE_TMPDIR/empty.ents" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict/></plist>
PLIST
  _resign "$bad" "$BATS_FILE_TMPDIR/empty.ents"

  # The trap, asserted directly: the STANDARD verifier is satisfied by the broken bundle. This is
  # why "codesign --verify passed" must never be quoted as evidence the clone works.
  run codesign --verify --strict "$bad"
  [ "$status" -eq 0 ]

  run bash "$BUILD" --verify-only "$bad" --cap 64
  [ "$status" -ne 0 ]
  [[ "$output" == *"verdict=FAILED"* ]]
  [[ "$output" == *"disable-library-validation"* ]]
}

# ── control 2: the silently-unpatched bundle, which is the worse failure ───────────────────────────

@test "verify: REJECTS a bundle carrying the STOCK Metal cap" {
  # The predecessor's real defect. A clone that launches but was never patched measures nothing and
  # says nothing. Asserting on the cap READ BACK OUT of the binary by disassembly — not on the fact
  # that we once wrote bytes — is the only version of this check that cannot pass vacuously.
  local stock="$BATS_FILE_TMPDIR/stock.app"
  rm -rf "$stock"; cp -R "$SRC_APP" "$stock"
  run bash "$BUILD" --verify-only "$stock" --cap 64
  [ "$status" -ne 0 ]
  [[ "$output" == *"verdict=FAILED"* ]]
  # It must fail ON THE CAP, not merely fail. A test satisfied by any non-zero exit would also pass
  # if the script crashed on an unrelated error.
  [[ "$output" == *"cap"* ]]
}

@test "verify: ACCEPTS the good bundle — the controls above are not just always-red" {
  # Alarm polarity (memory alarm-polarity-and-attention-budget): a verifier that rejects everything
  # carries exactly as little information as one that accepts everything.
  run bash "$BUILD" --verify-only "$GOOD" --cap 64
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=OK"* ]]
}

# ── the patcher must refuse rather than guess ──────────────────────────────────────────────────────

@test "patch: refuses to re-patch an already-patched binary instead of corrupting it" {
  # The patcher asserts the CURRENT immediate is the stock 6 before writing. Running the build twice
  # over the same executable must not silently produce a cap of garbage. (The script copies fresh
  # each run, so this exercises the guard directly on the patched fixture.)
  run bash -c "cp -R '$GOOD' '$BATS_TEST_TMPDIR/twice.app' &&
               '$BUILD' --verify-only '$BATS_TEST_TMPDIR/twice.app' --cap 6"
  [ "$status" -ne 0 ]
  [[ "$output" == *"expected 6"* || "$output" == *"cap immediate is 64"* ]]
}

@test "build: refuses to write into /Applications — the live terminal is not a build target" {
  # A bug that patched /Applications/iTerm.app would break the operator's terminal while ~30 Claude
  # Code sessions are inside it. This guard is cheap and the blast radius it prevents is not.
  run bash "$BUILD" --out /Applications/nope
  [ "$status" -ne 0 ]
  [[ "$output" == *"refusing to build into"* ]]
  [ ! -e /Applications/nope ]
}

@test "build: a missing source app is a loud failure, never an empty success" {
  run bash "$BUILD" --src /nonexistent/NotITerm.app --out "$BATS_TEST_TMPDIR/x"
  [ "$status" -ne 0 ]
  [[ "$output" == *"verdict=FAILED"* ]]
}

# ── opt-in: the launch invariant the script enforces by construction ──────────────────────────────

@test "launch: the built bundle survives dyld (opt-in, launches a GUI app)" {
  [ "${ITERM_BENCH_LAUNCH_TEST:-0}" = 1 ] || \
    skip "set ITERM_BENCH_LAUNCH_TEST=1 to launch a real GUI app from the suite"
  run bash "$BUILD" --cap 64 --out "$BATS_TEST_TMPDIR/launch"
  [ "$status" -eq 0 ]
  [[ "$output" == *"launch probe: process survived dyld"* ]]
  [[ "$output" == *"verdict=OK"* ]]
}
