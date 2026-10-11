#!/usr/bin/env bats
# lr-lib.sh lr_registry_live_rows — ONE jq FOR THE WHOLE REGISTRY (lr-reliability-telemetry-speed
# 2026-10-10, wave C: report D7, ranked row 11).
#
# The function used to fork basename plus up to five jq per registry file per call (1.19 s a call at
# load ~848, 26 call sites). It now reads every file in one jq and falls back to the per-file loop on
# any non-zero jq exit. Two claims are pinned here:
#   1. ONE jq per call on a canonical registry (red on trunk, which forks jq once per file and more).
#   2. BYTE-IDENTICAL output and rc against the loop exactly as it stood at 110ea9a64 — read from git,
#      never retyped — on canonical rows, a malformed file, a two-value file, a non-scalar cell and
#      an empty directory.

TRUNK=110ea9a64

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd -P)"
  LIB="$REPO/scripts/limit-recover/lr-lib.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export LR_LIB_DIR="$REPO/scripts/limit-recover"
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg"; mkdir -p "$CC_REGISTRY_DIR"
  # shellcheck source=../scripts/limit-recover/lr-lib.sh
  . "$LIB"
  SID="0000cccc-0000-4000-8000-00000000c3c3"
  sleep 300 & LIVE=$!
  sh -c 'exit 0' & DEAD=$!; wait "$DEAD" 2>/dev/null || true
  # A jq that counts its own invocations, then runs the real one.
  REAL_JQ="$(command -v jq)"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  export JQ_LOG="$BATS_TEST_TMPDIR/jq.log"; : > "$JQ_LOG"
  printf '#!/bin/bash\necho x >> "$JQ_LOG"\nexec %q "$@"\n' "$REAL_JQ" > "$BATS_TEST_TMPDIR/bin/jq"
  chmod +x "$BATS_TEST_TMPDIR/bin/jq"
}
teardown() { kill "$LIVE" 2>/dev/null || true; }

# The reference: the function body at $TRUNK, renamed. Skipped (never passed) when git cannot read it.
load_ref() {
  local src
  src="$(git -C "$REPO" show "$TRUNK:scripts/limit-recover/lr-lib.sh" 2>/dev/null)" || skip "git cannot read $TRUNK"
  src="$(printf '%s\n' "$src" | sed -n '/^lr_registry_live_rows() {/,/^}/p')"
  [ -n "$src" ] || skip "no lr_registry_live_rows at $TRUNK"
  eval "${src/lr_registry_live_rows()/ref_rows()}"
}
reg() { printf '%s\n' "$2" > "$CC_REGISTRY_DIR/$1"; }
canonical() {
  reg 11.json  "{\"session_id\":\"$SID\",\"pid\":$LIVE,\"paneUUID\":\"P-11\",\"account\":\"claude-next\",\"cwd\":\"/w/a b\"}"
  reg 12.json  "{\"session_id\":\"$SID\",\"pid\":$LIVE,\"cwd\":\"/w/no-acct-no-pane\"}"
  reg 13.json  "{\"sessionId\":\"$SID\",\"pid\":\"$LIVE\",\"account\":\"\",\"cwd\":\"\"}"
  reg 14.json  "{\"session_id\":\"$SID\",\"pid\":$DEAD,\"paneUUID\":\"P-dead\",\"account\":\"x\",\"cwd\":\"/w\"}"
  reg 15.json  "{\"session_id\":\"$SID\",\"pid\":\"12ab\",\"cwd\":\"/w\"}"
  reg 16.json  "{\"session_id\":\"other\",\"pid\":$LIVE,\"cwd\":\"/w\"}"
  reg 17.json  "{\"session_id\":false,\"sessionId\":\"$SID\",\"pid\":$LIVE,\"paneUUID\":null,\"cwd\":\"/w/false\"}"
  reg 18.json  'null'
  reg .hid.json "{\"session_id\":\"$SID\",\"pid\":$LIVE,\"cwd\":\"/w/hidden\"}"
  : > "$CC_REGISTRY_DIR/19.json"
  mkdir -p "$CC_REGISTRY_DIR/dir.json"
}
# new and ref agree on stdout AND rc
same() {
  run lr_registry_live_rows "$SID"; local o1="$output" s1="$status"
  run ref_rows "$SID";              local o2="$output" s2="$status"
  [ "$s1" = "$s2" ] || { echo "rc new=$s1 ref=$s2"; false; }
  [ "$o1" = "$o2" ] || { printf 'NEW:\n%s\nREF:\n%s\n' "$o1" "$o2"; false; }
}

@test "one jq: a canonical registry of 10 files is read by exactly ONE jq, not one per file" {
  canonical
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run lr_registry_live_rows "$SID"
  [ "$status" -eq 0 ] || { echo "status=$status $output"; false; }
  [ "$(wc -l < "$JQ_LOG" | tr -d ' ')" -eq 1 ] || { echo "jq ran $(wc -l < "$JQ_LOG") times"; false; }
  # and the rows are the live, matching ones, in glob order, padded
  [ "$output" = "$(printf 'P-11\t%s\tclaude-next\t/w/a b\n12\t%s\t-\t/w/no-acct-no-pane\n13\t%s\t-\t\n17\t%s\t-\t/w/false' "$LIVE" "$LIVE" "$LIVE" "$LIVE")" ] \
    || { printf '%s\n' "$output" | cat -A 2>/dev/null || printf '%s\n' "$output"; false; }
}
@test "differential: canonical registry — byte-identical to the 110ea9a64 loop" {
  load_ref; canonical; same
}
@test "differential: a malformed file falls back — byte-identical, and the loop really ran" {
  load_ref; canonical
  reg 10.json '{"session_id":"'"$SID"'","pid":'"$LIVE"',"cwd":"/w/torn"'
  same
  : > "$JQ_LOG"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run lr_registry_live_rows "$SID"
  [ "$(wc -l < "$JQ_LOG" | tr -d ' ')" -gt 1 ] || { echo "no fallback: jq ran $(wc -l < "$JQ_LOG") time(s)"; false; }
}
@test "differential: two JSON values in one file — byte-identical (the loop never matches it)" {
  load_ref; canonical
  printf '{"session_id":"%s","pid":%s,"cwd":"/w/1"}\n{"session_id":"%s","pid":%s,"cwd":"/w/2"}\n' \
    "$SID" "$LIVE" "$SID" "$LIVE" > "$CC_REGISTRY_DIR/20.json"
  same
}
@test "differential: an object-valued cell and a newline in a cell — byte-identical" {
  load_ref; canonical
  reg 21.json "{\"session_id\":\"$SID\",\"pid\":$LIVE,\"cwd\":{\"p\":1}}"
  reg 22.json "{\"session_id\":\"$SID\",\"pid\":$LIVE,\"cwd\":\"/w/trailing\\n\"}"
  same
}
@test "differential: an empty registry dir, and one holding only non-files — both rc 1, no output" {
  load_ref
  same
  [ "$status" -eq 1 ] && [ -z "$output" ] || false
  mkdir -p "$CC_REGISTRY_DIR/only.json"
  same
  [ "$status" -eq 1 ]
}
