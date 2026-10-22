#!/usr/bin/env bats
# Launchd jobs run their `#!` main through its own interpreter (docs/research/kalloc-longterm-2026-10-21/
# REPORT.md §3 Phase 1, row "Launchd jobs"): `scripts/hook-interp.py lint-plist` over launchd/*.plist +
# launchd/staged/*.plist through scripts/hook-shebang-lint.sh (the land-gate arm), and migration 0076
# (the installed-copy refresh + reload, c10) against a stubbed launchctl.
#
# RED-proof: every real repo plist with its interpreter prefix stripped back out is the by-path form the
# fleet had before 2026-10-22, and the same lint goes RED on it; 0076's verify exits 1 on those copies.
#
# Hermetic: $HOME is a fixture, launchctl is a stub; nothing reads or writes ~/Library/LaunchAgents.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  F="$BATS_TEST_TMPDIR/fx"
  mkdir -p "$HOME" "$F"
  PRED=(/usr/bin/env python3 "$REPO/scripts/hook-interp.py")
}

# A real repo plist with the interpreter in front of its script word taken back out.
strip_interp() { # <plist> <out>
  sed -E 's#(/bin/bash|/usr/bin/env (bash|python3)) ("?(\$HOME|~/))#\3#g' "$1" > "$2"
}

@test "lint: every repo job is clean, and the same jobs with the interpreter stripped are RED" {
  run "${PRED[@]}" lint-plist "$REPO"/launchd/*.plist "$REPO"/launchd/staged/*.plist --root "$REPO"
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=clean n=0"* ]] || false
  args=()
  for p in "$REPO"/launchd/*.plist "$REPO"/launchd/staged/*.plist; do
    strip_interp "$p" "$F/$(basename "$p")"; args+=(--file "$F/$(basename "$p")")
  done
  run /bin/bash "$REPO/scripts/hook-shebang-lint.sh" "${args[@]}"
  [ "$status" -eq 1 ]
  [[ "$output" =~ lint-plist:\ verdict=RED\ n=([0-9]+) ]] || false
  [ "${BASH_REMATCH[1]}" -ge 40 ]
  [[ "$output" == *'com.claude.capacity-alarm.plist: ProgramArguments[2] -c execs "$HOME/.claude/scripts/capacity-alarm.sh"'* ]] || false
  [[ "$output" == *'com.claude.accounts-local.plist: ProgramArguments[2] -c execs "$HOME/.claude/bin/claude-accounts"'* ]] || false
}

@test "lint: the default scope reaches the plists, the selftest passes, an unreadable plist is no verdict" {
  run /bin/bash "$REPO/scripts/hook-shebang-lint.sh" --print-scope
  [[ "$output" == *"launchd/staged/com.claude.relogin.plist"* ]] || false
  run /bin/bash "$REPO/scripts/hook-shebang-lint.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"lint-plist: verdict=clean"* ]] || false
  run /bin/bash "$REPO/scripts/hook-shebang-lint.sh" --selftest
  [ "$status" -eq 0 ]
  run /bin/bash "$REPO/scripts/hook-shebang-lint.sh" --file "$F/nope.plist"
  [ "$status" -eq 2 ]
}

# launchctl, stubbed: a job is loaded while $LCS/<label>.plist (its bytes at bootstrap) exists;
# <label>.state holds its `state =` line. Every call is appended to $LCS/log.
lc_stub() {
  LCS="$BATS_TEST_TMPDIR/lc"; mkdir -p "$LCS"; export LCS
  printf '%s\n' '#!/bin/bash' 'printf "%s\n" "$*" >> "$LCS/log"' 'l="${2##*/}"' 'case "$1" in' \
    '  print) [ -f "$LCS/$l.plist" ] || exit 113' \
    '         printf "%s = {\n\tstate = %s\n\targuments = {\n" "$2" "$(cat "$LCS/$l.state" 2>/dev/null || echo "not running")"' \
    '         plutil -extract ProgramArguments json -o - "$LCS/$l.plist" | jq -r ".[] | \"\t\t\" + ."' \
    '         printf "\t}\n}\n" ;;' \
    '  bootout) [ -f "$LCS/$l.plist" ] || exit 3; rm -f "$LCS/$l.plist" ;;' \
    '  bootstrap) cp "$3" "$LCS/$(basename "$3")" ;;' \
    '  *) exit 64 ;;' 'esac' > "$LCS/launchctl"
  chmod +x "$LCS/launchctl"
}

m0076() { CC_MIGRATION_REPO="$REPO" CC_0076_LAUNCHCTL="$LCS/launchctl" CC_0076_WAIT_S=0 CC_0076_POLL_S=1 \
            CC_SENTINEL_FROZEN_DB="$F/frozen.tsv" /bin/bash "$REPO/migrations/0076-launchd-explicit-interpreter.sh" "$@"; }

installed() { # <repo-relative plist> <loaded|idle> — a by-path copy installed, optionally loaded
  local la="$HOME/Library/LaunchAgents" b; b="$(basename "$1")"
  mkdir -p "$la"; strip_interp "$REPO/$1" "$la/$b"
  if [ "$2" = loaded ]; then cp "$la/$b" "$LCS/$b"; fi
}

@test "0076: verify is RED before; dry run and a bare run change nothing" {
  lc_stub
  installed launchd/com.claude.capacity-alarm.plist loaded
  installed launchd/staged/com.claude.relogin.plist idle
  cp -R "$HOME/Library/LaunchAgents" "$F/before"
  run m0076 --verify
  [ "$status" -eq 1 ]
  [[ "$output" == *"com.claude.capacity-alarm.plist still execs"* ]] || false
  for a in --dry-run ""; do
    run m0076 ${a:+"$a"}
    [ "$status" -eq 0 ]
    [[ "$output" == *"then reload com.claude.capacity-alarm"* ]] || false
    [[ "$output" == *"com.claude.relogin is not loaded: no reload"* ]] || false
  done
  diff -r "$F/before" "$HOME/Library/LaunchAgents"
  ! grep -qE '^(bootout|bootstrap)' "$LCS/log" || false
}

@test "0076: --confirm refreshes each installed copy once, reloads only loaded jobs, then is a no-op" {
  lc_stub
  installed launchd/com.claude.capacity-alarm.plist loaded
  installed launchd/staged/com.claude.accounts-local.plist loaded
  installed launchd/staged/com.claude.chime-player.plist loaded       # KeepAlive: bounced, not waited on
  installed launchd/staged/com.claude.relogin.plist idle              # staged and unloaded: never bootstrapped
  echo running > "$LCS/com.claude.chime-player.state"
  run m0076 --confirm launchd
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c '^0076: installed ')" -eq 4 ]
  [ "$(printf '%s\n' "$output" | grep -c ' reloaded; launchd now holds')" -eq 3 ]
  for p in launchd/com.claude.capacity-alarm.plist launchd/staged/com.claude.accounts-local.plist \
           launchd/staged/com.claude.chime-player.plist launchd/staged/com.claude.relogin.plist; do
    cmp -s "$REPO/$p" "$HOME/Library/LaunchAgents/$(basename "$p")"
  done
  ! grep -qE '^(bootout|bootstrap).*relogin' "$LCS/log" || false
  [ "$(ls "$HOME/Library/LaunchAgents/"*.bak-0076-* | wc -l | tr -d ' ')" -eq 4 ]
  run m0076 --verify
  [ "$status" -eq 0 ]
  cp "$LCS/log" "$F/log1"
  run m0076 --confirm launchd
  [ "$status" -eq 0 ]
  [[ "$output" == *"already applied"* ]] || false
  ! diff "$F/log1" "$LCS/log" | grep -qE '^> (bootout|bootstrap)' || false
}

@test "0076: a running tick and the sentinel's SIGCONT debt each stop the reload, with nothing reloaded" {
  lc_stub
  installed launchd/com.claude.capacity-alarm.plist loaded
  echo running > "$LCS/com.claude.capacity-alarm.state"
  run m0076 --confirm launchd
  [ "$status" -eq 75 ]
  [[ "$output" == *"busy: re-run — com.claude.capacity-alarm"* ]] || false
  rm -f "$LCS/com.claude.capacity-alarm.state" "$LCS/com.claude.capacity-alarm.plist"
  installed launchd/com.claude.compressor-sentinel.plist loaded
  printf '123\tx\n' > "$F/frozen.tsv"
  run m0076 --confirm launchd
  [ "$status" -eq 75 ]
  [[ "$output" == *"vetoed: re-run — com.claude.compressor-sentinel"* ]] || false
  ! grep -qE '^(bootout|bootstrap)' "$LCS/log" || false
}
