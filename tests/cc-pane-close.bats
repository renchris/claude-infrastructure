#!/usr/bin/env bats
# bin/cc-pane-close — an agent can close a husk pane that should close, without kitty remote control.
#
# Husk panes 55, 69 and 76 (2026-10-01) sat at a bare shell for hours while kitty's control socket
# refused connections, and the only remedy an agent could offer was "press Ctrl-D". This closes a
# pane by signalling its window shell, behind four fail-closed gates (identity, nothing live, the
# session meant to end or its work was ruled done, no uncommitted work). Every external is a stub:
# ps answers from fixture files, kill only records its argv, nothing touches a real process.
# shellcheck disable=SC2030,SC2031,SC2016  # per-test env exports are deliberate; stub bodies are literal

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  CLOSE="$REPO/bin/cc-pane-close"
  F="$BATS_TEST_TMPDIR/fix"; S="$BATS_TEST_TMPDIR/stub"; mkdir -p "$F" "$S"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  unset KITTY_LISTEN_ON CC_PANE_CMD CC_PANE_CMD_DIR CC_PANE_CMD_INTERACTIVE
  export CC_PANE_CLOSE_KITTY_PID=610 CC_PANE_CLOSE_REMOTE=off CC_PANE_CLOSE_SETTLE_S=1
  export CC_PANE_CLOSE_WATCHDOG_LOG="$F/watchdog.log" CC_PANE_CLOSE_LOG="$F/close.jsonl"
  export CC_PANE_CLOSE_STORES="$F/store" CC_PANE_CLOSE_CUSTODY_BIN="$S/custody" FIX="$F"
  export CC_PANE_CLOSE_PS_BIN="$S/ps" CC_PANE_CLOSE_KILL_BIN="$S/kill"
  # ps: `-o lstart= -p <pid>` → $FIX/lstart.<pid>; `-o pid=,ppid=,comm= -t <tty>` → $FIX/tty.<tty>
  # shellcheck disable=SC2016  # stub bodies expand when the STUB runs
  printf '#!/bin/bash\nfor a; do prev2="$prev"; prev="$a"; done\ncase "$2" in lstart=) cat "$FIX/lstart.$prev" 2>/dev/null ;; *) cat "$FIX/tty.$prev" 2>/dev/null ;; esac\nexit 0\n' > "$S/ps"
  # kill: records its argv, and the window then goes away (its root process loses its lstart)
  # shellcheck disable=SC2016
  printf '#!/bin/bash\necho "$*" >> "$FIX/kill.log"\nrm -f "$FIX/lstart.$ROOT"\n' > "$S/kill"
  printf '#!/bin/bash\ncat "$FIX/custody.tsv" 2>/dev/null\n' > "$S/custody"
  chmod +x "$S"/*
  NOW=$(date +%s); K=$((NOW - 36000)); REG=$((NOW - 7200))
  lst 610 "$K"
  export ROOT=5000
  SID="aaaaaaaa-1111-2222-3333-444444444444"
  printf '[%s] registered session=%s pid=7000 tty=ttys057 pane=69\n' "$(date -r "$REG" '+%Y-%m-%d %H:%M:%S')" "$SID" > "$F/watchdog.log"
  lst 5000 $((REG - 4)); lst 5001 $((REG - 4))           # login + zsh started just before the session
  printf '5000 610 /usr/bin/login\n5001 5000 /bin/zsh\n9999 1 gitstatusd\n' > "$F/tty.ttys057"
  CWD="$BATS_TEST_TMPDIR/work"; mkdir -p "$CWD"; git -C "$CWD" init -q
  mkdir -p "$F/store/projects/p"
}

lst() { date -u -r "$2" '+%a %b %d %T %Y' > "$FIX/lstart.$1"; }
transcript() { # $1 = jsonl body lines (cwd is filled in)
  printf '%s\n' "$@" | sed "s#CWD#$CWD#g" > "$FIX/store/projects/p/$SID.jsonl"
}
teammate()  { transcript '{"type":"user","teamName":"session-x","cwd":"CWD","message":{"role":"user","content":"hi"}}'; }
plain_no()  { transcript '{"type":"user","cwd":"CWD","message":{"role":"user","content":"An honest Good to close: no in instructions"}}'; }

@test "a retired teammate's husk is closed by SIGHUP to its window shell" {
  teammate
  run "$CLOSE" --pane 69
  [ "$status" -eq 0 ]
  [[ "$output" == *"pane 69: CLOSED"*"retired Agent-Teams member"*"SIGHUP to the window shell (pid 5001)"* ]] || false
  [ "$(cat "$FIX/kill.log")" = "-HUP 5001" ]
}

@test "a still-running claude refuses — nothing is signalled" {
  teammate; lst 7000 $((REG - 2))
  run "$CLOSE" --pane 69
  [ "$status" -eq 1 ]
  [[ "$output" == *"its claude (pid 7000) is still running"* ]] || false
  [ ! -e "$FIX/kill.log" ]
}

@test "a reused claude pid (started after the registration) does not count as live" {
  teammate; lst 7000 $((NOW - 60))
  run "$CLOSE" --pane 69
  [ "$status" -eq 0 ]
}

@test "a window that started AFTER the session registered is a different window — refused" {
  teammate; lst 5000 $((REG + 600))
  run "$CLOSE" --pane 69
  [ "$status" -eq 1 ]
  [[ "$output" == *"a different window"* ]] || false
  [ ! -e "$FIX/kill.log" ]
}

@test "a live job in the window (not a shell) is refused" {
  teammate; printf '5000 610 /usr/bin/login\n5001 5000 /bin/zsh\n5002 5001 node\n' > "$FIX/tty.ttys057"
  run "$CLOSE" --pane 69
  [ "$status" -eq 1 ]
  [[ "$output" == *"a live job runs in the window: node"* ]]
}

@test "a session with nothing saying it meant to end is refused, pointing at triage" {
  plain_no
  run "$CLOSE" --pane 69
  [ "$status" -eq 1 ]
  [[ "$output" == *"nothing says session aaaaaaaa meant to end"*"cc-husk-sweep --pane 69"* ]] || false
  [ ! -e "$FIX/kill.log" ]
}

@test "an orchestrator's custody abandon after the registration makes a killed lead closeable" {
  plain_no
  printf '%s\tabandon\tw2-x\t69\tMARK\tprov?\n' "$(date -u -r $((REG + 60)) +%FT%TZ)" > "$FIX/custody.tsv"
  run "$CLOSE" --pane 69
  [ "$status" -eq 0 ]
  [[ "$output" == *"abandoned/returned its custody"* ]]
}

@test "a custody abandon from BEFORE this registration does not count" {
  plain_no
  printf '%s\tabandon\tw2-x\t69\tMARK\tprov?\n' "$(date -u -r $((REG - 600)) +%FT%TZ)" > "$FIX/custody.tsv"
  run "$CLOSE" --pane 69
  [ "$status" -eq 1 ]
}

@test "the close verdict is read from ASSISTANT text only" {
  transcript '{"type":"user","cwd":"CWD","message":{"role":"user","content":"Good to close: no"}}' \
             '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Good to close: yes — done"}]}}'
  run "$CLOSE" --pane 69
  [ "$status" -eq 0 ]
  [[ "$output" == *"Good to close: yes"* ]]
}

@test "uncommitted work in the session's cwd refuses the close" {
  teammate; echo x > "$CWD/f"
  run "$CLOSE" --pane 69
  [ "$status" -eq 1 ]
  [[ "$output" == *"uncommitted change(s)"* ]]
}

@test "--dry-run says WOULD CLOSE and signals nothing" {
  teammate
  run "$CLOSE" --dry-run --pane 69
  [ "$status" -eq 0 ]
  [[ "$output" == *"WOULD CLOSE"* ]] || false
  [ ! -e "$FIX/kill.log" ]
}

@test "a registration from a previous kitty's lifetime is ignored" {
  teammate; lst 610 $((NOW - 60))
  run "$CLOSE" --pane 69
  [ "$status" -eq 1 ]
  [[ "$output" == *"no session registration for this pane in the running kitty's lifetime"* ]]
}

@test "a signal that does not take is reported as FAILED, not closed" {
  teammate
  printf '#!/bin/bash\necho "$*" >> "$FIX/kill.log"\n' > "$S/kill"
  run "$CLOSE" --pane 69
  [ "$status" -eq 1 ]
  [[ "$output" == *"pane 69: FAILED"* ]]
}
