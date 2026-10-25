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
# HAMMERSPOON STALL CHECK (PLAN F6, report-only; ruled 2026-10-11 in place of a heartbeat watchdog).
# Hammerspoon froze 264 s on 2026-10-09 (and 390 s and 150 s on 10-04) with nothing noticing, and
# macOS kept no hang report. Each tick: its pid from the same `ps -axo`, then ONE `ps -o etime=,time=`.
#   stall (cpu-flat)   CPU grew <= 0.05 s since the last tick AND 0.00 s across a CONFIRM_S re-read
#                      (healthy is ~1.3 s per 30 s: its 5 ms screenshot poll timer)
#   stall (thumb-open) the LAST line of screenshot.log is a thumb still shown, over 30 s old (only the
#                      last line: a thumb the next shot replaced never gets its dismissed line)
#   spin               CPU rate over the interval >= 0.8 of a core
# No verdict (hs_state=skip, baseline reset) when the process is under 60 s old, the pid changed,
# there is no earlier reading, or the wall gap is outside 30-300 s (sleep, or a late tick).
# On the ok -> stall/spin edge only: one bounded `sample` into a convoy-hs-* evidence directory (at
# most CONVOY_GAUGE_HS_SAMPLES_PER_DAY) and one page on the same desk-first path as a trip. On
# recovery: hs_stall_s (first stall tick to recovery tick) and a transitions-log line, no page.
# hs_gap_s: the longest thumb-shown -> dismissed gap over 10 s that closed since the last tick, so a
# stall shorter than a tick still leaves a row when a screenshot was up.
#   NEVER kill or signal Hammerspoon, never message it (no hs, hs.ipc or osascript), never play a
# sound. No launchd job of its own. Its state is one line in CONVOY_GAUGE_HS_STATE.
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
#   CONVOY_GAUGE_HS=on                  off = no Hammerspoon check and no hs_* fields in the row
#   CONVOY_GAUGE_HS_SAMPLES_PER_DAY=5   cap on Hammerspoon samples
# SEAMS: CONVOY_GAUGE_LOG CONVOY_GAUGE_TRANSITIONS_LOG CONVOY_GAUGE_SHED_DIR (the flag's directory)
#        CONVOY_GAUGE_EVIDENCE_DIR CONVOY_GAUGE_PS CONVOY_GAUGE_SYSCTL
#        CONVOY_GAUGE_GETCONF CONVOY_GAUGE_SAMPLE (sampler binary; 0 = no sample) CONVOY_GAUGE_SLEEP
#        CONVOY_GAUGE_NOTIFY (a cc-notify-compatible binary; 0 = no page)
#        CONVOY_GAUGE_HS_STATE CONVOY_GAUGE_HS_SCREENSHOT_LOG
# bash 3.2 safe. Ships to launchd ⇒ tested under /bin/bash.
set -uo pipefail

for a in "$@"; do
  case "$a" in
    -h|--help) sed -n 2,95p "$0"; exit 0 ;;
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
HS_STATE_FILE="${CONVOY_GAUGE_HS_STATE:-$HOME/.claude/logs/convoy-gauge-hs.state}"
HS_LOG="${CONVOY_GAUGE_HS_SCREENSHOT_LOG:-$HOME/Library/Logs/Hammerspoon/screenshot.log}"
HS_SAMPLES_PER_DAY="${CONVOY_GAUGE_HS_SAMPLES_PER_DAY:-5}"
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
  MAX=""; N_LSD=""; N_TRUSTD=""; N_SECD=""; N_TCCD=""; P_LSD=""; P_TRUSTD=""; P_SECD=""; P_TCCD=""; P_HS=""
  snap="$("$PS_BIN" -axo pid=,ppid=,uid=,state=,pri=,comm= 2>/dev/null | /usr/bin/awk -v uid="$UID" '
    { seen = 1 }
    $4 ~ /^R/ { p = $5 + 0
      if (p <= 9) bg++; else if (p <= 25) ut++; else if (p <= 36) df++; else if (p <= 63) ui++; else sy++ }
    $3 == uid && NF >= 6 {
      path = $6; for (i = 7; i <= NF; i++) path = path " " $i
      if (path ~ /\/Hammerspoon\.app\/Contents\/MacOS\/Hammerspoon$/) { print "H", $1; next }
      if ($2 != 1) next
      if (path ~ /\/CoreSimulator\//) next
      n = path; sub(/.*\//, "", n)
      if (n == "lsd" || n == "trustd" || n == "secd" || n == "tccd") print "D", n ":" $1, $1
    }
    END { if (seen) printf "B %d %d %d %d %d\n", bg, ut, df, ui, sy }')"
  BANDS=""
  while IFS= read -r line; do
    case "$line" in
      "B "*) BANDS="${line#B }" ;;
      "H "*) [ -n "$P_HS" ] || P_HS="${line#H }" ;;
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
$("$PS_BIN" -x -M -p "$pids" 2>/dev/null | /usr/bin/awk -v cands="$cands" '
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

# ── Hammerspoon stall check (see the header) ──
HS_ON=0; HS_PID=""; HS_CPU=""; HS_DELTA=""; HS_WALL=""; HS_THUMB=""; HS_STATE=""; HS_TRANS=none
HS_STALL=""; HS_SAMPLE=""; HS_GAP=""; HS_WHY=""; HS_PAGE=none; HS_JOB=""; HS_EVID=""

# hs_secs <[[dd-]hh:]mm:ss[.cc]> — a ps etime or time field in seconds (2 decimals); empty if not one.
hs_secs() {
  printf '%s\n' "$1" | /usr/bin/awk '/^[0-9]+(-[0-9]+)?(:[0-9]+)*(\.[0-9]+)?$/ { d = 0; s = $0
    if (index(s, "-")) { d = substr(s, 1, index(s, "-") - 1); s = substr(s, index(s, "-") + 1) }
    n = split(s, f, ":"); t = 0; for (i = 1; i <= n; i++) t = t * 60 + f[i]
    printf "%.2f\n", d * 86400 + t }'
}
# hs_read <pid> — one `ps -o etime=,time=`: sets HS_AGE (whole s) and HS_CPU_NOW. rc 1 if unreadable.
hs_read() {
  local e t
  # shellcheck disable=SC2046  # two whitespace-separated ps fields, split on purpose
  set -- $("$PS_BIN" -o etime=,time= -p "$1" 2>/dev/null | /usr/bin/head -1)
  e="$(hs_secs "${1:-}")"; t="$(hs_secs "${2:-}")"
  [ -n "$e" ] && [ -n "$t" ] || return 1
  HS_AGE="${e%.*}"; HS_CPU_NOW="$t"
}
# fle <a> <b> — a <= b, as decimals.
fle() { /usr/bin/awk -v a="$1" -v b="$2" 'BEGIN { exit !(a + 0 <= b + 0) }'; }

# hs_gaps — the longest thumb-shown -> dismissed gap over 10 s whose dismissal is newer than the
# last one reported (S_GAPMONO, the log's own mono clock). No earlier mark, or a clock that went
# backwards (a reboot): take the newest mono as the mark and report nothing.
hs_gaps() {
  local r newest max
  [ -f "$HS_LOG" ] || return 0
  r="$(/usr/bin/tail -n 400 "$HS_LOG" 2>/dev/null | /usr/bin/awk -v last="$S_GAPMONO" '
    { ph = ""; id = ""; mo = ""
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^phase=/) ph = substr($i, 7); else if ($i ~ /^id=/) id = substr($i, 4)
        else if ($i ~ /^mono=[0-9]+$/) mo = substr($i, 6) }
      if (mo == "") next
      mo += 0; if (mo > newest) newest = mo
      if (ph == "thumb-shown") shown[id] = mo
      else if (ph == "dismissed" && (id in shown) && last != "" && mo > last + 0) {
        g = (mo - shown[id]) / 1e9; if (g > max) max = g } }
    END { printf "%.0f %.1f\n", newest, max }')"
  newest="${r%% *}"; max="${r##* }"
  case "$newest" in ''|0|*[!0-9]*) return 0 ;; esac
  if [ -n "$S_GAPMONO" ] && ! fle "$S_GAPMONO" "$newest"; then S_GAPMONO="$newest"; return 0; fi
  S_GAPMONO="$newest"
  fle "$max" 10 || HS_GAP="$max"
}

# hs_thumb_open — HS_THUMB = seconds since the log's LAST line, when that line is a thumb still up.
hs_thumb_open() {
  local l ts e
  [ -f "$HS_LOG" ] || return 0
  l="$(/usr/bin/tail -n 1 "$HS_LOG" 2>/dev/null)"
  case "$l" in *" phase=thumb-shown "*|*" phase=thumb-visible "*) ;; *) return 0 ;; esac
  ts="${l#ts=}"; ts="${ts%% *}"                         # 2026-10-11T12:51:09.951-0500
  case "$ts" in *.[0-9][0-9][0-9][+-]*) ts="${ts%.*}${ts##*.[0-9][0-9][0-9]}" ;; esac
  e="$(/bin/date -j -f '%Y-%m-%dT%H:%M:%S%z' "$ts" +%s 2>/dev/null)"
  case "$e" in ''|*[!0-9]*) return 0 ;; esac
  HS_THUMB=$(( NOW - e ))
}

# hs_save — the one-line state: last reading, episode, gap mark, today's sample count.
hs_save() {
  (umask 022; /bin/mkdir -p "$(dirname "$HS_STATE_FILE")") 2>/dev/null
  printf 'pid=%s cpu=%s ts=%s state=%s since=%s gapmono=%s day=%s nsamp=%s\n' "$1" "$2" "$3" \
    "$S_STATE" "$S_SINCE" "$S_GAPMONO" "$TODAY" "$S_NSAMP" > "$HS_STATE_FILE.tmp.$$" 2>/dev/null \
    && /bin/mv -f "$HS_STATE_FILE.tmp.$$" "$HS_STATE_FILE" 2>/dev/null
}

hs_check() {
  local kv s_pid="" s_cpu="" s_ts="" s_day="" prev _p rc
  [ "${CONVOY_GAUGE_HS:-on}" != off ] || return 0
  HS_ON=1; S_STATE=ok; S_SINCE=""; S_GAPMONO=""; S_NSAMP=0
  TODAY="$(/bin/date +%Y%m%d)"
  if [ -f "$HS_STATE_FILE" ]; then
    for kv in $(/usr/bin/head -1 "$HS_STATE_FILE" 2>/dev/null); do
      case "$kv" in
        pid=*) s_pid="${kv#pid=}" ;; cpu=*) s_cpu="${kv#cpu=}" ;; ts=*) s_ts="${kv#ts=}" ;;
        state=*) S_STATE="${kv#state=}" ;; since=*) S_SINCE="${kv#since=}" ;;
        gapmono=*) S_GAPMONO="${kv#gapmono=}" ;; day=*) s_day="${kv#day=}" ;; nsamp=*) S_NSAMP="${kv#nsamp=}" ;;
      esac
    done
  fi
  case "$S_STATE" in ok|stall|spin) ;; *) S_STATE=ok ;; esac
  case "$S_GAPMONO" in *[!0-9]*) S_GAPMONO="" ;; esac
  case "$S_NSAMP" in ''|*[!0-9]*) S_NSAMP=0 ;; esac
  [ "$s_day" = "$TODAY" ] || S_NSAMP=0
  prev="$S_STATE"
  hs_gaps

  HS_PID="$P_HS"
  if [ -z "$HS_PID" ] || ! hs_read "$HS_PID"; then
    HS_STATE=absent; HS_PID=""
    [ "$prev" = ok ] || { HS_TRANS=gone; S_STATE=ok; S_SINCE=""; }
    hs_save "" "" ""; return 0
  fi
  HS_CPU="$HS_CPU_NOW"
  case "$s_ts" in ''|*[!0-9]*) s_ts=0 ;; esac
  HS_WALL=$(( NOW - s_ts ))
  if [ "$HS_AGE" -le 60 ] || [ "$s_pid" != "$HS_PID" ] || [ -z "$s_cpu" ] \
     || [ "$HS_WALL" -lt 30 ] || [ "$HS_WALL" -gt 300 ]; then
    HS_STATE=skip; HS_WALL=""
    # a new process ends the old one's episode; a late tick or sleep leaves it unjudged
    [ "$s_pid" = "$HS_PID" ] || { S_STATE=ok; S_SINCE=""; }
    hs_save "$HS_PID" "$HS_CPU" "$NOW"; return 0
  fi
  HS_DELTA="$(/usr/bin/awk -v a="$HS_CPU" -v b="$s_cpu" 'BEGIN { printf "%.2f", a - b }')"
  if /usr/bin/awk -v d="$HS_DELTA" -v w="$HS_WALL" 'BEGIN { exit !(d / w >= 0.8) }'; then
    HS_STATE=spin; HS_WHY=spin
  elif fle "$HS_DELTA" 0.05; then
    [ "$CONFIRM_S" = 0 ] || "$SLEEP_BIN" "$CONFIRM_S" 2>/dev/null
    _p="$HS_CPU"
    if hs_read "$HS_PID" && fle "$(/usr/bin/awk -v a="$HS_CPU_NOW" -v b="$_p" 'BEGIN { print a - b }')" 0.005; then
      HS_STATE=stall; HS_WHY=cpu-flat
    fi
  fi
  if [ -z "$HS_STATE" ]; then
    hs_thumb_open
    if [ -n "$HS_THUMB" ] && [ "$HS_THUMB" -gt 30 ]; then HS_STATE=stall; HS_WHY=thumb-open
    else HS_STATE=ok; fi
  fi

  if [ "$HS_STATE" = ok ]; then
    if [ "$prev" != ok ]; then
      HS_TRANS=recover
      case "$S_SINCE" in ''|*[!0-9]*) ;; *) HS_STALL=$(( NOW - S_SINCE )) ;; esac
      (umask 022; /bin/mkdir -p "$(dirname "$TLOG")") 2>/dev/null
      printf '%s HAMMERSPOON RECOVER pid=%s after ~%ss — report-only, nothing was touched\n' \
        "$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ)" "$HS_PID" "${HS_STALL:-?}" >> "$TLOG" 2>/dev/null
    fi
    S_STATE=ok; S_SINCE=""
  elif [ "$prev" != ok ]; then
    S_STATE="$HS_STATE"
    case "$S_SINCE" in ''|*[!0-9]*) S_SINCE="$NOW" ;; esac
    HS_STALL=$(( NOW - S_SINCE ))
  else
    HS_TRANS=stall; S_STATE="$HS_STATE"; S_SINCE="$NOW"
    # one bounded sample, in the background beside the page (perl directly, so $! is the runner)
    if [ "$SAMPLE_BIN" != 0 ] && [ -x /usr/bin/perl ] && [ "$S_NSAMP" -lt "$HS_SAMPLES_PER_DAY" ]; then
      HS_EVID="$EVID_ROOT/convoy-hs-$(/bin/date -u +%Y%m%dT%H%M%SZ)-$$"
      if (umask 077; /bin/mkdir -p "$HS_EVID") 2>/dev/null; then
        printf 'ts=%s hs_pid=%s why=%s cpu_s=%s cpu_delta_s=%s wall_s=%s thumb_open_s=%s\n' "$NOW" "$HS_PID" \
          "$HS_WHY" "$HS_CPU" "$HS_DELTA" "$HS_WALL" "${HS_THUMB:-null}" > "$HS_EVID/meta.txt" 2>/dev/null
        HS_SAMPLE="$HS_EVID/hammerspoon.sample.txt"; S_NSAMP=$(( S_NSAMP + 1 ))
        /usr/bin/perl -MPOSIX=WNOHANG -e "$BOUNDED_PL" "$SAMPLE_TIMEOUT_S" "$SAMPLE_BIN" "$HS_PID" 1 \
          -file "$HS_SAMPLE" </dev/null >/dev/null 2>&1 &
        HS_JOB=$!
      fi
    fi
    case "$HS_WHY" in
      spin) _p="spinning at $(/usr/bin/awk -v d="$HS_DELTA" -v w="$HS_WALL" 'BEGIN { printf "%.1f", d / w }') cores" ;;
      thumb-open) _p="stalled ~${HS_THUMB}s (a screenshot thumbnail is stuck on screen)" ;;
      *) _p="stalled ~${HS_WALL}s (main thread used no CPU)" ;;
    esac
    _p="Hammerspoon $_p; sample at ${HS_SAMPLE:-none (daily cap or no sampler)}; report-only, nothing was killed"
    local _keep="$PAGE"; transition "HAMMERSPOON $_p"; HS_PAGE="$PAGE"; PAGE="$_keep"
    hs_join
  fi
  hs_save "$HS_PID" "$HS_CPU" "$NOW"
}
# hs_join — wait for the Hammerspoon sample and record its rc. Safe to re-enter from the TERM trap.
hs_join() {
  local rc=0
  [ -n "$HS_JOB" ] || return 0
  wait "$HS_JOB" 2>/dev/null || rc=$?
  printf 'sample hammerspoon pid=%s rc=%s\n' "$HS_PID" "$rc" >> "$HS_EVID/meta.txt" 2>/dev/null
  HS_JOB=""
}

# hs_json — the row's hs_* fields (empty when the check is off).
hs_json() {
  local s=null
  [ "$HS_ON" = 1 ] || return 0
  if [ -n "$HS_SAMPLE" ]; then s="${HS_SAMPLE//\\/\\\\}"; s="\"${s//\"/\\\"}\""; fi
  printf ',"hs_pid":%s,"hs_cpu_s":%s,"hs_cpu_delta_s":%s,"hs_wall_s":%s,"hs_thumb_open_s":%s,"hs_state":"%s","hs_why":%s,"hs_transition":"%s","hs_stall_s":%s,"hs_sample":%s,"hs_gap_s":%s,"hs_page":"%s"' \
    "${HS_PID:-null}" "${HS_CPU:-null}" "${HS_DELTA:-null}" "${HS_WALL:-null}" "${HS_THUMB:-null}" \
    "${HS_STATE:-skip}" "$( [ -n "$HS_WHY" ] && printf '"%s"' "$HS_WHY" || echo null)" "$HS_TRANS" \
    "${HS_STALL:-null}" "$s" "${HS_GAP:-null}" "$HS_PAGE"
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
    printf '{"ts":%s,"lsd":%s,"trustd":%s,"secd":%s,"tccd":%s,"lsd_pid":%s,"trustd_pid":%s,"secd_pid":%s,"tccd_pid":%s,"max":%s,"confirm_max":%s,"run_bg":%s,"run_util":%s,"run_default":%s,"run_ui":%s,"run_sys":%s,"load1":%s,"state":"%s","prev":"%s","transition":"%s","null_hold":%s,"captured":%s,"evidence_dir":%s,"page":"%s","cut":%s%s}\n' \
      "$NOW" "${F_LSD:-null}" "${F_TRUSTD:-null}" "${F_SECD:-null}" "${F_TCCD:-null}" \
      "${F_P_LSD:-null}" "${F_P_TRUSTD:-null}" "${F_P_SECD:-null}" "${F_P_TCCD:-null}" "${F_MAX:-null}" "${CONFIRM_MAX:-null}" \
      "${RUN_BG:-null}" "${RUN_UTIL:-null}" "${RUN_DEFAULT:-null}" "${RUN_UI:-null}" "${RUN_SYS:-null}" "${LOAD1:-null}" \
      "$STATE" "$PREV" "$TRANSITION" "$_nh" "$CAPTURED" "$_evid_json" "$PAGE" "$CUT" "$(hs_json)" >> "$LOG" 2>/dev/null
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
  for j in $JOBS $HS_JOB; do kill -TERM "${j##*:}" 2>/dev/null; done
  capture_finish
  hs_join
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
hs_check
finish "$RC"
