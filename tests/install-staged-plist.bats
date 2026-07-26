#!/usr/bin/env bats
# STAGED LaunchAgents must live OUTSIDE the directory install.sh auto-installs from.
#
# install.sh globs `launchd/*.plist` and, for each one, copies it to ~/Library/LaunchAgents AND
# runs `launchctl bootstrap`. So a staged plist sitting in launchd/ is activated the next time
# anyone runs the installer. For com.claude.relogin that means unattended credential re-auth
# starting because someone ran a setup script — the exact thing its own header forbids.
#
# Copying without bootstrapping is NOT a safe middle ground either: launchd bootstraps
# everything in ~/Library/LaunchAgents at the next login, so the copy IS the activation.
#
# The fix is structural rather than a conditional inside install.sh: a plain glob cannot reach a
# subdirectory, so `launchd/staged/` is immune BY CONSTRUCTION — nothing to keep in sync, no
# marker string that can drift. These tests pin the two halves of that invariant:
#   1. the glob directory contains NO self-declared-staged plist (the drift a human would cause
#      by dropping a new staged plist in the obvious place), and
#   2. install.sh's glob really is non-recursive, so `staged/` is genuinely out of reach.
# Both read install.sh and the plists off disk — nothing here restates a constant it checks.

setup() {
  # HERMETIC $HOME (scripts/test-hermeticity-lint.sh — the ratchet that binds every NEW suite).
  # Free here: every path below is under $REPO and nothing reads ~. Set anyway so the suite can
  # never start depending on the operator's live layer.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  INSTALL="$REPO/install.sh"
  MARKER='STAGED, NOT LOADED'
  GLOB_DIR="$REPO/launchd"
  STAGED_DIR="$REPO/launchd/staged"

  # A bare `! cmd` is errexit-EXEMPT in bats unless it is the final line of the @test, so every
  # negative assertion goes through this helper instead (house rule; verified on bats 1.13.0).
  refute() { run "$@"; [ "$status" -ne 0 ]; }
}

@test "install.sh still auto-installs launchd/*.plist (the premise these tests rest on)" {
  # If this ever stops being true the whole invariant is moot — and these tests would otherwise
  # keep passing vacuously while guarding nothing.
  grep -q 'for plist in "\$REPO_DIR"/launchd/\*\.plist; do' "$INSTALL"
  grep -q 'launchctl bootstrap' "$INSTALL"
}

@test "install.sh's glob is NON-recursive, so launchd/staged/ is unreachable by construction" {
  # A `*` glob does not descend, and no ** / -r / find sweep may creep in beside it.
  refute grep -qE 'launchd/(\*\*|.*\*/\*)\.plist' "$INSTALL"
  refute grep -qE 'find "?\$REPO_DIR"?/launchd' "$INSTALL"
}

@test "the staged plist is in launchd/staged/, NOT in the auto-installed glob dir" {
  [ -f "$STAGED_DIR/com.claude.relogin.plist" ]
  refute test -e "$GLOB_DIR/com.claude.relogin.plist"
}

@test "the staged plist declares itself staged (the marker a reader/grep relies on)" {
  grep -q "$MARKER" "$STAGED_DIR/com.claude.relogin.plist"
}

@test "NO plist in the auto-installed glob dir declares itself STAGED" {
  # The real regression this suite exists to catch: someone adds a staged plist and puts it in
  # launchd/ (the obvious place), where the installer WILL bootstrap it.
  local p n=0 offenders=""
  for p in "$GLOB_DIR"/*.plist; do
    [ -f "$p" ] || continue
    if grep -q "$MARKER" "$p"; then offenders="$offenders $(basename "$p")"; n=$((n + 1)); fi
  done
  [ -z "$offenders" ] || echo "staged plists in the auto-install dir:$offenders — move them to launchd/staged/"
  [ "$n" -eq 0 ]
}

@test "positive control: the glob dir is non-empty and the marker search can actually match" {
  # Guards the two ways the census above could pass while testing nothing: an empty glob dir,
  # or a marker that matches no file anywhere (a typo'd needle).
  local c
  c=$(find "$GLOB_DIR" -maxdepth 1 -name '*.plist' | wc -l | tr -d ' ')
  [ "$c" -gt 1 ]
  grep -rq "$MARKER" "$STAGED_DIR"
}
