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
#
# 🚨 A SILENT ALARM IS NOT A QUIET BOX — D3 ABORTS AS UNVERIFIABLE (added 2026-08-11, closing
# scaling-bottlenecks-2026-08-09/10-adv-redteam.md finding F5). The old reader was
#     seg_pct() { tail -1 …compressor-sentinel.jsonl | jq -r '.pct // 0' || echo 0; }
# so a MISSING, STALE, or UNPARSEABLE log read `0` — and 0 is the HEALTHIEST possible segment
# figure. `breach()` then passed, and the ramp advanced a stage on an instrument that was not
# reporting. The sentinel dying mid-ramp is not hypothetical: it has its own SKIP path, and a
# launchd restart loses its baselines. The redteam's falsifier was one line — `mv` the jsonl aside
# and run `capacity-ramp.sh breach` — and it read OK.
#
# THE DISTINCTION THE FIX TURNS ON: "measured 0" and "could not measure" are DIFFERENT STATES and
# reach DIFFERENT BRANCHES. A fresh row saying 0.00% is a real reading of a healthy box and the
# ramp proceeds. No row, no `ts`, a null `pct`, no `jq`, or a row older than CC_RAMP_SEG_MAX_AGE is
# an ABSENCE of reading and the ramp ABORTS. The sentinel itself already implements exactly this
# contract on its own side (SKIP emits no row rather than a zero one,
# compressor-sentinel.sh:46-53); its DoD consumer was the half that violated it. Fleet memory:
# alarm-polarity, published-figure-decays, and render-census.sh's own NO-DATA rung, which is this
# same rule one instrument over.
#
# Freshness is computed from the ROW'S OWN `ts`, converted to epoch by civil-date arithmetic in
# awk rather than by `date`. Deliberate: the ISO-8601 parse spellings diverge (`date -j -f` on
# macOS, `date -d` on GNU), and an instrument whose freshness check silently fails to parse on one
# of them would fail exactly the way F5 describes. `date -u +%s` — the one call kept — is portable.
set -uo pipefail

BIN="${CC_RAMP_BIN:-$HOME/.claude-220/node_modules/.bin/claude}"
PIDFILE="${CC_RAMP_PIDFILE:-/tmp/cc-ramp-pids.txt}"
FIFODIR="${CC_RAMP_FIFODIR:-/tmp}"
FLOOR_GB="${CC_RAMP_FLOOR_GB:-8}"     # abort below this (free+purgeable); the alarm's WARN line
SEG_MAX="${CC_RAMP_SEG_MAX:-15}"      # abort at/above this seg_pct — the sentinel's own trip level
SETTLE="${CC_RAMP_SETTLE:-4}"         # seconds between unit launches
SEG_LOG="${CC_RAMP_SEG_LOG:-$HOME/.claude/logs/compressor-sentinel.jsonl}"
SEG_MAX_AGE="${CC_RAMP_SEG_MAX_AGE:-30}"  # a row older than this is a DEAD instrument, not a calm one

# ── THE LOAD TERM (2026-08-19, backlog e981656df348) ───────────────────────────────────────────
# WHY IT WAS MISSING AND WHY THAT MATTERED. This script is the box's ONLY actuator that adds
# sessions one at a time under a tracked identity — and until now it recorded sessions, ptys,
# memory, segments and panics, and NOT the one quantity the spawn gate actually keys on. So every
# capacity constant in the tree divides by a marginal load per session that no ramp ever measured,
# and the four values in circulation span 30x (0.172 pooled OLS · 0.566 bucket median · 1.89 delta
# · 2.5-5 published, an aggregate/N). capacity-alarm.sh:132-135 states the same gap from the other
# side: "no historical load series for this box exists to calibrate against — the log has to become
# that series first." `marginal` is that series.
#
# 🚨 THE UNIT HERE IS RESIDENT-IDLE, AND THAT BOUNDS WHAT THE NUMBER MEANS. Every figure this verb
# produces is the RESIDENCY FLOOR of the marginal — a lower bound. An ACTIVE, model-driven session
# is a different and larger draw, and measuring it needs real turns and real quota, which this
# harness deliberately does not spend (see the header: full RSS, one pty, ZERO tokens). Do not quote
# a number from here as "the marginal load per session"; the report labels every line accordingly.
#
# THE NULL ARM IS NOT OPTIONAL. §8.5.7 measured this box's load moving 29.15 -> 59.80 at a CONSTANT
# 31-32 sessions, and one instrumentation run alone moved it 19 -> 36 with session count unchanged.
# A per-unit delta drawn from that box without a no-unit control is indistinguishable from drift, so
# `marginal` runs the null arm FIRST and the report refuses to resolve a marginal smaller than it.
MLOG="${CC_RAMP_MARGINAL_LOG:-$HOME/.claude/logs/capacity-marginal.jsonl}"
# 300 s, not the 4 s launch cadence above. loadavg field 1 is an exponentially-damped 1-minute
# average, so a delta sampled S seconds after the step still carries e^(-S/60) of the old level:
# at 4 s that is 94% stale and measures nothing, at 90 s 22%, at 300 s 0.67%. The default is the
# first settle at which the residual is below the reporting precision, and NO correction is applied
# — correcting for a time constant the sampler never verified would be inventing a measurement.
MSETTLE="${CC_RAMP_MARGINAL_SETTLE:-300}"
MMIN="${CC_RAMP_MARGINAL_MIN_TRIALS:-5}"   # the doc's N>=5 at different baselines; report refuses below it

# sysctl is RESOLVED ABSOLUTELY for the same measured reason capacity-admit.sh:155-160 gives — it
# lives in /usr/sbin, which a launchd PATH lacks, and 222 of 239 capacity rows once read
# `hw.ncpu unreadable ('')` because the bare name never resolved. An EXPLICIT override is honoured
# verbatim and only the DEFAULT falls back.
sysctl_bin() { if [ -n "${CC_RAMP_SYSCTL:-}" ]; then printf '%s' "$CC_RAMP_SYSCTL"
               elif [ -x /usr/sbin/sysctl ]; then printf '%s' /usr/sbin/sysctl
               else printf '%s' sysctl; fi; }
is_num() { case "${1:-}" in ''|*[!0-9.]*) return 1 ;; esac; return 0; }
# BOTH probes print NOTHING and return 1 when they cannot read — never a 0. This file's seg_read()
# already establishes the rule and the reason: a 0 is the healthiest possible reading, so a dead
# probe that returns one re-enters as a calm box. A marginal computed from a blind load probe would
# read 0.00/session, which is exactly the conclusion the whole question is trying to test.
load1() { local v; v="${CC_RAMP_LOADAVG_OVERRIDE:-$("$(sysctl_bin)" -n vm.loadavg 2>/dev/null | awk '{print $2}')}"
          is_num "$v" || return 1; printf '%s' "$v"; }
ncpu()  { local v; v="${CC_RAMP_NCPU_OVERRIDE:-$("$(sysctl_bin)" -n hw.ncpu 2>/dev/null)}"
          is_num "$v" || return 1; [ "${v%%.*}" -gt 0 ] 2>/dev/null || return 1; printf '%s' "$v"; }
load_display() { local l n; l="$(load1)" || { printf 'BLIND'; return 0; }
                 n="$(ncpu)" || { printf '%s' "$l"; return 0; }
                 awk -v l="$l" -v n="$n" 'BEGIN{ printf "%s(%.2f/core)", l, l / n }'; }

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
# iso_age: ISO-8601 Zulu timestamp + a `now` epoch → whole seconds of age on stdout, NOTHING (and
# rc 1) on anything that is not exactly that shape. Howard Hinnant's days_from_civil, which is pure
# integer arithmetic and therefore identical under BWK awk (macOS) and gawk — unlike mktime, which
# macOS awk does not have at all.
iso_age() { # $1=ts  $2=now_epoch
  awk -v ts="$1" -v now="$2" '
    function dfc(y, m, d,   era, yoe, doy, doe) {
      if (m <= 2) y -= 1
      era = int((y >= 0 ? y : y - 399) / 400)
      yoe = y - era * 400
      doy = int((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5) + d - 1
      doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
      return era * 146097 + doe - 719468
    }
    BEGIN {
      if (ts !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z$/) exit 1
      printf "%d", now + 0 - (dfc(substr(ts,1,4)+0, substr(ts,6,2)+0, substr(ts,9,2)+0) * 86400 \
             + substr(ts,12,2)*3600 + substr(ts,15,2)*60 + substr(ts,18,2))
    }'
}

# seg_read: prints "<pct> <age_seconds>" for a row that was ACTUALLY READ, and prints NOTHING for
# every failure mode — absent log, empty log, no `ts`, `pct` null, no `jq`, unparseable timestamp.
# EMPTY IS THE BLIND STATE AND IT IS NEVER A NUMBER. Every caller must branch on emptiness before
# it has a figure to compare, which is what stops a dead instrument re-entering as a healthy 0.
seg_read() {
  local row ts pct now age
  [ -s "$SEG_LOG" ] || return 1
  row="$(tail -1 "$SEG_LOG" 2>/dev/null)" || return 1
  [ -n "$row" ] || return 1
  # `// empty` NOT `// 0`: a null pct means the sentinel emitted a row it could not fill, and that
  # is the same absence as no row at all. jq missing exits non-zero here rather than echoing 0.
  ts="$(printf '%s\n' "$row" | jq -r '.ts // empty' 2>/dev/null)" || return 1
  pct="$(printf '%s\n' "$row" | jq -r '.pct // empty' 2>/dev/null)" || return 1
  [ -n "$ts" ] && [ -n "$pct" ] || return 1
  now="$(date -u +%s 2>/dev/null)" || return 1
  [ -n "$now" ] || return 1
  age="$(iso_age "$ts" "$now")" || return 1
  [ -n "$age" ] || return 1
  printf '%s %s\n' "$pct" "$age"
}
# seg_pct: the DISPLAY spelling. BLIND, never 0 — the string cannot be mistaken for a reading by a
# reader, a grep, or an arithmetic comparison.
seg_pct()  { local r; if r="$(seg_read)" && [ -n "$r" ]; then printf '%s' "${r%% *}"; else printf 'BLIND'; fi; }
# shellcheck disable=SC2012  # panic filenames are Apple-generated and alphanumeric; a count is all
# D2 needs, and `find` here would add a directory walk to a hot per-unit loop.
panics()   { ls -1 /Library/Logs/DiagnosticReports/*.panic 2>/dev/null | wc -l | tr -d ' '; }

# breach: echoes the reason and returns 0 when a D2-D6 abort condition holds.
#
# THREE D3 OUTCOMES, NOT TWO. The segment arm can now say "over the ceiling", "under the ceiling",
# or "I did not get a reading" — and only the middle one lets the ramp advance. D6 is still
# evaluated first, so a box that is simultaneously out of memory reports the memory floor (the
# louder, more actionable fact) rather than the instrument.
breach() {
  local a r pct age
  a="$(avail_gb)"
  awk -v a="$a" -v f="$FLOOR_GB" 'BEGIN{exit !(a+0 < f+0)}' && { echo "D6 memory: ${a}GB < ${FLOOR_GB}GB floor"; return 0; }
  r="$(seg_read)" || r=""
  if [ -z "$r" ]; then
    echo "D3 UNVERIFIABLE: compressor sentinel gave no reading ($SEG_LOG) — could not measure is NOT healthy"
    return 0
  fi
  pct="${r%% *}"; age="${r##* }"
  if awk -v g="$age" -v m="$SEG_MAX_AGE" 'BEGIN{exit !(g+0 > m+0 || g+0 < -(m+0))}'; then
    echo "D3 UNVERIFIABLE: sentinel sample is ${age}s old (max ${SEG_MAX_AGE}s) — the alarm is dead, not quiet"
    return 0
  fi
  awk -v s="$pct" -v m="$SEG_MAX" 'BEGIN{exit !(s+0 >= m+0)}' && { echo "D3 segments: ${pct}% >= ${SEG_MAX}%"; return 0; }
  return 1
}

stat_line() {
  local r seg age
  r="$(seg_read)" || r=""
  if [ -n "$r" ]; then seg="${r%% *}%"; age="${r##* }s"; else seg="BLIND"; age="n/a"; fi
  printf 'sessions=%s ptys=%s avail=%sGB seg=%s segage=%s panics=%s load=%s\n' \
    "$(sessions)" "$(ptys)" "$(avail_gb)" "$seg" "$age" "$(panics)" "$(load_display)"
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

# ── THE TWO-ARM MARGINAL EXPERIMENT ────────────────────────────────────────────────────────────
# m_sample: "<sessions> <load1>" for ONE instant, or nothing and rc 1 when the load probe is blind.
# The census is `ps -axo comm=` (command position), never `pgrep -f` — measured 2026-08-09 at 9 by
# argv against 0 by command position on this box, because argv here carries whole agent briefs.
m_sample() { local s l; s="$(sessions)"; l="$(load1)" || return 1; printf '%s %s' "$s" "$l"; }

m_emit() { # $1=event $2=i $3=s_pre $4=s_post $5=l_pre $6=l_post $7=ncpu $8=valid $9=why
  mkdir -p "$(dirname "$MLOG")" 2>/dev/null || true
  printf '{"ts":"%s","event":"%s","i":%s,"sessions_pre":%s,"sessions_post":%s,"dsessions":%s,"load_pre":%s,"load_post":%s,"dload":%s,"ncpu":%s,"settle":%s,"valid":%s,"why":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" "$3" "$4" "$(( $4 - $3 ))" "$5" "$6" \
    "$(awk -v a="$5" -v b="$6" 'BEGIN{ printf "%.3f", b - a }')" "$7" "$MSETTLE" "$8" "$9" >> "$MLOG"
}

marginal() {
  local n="${1:?usage: marginal <trials>}" i pre post sp sq lp lq nc valid why
  [ -x "$BIN" ] || { echo "capacity-ramp: binary not executable: $BIN" >&2; return 2; }
  nc="$(ncpu)"  || { echo "capacity-ramp: hw.ncpu unreadable — a per-core figure cannot be computed" >&2; return 4; }
  # A BLIND LOAD PROBE ABORTS BEFORE ANYTHING IS SPAWNED. Same rule as D3's UNVERIFIABLE branch:
  # "could not measure" is not "measured 0", and here it would spend real sessions producing rows
  # that all read 0.000 — the exact answer the experiment exists to test.
  pre="$(m_sample)" || { echo "capacity-ramp: load probe BLIND — refusing to spawn for an unmeasurable trial" >&2; return 4; }

  # ARM 0 — THE NULL. Same window, same sampler, no unit added. Whatever this reads is the box's own
  # drift, and it is the floor of what any per-unit delta below can claim to have resolved.
  echo "capacity-ramp: NULL ARM — ${MSETTLE}s of drift with NO unit added (this is the control)"
  sleep "$MSETTLE"
  post="$(m_sample)" || { echo "capacity-ramp: load probe went BLIND during the null arm" >&2; return 4; }
  sp="${pre%% *}"; lp="${pre##* }"; sq="${post%% *}"; lq="${post##* }"
  m_emit null-arm 0 "$sp" "$sq" "$lp" "$lq" "$nc" true "no unit added"
  echo "capacity-ramp: null drift = $(awk -v a="$lp" -v b="$lq" 'BEGIN{printf "%+.3f", b-a}') load over ${MSETTLE}s (sessions ${sp} -> ${sq})"

  for i in $(seq 1 "$n"); do
    pre="$(m_sample)" || { echo "capacity-ramp: trial $i ABORT — load probe blind" >&2; return 4; }
    sp="${pre%% *}"; lp="${pre##* }"
    up 1 || { echo "capacity-ramp: trial $i ABORT — up refused (rc $?)" >&2; return 3; }
    sleep "$MSETTLE"
    post="$(m_sample)" || { echo "capacity-ramp: trial $i ABORT — load probe blind after the unit" >&2; return 4; }
    sq="${post%% *}"; lq="${post##* }"
    # THE CONTROL THAT MUST BE ABLE TO FAIL. The census has to reproduce the population it is
    # apportioning: exactly ONE more session, no more and no fewer. A trial where the box gained or
    # lost sessions of its own is a delta over a moving population and is recorded INVALID rather
    # than quietly averaged in — the defect that killed this wave's "64% is our own automation"
    # headline was a census that stayed flat while load moved.
    if [ "$(( sq - sp ))" -eq 1 ]; then valid=true;  why="census moved by exactly 1"
    else                               valid=false; why="census moved by $(( sq - sp )), not 1"; fi
    m_emit trial "$i" "$sp" "$sq" "$lp" "$lq" "$nc" "$valid" "$why"
    printf 'capacity-ramp: trial %s/%s baseline=%s dload=%s valid=%s (%s)\n' \
      "$i" "$n" "$lp" "$(awk -v a="$lp" -v b="$lq" 'BEGIN{printf "%+.3f", b-a}')" "$valid" "$why"
  done
  echo "capacity-ramp: $n trial(s) recorded in $MLOG — read them with 'marginal-report', then RUN 'down'"
}

marginal_report() {
  [ -s "$MLOG" ] || { echo "capacity-ramp: no marginal log at $MLOG — run 'marginal <n>' first" >&2; return 1; }
  command -v jq >/dev/null 2>&1 || { echo "capacity-ramp: jq unavailable — cannot fold $MLOG" >&2; return 1; }
  jq -rs --argjson min "$MMIN" '
    (map(select(.event == "null-arm")) | map(.dload | fabs) | max) as $drift
    | (map(select(.event == "trial" and .valid))) as $ok
    | ($ok | map(.dload) | sort) as $d
    | (if ($d | length) == 0 then null
       elif (($d | length) % 2) == 1 then $d[(($d | length) - 1) / 2]
       else (($d[($d | length) / 2 - 1] + $d[($d | length) / 2]) / 2) end) as $median
    | "capacity-ramp marginal report — RESIDENT-IDLE sessions only: a LOWER BOUND, never the marginal",
      "  valid trials ....... \($ok | length) (need \($min))",
      "  invalid trials ..... \(map(select(.event == "trial" and (.valid | not))) | length) — census did not move by exactly 1",
      "  null-arm drift ..... \($drift // "NONE RUN") load over the same window, NO unit added",
      "  per-trial dload .... \($d | @json)",
      (if ($ok | length) < $min then
         "  VERDICT: INSUFFICIENT — \($ok | length) of \($min) valid trials. No figure is reported."
       elif $drift == null then
         "  VERDICT: UNCONTROLLED — no null arm in this log. A delta without the drift control is not a measurement."
       elif ($median | fabs) <= $drift then
         "  VERDICT: UNRESOLVED — median \($median + 0) is within the box'"'"'s own \($drift) drift. The instrument cannot see the term."
       else
         "  median marginal ... \($median + 0) load per RESIDENT session (\(($median / ($ok[0].ncpu)) * 100 | floor / 100) per core)",
         "  VERDICT: RESOLVED at the residency floor. This does NOT license moving CC_HW_DEFAULT_MAX_LOAD_PER_CORE:",
         "           that constant needs a population separating FATAL from SURVIVED, and this measures neither."
       end)
  ' "$MLOG"
}

case "${1:-}" in
  up)     shift; up "$@" ;;
  down)   down ;;
  stat)   stat_line ;;
  marginal)        shift; marginal "$@" ;;
  marginal-report) marginal_report ;;
  breach) if r="$(breach)"; then echo "BREACH: $r"; exit 1; else echo "OK: $(stat_line)"; fi ;;
  *) cat >&2 <<USAGE
usage: capacity-ramp.sh {up <n>|down|stat|breach|marginal <n>|marginal-report}
  up <n>   launch n RESIDENT idle sessions (tracked in $PIDFILE), aborting on a D3/D6 breach
  down     terminate ONLY the pids this script recorded — never by age, never by pattern
  stat     one line: sessions, ptys, available GB, seg_pct (or BLIND), sample age, panics, load
  breach   exit 1 with the reason if a D3/D6 abort condition holds right now
  marginal <n>     the TWO-ARM experiment for the marginal load of ONE added session: a NULL arm
                   (\${CC_RAMP_MARGINAL_SETTLE}=${MSETTLE}s of drift, no unit) then n trials, each
                   adding exactly ONE unit at a HIGHER baseline. Rows -> \$CC_RAMP_MARGINAL_LOG
                   (${MLOG}). Run 'down' when finished — it does not tear down between trials,
                   because rising baselines are the point.
  marginal-report  fold that log. REFUSES a figure below \${CC_RAMP_MARGINAL_MIN_TRIALS}=${MMIN}
                   valid trials, and refuses to resolve a median smaller than the null arm's drift.
🚨 The unit is RESIDENT-IDLE (full RSS, one pty, zero tokens), so every figure is a LOWER BOUND on
the marginal, never "the marginal load per session". The ACTIVE marginal needs real turns and real
quota and this harness deliberately does not spend them. Neither figure licenses moving
CC_HW_DEFAULT_MAX_LOAD_PER_CORE — see tests/capacity-ceiling-derivation.bats for why that constant
needs a population this axis can separate, which no marginal supplies (backlog e981656df348).
Stages for S6-DOD D1: 19 -> 40 -> 80 -> 150, measuring at each and never advancing past a breach.
D3 aborts as UNVERIFIABLE when the compressor sentinel gives no reading at all — a missing, stale
(> \$CC_RAMP_SEG_MAX_AGE=${SEG_MAX_AGE}s), or unparseable row is a dead instrument, never a healthy 0.
Seams: CC_RAMP_SEG_LOG (${SEG_LOG}) · CC_RAMP_SEG_MAX_AGE (${SEG_MAX_AGE}s).
USAGE
     exit 64 ;;
esac
