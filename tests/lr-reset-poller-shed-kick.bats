#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031  # each @test is its own subshell; per-test exports are the intent
# lr-reset-poller.sh lrp_shed_kick — the poller starts the late-band shed (D2b, LR_SUSTAINED_LOAD W16;
# D2-warning-band-shedding.md §6.4 and §8 T3, with review D1). The tests/lr-evidence-gc.bats poller
# cases are the model: only the deployed layer starts it, detached, throttled by a stamp.
#
# WHAT IS PINNED:
#   · nothing at all happens while shed/mode is absent (the kill switch), not even a log line;
#   · a copy that is not the deployed layer never starts it (test ticks once started 133 copies of
#     the evidence GC);
#   · D1: the kick takes NO lock and writes NO pid. The design's kick wrote the pid it had just
#     started into run.pid, and the controller then read its own live pid there and returned: every
#     tick a no-op. Here the started controller really runs (a decision row lands), and a controller
#     already holding shed/run.lock makes the new start a quiet no-op inside lr-shed.py;
#   · the start is detached, outlives the tick, and is not under taskpolicy (it must inherit the
#     poller's Interactive band, priority 31);
#   · the stamp throttles it to LR_SHED_EVERY_MIN; --dry-run only says it would start.
#
# Every tick runs /bin/bash, the interpreter launchd gives the poller. HERMETIC: HOME, LR_STATE_DIR,
# LR_RECON_ROOT and TMPDIR live under BATS_TEST_TMPDIR; claude-accounts is a stub whose --shed-band
# answer is a blind one, so a started controller only ever logs.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  POLLER="$REPO/scripts/limit-recover/lr-reset-poller.sh"
  export LR_UPGRADE_AUTO=off LR_POLLER_NO_CENSUS=1
  export HOME="$BATS_TEST_TMPDIR/home"; PSTATE="$HOME/.reso/limit-recover"
  export TMPDIR="$BATS_TEST_TMPDIR/tmp"
  mkdir -p "$HOME/bin" "$PSTATE/parked" "$PSTATE/locks" "$BATS_TEST_TMPDIR/stubs" "$TMPDIR"
  # The poller defaults LR_STATE_DIR to this same path; it is set so the detached controller and the
  # assertions read one store whichever way a future poller resolves it.
  export LR_STATE_DIR="$PSTATE" LR_RECON_ROOT="$PSTATE/recon"
  unset LR_CONFIG_DIRS CLAUDE_CONFIG_DIR KITTY_WINDOW_ID LR_SHED LR_SHED_EVERY_MIN CC_ACCOUNTS_BIN
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg"; mkdir -p "$CC_REGISTRY_DIR"
  export CC_KITTY_SOCKET_BIN="$BATS_TEST_TMPDIR/no-kitty-socket" LR_CC_TUI_LIB="$BATS_TEST_TMPDIR/absent-cc-tui.sh"
  printf '#!/bin/bash\nexit 1\n' > "$BATS_TEST_TMPDIR/stubs/osascript"
  printf '#!/bin/bash\nexit 0\n' > "$BATS_TEST_TMPDIR/stubs/launchctl"
  # The poller's --rank reads get `none`; the controller's --shed-band read gets a blind answer
  # (after CA_SLEEP, so a case can watch the run while it is alive).
  cat > "$HOME/bin/claude-accounts" <<'STUB'
#!/bin/bash
case " $* " in *" --shed-band "*) sleep "${CA_SLEEP:-0}"; echo '{"v":1,"wait_data":true}'; exit 3 ;; esac
echo none
STUB
  chmod +x "$BATS_TEST_TMPDIR/stubs/"* "$HOME/bin/claude-accounts"
  export PATH="$BATS_TEST_TMPDIR/stubs:$PATH" LR_SHED_CA_BIN="$HOME/bin/claude-accounts"
}
teardown() { [ -z "${SP:-}" ] || kill "$SP" 2>/dev/null || true; }
live_layer() { # the fixture $HOME's deployed lr-shed.py IS this checkout's, as install.sh links it
  mkdir -p "$HOME/.claude/scripts/limit-recover"
  ln -s "$REPO/scripts/limit-recover/lr-shed.py" "$HOME/.claude/scripts/limit-recover/lr-shed.py"
}
mode() { mkdir -p "$PSTATE/shed"; printf '%s\n' "$1" > "$PSTATE/shed/mode"; }
plog() { cat "$PSTATE/poller.log" 2>/dev/null; }
kicked_pid() { sed -n 's/.*SHED-KICK started pid \([0-9][0-9]*\).*/\1/p' "$PSTATE/poller.log" | tail -1; }
await_row() { # the detached controller's first decision row, bounded; it never waits on load
  local _i
  for _i in $(seq 1 150); do grep -q "\"ev\":\"$1\"" "$PSTATE/shed/decisions.jsonl" 2>/dev/null && return 0; sleep 0.2; done
  return 1
}

@test "[RED] a copy that is not the deployed layer never starts the shed, even with shed/mode present" {
  mode shadow
  run /bin/bash "$POLLER" --once
  grep -q 'SHED-SKIP .* is not the deployed layer' "$PSTATE/poller.log" || { plog; false; }
  ! grep -q 'SHED-KICK' "$PSTATE/poller.log" || { plog; false; }
  [ ! -e "$PSTATE/shed/kick.stamp" ]
}

@test "shed/mode absent: no start and no log line at all (the kill switch)" {
  live_layer
  run /bin/bash "$POLLER" --once
  ! grep -q 'SHED' "$PSTATE/poller.log" || { plog; false; }
  [ ! -d "$PSTATE/shed" ]
}

@test "LR_SHED=off: nothing, with the mode file present" {
  live_layer; mode shadow
  LR_SHED=off run /bin/bash "$POLLER" --once
  ! grep -q 'SHED' "$PSTATE/poller.log" || { plog; false; }
}

@test "--dry-run only says it would start: no stamp, no process" {
  live_layer; mode shadow
  run /bin/bash "$POLLER" --dry-run --once
  grep -q 'DRY   shed would start: /usr/bin/python3 -I .*lr-shed.py --tick' "$PSTATE/poller.log" || { plog; false; }
  [ ! -e "$PSTATE/shed/kick.stamp" ]
  [ ! -e "$PSTATE/shed/decisions.jsonl" ]
}

@test "[RED] D1: the live layer's tick starts ONE detached controller that outlives the tick, not under taskpolicy, and it RUNS (no pid file locks it out)" {
  live_layer; mode shadow
  export CA_SLEEP=8
  run /bin/bash "$POLLER" --once
  SP="$(kicked_pid)"
  [ -n "$SP" ] || { plog; false; }
  # the tick has exited; the controller is still alive as lr-shed.py, at the poller's band
  # (/usr/bin/python3 is a shim that execs the Xcode framework Python, so the argv reads `…/Python -I`)
  ps -o command= -p "$SP" | grep -q 'Python.* -I .*/lr-shed.py --tick\|python3 -I .*/lr-shed.py --tick' || { ps -o command= -p "$SP"; false; }
  ! ps -o command= -p "$SP" | grep -q taskpolicy || false
  [ ! -e "$PSTATE/shed/run.pid" ]
  # D1: the run the kick started is the one that takes the lock and writes the decision
  for _i in $(seq 1 50); do [ -s "$PSTATE/shed/run.lock" ] && break; sleep 0.2; done
  [ "$(cut -d' ' -f1 "$PSTATE/shed/run.lock")" = "$SP" ] || { cat "$PSTATE/shed/run.lock"; false; }
  await_row band || { cat "$PSTATE/shed/shed.log" "$PSTATE/shed/decisions.jsonl" 2>/dev/null; false; }
  grep -q '"verdict":"unknown"' "$PSTATE/shed/decisions.jsonl"
  ! grep -q Traceback "$PSTATE/shed/shed.log" 2>/dev/null || { cat "$PSTATE/shed/shed.log"; false; }
}

@test "the stamp throttles to LR_SHED_EVERY_MIN: a second tick starts nothing" {
  live_layer; mode shadow
  run /bin/bash "$POLLER" --once
  [ "$(grep -c 'SHED-KICK started' "$PSTATE/poller.log")" -eq 1 ] || { plog; false; }
  run /bin/bash "$POLLER" --once
  [ "$(grep -c 'SHED-KICK started' "$PSTATE/poller.log")" -eq 1 ] || { plog; false; }
  # an aged stamp lets the next tick start it again
  touch -t 202601010000 "$PSTATE/shed/kick.stamp"
  run /bin/bash "$POLLER" --once
  [ "$(grep -c 'SHED-KICK started' "$PSTATE/poller.log")" -eq 2 ] || { plog; false; }
}

@test "a controller already holding shed/run.lock makes the new start a quiet no-op inside lr-shed.py" {
  live_layer; mode shadow
  sleep 60 3>&- & SP=$!
  printf '%s %s' "$SP" "$(TZ=UTC LC_ALL=C ps -o lstart= -p "$SP" | tr -s ' ' | sed 's/^ //;s/ $//')" > "$PSTATE/shed/run.lock"
  run /bin/bash "$POLLER" --once
  KP="$(kicked_pid)"; [ -n "$KP" ] || { plog; false; }
  for _i in $(seq 1 100); do kill -0 "$KP" 2>/dev/null || break; sleep 0.2; done
  ! kill -0 "$KP" 2>/dev/null || { echo "the second controller is still running"; false; }
  [ ! -e "$PSTATE/shed/decisions.jsonl" ] || { cat "$PSTATE/shed/decisions.jsonl"; false; }
  [ "$(cut -d' ' -f1 "$PSTATE/shed/run.lock")" = "$SP" ]
}
