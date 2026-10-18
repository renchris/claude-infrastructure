#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2329,SC2317
# Startup sentinels (docs/research/startup-hooks-2026-10-18/README.md §5 unit 3.1): every own sync
# SessionStart hook leaves <hook>.start and, on every exit path, <hook>.done with rc, elapsed and the
# bytes it owed — so a harness cancel (which Claude Code renders nowhere) is reportable. Hermetic:
# $HOME and CC_STARTUP_HEALTH_DIR are fixtures; no hook runs against live state.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LIB="$REPO/hooks/lib/startup-sentinel.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude"
  export CC_STARTUP_HEALTH_DIR="$BATS_TEST_TMPDIR/sh"
  SID="aaaaaaaa-1111-2222-3333-444444444444"
  S="$CC_STARTUP_HEALTH_DIR/$SID"
}

probe() { # <body> → a hook script that opens a sentinel then runs body
  printf '#!/bin/bash\n. "%s" && ss_begin probe-hook 5000 "%s" "%s"\n%s\n' "$LIB" "$SID" "${TP:-}" "$1" \
    > "$BATS_TEST_TMPDIR/h.sh"
}
field() { sed -n "s/^$2=//p" "$S/$1"; }

@test "healthy run: start and done, rc 0, owed matches the bytes printed" {
  probe 'out="hello world"; ss_owed $(( ${#out} + 1 )); printf "%s\n" "$out"'
  run bash "$BATS_TEST_TMPDIR/h.sh"
  [ "$status" -eq 0 ]
  [ -f "$S/probe-hook.start" ]
  [ "$(field probe-hook.done rc)" = 0 ]
  [ "$(field probe-hook.done owed)" = "$(( ${#output} + 1 ))" ]    # bats strips the trailing newline
  [ "$(field probe-hook.done timeout_ms)" = 5000 ]
}

@test "an abstain (early exit 0, nothing printed) still leaves done with owed 0" {
  probe 'exit 0'
  run bash "$BATS_TEST_TMPDIR/h.sh"
  [ "$(field probe-hook.done rc)" = 0 ]
  [ "$(field probe-hook.done owed)" = 0 ]
}

@test "a TERM leaves done rc=143" {
  probe 'sleep 5 & wait $!'
  bash "$BATS_TEST_TMPDIR/h.sh" & p=$!
  for _ in 1 2 3 4 5 6 7 8 9 10; do [ -f "$S/probe-hook.start" ] && break; sleep 0.2; done
  kill -TERM "$p"; wait "$p" || true
  [ "$(field probe-hook.done rc)" = 143 ]
}

@test "a SIGKILL leaves start without done (still readable as a possible loss)" {
  probe 'sleep 5 & wait $!'
  bash "$BATS_TEST_TMPDIR/h.sh" & p=$!
  for _ in 1 2 3 4 5 6 7 8 9 10; do [ -f "$S/probe-hook.start" ] && break; sleep 0.2; done
  kill -KILL "$p"; wait "$p" || true
  [ -f "$S/probe-hook.start" ]
  [ ! -f "$S/probe-hook.done" ]
}

@test "session.start is written once, with the transcript path and its size at start" {
  TP="$BATS_TEST_TMPDIR/t.jsonl"; printf '0123456789' > "$TP"
  probe 'exit 0'
  bash "$BATS_TEST_TMPDIR/h.sh"
  [ "$(field session.start transcript_path)" = "$TP" ]
  [ "$(field session.start size)" = 10 ]
  printf 'more' >> "$TP"
  bash "$BATS_TEST_TMPDIR/h.sh"
  [ "$(field session.start size)" = 10 ]     # the FIRST writer's record stands
}

@test "CC_STARTUP_SENTINEL=0 writes nothing; an unsafe sid writes nothing" {
  probe 'exit 0'
  CC_STARTUP_SENTINEL=0 bash "$BATS_TEST_TMPDIR/h.sh"
  [ ! -e "$S" ]
  SID='../escape'; probe 'exit 0'; bash "$BATS_TEST_TMPDIR/h.sh"
  [ ! -e "$CC_STARTUP_HEALTH_DIR/../escape" ]
}

@test "desk-brief-inject leaves start+done on its abstain path (no role file)" {
  run bash -c "printf '{\"session_id\":\"$SID\"}' | DESK_BRIEF_IDL='$BATS_TEST_TMPDIR/idl.jsonl' CC_ROLES_DIR='$BATS_TEST_TMPDIR/roles' DESK_BRIEF_PANE=p1 bash '$REPO/hooks/desk-brief-inject.sh'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -f "$S/desk-brief-inject.start" ]
  [ "$(field desk-brief-inject.done rc)" = 0 ]
  [ "$(field desk-brief-inject.done owed)" = 0 ]
}

@test "desk-brief-inject's injected brief is recorded as owed bytes" {
  mkdir -p "$BATS_TEST_TMPDIR/roles"; echo p1 > "$BATS_TEST_TMPDIR/roles/desk"
  printf 'brief body\n' > "$BATS_TEST_TMPDIR/brief.md"
  run bash -c "printf '{\"session_id\":\"$SID\"}' | DESK_BRIEF_IDL='$BATS_TEST_TMPDIR/idl.jsonl' CC_ROLES_DIR='$BATS_TEST_TMPDIR/roles' DESK_BRIEF_PANE=p1 DESK_BRIEF_FILE='$BATS_TEST_TMPDIR/brief.md' bash '$REPO/hooks/desk-brief-inject.sh'"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("brief body")' >/dev/null
  [ "$(field desk-brief-inject.done owed)" = "$(( ${#output} + 1 ))" ]
}
