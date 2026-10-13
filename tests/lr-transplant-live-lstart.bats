#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2016,SC2034,SC2086  # each @test is its own subshell; per-test exports are the intent
# lr-transplant.sh --phase unconfirm: a LIVE source is live, whichever `ps` rendered its start time.
#
# THE DEFECT (reproduced 2026-10-13 on pane 12, claude pid 78979): `--phase unconfirm --source-pid
# 78979 --source-lstart L` refused source-dead for a process that was alive, with L taken from
# `ps -o lstart= -p 78979` in the session locale ("Sun 11 Oct 14:11:30 2026", en_CA) and under
# LC_ALL=C ("Sun Oct 11 14:11:30 2026"). The same call without the two flags succeeded. An lstart
# string carries no zone: both values are local time (CDT), and lrt_live compared them against the
# one form this rail writes, `TZ=UTC LC_ALL=C` ("Sun Oct 11 19:11:30 2026").
#
# Hermetic: the source is a real child process of the test, the stores are temp dirs, and the
# session zone is pinned so local time and UTC differ wherever the suite runs.

bats_require_minimum_version 1.5.0

setup() {
  command -v jq >/dev/null || skip "jq required"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LRT="$REPO/scripts/limit-recover/lr-transplant.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export LR_STATE_DIR="$HOME/.reso/limit-recover"; mkdir -p "$LR_STATE_DIR/locks"
  unset CLAUDE_CODE_SESSION_ID LR_RECON_ROOT
  HOLDER_PIDS=""
}

teardown() {
  local p
  for p in $HOLDER_PIDS; do kill "$p" 2>/dev/null || true; done
}

# half_moved → admit + confirm by the REAL writer over a REAL child holding the source
half_moved() {
  T="$BATS_TEST_TMPDIR"; SID=c56c729c-0000-4000-8000-000000000012
  mkdir -p "$T/from/projects/slug" "$T/to/projects/slug" "$T/from/sessions"
  SRC="$T/from/projects/slug/$SID.jsonl"; RET="$SRC.handed-off"
  printf '{"type":"user","uuid":"a1"}\n{"type":"assistant","uuid":"a2","message":{"stop_reason":"end_turn"}}\n' > "$SRC"
  bash "$LRT" --phase admit --sid "$SID" --from "$T/from" --to "$T/to" --cause voluntary >/dev/null
  bash "$LRT" --phase confirm --sid "$SID" --from "$T/from" --to "$T/to" --cause voluntary >/dev/null
  [ -f "$RET" ] && [ ! -e "$SRC" ]
  tail -f /dev/null >/dev/null 2>&1 3>&- &
  CHILD=$!; HOLDER_PIDS="$HOLDER_PIDS $CHILD"
  # the holder row every store of this rail writes: the start in UTC, C locale
  printf '{"pid":%s,"sessionId":"%s","procStart":"%s","cwd":"/tmp"}\n' "$CHILD" "$SID" \
    "$(TZ=UTC LC_ALL=C ps -o lstart= -p "$CHILD" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')" > "$T/from/sessions/s1.json"
}

@test "[RED] unconfirm accepts a live source whose lstart came from a plain ps: local time, C locale or the session's" {
  local form l
  export TZ=America/Chicago
  for form in "LC_ALL=C" "LC_ALL=en_CA.UTF-8" "LC_ALL=C TZ=UTC"; do
    half_moved
    l="$(env $form ps -o lstart= -p "$CHILD")"
    [ -n "$l" ]
    run --separate-stderr bash "$LRT" --phase unconfirm --sid "$SID" --from "$T/from" --to "$T/to" --source-pid "$CHILD" --source-lstart "$l"
    [ "$status" -eq 0 ] || { echo "form '$form' lstart '$l': rc=$status $output $stderr"; false; }
    [ -f "$SRC" ] || { echo "form '$form': the source is not back at its path"; false; }
    [ ! -e "$RET" ] || { echo "form '$form': the source was not handed back"; false; }
    kill "$CHILD" 2>/dev/null || true
    rm -rf "$T/from" "$T/to" "$LR_STATE_DIR/locks"; mkdir -p "$LR_STATE_DIR/locks"
  done
}

@test "a start time that is not that process's still refuses source-dead, and so does a dead pid" {
  export TZ=America/Chicago
  half_moved
  run --separate-stderr bash "$LRT" --phase unconfirm --sid "$SID" --from "$T/from" --to "$T/to" --source-pid "$CHILD" --source-lstart "Mon Jan  1 00:00:00 2001"
  [ "$status" -eq 2 ] || { echo "rc=$status $output $stderr"; false; }
  [ "$(printf '%s' "$output" | jq -r .reason)" = source-dead ] || { echo "$output"; false; }
  local l; l="$(LC_ALL=C ps -o lstart= -p "$CHILD")"
  kill "$CHILD" 2>/dev/null || true; wait "$CHILD" 2>/dev/null || true
  run --separate-stderr bash "$LRT" --phase unconfirm --sid "$SID" --from "$T/from" --to "$T/to" --source-pid "$CHILD" --source-lstart "$l"
  [ "$status" -eq 2 ] || { echo "a dead pid passed: rc=$status $output"; false; }
  [ -f "$RET" ] || { echo "a refusal moved the retired copy"; false; }
}
