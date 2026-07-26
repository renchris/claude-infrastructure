#!/usr/bin/env bats
# cc-close-attrib — the session close-attribution exec-wrapper + its join in the crash
# watchdog. The wrapper runs the real binary unchanged, tees stderr to a per-run capture,
# and writes ~/.claude/logs/close-records/<pid>-<epoch>.json carrying the REAL exit_code/
# signal; the watchdog then turns that record into an attributed cause (clean-exit vs
# killed-oom-or-force vs binary-crash vs error-exit) instead of "abrupt-unknown".
#
# Coverage: (i) exit-code + argv passthrough · (ii) exit_code/signal record fields (0, 1,
# 139-via-SIGSEGV) · (iii) stderr reaches the caller's fd2 AND the tail is captured ·
# (iv) secret-bearing lines stripped from the tail · (v) unwritable records dir fails open
# (session runs, exit code preserved, no crash) · (vi) watchdog joins a fixture close-record
# → enrichment fields + clean-exit/binary-crash classification, outranks jetsam, no-record
# falls through to existing behavior.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  WRAP="$REPO/bin/cc-close-attrib"
  HOOK="$REPO/hooks/lead-crash-watchdog.sh"
  export CC_CLOSE_RECORDS_DIR="$BATS_TEST_TMPDIR/close-records"
  # sandbox the watchdog's account roots so --classify never touches live transcripts
  export CC_ACCOUNT_BASES="$BATS_TEST_TMPDIR/acct"
  mkdir -p "$CC_ACCOUNT_BASES/projects/proj"
}

# executable stub that early-exits on `--version` (so the wrapper's cached version probe
# never triggers the stub's real body), then runs the given body lines.
mk_stub() { # $1=path  $2...=body lines
  local p="$1"; shift
  { printf '#!/bin/bash\n[[ "$1" == "--version" ]] && { echo "stub 9.9.9"; exit 0; }\n'
    printf '%s\n' "$@"
  } > "$p"
  chmod +x "$p"
}

# newest close-record in the sandbox
rec() { ls -1t "$CC_CLOSE_RECORDS_DIR"/*.json 2>/dev/null | head -1; }

# ── (i) passthrough ───────────────────────────────────────────────────────────────────────
@test "wrapper passes the exit code and argv through to the stub" {
  local stub="$BATS_TEST_TMPDIR/stub"
  mk_stub "$stub" 'printf "%s\n" "$@" > "'"$BATS_TEST_TMPDIR"'/seen"' 'exit 33'
  run bash "$WRAP" "$stub" alpha beta
  [ "$status" -eq 33 ]                                  # exit code preserved
  grep -qx alpha "$BATS_TEST_TMPDIR/seen"              # stub actually received the args
  grep -qx beta  "$BATS_TEST_TMPDIR/seen"
  grep -q ',"alpha","beta"\]' "$(rec)"                 # argv[first 3] recorded
}

# ── (ii) exit_code / signal record fields ───────────────────────────────────────────────────
@test "record carries exit_code/signal for clean, error, and SIGSEGV exits" {
  local s0="$BATS_TEST_TMPDIR/s0" s1="$BATS_TEST_TMPDIR/s1" s9="$BATS_TEST_TMPDIR/s9"
  mk_stub "$s0" 'exit 0'
  mk_stub "$s1" 'exit 1'
  mk_stub "$s9" 'kill -SEGV $$'

  run bash "$WRAP" "$s0"
  [ "$status" -eq 0 ]
  grep -q '"exit_code":0,' "$(rec)"
  grep -q '"signal":"",'   "$(rec)"

  run bash "$WRAP" "$s1"
  [ "$status" -eq 1 ]
  grep -q '"exit_code":1,' "$(rec)"

  run bash "$WRAP" "$s9"
  [ "$status" -eq 139 ]
  grep -q '"exit_code":139,' "$(rec)"
  grep -q '"signal":"11",'   "$(rec)"                  # 139 = 128 + SIGSEGV(11)
}

# ── (iii) stderr passthrough AND capture ────────────────────────────────────────────────────
@test "stderr still reaches the caller's fd2 while the tail is captured" {
  local stub="$BATS_TEST_TMPDIR/stub"
  mk_stub "$stub" 'echo "to-stdout"' 'echo "to-stderr-line" >&2' 'exit 0'
  bash "$WRAP" "$stub" >"$BATS_TEST_TMPDIR/o" 2>"$BATS_TEST_TMPDIR/e"
  grep -qx "to-stdout"      "$BATS_TEST_TMPDIR/o"      # stdout untouched
  grep -qx "to-stderr-line" "$BATS_TEST_TMPDIR/e"      # stderr reached the caller (fd2)
  grep -q  "to-stderr-line" "$(rec)"                    # AND landed in the record tail
}

# ── (iv) secret stripping ───────────────────────────────────────────────────────────────────
@test "secret-bearing stderr lines are stripped from the record tail" {
  local stub="$BATS_TEST_TMPDIR/stub"
  mk_stub "$stub" \
    'echo "normal diagnostic line" >&2' \
    'echo "authorization: Bearer abc123" >&2' \
    'echo "api_key=SUPERSECRET" >&2' \
    'echo "x-auth-token: zzz" >&2' \
    'echo "another normal line" >&2' \
    'exit 0'
  bash "$WRAP" "$stub" >/dev/null 2>/dev/null
  local r; r="$(rec)"
  grep -q "normal diagnostic line" "$r"
  grep -q "another normal line"    "$r"
  ! grep -qi "bearer"        "$r" || false
  ! grep -qi "SUPERSECRET"   "$r" || false
  ! grep -qi "authorization" "$r" || false
  ! grep -qi "token"         "$r"
}

# ── (v) fail-open on an unwritable records dir ──────────────────────────────────────────────
@test "unwritable records dir fails open: session runs, exit code preserved, no crash" {
  local ro="$BATS_TEST_TMPDIR/ro"; mkdir -p "$ro"; chmod 000 "$ro"
  export CC_CLOSE_RECORDS_DIR="$ro/nope/records"
  local stub="$BATS_TEST_TMPDIR/stub"
  mk_stub "$stub" 'echo "ran anyway"' 'exit 5'
  run bash "$WRAP" "$stub"
  chmod 755 "$ro"                                       # restore so bats teardown can clean up
  [ "$status" -eq 5 ]                                   # exit code still preserved
  printf '%s' "$output" | grep -q "ran anyway"          # session still ran
}

# ── (vi) watchdog close-record join ─────────────────────────────────────────────────────────
@test "watchdog joins a fixture close-record → clean-exit / binary-crash classification" {
  mkdir -p "$CC_CLOSE_RECORDS_DIR"
  printf '{"pid":8001,"exit_code":0,"signal":"","stderr_tail":"bye","version":"2.1.9"}\n'   > "$CC_CLOSE_RECORDS_DIR/8001-100.json"
  printf '{"pid":8002,"exit_code":139,"signal":"11","stderr_tail":"x","version":"2.1.9"}\n' > "$CC_CLOSE_RECORDS_DIR/8002-100.json"

  run bash "$HOOK" --classify sess 8001
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | cut -f1)" = "RECYCLE" ]
  [ "$(printf '%s' "$output" | cut -f2)" = "clean-exit" ]

  run bash "$HOOK" --classify sess 8002
  [ "$(printf '%s' "$output" | cut -f1)" = "CRASH" ]
  [ "$(printf '%s' "$output" | cut -f2)" = "binary-crash" ]
}

@test "watchdog --close-fields exposes exit_code/signal/path/version for the crash row" {
  mkdir -p "$CC_CLOSE_RECORDS_DIR"
  printf '{"pid":8003,"exit_code":137,"signal":"9","stderr_tail":"oom","version":"2.1.42"}\n' > "$CC_CLOSE_RECORDS_DIR/8003-100.json"
  run bash "$HOOK" --close-fields 8003
  [ "$(printf '%s' "$output" | cut -f1)" = "137" ]
  [ "$(printf '%s' "$output" | cut -f2)" = "9" ]
  printf '%s' "$output" | grep -q "8003-100.json"       # stderr_tail_path
  [ "$(printf '%s' "$output" | cut -f4)" = "2.1.42" ]
}

@test "close-record OUTRANKS the jetsam heuristic (per-pid ground truth wins)" {
  mkdir -p "$CC_CLOSE_RECORDS_DIR"
  export CC_JETSAM_DIRS="$BATS_TEST_TMPDIR/jetsam"; mkdir -p "$CC_JETSAM_DIRS"
  : > "$CC_JETSAM_DIRS/JetsamEvent-2099-01-01-000000.ips"   # a fresh jetsam event...
  printf '{"pid":8010,"exit_code":0,"signal":"","stderr_tail":"clean","version":"1.0.0"}\n' > "$CC_CLOSE_RECORDS_DIR/8010-1.json"
  run bash "$HOOK" --classify sess 8010                      # ...but this pid exited clean
  [ "$(printf '%s' "$output" | cut -f2)" = "clean-exit" ]
}

@test "no close-record for the pid ⇒ existing behavior (no forced override)" {
  run bash "$HOOK" --classify sess 9999
  [ "$(printf '%s' "$output" | cut -f1)" = "CRASH" ]
  [ "$(printf '%s' "$output" | cut -f2)" = "no-transcript" ]
}
