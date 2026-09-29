#!/usr/bin/env bats
# session-register.sh records WHICH kitty a pane lives in (W2c, docs/plans/LIMIT_RECOVER_FLEET_V2.md).
#
# A kitty window id is a per-process counter that restarts at 1 with every kitty, so the row's
# paneUUID alone can name a window in a DIFFERENT kitty after a restart. The row therefore carries
# `kitty_listen_on` (the control socket, only when it is live at registration) and `kitty_pid` (the
# numeric pid kitty.conf embeds in that socket's name) — the proof a reconciler hands bin/it2-kitty
# as CC_TERM_KITTY_PID. Both are null whenever they cannot be proven, and the hook never forks `ps`
# for them. Assertions are on the written ROW, never on the hook's report of itself.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  REG="$REPO/hooks/session-register.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg"
  export SESSION_REGISTER_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export SESSION_REGISTER_RECLAIM_WAIT=1 CC_BACKLOG_BIN=/usr/bin/false
  S="$BATS_TEST_TMPDIR/s"; mkdir -p "$S"
}

mksock() { # bind a real unix socket at $1; relative bind keeps sun_path under Darwin's 104 bytes
  /usr/bin/python3 -c 'import os,socket,sys; d,b=os.path.split(os.path.abspath(sys.argv[1])); os.chdir(d); socket.socket(socket.AF_UNIX).bind(b)' "$1"
  [ -S "$1" ]
}

register() { # $1 = KITTY_LISTEN_ON value ('' = unset)
  printf '{"cwd":"/tmp/kt"}' \
    | env -u ITERM_SESSION_ID -u CC_PANE_ID -u KITTY_LISTEN_ON KITTY_WINDOW_ID=186 CC_SESSION_NAME=kt \
          ${1:+KITTY_LISTEN_ON=$1} bash "$REG"
  [ -f "$CC_REGISTRY_DIR/186.json" ]
}

@test "a live kitty socket: the row carries kitty_listen_on and a NUMERIC kitty_pid" {
  mksock "$S/kitty-4242"
  register "unix:$S/kitty-4242"
  run jq -r '.kitty_listen_on' "$CC_REGISTRY_DIR/186.json"; [ "$output" = "unix:$S/kitty-4242" ]
  run jq -r '.kitty_pid|type' "$CC_REGISTRY_DIR/186.json";  [ "$output" = "number" ]
  run jq -r '.kitty_pid' "$CC_REGISTRY_DIR/186.json";       [ "$output" = "4242" ]
  # every pre-existing field survives the widening
  run jq -r '.paneUUID, .name, (.pid|type)' "$CC_REGISTRY_DIR/186.json"
  [ "$output" = "$(printf '186\nkt\nnumber')" ]
}

@test "KITTY_LISTEN_ON unset: both keys present and null" {
  register ""
  run jq -c '[has("kitty_listen_on"), has("kitty_pid"), .kitty_listen_on, .kitty_pid]' "$CC_REGISTRY_DIR/186.json"
  [ "$output" = '[true,true,null,null]' ]
}

@test "KITTY_LISTEN_ON naming a plain FILE (not a socket): both null" {
  touch "$S/kitty-4243"
  register "unix:$S/kitty-4243"
  run jq -c '[has("kitty_listen_on"), .kitty_listen_on, .kitty_pid]' "$CC_REGISTRY_DIR/186.json"
  [ "$output" = '[true,null,null]' ]
}

@test "a live socket whose name embeds no pid: the socket is kept, the pid is null" {
  mksock "$S/inherited"
  register "unix:$S/inherited"
  run jq -c '[.kitty_listen_on, .kitty_pid]' "$CC_REGISTRY_DIR/186.json"
  [ "$output" = "[\"unix:$S/inherited\",null]" ]
}
