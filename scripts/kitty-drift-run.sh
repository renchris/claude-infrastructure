#!/bin/bash
# kitty-drift-run.sh — hold kitty at a CONSTANT layout for N hours and sample the leak instrument.
#
# WHY THIS EXISTS. docs/plans/TERMINAL_AGNOSTIC_L3_L4.md §4.1 lists "kitty multi-hour drift at
# constant layout" as OPEN: the 12 h/48-pane run was destroyed by the 2026-07-31 11:46 spinlock
# panic before its second reading. That is now the SECOND time this measurement has been needed,
# so it stops being an ad-hoc command line and becomes a script that survives a reboot.
#
# WHAT IT ESTABLISHES, and what it cannot.
#   DRIFT — not level — is the only reading that supports a leak verdict. Every macOS app carries a
#   large offscreen window population and a large baseline port table; a single reading convicts
#   nobody (measured baselines: Finder 20 offscreen windows, Terminal 18, Cursor 22). The incumbent
#   iTerm2 number this run exists to be compared against is +76 mach ports/hr AT FROZEN LAYOUT while
#   RSS FALLS — i.e. a port leak that a memory reading actively hides.
#   A flat drift here does NOT prove kitty never leaks; it proves it does not leak ON THESE COUNTERS
#   OVER THIS WINDOW at this layout. That is exactly the claim §4.1 needs and no more.
#
# SAFETY CEILINGS (binding, non-negotiable — a research probe spinlock-panicked this box on
# 2026-07-31 with an 8,368-thread ladder, costing a hard reboot and 19 live sessions):
#   ≤ 512 threads · ≤ 64 panes · ≤ 16 OS windows · ≤ 64 processes, TOTAL, EVER.
# PANES defaults to 30, not the 48 of the destroyed run. 48 panes is 48 shells + kitty + the
# sampler's own transient children (top, sample, swiftc) ≈ 55-58 processes = 86-90% of the process
# ceiling, held for six hours. Drift is a RATE, so 30 panes measures the same leak at ~62% of the
# amplitude with ~48% ceiling headroom. The trade is stated here rather than buried, and a reader
# can scale the reported rate. This script REFUSES to exceed the ceilings rather than trusting the
# caller (see the guard below) — a ceiling that depends on the operator remembering it is not one.
#
# READ-ONLY with respect to the operator's environment: it drives ONLY its own kitty instance,
# addressed by an explicit --to socket, and it never touches iTerm2 or any running claude process.
#
# USAGE
#   scripts/kitty-drift-run.sh --hours 6 --panes 30            # create layout, sample, tear down
#   scripts/kitty-drift-run.sh --hours 6 --no-teardown         # leave the layout up afterwards
#   scripts/kitty-drift-run.sh --teardown-only                 # close just this run's panes
#
# VERDICT TOKENS (last line, machine-parsable — a consumer must be able to tell "measured zero
# drift" from "the instrument never ran", the failure recorded in memory
# claimed-outcome-vs-checked-outcome):
#   verdict=OK        the full window elapsed and ≥3 samples landed — a fittable series
#   verdict=PARTIAL   the layout stood and samples landed, but fewer than 3, or the window was cut
#   verdict=NO-DATA   the layout could not be built, or kitty is not reachable  (exit 3)
set -uo pipefail

HOURS=6; PANES=30; SOCKET="unix:/tmp/kitty-axis"; EVERY=900
TEARDOWN=1; TEARDOWN_ONLY=0; OUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --hours)         HOURS="${2:-6}"; shift 2 ;;
    --panes)         PANES="${2:-30}"; shift 2 ;;
    --socket)        SOCKET="${2:-}"; shift 2 ;;
    --every)         EVERY="${2:-900}"; shift 2 ;;
    --out)           OUT="${2:-}"; shift 2 ;;
    --no-teardown)   TEARDOWN=0; shift ;;
    --teardown-only) TEARDOWN_ONLY=1; shift ;;
    -h|--help)       sed -n '1,40p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

# ── HARD CEILING GUARD ────────────────────────────────────────────────────────────────────────────
# Refuse rather than trust. The ceiling exists because a probe that escalated until something broke
# DID break this box; a script that merely documents the limit repeats that failure the first time
# someone passes a bigger number "just to see".
MAX_PANES=64
if [ "$PANES" -gt "$MAX_PANES" ]; then
  echo "kitty-drift-run: REFUSED — --panes $PANES exceeds the hard ceiling of $MAX_PANES" >&2
  echo "verdict=NO-DATA"; exit 3
fi
# 1 shell per pane + kitty + kitten + the sampler's transient children. Keep total under 64.
if [ "$((PANES + 8))" -gt 64 ]; then
  echo "kitty-drift-run: REFUSED — $PANES panes projects to $((PANES+8)) processes, over the 64 ceiling" >&2
  echo "verdict=NO-DATA"; exit 3
fi

KITTEN="$(command -v kitten || echo /Applications/kitty.app/Contents/MacOS/kitten)"
TITLE_PREFIX="cc-drift"
k() { "$KITTEN" @ --to "$SOCKET" "$@"; }

# ── teardown: close ONLY the panes this script created, matched by title prefix ───────────────────
# Deliberately NOT `close-window --match all` and NOT a kill of the kitty pid: this instance may be
# shared, and the operator's own windows must survive. Matching on our own title prefix scopes the
# destructive verb to what we made (memory: scope to the dangerous EFFECT, never the location).
teardown() {
  local n=0
  while read -r _id; do
    [ -n "$_id" ] || continue
    k close-window --match "id:$_id" >/dev/null 2>&1 && n=$((n+1))
  done < <(k ls 2>/dev/null | python3 -c "
import sys,json
try: d=json.load(sys.stdin)
except Exception: sys.exit(0)
for osw in d:
    for t in osw.get('tabs',[]):
        for w in t.get('windows',[]):
            if str(w.get('title','')).startswith('$TITLE_PREFIX'): print(w['id'])
" 2>/dev/null)
  echo "  torn down $n pane(s) titled ${TITLE_PREFIX}*"
}

if [ "$TEARDOWN_ONLY" = 1 ]; then teardown; echo "verdict=OK"; exit 0; fi

# ── reachability ──────────────────────────────────────────────────────────────────────────────────
if ! k ls >/dev/null 2>&1; then
  echo "kitty-drift-run: kitty not reachable at $SOCKET" >&2
  echo "verdict=NO-DATA"; exit 3
fi

PID="$(pgrep -x kitty | head -1 || true)"
[ -n "$PID" ] || { echo "kitty-drift-run: no kitty process" >&2; echo "verdict=NO-DATA"; exit 3; }

OUT="${OUT:-${TMPDIR:-/tmp}/kitty-drift-$(date +%Y%m%dT%H%M%S).tsv}"
# The heartbeat is deliberately non-empty. A layout of 30 shells sitting at a static prompt exercises
# almost no render path, and a leak that only accretes per FRAME would go undetected — the run would
# report a reassuring flat line for the wrong reason (a vacuous pass). One line per pane per 5 s is
# ~6 lines/s across 30 panes: enough to keep the renderer live, far too little to be a CPU load.
HEARTBEAT='while :; do date +%H:%M:%S; sleep 5; done'

echo "kitty-drift-run — pid=$PID panes=$PANES hours=$HOURS every=${EVERY}s  $(date -u +%FT%TZ)"
echo "  out=$OUT"

# ── build the constant layout ─────────────────────────────────────────────────────────────────────
FIRST="$(k launch --type=os-window --title "${TITLE_PREFIX}-001" \
          --cwd "${TMPDIR:-/tmp}" /bin/sh -c "$HEARTBEAT" 2>&1)"
case "$FIRST" in ''|*[!0-9]*) echo "kitty-drift-run: could not create OS window: $FIRST" >&2
                              echo "verdict=NO-DATA"; exit 3 ;; esac
k goto-layout grid >/dev/null 2>&1
made=1
for i in $(seq 2 "$PANES"); do
  if k launch --type=window --title "$(printf '%s-%03d' "$TITLE_PREFIX" "$i")" \
       --cwd "${TMPDIR:-/tmp}" /bin/sh -c "$HEARTBEAT" >/dev/null 2>&1; then made=$((made+1)); fi
done
echo "  layout built: $made/$PANES panes in 1 OS window (grid)"
if [ "$made" -lt "$PANES" ]; then echo "  ⚠ only $made panes came up — reported n reflects reality"; fi

# Settle: kitty reflows and re-rasterises the grid for a few seconds after the last launch. Sampling
# during that transient would book one-off allocation as drift.
sleep 20

# Column 7 is the LIVE PANE COUNT, not a window count. Naming it `win` would collide with the
# window-census column of the same name in terminal-bench.sh, where it means CGWindowList entries
# (kitty measures 36 there at this same layout — one visible OS window plus a large offscreen
# population). Two columns named `win` meaning different things is how a comparison table acquires a
# silent off-by-36.
printf 'ts\telapsed_s\tcpu\tmem_mb\tthreads\tports\tpanes\toff\tws_cpu\tws_ports\n' > "$OUT"

START=$(date +%s)
END=$((START + HOURS*3600))
n=0
while [ "$(date +%s)" -lt "$END" ]; do
  # SECOND sample of top -l 2. The first is a LIFETIME average — using it misread WindowServer on
  # this box by 2.3x.
  line="$(top -l 2 -pid "$PID" -stats pid,command,cpu,mem,th,ports 2>/dev/null \
          | grep -E "^[[:space:]]*${PID}[[:space:]]" | tail -1)"
  wsline=""
  WS_PID="$(pgrep -x WindowServer | head -1 || true)"
  [ -n "$WS_PID" ] && wsline="$(top -l 2 -pid "$WS_PID" -stats pid,command,cpu,mem,th,ports 2>/dev/null \
          | grep -E "^[[:space:]]*${WS_PID}[[:space:]]" | tail -1)"
  if [ -n "$line" ]; then
    cpu="$(awk '{print $3}' <<<"$line")"
    mem="$(awk '{print $4}' <<<"$line")"
    th="$(awk  '{print $5}' <<<"$line" | tr -d '+-' | cut -d/ -f1)"
    pt="$(awk '{print $6}' <<<"$line" | tr -d '+-')"
    mem="$(awk -v m="$mem" 'BEGIN{ v=m; sub(/[KMG][+-]?$/,"",v);
        if(m ~ /G[+-]?$/) v=v*1024; else if(m ~ /K[+-]?$/) v=v/1024; printf "%.0f", v }')"
    wcpu="NA"; wpt="NA"
    if [ -n "$wsline" ]; then
      wcpu="$(awk '{print $3}' <<<"$wsline")"; wpt="$(awk '{print $6}' <<<"$wsline" | tr -d '+-')"
    fi
    # Pane count is RE-READ every sample, never assumed. "Constant layout" is the precondition of
    # the whole measurement; if a pane dies the series must show it rather than silently average a
    # shrinking layout into the drift rate.
    live="$(k ls 2>/dev/null | python3 -c "
import sys,json
try: d=json.load(sys.stdin)
except Exception: print('NA'); sys.exit(0)
print(sum(1 for o in d for t in o.get('tabs',[]) for w in t.get('windows',[])
          if str(w.get('title','')).startswith('$TITLE_PREFIX')))" 2>/dev/null || echo NA)"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$(date -u +%FT%TZ)" "$(( $(date +%s) - START ))" "$cpu" "$mem" "$th" "$pt" \
      "$live" "NA" "$wcpu" "$wpt" >> "$OUT"
    n=$((n+1))
    echo "  [$n] t+$(( ($(date +%s)-START)/60 ))m  mem=${mem}MB th=$th ports=$pt panes=$live ws_ports=$wpt"
  fi
  sleep "$EVERY"
done

echo "  samples=$n → $OUT"
[ "$TEARDOWN" = 1 ] && teardown
if [ "$n" -ge 3 ]; then echo "verdict=OK"; else echo "verdict=PARTIAL"; fi
