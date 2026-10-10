#!/bin/bash
# convoy-gauge.sh — detect a LaunchServices/trust/keychain lock convoy early, and capture the
# evidence nobody has yet. DETECT-ONLY: it never refuses, blocks, pauses or kills anything.
#
# WHAT IT WATCHES. On 2026-10-09 21:26-21:34 the user's lsd held its database lock for ~7.5 minutes
# while a registerSelf write waited on trustd, which waited on secd. About 45 lsd threads piled up
# behind it; Claude TUIs froze on a clipboard read and coreaudiod parked in a TCC preflight. Load
# did not predict it: no convoy at load 503, a convoy at ~197.
#
# THE INSTRUMENT is the THREAD COUNT of the current user's lsd, trustd, secd and tccd: 2-7 at rest
# even at load 297-503, 45 during that freeze, 84 in a 2026-10-04 incident. Nobody has sampled secd
# during a convoy, so the root cause is still unknown; the main job here is to capture that at the
# next one. A daemon that is absent or unreadable is recorded as null, never as 0 (0 would read as
# "at rest").
#   HOST INSTANCES ONLY. The iOS Simulator runs its own lsd, trustd and tccd as children of
# launchd_sim, under our uid and with our names; measured 2026-10-10, its trustd rests at 8 threads
# against the host's 2-3, so reading it would make every reading, and every sample, the simulator's.
# An instance counts only if its parent is launchd (ppid 1) and its path is not under CoreSimulator.
# With several host instances of one name, the busiest is the reading; its pid goes in the row.
#
# ONE SHOT, called once per tick by scripts/capacity-alarm.sh (launchd, ~60 s), which bounds it and
# ignores its exit code and output. Each run appends ONE row to the JSONL log:
#   ts, lsd, trustd, secd, tccd, lsd_pid, trustd_pid, secd_pid, tccd_pid, max, confirm_max,
#   run_bg/run_util/run_default/run_ui/run_sys (runnable processes per priority band, from the
#   same ONE `ps -axo` that finds the daemons), load1, state, prev, transition (none|trip|clear), null_hold, captured,
#   evidence_dir, page, cut
# The row is written on every exit path but SIGKILL: a TERM (the caller's bound) writes it with
# cut=true after the gauge has cut its own bounded children and released its lock.
#
# STATE, with hysteresis: TRIP when max >= TRIP_THREADS and a second read CONFIRM_S later agrees
# (one busy instant is not a convoy); CLEAR when max <= CLEAR_THREADS; in between, the previous
# state holds. The previous state IS the flag below: there is no sidecar to go stale.
#   A NULL HOLDS A TRIP. While tripped, a daemon that cannot be read now but was over the clear
# ceiling at its last reading keeps the state tripped (null_hold names it): losing sight of the
# daemon that tripped is not evidence that it recovered.
#
# THE FLAG: "$(getconf DARWIN_USER_TEMP_DIR)/cc-shed/active", written on the trip edge and rewritten
# on every tripped run: `since=<epoch>` and each daemon's last known count (a null carries the
# previous count forward). Removed on clear.
#   CONSUMERS MUST IGNORE A FLAG OLDER THAN 300 s: a gauge that died while tripped cannot remove
# it. The gauge applies the same rule to itself, so a stale flag reads as "was clear".
#
# ON THE TRIP EDGE ONLY (clear -> tripped), single-flight under a lock dir (a concurrent run skips
# the edge entirely; a lock whose holder is dead, or older than LOCK_STALE_S, is broken): a new
# directory under ~/.claude/logs/convoy-evidence/ gets `ps -M` and one `sample <pid> 1` per present
# daemon. The samples run in parallel with the page, each bounded, so a wedged sample cannot wedge
# the gauge. No bounded runner (/usr/bin/perl) means no sample, never an unbounded one.
#
# ON EACH TRANSITION ONLY (trip edge, clear edge): the line goes to the transitions log and stderr
# FIRST, so it is never lost, then ONE page through cc-notify --role, trying `desk` and then
# `orchestrator`, phone fallback off: a pane only. No osascript and no afplay, because starting an
# audio or AppleEvent client during a convoy is what parked coreaudiod. The row's page field names
# the role that took it, or every role's rc.
#
# BOUNDS: every bounded child gets its own process group; a cut sends TERM to the group, then KILL
# 2 s later, so cc-notify's TERM trap can still print its verdict. A TERM to the gauge itself cuts
# its running samples the same way and waits for them before it writes the row.
#
# EXIT: 0 on a completed read, whatever the state · 3 when no daemon could be measured (the row is
# still written, the flag is left alone) · 143 when cut by TERM · 2 usage.
#
# ENV (thresholds from the two incidents above)
#   CONVOY_GAUGE=0                      kill switch: prints state=clear, touches nothing
#   CONVOY_GAUGE_TRIP_THREADS=16        trip floor (rest is 2-7; the incidents read 45 and 84)
#   CONVOY_GAUGE_CLEAR_THREADS=8        clear ceiling
#   CONVOY_GAUGE_CONFIRM_S=5            delay before the confirming read (0 = no delay)
#   CONVOY_GAUGE_FLAG_STALE_S=300       a flag older than this is not a previous state
#   CONVOY_GAUGE_LOCK_STALE_S=90        an edge lock older than this is broken (a run lives < 50 s)
#   CONVOY_GAUGE_SAMPLE_TIMEOUT_S=15    bound on each `sample`
#   CONVOY_GAUGE_PAGE_TIMEOUT_S=10      bound on each page attempt
#   CONVOY_GAUGE_EVIDENCE_KEEP=30       newest N evidence directories kept
# SEAMS: CONVOY_GAUGE_LOG CONVOY_GAUGE_TRANSITIONS_LOG CONVOY_GAUGE_SHED_DIR (the flag's directory)
#        CONVOY_GAUGE_EVIDENCE_DIR CONVOY_GAUGE_PS CONVOY_GAUGE_SYSCTL
#        CONVOY_GAUGE_GETCONF CONVOY_GAUGE_SAMPLE (sampler binary; 0 = no sample) CONVOY_GAUGE_SLEEP
#        CONVOY_GAUGE_NOTIFY (a cc-notify-compatible binary; 0 = no page)
# bash 3.2 safe. Ships to launchd ⇒ tested under /bin/bash.
set -uo pipefail

for a in "$@"; do
  case "$a" in
    -h|--help) sed -n 2,76p "$0"; exit 0 ;;
    *) echo "convoy-gauge: unknown argument: $a" >&2; exit 2 ;;
  esac
done

if [ "${CONVOY_GAUGE:-1}" = 0 ]; then
  printf 'convoy-gauge: disabled (CONVOY_GAUGE=0)\nstate=clear\n'; exit 0
fi

TRIP="${CONVOY_GAUGE_TRIP_THREADS:-16}"
CLEAR="${CONVOY_GAUGE_CLEAR_THREADS:-8}"
CONFIRM_S="${CONVOY_GAUGE_CONFIRM_S:-5}"
FLAG_STALE_S="${CONVOY_GAUGE_FLAG_STALE_S:-300}"
LOCK_STALE_S="${CONVOY_GAUGE_LOCK_STALE_S:-90}"
SAMPLE_TIMEOUT_S="${CONVOY_GAUGE_SAMPLE_TIMEOUT_S:-15}"
PAGE_TIMEOUT_S="${CONVOY_GAUGE_PAGE_TIMEOUT_S:-10}"
EVIDENCE_KEEP="${CONVOY_GAUGE_EVIDENCE_KEEP:-30}"
PS_BIN="${CONVOY_GAUGE_PS:-/bin/ps}"
SYSCTL_BIN="${CONVOY_GAUGE_SYSCTL:-/usr/sbin/sysctl}"
GETCONF_BIN="${CONVOY_GAUGE_GETCONF:-/usr/bin/getconf}"
SAMPLE_BIN="${CONVOY_GAUGE_SAMPLE:-/usr/bin/sample}"
SLEEP_BIN="${CONVOY_GAUGE_SLEEP:-/bin/sleep}"
LOG="${CONVOY_GAUGE_LOG:-$HOME/.claude/logs/convoy-gauge.jsonl}"
TLOG="${CONVOY_GAUGE_TRANSITIONS_LOG:-$HOME/.claude/logs/convoy-gauge-transitions.log}"
EVID_ROOT="${CONVOY_GAUGE_EVIDENCE_DIR:-$HOME/.claude/logs/convoy-evidence}"
PAGE_ROLES="desk orchestrator"
NOW="$(/bin/date +%s)"

# The flag's directory. launchd exports the same per-user temp dir as TMPDIR, so that is the
# fallback when getconf answers nothing: a consumer still finds the flag where it looks.
SHED_DIR="${CONVOY_GAUGE_SHED_DIR:-}"
if [ -z "$SHED_DIR" ]; then
  _t="$("$GETCONF_BIN" DARWIN_USER_TEMP_DIR 2>/dev/null)"
  [ -n "$_t" ] && [ -d "$_t" ] || _t="${TMPDIR:-/tmp}"
  SHED_DIR="${_t%/}/cc-shed"
fi
FLAG="$SHED_DIR/active"
LOCK="$SHED_DIR/convoy-gauge.lock"

# The page transport: cc-notify beside this file's real path (~/.claude/scripts/convoy-gauge.sh is a
# per-file symlink into the checkout), else the deployed one.
NOTIFY_BIN="${CONVOY_GAUGE_NOTIFY:-}"
if [ -z "$NOTIFY_BIN" ]; then
  _self="${BASH_SOURCE[0]}"
  while [ -L "$_self" ]; do
    _d="$(cd -P "$(dirname "$_self")" && pwd)"; _self="$(readlink "$_self")"
    case "$_self" in /*) ;; *) _self="$_d/$_self" ;; esac
  done
  for _c in "$(cd -P "$(dirname "$_self")" && pwd)/../bin/cc-notify" "$HOME/.claude/bin/cc-notify"; do
    [ -x "$_c" ] && { NOTIFY_BIN="$_c"; break; }
  done
fi

# The bounded runner: perl <seconds> <cmd…> — rc 124 on a cut at the bound, 143 when the runner
# itself is TERMed. The child gets its own process group; a cut sends TERM to the group, waits up to
# 2 s for the child, then KILLs the group, so a grandchild cannot keep a pipe (or us) waiting.
# shellcheck disable=SC2016  # perl source: its $vars are perl's, never the shell's
BOUNDED_PL='my $t = shift; my $p = fork; exit 1 unless defined $p;
  if (!$p) { setpgrp(0, 0); exec @ARGV; exit 127 }
  sub cut { my $rc = shift; $SIG{ALRM} = $SIG{TERM} = "IGNORE";
    kill "TERM", -$p; kill "TERM", $p;
    for (1 .. 20) { last if waitpid($p, WNOHANG) != 0; select(undef, undef, undef, 0.1) }
    kill "KILL", -$p; kill "KILL", $p; exit $rc }
  $SIG{ALRM} = sub { cut(124) }; $SIG{TERM} = sub { cut(143) };
  alarm $t; waitpid($p, 0); exit($? >> 8)'
# bounded <seconds> <cmd…> — rc 3 with no bounded runner.
bounded() {
  [ -x /usr/bin/perl ] || return 3
  /usr/bin/perl -MPOSIX=WNOHANG -e "$BOUNDED_PL" "$@"
}

# read_all — one read of the four daemons, in TWO forks of ps whatever the instance count (the
# per-daemon pgrep + ps chain this replaced cost ~1-1.5 s a run at load 80-140, against a
# budget of well under 1 s): ONE `ps -axo` over every process gives the runnable count per priority
# band (BANDS) and the HOST instances of each daemon — ours (uid), launchd's child (ppid 1), not
# under CoreSimulator (see the header); then ONE `ps -M` over those pids gives their thread counts
# (a header, then one row per thread: the first row of a process starts with USER, the rest with
# the pid). The busiest instance of each name is its reading. A pid that vanished between the two
# prints no rows, and that is "unreadable", not 0. Sets N_<name>, P_<name>, MAX (empty = none
# readable) and BANDS.
read_all() {
  local snap cands="" pids="" line d n pid
  MAX=""; N_LSD=""; N_TRUSTD=""; N_SECD=""; N_TCCD=""; P_LSD=""; P_TRUSTD=""; P_SECD=""; P_TCCD=""
  snap="$("$PS_BIN" -axo pid=,ppid=,uid=,state=,pri=,comm= 2>/dev/null | /usr/bin/awk -v uid="$UID" '
    { seen = 1 }
    $4 ~ /^R/ { p = $5 + 0
      if (p <= 9) bg++; else if (p <= 25) ut++; else if (p <= 36) df++; else if (p <= 63) ui++; else sy++ }
    $3 == uid && $2 == 1 && NF >= 6 {
      path = $6; for (i = 7; i <= NF; i++) path = path " " $i
      if (path ~ /\/CoreSimulator\//) next
      n = path; sub(/.*\//, "", n)
      if (n == "lsd" || n == "trustd" || n == "secd" || n == "tccd") print "D", n ":" $1, $1
    }
    END { if (seen) printf "B %d %d %d %d %d\n", bg, ut, df, ui, sy }')"
  BANDS=""
  while IFS= read -r line; do
    case "$line" in
      "B "*) BANDS="${line#B }" ;;
      "D "*) line="${line#D }"; cands="$cands${cands:+ }${line%% *}"; pids="$pids${pids:+,}${line##* }" ;;
    esac
  done <<EOF
$snap
EOF
  [ -n "$pids" ] || return 0
  while read -r d n pid; do
    case "$n" in ''|*[!0-9]*) continue ;; esac
    case "$d" in
      lsd)    N_LSD="$n";    P_LSD="$pid" ;;
      trustd) N_TRUSTD="$n"; P_TRUSTD="$pid" ;;
      secd)   N_SECD="$n";   P_SECD="$pid" ;;
      tccd)   N_TCCD="$n";   P_TCCD="$pid" ;;
      *) continue ;;
    esac
    if [ -z "$MAX" ] || [ "$n" -gt "$MAX" ]; then MAX="$n"; fi
  done <<EOF
$("$PS_BIN" -M -p "$pids" 2>/dev/null | /usr/bin/awk -v cands="$cands" '
  BEGIN { m = split(cands, L, " "); for (i = 1; i <= m; i++) { split(L[i], f, ":"); name[f[2]] = f[1] } }
  NR > 1 { pid = ($1 ~ /^[0-9]+$/) ? $1 : $2; c[pid]++ }
  END { for (p in c) if (p in name) { k = name[p]; if (!(k in best) || c[p] > best[k]) { best[k] = c[p]; bp[k] = p } }
        for (k in best) print k, best[k], bp[k] }')
EOF
}

counts() { printf 'lsd=%s trustd=%s secd=%s tccd=%s' "${F_LSD:-null}" "${F_TRUSTD:-null}" "${F_SECD:-null}" "${F_TCCD:-null}"; }

# flag_count <name> — the daemon's last known count in the flag (empty if none).
flag_count() { printf '%s\n' "$FLAG_BODY" | /usr/bin/sed -n "s/.* $1=\([0-9][0-9]*\).*/\1/p" | /usr/bin/head -1; }

# write_flag — since and each daemon's last known count (a null carries the flag's count forward).
write_flag() {
  local l t s c
  [ -L "$FLAG" ] && return 0
  l="${F_LSD:-$(flag_count lsd)}"; t="${F_TRUSTD:-$(flag_count trustd)}"
  s="${F_SECD:-$(flag_count secd)}"; c="${F_TCCD:-$(flag_count tccd)}"
  printf 'since=%s lsd=%s trustd=%s secd=%s tccd=%s\n' "$1" "${l:-null}" "${t:-null}" "${s:-null}" "${c:-null}" \
    > "$FLAG.tmp.$$" 2>/dev/null && /bin/mv -f "$FLAG.tmp.$$" "$FLAG" 2>/dev/null
}

# capture_start — the trip-edge evidence: ps -M now, and the samples started in the background
# (finished by capture_finish). Sets EVID and CAPTURED. Uses the pids of the newest read.
JOBS=""; CAPTURE_OPEN=0
capture_start() {
  local dir d pid
  dir="$EVID_ROOT/convoy-$(/bin/date -u +%Y%m%dT%H%M%SZ)-$$"
  (umask 077; /bin/mkdir -p "$dir") 2>/dev/null || return 1
  EVID="$dir"; CAPTURE_OPEN=1
  printf 'ts=%s %s pids=%s,%s,%s,%s max=%s confirm_max=%s load1=%s\n' "$NOW" "$(counts)" \
    "${P_LSD:-null}" "${P_TRUSTD:-null}" "${P_SECD:-null}" "${P_TCCD:-null}" \
    "${F_MAX:-null}" "${CONFIRM_MAX:-null}" "${LOAD1:-null}" > "$dir/meta.txt" 2>/dev/null
  for d in lsd trustd secd tccd; do
    case "$d" in
      lsd) pid="$P_LSD" ;; trustd) pid="$P_TRUSTD" ;; secd) pid="$P_SECD" ;; tccd) pid="$P_TCCD" ;;
    esac
    [ -n "$pid" ] || continue
    "$PS_BIN" -M -p "$pid" > "$dir/$d.ps-M.txt" 2>&1 && CAPTURED=true
    [ "$SAMPLE_BIN" != 0 ] || continue
    if [ -x /usr/bin/perl ]; then
      # perl directly (not through the function), so $! is the runner a TERM must reach
      /usr/bin/perl -MPOSIX=WNOHANG -e "$BOUNDED_PL" "$SAMPLE_TIMEOUT_S" "$SAMPLE_BIN" "$pid" 1 \
        -file "$dir/$d.sample.txt" </dev/null >/dev/null 2>&1 &
      JOBS="$JOBS${JOBS:+ }$d:$pid:$!"
    else
      printf 'sample %s pid=%s rc=3\n' "$d" "$pid" >> "$dir/meta.txt" 2>/dev/null
    fi
  done
  return 0
}

# capture_finish — wait for each sample, record its rc, prune. Safe to re-enter from the TERM trap:
# a job leaves JOBS only after its rc is recorded.
# sample_rc: 0 written · 124 cut at the bound · 143 cut by a TERM to the gauge · 3 no bounded runner
capture_finish() {
  local j rc d pid
  [ "$CAPTURE_OPEN" = 1 ] || return 0
  while [ -n "$JOBS" ]; do
    j="${JOBS%% *}"
    rc=0; wait "${j##*:}" 2>/dev/null || rc=$?
    d="${j%%:*}"; pid="${j#*:}"; pid="${pid%%:*}"
    printf 'sample %s pid=%s rc=%s\n' "$d" "$pid" "$rc" >> "$EVID/meta.txt" 2>/dev/null
    case "$JOBS" in *" "*) JOBS="${JOBS#* }" ;; *) JOBS="" ;; esac
  done
  CAPTURE_OPEN=0
  # Newest EVIDENCE_KEEP directories kept; only this gauge's own convoy-* directories are listed.
  /bin/ls -1dt "$EVID_ROOT"/convoy-* 2>/dev/null | /usr/bin/tail -n +$(( EVIDENCE_KEEP + 1 )) \
    | while IFS= read -r _old; do [ -d "$_old" ] && /bin/rm -rf "$_old"; done
  return 0
}

# transition <message> — the line goes to the transitions log and stderr BEFORE any page is tried,
# then one page: each role in PAGE_ROLES in turn, until one reports verdict=delivered. Sets PAGE.
transition() {
  local out rc v role tried=""
  (umask 022; /bin/mkdir -p "$(dirname "$TLOG")") 2>/dev/null
  printf '%s %s\n' "$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" >> "$TLOG" 2>/dev/null
  echo "convoy-gauge: $1" >&2
  if [ "$NOTIFY_BIN" = 0 ]; then PAGE=off; return 0; fi
  if [ -z "$NOTIFY_BIN" ]; then PAGE=no-transport; return 0; fi
  if [ ! -x /usr/bin/perl ]; then PAGE=no-bounded-runner; return 0; fi
  PAGE=pending
  for role in $PAGE_ROLES; do
    rc=0
    out="$(CC_NOTIFY_PHONE_FALLBACK=0 bounded "$PAGE_TIMEOUT_S" "$NOTIFY_BIN" --role "$role" "$1" 2>&1 >/dev/null </dev/null)" || rc=$?
    v="$(printf '%s' "$out" | /usr/bin/grep -oE 'verdict=[a-z-]+' | /usr/bin/head -1)"
    if [ "$rc" = 0 ] && [ "$v" = "verdict=delivered" ]; then PAGE="$role"; return 0; fi
    tried="$tried${tried:+,}$role=rc$rc"
  done
  PAGE="undelivered:$tried"
}

# finish <rc> — every exit path: release the lock, write the row (once), print the summary.
ROW_DONE=0; HELD=0; CUT=false
finish() {
  local _evid_json=null _e _nh=null
  if [ "$HELD" = 1 ]; then /bin/rm -f "$LOCK/pid" 2>/dev/null; /bin/rmdir "$LOCK" 2>/dev/null; HELD=0; fi
  if [ "$ROW_DONE" = 0 ]; then
    ROW_DONE=1
    if [ -n "$EVID" ]; then _e="${EVID//\\/\\\\}"; _evid_json="\"${_e//\"/\\\"}\""; fi
    [ -z "$NULL_HOLD" ] || _nh="\"$NULL_HOLD\""
    (umask 022; /bin/mkdir -p "$(dirname "$LOG")") 2>/dev/null
    printf '{"ts":%s,"lsd":%s,"trustd":%s,"secd":%s,"tccd":%s,"lsd_pid":%s,"trustd_pid":%s,"secd_pid":%s,"tccd_pid":%s,"max":%s,"confirm_max":%s,"run_bg":%s,"run_util":%s,"run_default":%s,"run_ui":%s,"run_sys":%s,"load1":%s,"state":"%s","prev":"%s","transition":"%s","null_hold":%s,"captured":%s,"evidence_dir":%s,"page":"%s","cut":%s}\n' \
      "$NOW" "${F_LSD:-null}" "${F_TRUSTD:-null}" "${F_SECD:-null}" "${F_TCCD:-null}" \
      "${F_P_LSD:-null}" "${F_P_TRUSTD:-null}" "${F_P_SECD:-null}" "${F_P_TCCD:-null}" "${F_MAX:-null}" "${CONFIRM_MAX:-null}" \
      "${RUN_BG:-null}" "${RUN_UTIL:-null}" "${RUN_DEFAULT:-null}" "${RUN_UI:-null}" "${RUN_SYS:-null}" "${LOAD1:-null}" \
      "$STATE" "$PREV" "$TRANSITION" "$_nh" "$CAPTURED" "$_evid_json" "$PAGE" "$CUT" >> "$LOG" 2>/dev/null
    printf 'convoy-gauge: %s max=%s load1=%s transition=%s captured=%s page=%s cut=%s\nstate=%s\n' \
      "$(counts)" "${F_MAX:-null}" "${LOAD1:-null}" "$TRANSITION" "$CAPTURED" "$PAGE" "$CUT" "$STATE"
  fi
  exit "$1"
}

# on_term — the caller's bound (or anyone) cut us: cut our own running samples (each runner sends
# TERM to its sample's group, then KILL 2 s later), wait for them, then write the row and go.
# shellcheck disable=SC2329  # invoked by the TERM/INT/HUP trap below
on_term() {
  local j
  trap '' TERM INT HUP
  CUT=true
  for j in $JOBS; do kill -TERM "${j##*:}" 2>/dev/null; done
  capture_finish
  [ "$PAGE" != pending ] || PAGE="cut"
  finish 143
}

N_LSD=""; N_TRUSTD=""; N_SECD=""; N_TCCD=""; P_LSD=""; P_TRUSTD=""; P_SECD=""; P_TCCD=""
F_LSD=""; F_TRUSTD=""; F_SECD=""; F_TCCD=""; F_P_LSD=""; F_P_TRUSTD=""; F_P_SECD=""; F_P_TCCD=""
F_MAX=""; CONFIRM_MAX=""; LOAD1=""; RUN_BG=""; RUN_UTIL=""; RUN_DEFAULT=""; RUN_UI=""; RUN_SYS=""
TRANSITION=none; CAPTURED=false; EVID=""; PAGE=none; NULL_HOLD=""

# ── previous state: the flag, if it is fresh ──
PREV=clear; SINCE=""; FLAG_BODY=""
if [ -f "$FLAG" ] && [ ! -L "$FLAG" ]; then
  _m="$(/usr/bin/stat -f %m "$FLAG" 2>/dev/null)"
  case "$_m" in ''|*[!0-9]*) _m=0 ;; esac
  if [ $(( NOW - _m )) -lt "$FLAG_STALE_S" ]; then
    PREV=tripped
    FLAG_BODY="$(/usr/bin/head -1 "$FLAG" 2>/dev/null)"
    SINCE="$(printf '%s\n' "$FLAG_BODY" | /usr/bin/sed -n 's/^since=\([0-9][0-9]*\).*/\1/p')"
  fi
fi
STATE="$PREV"
trap on_term TERM INT HUP

# ── read ──
read_all
F_LSD="$N_LSD"; F_TRUSTD="$N_TRUSTD"; F_SECD="$N_SECD"; F_TCCD="$N_TCCD"; F_MAX="$MAX"
F_P_LSD="$P_LSD"; F_P_TRUSTD="$P_TRUSTD"; F_P_SECD="$P_SECD"; F_P_TCCD="$P_TCCD"

# Runnable processes per Darwin priority band, from the first read's one `ps -axo` (background
# PRI 4, utility 20, default 31, user-initiated/interactive 37-47, above that the system's own).
# Unreadable ⇒ null.
if [ -n "$BANDS" ]; then
  # shellcheck disable=SC2086  # five space-separated integers from read_all's awk
  set -- $BANDS
  RUN_BG="$1"; RUN_UTIL="$2"; RUN_DEFAULT="$3"; RUN_UI="$4"; RUN_SYS="$5"
fi
LOAD1="$("$SYSCTL_BIN" -n vm.loadavg 2>/dev/null | /usr/bin/awk '{ for (i = 1; i <= NF; i++) if ($i ~ /^[0-9.]+$/) { print $i; exit } }')"

# ── classify ──
RC=0
if [ -z "$F_MAX" ]; then
  STATE="$PREV"; RC=3                       # nothing measured: no verdict, and the flag is left alone
elif [ "$F_MAX" -ge "$TRIP" ]; then
  if [ "$PREV" = tripped ]; then STATE=tripped
  else
    # One busy instant is not a convoy: the same floor must hold on a second read.
    [ "$CONFIRM_S" = 0 ] || "$SLEEP_BIN" "$CONFIRM_S" 2>/dev/null
    read_all
    CONFIRM_MAX="$MAX"
    if [ -n "$CONFIRM_MAX" ] && [ "$CONFIRM_MAX" -ge "$TRIP" ]; then STATE=tripped; else STATE=clear; fi
  fi
elif [ "$F_MAX" -le "$CLEAR" ]; then
  STATE=clear
  if [ "$PREV" = tripped ]; then
    # A null holds a trip: a daemon we cannot see now, last seen over the clear ceiling.
    for _d in lsd trustd secd tccd; do
      case "$_d" in lsd) _n="$F_LSD" ;; trustd) _n="$F_TRUSTD" ;; secd) _n="$F_SECD" ;; tccd) _n="$F_TCCD" ;; esac
      [ -z "$_n" ] || continue
      _l="$(flag_count "$_d")"
      if [ -n "$_l" ] && [ "$_l" -gt "$CLEAR" ]; then NULL_HOLD="$NULL_HOLD${NULL_HOLD:+,}$_d"; fi
    done
    [ -z "$NULL_HOLD" ] || STATE=tripped
  fi
else STATE="$PREV"; fi

# ── act on the state: flag, and on an edge the transition line, the evidence and the page ──
if [ "$RC" = 0 ] && [ "$STATE" = tripped ]; then
  (umask 077; /bin/mkdir -p "$SHED_DIR") 2>/dev/null
  if [ "$PREV" = clear ]; then
    # Single-flight. A lock whose holder is gone, or older than LOCK_STALE_S, is broken.
    if [ -d "$LOCK" ]; then
      _m="$(/usr/bin/stat -f %m "$LOCK" 2>/dev/null)"
      case "$_m" in ''|*[!0-9]*) _m="$NOW" ;; esac
      _h="$(/usr/bin/head -1 "$LOCK/pid" 2>/dev/null)"
      _stale=0
      [ $(( NOW - _m )) -lt "$LOCK_STALE_S" ] || _stale=1
      case "$_h" in ''|*[!0-9]*) ;; *) kill -0 "$_h" 2>/dev/null || _stale=1 ;; esac
      if [ "$_stale" = 1 ]; then /bin/rm -f "$LOCK/pid" 2>/dev/null; /bin/rmdir "$LOCK" 2>/dev/null; fi
    fi
    if /bin/mkdir "$LOCK" 2>/dev/null; then
      HELD=1; echo "$$" > "$LOCK/pid" 2>/dev/null
      TRANSITION=trip
      write_flag "$NOW"
      capture_start
      transition "TRIP $(counts) (trip >= $TRIP threads) — a Claude pane can freeze about 1 s after you focus it; avoid cycling panes until the clear line. Evidence: ${EVID:-none}"
      capture_finish
    fi
  else
    write_flag "${SINCE:-$NOW}"
  fi
elif [ "$RC" = 0 ]; then
  /bin/rm -f "$FLAG" 2>/dev/null
  if [ "$PREV" = tripped ]; then
    TRANSITION=clear
    case "$SINCE" in ''|*[!0-9]*) _dur="an unknown time" ;; *) _dur="$(printf '%dm%02ds' $(( (NOW - SINCE) / 60 )) $(( (NOW - SINCE) % 60 )))" ;; esac
    transition "CLEAR $(counts) (clear <= $CLEAR threads) — tripped for $_dur; panes are safe to cycle again."
  fi
fi
finish "$RC"
