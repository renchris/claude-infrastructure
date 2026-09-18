#!/usr/bin/env bats
# T17 of docs/plans/CONTINUOUS_DELIVERY_TO_LIVE_KITTY.md — the staged actuator for decision packet
# 4194644aea26 (class C, human-only: may the unattended converger restart a stale resident daemon).
#
# THE PROPERTY UNDER TEST IS A REFUSAL, NOT A FEATURE. The packet's whole value is that a human
# rules on it; an actuator that runs before the ruling answers the question by acting, which is the
# one thing class C forbids. So most cases here prove it REFUSES, and the mutant halves prove those
# refusals are consulted rather than decorative.
#
# HERMETIC: $HOME, CC_DECISIONS_DIR and CC_LAUNCHCTL_BIN are all fixtured. The launchctl seam is the
# load-bearing one — without it, proving "this refuses correctly" would bootout the operator's real
# converger to find out. Nothing here can touch the live plist or the live decisions store.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  MIG="$REPO/migrations/0031-resident-reload-flip.sh"

  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/Library/LaunchAgents"
  export CC_DECISIONS_DIR="$BATS_TEST_TMPDIR/decisions"; mkdir -p "$CC_DECISIONS_DIR"
  PACKET="$CC_DECISIONS_DIR/4194644aea26.json"

  # launchctl is a STUB that records its argv and succeeds.
  LCLOG="$BATS_TEST_TMPDIR/launchctl.log"
  export CC_LAUNCHCTL_BIN="$BATS_TEST_TMPDIR/launchctl-stub"
  { printf '#!/bin/bash\n'; printf 'printf "%%s\\n" "$*" >> "%s"\nexit 0\n' "$LCLOG"; } > "$CC_LAUNCHCTL_BIN"
  chmod +x "$CC_LAUNCHCTL_BIN"

  PLIST="$HOME/Library/LaunchAgents/com.claude.deploy-live.plist"
  make_plist
}

make_plist() {
  cat > "$PLIST" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.claude.deploy-live</string>
  <key>ProgramArguments</key><array><string>/bin/echo</string></array>
</dict>
</plist>
EOF
}

rule() { # <status> — write a packet in that state
  printf '{"id":"4194644aea26","class":"C","status":"%s"}\n' "$1" > "$PACKET"
}

pbread() { /usr/libexec/PlistBuddy -c 'Print :EnvironmentVariables:CC_INSTALL_RESIDENT_RELOAD' "$PLIST" 2>/dev/null; }

# Count this migration's backups by GLOB, not `ls | grep`: a filename is not a line of text, and the
# pipeline breaks on any name the shell would have matched literally (SC2010).
count_backups() {
  local f n=0
  for f in "$HOME/Library/LaunchAgents/"*.bak-0031-*; do [ -e "$f" ] && n=$((n + 1)); done
  printf '%s' "$n"
}

mutant() { # <sed-expr> → a broken copy of the migration
  local m="$BATS_TEST_TMPDIR/mig-mutant-$RANDOM.sh"
  sed "$1" "$MIG" > "$m"; chmod +x "$m"; printf '%s' "$m"
}

# ── THE REFUSALS ────────────────────────────────────────────────────────────────────────────────

@test "an OPEN packet REFUSES — the class-C ruling is not pre-empted by acting" {
  rule open
  run bash "$MIG"
  [ "$status" -eq 1 ]
  [[ "$output" == *"still OPEN"* ]] || false
  [ -z "$(pbread)" ]                      # and the plist was NOT touched
  [ ! -f "$LCLOG" ]                       # and launchctl was never invoked
}

@test "a VETOED packet REFUSES — a declined grant stays declined" {
  rule vetoed
  run bash "$MIG"
  [ "$status" -eq 1 ]
  [[ "$output" == *"VETOED"* ]] || false
  [ -z "$(pbread)" ]
}

@test "a MISSING packet REFUSES — no record of the grant means the grant was not made" {
  rm -f "$PACKET"
  run bash "$MIG"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not on disk"* ]] || false
  [ -z "$(pbread)" ]
}

@test "an UNREADABLE packet REFUSES — a ruling we cannot read is not a ruling (fails closed)" {
  printf 'not json at all\n' > "$PACKET"
  run bash "$MIG"
  [ "$status" -eq 1 ]
  [ -z "$(pbread)" ]
}

@test "a MISSING plist REFUSES — this never creates the converger it is granting power to" {
  rule actioned
  rm -f "$PLIST"
  run bash "$MIG"
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not exist"* ]] || false
  [ ! -f "$PLIST" ]
}

# ── THE GRANT, once ruled ───────────────────────────────────────────────────────────────────────

@test "an ACTIONED packet sets the flag, reloads the job, and verifies by reading it back" {
  rule actioned
  run bash "$MIG"
  [ "$status" -eq 0 ]
  [ "$(pbread)" = 1 ]
  run cat "$LCLOG"
  [[ "$output" == *"bootout"* ]] || false
  [[ "$output" == *"bootstrap"* ]] || false
}

@test "it is IDEMPOTENT — a second run is a no-op that does not re-bootout the converger" {
  rule actioned
  bash "$MIG" >/dev/null 2>&1
  : > "$LCLOG"
  run bash "$MIG"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already set"* ]] || false
  [ ! -s "$LCLOG" ]                       # no second reload
}

@test "a CONFLICTING value is left alone rather than overwritten" {
  rule actioned
  /usr/libexec/PlistBuddy -c 'Add :EnvironmentVariables dict' "$PLIST"
  /usr/libexec/PlistBuddy -c 'Add :EnvironmentVariables:CC_INSTALL_RESIDENT_RELOAD string 0' "$PLIST"
  run bash "$MIG"
  [ "$status" -eq 1 ]
  [[ "$output" == *"CONFLICT"* ]] || false
  [ "$(pbread)" = 0 ]                     # unchanged
}

@test "sibling EnvironmentVariables survive — the dict is added to, never replaced" {
  rule actioned
  /usr/libexec/PlistBuddy -c 'Add :EnvironmentVariables dict' "$PLIST"
  /usr/libexec/PlistBuddy -c 'Add :EnvironmentVariables:SOMETHING_ELSE string keepme' "$PLIST"
  run bash "$MIG"
  [ "$status" -eq 0 ]
  run /usr/libexec/PlistBuddy -c 'Print :EnvironmentVariables:SOMETHING_ELSE' "$PLIST"
  [ "$output" = keepme ]
  [ "$(pbread)" = 1 ]
}

@test "the plist is still valid after the edit, and a backup was written" {
  rule actioned
  bash "$MIG" >/dev/null 2>&1
  run plutil -lint "$PLIST"
  [ "$status" -eq 0 ]
  [ "$(count_backups)" -ge 1 ]
}

# ── THE HEADER CONTRACT (migrations/README.md) ──────────────────────────────────────────────────

@test "it declares class c10 and carries the four header fields the contract requires" {
  run grep -c '^# migration-class: c10$' "$MIG"
  [ "$output" = 1 ]
  for f in migration-step migration-run migration-verify migration-subject; do
    grep -q "^# $f: " "$MIG" || { echo "missing $f"; false; }
  done
}

@test "migration-verify reads FALSE before the grant and TRUE after it (an oracle that can do both)" {
  V="$(sed -n 's/^# migration-verify: //p' "$MIG")"
  run bash -c "$V"
  [ "$status" -ne 0 ]                     # not yet granted
  rule actioned; bash "$MIG" >/dev/null 2>&1
  run bash -c "$V"
  [ "$status" -eq 0 ]                     # now live in the enforcing store
}

# ── REMOVE HALVES ───────────────────────────────────────────────────────────────────────────────

@test "REMOVE: with the ruling gate deleted, an OPEN packet is acted on (the refusal is real)" {
  rule open
  local m; m="$(mutant 's/^    open)$/    open) : ;;\n    never-matches)/')"
  run bash "$m"
  [ "$status" -eq 0 ]
  [ "$(pbread)" = 1 ]                     # the mutant grants what the subject refuses
}

# WHAT THIS MUTANT ACTUALLY MEASURED, recorded rather than tuned away. The first version of this
# case asserted the mutant would CLOBBER an existing `0`, and it did not — because PlistBuddy's
# `Add` fails on a key that already exists, so the value is protected twice over and case 8 was
# passing for two reasons at once (memory: green-in-both-arms-is-an-equivalence-guard). The conflict
# guard is therefore a DIAGNOSTIC guard, not the safety barrier: what it buys is a named CONFLICT
# instead of a misleading "could not set … restoring backup", and no spurious backup file. That is
# worth keeping and is what this now pins — the honest claim, not the flattering one.
@test "REMOVE: without the conflict guard the refusal is misdiagnosed (the guard is diagnostic, not the barrier)" {
  rule actioned
  /usr/libexec/PlistBuddy -c 'Add :EnvironmentVariables dict' "$PLIST"
  /usr/libexec/PlistBuddy -c 'Add :EnvironmentVariables:CC_INSTALL_RESIDENT_RELOAD string 0' "$PLIST"

  run bash "$MIG"                          # the subject NAMES the conflict
  [ "$status" -eq 1 ]
  [[ "$output" == *"CONFLICT"* ]] || false
  before="$(count_backups)"

  local m; m="$(mutant '/^if \[ -n "\$cur" \]; then$/,/^fi$/d')"
  run bash "$m"                            # the mutant fails too, but says the wrong thing
  [ "$status" -eq 1 ]
  [[ "$output" != *"CONFLICT"* ]] || false
  after="$(count_backups)"
  [ "$after" -gt "$before" ]               # …and litters a backup the subject never makes
  [ "$(pbread)" = 0 ]                      # the VALUE is safe in both arms — PlistBuddy Add refuses
}
