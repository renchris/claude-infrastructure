#!/usr/bin/env bats
# bin/cc-pane-runner — a clean exit the fullscreen guard refuses HOLDS, then closes itself (W1a).
#
# THE DEFECT (pane 289, docs/research/husk-history-2026-10-24/FIX-DESIGN.md). A fleet session exited
# cleanly as the last pane of a native-fullscreen window; kitty-fullscreen-guard refused the close
# (rightly: emptying that window crashes kitty), and the runner fell back to a login shell — a husk
# that nothing would ever close, because every later closer meets the same refusal. Now the runner
# stays the pane's process, ignores INT/QUIT/TSTP/TERM/HUP from the command's return on, re-asks the
# guard, and exits 0 only after two consecutive safe reads (rc 0|4), a clear `--any-fs` read on a
# deaf kitty, or once kitty itself is gone. A guard that cannot answer, or the poll budget, escapes
# to `keep:fallback` and a shell (FIX-DESIGN §2 invariant 1, D1-D3).
#
# Arms are the unit forms of FIX-DESIGN §5 A1/A1b/A1x/A1k/A1t plus A1u (D3), A1e (break 5), A1a
# (break 7) and A1g (break 4). Hermetic: the guard, the fallback shell, claude and kitty are stubs.
# The guard stub reads $T/guard-seq — one `rc<TAB>stderr` line per refuse-mode call, the last line
# repeating — and logs every argv; `--any-fs` calls answer $T/anyfs-rc (default 0) and do not
# consume the sequence.

load helpers/cc-stub

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  RUNNER="$REPO/bin/cc-pane-runner"
  T="$BATS_TEST_TMPDIR"
  S="$T/stub"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  mkdir -p "$T/locks" "$T/q" "$T/cmd"
  export T LR_LOCKS_DIR="$T/locks" CC_PANE_CLOSE_QUEUE_DIR="$T/q"
  export KITTY_WINDOW_ID=289 CC_PANE_WEDGE_WATCH=0 CC_PANE_HOLD_STEP_S=0
  export CC_PANE_EXIT_DIR="$T/pane-exit" CC_REGISTRY_DIR="$T/reg" CC_BEAT_DIR="$T/beats"
  export CC_PANE_VERDICT_DIR="$T/pv" CC_PANE_VERDICT_KITTY_BIN="$S/kittybin"
  unset KITTY_LISTEN_ON CC_TERM_KITTY_TO CC_PANE_CLOSE_ON_EXIT CC_PANE_CMD_INTERACTIVE CC_PANE_CMD CC_PANE_CMD_DIR
  unset CC_PANE_RUNNER_OWNS_CLOSE KITTY_PID LR_RUN_DIR CC_PANE_STARTED_FILE CC_PANE_EXIT_OWED
  unset CC_PANE_HOLD_MAX_POLLS CC_PANE_RUNNER_TTY GUARD_ARMED GUARD_SLEEP1 CC_SAY_LOG
  export PATH="$S:/usr/bin:/bin"
  SAY="$HOME/.claude/logs/pane-say.jsonl"
  cc_stub "$S" fsguard '#!/bin/bash
printf "%s\n" "$*" >> "$T/guard-log"
case " $* " in *" --any-fs "*) exit "$(cat "$T/anyfs-rc" 2>/dev/null || echo 0)" ;; esac
n=$(( $(cat "$T/guard-n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$T/guard-n"
if [ -n "${GUARD_ARMED:-}" ]; then if [ -e "$GUARD_ARMED" ]; then echo present; else echo absent; fi >> "$T/guard-armed"; fi
[ "$n" = 1 ] && [ -n "${GUARD_SLEEP1:-}" ] && /bin/sleep "$GUARD_SLEEP1"
[ -e "$T/release" ] && exit 0
line="$(sed -n "${n}p" "$T/guard-seq")"; [ -n "$line" ] || line="$(tail -n 1 "$T/guard-seq")"
rc="${line%%	*}"; err="${line#*	}"; [ "$err" = "$line" ] && err=""
[ -n "$err" ] && printf "%s\n" "$err" >&2
exit "$rc"'
  export CC_KITTY_FS_GUARD="$S/fsguard"
  cc_stub "$S" claude '#!/bin/bash
echo "$PPID" > "$T/runner-pid"
exit "${STUB_RC:-0}"'
  cc_stub "$S" fakeshell '#!/bin/bash
: > "$T/shell-ran"
exit 7'
  cc_stub "$S" kittybin '#!/bin/bash
printf "%s\n" "$*" >> "$T/kitty-log"'
  export SHELL="$S/fakeshell"
}

# guard answers, one per refuse-mode call: 0 · 2 · 3fs (last pane of a fullscreen window) ·
# 3unreadable (a read that failed) · 3kf (the kitten itself failed: remote control down)
seq_guard() {
  local a; : > "$T/guard-seq"
  for a; do
    case "$a" in
      3fs) printf '3\tkitty-fullscreen-guard: refused (refused-fs) kitty window 289 scope=pane mode=refuse: state=FS types=[4] onscreen=True\n' ;;
      3unreadable) printf '3\tkitty-fullscreen-guard: refused (refused-unknown) kitty window 289 scope=pane mode=refuse: state=UNKNOWN types=None\n' ;;
      3kf) printf '3\tkitty-fullscreen-guard: refused (kitten-failed) could not read kitty window 289: timed out\n' ;;
      *) printf '%s\t\n' "$a" ;;
    esac >> "$T/guard-seq"
  done
}
run_runner() { CC_PANE_CMD=claude run "$RUNNER"; }
refuse_calls() { grep -vc -- '--any-fs' "$T/guard-log"; }
tail_is() { [ "$(jq -r .tail "$CC_PANE_EXIT_DIR/289.json")" = "$1" ] || { cat "$CC_PANE_EXIT_DIR/289.json"; false; }; }
said() { grep -qF -- "$1" "$SAY" || { echo "not in the cc-say log: $1"; cat "$SAY" 2>/dev/null; false; }; }
rows() { find "$T/q" -name 'husk-*.json' | wc -l | tr -d ' '; }
# poll a condition for up to $1 seconds (tenths) — a background runner has no `run` to wait on
wait_until() { local n=$(( $1 * 10 )); shift; until "$@"; do n=$((n - 1)); [ "$n" -gt 0 ] || return 1; /bin/sleep 0.1; done; }
alive() { kill -0 "$1" 2>/dev/null; }
gone() { ! kill -0 "$1" 2>/dev/null; }
held() { [ -s "$CC_PANE_EXIT_DIR/289.json" ] && [ "$(jq -r '.tail // empty' "$CC_PANE_EXIT_DIR/289.json")" = "$1" ]; }
not_stopped() { case "$(ps -o stat= -p "$1" 2>/dev/null)" in T*) return 1 ;; esac; }

@test "A1: a refused clean exit holds, then closes after two safe reads — never a shell, never resume" {
  seq_guard 3fs 3fs 0 0
  run_runner
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ ! -e "$T/shell-ran" ]
  [ "$(refuse_calls)" = 4 ]
  [ "$(sed -n 1p "$T/guard-log")" = "--window 289 --mode refuse --scope pane --tool cc-pane-runner" ]
  [ "$(sed -n '2,4p' "$T/guard-log" | sort -u)" = "--window 289 --mode refuse --scope pane --tool cc-pane-hold" ]
  tail_is closed
  [ "$(jq -r .rc "$CC_PANE_EXIT_DIR/289.json")" = 0 ]
  [[ "$output" == *"done · closes itself when safe"*"⌘W closes it now"* ]] || { echo "$output"; false; }
  said "held: closes itself when safe"
  [ "$(rows)" = 0 ]
  printf '%s\n' "$output" > "$T/out"
  run grep -E 'RESUME|resume|stopped mid-task' "$SAY" "$T/out"
  [ "$status" -eq 1 ]
}

@test "A1 painted: with a tty the hold is painted as DONE through cc-pane-verdict, never RESUME" {
  export CC_PANE_RUNNER_TTY="$T/tty"; : > "$CC_PANE_RUNNER_TTY"
  seq_guard 3fs 0 0
  run_runner
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -qF 'finished · nothing to resume' "$T/tty" || { cat -v "$T/tty"; false; }
  [[ "$output" != *"closes itself when safe"* ]] || { echo "the runner added a line over the paint: $output"; false; }
  run grep -E 'RESUME|stopped mid-task' "$T/tty"
  [ "$status" -eq 1 ]
}

@test "A1b: the first safe read does not release — a refusal between resets the count" {
  seq_guard 3fs 0 3fs 0 0
  run_runner
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(refuse_calls)" = 5 ]
  [ ! -e "$T/shell-ran" ]
  tail_is closed
}

@test "A1b: rc 4 (the window is gone) counts as a safe read" {
  seq_guard 3fs 4 4
  run_runner
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(refuse_calls)" = 3 ]
  tail_is closed
}

@test "A1x: the poll budget spent, the hold escapes to keep:fallback — a shell and one retry row" {
  seq_guard 3fs
  CC_PANE_HOLD_MAX_POLLS=2 run_runner
  [ "$status" -eq 7 ] || { echo "$output"; false; }
  [ -e "$T/shell-ran" ]
  tail_is keep:fallback
  [ "$(refuse_calls)" = 3 ]
  [ "$(rows)" = 1 ]
  [ "$(jq -r .reason "$T/q/husk-289.json")" = runner-escape ]
  [[ "$output" == *"the runner ended unexpectedly"* ]] || { echo "$output"; false; }
}

@test "A1k: kitty itself gone (KITTY_PID reaped) ends the hold at the first poll — closed, no shell" {
  /usr/bin/true & dead=$!; wait "$dead"
  seq_guard 3unreadable
  KITTY_PID="$dead" CC_PANE_HOLD_MAX_POLLS=3 run_runner
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(refuse_calls)" = 1 ]
  [ ! -e "$T/shell-ran" ]
  tail_is closed
}

@test "A1u: a kitten-failed read asks --any-fs for this kitty, and a clear answer counts as safe" {
  seq_guard 3kf
  KITTY_PID=$$ CC_PANE_HOLD_MAX_POLLS=5 run_runner
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ ! -e "$T/shell-ran" ]
  tail_is closed
  [ "$(grep -c -- "^--any-fs --kitty-pid $$ --tool cc-pane-hold$" "$T/guard-log")" = 2 ]
  # the gate itself never asks --any-fs: only the hold does
  [ "$(sed -n 1p "$T/guard-log")" = "--window 289 --mode refuse --scope pane --tool cc-pane-runner" ]
}

@test "A1u control: an --any-fs read that is NOT clear keeps holding" {
  seq_guard 3kf; echo 3 > "$T/anyfs-rc"
  KITTY_PID=$$ CC_PANE_HOLD_MAX_POLLS=2 run_runner
  [ "$status" -eq 7 ]
  tail_is keep:fallback
  [ "$(grep -c -- '^--any-fs' "$T/guard-log")" = 2 ]
}

@test "A1e: a guard that cannot answer during the hold (rc 2) escapes to keep:fallback and a shell" {
  seq_guard 3fs 2
  CC_PANE_HOLD_MAX_POLLS=5 run_runner
  [ "$status" -eq 7 ] || { echo "$output"; false; }
  [ -e "$T/shell-ran" ]
  tail_is keep:fallback
  [ "$(refuse_calls)" = 2 ]
}

@test "A1e gate: a guard that cannot answer at the gate keeps the shell (keep:no-guard) with a row" {
  seq_guard 2
  run_runner
  [ "$status" -eq 7 ]
  tail_is keep:no-guard
  [ "$(jq -r .reason "$T/q/husk-289.json")" = no-guard ]
  [[ "$output" == *"pane kept, not closed · fullscreen guard failed"* ]] || { echo "$output"; false; }
}

@test "A1a: the arming marker is gone before the guard is asked (no-command deadline)" {
  : > "$T/cmd/289.armed"
  seq_guard 3fs 0 0
  GUARD_ARMED="$T/cmd/289.armed" CC_PANE_CMD_DIR="$T/cmd" CC_PANE_CMD_WAIT_S=0 run "$RUNNER"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(sort -u "$T/guard-armed")" = absent ] || { cat "$T/guard-armed"; false; }
  tail_is closed
  [ "$(jq -r .rc "$CC_PANE_EXIT_DIR/289.json")" = 124 ]
}

@test "A1g: TERM then INT to the runner's process group while the guard decides — it survives and holds" {
  seq_guard 3fs 0 0
  export GUARD_SLEEP1=3 CC_PANE_CMD=claude
  set -m
  "$RUNNER" </dev/null >"$T/out" 2>&1 &
  pid=$!
  set +m
  wait_until 10 test -s "$T/guard-log" || { echo "the gate never asked the guard"; false; }
  kill -TERM -- "-$pid"; /bin/sleep 0.3
  kill -INT -- "-$pid"; /bin/sleep 0.3
  alive "$pid" || { echo "the runner died in the gate"; cat "$T/out"; false; }
  st=0; wait "$pid" || st=$?
  [ "$st" -eq 0 ] || { echo "status $st"; cat "$T/out"; false; }
  [ ! -e "$T/shell-ran" ]
  [ "$(refuse_calls)" = 3 ]
  tail_is closed
}

@test "A1t: a held runner survives TERM, INT, HUP, QUIT and TSTP, and closes once safe" {
  seq_guard 3fs
  export CC_PANE_HOLD_STEP_S=1 CC_PANE_CMD=claude
  "$RUNNER" </dev/null >"$T/out" 2>&1 &
  pid=$!
  wait_until 10 held hold:fs || { echo "never held"; cat "$T/out"; false; }
  for sig in TERM INT HUP QUIT TSTP; do
    kill -s "$sig" "$pid"; /bin/sleep 0.3
    alive "$pid" || { echo "died on SIG$sig"; cat "$T/out"; false; }
    not_stopped "$pid" || { echo "stopped by SIG$sig"; kill -CONT "$pid"; false; }
  done
  : > "$T/release"
  wait_until 10 gone "$pid" || { echo "still held 10 s after release"; false; }
  st=0; wait "$pid" || st=$?
  [ "$st" -eq 0 ] || { echo "status $st"; cat "$T/out"; false; }
  [ ! -e "$T/shell-ran" ]
  tail_is closed
}

# The keys typed at a held pane, through a real pty whose foreground group is the runner. Driven by
# python's pty module, not script(1): macOS script refuses a non-tty stdin ("tcgetattr/ioctl:
# Operation not supported on socket") and exits at once, so it cannot be typed into from a test.
PTY_DRIVER='
import json, os, pty, select, sys, time
T, runner = os.environ["T"], sys.argv[1]
pid, fd = pty.fork()
if pid == 0:
    os.execv("/bin/bash", ["/bin/bash", runner])
def drain():
    while select.select([fd], [], [], 0)[0]:
        try:
            os.read(fd, 4096)
        except OSError:
            return
def tail():
    try:
        return json.load(open(T + "/pane-exit/289.json")).get("tail")
    except Exception:
        return None
def ended():
    p, st = os.waitpid(pid, os.WNOHANG | os.WUNTRACED)
    return None if p == 0 else st
end = time.time() + 10
while tail() != "hold:fs":
    drain(); time.sleep(0.1)
    if time.time() > end:
        sys.exit("never held")
for ch in (b"\x03", b"\x1c", b"\x1a"):
    os.write(fd, ch); time.sleep(0.3); drain()
    st = ended()
    if st is not None:
        sys.exit("ended or stopped by %r: wait status %d" % (ch, st))
open(T + "/release", "w").close()
end = time.time() + 10
while True:
    drain(); st = ended()
    if st is not None:
        break
    if time.time() > end:
        sys.exit("still held 10 s after release")
    time.sleep(0.1)
print("exit=%d" % os.waitstatus_to_exitcode(st))
'

@test "A1t pty: ^C ^\\ ^Z typed at the held pane's terminal do not end or stop it" {
  /usr/bin/python3 -I -c 'import pty' 2>/dev/null || skip "no python3 pty module to type through (an environment precondition)"
  seq_guard 3fs
  export CC_PANE_HOLD_STEP_S=1 CC_PANE_CMD=claude
  run /usr/bin/python3 -I -c "$PTY_DRIVER" "$RUNNER"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" = "exit=0" ] || { echo "$output"; false; }
  [ ! -e "$T/shell-ran" ]
  tail_is closed
}

@test "the command sees CC_PANE_RUNNER_OWNS_CLOSE = this pane's window id" {
  cc_stub "$S" claude '#!/bin/bash
printf "%s\n" "${CC_PANE_RUNNER_OWNS_CLOSE:-}" > "$T/owns"
exit 0'
  seq_guard 0
  run_runner
  [ "$status" -eq 0 ]
  [ "$(cat "$T/owns")" = 289 ]
}

# ── STRUCTURE: the shapes the invariants rest on ────────────────────────────────────────────────

@test "STRUCTURAL: exactly one exec of a shell in the runner, and it is _fallback's" {
  [ "$(grep -c 'exec "${SHELL' "$RUNNER")" = 1 ]
  run awk '/^_fallback\(\) \{/{f=1} f&&/exec "\$\{SHELL/{print "in-fallback"} f&&/^\}/{exit}' "$RUNNER"
  [ "$output" = in-fallback ]
  # and _fallback gives the shell back its signals before it execs
  run awk '/^_fallback\(\) \{/{getline; print; exit}' "$RUNNER"
  [ "$output" = "  trap - INT QUIT TSTP TERM HUP EXIT" ]
}

@test "STRUCTURAL: every post-launch _fallback is preceded by a keep: tail write" {
  # Post-launch = inside a function (the three top-level _fallback calls run before any command and
  # leave no record). Each such call needs, earlier in its function, a _pane_exit_tail whose argument
  # is a keep: literal — or _end's "$_TAIL", whose arms leave only keep:* to reach the call.
  run awk '
    /^[a-z_]+\(\) *\{/ { fn=$1; sub(/\(\).*/, "", fn); kept=0; tailv=0 }
    /^\}/ { fn="" }
    fn != "" && fn != "_fallback" && /_pane_exit_tail keep:/ { kept=1 }
    fn == "_end" && /_pane_exit_tail "\$_TAIL"/ { tailv=1 }
    fn == "_end" && /^    \*\) _TAIL=keep:fallback; _pane_exit_tail keep:fallback/ { kept=1 }
    fn != "" && fn != "_fallback" && /(^|[;{ ])_fallback( |$)/ && !/^[[:space:]]*#/ {
      n++; if (!(kept || (fn == "_end" && tailv))) { print "UNKEPT " fn ": " $0; bad=1 } }
    END { print "post-launch=" n; exit bad }' "$RUNNER"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" = "post-launch=2" ] || { echo "$output"; false; }
  # _end's fall-through is keep:* only: closed exits, hold:* exits, any other value is rewritten
  run awk '/^_end\(\) \{/{f=1} f&&/^\}/{exit} f' "$RUNNER"
  [[ "$output" == *'closed)'*'_DONE=1; exit 0 ;;'* ]] || false
  [[ "$output" == *'hold:*) _hold "${_TAIL#hold:}"; exit 1 ;;'* ]] || false
  [[ "$output" == *'*) _TAIL=keep:fallback; _pane_exit_tail keep:fallback;'* ]] || false
}

@test "STRUCTURAL: the decision path sets the traps right after the command returns" {
  run grep -cE '_rc=\$\?; _guarded$' "$RUNNER"
  [ "$output" = 2 ]
  run awk '/^_no_command\(\) \{/{getline; print; exit}' "$RUNNER"
  [ "$output" = "  _guarded" ]
}
