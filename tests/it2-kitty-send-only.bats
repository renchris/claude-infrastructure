#!/usr/bin/env bats
# it2-kitty `session type` — the SEND-ONLY verb, and the arming marker's lifetime.
#
# WHY THIS SUITE EXISTS. scripts/handoff-fire.sh's --recycle and self-close could not type `/exit`
# into a kitty pane at all, so session succession was silently broken on every kitty box
# (docs/plans/KITTY_RECYCLE_TRANSPORT.md). Two independent defects composed:
#
#   1. `run` is the LAUNCH verb. Against a pane it classifies as ARMED it does not type — it writes
#      the text to $CC_PANE_CMD_DIR/<id>.cmd and waits for cc-pane-runner to pick it up and exec it.
#      `/exit` starts no agent and a live Claude Code pane has no runner behind it, so that proof
#      can only ever fail. as_write returned non-zero 3x and both callers killed their own armed
#      watcher.
#   2. The arming marker outlived everything it stood for. The runner consumed it only on the path
#      where a command actually ARRIVED; a wait-loop timeout exec'd a shell and left it on disk, and
#      kitty window ids are a per-process counter that restarts at 1. Measured on this box
#      2026-09-17: 12 markers, 11 for dead panes, and `17.armed` — written 19h earlier — sitting
#      over a LIVE Claude Code session, which is the pane the defect was diagnosed on.
#
# The tests below are PAIRS wherever a claim has an opposite, because "the text was typed" is worth
# nothing unless something also proves this harness can still observe it being argv-delivered
# instead. Every assertion is `[ ]` or `… || false` — `[[ ]]` and `(( ))` are errexit-EXEMPT in bats
# and are silently DEAD anywhere but a body's last line.

setup() {
  export CC_FIRE_CAPACITY_GATE=off
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  K="$REPO/bin/it2-kitty"
  RUNNER="$REPO/bin/cc-pane-runner"
  # A fake socket bypasses the ancestry gate, so this suite does not depend on WHICH terminal the
  # developer is sitting in — the dependency that silently decided the verdict in five sibling
  # suites (tests/it2-kitty-argv-spawn.bats setup).
  export CC_TERM_KITTY_TO="unix:$BATS_TEST_TMPDIR/sock"
  export CC_TERM_KITTY="$BATS_TEST_TMPDIR/fake-kitty"
  export CC_PANE_CMD_DIR="$BATS_TEST_TMPDIR/cmd"
  export CC_PANE_RUNNER_BIN="$RUNNER"
  unset CC_PANE_CMD CC_PANE_CMD_INTERACTIVE CC_PANE_CMD_WAIT_S CC_PANE_RUNNER
  KLOG="$BATS_TEST_TMPDIR/kitty.log"; export KLOG
  mkdir -p "$CC_PANE_CMD_DIR"
  fake_kitty
}

# Pane 42 exists; every other id does not. That asymmetry is what lets prove_target be exercised.
fake_kitty() {
  cat > "$CC_TERM_KITTY" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >> "$KLOG"
verb=""
for a in "$@"; do
  case "$a" in @|--to|unix:*) continue ;; *) verb="$a"; break ;; esac
done
case "$verb" in
  ls)       echo '[{"id":1,"tabs":[{"id":1,"windows":[{"id":42,"title":"t","cwd":"/tmp","pid":9,"in_alternate_screen":true}]}]}]' ;;
  get-text) echo "fake pane text" ;;
esac
exit 0
SH
  chmod +x "$CC_TERM_KITTY"
}

arm() { : > "$CC_PANE_CMD_DIR/$1.armed"; }
# ONE producer per stream. `grep -c` PRINTS a valid 0 AND EXITS 1 on no-match, so
# `grep -c X f || echo 0` puts a SECOND 0 on the same stream and the caller reads "0\n0".
count_in_klog() { local n; n="$(grep -c -- "$1" "$KLOG" 2>/dev/null)" || n=0; printf '%s' "${n:-0}"; }
# A literal CR in the logged argv. `tr -d` is the portable reader; a $'\r' inside a bats heredoc is
# mangled by the layers between here and the shell that evaluates it.
klog_has_cr() { [ -f "$KLOG" ] && [ "$(tr -dc '\r' < "$KLOG" | wc -c | tr -d ' ')" != "0" ]; }

# ── the verb delivers, and delivers text + Enter ─────────────────────────────────────────────────

@test "session type sends the text WITH a carriage return — send alone would never submit /exit" {
  run "$K" session type -s 42 "/exit"
  [ "$status" -eq 0 ]
  # $'\r' reaches the fake as a literal CR inside the logged line.
  grep -q -- 'send-text --match id:42 -- /exit' "$KLOG" || false
  run bash -c "grep -c \$'\\\\r' '$KLOG'"
  [ "$output" != "0" ]
}

@test "CONTROL: session send is still the no-Enter verb — type did not replace it" {
  run "$K" session send -s 42 "/exit"
  [ "$status" -eq 0 ]
  ! klog_has_cr || false
}

# ── THE PAIR THAT IS THE WHOLE POINT: type never argv-delivers ───────────────────────────────────

@test "an ARMED pane is still TYPED by session type — a message is not a launch command" {
  arm 42
  run "$K" session type -s 42 "/exit"
  [ "$status" -eq 0 ]
  grep -q -- 'send-text --match id:42' "$KLOG" || false
  [ ! -f "$CC_PANE_CMD_DIR/42.cmd" ]
}

@test "CONTROL: the same ARMED pane makes session RUN argv-deliver — this harness can see it" {
  # Without this arm the case above proves nothing: a `type` that typed because the marker was not
  # read the same way would be indistinguishable from one that typed on purpose.
  arm 42
  CC_KITTY_SPAWN_VERIFY_S=0 run "$K" session run -s 42 "/exit"
  [ "$status" -eq 0 ]
  [ -f "$CC_PANE_CMD_DIR/42.cmd" ]
  grep -qx -- '/exit' "$CC_PANE_CMD_DIR/42.cmd" || false
  [ "$(count_in_klog send-text)" = "0" ]    # nothing was typed — it went into the file
}

# ── every gate the other delivery verbs have still binds ─────────────────────────────────────────

@test "session type with no -s REFUSES instead of typing into the active window" {
  run "$K" session type "/exit"
  [ "$status" -eq 65 ]
  echo "$output" | grep -q 'requires -s'
  echo "$output" | grep -qi 'active window'
  [ "$(count_in_klog send-text)" = "0" ]
}

@test "session type refuses an iTerm2 UUID, exactly like close/send/run" {
  run "$K" session type -s D40A5752-F313-4F2C-B5BF-2FADE3BADB2C "/exit"
  [ "$status" -eq 65 ]
  [ "$(count_in_klog send-text)" = "0" ]
}

@test "session type refuses a pane kitty does not list — send-text exits 0 for a dead id" {
  run "$K" session type -s 999999 "/exit"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q 'not in kitty'
  [ "$(count_in_klog send-text)" = "0" ]
}

@test "session type never mints the nonce wire — on a TUI that text becomes a chat message" {
  # `run`'s type_verified types `: <nonce>; <line>` and reads it back. On a live composer that is
  # not useless but DESTRUCTIVE: it enters the literal prefix as a message and submits it. `type`
  # must never reach that code at all, whatever a screen oracle says about the pane.
  run "$K" session type -s 42 "/exit"
  [ "$status" -eq 0 ]
  [ "$(count_in_klog 'ktv-')" = "0" ]
}

# ── the arming marker's lifetime ─────────────────────────────────────────────────────────────────

@test "a marker older than the runner's own wait budget no longer arms the pane" {
  # THE MEASURED DEFECT. cc-pane-runner gives up at CC_PANE_CMD_WAIT_S (300s) and becomes a shell,
  # so past that budget there is provably nobody behind the marker — whether it fell back cleanly or
  # was killed. Pane 17 on this box carried one for 19 hours.
  arm 42
  touch -t 202001010000 "$CC_PANE_CMD_DIR/42.armed"
  CC_KITTY_SPAWN_VERIFY_S=0 run "$K" session run -s 42 "hello"
  [ "$status" -eq 0 ]
  [ ! -f "$CC_PANE_CMD_DIR/42.cmd" ]              # not argv-delivered…
  grep -q -- 'send-text --match id:42' "$KLOG" || false   # …typed instead
}

@test "CONTROL: a FRESH marker still arms — the age bound did not retire the argv transport" {
  arm 42
  CC_KITTY_SPAWN_VERIFY_S=0 run "$K" session run -s 42 "hello"
  [ "$status" -eq 0 ]
  [ -f "$CC_PANE_CMD_DIR/42.cmd" ]
}

@test "a marker minted against ANOTHER kitty generation does not arm this one" {
  # A kitty window id is a per-process counter that restarts at 1, which is why the close path
  # already carries --expect-generation. The arm path now carries the same pin, for free: kitty
  # names its control socket after its own pid.
  export CC_TERM_KITTY_TO="unix:$BATS_TEST_TMPDIR/kitty-424242"
  printf '999999\n' > "$CC_PANE_CMD_DIR/42.armed"
  CC_KITTY_SPAWN_VERIFY_S=0 run "$K" session run -s 42 "hello"
  [ "$status" -eq 0 ]
  [ ! -f "$CC_PANE_CMD_DIR/42.cmd" ]
  grep -q -- 'send-text --match id:42' "$KLOG" || false
}

@test "CONTROL: the MATCHING generation still arms — the pin reads the value, not merely its presence" {
  export CC_TERM_KITTY_TO="unix:$BATS_TEST_TMPDIR/kitty-424242"
  printf '424242\n' > "$CC_PANE_CMD_DIR/42.armed"
  CC_KITTY_SPAWN_VERIFY_S=0 run "$K" session run -s 42 "hello"
  [ "$status" -eq 0 ]
  [ -f "$CC_PANE_CMD_DIR/42.cmd" ]
}

@test "an EMPTY legacy marker is judged on age alone — no generation is not a mismatch" {
  # Every marker written before this change carries no generation. Reading their absence as a
  # mismatch would retire the argv transport for every pane already armed at deploy time.
  export CC_TERM_KITTY_TO="unix:$BATS_TEST_TMPDIR/kitty-424242"
  arm 42                                            # empty, fresh
  CC_KITTY_SPAWN_VERIFY_S=0 run "$K" session run -s 42 "hello"
  [ "$status" -eq 0 ]
  [ -f "$CC_PANE_CMD_DIR/42.cmd" ]
}

# ── the leak at its source ───────────────────────────────────────────────────────────────────────

# A REAL shell stand-in, so "the runner fell back" is OBSERVED rather than inferred from an exit
# code. /bin/true would satisfy the exec and leave no evidence which path produced it.
fallback_shell() {
  cat > "$BATS_TEST_TMPDIR/fakeshell" <<SH
#!/bin/sh
: > "$BATS_TEST_TMPDIR/fellback"
exit 0
SH
  chmod +x "$BATS_TEST_TMPDIR/fakeshell"
}

@test "cc-pane-runner removes its own arming marker when it falls back to a shell" {
  # The runner consumed the marker only on the path where a command ARRIVED. Every other exit left
  # it on disk to answer for whatever LIVE pane later carried that id.
  fallback_shell
  : > "$CC_PANE_CMD_DIR/42.armed"
  SHELL="$BATS_TEST_TMPDIR/fakeshell" CC_PANE_CMD_DIR="$CC_PANE_CMD_DIR" KITTY_WINDOW_ID=42 \
    CC_PANE_CMD_WAIT_S=0 run bash "$RUNNER"
  [ -f "$BATS_TEST_TMPDIR/fellback" ]              # it really took the fallback path
  [ ! -f "$CC_PANE_CMD_DIR/42.armed" ]
}

@test "CONTROL: a marker for a DIFFERENT pane survives — the runner cleans its own, not the dir" {
  fallback_shell
  : > "$CC_PANE_CMD_DIR/42.armed"
  : > "$CC_PANE_CMD_DIR/43.armed"
  SHELL="$BATS_TEST_TMPDIR/fakeshell" CC_PANE_CMD_DIR="$CC_PANE_CMD_DIR" KITTY_WINDOW_ID=42 \
    CC_PANE_CMD_WAIT_S=0 run bash "$RUNNER"
  [ -f "$BATS_TEST_TMPDIR/fellback" ]
  [ ! -f "$CC_PANE_CMD_DIR/42.armed" ]
  [ -f "$CC_PANE_CMD_DIR/43.armed" ]
}

# ── the split stamps what armed() reads ──────────────────────────────────────────────────────────

@test "split writes the generation INTO the marker, so a later kitty cannot inherit it" {
  cat > "$CC_TERM_KITTY" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >> "$KLOG"
verb=""
for a in "$@"; do case "$a" in @|--to|unix:*) continue ;; *) verb="$a"; break ;; esac; done
case "$verb" in launch) echo 42 ;; esac
exit 0
SH
  chmod +x "$CC_TERM_KITTY"
  export CC_TERM_KITTY_TO="unix:$BATS_TEST_TMPDIR/kitty-424242"
  run "$K" session split -v -s 7
  [ "$status" -eq 0 ]
  [ -f "$CC_PANE_CMD_DIR/42.armed" ]
  run head -n 1 "$CC_PANE_CMD_DIR/42.armed"
  [ "$output" = "424242" ]
}
