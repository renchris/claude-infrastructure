#!/bin/bash
# capacity-ramp.sh — staged residency ramp for docs/plans/CONCURRENCY_PROGRAM.md § S6-DOD, D1.
#
# WHY THIS EXISTS. D1 is the one criterion the DoD says analysis cannot satisfy: every
# 150-session figure in that program is an 8x extrapolation from a 19-session sample, and only a
# real ramp closes the gap. This is its execution vehicle.
#
# THE UNIT IS A *RESIDENT* SESSION, NOT A WORKING ONE. Each unit is the claude binary on its own
# pty with stdin held open by a fifo, submitting nothing: full RSS, one pty, ZERO tokens. That is
# exactly what "150 resident" means in S6.2's model (150 resident, ~10 active), so the expensive
# half of the target is testable without spending quota.
#
# 🚨 IDENTITY IS BY TRACKED PID, NEVER BY AGE OR PATTERN. Every pid this script spawns is appended
# to PIDFILE and `down` kills only those. This is not stylistic. On 2026-08-09 a cleanup in this
# very investigation killed by the heuristic "any claude younger than 4 minutes" — and a
# freshly-fired peer session is young BY CONSTRUCTION, so that predicate cannot distinguish this
# script's units from the operator's live work. It happened to hit only its own probes; it could
# not have known that. Age is not identity. Neither is `pgrep -f claude`, which on this box matches
# any session whose ARGV merely mentions the string (measured: 9 by argv, 0 by command position).
#
# 🚨 THE ACTUATOR DOES NOT COVER THIS. compressor-sentinel excludes claude.exe/claude from its
# SIGSTOP cohort by construction (compressor-sentinel.sh:280,330) — correctly, so it never freezes
# the operator's sessions. The consequence is that a memory blowout driven by claude processes
# themselves has NOTHING above it: CONFIG_JETSAM is off and the fleet sits in jetsam band 180. So
# this script carries its OWN floor and aborts on it. That floor is the only backstop the ramp has.
set -uo pipefail

BIN="${CC_RAMP_BIN:-$HOME/.claude-220/node_modules/.bin/claude}"
PIDFILE="${CC_RAMP_PIDFILE:-/tmp/cc-ramp-pids.txt}"
FIFODIR="${CC_RAMP_FIFODIR:-/tmp}"
FLOOR_GB="${CC_RAMP_FLOOR_GB:-8}"     # abort below this (free+purgeable); the alarm's WARN line
SEG_MAX="${CC_RAMP_SEG_MAX:-15}"      # abort at/above this seg_pct — the sentinel's own trip level
SETTLE="${CC_RAMP_SETTLE:-4}"         # seconds between unit launches

avail_gb() { vm_stat 2>/dev/null | awk '
  /^Pages free:/        {gsub(/[^0-9]/,"",$NF); f=$NF}
  /^Pages purgeable:/   {gsub(/[^0-9]/,"",$NF); p=$NF}
  END { printf "%.2f", (f+p)*16384/1073741824 }'; }
# shellcheck disable=SC2009  # pgrep is the FORBIDDEN instrument here, not the preferred one:
# `pgrep -f` matches ARGV, and on this box argv carries whole agent briefs, so it counts every
# session that merely MENTIONS the string (measured 2026-08-09: 9 by argv, 0 by command position).
# Grepping `ps -axo comm=` anchors on the COMMAND POSITION, which is the whole point.
sessions() { ps -axo comm= 2>/dev/null | grep -c 'node_modules/.bin/claude'; }
# shellcheck disable=SC2009  # same reason: comm=/tty= are command-position reads, not argv matches.
ptys()     { ps -axo tty=  2>/dev/null | grep '^ttys' | sort -u | wc -l | tr -d ' '; }
seg_pct()  { tail -1 "$HOME/.claude/logs/compressor-sentinel.jsonl" 2>/dev/null \
               | jq -r '.pct // 0' 2>/dev/null || echo 0; }
# shellcheck disable=SC2012  # panic filenames are Apple-generated and alphanumeric; a count is all
# D2 needs, and `find` here would add a directory walk to a hot per-unit loop.
panics()   { ls -1 /Library/Logs/DiagnosticReports/*.panic 2>/dev/null | wc -l | tr -d ' '; }

# breach: echoes the reason and returns 0 when a D2-D6 abort condition holds.
breach() {
  local a s
  a="$(avail_gb)"; s="$(seg_pct)"
  awk -v a="$a" -v f="$FLOOR_GB" 'BEGIN{exit !(a+0 < f+0)}' && { echo "D6 memory: ${a}GB < ${FLOOR_GB}GB floor"; return 0; }
  awk -v s="$s" -v m="$SEG_MAX" 'BEGIN{exit !(s+0 >= m+0)}' && { echo "D3 segments: ${s}% >= ${SEG_MAX}%"; return 0; }
  return 1
}

stat_line() {
  printf 'sessions=%s ptys=%s avail=%sGB seg=%s%% panics=%s\n' \
    "$(sessions)" "$(ptys)" "$(avail_gb)" "$(seg_pct)" "$(panics)"
}

up() {
  local n="${1:?usage: up <n>}" i reason
  [ -x "$BIN" ] || { echo "capacity-ramp: binary not executable: $BIN" >&2; return 2; }
  for i in $(seq 1 "$n"); do
    if reason="$(breach)"; then
      echo "capacity-ramp: ABORT before unit $i — $reason" >&2
      return 3
    fi
    mkfifo "$FIFODIR/ccramp.$$.$i.fifo" 2>/dev/null || true
    ( sleep 7200 > "$FIFODIR/ccramp.$$.$i.fifo" ) & echo "$!" >> "$PIDFILE"
    script -q /dev/null "$BIN" < "$FIFODIR/ccramp.$$.$i.fifo" >/dev/null 2>&1 & echo "$!" >> "$PIDFILE"
    sleep "$SETTLE"
  done
  echo "capacity-ramp: up $n complete — $(stat_line)"
}

down() {
  [ -f "$PIDFILE" ] || { echo "capacity-ramp: no pidfile — nothing this script spawned"; return 0; }
  local p
  while read -r p; do [ -n "$p" ] && kill -TERM "$p" 2>/dev/null; done < "$PIDFILE"
  sleep 4
  while read -r p; do [ -n "$p" ] && kill -KILL "$p" 2>/dev/null; done < "$PIDFILE"
  rm -f "$PIDFILE" "$FIFODIR"/ccramp.*.fifo
  echo "capacity-ramp: down complete — $(stat_line)"
}

case "${1:-}" in
  up)     shift; up "$@" ;;
  down)   down ;;
  stat)   stat_line ;;
  breach) if r="$(breach)"; then echo "BREACH: $r"; exit 1; else echo "OK: $(stat_line)"; fi ;;
  *) cat >&2 <<USAGE
usage: capacity-ramp.sh {up <n>|down|stat|breach}
  up <n>   launch n RESIDENT idle sessions (tracked in $PIDFILE), aborting on a D3/D6 breach
  down     terminate ONLY the pids this script recorded — never by age, never by pattern
  stat     one line: sessions, ptys, available GB, seg_pct, panic count
  breach   exit 1 with the reason if a D3/D6 abort condition holds right now
Stages for S6-DOD D1: 19 -> 40 -> 80 -> 150, measuring at each and never advancing past a breach.
USAGE
     exit 64 ;;
esac
