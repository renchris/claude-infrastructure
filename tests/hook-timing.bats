#!/usr/bin/env bats
# hook-timing.bats — hooks/lib/hook-timing.sh: per-hook start/end stamps for the UserPromptSubmit
# hooks (README §5 Wave 7, A9-F9). The prompt path forks nothing (file mtimes are the clock); the
# fold, which runs in session-beat's detached worker, turns pairs into ledger rows exactly once, and a
# hook that never reached its EXIT trap folds as "killed". Fixtures only: HOME and every dir are temp.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  LIB="$REPO/hooks/lib/hook-timing.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_HOOK_TIMING=on
  export CC_HOOK_TIMING_DIR="$BATS_TEST_TMPDIR/ht"
  export CC_HOOK_TIMING_LEDGER="$BATS_TEST_TMPDIR/hook-timing.jsonl"
  FX="$BATS_TEST_TMPDIR/fx.sh"
  printf '%s\n' '#!/bin/bash' 'set -uo pipefail' ". '$LIB' && ht_begin fx-hook" \
    'HT_SID=abc-1' '[ "${FX_SLEEP:-0}" = 0 ] || sleep "$FX_SLEEP"' 'exit "${FX_RC:-0}"' > "$FX"
  chmod +x "$FX"
}

nfiles() { # <glob under the stamp dir> → how many files match
  local n=0 f
  for f in "$CC_HOOK_TIMING_DIR"/$1; do [ -e "$f" ] && n=$((n + 1)); done
  echo "$n"
}

fold() { /bin/bash -c "set -uo pipefail; . '$REPO/hooks/lib/hook-timing-fold.sh'; ht_fold"; }

@test "a run leaves one start and one end stamp, and the fold turns them into one timed row" {
  FX_SLEEP=1 FX_RC=3 run /bin/bash "$FX"
  [ "$status" -eq 3 ]
  [ "$(nfiles 'fx-hook.*.s')" -eq 1 ]
  [ "$(nfiles 'fx-hook.*.e')" -eq 1 ]
  run fold
  [ "$status" -eq 0 ]
  [ "$(grep -c . "$CC_HOOK_TIMING_LEDGER")" -eq 1 ]
  jq -e 'select(.hook=="fx-hook" and .sid=="abc-1" and .disposition=="timed" and .reason=="UserPromptSubmit"
                and .rc==3 and .ms>=900 and .ms<60000 and (.t0|type)=="number" and (.ts|test("^[0-9-]+T")))' \
    "$CC_HOOK_TIMING_LEDGER" >/dev/null
  [ -z "$(ls -A "$CC_HOOK_TIMING_DIR")" ]
  run fold
  [ "$(grep -c . "$CC_HOOK_TIMING_LEDGER")" -eq 1 ]
}

@test "the clock is /bin/bash 3.2's file mtime (clock=mtime), and \$EPOCHREALTIME under bash 5 (clock=rt)" {
  /bin/bash "$FX"
  fold
  jq -e 'select(.clock=="mtime")' "$CC_HOOK_TIMING_LEDGER" >/dev/null
  b5=/opt/homebrew/bin/bash
  [ -x "$b5" ] || skip "no bash 5 at $b5"
  : > "$CC_HOOK_TIMING_LEDGER"
  "$b5" "$FX"
  fold
  jq -e 'select(.clock=="rt" and .ms>=0)' "$CC_HOOK_TIMING_LEDGER" >/dev/null
}

@test "the prompt path runs no external command once the stamp directory exists" {
  stub="$BATS_TEST_TMPDIR/stub"; mkdir -p "$stub" "$CC_HOOK_TIMING_DIR"
  for c in mkdir date stat rm mv cat sleep jq; do
    printf '#!/bin/bash\necho %s >> "%s"\nexit 0\n' "$c" "$BATS_TEST_TMPDIR/forks" > "$stub/$c"
    chmod +x "$stub/$c"
  done
  : > "$BATS_TEST_TMPDIR/forks"
  PATH="$stub" /bin/bash "$FX"
  [ ! -s "$BATS_TEST_TMPDIR/forks" ]
  [ "$(nfiles '*.e')" -eq 1 ]
}

@test "a hook whose process is gone without an end stamp folds as killed, with the age it reached" {
  mkdir -p "$CC_HOOK_TIMING_DIR"
  printf 'UserPromptSubmit \n' > "$CC_HOOK_TIMING_DIR/slow-hook.99999999.s"
  run fold
  jq -e 'select(.hook=="slow-hook" and .disposition=="killed" and .rc==null and .ms>=0 and .sid=="?")' \
    "$CC_HOOK_TIMING_LEDGER" >/dev/null
  [ ! -e "$CC_HOOK_TIMING_DIR/slow-hook.99999999.s" ]
}

@test "a hook still running is left alone until it ends" {
  mkdir -p "$CC_HOOK_TIMING_DIR"
  printf 'UserPromptSubmit \n' > "$CC_HOOK_TIMING_DIR/busy-hook.$$.s"
  run fold
  [ ! -s "$CC_HOOK_TIMING_LEDGER" ]
  [ -e "$CC_HOOK_TIMING_DIR/busy-hook.$$.s" ]
  printf '0  \n' > "$CC_HOOK_TIMING_DIR/busy-hook.$$.e"
  run fold
  jq -e 'select(.hook=="busy-hook" and .disposition=="timed" and .rc==0)' "$CC_HOOK_TIMING_LEDGER" >/dev/null
}

@test "two folds at once write each row exactly once" {
  for i in 1 2 3 4 5 6; do /bin/bash "$FX"; done
  fold & fold & fold &
  wait
  [ "$(grep -c . "$CC_HOOK_TIMING_LEDGER")" -eq 6 ]
  [ -z "$(ls -A "$CC_HOOK_TIMING_DIR")" ]
}

@test "the ledger keeps one older generation past its byte cap" {
  /bin/bash "$FX"; fold
  /bin/bash "$FX"; CC_HOOK_TIMING_MAX_BYTES=10 fold
  [ "$(grep -c . "$CC_HOOK_TIMING_LEDGER.1")" -eq 1 ]
  [ "$(grep -c . "$CC_HOOK_TIMING_LEDGER")" -eq 1 ]
}

@test "default: under bats with CC_HOOK_TIMING unset nothing is stamped" {
  unset CC_HOOK_TIMING
  /bin/bash "$FX"
  [ ! -e "$CC_HOOK_TIMING_DIR" ]
}

@test "all seven UserPromptSubmit hooks stamp, and session-beat's worker folds them into rows" {
  export CC_STARTUP_HEALTH_DIR="$BATS_TEST_TMPDIR/no-sh" CC_HOOK_DEADLINE_DIR="$BATS_TEST_TMPDIR/hd"
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mailbox" CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  in='{"session_id":"abc-1","hook_event_name":"UserPromptSubmit","cwd":"/tmp","prompt":"hello there"}'
  for h in handed-off-session-guard cache-expiry-warning memory-nudge handoff-intent-nudge \
           research-precognition-nudge; do
    printf '%s' "$in" | "$REPO/hooks/$h.sh" >/dev/null 2>&1 || true
  done
  printf '%s' "$in" | "$REPO/hooks/mailbox-drain.sh" prompt >/dev/null 2>&1 || true
  printf '%s' "$in" | "$REPO/hooks/session-beat.sh" prompt >/dev/null 2>&1 || true
  # The first beat's worker folds the six; a second beat folds the first beat's own stamp.
  i=0; until [ "$(jq -r .hook "$CC_HOOK_TIMING_LEDGER" 2>/dev/null | sort -u | grep -c .)" -ge 6 ] || [ $i -ge 300 ]; do sleep 0.1; i=$((i + 1)); done
  printf '%s' "$in" | "$REPO/hooks/session-beat.sh" prompt >/dev/null 2>&1 || true
  i=0; until jq -e 'select(.hook=="session-beat")' "$CC_HOOK_TIMING_LEDGER" >/dev/null 2>&1 || [ $i -ge 300 ]; do sleep 0.1; i=$((i + 1)); done
  for h in handed-off-session-guard cache-expiry-warning memory-nudge handoff-intent-nudge \
           research-precognition-nudge mailbox-drain session-beat; do
    jq -e --arg h "$h" 'select(.hook==$h and .disposition=="timed" and (.ms|type)=="number")' \
      "$CC_HOOK_TIMING_LEDGER" >/dev/null || { echo "no timed row for $h"; cat "$CC_HOOK_TIMING_LEDGER"; false; }
  done
  jq -e 'select(.hook=="mailbox-drain" and .sid=="abc-1")' "$CC_HOOK_TIMING_LEDGER" >/dev/null
  jq -e 'select(.hook=="session-beat" and .sid=="abc-1")' "$CC_HOOK_TIMING_LEDGER" >/dev/null
}

@test "mailbox-drain stamps only in prompt mode" {
  printf '%s' '{"session_id":"abc-1","hook_event_name":"PostToolUse","cwd":"/tmp"}' \
    | CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mailbox" "$REPO/hooks/mailbox-drain.sh" post-tool >/dev/null 2>&1 || true
  [ ! -e "$CC_HOOK_TIMING_DIR" ] || [ -z "$(ls -A "$CC_HOOK_TIMING_DIR")" ]
}

@test "a hook reached through a dir with no lib/ (set -e hooks included) still runs; only the stamp is lost" {
  # bash 3.2 EXITS a `set -e` shell when `.` cannot find its file, even inside an `if`.
  d="$BATS_TEST_TMPDIR/bare/hooks"; mkdir -p "$d"
  for h in memory-nudge cache-expiry-warning research-precognition-nudge; do
    ln -s "$REPO/hooks/$h.sh" "$d/$h.sh"
    run bash -c "printf '%s' '{\"session_id\":\"abc-1\",\"cwd\":\"/tmp\",\"prompt\":\"hi\"}' | /bin/bash '$d/$h.sh'"
    [ "$status" -eq 0 ] || { echo "$h exited $status without its lib"; false; }
  done
  [ ! -e "$CC_HOOK_TIMING_DIR" ] || [ -z "$(ls -A "$CC_HOOK_TIMING_DIR")" ]
}
