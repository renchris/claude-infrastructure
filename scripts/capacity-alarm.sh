#!/bin/bash
# capacity-alarm.sh — surface machine-capacity pressure BEFORE the box starts swapping.
#
# WHY (row 13 M6, MACHINE_CAPACITY_V2.md §4). The row measured a real ceiling — ~50 concurrent
# sessions on this 10-core/64 GiB box — and the ceiling was STATED with nothing that would notice it
# being approached. An unalarmed ceiling is discovered by swapping, which is the lagging indicator.
#
# THIS IS AN ALARM, NOT A GATE — and that distinction is the whole design.
# The landed `capacity_gate()` (handoff-fire.sh, CC_FIRE_MAX_LOAD_PER_CORE=2.0) is the cautionary
# case: measured against 13 real samples it scores REFUSE 10/10, because it keys on a system-wide
# loadavg dominated by the TUI renderer and macOS scanning — neither sheddable by refusing a spawn.
# Deployed, it would be a permanent dispatch outage. So this file:
#   · NEVER refuses, blocks, queues, sleeps, or polls-until-clear. It reports and exits (R1: a
#     shedder that WAITS amplifies).
#   · keys on MEMORY, which is genuinely sheddable and genuinely attributable to sessions — never on
#     loadavg, which swung 2.05x (29.15 -> 59.80) at a CONSTANT 31-32 sessions.
#
# THE INSTRUMENT, chosen because the obvious ones lie:
#   · `ps rss` summed over sessions OVERCOUNTS ~2.34x (it double-counts shared pages) — do not use
#     it to decide anything. It is fine for per-process comparison, wrong for a fleet total.
#   · loadavg is high-variance and not session-attributable (above).
#   · What actually decides whether the box swaps is RECLAIMABLE HEADROOM:
#     free + speculative + inactive + purgeable. Measured 28.2 GB with 8 sessions live.
#   · `sysctl vm.swapusage` used > 0 is the HARD signal — by then it is already happening.
#
# Verdicts (four, never a boolean — "could not measure" must not read as "fine"):
#   OK       headroom above the warn floor and no swap in use.        exit 0
#   WARN     headroom below the warn floor, still no swap.            exit 1
#   ALARM    swap in use, or headroom below the alarm floor.          exit 2
#   NO-DATA  vm_stat/sysctl unreadable — nothing is asserted.         exit 3
#
# Seams: CC_CAPACITY_ALARM=off (kill switch) · CC_CAP_WARN_GB (default 8) ·
#        CC_CAP_ALARM_GB (default 3) · CC_CAP_LOG · CC_CAP_SELFTEST=1 (positive control)
#
# bash 3.2 safe. Ships to launchd ⇒ tested under /bin/bash.

set -uo pipefail

WARN_GB="${CC_CAP_WARN_GB:-8}"
ALARM_GB="${CC_CAP_ALARM_GB:-3}"
LOG="${CC_CAP_LOG:-$HOME/.claude/logs/capacity-alarm.jsonl}"
APPEND=1; WANT_JSON=0; QUIET=0

while [ $# -gt 0 ]; do
  if   [ "$1" = "--json" ];      then WANT_JSON=1
  elif [ "$1" = "--quiet" ];     then QUIET=1
  elif [ "$1" = "--no-append" ]; then APPEND=0
  elif [ "$1" = "--selftest" ];  then CC_CAP_SELFTEST=1
  elif [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    sed -n '2,/^set -uo/p' "$0" | sed 's/^# \{0,1\}//; /^set -uo/d'; exit 0
  else echo "capacity-alarm.sh: unknown arg '$1'" >&2; exit 64
  fi
  shift
done

if [ "${CC_CAPACITY_ALARM:-on}" = "off" ]; then
  [ "$QUIET" = 1 ] || echo "capacity-alarm: disabled (CC_CAPACITY_ALARM=off)"
  exit 0
fi

# ── read machine memory truth ─────────────────────────────────────────────────────────────────────
# One python3 pass over vm_stat: the page size is authoritative from vm_stat's own header, never
# assumed to be 4096 (it is 16384 on Apple silicon, and assuming 4096 understates by 4x).
#
# NOTE ON THE INVOCATION FORM — `python3 -c`, never `python3 - <<'HEREDOC'`.
# The heredoc form was written here first and was silently broken: with `python3 -`, the PROGRAM is
# read from stdin, so a heredoc claims the very stdin the pipe was supposed to deliver and
# `sys.stdin.read()` gets nothing. The result was a permanent NO-DATA. This is the documented trap in
# memory blind-check-generators-stdin-and-sid-keys ("`python3 - <<PY` eats the stdin a guard meant to
# read"), and shellcheck flags it as SC2259. Keep the program in -c so stdin stays the data channel.
read_mem() {
  vm_stat 2>/dev/null | "${CC_CAP_PYTHON:-python3}" -c '
import sys,re
o=sys.stdin.read()
m=re.search(r"page size of (\d+)",o)
if not m: sys.exit(1)
pg=int(m.group(1)); d={}
for line in o.splitlines()[1:]:
    if ":" not in line: continue
    k,v=line.split(":",1); v=v.strip().rstrip(".")
    if v.isdigit(): d[k.strip()]=int(v)
G=lambda k: d.get(k,0)*pg/1024**3
head=G("Pages free")+G("Pages speculative")+G("Pages inactive")+G("Pages purgeable")
comp=G("Pages occupied by compressor")
act=G("Pages active"); wired=G("Pages wired down")
if head==0 and act==0: sys.exit(1)
print("%.2f %.2f %.2f %.2f" % (head,comp,act,wired))
' 2>/dev/null
}

MEM="$(read_mem || true)"
SWAP_MB="$(sysctl -n vm.swapusage 2>/dev/null \
            | sed -n 's/.*used = \([0-9.]*\)M.*/\1/p' | head -1)"
# shellcheck disable=SC2009  # ps|grep is REQUIRED. pgrep was tried here and SILENTLY UNDERCOUNTS:
# measured 2026-07-29 with 8 live sessions, `pgrep -cf 'claude-code/bin/claude\.exe'` returned 0
# while `ps -eo args | grep -c` returned 8 — macOS pgrep -f matches against a TRUNCATED argv, so a
# long absolute path never matches, and `pgrep -x` cannot see the path at all. A counter that reads 0
# forever is the exact failure in memory actuator-must-see-the-target-population (134/134 MISS), and
# here it would make this alarm permanently report an empty fleet. Verify a census instrument against
# a known population BEFORE trusting it; a zero from a matcher is not evidence of absence.
SESSIONS="$(ps -eo args 2>/dev/null | grep -cE 'claude-code/bin/claude\.exe' || true)"
case "$SESSIONS" in ''|*[!0-9]*) SESSIONS=0 ;; esac

# ── positive control (R6) — prove the ladder can reach every rung ─────────────────────────────────
# Without this, "OK" is indistinguishable from "the thresholds are unreachable". Runs the SAME
# classify function against synthetic inputs, so it tests the real code path, not a description.
classify() { # <headroom_gb> <swap_mb> → prints verdict
  local h="$1" s="$2"
  if [ -z "$h" ]; then printf 'NO-DATA'; return 0; fi
  # swap in use is the hard signal and outranks headroom
  if [ -n "$s" ] && [ "$(printf '%s\n' "$s" | cut -d. -f1)" -gt 0 ] 2>/dev/null; then printf 'ALARM'; return 0; fi
  if awk -v a="$h" -v b="$ALARM_GB" 'BEGIN{exit !(a+0 < b+0)}'; then printf 'ALARM'; return 0; fi
  if awk -v a="$h" -v b="$WARN_GB"  'BEGIN{exit !(a+0 < b+0)}'; then printf 'WARN';  return 0; fi
  printf 'OK'
}

if [ "${CC_CAP_SELFTEST:-0}" = "1" ]; then
  fails=0
  for probe in "99:0:OK" "5:0:WARN" "1:0:ALARM" "99:512:ALARM" ":0:NO-DATA"; do
    h="${probe%%:*}"; rest="${probe#*:}"; s="${rest%%:*}"; want="${rest#*:}"
    got="$(classify "$h" "$s")"
    if [ "$got" = "$want" ]; then echo "  control OK   headroom='$h' swap='$s' → $got"
    else echo "  control FAIL headroom='$h' swap='$s' → $got (want $want)"; fails=$((fails+1)); fi
  done
  [ "$fails" -eq 0 ] && { echo "capacity-alarm: selftest GREEN (4 rungs + no-data reachable)"; exit 0; }
  echo "capacity-alarm: selftest RED ($fails)" >&2; exit 70
fi

HEAD=""; COMP=""; ACT=""; WIRED=""
if [ -n "$MEM" ]; then
  # shellcheck disable=SC2086  # deliberate word-split of the 4-field python output
  set -- $MEM
  HEAD="${1:-}"; COMP="${2:-}"; ACT="${3:-}"; WIRED="${4:-}"
fi

VERDICT="$(classify "$HEAD" "${SWAP_MB:-0}")"
case "$VERDICT" in
  OK)      RC=0 ;;
  WARN)    RC=1 ;;
  ALARM)   RC=2 ;;
  *)       RC=3 ;;
esac

# Projected ceiling: how many MORE sessions fit in the reclaimable headroom, at the row's measured
# ~636 MB/session process RSS. Reported as an ESTIMATE and never used in the verdict — per-session
# RSS overcounts shared pages, so this is directional guidance for the operator, not a threshold.
PER_MB="${CC_CAP_PER_SESSION_MB:-636}"
ROOM="?"
if [ -n "$HEAD" ]; then
  ROOM="$(awk -v h="$HEAD" -v p="$PER_MB" 'BEGIN{printf "%d", (h*1024)/p}')"
fi

TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
JSON="$(printf '{"ts":"%s","verdict":"%s","sessions":%s,"headroom_gb":%s,"compressor_gb":%s,"active_gb":%s,"wired_gb":%s,"swap_used_mb":%s,"warn_gb":%s,"alarm_gb":%s,"est_room_sessions":%s,"per_session_mb_est":%s}' \
  "$TS" "$VERDICT" "$SESSIONS" "${HEAD:-null}" "${COMP:-null}" "${ACT:-null}" "${WIRED:-null}" \
  "${SWAP_MB:-0}" "$WARN_GB" "$ALARM_GB" "${ROOM:-null}" "$PER_MB")"

if [ "$APPEND" = 1 ]; then
  mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
  printf '%s\n' "$JSON" >> "$LOG" 2>/dev/null || true
fi

if [ "$QUIET" != 1 ] && [ "$WANT_JSON" != 1 ]; then
  echo "capacity-alarm — $TS"
  echo "  live sessions:          ${SESSIONS}"
  echo "  reclaimable headroom:   ${HEAD:-?} GB   (warn <${WARN_GB} · alarm <${ALARM_GB})"
  echo "  compressor / active:    ${COMP:-?} GB / ${ACT:-?} GB"
  echo "  swap used:              ${SWAP_MB:-0} MB   (>0 ⇒ ALARM, the lagging indicator)"
  echo "  est. room for:          ~${ROOM} more sessions at ~${PER_MB} MB (ESTIMATE — rss overcounts)"
  echo "  VERDICT:                ${VERDICT}"
  if [ "$VERDICT" = "WARN" ] || [ "$VERDICT" = "ALARM" ]; then
    echo "  This alarm never refuses a spawn. Shed by CLOSING sessions (/handoff the idle ones);"
    echo "  do NOT add a load-based spawn gate — see MACHINE_CAPACITY_V2.md §8.5.7."
  fi
fi
[ "$WANT_JSON" = 1 ] && printf '%s\n' "$JSON"
exit "$RC"
