#!/usr/bin/env bats
# migration 0057 — the operator's install of the root fseventsd watchdog (c10).
#
# Pins: the header carries the c10 contract (class, step, run line naming its --confirm target, a
# manual batch hold, a non-tautological verify); a bare run is a dry run that changes nothing; a
# --confirm naming anything but the label refuses before any admin step; --verify fails closed on
# each leg (not loaded, copy missing, copy not root-owned). The --confirm apply itself needs the macOS
# administrator dialog and is never run here; launchctl is a stub, so no test touches launchd.

bats_require_minimum_version 1.5.0

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  MIG="$REPO/migrations/0057-fseventsd-watchdog.sh"
  F="$BATS_TEST_TMPDIR/fx"; mkdir -p "$F"
  export CC_MIGRATION_REPO="$REPO"
  export FSE_INSTALL_DST="$F/libexec/claude-fseventsd-watch.sh" FSE_INSTALL_DST_PLIST="$F/claude.plist"
  printf '#!/bin/bash\necho "$*" >> "%s/launchctl.argv"\n[ -e "%s/loaded" ]\n' "$F" "$F" > "$F/launchctl"
  chmod +x "$F/launchctl"
  export FSE_INSTALL_LAUNCHCTL="$F/launchctl"
}

hdr() { grep -m1 "^# migration-$1:" "$MIG" | sed "s/^# migration-$1: *//"; }

@test "header: c10, an operator step, a run line naming its target, a manual hold, a real verifier" {
  [ "$(hdr class)" = c10 ]
  [ -n "$(hdr step)" ]
  [[ "$(hdr run)" == *"0057-fseventsd-watchdog.sh --confirm com.claude.fseventsd-watchdog" ]] || false
  [[ "$(hdr batch-hold)" == manual* ]] || false
  [[ "$(hdr verify)" == *"0057-fseventsd-watchdog.sh\" --verify" ]] || false
  [ -f "$REPO/$(hdr subject)" ]
}

@test "a bare run is a dry run: it prints the plan, exits 0 and writes nothing" {
  run bash "$MIG"
  [ "$status" -eq 0 ]
  [[ "$output" == *"(dry run): would copy"*"--confirm com.claude.fseventsd-watchdog"* ]] || false
  [ ! -e "$FSE_INSTALL_DST" ] && [ ! -e "$FSE_INSTALL_DST_PLIST" ]
  run ! grep -qsE 'bootstrap|bootout' "$F/launchctl.argv"
}

@test "--confirm with the wrong target refuses before any administrator step" {
  run bash "$MIG" --confirm com.claude.something-else
  [ "$status" -eq 1 ]
  [[ "$output" == *"--confirm must name the target"* ]] || false
  run ! grep -qsE 'bootstrap|bootout' "$F/launchctl.argv"
}

@test "--verify fails closed: not loaded, then copy missing, then copy not root-owned" {
  run bash "$MIG" --verify
  [ "$status" -eq 1 ]; [[ "$output" == *"is not loaded"* ]] || false
  touch "$F/loaded"
  run bash "$MIG" --verify
  [ "$status" -eq 1 ]; [[ "$output" == *"is missing"* ]] || false
  mkdir -p "$(dirname "$FSE_INSTALL_DST")"
  cp "$REPO/scripts/fseventsd-watch.sh" "$FSE_INSTALL_DST"                # owned by the test user
  cp "$REPO/launchd/system/com.claude.fseventsd-watchdog.plist" "$FSE_INSTALL_DST_PLIST"
  run bash "$MIG" --verify
  [ "$status" -eq 1 ]; [[ "$output" == *"is not root-owned"* ]] || false
}

@test "the system plist runs the ROOT-OWNED copy with --restart, never the repo path" {
  P="$REPO/launchd/system/com.claude.fseventsd-watchdog.plist"
  /usr/bin/plutil -lint "$P"
  [ "$(/usr/bin/plutil -extract ProgramArguments.0 raw -o - "$P")" = /bin/bash ]
  [ "$(/usr/bin/plutil -extract ProgramArguments.1 raw -o - "$P")" = /usr/local/libexec/claude-fseventsd-watch.sh ]
  [ "$(/usr/bin/plutil -extract ProgramArguments.2 raw -o - "$P")" = --restart ]
}
