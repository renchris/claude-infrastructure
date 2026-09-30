#!/usr/bin/env bash
# alarm-reboot-prep.sh — the agent half of the safe reboot order, run whenever the capacity alarm's
# kalloc rung fires (host-memory.2 of the 2026-09-30 backlog master plan).
#
# WHY A STANDING PROCEDURE. data.kalloc.1024 is a kernel zone only a reboot resets. It read
# 14.78 GB after 13.8 days on the 2026-09-16 boot (1.05 GB/day measured) and panic #5 died at
# 9.89 GB, so a reboot buys roughly 5 days to the 6 GB alarm and 9 to the panic level until the
# driver is fixed (docs/research/kalloc-ratchet-2026-10.md). The first reboot, on 2026-09-30, went
# in a safe order; this script is that order, so every later one repeats it instead of improvising:
#
#   1. record the start epoch        ~/.claude/autonomy/reboot-<date>.start
#   2. record the live-session roster ~/.claude/autonomy/reboot-<date>.roster.json  (cc-sessions --json;
#      the resume path relaunches from it after login)
#   3. refuse while a land is in flight (a ship-land.sh PROCESS) — a reboot mid-push strands the land
#   4. record the kalloc reading the reboot is about to erase
#   5. print the operator's steps: long-running leads write a handoff first; if a root zone capture
#      is staged (~/.claude/autonomy/kalloc-root-capture.cmd, written by the ratchet analysis when
#      it could not name a driver), run it BEFORE rebooting, because the reboot erases the evidence;
#      then reboot within 24 h of the alarm. If ~/.claude/autonomy/kitty-restart-pending exists,
#      this reboot is also the kitty restart (plan W3) and the script says so.
#
# It never reboots, never kills a session and never runs sudo: those are the operator's.
# Exit: 0 READY · 3 NOT-READY (a land is in flight; re-run when it finishes) · 2 usage.
# Env:  CC_REBOOT_PREP_DIR (default ~/.claude/autonomy) · CC_REBOOT_PREP_DATE (default today, local)
#       CC_REBOOT_PREP_PS (default /bin/ps; stub for tests) · CC_REBOOT_PREP_SESSIONS (default cc-sessions)
#       CC_REBOOT_PREP_ZPRINT (default /usr/bin/zprint)
set -uo pipefail

case "${1:-}" in -h|--help) sed -n '2,26p' "$0"; exit 0 ;; '') ;; *) echo "usage: $0 [--help]" >&2; exit 2 ;; esac

DIR="${CC_REBOOT_PREP_DIR:-$HOME/.claude/autonomy}"
DAY="${CC_REBOOT_PREP_DATE:-$(date +%Y-%m-%d)}"
PS="${CC_REBOOT_PREP_PS:-/bin/ps}"
SESSIONS="${CC_REBOOT_PREP_SESSIONS:-cc-sessions}"
ZPRINT="${CC_REBOOT_PREP_ZPRINT:-/usr/bin/zprint}"
CAPTURE_CMD="$DIR/kalloc-root-capture.cmd"
mkdir -p "$DIR" || { echo "alarm-reboot-prep: cannot create $DIR" >&2; exit 2; }

now="$(date +%s)"
printf '%s\n' "$now" > "$DIR/reboot-$DAY.start"

roster="$DIR/reboot-$DAY.roster.json"
if "$SESSIONS" --json > "$roster.tmp" 2>/dev/null && [ -s "$roster.tmp" ]; then
  mv -f "$roster.tmp" "$roster"
  n="$(grep -o '"paneUUID"' "$roster" 2>/dev/null | wc -l | tr -d ' ')"   # occurrences, not lines
else
  rm -f "$roster.tmp"; n="unknown (cc-sessions failed — record the panes by hand)"
fi

kalloc="$("$ZPRINT" data.kalloc.1024 2>/dev/null \
          | awk '$1 == "data.kalloc.1024" && $7 ~ /^[0-9]+$/ { printf "%.2f", $2 * $7 / 1073741824; exit }')"
printf '%s kalloc1024_gb=%s\n' "$now" "${kalloc:-unreadable}" >> "$DIR/reboot-$DAY.start"

# A land in flight is a process whose PROGRAM is ship-land.sh (argv[0], or argv[1] under a shell) —
# never `pgrep -f ship-land.sh`, which also matches every agent session whose brief merely MENTIONS
# the name (measured 2026-09-30: 6 of 6 matches were claude sessions, 0 were lands).
lands="$("$PS" -axo pid=,args= 2>/dev/null | awk '
  { a0 = $2; a1 = $3 }
  a0 ~ /(^|\/)ship-land\.sh$/ { print $1; next }
  a0 ~ /(^|\/)(ba|z|da)?sh$/ && a1 ~ /(^|\/)ship-land\.sh$/ { print $1 }' | tr '\n' ' ')"

echo "alarm-reboot-prep — $(date '+%Y-%m-%d %H:%M %z')"
echo "  start epoch        $now  → $DIR/reboot-$DAY.start"
echo "  live sessions      $n  → $roster"
echo "  data.kalloc.1024   ${kalloc:-unreadable} GB (the reading this reboot erases)"
if [ -n "${lands// /}" ]; then
  echo "  lands in flight    pids ${lands% } — NOT READY: re-run when ship-land.sh has exited"
  echo "verdict=NOT-READY reason=land-in-flight"
  exit 3
fi
echo "  lands in flight    none"
echo
echo "Operator steps, in order:"
echo "  1. Long-running leads write a handoff first (the FLEET_V2 lead included); every other"
echo "     session resumes from its own handoff or from the roster above."
if [ -s "$CAPTURE_CMD" ]; then
  echo "  2. A root zone capture is STAGED. Run it before rebooting — the reboot erases the evidence:"
  echo "       bash $CAPTURE_CMD"
  echo "  3. Reboot within 24 h of the alarm."
else
  echo "  2. Reboot within 24 h of the alarm. (No root capture is staged: the ratchet analysis named"
  echo "     a driver, or has not asked for one.)"
fi
# The kitty restart rides the next alarm reboot after the operator's kitty build choice (plan W3):
# whoever stages the build drops this marker with one line saying what the restart installs.
if [ -s "$DIR/kitty-restart-pending" ]; then
  echo "  This reboot is ALSO the kitty restart: $(head -1 "$DIR/kitty-restart-pending")"
  echo "     (remove $DIR/kitty-restart-pending once kitty is back on the new build)"
fi
echo "  After login, resume sessions with the resume-sessions skill; the next capacity-alarm tick"
echo "  should read data.kalloc.1024 under 3 GB."
echo "verdict=READY"
exit 0
