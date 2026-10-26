#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031
#   Structurally false under bats (every @test body is its own subshell; `run` sets $output there).
#
# alarm-reboot-prep.sh --files-only (incident 2026-10-25, DESIGN.md C6): the roster taken before a
# LOCKUP reboot. In a lockup `ps`, `cc-sessions` and `kitty @` are what hang, so this mode reads files
# only — Claude Code's pid files (<config>/sessions/<pid>.json), the newest heartbeat's rosters and
# the last 10 minutes of shutdown tombstones — and writes the reboot-<date>.roster.json + .start that
# boot-resume reads. Contracts: zero calls to ps / cc-sessions / kitten (each a PATH-and-seam stub
# that logs); the roster merges the three by session id, field by field, the heartbeat winning; an old tombstone
# and a non-interactive session are left out.
# RED-proof: against origin/main's alarm-reboot-prep.sh, --files-only is a usage error (exit 2).

bats_require_minimum_version 1.5.0

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  S="$REPO/scripts/alarm-reboot-prep.sh"
  D="$BATS_TEST_TMPDIR"
  export HOME="$D/home"; mkdir -p "$HOME"
  export CC_REBOOT_PREP_DIR="$D/autonomy" CC_REBOOT_PREP_DATE=2020-01-01
  mkdir -p "$D/bin" "$CC_REBOOT_PREP_DIR"
  for b in ps cc-sessions kitten kitty lsof; do
    printf '#!/bin/sh\necho "%s $*" >> "%s/calls.log"\nexit 0\n' "$b" "$D" > "$D/bin/$b"; chmod +x "$D/bin/$b"
  done
  export PATH="$D/bin:$PATH"
  export CC_REBOOT_PREP_PS="$D/bin/ps" CC_REBOOT_PREP_SESSIONS="$D/bin/cc-sessions" CC_REBOOT_PREP_LSOF="$D/bin/lsof" \
         CC_REBOOT_PREP_KITTEN="$D/bin/kitten" CC_REBOOT_PREP_CC_HOMES="$D/cc/.claude"
  export CC_HEARTBEAT_DIR="$D/hb" CC_SHUTDOWN_TOMB_DIR="$D/tombs"
  # never the live ones (the files-only mode reads none of them; a regression must not reach them)
  export CC_REBOOT_PREP_CLAUDE_TMP="$D/no-ctmp" CC_REBOOT_PREP_KITTY_SOCK_PREFIX="$D/no-kitty-" CC_REBOOT_PREP_SOCKS_DIR="$D/no-socks"
  mkdir -p "$D/cc/.claude-quaternary/sessions" "$D/cc/.claude-next/sessions" "$CC_SHUTDOWN_TOMB_DIR"
  printf '{"pid":11,"sessionId":"s-pidfile","cwd":"/w/a","startedAt":1,"kind":"interactive"}\n' > "$D/cc/.claude-quaternary/sessions/11.json"
  printf '{"pid":12,"sessionId":"s-headless","cwd":"/w/h","startedAt":1,"kind":"print"}\n' > "$D/cc/.claude-next/sessions/12.json"
  printf '{"pid":13,"sessionId":"s-both","cwd":"/w/b","startedAt":1,"kind":"interactive"}\n' > "$D/cc/.claude-next/sessions/13.json"
  # two heartbeat boots; the newer one names s-both with its pane
  mkdir -p "$D/hb/OLD/1" "$D/hb/NEW/7"
  echo 100 > "$D/hb/OLD/1/hb.start"; echo '[{"session_id":"s-old","cwd":"/w/o"}]' > "$D/hb/OLD/1/hb.roster.json"
  echo 200 > "$D/hb/NEW/7/hb.start"; echo '[{"session_id":"s-both","cwd":"/w/b","paneUUID":"42","kitty_pid":7}]' > "$D/hb/NEW/7/hb.roster.json"
  now="$(date +%s)"
  printf '{"session_id":"s-tomb","cwd":"/w/t","account":"claude-next","endedAt":%s}\n' "$((now - 60))" > "$D/tombs/t1.json"
  printf '{"session_id":"s-tomb-old","cwd":"/w/x","account":"claude-next","endedAt":%s}\n' "$((now - 7200))" > "$D/tombs/t2.json"
}

@test "files-only: no ps, no cc-sessions, no kitty — a roster from pid files, the newest heartbeat and recent tombstones" {
  run bash "$S" --files-only
  [ "$status" -eq 0 ]
  [ ! -s "$D/calls.log" ]                                         # nothing that can hang in a lockup was called
  r="$CC_REBOOT_PREP_DIR/reboot-2020-01-01.roster.json"
  [ -s "$CC_REBOOT_PREP_DIR/reboot-2020-01-01.start" ]
  [ "$(jq -r '[.[].session_id] | sort | join(" ")' "$r")" = "s-both s-pidfile s-tomb" ]
  [ "$(jq -r '.[] | select(.session_id == "s-both") | .paneUUID' "$r")" = 42 ]     # the heartbeat names the pane
  [ "$(jq -r '.[] | select(.session_id == "s-both") | .account' "$r")" = claude-next ]   # the pid file fills the rest
  [ "$(jq -r '.[] | select(.session_id == "s-pidfile") | .account' "$r")" = claude-quaternary ]
  [[ "$output" == *"files-only roster=$r sessions=3 heartbeat=$D/hb/NEW"* ]] || false
}

