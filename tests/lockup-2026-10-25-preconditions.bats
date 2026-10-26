#!/usr/bin/env bats
# The 2026-10-25 /dev wedge: its three preconditions in our own code are gone.
#
# THE INCIDENT (~/incident-2026-10-25/RCA.md §1; FIX-DESIGN §8 of docs/research/husk-history-2026-10-24).
# A pty test driver exited after its budget without killing its child, so the master closed under a
# held bin/cc-pane-runner. The runner's `trap ''` was inherited by its painter, whose subshell then
# opened the pane's pty slave BY PATH (`stty size < "$TTYP"` in bin/cc-pane-verdict) and slept in the
# kernel waiting for a carrier. A teammate's kill of the runner by pid made its exit revoke the tty,
# and the revoke waited forever on that sleeping open: every /dev lookup of the node hung for 9 h.
#
# Each arm proves a precondition is absent; none of them builds the deadlock. No arm opens a pty
# slave whose master is closed, and no arm kills a pty session leader while an open of its slave is in
# progress. The blocking-open arm uses a FIFO with no reader, which blocks a plain open() exactly as a
# carrier-less pty slave does and is released by O_NONBLOCK exactly as that is.
#   1. children of the runner start with default dispositions for HUP INT QUIT TERM TSTP, even when
#      the runner itself was launched with some of them ignored;
#   2. cc-pane-verdict never opens a tty path without O_NONBLOCK, and paints through an fd it is given;
#   3. the pty test driver leaves no member of its child's process group alive on any exit path;
#   4. a held runner ends when its pty master closes, and names its tty without a /dev walk (§ 4).
# Each arm is RED on the pre-fix tree (751b2ed5f); the TAPs of both runs are in the commit body.
# CC_PTY_DRIVER points arm 3 at another copy of the driver (the pre-fix replay).

load helpers/cc-stub

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  RUNNER="$REPO/bin/cc-pane-runner"
  VERDICT="$REPO/bin/cc-pane-verdict"
  DRIVER="${CC_PTY_DRIVER:-$REPO/tests/helpers/cc-pane-pty-driver.py}"
  T="$BATS_TEST_TMPDIR"
  S="$T/stub"
  export HOME="$T/home"; mkdir -p "$HOME" "$T/locks" "$T/q" "$T/cmd"
  export T LR_LOCKS_DIR="$T/locks" CC_PANE_CLOSE_QUEUE_DIR="$T/q"
  export KITTY_WINDOW_ID=289 CC_PANE_WEDGE_WATCH=0 CC_PANE_HOLD_STEP_S=0
  export CC_PANE_EXIT_DIR="$T/pane-exit" CC_REGISTRY_DIR="$T/reg" CC_BEAT_DIR="$T/beats"
  export CC_PANE_VERDICT_DIR="$T/pv" CC_PANE_VERDICT_KITTY_BIN="$S/kittybin"
  unset KITTY_LISTEN_ON CC_TERM_KITTY_TO CC_PANE_CLOSE_ON_EXIT CC_PANE_CMD_INTERACTIVE CC_PANE_CMD_DIR
  unset CC_PANE_RUNNER_OWNS_CLOSE KITTY_PID LR_RUN_DIR CC_PANE_STARTED_FILE CC_PANE_EXIT_OWED
  unset CC_PANE_HOLD_MAX_POLLS CC_PANE_RUNNER_TTY CC_SAY_LOG
  export PATH="$S:/usr/bin:/bin" CC_PANE_CMD=claude
  # The guard is the child the runner starts after the command returns: it records what it inherited.
  cc_stub "$S" fsguard '#!/bin/bash
/usr/bin/python3 -I -c "
import signal as s
print(\" \".join(\"%s=%s\" % (n, \"IGN\" if s.getsignal(getattr(s, \"SIG\" + n)) == s.SIG_IGN else \"ok\") for n in (\"HUP\", \"INT\", \"QUIT\", \"TERM\", \"TSTP\")))
" >> "$T/dispo"
exit 0'
  export CC_KITTY_FS_GUARD="$S/fsguard"
  cc_stub "$S" claude '#!/bin/bash
exit 0'
  cc_stub "$S" fakeshell '#!/bin/bash
: > "$T/shell-ran"
exit 7'
  cc_stub "$S" kittybin '#!/bin/bash
exit 1'
  export SHELL="$S/fakeshell"
}

teardown() {
  local f p
  for f in "$T/pty-child-pid" "$T/leader" "$T/grandchild"; do
    p="$(cat "$f" 2>/dev/null)"
    case "$p" in ''|*[!0-9]*) ;; *) kill -KILL -- "-$p" 2>/dev/null || true; kill -KILL "$p" 2>/dev/null || true ;; esac
  done
  if [ -n "${dpid:-}" ]; then kill -KILL "$dpid" 2>/dev/null || true; fi
  return 0
}

wait_until() { local n=$(( $1 * 10 )); shift; until "$@"; do n=$((n - 1)); [ "$n" -gt 0 ] || return 1; /bin/sleep 0.1; done; }
gone() { ! kill -0 "$1" 2>/dev/null; }
now() { /usr/bin/perl -MTime::HiRes=time -e 'printf "%.1f\n", time'; }

# ── 1. no child of the runner inherits an ignored signal ─────────────────────────────────────────

@test "1a: the guard the runner starts after the command returns inherits no ignored HUP INT QUIT TERM TSTP" {
  run "$RUNNER"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -s "$T/dispo" ] || { echo "the runner never asked the guard"; false; }
  run cat "$T/dispo"
  echo "# $(head -n 1 "$T/dispo")" >&3
  [[ "$output" != *IGN* ]] || { echo "inherited an ignore: $output"; false; }
}

@test "1b: launched with HUP, TERM and INT already ignored (nohup, a background job), its children still get defaults" {
  run /usr/bin/perl -e '$SIG{$_} = "IGNORE" for qw(HUP TERM INT); exec { $ARGV[0] } @ARGV' "$RUNNER"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  run cat "$T/dispo"
  [ -n "$output" ] || { echo "the runner never asked the guard"; false; }
  [[ "$output" != *IGN* ]] || { echo "inherited an ignore: $output"; false; }
}

# ── 2. no blocking open of a tty by path ────────────────────────────────────────────────────────

@test "2a: cc-pane-verdict handed a path nobody has open returns at once — it never waits in open()" {
  mkfifo "$T/fifo"
  t0="$(now)"
  run /usr/bin/perl -e 'alarm 20; exec { $ARGV[0] } @ARGV' "$VERDICT" --pane 7 --state DONE --tty "$T/fifo"
  t1="$(now)"
  [ "$status" -eq 0 ] || { echo "status $status (142 = still blocked in open after 20 s): $output"; false; }
  /usr/bin/perl -e 'exit($ARGV[1] - $ARGV[0] < 10 ? 0 : 1)' "$t0" "$t1" || { echo "took $t0 → $t1"; false; }
}

@test "2b: cc-pane-verdict paints through the fd it is handed (--tty-fd), opening no path" {
  : > "$T/screen"
  run "$VERDICT" --pane 7 --state DONE --tty-fd 3 3>>"$T/screen"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -qF 'finished · nothing to resume' "$T/screen" || { cat -v "$T/screen"; false; }
}

@test "2d: a tty fd that never takes the paint (a full pipe) is abandoned within its bound, never waited on" {
  mkfifo "$T/full"
  exec 4<>"$T/full"
  # fill the pipe, then make the fd blocking again so the painter's write would wait forever
  /usr/bin/perl -e 'use Fcntl; my $f = fcntl(STDOUT, F_GETFL, 0); fcntl(STDOUT, F_SETFL, $f | O_NONBLOCK);
    1 while syswrite(STDOUT, "x" x 512); fcntl(STDOUT, F_SETFL, $f)' >&4
  t0="$(now)"
  # two abandons (paint, title) of about 5 s each; the alarm only tells "returned" from "waited forever"
  run /usr/bin/perl -e 'alarm 120; exec { $ARGV[0] } @ARGV' "$VERDICT" --pane 7 --state DONE --tty-fd 4
  t1="$(now)"
  exec 4>&-
  [ "$status" -eq 0 ] || { echo "status $status (142 = the painter waited on the write): $output"; false; }
  /usr/bin/perl -e 'exit($ARGV[1] - $ARGV[0] < 60 ? 0 : 1)' "$t0" "$t1" || { echo "took $t0 → $t1"; false; }
  echo "# took $(/usr/bin/perl -e 'printf "%.1f", $ARGV[1] - $ARGV[0]' "$t0" "$t1") s" >&3
}

@test "2c: STRUCTURAL: neither file opens a tty variable by shell redirection, and the runner's painter call asks no tty(1)" {
  run grep -nE '(<|>|<>)[[:space:]]*"?\$\{?(TTYP|TTY|tty|CC_PANE_RUNNER_TTY)\b' "$VERDICT" "$RUNNER"
  hits="$(printf '%s\n' "$output" | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' || true)"
  [ -z "$hits" ] || { echo "a redirection opens a tty by path: $hits"; false; }
  run awk '/^_verdict\(\) \{/{f=1} f&&/\$\(tty/{print} f&&/^\}/{exit}' "$RUNNER"
  [ -z "$output" ] || { echo "_verdict walks /dev through tty(1): $output"; false; }
}

# ── 3. the pty test driver kills its child's process group on every exit path ───────────────────
# The stub "runner" never holds, and starts a member of its group that ignores HUP/TERM/INT, as the
# painter's subshell did, but holds no pty fd at all (stdio on /dev/null). The stub itself keeps
# default dispositions, so even the pre-fix driver's replay never leaves a signal-immune leader on a
# closed master, and nothing here opens the slave.

_stub_runner() {
  printf '%s\n' '#!/bin/bash' \
    'echo "$$" > "$T/leader"' \
    "( trap '' HUP TERM INT; exec /bin/sleep 120 ) </dev/null >/dev/null 2>&1 &" \
    'echo "$!" > "$T/grandchild"' \
    'wait' > "$T/stub-runner"
}

@test "3a: the driver's start-up timeout leaves no member of its child's group alive" {
  /usr/bin/python3 -I -c 'import pty' 2>/dev/null || skip "no python3 pty module (an environment precondition)"
  _stub_runner
  PTY_DRIVER_START_S=2 run /usr/bin/perl -e 'alarm 60; exec { $ARGV[0] } @ARGV' /usr/bin/python3 -I "$DRIVER" "$T/stub-runner"
  [ "$status" -ne 0 ] || { echo "the driver passed a runner that never held: $output"; false; }
  [[ "$output" == *"never held"* ]] || { echo "$output"; false; }
  g="$(cat "$T/grandchild")"
  wait_until 5 gone "$g" || { echo "pid $g of the child's group outlived the driver"; false; }
}

@test "3b: a driver ended by SIGTERM (a bats timeout) leaves no member of its child's group alive" {
  /usr/bin/python3 -I -c 'import pty' 2>/dev/null || skip "no python3 pty module (an environment precondition)"
  _stub_runner
  PTY_DRIVER_START_S=60 /usr/bin/perl -e 'alarm 60; exec { $ARGV[0] } @ARGV' /usr/bin/python3 -I "$DRIVER" "$T/stub-runner" >"$T/drv-out" 2>&1 &
  dpid=$!
  wait_until 20 test -s "$T/grandchild" || { echo "the stub never started"; cat "$T/drv-out"; false; }
  kill -TERM "$dpid"
  wait_until 10 gone "$dpid" || { echo "the driver ignored TERM"; false; }
  g="$(cat "$T/grandchild")"
  wait_until 5 gone "$g" || { echo "pid $g of the child's group outlived the driver"; false; }
}

# ── 4. a held runner lets go of a dead tty, and never walks /dev for its name (lane F2) ─────────────
# RCA R2, second half: the held runner did not notice its master was gone and held on a dead tty
# until the guard or KITTY_PID let go. 4a closes the master of a REAL held runner on purpose; nothing
# in it opens the slave (the painter paints a file through CC_PANE_RUNNER_TTY, the guard opens no tty),
# and CC_PANE_HOLD_MAX_POLLS ends even the pre-fix runner by itself. RED on 1bceb92c0 (TAPs in the
# commit body): 4a reads exit=7 tail=keep:fallback, 4b and 4c find tty(1) asked.

_refusing_guard() { # every refuse-mode ask: the last pane of a fullscreen window
  cc_stub "$S" fsguard '#!/bin/bash
printf "%s\n" "$*" >> "$T/guard-log"
echo "kitty-fullscreen-guard: refused (refused-fs) kitty window 289 scope=pane mode=refuse: state=FS" >&2
exit 3'
}
_tty_spy() { # tty(1) on PATH: asking it is the defect; its answer is a name no pty has
  cc_stub "$S" tty '#!/bin/bash
: > "$T/tty-asked"
echo /dev/ttys-from-tty1'
}

@test "4a: a held runner whose pty master closes ends the hold as master-lost and execs no shell" {
  /usr/bin/python3 -I -c 'import pty' 2>/dev/null || skip "no python3 pty module (an environment precondition)"
  _refusing_guard
  export CC_PANE_HOLD_STEP_S=1 CC_PANE_HOLD_MAX_POLLS=4 CC_PANE_RUNNER_TTY="$T/tty"; : > "$T/tty"
  PTY_DRIVER_MODE=master-lost PTY_DRIVER_START_S=120 PTY_DRIVER_LOST_S=120 \
    run /usr/bin/perl -e 'alarm 300; exec { $ARGV[0] } @ARGV' /usr/bin/python3 -I "$DRIVER" "$RUNNER"
  echo "# $output" >&3
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == "exit=0 tail=master-lost after "* ]] || { echo "$output"; false; }
  [ ! -e "$T/shell-ran" ] || { echo "a shell was exec'd onto the dead tty"; false; }
}

@test "4b: a kept pane's husk row names its tty from fd 0, without asking tty(1)" {
  /usr/bin/python3 -I -c 'import pty' 2>/dev/null || skip "no python3 pty module (an environment precondition)"
  cc_stub "$S" fsguard '#!/bin/bash
exit 2'
  _tty_spy
  export CC_PANE_RUNNER_TTY="$T/tty"; : > "$T/tty"
  PTY_DRIVER_MODE=exit PTY_DRIVER_START_S=120 \
    run /usr/bin/perl -e 'alarm 300; exec { $ARGV[0] } @ARGV' /usr/bin/python3 -I "$DRIVER" "$RUNNER"
  [[ "$output" == "exit=7 after "* ]] || { echo "$output"; false; }
  [ ! -e "$T/tty-asked" ] || { echo "_husk_row asked tty(1), a /dev walk"; false; }
  want="$(cat "$T/pty-slave-path")"
  [ -n "$want" ] || { echo "the driver's child recorded no slave path"; false; }
  run jq -r .tty "$T/q/husk-289.json"
  [ "$output" = "$want" ] || { echo "row tty [$output], slave [$want]"; false; }
}

@test "4c: with no tty on fd 0 the row's tty is empty and tty(1) is not asked" {
  cc_stub "$S" fsguard '#!/bin/bash
exit 2'
  _tty_spy
  run "$RUNNER" </dev/null
  [ "$status" -eq 7 ] || { echo "$output"; false; }
  [ ! -e "$T/tty-asked" ] || { echo "_husk_row asked tty(1), a /dev walk"; false; }
  run jq -r .tty "$T/q/husk-289.json"
  [ "$output" = "" ] || { echo "row tty [$output]"; false; }
}
