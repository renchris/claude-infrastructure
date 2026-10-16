#!/usr/bin/env bats
# bin/cc-dia-js status — which Dia process is the operator's, and is the JS launch flag on it.
# Every case drives stubbed ps/pgrep through DIA_JS_PS / DIA_JS_PGREP; setup refuses to run a
# case without both, so no result here depends on whether the real Dia is running.

setup() {
  REPO="${CC_REDPROOF_TREE:-$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)}"
  SUT="$REPO/bin/cc-dia-js"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  STUB="$BATS_TEST_TMPDIR/stub"
  mkdir -p "$STUB"
  EXE=/Applications/Dia.app/Contents/MacOS/Dia
  # pgrep stub: prints the pids listed in $STUB/pids (none ⇒ exit 1, as pgrep does).
  printf '%s\n' '#!/bin/bash' \
    '[ -s "'"$STUB"'/pids" ] || exit 1' \
    'cat "'"$STUB"'/pids"' > "$STUB/pgrep"
  # ps stub: answers -o command= / ucomm= / lstart= / etime= for -p <pid> from $STUB/<field>.<pid>.
  printf '%s\n' '#!/bin/bash' \
    'field=""; pid=""' \
    'while [ $# -gt 0 ]; do case "$1" in -o) field=${2%=}; shift ;; -p) pid=$2; shift ;; esac; shift; done' \
    'f="'"$STUB"'/$field.$pid"' \
    '[ -f "$f" ] || exit 1' \
    'cat "$f"' > "$STUB/ps"
  chmod +x "$STUB/pgrep" "$STUB/ps"
  export DIA_JS_PS="$STUB/ps" DIA_JS_PGREP="$STUB/pgrep"
  [ -n "${DIA_JS_PS:-}" ] && [ -n "${DIA_JS_PGREP:-}" ] || return 1
}

# dia PID COMMAND [UCOMM] [ETIME] — register one stub process.
dia() {
  printf '%s\n' "$1" >> "$STUB/pids"
  printf '%s\n' "$2" > "$STUB/command.$1"
  printf '%s\n' "${3:-Dia}" > "$STUB/ucomm.$1"
  printf '%s\n' "Thu Oct 15 21:38:19 2026" > "$STUB/lstart.$1"
  printf '%s\n' "${4:-01:00}" > "$STUB/etime.$1"
}

@test "no Dia process: NOT_RUNNING; exit 0, or 2 under --rc" {
  run "$SUT" status
  [ "$status" -eq 0 ]
  [[ "$output" == "DIA_JS=NOT_RUNNING "* ]] || false
  run "$SUT" status --rc
  [ "$status" -eq 2 ]
}

@test "personal Dia without the flag: OFF; exit 0, or 1 under --rc" {
  dia 41919 "$EXE"
  run "$SUT" status
  [ "$status" -eq 0 ]
  [[ "$output" == "DIA_JS=OFF pid=41919 since=Thu_Oct_15_21:38:19_2026 age=60 "* ]] || false
  run "$SUT" status --rc
  [ "$status" -eq 1 ]
}

@test "personal Dia with the flag: ON; exit 0 under --rc" {
  dia 41919 "$EXE --enable-applescript-javascript"
  run "$SUT" status --rc
  [ "$status" -eq 0 ]
  [[ "$output" == "DIA_JS=ON pid=41919 "*"reason=flag in argv" ]]
}

@test "a lookalike flag is not the flag: OFF" {
  dia 41919 "$EXE --enable-applescript-javascript-x"
  run "$SUT" status --rc
  [ "$status" -eq 1 ]
  [[ "$output" == "DIA_JS=OFF "* ]]
}

@test "an ON older than the stale bound says so" {
  dia 41919 "$EXE --enable-applescript-javascript" Dia "1-02:00:00"
  run "$SUT" status --rc
  [ "$status" -eq 0 ]
  [[ "$output" == *"age=93600 reason=stale"* ]]
}

@test "only the clean-profile launcher's instance: UNKNOWN, never OFF" {
  dia 500 "$EXE --user-data-dir=/x/Dia-Agent --remote-debugging-port=9222"
  run "$SUT" status
  [ "$status" -eq 3 ]
  [[ "$output" == "DIA_JS=UNKNOWN "* ]]
}

@test "launcher plus personal Dia: the personal one is read" {
  dia 500 "$EXE --user-data-dir=/x/Dia-Agent --enable-applescript-javascript"
  dia 41919 "$EXE"
  run "$SUT" status --rc
  [ "$status" -eq 1 ]
  [[ "$output" == "DIA_JS=OFF pid=41919 "* ]]
}

@test "a Dia-named process at another path: UNKNOWN" {
  dia 41919 "/tmp/Dia --enable-applescript-javascript"
  run "$SUT" status --rc
  [ "$status" -eq 3 ]
}

@test "two personal-looking processes: UNKNOWN" {
  dia 41919 "$EXE"
  dia 41920 "$EXE --enable-applescript-javascript"
  run "$SUT" status --rc
  [ "$status" -eq 3 ]
  [[ "$output" == *"more than one"* ]]
}

@test "ucomm other than Dia: UNKNOWN" {
  dia 41919 "$EXE" "Dia Helper"
  run "$SUT" status
  [ "$status" -eq 3 ]
}

@test "bad arguments: usage, exit 64" {
  run "$SUT"
  [ "$status" -eq 64 ]
  run "$SUT" status --bogus
  [ "$status" -eq 64 ]
}
