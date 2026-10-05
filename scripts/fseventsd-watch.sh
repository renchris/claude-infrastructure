#!/bin/bash
# fseventsd-watch.sh — detect fseventsd memory bloat, and (as root, with --restart) clear it.
#
# WHAT IT WATCHES (docs/research/concurrency-scale-2026-10-04/a1-capacity-knee.md, c-outcome-ledger.md).
# On 2026-10-04 fseventsd (pid 317, up 4 days) held a 64 GB footprint, 56 GB of it compressed, and
# filled swap to 40.7 of 42 GB. Compressor segments read 66-69% against the 70% alarm (both 09-16
# kernel panics came with segments at 100%), and the compressor sentinel's SIGKILLs then reddened
# every land gate on the machine. A manual `sudo kill` of fseventsd (launchd respawns it at once)
# took swap to 5.1 of 6 GB; the fresh daemon read 3.5 MB. An earlier incident had it at 40 GB
# before a crash. Nothing on the box said so in either case.
#
# THE INSTRUMENT is the daemon's physical footprint (top's MEM column, which counts its compressed
# pages) plus the compressed part on its own (CMPRS). fseventsd runs as root, so libproc's
# proc_pid_rusage refuses it from uid 501 (the pass in scripts/lib/capacity-attrib.py cannot see
# it); `top -l 1 -pid` can, for ~0.8 CPU-s per read (measured 2026-10-04). RSS is no instrument here:
# it leaves the compressed bulk out (the fresh daemon read RSS 14 MB, footprint 3.5 MB).
#
# MODES
#   fseventsd-watch.sh              measure, print one line + verdict=, append the JSONL log
#   fseventsd-watch.sh --notify     + page (cc-desk-page: the desk, else the operator's banner and
#                                    phone) when the verdict rises (ok -> warn -> act), re-asserted
#                                    every RENOTIFY_S while it stays above ok
#   fseventsd-watch.sh --restart    ROOT ONLY: at or past ACT_MB on ACT_RUNS consecutive runs of one
#                                    pid, and past the cooldown, sample the daemon's stack, SIGTERM
#                                    it (SIGKILL after TERM_WAIT_S), confirm launchd brought it back
#                                    under a NEW pid, and append one ledger row per restart.
#
# VERDICTS: ok | warn (footprint >= WARN_MB) | act (footprint >= ACT_MB) | absent | unknown
#
# WHAT A RESTART COSTS: fseventsd's clients (Spotlight, Time Machine, file watchers) see an event-id
# discontinuity and rescan the volumes they watch. That is what the operator's manual kill cost too,
# and it is cheaper than a full compressor; the cooldown keeps it rare.
#
# ENV (thresholds; fresh daemon 3.5 MB, incidents 40 GB and 64 GB)
#   FSE_WATCH=0                     kill switch: prints verdict=ok, touches nothing
#   FSE_WATCH_WARN_MB=8192          warn floor (page once)
#   FSE_WATCH_ACT_MB=16384          act floor (page again; the root watchdog restarts at it)
#   FSE_WATCH_ACT_RUNS=2            consecutive runs of the same pid at/over ACT_MB before a restart
#   FSE_WATCH_RESTART_GAP_S=1800    minimum spacing between restarts
#   FSE_WATCH_TERM_WAIT_S=10        SIGTERM grace before SIGKILL
#   FSE_WATCH_RESPAWN_WAIT_S=20     how long to wait for launchd's new pid before reporting none
#   FSE_WATCH_RENOTIFY_S=21600      re-page interval while still above ok
#   FSE_WATCH_SAMPLE_DIR=/var/log/claude-fseventsd-samples   a 3 s stack sample of the daemon is
#   FSE_WATCH_SAMPLE_KEEP=5         written here just before each restart; newest N kept
# SEAMS: FSE_WATCH_PS FSE_WATCH_TOP FSE_WATCH_SYSCTL FSE_WATCH_KILL FSE_WATCH_SLEEP FSE_WATCH_PAGE
#        FSE_WATCH_SAMPLE (sampler binary; 0 = no sample) FSE_WATCH_STATE FSE_WATCH_LOG
#        FSE_WATCH_LEDGER FSE_WATCH_NOW FSE_WATCH_ROOT_OK (tests: allow --restart without EUID 0)
set -uo pipefail

NOTIFY=0; RESTART=0
for a in "$@"; do
  case "$a" in
    --notify) NOTIFY=1 ;;
    --restart) RESTART=1 ;;
    -h|--help) sed -n 2,47p "$0"; exit 0 ;;
    *) echo "fseventsd-watch: unknown argument: $a" >&2; exit 2 ;;
  esac
done

if [ "${FSE_WATCH:-1}" = 0 ]; then
  printf 'fseventsd-watch: disabled (FSE_WATCH=0)\nverdict=ok\n'; exit 0
fi

WARN_MB="${FSE_WATCH_WARN_MB:-8192}"
ACT_MB="${FSE_WATCH_ACT_MB:-16384}"
ACT_RUNS="${FSE_WATCH_ACT_RUNS:-2}"
RESTART_GAP_S="${FSE_WATCH_RESTART_GAP_S:-1800}"
TERM_WAIT_S="${FSE_WATCH_TERM_WAIT_S:-10}"
RESPAWN_WAIT_S="${FSE_WATCH_RESPAWN_WAIT_S:-20}"
RENOTIFY_S="${FSE_WATCH_RENOTIFY_S:-21600}"
PS_BIN="${FSE_WATCH_PS:-/bin/ps}"
TOP_BIN="${FSE_WATCH_TOP:-/usr/bin/top}"
SYSCTL_BIN="${FSE_WATCH_SYSCTL:-/usr/sbin/sysctl}"
KILL_BIN="${FSE_WATCH_KILL:-/bin/kill}"
SLEEP_BIN="${FSE_WATCH_SLEEP:-/bin/sleep}"
SAMPLE_BIN="${FSE_WATCH_SAMPLE:-/usr/bin/sample}"
SAMPLE_DIR="${FSE_WATCH_SAMPLE_DIR:-/var/log/claude-fseventsd-samples}"
SAMPLE_KEEP="${FSE_WATCH_SAMPLE_KEEP:-5}"
NOW="${FSE_WATCH_NOW:-$(/bin/date +%s)}"

if [ "$RESTART" = 1 ]; then
  STATE="${FSE_WATCH_STATE:-/var/db/claude-fseventsd-watchdog.state}"
  LOG="${FSE_WATCH_LOG:-/var/log/claude-fseventsd-watchdog.jsonl}"
  LEDGER="${FSE_WATCH_LEDGER:-/var/log/claude-fseventsd-restarts.jsonl}"
else
  STATE="${FSE_WATCH_STATE:-$HOME/.claude/state/fseventsd-watch.state}"
  LOG="${FSE_WATCH_LOG:-$HOME/.claude/logs/fseventsd-watch.jsonl}"
fi

# seconds from ps `etime` ([dd-][hh:]mm:ss)
to_s() {
  printf '%s\n' "$1" | /usr/bin/awk '{
    d = 0; s = $0
    if (index(s, "-")) { split(s, dp, "-"); d = dp[1]; s = dp[2] }
    n = split(s, f, ":"); t = 0
    for (i = 1; i <= n; i++) t = t * 60 + f[i]
    printf "%d\n", d * 86400 + t }'
}

# "<pid> <etime>" of the running fseventsd, or nothing
daemon_row() {
  "$PS_BIN" -Axo pid=,etime=,comm= 2>/dev/null | /usr/bin/awk '$3 ~ /(^|\/)fseventsd$/ { print $1, $2; exit }'
}

row="$(daemon_row)"
if [ -z "$row" ]; then
  printf 'fseventsd-watch: fseventsd not running (launchd restarts it on demand)\nverdict=absent\n'
  exit 0
fi
read -r PID ETIME <<<"$row"
AGE_S="$(to_s "$ETIME")"

# top's MEM and CMPRS for that pid, in MB. Units are B/K/M/G/T with an optional +/- trend suffix
# ("3553K", "64G", "1024M+"). Exits 1 when the pid's row is missing or a field does not parse, so an
# unreadable instrument reads `unknown`, never a fabricated healthy 0.
read -r FP_MB CMPRS_MB <<<"$("$TOP_BIN" -l 1 -pid "$PID" -stats pid,mem,cmprs 2>/dev/null | /usr/bin/awk -v pid="$PID" '
  function mb(v,  n, u) {
    sub(/[+-]$/, "", v)
    if (v !~ /^[0-9.]+[BKMGT]$/) return -1
    n = substr(v, 1, length(v) - 1) + 0; u = substr(v, length(v))
    if (u == "B") return n / 1048576
    if (u == "K") return n / 1024
    if (u == "M") return n
    if (u == "G") return n * 1024
    return n * 1048576 }
  $1 == pid { f = mb($2); c = mb($3); if (f < 0 || c < 0) exit 1; printf "%d %d\n", f, c; found = 1; exit }
  END { if (!found) exit 1 }')"
case "$FP_MB" in ''|*[!0-9]*)
  printf 'fseventsd-watch: pid=%s footprint unreadable (top -l 1 -pid) — cannot judge\nverdict=unknown\n' "$PID"; exit 0 ;;
esac
case "$CMPRS_MB" in ''|*[!0-9]*) CMPRS_MB=0 ;; esac

# Machine context for the row: swap used, in MB ("used = 5068.88M"). Empty when unreadable.
SWAP_MB="$("$SYSCTL_BIN" -n vm.swapusage 2>/dev/null | /usr/bin/awk '{ for (i = 1; i < NF; i++) if ($i == "used") { v = $(i + 2); sub(/M$/, "", v); printf "%d", v } }')"
case "$SWAP_MB" in ''|*[!0-9]*) SWAP_MB=null ;; esac

prev_pid=""; prev_fp=""; prev_ts=""; prev_verdict="ok"; last_notify=0; last_restart=0; act_runs=0
if [ -f "$STATE" ]; then
  read -r prev_pid prev_fp prev_ts prev_verdict last_notify last_restart act_runs < "$STATE" 2>/dev/null || true
fi
case "$last_notify" in ''|*[!0-9]*) last_notify=0 ;; esac
case "$last_restart" in ''|*[!0-9]*) last_restart=0 ;; esac
case "$act_runs" in ''|*[!0-9]*) act_runs=0 ;; esac
case "$prev_verdict" in ok|warn|act) ;; *) prev_verdict=ok ;; esac

# Growth in MB/h since the last run of THIS pid; null on a first run or a new daemon.
GROWTH=null
if [ "$prev_pid" = "$PID" ] && [ -n "$prev_ts" ] && [ "$NOW" -gt "$prev_ts" ] 2>/dev/null \
   && [ -n "$prev_fp" ] && [ "$prev_fp" -ge 0 ] 2>/dev/null; then
  GROWTH=$(( (FP_MB - prev_fp) * 3600 / (NOW - prev_ts) ))
fi

if [ "$FP_MB" -ge "$ACT_MB" ]; then VERDICT=act
elif [ "$FP_MB" -ge "$WARN_MB" ]; then VERDICT=warn
else VERDICT=ok; fi

# Consecutive runs of THIS pid at or past the act floor; a new daemon starts the count from zero.
if [ "$VERDICT" != act ]; then act_runs=0
elif [ "$prev_pid" = "$PID" ]; then act_runs=$(( act_runs + 1 ))
else act_runs=1; fi

sev() { case "$1" in act) echo 2 ;; warn) echo 1 ;; *) echo 0 ;; esac; }

ACTION=none; NEW_PID=""
if [ "$RESTART" = 1 ]; then
  if [ "$(/usr/bin/id -u)" != 0 ] && [ "${FSE_WATCH_ROOT_OK:-0}" != 1 ]; then
    echo "fseventsd-watch: --restart needs root (it runs from the system LaunchDaemon)" >&2; exit 2
  fi
  if [ "$VERDICT" = act ] && [ "$act_runs" -ge "$ACT_RUNS" ]; then
    if [ $(( NOW - last_restart )) -lt "$RESTART_GAP_S" ]; then ACTION=deferred-gap
    else
      # Evidence before the cure: the restart erases the only record of what the daemon held, and the
      # leak's cause is still open. One 3 s stack sample per restart, newest SAMPLE_KEEP kept. Never
      # blocks the restart.
      SAMPLE_FILE=""
      if [ "$SAMPLE_BIN" != 0 ] && (umask 022; /bin/mkdir -p "$SAMPLE_DIR") 2>/dev/null; then
        SAMPLE_FILE="$SAMPLE_DIR/fseventsd-sample-$NOW.txt"
        "$SAMPLE_BIN" "$PID" 3 -file "$SAMPLE_FILE" >/dev/null 2>&1 || SAMPLE_FILE=""
        /bin/ls -1t "$SAMPLE_DIR"/fseventsd-sample-*.txt 2>/dev/null | /usr/bin/tail -n +$(( SAMPLE_KEEP + 1 )) \
          | while IFS= read -r _old; do /bin/rm -f "$_old"; done
      fi
      SIGNAL=TERM
      if "$KILL_BIN" -TERM "$PID" 2>/dev/null; then
        i=0
        while [ "$i" -lt "$TERM_WAIT_S" ] && "$KILL_BIN" -0 "$PID" 2>/dev/null; do "$SLEEP_BIN" 1; i=$(( i + 1 )); done
        if "$KILL_BIN" -0 "$PID" 2>/dev/null; then
          SIGNAL=KILL; "$KILL_BIN" -KILL "$PID" 2>/dev/null || true
        fi
        # Confirm launchd brought it back under a NEW pid: a restart that leaves no daemon is not a cure.
        i=0
        while :; do
          _r="$(daemon_row)"; NEW_PID="${_r%% *}"
          if [ -n "$NEW_PID" ] && [ "$NEW_PID" != "$PID" ]; then break; fi
          NEW_PID=""
          [ "$i" -ge "$RESPAWN_WAIT_S" ] && break
          "$SLEEP_BIN" 1; i=$(( i + 1 ))
        done
        if [ -n "$NEW_PID" ]; then ACTION=restarted; else ACTION=restarted-no-respawn; fi
        last_restart="$NOW"; act_runs=0
      else
        ACTION=restart-failed
      fi
      (umask 022; /bin/mkdir -p "$(dirname "$LEDGER")") 2>/dev/null
      printf '{"ts":%s,"old_pid":%s,"new_pid":%s,"fp_mb":%s,"cmprs_mb":%s,"age_s":%s,"swap_mb":%s,"signal":"%s","action":"%s","sample":"%s"}\n' \
        "$NOW" "$PID" "${NEW_PID:-null}" "$FP_MB" "$CMPRS_MB" "$AGE_S" "$SWAP_MB" "$SIGNAL" "$ACTION" "$SAMPLE_FILE" >> "$LEDGER" 2>/dev/null
    fi
  fi
elif [ "$NOTIFY" = 1 ] && [ "$VERDICT" != ok ]; then
  if [ "$(sev "$VERDICT")" -gt "$(sev "$prev_verdict")" ] || [ $(( NOW - last_notify )) -ge "$RENOTIFY_S" ]; then
    _gr="$GROWTH"; [ "$_gr" = null ] && _gr="?"
    msg="fseventsd $VERDICT: footprint ${FP_MB} MB (${CMPRS_MB} MB compressed, ${_gr} MB/h), pid $PID up ${AGE_S}s, swap used ${SWAP_MB} MB. A restart clears it (launchd respawns the daemon at once): sudo killall fseventsd — or install the root watchdog: bash ~/Development/claude-infrastructure/migrations/0057-fseventsd-watchdog.sh --confirm com.claude.fseventsd-watchdog"
    rc=0
    if [ -n "${FSE_WATCH_PAGE:-}" ]; then "$FSE_WATCH_PAGE" --source fseventsd-watch -- "$msg" >/dev/null 2>&1 || rc=$?
    elif [ -x "$HOME/.claude/bin/cc-desk-page" ]; then "$HOME/.claude/bin/cc-desk-page" --source fseventsd-watch -- "$msg" >/dev/null 2>&1 || rc=$?
    elif command -v cc-desk-page >/dev/null 2>&1; then cc-desk-page --source fseventsd-watch -- "$msg" >/dev/null 2>&1 || rc=$?
    else rc=127; fi
    # cc-desk-page exits 0 only when some channel took the page; anything else is said, never
    # rendered as delivered.
    if [ "$rc" = 0 ]; then ACTION=paged; last_notify="$NOW"
    elif [ "$rc" = 127 ]; then ACTION=page-no-transport
    else ACTION="page-undelivered-rc$rc"; fi
  else ACTION=page-damped; fi
fi

# The state row keeps the verdict the PAGE was judged against, so an undelivered page re-tries the
# rise next run instead of being swallowed as already-said.
STATE_VERDICT="$VERDICT"
case "$ACTION" in page-undelivered-*|page-no-transport) STATE_VERDICT="$prev_verdict" ;; esac
[ "$ACTION" = restarted ] && STATE_VERDICT=ok

(umask 022; /bin/mkdir -p "$(dirname "$STATE")" "$(dirname "$LOG")") 2>/dev/null
printf '%s %s %s %s %s %s %s\n' "$PID" "$FP_MB" "$NOW" "$STATE_VERDICT" "$last_notify" "$last_restart" "$act_runs" > "$STATE" 2>/dev/null
printf '{"ts":%s,"pid":%s,"fp_mb":%s,"cmprs_mb":%s,"growth_mb_h":%s,"age_s":%s,"swap_mb":%s,"verdict":"%s","action":"%s"%s}\n' \
  "$NOW" "$PID" "$FP_MB" "$CMPRS_MB" "$GROWTH" "$AGE_S" "$SWAP_MB" "$VERDICT" "$ACTION" "${NEW_PID:+,\"new_pid\":$NEW_PID}" >> "$LOG" 2>/dev/null
printf 'fseventsd-watch: pid=%s fp=%sMB cmprs=%sMB growth=%sMB/h age=%ss swap=%sMB action=%s%s\nverdict=%s\n' \
  "$PID" "$FP_MB" "$CMPRS_MB" "$GROWTH" "$AGE_S" "$SWAP_MB" "$ACTION" "${NEW_PID:+ new_pid=$NEW_PID}" "$VERDICT"
exit 0
