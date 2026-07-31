#!/usr/bin/env bats
# chromium-bundle-lint — the ratchet that stops a screenshot path from launching the FULL
# Chromium.app bundle instead of chrome-headless-shell.
#
# The scar (2026-07-30, operator-reported): the macOS Dock strobed a launching-app tile every 1-2s
# for as long as any banner render ran. scripts/banner-shots.sh exec'd the playwright FULL bundle
# once per shot, and that bundle checks in with LaunchServices on EVERY launch even under
# --headless, so the Dock painted a tile for the ~1.3s each process lived. Measured against a
# 0-launch idle baseline of 0: full bundle x20 -> 22 app CHECKINs; chrome-headless-shell x20 -> 0.
#
# Four properties are proved here, and all four matter:
#   • it DISCRIMINATES — red on the real scar shape, green on the remedy and on the shell binary;
#   • a NON-VERDICT is never a pass — an unusable scan root exits 2, not 0, because a detector that
#     could not run has nothing to say about the tree;
#   • it is GREEN on the tree as it stands — a lint that ships standing-red is rot, and the nightly
#     runs every scripts/*lint*.sh, so a false red here poisons the whole nightly signal;
#   • it is WIRED AT THE CHOKEPOINT — enforcement by its own suite alone is detection, not a gate
#     (memory: enforcement-must-live-at-the-chokepoint), so run_gate must invoke it. gate-select
#     will not pick this suite up when the edited file is a PRODUCER (a new screenshot script)
#     rather than the lint itself, which is precisely how this class stays invisible.
#
# Assertions use the explicit `|| { …; false; }` form throughout: a non-final `[[ ]]` is
# errexit-EXEMPT under bats and would be a DEAD assertion that can never fail
# (memory: bats-dead-assertions-errexit-exemptions).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LINT="$REPO/scripts/chromium-bundle-lint.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"   # dogfood the sibling hermeticity rule
  FIX="$BATS_TEST_TMPDIR/fix"; mkdir -p "$FIX"
}

# mk <case> <body> — a scan root $FIX/<case> holding one shell file under scripts/
mk() {
  mkdir -p "$FIX/$1/scripts"
  { printf '#!/bin/bash\n'; printf '%s\n' "$2"; } > "$FIX/$1/scripts/probe.sh"
}

@test "the lint is executable" {
  [ -x "$LINT" ] || { echo "not executable: $LINT"; false; }
}

@test "--selftest passes (the detector still discriminates)" {
  run "$LINT" --selftest
  [ "$status" -eq 0 ] || { echo "selftest failed:"; echo "$output"; false; }
}

@test "the tree as it stands is GREEN (a standing-red lint is rot)" {
  run "$LINT" --root "$REPO"
  [ "$status" -eq 0 ] || { echo "lint is red on the tree:"; echo "$output"; false; }
}

@test "RED: the real scar shape fires" {
  mk red 'for _c in "$HOME"/Library/Caches/ms-playwright/chromium-*/chrome-mac/Chromium.app/Contents/MacOS/Chromium; do
  [[ -x "$_c" ]] && CHROME="$_c"
done'
  run "$LINT" --root "$FIX/red"
  [ "$status" -eq 1 ] || { echo "scar shape did not fire (status=$status)"; echo "$output"; false; }
  echo "$output" | grep -q 'CHROMIUM-BUNDLE' || { echo "no named finding:"; echo "$output"; false; }
}

@test "GREEN: the remedy does not fire (the lint must not reject its own fix)" {
  mk green 'CHROME="$(resolve_headless_chrome "${BANNER_CHROME:-}")"'
  run "$LINT" --root "$FIX/green"
  [ "$status" -eq 0 ] || { echo "the remedy fired:"; echo "$output"; false; }
}

@test "GREEN: the chrome-headless-shell binary does not fire" {
  mk shell 'CHROME="$HOME/Library/Caches/ms-playwright/chromium_headless_shell-1228/chrome-headless-shell-mac-arm64/chrome-headless-shell"'
  run "$LINT" --root "$FIX/shell"
  [ "$status" -eq 0 ] || { echo "the headless shell fired:"; echo "$output"; false; }
}

@test "a NON-VERDICT is loud: an unusable scan root exits 2, never a clean 0" {
  run "$LINT" --root "$FIX/does-not-exist"
  [ "$status" -eq 2 ] || { echo "missing root gave status=$status, wanted 2"; echo "$output"; false; }

  mkdir -p "$FIX/empty"
  run "$LINT" --root "$FIX/empty"
  [ "$status" -eq 2 ] || { echo "root with no source dirs gave status=$status, wanted 2"; echo "$output"; false; }
}

@test "own-scope: a finding outside this land's diff is advisory, inside it blocks" {
  mk red 'for _c in "$HOME"/Library/Caches/ms-playwright/chromium-*/chrome-mac/Chromium.app/Contents/MacOS/Chromium; do
  [[ -x "$_c" ]] && CHROME="$_c"
done'
  CC_CHROMIUM_OWN="scripts/unrelated.sh" run "$LINT" --root "$FIX/red"
  [ "$status" -eq 0 ] || { echo "an out-of-scope finding blocked (status=$status)"; false; }

  CC_CHROMIUM_OWN="scripts/probe.sh" run "$LINT" --root "$FIX/red"
  [ "$status" -eq 1 ] || { echo "an in-scope finding did not block (status=$status)"; false; }
}

@test "the real producers use resolve_headless_chrome, not the bundle" {
  for f in scripts/banner-shots.sh scripts/banner-timeline-anchor.sh; do
    grep -q 'resolve_headless_chrome' "$REPO/$f" \
      || { echo "$f no longer resolves its Chromium through the helper"; false; }
  done
}

@test "WIRED AT THE CHOKEPOINT: run_gate invokes the lint" {
  # A lint enforced only by this suite is post-hoc detection. gate-select picks a suite by the
  # files a land touches, so a NEW screenshot script would never select this file.
  grep -q 'chromium-bundle-lint' "$REPO/scripts/ship-land.sh" \
    || { echo "ship-land.sh does not invoke chromium-bundle-lint.sh — the ratchet is unenforced"; false; }
}
