#!/bin/bash
# render-census.sh — put the DOMINANT sustained consumer under a measured budget with an alarm.
#
# WHY (row 13 M8, MACHINE_CAPACITY_V2.md §11.3). Every capacity mechanism this row built so far
# governs memory or batch CPU. The measured truth (§11.2 gu13-live axis) is that neither is the
# stable floor: TUI render — iTerm2 + WindowServer — draws 1.76-1.91 cores and NEVER MOVES, while
# the batch and indexing classes swing. A consumer that large with nothing watching it is the same
# unalarmed-ceiling defect capacity-alarm.sh was built to close, one class over.
#
# THIS IS AN ALARM, NOT A GATE. Identical stance to capacity-alarm.sh, for the same measured reason:
#   · NEVER refuses, blocks, queues, sleeps, or polls-until-clear. It reports and exits (R1).
#   · It cannot shed render cost itself — the remedy is the operator's (close panes, /handoff idle
#     sessions, retire orphan watchdogs). An alarm that pretends to act is worse than one that
#     reports, because it hides that nothing happened.
#
# THE INSTRUMENT, chosen because the obvious one lies:
#   · `ps %cpu` is a LIFETIME AVERAGE. §11.2 measured it understating claude.exe by ~4x (33% vs
#     129%). Every CPU claim in this repo cites `top -l 2` SECOND sample, and so does this file:
#     the first sample is the same lifetime average, the second is a true delta over the interval.
#   · `-n 0` was tried here and SUPPRESSES EVERY PROCESS ROW (verified: only the header block
#     prints). The census would then read an empty fleet forever — the exact class of defect in
#     memory actuator-must-see-the-target-population. Do not add it back.
#   · The iTerm2 pid is taken from top's OWN row rather than a second lookup, so the pid and the
#     CPU number can never come from two different instruments. `pgrep -n iTerm2` was tried and
#     returned EMPTY on this box with iTerm2 plainly live (macOS pgrep matches a truncated argv).
#   · top's COMMAND column truncates (~15-16 chars: `iTermServer-3.6.`). The names this file
#     matches — iTerm2, WindowServer, mdworker_shared (15) — all fit whole. Matching is EXACT on
#     the command field, never a substring, so `iTermServer` can never be counted as `iTerm2`.
#
# WHAT THE INDEXING COLUMN IS FOR (§11.9(3)). M8b's premise was FALSIFIED: the ~/.claude* dirs are
# already index-excluded by the dot-prefix rule, `.metadata_never_index` is dead on this OS, and the
# 0.49-0.80-core mds reading did NOT reproduce (sustained re-measure peaked at 2.1%). Both reads
# were real — THE CLASS IS BURSTY. So no exclusion action is taken anywhere; the census carries the
# indexing-class CPU and the mdworker spawn rate as a COLUMN, which is how a bursty class is seen
# honestly instead of argued about from one sample.
#
# Verdicts (four, never a boolean — "could not measure" must not read as "fine"):
#   OK       render cores under the budget.                             exit 0
#   WARN     render cores at/above the budget, under the alarm floor.   exit 1
#   ALARM    render cores at/above the alarm floor.                     exit 2
#   NO-DATA  top produced no second sample — nothing is asserted.       exit 3
# Note the direction is INVERTED from capacity-alarm.sh (there, LOWER headroom is worse).
#
# Seams: CC_RENDER_CENSUS=off (kill switch) · CC_RENDER_BUDGET_CORES (WARN, default 2.5) ·
#        CC_RENDER_ALARM_CORES (default 3.5) · CC_RENDER_LOG · CC_RENDER_SAMPLE_S (default 5) ·
#        CC_RENDER_PAGE=off · CC_PAGES_DIR · CC_RENDER_SELFTEST=1 (positive control)
# Defaults are set ABOVE today's measured 2.0-core floor deliberately: this alarm speaks on
# REGRESSION, not on the steady state it was calibrated against. An alarm that always fires carries
# the same zero bits as one that cannot (memory alarm-polarity-and-attention-budget).
#
# bash 3.2 safe. Ships to launchd ⇒ tested under /bin/bash.

set -uo pipefail

WARN_CORES="${CC_RENDER_BUDGET_CORES:-2.5}"
ALARM_CORES="${CC_RENDER_ALARM_CORES:-3.5}"
LOG="${CC_RENDER_LOG:-$HOME/.claude/logs/render-census.jsonl}"
SAMPLE_S="${CC_RENDER_SAMPLE_S:-5}"
APPEND=1; WANT_JSON=0; QUIET=0

while [ $# -gt 0 ]; do
  if   [ "$1" = "--json" ];      then WANT_JSON=1
  elif [ "$1" = "--quiet" ];     then QUIET=1
  elif [ "$1" = "--no-append" ]; then APPEND=0
  elif [ "$1" = "--selftest" ];  then CC_RENDER_SELFTEST=1
  elif [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    sed -n '2,/^set -uo/p' "$0" | sed 's/^# \{0,1\}//; /^set -uo/d'; exit 0
  else echo "render-census.sh: unknown arg '$1'" >&2; exit 64
  fi
  shift
done

if [ "${CC_RENDER_CENSUS:-on}" = "off" ]; then
  [ "$QUIET" = 1 ] || echo "render-census: disabled (CC_RENDER_CENSUS=off)"
  exit 0
fi

# ── verdict ladder (R6: the SAME function the live path uses, so the control tests real code) ─────
classify() { # <render_cores> → prints verdict
  local c="$1"
  if [ -z "$c" ]; then printf 'NO-DATA'; return 0; fi
  if awk -v a="$c" -v b="$ALARM_CORES" 'BEGIN{exit !(a+0 >= b+0)}'; then printf 'ALARM'; return 0; fi
  if awk -v a="$c" -v b="$WARN_CORES"  'BEGIN{exit !(a+0 >= b+0)}'; then printf 'WARN';  return 0; fi
  printf 'OK'
}

if [ "${CC_RENDER_SELFTEST:-0}" = "1" ]; then
  fails=0
  for probe in "0.5:OK" "2.0:OK" "2.9:WARN" "3.5:ALARM" "9.9:ALARM" ":NO-DATA"; do
    c="${probe%%:*}"; want="${probe#*:}"
    got="$(classify "$c")"
    if [ "$got" = "$want" ]; then echo "  control OK   render_cores='$c' → $got"
    else echo "  control FAIL render_cores='$c' → $got (want $want)"; fails=$((fails+1)); fi
  done
  [ "$fails" -eq 0 ] && { echo "render-census: selftest GREEN (4 rungs + no-data reachable)"; exit 0; }
  echo "render-census: selftest RED ($fails)" >&2; exit 70
fi

# ── bounded external calls (row 6 standing constraint; memory bounding-external-calls) ────────────
TIMEOUT_BIN=""
for _c in "$(command -v timeout 2>/dev/null || true)" "$(command -v gtimeout 2>/dev/null || true)" \
          /opt/homebrew/bin/timeout /usr/local/bin/timeout \
          /opt/homebrew/bin/gtimeout /usr/local/bin/gtimeout; do
  [ -n "$_c" ] && [ -x "$_c" ] && { TIMEOUT_BIN="$_c"; break; }
done
rc_bounded() { # $1=seconds, rest=command — rc 124 on expiry, which every caller treats as failure
  local s="$1"; shift
  if [ -z "$TIMEOUT_BIN" ] || [ ! -x "$TIMEOUT_BIN" ]; then "$@"; return $?; fi
  "$TIMEOUT_BIN" -k 3 "$s" "$@"
}

# ── the one render sample: top -l 2, SECOND block only ────────────────────────────────────────────
# Bounded at 3x the sample span + 10s: a `top` that wedges under load must degrade to NO-DATA, never
# hang a launchd job forever.
TOP_BOUND="$(awk -v s="$SAMPLE_S" 'BEGIN{printf "%d", s*3+10}')"
TOP_OUT="$(rc_bounded "$TOP_BOUND" top -l 2 -s "$SAMPLE_S" -stats pid,command,cpu 2>/dev/null || true)"

# One awk pass over the second sample. Emits: iterm_pid iterm_cpu ws_cpu idx_cpu rows
# `command` is joined from fields 2..NF-1 so a name containing spaces cannot shift the CPU column.
RENDER_FIELDS="$(printf '%s\n' "$TOP_OUT" | awk '
  /^Processes:/ { blk++; next }
  blk != 2      { next }
  $1 !~ /^[0-9]+$/ { next }
  {
    cpu = $NF + 0
    cmd = ""
    for (i = 2; i < NF; i++) cmd = (cmd == "" ? $i : cmd " " $i)
    rows++
    if (cmd == "iTerm2")       { ipid = $1; icpu += cpu }
    if (cmd == "WindowServer") { wcpu += cpu }
    if (cmd == "mds" || cmd == "mds_stores" || cmd == "mdworker" || \
        cmd == "mdworker_shared" || cmd == "corespotlightd") xcpu += cpu
  }
  END { printf "%s %.1f %.1f %.1f %d", (ipid == "" ? "0" : ipid), icpu+0, wcpu+0, xcpu+0, rows+0 }
' 2>/dev/null || true)"

ITERM_PID=""; ITERM_CPU=""; WS_CPU=""; IDX_CPU=""; TOP_ROWS=0
if [ -n "$RENDER_FIELDS" ]; then
  # shellcheck disable=SC2086  # deliberate word-split of the 5-field awk output
  set -- $RENDER_FIELDS
  ITERM_PID="${1:-0}"; ITERM_CPU="${2:-}"; WS_CPU="${3:-}"; IDX_CPU="${4:-}"; TOP_ROWS="${5:-0}"
fi

# NO-DATA is keyed on the SAMPLE, not on the reading. top running fine on a box where iTerm2 happens
# not to be live is a legitimate 0.00 cores; top failing to produce a second sample asserts nothing.
# Conflating those two would let a broken instrument report the healthiest possible number.
RENDER_CORES=""
if [ "${TOP_ROWS:-0}" -gt 0 ] 2>/dev/null; then
  RENDER_CORES="$(awk -v a="${ITERM_CPU:-0}" -v b="${WS_CPU:-0}" 'BEGIN{printf "%.2f", (a+b)/100}')"
fi
IDX_CORES="null"
[ -n "$IDX_CPU" ] && IDX_CORES="$(awk -v a="$IDX_CPU" 'BEGIN{printf "%.2f", a/100}')"

# ── iTerm2 hot-thread share ───────────────────────────────────────────────────────────────────────
# §11.9(2) found the saturated thread by `sample` (56-70% of the main thread in legacyView:drawRect:).
# `ps -M` is NOT that instrument — its per-thread %CPU is a lifetime average, so it reports a much
# flatter share than the instantaneous one. It is carried because it is cheap and directional (is ONE
# thread carrying this process?), and the jsonl labels its provenance so a future reader cannot
# mistake it for the `sample` number. Row 2 of `ps -M` is the process line (NF=9); thread rows are
# NF=6 with $2=%CPU — verified on this box.
HOT_PCT="null"; HOT_SHARE="null"
if [ -n "$ITERM_PID" ] && [ "$ITERM_PID" != "0" ]; then
  HOT_FIELDS="$(rc_bounded 5 ps -M "$ITERM_PID" 2>/dev/null \
    | awk 'NR==2{p=$4+0} NF==6{if($2+0>m) m=$2+0} END{if(NR>1) printf "%.1f %.2f", m+0, (p>0? m/p : 0)}' || true)"
  if [ -n "$HOT_FIELDS" ]; then
    # shellcheck disable=SC2086  # deliberate word-split of the 2-field awk output
    set -- $HOT_FIELDS
    HOT_PCT="${1:-null}"; HOT_SHARE="${2:-null}"
  fi
fi

# ── pane count: ONE bounded osascript, never a guess on failure ───────────────────────────────────
# A failed pane query reports null. Substituting a remembered or derived number would make the log
# claim a measurement that never happened.
PANES="null"
PANE_OUT="$(rc_bounded 5 osascript \
  -e 'tell application "iTerm2" to set n to 0' \
  -e 'tell application "iTerm2" to repeat with w in windows' \
  -e 'repeat with t in tabs of w' \
  -e 'set n to n + (count of sessions of t)' \
  -e 'end repeat' -e 'end repeat' -e 'return n' 2>/dev/null || true)"
case "$PANE_OUT" in ''|*[!0-9]*) PANES="null" ;; *) PANES="$PANE_OUT" ;; esac

# ── session census: BOTH pid families, root-deduped by in-family ppid ─────────────────────────────
# §11.2/archaeology (b): the fleet lives in two DISJOINT families (intersection 0) — the alarm that
# matched only `claude-code/bin/claude.exe` reported 13 of 31 real session trees. Matching both and
# then dropping any process whose PARENT is also in the matched set counts session ROOTS, so a
# family that spawns helpers cannot inflate the count relative to one that does not.
#
# The snapshot is taken into a variable FIRST, then piped. This is deliberate: in a live
# `ps | awk '…claude…'` pipeline the awk process is running while ps samples, and awk's own argv
# CONTAINS the pattern — so the census counts itself (memory pgrep-f-matches-agent-briefs). A
# completed snapshot cannot contain a process that does not exist yet.
PS_SNAP="$(ps -eo pid,ppid,etime,args 2>/dev/null || true)"
SESSIONS="$(printf '%s\n' "$PS_SNAP" | awk '
  $1 ~ /^[0-9]+$/ && $0 ~ /claude-code\/bin\/claude\.exe|node_modules\/\.bin\/claude/ {
    seen[$1] = 1; pid[n] = $1; par[n] = $2; n++
  }
  END { c = 0; for (i = 0; i < n; i++) if (!(par[i] in seen)) c++; print c+0 }
' 2>/dev/null || true)"
case "$SESSIONS" in ''|*[!0-9]*) SESSIONS=0 ;; esac

# mdworker spawn count inside the sample window — the churn term §11.2(e) measured at 21/60s.
# macOS ps has NO `etimes` keyword (verified: "keyword not found"), so elapsed time is parsed from
# `etime`'s three shapes: MM:SS, HH:MM:SS, DD-HH:MM:SS.
MDW_SPAWNS="$(printf '%s\n' "$PS_SNAP" | awk -v win="$SAMPLE_S" '
  function etsec(e,   a, b, n, d) {
    d = 0
    if (index(e, "-")) { split(e, a, "-"); d = a[1] + 0; e = a[2] }
    n = split(e, b, ":")
    if (n == 3) return d*86400 + b[1]*3600 + b[2]*60 + b[3]
    if (n == 2) return d*86400 + b[1]*60 + b[2]
    return d*86400 + b[1]
  }
  $1 ~ /^[0-9]+$/ && $4 ~ /\/mdworker/ { if (etsec($3) <= win + 0) c++ }
  END { print c+0 }
' 2>/dev/null || true)"
case "$MDW_SPAWNS" in ''|*[!0-9]*) MDW_SPAWNS=0 ;; esac

# ── top consumer by name (the platter needs a NAME, not a number) ─────────────────────────────────
TOP_NAME="unknown"; TOP_PCT="0.0"
if [ "${TOP_ROWS:-0}" -gt 0 ] 2>/dev/null; then
  TOP_FIELDS="$(awk -v i="${ITERM_CPU:-0}" -v w="${WS_CPU:-0}" -v x="${IDX_CPU:-0}" 'BEGIN{
    n="iTerm2"; v=i+0
    if (w+0 > v) { n="WindowServer"; v=w+0 }
    if (x+0 > v) { n="indexing-class"; v=x+0 }
    printf "%s %.1f", n, v
  }')"
  # shellcheck disable=SC2086  # deliberate word-split of the 2-field awk output
  set -- $TOP_FIELDS
  TOP_NAME="${1:-unknown}"; TOP_PCT="${2:-0.0}"
fi

VERDICT="$(classify "$RENDER_CORES")"
case "$VERDICT" in
  OK)    RC=0 ;;
  WARN)  RC=1 ;;
  ALARM) RC=2 ;;
  *)     RC=3 ;;
esac

TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
JSON="$(printf '{"ts":"%s","verdict":"%s","render_cores":%s,"iterm_cpu_pct":%s,"windowserver_cpu_pct":%s,"hot_thread_pct":%s,"hot_thread_share":%s,"hot_thread_src":"ps-M-lifetime-avg","panes":%s,"sessions":%s,"indexing_cores":%s,"indexing_cpu_pct":%s,"mdworker_spawns_in_window":%s,"top_consumer":"%s","top_consumer_pct":%s,"sample_s":%s,"top_rows":%s,"warn_cores":%s,"alarm_cores":%s}' \
  "$TS" "$VERDICT" "${RENDER_CORES:-null}" "${ITERM_CPU:-null}" "${WS_CPU:-null}" \
  "$HOT_PCT" "$HOT_SHARE" "$PANES" "$SESSIONS" "$IDX_CORES" "${IDX_CPU:-null}" \
  "$MDW_SPAWNS" "$TOP_NAME" "$TOP_PCT" "$SAMPLE_S" "${TOP_ROWS:-0}" "$WARN_CORES" "$ALARM_CORES")"

if [ "$APPEND" = 1 ]; then
  mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
  printf '%s\n' "$JSON" >> "$LOG" 2>/dev/null || true
fi

# ── page the operator on WARN/ALARM, and SELF-CLEAR on OK ─────────────────────────────────────────
# ONE FIXED SLUG (capacity-alarm.sh:163-199 is the pattern this mirrors): every write overwrites the
# same file, so a job on a cadence cannot accumulate hundreds of pages. AND IT SELF-CLEARS — a page
# whose condition has passed is misinformation, not history; the jsonl is the durable record.
# NO-DATA clears too: leaving a stale ALARM up while blind asserts a condition we can no longer see.
PAGES_DIR="${CC_PAGES_DIR:-$HOME/.claude/autonomy/pages}"
PAGE="$PAGES_DIR/render-census.page"
if [ "${CC_RENDER_PAGE:-on}" != "off" ] && [ "$APPEND" = 1 ]; then
  if [ "$VERDICT" = "WARN" ] || [ "$VERDICT" = "ALARM" ]; then
    mkdir -p "$PAGES_DIR" 2>/dev/null || true
    {
      date +%s 2>/dev/null || echo 0
      printf 'render %s — TUI render drawing %s cores (budget %s, alarm %s)\n' \
        "$VERDICT" "${RENDER_CORES:-?}" "$WARN_CORES" "$ALARM_CORES"
      printf 'top consumer: %s at %s%%  ·  panes: %s  ·  sessions: %s  ·  indexing: %s cores\n' \
        "$TOP_NAME" "$TOP_PCT" "$PANES" "$SESSIONS" "$IDX_CORES"
      printf 'shed it — in order of measured effect:\n'
      printf '  1. bin/cc-reaper --watchdog-census    (retire orphaned watchdogs + their panes)\n'
      printf '  2. /handoff the idle sessions          (each closed pane stops being drawn)\n'
      printf '  3. top consumer is %s — if that is iTerm2, pane COUNT is the lever;\n' "$TOP_NAME"
      printf '     scripts/iterm2-perf-parity.sh reports which render knobs are still adrift.\n'
      printf 'This is an ALARM, not a gate: it never refuses a spawn. See MACHINE_CAPACITY_V2.md §11.3 M8.\n'
      printf 're-run:  %s\n' "$0"
    } > "$PAGE" 2>/dev/null || true
  else
    rm -f "$PAGE" "$PAGE.notified" 2>/dev/null || true
  fi
fi

if [ "$QUIET" != 1 ] && [ "$WANT_JSON" != 1 ]; then
  echo "render-census — $TS"
  echo "  render cores:           ${RENDER_CORES:-?}   (warn >=${WARN_CORES} · alarm >=${ALARM_CORES})"
  echo "  iTerm2 / WindowServer:  ${ITERM_CPU:-?}% / ${WS_CPU:-?}%   (top -l 2 second sample)"
  echo "  iTerm2 hot thread:      ${HOT_PCT}% (share ${HOT_SHARE} — ps -M lifetime avg, not sample)"
  echo "  panes / sessions:       ${PANES} / ${SESSIONS}"
  echo "  indexing class:         ${IDX_CORES} cores · ${MDW_SPAWNS} mdworker spawns in ${SAMPLE_S}s"
  echo "  top consumer:           ${TOP_NAME} at ${TOP_PCT}%"
  echo "  VERDICT:                ${VERDICT}"
  if [ "$VERDICT" = "WARN" ] || [ "$VERDICT" = "ALARM" ]; then
    echo "  This alarm never refuses a spawn. Shed by closing panes (/handoff idle sessions,"
    echo "  bin/cc-reaper --watchdog-census); see MACHINE_CAPACITY_V2.md §11.3 M8."
  fi
fi
[ "$WANT_JSON" = 1 ] && printf '%s\n' "$JSON"
exit "$RC"
