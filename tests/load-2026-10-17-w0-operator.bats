#!/usr/bin/env bats
# 55-load-2026-10-17-w0-operator.sh — Wave 0 of the load-root-cause program as one operator script.
#
# WHY THIS SUITE EXISTS: every W0 step is root-only and one of them restarts a system daemon, so the
# script's value is in what it REFUSES: a bare run that writes nothing and never calls sudo, a restart
# refused while fseventsd is healthy or while the Spotlight exclusion is missing, a TERM before any KILL,
# a capture refused outside its window or a second time, and no signal ever sent to a censused orphan.
#
# HERMETIC: HOME is $BATS_TEST_TMPDIR/home; every macOS tool the script calls (sudo, pgrep, ps, top,
# kill, sample, mdutil, getconf, xcrun, stat, zprint, vm_stat, ioreg, fs_usage, sysctl, PlistBuddy) is a
# stub on PATH whose state lives in $STUB, outside HOME. sudo just runs its argv, so `sudo kill` reaches
# the kill stub. Nothing reads stdin.
#
# Seam for the RED proof: W0_SCRIPT.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT="${W0_SCRIPT:-$REPO/docs/activation/pending-activation/55-load-2026-10-17-w0-operator.sh}"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/autonomy"
  STUB="$BATS_TEST_TMPDIR/stub"; mkdir -p "$STUB/bin" "$STUB/T"
  export STUB PATH="$STUB/bin:$PATH" CC_W0_SUDO=sudo CC_W0_PLISTBUDDY="$STUB/bin/PlistBuddy"
  export CC_W0_SPOT_PLIST="$STUB/VolumeConfiguration.plist" CC_W0_WAIT_S=1
  OUT="$HOME/.claude/logs/load-2026-10-17/w0"
  : > "$CC_W0_SPOT_PLIST"
  echo 500 > "$STUB/fsev_pid"; touch "$STUB/alive-500"
  echo 14M > "$STUB/mem"
  : > "$STUB/gates"
  write_stubs
}

stub() { printf '#!/bin/bash\n%s\n' "$2" > "$STUB/bin/$1"; chmod +x "$STUB/bin/$1"; }
write_stubs() {
  stub sudo 'echo "sudo $*" >> "$STUB/calls"; exec "$@"'
  stub pgrep 'case "$1 $2" in
  "-x fseventsd") cat "$STUB/fsev_pid" ;;
  -x*) exit 1 ;;
  -fl*) case "$2" in pytest*) cat "$STUB/gates" ;; *render*) cat "$STUB/orphans" 2>/dev/null ;; esac ;;
  -f*) cat "$STUB/gates" ;;
esac; exit 0'
  stub ps '[ "$1" = -p ] && [ -f "$STUB/alive-$2" ]'
  stub top 'printf "MEM\n%s\n" "$(cat "$STUB/mem")"'
  # kill: TERM is honoured unless $STUB/ignore-term; a dead daemon is respawned by "launchd" as pid 501.
  stub kill 'echo "kill $*" >> "$STUB/calls"
sig="$1"; pid="$2"
if [ "$sig" = -KILL ] || [ ! -f "$STUB/ignore-term" ]; then rm -f "$STUB/alive-$pid"; echo 501 > "$STUB/fsev_pid"; touch "$STUB/alive-501"; fi'
  stub sample 'echo "sample $*" >> "$STUB/calls"'
  stub mdutil 'echo "Indexing enabled."'
  stub getconf 'echo "$STUB/T/"'
  stub xcrun 'echo "xcrun $*" >> "$STUB/calls"; [ -f "$STUB/db-returns" ] || rm -f "$STUB/T/xcrun_db"'
  stub stat 'wc -c < "$3"'
  stub zprint 'echo "zone 1 2 3"'
  stub vm_stat 'echo pages'
  stub ioreg 'echo "\"Statistics\" = {\"Bytes (Write)\"=$RANDOM}"'
  stub fs_usage 'echo "fs_usage $*"'
  stub sysctl 'echo 263168'
  stub PlistBuddy 'case "$2" in
  "Print :Exclusions") echo "Array {"; sed "s/^/    /" "$3"; echo "}" ;;
  "Add :Exclusions: string "*) echo "${2#Add :Exclusions: string }" >> "$3" ;;
esac'
}

files() { (cd "$HOME" && find . -type f -print | LC_ALL=C sort); }
calls() { cat "$STUB/calls" 2>/dev/null; }

@test "a bare run reports every step, writes nothing and never calls sudo" {
  echo "1 node render.mjs" > "$STUB/orphans"
  before="$(files)"
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"== 1. OP-1 precondition"* ]] || false
  [[ "$output" == *"pid 500, footprint 14 MB"* ]] || false
  [[ "$output" == *"render\.mjs: 1 node render.mjs"* ]] || false
  [[ "$output" == *"kern.maxvnodes now 263168; NOT run here"* ]] || false
  [ "$(files)" = "$before" ]
  [ -z "$(calls)" ]
}

@test "arguments are validated before anything runs" {
  run "$SCRIPT" --confirm bogus
  [ "$status" -eq 2 ]
  run "$SCRIPT" --confirm wired-capture
  [ "$status" -eq 2 ]
  [[ "$output" == *"need --window"* ]] || false
  run "$SCRIPT" --confirm xcrun-cache --window noon
  [ "$status" -eq 2 ]
  run "$SCRIPT" --confirm
  [ "$status" -eq 2 ]
  [ -z "$(calls)" ]
  [ ! -d "$OUT" ]
}

@test "fseventsd-restart is refused while the daemon is healthy" {
  echo "$HOME/Development" > "$CC_W0_SPOT_PLIST"
  run "$SCRIPT" --confirm fseventsd-restart
  [ "$status" -eq 1 ]
  [[ "$output" == *"14 MB is not wedged"* ]] || false
  [ "$(calls | grep -c '^kill')" -eq 0 ]
}

@test "fseventsd-restart is refused when wedged but Spotlight would rescan Development" {
  echo 11G > "$STUB/mem"
  run "$SCRIPT" --confirm fseventsd-restart
  [ "$status" -eq 1 ]
  [[ "$output" == *"not in Spotlight Exclusions"* ]] || false
  [ "$(calls | grep -c '^kill')" -eq 0 ]
}

@test "a wedged daemon gets mds recorded, a sample, TERM, and a verified new pid — no KILL" {
  echo 11G > "$STUB/mem"; echo "$HOME/Development" > "$CC_W0_SPOT_PLIST"
  run "$SCRIPT" --confirm fseventsd-restart
  [ "$status" -eq 0 ]
  [[ "$output" == *"VERIFIED: fseventsd 500 → 501"* ]] || false
  calls | grep -qx 'kill -TERM 500'
  [ "$(calls | grep -c 'kill -KILL')" -eq 0 ]
  calls | grep -q '^sample 500 5 -file '
  compgen -G "$OUT/*-mds.txt" >/dev/null
}

@test "a daemon that ignores TERM for WAIT_S gets KILL, then the new pid is required" {
  echo 11G > "$STUB/mem"; echo "$HOME/Development" > "$CC_W0_SPOT_PLIST"; touch "$STUB/ignore-term"
  run "$SCRIPT" --confirm fseventsd-restart
  [ "$status" -eq 0 ]
  [ "$(calls | grep '^kill' | tr '\n' '|')" = "kill -TERM 500|kill -KILL 500|" ]
  [[ "$output" == *"VERIFIED: fseventsd 500 → 501"* ]]
}

@test "spotlight-privacy backs the plist up, adds the entry, reads it back, and is idempotent" {
  run "$SCRIPT" --confirm spotlight-privacy
  [ "$status" -eq 0 ]
  [[ "$output" == *"VERIFIED: $HOME/Development is in Exclusions"* ]] || false
  compgen -G "$OUT/*-VolumeConfiguration.plist.bak" >/dev/null
  run "$SCRIPT" --confirm spotlight-privacy
  [ "$status" -eq 0 ]
  [[ "$output" == *"already excluded"* ]] || false
  [ "$(grep -c . "$CC_W0_SPOT_PLIST")" -eq 1 ]
}

@test "xcrun-cache removes only stale temp files and records the cleanup" {
  echo db > "$STUB/T/xcrun_db"; echo x > "$STUB/T/xcrun_db-old"; echo y > "$STUB/T/xcrun_db-new"
  echo z > "$STUB/T/other-old"
  touch -d '2 hours ago' "$STUB/T/xcrun_db-old" "$STUB/T/other-old"
  run "$SCRIPT" --confirm xcrun-cache
  [ "$status" -eq 0 ]
  [ ! -e "$STUB/T/xcrun_db-old" ]
  [ -e "$STUB/T/xcrun_db-new" ]
  [ -e "$STUB/T/other-old" ]
  [ -f "$OUT/xcrun-cache.cleaned" ]
}

@test "xcrun-cache refuses when the db is restored by a concurrent rename" {
  echo db > "$STUB/T/xcrun_db"; touch "$STUB/db-returns"
  run "$SCRIPT" --confirm xcrun-cache
  [ "$status" -eq 1 ]
  [[ "$output" == *"xcrun_db is back"* ]] || false
  [ ! -f "$OUT/xcrun-cache.cleaned" ]
}

@test "captures are refused outside their window and a second time" {
  echo "11 pytest -n 4" > "$STUB/gates"
  run "$SCRIPT" --confirm wired-capture --window peak
  [ "$status" -eq 1 ]
  [[ "$output" == *"needs >= 2 gates running (have 1)"* ]] || false
  run "$SCRIPT" --confirm fsusage-capture --window idle
  [ "$status" -eq 1 ]
  : > "$STUB/gates"
  run "$SCRIPT" --confirm wired-capture --confirm fsusage-capture --window idle
  [ "$status" -eq 0 ]
  compgen -G "$OUT/*-idle-wired-zprint.txt" >/dev/null
  compgen -G "$OUT/*-idle-fsusage-B-diskio.txt" >/dev/null
  grep -q 'fs_usage -w -f filesys -t 10' "$OUT"/*-idle-fsusage-A-filesys.txt
  run "$SCRIPT" --confirm wired-capture --window idle
  [ "$status" -eq 1 ]
  [[ "$output" == *"already captured"* ]]
}

@test "the .done marker needs a healthy daemon, the xcrun record and all four captures" {
  DONE="$HOME/.claude/autonomy/pending-activation/55-load-2026-10-17-w0-operator.sh.done"
  run "$SCRIPT" --confirm wired-capture --confirm fsusage-capture --window idle
  printf '1 pytest\n2 pytest\n' > "$STUB/gates"
  run "$SCRIPT" --confirm wired-capture --confirm fsusage-capture --window peak
  [ "$status" -eq 0 ]
  [ ! -e "$DONE" ]
  run "$SCRIPT" --confirm xcrun-cache
  [ "$status" -eq 0 ]
  [ -e "$DONE" ]
  rm "$DONE"; echo 2G > "$STUB/mem"
  run "$SCRIPT"
  [ ! -e "$DONE" ]
}
