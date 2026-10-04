#!/bin/bash
# coreaudiod-watch.sh — detect the coreaudiod IO-context leak, and (as root, with --restart) clear it.
#
# WHAT IT WATCHES (docs/research/coreaudiod-spin-2026-09-29.md). coreaudiod takes one
# `com.apple.audio.*context*.preventuseridlesleep` power assertion per IO context while that context's
# IO runs, and drops it when IO stops. Under CPU starvation (load >= ~40 on this 10-core box) client
# starts stop being torn down: the daemon ends up holding thousands of contexts that never release.
# Measured from `pmset -g log`: 5,117 held when pid 391 was restarted on 2026-09-24 and 4,641 when pid
# 36954 was restarted on 2026-09-29, each a context no live process owned. Once degraded, EVERY new
# client start leaked ~7 more (1 speaker + 6 `contextN`), so the count only climbs, the IO thread
# iterates an ever-longer client list, overload reports compound it, and CPU reached ~200%. Nothing
# but a coreaudiod restart releases them.
#
# THE INSTRUMENT is the leaked-context count, not CPU: `pmset -g assertions` needs no root, and the
# count is the cause, while CPU alone also spikes during a plain overload storm that a restart would
# not fix (475 contexts read 71% at load 75). CPU is reported as a rate between runs from `ps time`
# (cumulative), falling back to the lifetime average on the first run after a (re)start.
#
# THE SECOND SHAPE (2026-10-04, same doc): held contexts stayed LOW (10 -> 110) while interval CPU
# climbed 15% -> ~300% and RSS sawtoothed up to ~21 GB (a fresh daemon is ~26 MB). The context arms
# never fired, so RSS is its instrument: RSS >= RESTART_RSS_MB with interval CPU >= RESTART_RSS_CPU
# on RESTART_RSS_RUNS consecutive runs of one pid restarts it, whatever ctx reads. The 475-context
# overload storm peaked at 383 MB footprint, half the RSS floor, and a storm is not sustained.
#
# MODES
#   coreaudiod-watch.sh              measure, print one line + verdict=, append the JSONL log,
#                                    maintain the hot flag hooks/notify.sh reads to back off chimes
#   coreaudiod-watch.sh --notify     + damped cc-notify to the desk on the ok -> degraded edge; if
#                                    the desk send fails (rc 3 = no desk registered), a macOS banner
#   coreaudiod-watch.sh --restart    ROOT ONLY: killall coreaudiod (launchd respawns it) when the
#                                    leak is past the restart floor, no live audio input is younger
#                                    than the grace window (a call or dictation), and the last
#                                    restart is older than the gap. Never writes the user flag.
#
# VERDICTS: ok | leaking (ctx >= WARN_CTX) | bloated (rss >= WARN_RSS_MB, ctx below)
#           | hot (cpu >= WARN_CPU, ctx and rss below) | absent | unknown
#
# ENV (thresholds; defaults from the 2026-09-29 measurements)
#   CA_WATCH=0                     kill switch: prints verdict=ok, touches nothing
#   CA_WATCH_WARN_CTX=300          leaking floor (fresh daemon holds 0; 475 already read 71% CPU)
#   CA_WATCH_WARN_CPU=60           hot floor, % of one core (Apple's own cpu_resource limit is 50%)
#   CA_WATCH_RESTART_CTX=1000      restart unconditionally at or past this many held contexts
#   CA_WATCH_RESTART_MIN_CTX=300   ...or past this many AND cpu >= RESTART_CPU on an interval reading
#   CA_WATCH_RESTART_CPU=100
#   CA_WATCH_WARN_RSS_MB=512       bloated floor (healthy daemons logged <= 64 MB, 2026-09-29..10-04)
#   CA_WATCH_RESTART_RSS_MB=768    restart at or past this RSS, any ctx, when CPU and runs also hold
#   CA_WATCH_RESTART_RSS_CPU=50    ...with interval cpu at or past this (healthy max logged: 11%)
#   CA_WATCH_RESTART_RSS_RUNS=3    ...on this many consecutive runs of the same pid (300 s apart)
#   CA_WATCH_RESTART_GAP_S=1800    minimum spacing between restarts
#   CA_WATCH_INPUT_GRACE_S=10800   an audio-in context younger than this defers a restart
#   CA_WATCH_RENOTIFY_S=21600      re-assert interval while still degraded (desk or banner alike)
#   CA_WATCH_SAMPLE_DIR=/var/log/claude-coreaudiod-samples   a 3 s stack sample of the daemon is
#   CA_WATCH_SAMPLE_KEEP=5         written here just before each restart; newest N kept
# SEAMS: CA_WATCH_PS CA_WATCH_PMSET CA_WATCH_KILLALL CA_WATCH_NOTIFY CA_WATCH_BANNER CA_WATCH_STATE
#        CA_WATCH_LOG CA_WATCH_HOT_FLAG CA_WATCH_NOW CA_WATCH_ROOT_OK (tests: allow --restart without EUID 0)
#        CA_WATCH_SAMPLE (sampler binary; 0 = no sample)
set -uo pipefail

NOTIFY=0; RESTART=0
for a in "$@"; do
  case "$a" in
    --notify) NOTIFY=1 ;;
    --restart) RESTART=1 ;;
    -h|--help) sed -n 2,56p "$0"; exit 0 ;;
    *) echo "coreaudiod-watch: unknown argument: $a" >&2; exit 2 ;;
  esac
done

if [ "${CA_WATCH:-1}" = 0 ]; then
  printf 'coreaudiod-watch: disabled (CA_WATCH=0)\nverdict=ok\n'; exit 0
fi

WARN_CTX="${CA_WATCH_WARN_CTX:-300}"
WARN_CPU="${CA_WATCH_WARN_CPU:-60}"
RESTART_CTX="${CA_WATCH_RESTART_CTX:-1000}"
RESTART_MIN_CTX="${CA_WATCH_RESTART_MIN_CTX:-300}"
RESTART_CPU="${CA_WATCH_RESTART_CPU:-100}"
WARN_RSS_MB="${CA_WATCH_WARN_RSS_MB:-512}"
RESTART_RSS_MB="${CA_WATCH_RESTART_RSS_MB:-768}"
RESTART_RSS_CPU="${CA_WATCH_RESTART_RSS_CPU:-50}"
RESTART_RSS_RUNS="${CA_WATCH_RESTART_RSS_RUNS:-3}"
RESTART_GAP_S="${CA_WATCH_RESTART_GAP_S:-1800}"
INPUT_GRACE_S="${CA_WATCH_INPUT_GRACE_S:-10800}"
RENOTIFY_S="${CA_WATCH_RENOTIFY_S:-21600}"
PS_BIN="${CA_WATCH_PS:-/bin/ps}"
PMSET_BIN="${CA_WATCH_PMSET:-/usr/bin/pmset}"
KILLALL_BIN="${CA_WATCH_KILLALL:-/usr/bin/killall}"
BANNER_BIN="${CA_WATCH_BANNER:-/usr/bin/osascript}"
SAMPLE_BIN="${CA_WATCH_SAMPLE:-/usr/bin/sample}"
SAMPLE_DIR="${CA_WATCH_SAMPLE_DIR:-/var/log/claude-coreaudiod-samples}"
SAMPLE_KEEP="${CA_WATCH_SAMPLE_KEEP:-5}"
NOW="${CA_WATCH_NOW:-$(/bin/date +%s)}"

if [ "$RESTART" = 1 ]; then
  STATE="${CA_WATCH_STATE:-/var/db/claude-coreaudiod-watchdog.state}"
  LOG="${CA_WATCH_LOG:-/var/log/claude-coreaudiod-watchdog.jsonl}"
else
  STATE="${CA_WATCH_STATE:-$HOME/.claude/state/coreaudiod-watch.state}"
  LOG="${CA_WATCH_LOG:-$HOME/.claude/logs/coreaudiod-watch.jsonl}"
fi
# The flag lives where hooks/notify.sh keeps its MACHINE-WIDE sound state: the per-uid Darwin temp
# dir resolved from confstr, never $TMPDIR (a harness run can carry its own TMPDIR).
if [ -n "${CA_WATCH_HOT_FLAG:-}" ]; then
  HOT_FLAG="$CA_WATCH_HOT_FLAG"
else
  _t="$(/usr/bin/getconf DARWIN_USER_TEMP_DIR 2>/dev/null || true)"
  HOT_FLAG="${_t:+${_t%/}/cc-notify/coreaudiod-hot}"
fi

# seconds from ps `time` (M:SS.ss, minutes unbounded) or `etime` ([dd-][hh:]mm:ss)
to_s() {
  printf '%s\n' "$1" | /usr/bin/awk '{
    d = 0; s = $0
    if (index(s, "-")) { split(s, dp, "-"); d = dp[1]; s = dp[2] }
    n = split(s, f, ":"); t = 0
    for (i = 1; i <= n; i++) t = t * 60 + f[i]
    printf "%d\n", d * 86400 + t }'
}

row="$("$PS_BIN" -Axo pid=,time=,etime=,rss=,comm= 2>/dev/null | /usr/bin/awk '$5 ~ /(^|\/)coreaudiod$/ { print $1, $2, $3, $4; exit }')"
if [ -z "$row" ]; then
  printf 'coreaudiod-watch: coreaudiod not running (launchd restarts it on demand)\nverdict=absent\n'
  [ "$RESTART" = 1 ] || { [ -n "$HOT_FLAG" ] && /bin/rm -f "$HOT_FLAG" 2>/dev/null; }
  exit 0
fi
read -r PID CPUT ETIME RSS <<<"$row"
CPU_S="$(to_s "$CPUT")"; AGE_S="$(to_s "$ETIME")"

# One pass over the assertion table: count coreaudiod's held IO contexts (the idle-sleep half of each
# pair — every context also holds a display-sleep twin), and the youngest audio-in context's age.
asrt="$("$PMSET_BIN" -g assertions 2>/dev/null)" || asrt=""
if [ -z "$asrt" ]; then
  printf 'coreaudiod-watch: pmset -g assertions unreadable — cannot judge\nverdict=unknown\n'; exit 0
fi
read -r CTX INPUT_YOUNG <<<"$(printf '%s\n' "$asrt" | /usr/bin/awk -v grace="$INPUT_GRACE_S" '
  function secs(a,  n, f, i, t) { n = split(a, f, ":"); t = 0; for (i = 1; i <= n; i++) t = t * 60 + f[i]; return t }
  /\(coreaudiod\):/ && /com\.apple\.audio\..*context.*preventuseridlesleep"/ {
    ctx++; age = -1
    for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+:[0-9][0-9]:[0-9][0-9]$/) { age = secs($i); break }
    pending = 1; next }
  pending && /Resources:/ { if ($0 ~ /audio-in/ && age >= 0 && age < grace) young++; pending = 0; next }
  { pending = 0 }
  END { printf "%d %d\n", ctx, young }')"

# CPU as a rate over the interval since the last run of THIS daemon pid; lifetime average otherwise.
prev_pid=""; prev_cpu=""; prev_ts=""; prev_verdict="ok"; last_notify=0; last_restart=0; bloat_runs=0
if [ -f "$STATE" ]; then
  read -r prev_pid prev_cpu prev_ts prev_verdict last_notify last_restart bloat_runs < "$STATE" 2>/dev/null || true
fi
case "$last_notify" in ''|*[!0-9]*) last_notify=0 ;; esac
case "$last_restart" in ''|*[!0-9]*) last_restart=0 ;; esac
case "$bloat_runs" in ''|*[!0-9]*) bloat_runs=0 ;; esac   # a 6-field state file predates the RSS arm
BASIS=lifetime; CPU_PCT=0
if [ "$prev_pid" = "$PID" ] && [ -n "$prev_ts" ] && [ "$NOW" -gt "$prev_ts" ] 2>/dev/null && [ "$CPU_S" -ge "$prev_cpu" ] 2>/dev/null; then
  CPU_PCT=$(( (CPU_S - prev_cpu) * 100 / (NOW - prev_ts) )); BASIS=interval
elif [ "$AGE_S" -gt 0 ] 2>/dev/null; then
  CPU_PCT=$(( CPU_S * 100 / AGE_S ))
fi

RSS_MB=$(( RSS / 1024 ))
if [ "$CTX" -ge "$WARN_CTX" ]; then VERDICT=leaking
elif [ "$RSS_MB" -ge "$WARN_RSS_MB" ]; then VERDICT=bloated
elif [ "$CPU_PCT" -ge "$WARN_CPU" ]; then VERDICT=hot
else VERDICT=ok; fi

# Consecutive runs of THIS pid in the bloat shape. An interval basis already means the same pid as
# the state row, so a new daemon (or a first run) starts the count from zero.
if [ "$BASIS" = interval ] && [ "$RSS_MB" -ge "$RESTART_RSS_MB" ] && [ "$CPU_PCT" -ge "$RESTART_RSS_CPU" ]; then
  bloat_runs=$(( bloat_runs + 1 ))
else bloat_runs=0; fi

ACTION=none
if [ "$RESTART" = 1 ]; then
  if [ "$(/usr/bin/id -u)" != 0 ] && [ "${CA_WATCH_ROOT_OK:-0}" != 1 ]; then
    echo "coreaudiod-watch: --restart needs root (it runs from the system LaunchDaemon)" >&2; exit 2
  fi
  want=0
  if [ "$CTX" -ge "$RESTART_CTX" ]; then want=1
  elif [ "$CTX" -ge "$RESTART_MIN_CTX" ] && [ "$BASIS" = interval ] && [ "$CPU_PCT" -ge "$RESTART_CPU" ]; then want=1
  elif [ "$bloat_runs" -ge "$RESTART_RSS_RUNS" ]; then want=1; fi
  if [ "$want" = 1 ]; then
    if [ "$INPUT_YOUNG" -gt 0 ]; then ACTION=deferred-input-live
    elif [ $(( NOW - last_restart )) -lt "$RESTART_GAP_S" ]; then ACTION=deferred-gap
    else
      # Evidence before the cure: the restart erases the only record of WHAT the daemon was busy with,
      # and the onset trigger is still unknown (2026-10-04: a fresh daemon leaked 0 of 8 chimes at
      # load 80). One 3 s stack sample per restart, newest SAMPLE_KEEP kept. Never blocks the restart.
      if [ "$SAMPLE_BIN" != 0 ] && (umask 022; /bin/mkdir -p "$SAMPLE_DIR") 2>/dev/null; then
        "$SAMPLE_BIN" "$PID" 3 -file "$SAMPLE_DIR/coreaudiod-sample-$NOW.txt" >/dev/null 2>&1 || true
        /bin/ls -1t "$SAMPLE_DIR"/coreaudiod-sample-*.txt 2>/dev/null | /usr/bin/tail -n +$(( SAMPLE_KEEP + 1 )) \
          | while IFS= read -r _old; do /bin/rm -f "$_old"; done
      fi
      if "$KILLALL_BIN" coreaudiod 2>/dev/null; then ACTION=restarted; last_restart="$NOW"
      else ACTION=restart-failed; fi
    fi
  fi
else
  # The hot flag: present while degraded, refreshed every run, removed on recovery. notify.sh treats
  # a flag older than 15 min as stale, so a dead watcher can never leave chimes throttled for good.
  if [ -n "$HOT_FLAG" ]; then
    if [ "$VERDICT" = ok ]; then /bin/rm -f "$HOT_FLAG" 2>/dev/null
    else (umask 077; /bin/mkdir -p "$(dirname "$HOT_FLAG")") 2>/dev/null
         [ -L "$HOT_FLAG" ] || printf '%s ctx=%s cpu=%s\n' "$VERDICT" "$CTX" "$CPU_PCT" > "$HOT_FLAG" 2>/dev/null; fi
  fi
  if [ "$NOTIFY" = 1 ] && [ "$VERDICT" != ok ]; then
    if [ "$prev_verdict" = ok ] || [ $(( NOW - last_notify )) -ge "$RENOTIFY_S" ]; then
      msg="coreaudiod $VERDICT: $CTX held IO contexts, ${CPU_PCT}% CPU, ${RSS_MB} MB (pid $PID). Only a restart clears it: osascript -e 'do shell script \"killall coreaudiod\" with administrator privileges' — or install the watchdog (docs/research/coreaudiod-spin-2026-09-29.md)."
      rc=0
      if [ -n "${CA_WATCH_NOTIFY:-}" ]; then "$CA_WATCH_NOTIFY" "$msg" >/dev/null 2>&1 || rc=$?
      elif command -v cc-notify >/dev/null 2>&1; then cc-notify --role desk "$msg" >/dev/null 2>&1 || rc=$?
      else rc=127; fi
      # No desk to read it (cc-notify --role desk exits 3 when none is registered) must not mean
      # nobody is told: on 2026-10-04 that silenced 98 consecutive alarms over 8 h. Fall back to a
      # banner, passed as argv so the message's quotes need no AppleScript escaping.
      if [ "$rc" = 0 ]; then ACTION=notified; last_notify="$NOW"
      elif "$BANNER_BIN" -e 'on run argv' -e 'display notification (item 1 of argv) with title "coreaudiod watchdog"' \
             -e 'end run' "$msg" >/dev/null 2>&1; then ACTION=notified-banner; last_notify="$NOW"
      elif [ "$rc" = 127 ]; then ACTION=notify-no-transport
      else ACTION="notify-undelivered-rc$rc"; fi
    else ACTION=notify-damped; fi
  fi
fi

(umask 022; /bin/mkdir -p "$(dirname "$STATE")" "$(dirname "$LOG")") 2>/dev/null
printf '%s %s %s %s %s %s %s\n' "$PID" "$CPU_S" "$NOW" "$VERDICT" "$last_notify" "$last_restart" "$bloat_runs" > "$STATE" 2>/dev/null
printf '{"ts":%s,"pid":%s,"ctx":%s,"cpu_pct":%s,"cpu_basis":"%s","rss_mb":%s,"age_s":%s,"input_young":%s,"verdict":"%s","action":"%s"}\n' \
  "$NOW" "$PID" "$CTX" "$CPU_PCT" "$BASIS" "$RSS_MB" "$AGE_S" "$INPUT_YOUNG" "$VERDICT" "$ACTION" >> "$LOG" 2>/dev/null
printf 'coreaudiod-watch: pid=%s ctx=%s cpu=%s%% (%s) rss=%sMB input_young=%s action=%s\nverdict=%s\n' \
  "$PID" "$CTX" "$CPU_PCT" "$BASIS" "$RSS_MB" "$INPUT_YOUNG" "$ACTION" "$VERDICT"
exit 0
