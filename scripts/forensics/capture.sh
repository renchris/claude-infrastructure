# shellcheck shell=bash
# capture.sh -- hang-proof forensic capture: precursor snapshot (L1) or full lockup bundle (L2/L3).
#
# Invoke ONLY as:  /bin/bash capture.sh <snapshot|full> <reason>     (never via #!: DESIGN I1)
#                  /bin/bash capture.sh <reason>                     (legacy kit form = full)
# Writes ~/Library/Logs/cc-forensics/<UTC>-<reason>/{steps.tsv, progress, manifest.json,
#        DIAGNOSIS.md, diagnosis.json, <step>.out ...}; prints the bundle dir as its LAST stdout line.
# Exit: 0 bundle written (steps may have failed; steps.tsv says which) · 75 busy or rate-limited,
#       retry · 1 setup error · 2 usage.
#
# Hang-proof contract (DESIGN I2, I4, I9; mac-forensics.md §2):
#   * Every step runs in a perl-forked child; the PARENT owns the deadline and exits on it without
#     waiting. A child in an uninterruptible devfs wait ignores SIGALRM/SIGKILL until its syscall
#     returns, so `alarm N; exec cmd` alone does NOT bound a caller. Past its deadline a step is
#     ABANDONed (rc 124); the run returns within deadline + ~1 s.
#   * The child calls setsid() first: no controlling tty, so nothing it runs (sudo, ps) can resolve
#     one through ttyname()/devname() into a /dev walk. Its stdio are REGULAR FILES; nothing here
#     opens /dev/null, /dev/tty or any /dev path. The deadline SIGKILL is the I9 exception (a
#     setsid'd child with no ctty), never a pty session.
#   * No ps column that resolves a tty name (tt, tty, -M, -t, -T), no ps without -x/-A, no multi-pid
#     -p, no lsof, no ls of /dev, no pgrep, no zsh, no login. kitty's pid comes from procscan.
#   * Every step child registers `pid lstart boot` in ~/.claude/autonomy/forensics/active.pids
#     before it execs, so the compressor actuator never freezes or kills it (DESIGN C2).
#   * Per-tier mutex = a (pid, lstart, kern.bootsessionuuid) record in a boot-scoped dir; a holder
#     that fails any of the three is stale and broken. Per-tier rate key: snapshot 300 s, full 900 s;
#     CC_FX_FORCE=1 overrides the rate key (L2/L3), never the mutex.
#
# Env: CC_FX=off (exit 0, nothing) · CC_FX_ROOT · CC_FX_PY · CC_FX_FORCE · CC_FX_NOSUDO=1 ·
#      CC_LOCKWATCH_DIR (lockwatch state to copy) · CC_FX_ACTIVE (active.pids path) ·
#      CC_FX_H2 (root wrapper path; default /usr/local/libexec/cc-forensics-root.sh) ·
#      CC_FX_TRANSCRIPT_ROOTS (colon list, for diagnose's cause scan).
# Test seams: CC_FX_STUB_DIR (tools resolve there first) · CC_FX_EXTRA_STEP='name|deadline|cmd ...'
#      (one injected step, word-split) · CC_FX_DEV_DIR / CC_FX_CANARY_STALL_AT (passed to the canary)
#      · CC_FX_SKIP_LOG=1 (skip log collect/show) · CC_FX_BOOT.
# bash 3.2-safe: launchd and the sentinel run /bin/bash.
set -u
umask 077
[ "${CC_FX:-on}" = off ] && exit 0

if [ $# -ge 2 ]; then TIER="$1"; REASON="$2"
elif [ $# -eq 1 ]; then TIER=full; REASON="$1"
else echo "usage: capture.sh <snapshot|full> <reason>" >&2; exit 2; fi
case "$TIER" in snapshot|full) ;; *) echo "capture: unknown tier $TIER" >&2; exit 2 ;; esac
REASON="${REASON//[^A-Za-z0-9_.-]/_}"

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
LW="$KIT/../lockwatch"
ROOT="${CC_FX_ROOT:-$HOME/Library/Logs/cc-forensics}"
LWDIR="${CC_LOCKWATCH_DIR:-$HOME/.claude/autonomy/lockwatch}"
ACTIVE="${CC_FX_ACTIVE:-$HOME/.claude/autonomy/forensics/active.pids}"
H2="${CC_FX_H2:-/usr/local/libexec/cc-forensics-root.sh}"
PERL=/usr/bin/perl

PY="${CC_FX_PY:-}"
if [ -z "$PY" ]; then
  for c in /Library/Frameworks/Python.framework/Versions/3.11/bin/python3.11 \
    /Applications/Xcode.app/Contents/Developer/Library/Frameworks/Python3.framework/Versions/3.9/bin/python3.9 \
    /Library/Developer/CommandLineTools/Library/Frameworks/Python3.framework/Versions/3.9/bin/python3.9 \
    /usr/bin/python3; do
    if [ -x "$c" ]; then PY="$c"; break; fi
  done
fi

# Tools by absolute path; CC_FX_STUB_DIR (tests) substitutes a recorder for any of them.
T_PS=/bin/ps; T_SAMPLE=/usr/bin/sample; T_SYSCTL=/usr/sbin/sysctl; T_VMSTAT=/usr/bin/vm_stat
T_LOG=/usr/bin/log; T_FIND=/usr/bin/find; T_SUDO=/usr/bin/sudo; T_MEMP=/usr/bin/memory_pressure
T_CP=/bin/cp
if [ -n "${CC_FX_STUB_DIR:-}" ]; then
  for v in T_PS T_SAMPLE T_SYSCTL T_VMSTAT T_LOG T_FIND T_SUDO T_MEMP T_CP; do
    eval "b=\$$v"; b="${b##*/}"
    if [ -x "$CC_FX_STUB_DIR/$b" ]; then eval "$v=\$CC_FX_STUB_DIR/\$b"; fi
  done
fi

mkdir -p "$ROOT" "$(dirname "$ACTIVE")" || exit 1
if [ -n "${CC_FX_BOOT:-}" ]; then BOOT="$CC_FX_BOOT"
else BOOT="$("$T_SYSCTL" -n kern.bootsessionuuid 2>"$ROOT/.sysctl.err")"; fi
[ -n "$BOOT" ] || BOOT=unknown-boot

# bounded RUN: run_bounded DEADLINE OUT ERR cmd... -> rc (124 = abandoned). Parent never waits past
# the deadline; the child setsid()s, records itself in active.pids, then execs.
run_bounded() {
  local t="$1" out="$2" err="$3"; shift 3
  # shellcheck disable=SC2016  # perl source, expanded by perl
  "$PERL" -e '
    use POSIX ();
    my ($t, $in, $out, $err, $act, $boot) = splice(@ARGV, 0, 6);
    my $p = fork; exit 70 unless defined $p;
    if (!$p) {
      POSIX::setsid();
      open STDIN, "<", $in; open STDOUT, ">", $out; open STDERR, ">", $err;
      my $mib = pack("i4", 1, 14, 1, $$); my $buf = "\0" x 648; my $len = pack("Q", 648);
      my $ls = (syscall(202, $mib, 4, $buf, $len, 0, 0) == 0) ? unpack("q", substr($buf, 0, 8)) : 0;
      if (open my $a, ">>", $act) { syswrite $a, "$$ $ls $boot\n"; close $a }
      exec { $ARGV[0] } @ARGV; POSIX::_exit(127);
    }
    $SIG{ALRM} = sub { kill "KILL", $p; POSIX::_exit(124) };   # I9 exception: setsid, no ctty
    alarm $t; waitpid($p, 0); POSIX::_exit($? >> 8);
  ' "$t" "$EMPTY" "$out" "$err" "$ACTIVE" "$BOOT" "$@"
}

# pid_lstart PID -> kernel p_starttime sec on stdout via a bounded child (0 when absent)
pid_lstart() {
  # shellcheck disable=SC2016  # perl source, expanded by perl
  run_bounded 3 "$LOCKD/.ls.$$" "$LOCKD/.ls.err" "$PERL" -e '
    my $mib = pack("i4", 1, 14, 1, $ARGV[0]); my $buf = "\0" x 648; my $len = pack("Q", 648);
    my $r = syscall(202, $mib, 4, $buf, $len, 0, 0);
    print((($r == 0 && unpack("Q", $len) >= 648) ? unpack("q", substr($buf, 0, 8)) : 0), "\n");' "$1"
  local v=""
  # a line without its newline makes `read` return 1 AFTER assigning it: test the value, not rc
  read -r v 2>"$LOCKD/.lockerr" < "$LOCKD/.ls.$$" || [ -n "$v" ] || v=0
  rm -f "$LOCKD/.ls.$$"
  printf '%s' "${v:-0}"
}

LOCKD="$ROOT/.locks/$BOOT"
mkdir -p "$LOCKD" || exit 1
EMPTY="$LOCKD/.empty"
: > "$EMPTY"
LOCK="$LOCKD/capture-$TIER.lock"
MYLS="$(pid_lstart $$)"
take_lock() {
  if mkdir "$LOCK" 2>"$LOCKD/.lockerr"; then
    printf '%s %s %s\n' "$$" "$MYLS" "$BOOT" > "$LOCK/owner"
    return 0
  fi
  local opid="" ols="" oboot=""
  read -r opid ols oboot 2>"$LOCKD/.lockerr" < "$LOCK/owner" || true
  if [ -n "$opid" ] && [ "$oboot" = "$BOOT" ] && kill -0 "$opid" 2>"$LOCKD/.lockerr" &&
     [ "$(pid_lstart "$opid")" = "$ols" ]; then
    printf 'capture: busy (%s lock held by pid %s since lstart %s)\n' "$TIER" "$opid" "$ols"
    return 75
  fi
  # stale: dead holder, reused pid (lstart differs), another boot's record, or no record at all
  rm -rf "${LOCK:?}"
  if mkdir "$LOCK" 2>"$LOCKD/.lockerr"; then
    printf '%s %s %s\n' "$$" "$MYLS" "$BOOT" > "$LOCK/owner"
    echo "capture: broke stale $TIER lock (holder ${opid:-none} ${ols:-?} ${oboot:-?})" >&2
    return 0
  fi
  echo "capture: busy ($TIER lock raced)"
  return 75
}
take_lock; rc=$?
[ "$rc" -eq 0 ] || exit "$rc"
trap 'rm -rf "${LOCK:?}"' EXIT

if [ "$TIER" = snapshot ]; then GAP="${CC_FX_SNAPSHOT_GAP_S:-300}"; else GAP="${CC_FX_FULL_GAP_S:-900}"; fi
NOW=$(/bin/date -u +%s)
LAST=0
read -r LAST 2>"$LOCKD/.lockerr" < "$ROOT/.last-$TIER" || LAST=0
if [ "${CC_FX_FORCE:-0}" != 1 ] && [ $((NOW - ${LAST:-0})) -lt "$GAP" ]; then
  echo "capture: rate-limited ($TIER last $((NOW - LAST)) s ago < $GAP s)"
  exit 75
fi
echo "$NOW" > "$ROOT/.last-$TIER"

D="$ROOT/$(/bin/date -u +%Y%m%dT%H%M%SZ)-$REASON"
[ -e "$D" ] && D="$D.$$"
mkdir -p "$D" || exit 1
printf 'step\trc\tms\tbytes\tstatus\n' > "$D/steps.tsv"
: > "$D/progress"
MISSING=""

now_ms() { "$PERL" -MTime::HiRes=time -e 'printf "%d", time*1000'; }

# step NAME DEADLINE_S CMD...  -> $D/NAME.out, $D/NAME.err, one row in steps.tsv
step() {
  local name="$1" t="$2" t0 t1 rc st bytes
  shift 2
  echo "START $name" >> "$D/progress"
  t0=$(now_ms)
  run_bounded "$t" "$D/$name.out" "$D/$name.err" "$@"
  rc=$?
  t1=$(now_ms)
  case "$rc" in 0) st=OK ;; 124) st=ABANDON ;; 127) st=NOEXEC ;; *) st=FAIL ;; esac
  bytes=$(/usr/bin/stat -f %z "$D/$name.out" 2>"$D/.stat.err")
  printf '%s\t%s\t%s\t%s\t%s\n' "$name" "$rc" "$((t1 - t0))" "${bytes:-0}" "$st" >> "$D/steps.tsv"
  echo "END $name rc=$rc $st" >> "$D/progress"
  return 0
}

# --- tier 0: kernel counters ---------------------------------------------------------------
step 00-sysctl 5 "$T_SYSCTL" kern.boottime kern.bootsessionuuid kern.num_threads kern.num_tasks \
  kern.maxproc kern.num_files kern.maxfiles kern.num_vnodes kern.maxvnodes kern.tty.ptmx_max \
  kern.memorystatus_level vm.memory_pressure vm.loadavg vm.swapusage vm.compressor_mode
step 01-vm_stat 5 "$T_VMSTAT"
# --- tier 1: who is stuck, devfs-free ------------------------------------------------------
step 02-procscan 20 "$PY" -I "$KIT/procscan.py" --threads --out "$D/02-procscan.json"
mkdir -p "$ROOT/.canary"
step 03-devfs-canary 6 "$PERL" "$KIT/devfs-canary.pl" "$ROOT/.canary" 3
step 04-ps 15 "$T_PS" -axww -o pid=,ppid=,pgid=,tdev=,stat=,lstart=,pri=,nice=,%cpu=,rss=,etime=,args=
for f in state.json pty.json procscan.json levels.jsonl; do
  [ -f "$LWDIR/$f" ] && step "05-lockwatch-${f%%.*}" 5 "$T_CP" "$LWDIR/$f" "$D/05-lockwatch-$f"
done
[ -f "$LWDIR/run/$BOOT/ttymap.json" ] && step 05-lockwatch-ttymap 5 "$T_CP" "$LWDIR/run/$BOOT/ttymap.json" \
  "$D/05-lockwatch-ttymap.json"
if [ -n "${CC_FX_EXTRA_STEP:-}" ]; then
  IFS='|' read -r xn xt xc <<EOF_X
$CC_FX_EXTRA_STEP
EOF_X
  # shellcheck disable=SC2086  # the seam's command is word-split on purpose
  step "$xn" "$xt" $xc
fi
# a second scan 2 s later turns cumulative cpu_s into a CURRENT rate for suspect ranking
/bin/sleep 2
step 06-procscan2 20 "$PY" -I "$KIT/procscan.py" --out "$D/06-procscan2.json"
# --- suspects: exiting/orphaned pty-leader pgid members first, then top CPU now (max 4) ------
step 07-suspects 10 "$PY" -I "$LW/diagnose.py" suspects --bundle "$D" --tier "$TIER" --self "$$"
SUSPECTS=""
[ -s "$D/07-suspects.out" ] && read -r SUSPECTS < "$D/07-suspects.out"
for P in $SUSPECTS; do
  case "$P" in *[!0-9]*|'') continue ;; esac
  step "08-sample-$P" 30 "$T_SAMPLE" "$P" 2 10 -file "$D/08-sample-$P.txt"
done

if [ "$TIER" = full ]; then
  # --- tier 2: kernel stacks through the H2 root wrapper only (DESIGN §8 H2) -------------------
  if [ "${CC_FX_NOSUDO:-0}" != 1 ] && [ -f "$H2" ]; then
    step 09-spindump 100 "$T_SUDO" -n /bin/bash "$H2" spindump
    step 09-tailspin 60 "$T_SUDO" -n /bin/bash "$H2" tailspin
  else
    MISSING="${MISSING} H2"
  fi
  # --- tier 3: history, frozen first (log collect is root-free on 15.8.1), then derived views --
  if [ "${CC_FX_SKIP_LOG:-0}" != 1 ]; then
    step 10-log-collect 90 "$T_LOG" collect --last 30m --output "$D/10-logs.logarchive"
    if [ -d "$D/10-logs.logarchive" ]; then
      step 11-log-kitty 45 "$T_LOG" show --archive "$D/10-logs.logarchive" --style compact --predicate \
        'process == "kitty" OR eventMessage CONTAINS "Too many peers"'
      step 11-log-kernel 60 "$T_LOG" show --archive "$D/10-logs.logarchive" --last 15m --style compact \
        --predicate 'process == "kernel" AND NOT (eventMessage CONTAINS "process_is_plugin_host")'
    fi
  fi
  step 12-reports 30 "$T_FIND" /Library/Logs/DiagnosticReports "$HOME/Library/Logs/DiagnosticReports" \
    -maxdepth 1 -type f -mmin -120 -print
  step 13-memory_pressure 10 "$T_MEMP" -Q
fi

# --- diagnosis, manifest, registry hygiene, retention ------------------------------------------
if [ "$TIER" = full ]; then
  step 20-diagnose 75 "$PY" -I "$LW/diagnose.py" bundle --bundle "$D" --state "$LWDIR"
else
  step 20-diagnose 20 "$PY" -I "$LW/diagnose.py" bundle --bundle "$D" --state "$LWDIR" --no-cause
fi
step 21-manifest 10 "$PY" -I "$LW/diagnose.py" manifest --bundle "$D" --tier "$TIER" --reason "$REASON" \
  --boot "$BOOT" --self "$$" --missing "${MISSING# }"
step 23-retention 60 "$PY" -I "$LW/diagnose.py" retention --root "$ROOT" --keep 3 --cap-mb "${CC_FX_CAP_MB:-3072}"
# shellcheck disable=SC2016  # perl source, expanded by perl
step 22-active-prune 10 "$PERL" -e '
  my ($f) = @ARGV; open my $h, "<", $f or exit 0; my @keep;
  while (my $l = <$h>) {
    my ($p, $ls) = split " ", $l; next unless $p && $p != $$ && kill(0, $p);
    my $mib = pack("i4", 1, 14, 1, $p); my $buf = "\0" x 648; my $len = pack("Q", 648);
    next unless syscall(202, $mib, 4, $buf, $len, 0, 0) == 0 && unpack("q", substr($buf, 0, 8)) == $ls;
    push @keep, $l;
  }
  close $h; open my $o, ">", "$f.tmp.$$" or exit 1; print $o @keep; close $o; rename "$f.tmp.$$", $f;
' "$ACTIVE"
echo "EXIT 0" >> "$D/progress"
echo "$D"
exit 0
