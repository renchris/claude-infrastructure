# shellcheck shell=bash
# pty-reap.bash — no process a test spawned on a pty outlives the test (incident 2026-10-25).
#
# THE HAZARD (~/incident-2026-10-25/RCA.md §1; lane-F hitlist, the lr-fire-resume expect row). Under
# `timeout N expect …`, a timeout kills expect, which closes the pty master; the program expect spawned
# gets only the hangup that close sends. A stub that ignores HUP then lives on with a dead tty, which
# is half of the deadlock that wedged /dev for 9 h: the other half is anything that later opens that
# slave by path (it sleeps for a carrier that never comes) and a kill of the session leader (its
# revoke waits on that open forever). So:
#
#   pty_timeout SECS CMD…   timeout(1) for CMD that spawns on a pty (expect). On expiry it kills, by
#                           process group, every descendant of CMD that leads a group of its own
#                           (expect's spawn calls setsid, so its child does) WHILE CMD STILL HOLDS THE
#                           MASTER, then CMD itself; rc 124, as timeout(1). Otherwise CMD's rc. Its
#                           stdin is CMD's stdin (a pipe into it works).
#   pty_reap                for teardown: every process whose argv names "$BATS_TEST_TMPDIR/" dies,
#                           by its process group, members first and the leader last, once they are
#                           gone. That is the order that never leaves a leader's revoke waiting on a
#                           member. By then the master may be closed, which is why pty_timeout runs
#                           first where it can. A process in the group of this shell or an ancestor
#                           (no pty session leader there) is killed alone; this shell and its
#                           ancestors never.
#
# Neither ever kills a bare session-leader pid, opens a tty, or walks /dev: pgrep and `ps -o pgid=
# -p <one pid>` read the process table only. An empty or relative BATS_TEST_TMPDIR selects nothing.

_pty_pgid() { ps -o pgid= -p "$1" 2>/dev/null | tr -d ' '; }

_pty_descendants() { # PID → every descendant pid, one per line
  local c
  for c in $(pgrep -P "$1" 2>/dev/null); do
    echo "$c"
    _pty_descendants "$c"
  done
}

_pty_kill_group() { # PGID: SIGKILL its members, wait them out (2 s), then the leader through the group
  local g="$1" m n=20
  case "$g" in '' | *[!0-9]* | 0 | 1) return 0 ;; esac
  for m in $(pgrep -g "$g" 2>/dev/null); do
    [ "$m" = "$g" ] || kill -KILL "$m" 2>/dev/null || true
  done
  while [ "$n" -gt 0 ] && pgrep -g "$g" 2>/dev/null | grep -qvx "$g"; do
    n=$((n - 1))
    /bin/sleep 0.1
  done
  kill -KILL -- "-$g" 2>/dev/null || true
  return 0
}

_pty_reap_spawns() { # PID: kill each process group a descendant of PID leads, PID's own group excepted
  # Deepest first: an expect spawned by expect holds the master of the stub below it, so the stub's
  # group dies while that master is still open, and then the inner expect's.
  local own p g seen=" " order=""
  own="$(_pty_pgid "$1")"
  for p in $(_pty_descendants "$1"); do
    g="$(_pty_pgid "$p")"
    [ -n "$g" ] && [ "$g" != "$own" ] || continue
    case "$seen" in *" $g "*) continue ;; esac
    seen="$seen$g "
    order="$g $order"
  done
  for g in $order; do _pty_kill_group "$g"; done
}

_pty_watchdog() { # SECS PID FLAG: after SECS, mark FLAG, kill PID's spawn groups, then PID
  local s p
  trap 'kill "$s" 2>/dev/null; exit 0' TERM
  /bin/sleep "$1" &
  s=$!
  wait "$s" || exit 0
  : >"$3"
  _pty_reap_spawns "$2"
  # What is left shares the test's group (no pty session leader can be there): TERM it deepest
  # first, then PID, as timeout(1)'s signal to its own group reached them.
  for p in $(_pty_descendants "$2" | awk '{ a[NR] = $0 } END { for (i = NR; i > 0; i--) print a[i] }'); do
    kill -TERM "$p" 2>/dev/null || true
  done
  kill -TERM "$2" 2>/dev/null || true
  s=50 # timeout(1)'s escalation, for a CMD that ignores TERM: KILL after 5 s
  while [ "$s" -gt 0 ] && kill -0 "$2" 2>/dev/null; do
    s=$((s - 1))
    /bin/sleep 0.1
  done
  kill -KILL "$2" 2>/dev/null || true
  exit 0
}

pty_timeout() { # SECS CMD…
  local secs="$1" pid wd rc=0 flag
  shift
  flag="${BATS_TEST_TMPDIR:-${TMPDIR:-/tmp}}/.pty-timeout.$$.$RANDOM"
  # An async command starts with INT and QUIT ignored when job control is off, and every spawn
  # would inherit that (RCA R2): perl resets them before it execs CMD (an executable, not a
  # function). The explicit <&0 keeps CMD's stdin, which an async command would lose to /dev/null.
  /usr/bin/perl -e '$SIG{$_} = "DEFAULT" for qw(INT QUIT); exec { $ARGV[0] } @ARGV or exit 127' "$@" <&0 &
  pid=$!
  _pty_watchdog "$secs" "$pid" "$flag" </dev/null >/dev/null 2>&1 &
  wd=$!
  wait "$pid" || rc=$?
  kill -TERM "$wd" 2>/dev/null || true
  wait "$wd" 2>/dev/null || true
  if [ -e "$flag" ]; then
    rm -f "$flag"
    return 124
  fi
  return "$rc"
}

pty_reap() {
  local d="${BATS_TEST_TMPDIR:-}" p g up skip=" " skipg=" " groups=" " loose="" pat
  case "$d" in /?*/?*) ;; *) return 0 ;; esac
  # This shell and its ancestors (bats itself) are never selected, whatever their argv says, and a
  # match inside one of THEIR groups is killed alone: a group kill there would reach bats.
  p=$$
  while [ -n "$p" ] && [ "$p" -gt 1 ]; do
    skip="$skip$p "
    skipg="$skipg$(_pty_pgid "$p") "
    up="$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')"
    [ "$up" != "$p" ] || break
    p="$up"
  done
  pat="$(printf '%s/' "$d" | sed 's/[][\.*^$+?(){}|]/\\&/g')"
  for p in $(pgrep -f -- "$pat" 2>/dev/null); do
    case "$skip" in *" $p "*) continue ;; esac
    g="$(_pty_pgid "$p")"
    [ -n "$g" ] || continue
    if case "$skipg" in *" $g "*) true ;; *) false ;; esac; then
      loose="$loose $p"
    else
      case "$groups" in *" $g "*) ;; *) groups="$groups$g " ;; esac
    fi
  done
  for p in $loose; do kill -KILL "$p" 2>/dev/null || true; done
  for g in $groups; do _pty_kill_group "$g"; done
  return 0
}
