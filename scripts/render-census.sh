#!/bin/bash
# render-census.sh — put the DOMINANT sustained consumer under a measured budget with an alarm.
#
# WHY (row 13 M8, MACHINE_CAPACITY_V2.md §11.3). Every capacity mechanism this row built so far
# governs memory or batch CPU. The measured truth (§11.2 gu13-live axis) is that neither is the
# stable floor: TUI render — the terminal (iTerm2/kitty) + WindowServer — draws 1.76-1.91 cores and
# NEVER MOVES, while the batch and indexing classes swing. A consumer that large with nothing
# watching it is the same unalarmed-ceiling defect capacity-alarm.sh was built to close, one class
# over.
#
# 🚨 THE RENDER SUM COUNTS kitty (added 2026-08-11, closing the FIFTH instrument artifact).
# scaling-bottlenecks-2026-08-09/09-adv-constants.md §2 and 02-render.md §6 D1 measured this file
# summing `iTerm2` + `WindowServer` ONLY while the fleet renders in KITTY: live, the census printed
# `iTerm2/WindowServer: 0.0% / 33.2% → 0.33 cores` in the same minute an independent `top -l 2 -s 5`
# read WindowServer 31.8-35.0% PLUS kitty 9.8-11.6% — a 23-26% under-read. The asymmetry is what
# made it an artifact rather than a nit: the WindowServer share it DID see is the pane-INDEPENDENT
# baseline, and the kitty share it could not see is the per-pane term the 3.5-core alarm exists to
# catch. This file's *pane* arm was given a kitty branch on 2026-07-31 (:228-244); its *CPU* arm was
# not, so two halves of one instrument disagreed about which terminal exists. They now agree.
#
# 🚨 WindowServer IS A SHARED DESKTOP TERM AND IS LABELLED AS ONE (same date, 02-render.md §6 D2).
# WindowServer is the whole-desktop compositor, not a terminal component. Measured concurrently on
# this box: `Dia 13.7% + Browser Helper 45.4% + Browser Helper 14.3%` against 4 displays totalling
# ~52 Mpx (3× DELL S2725QC 5K@60 + built-in). 02-render.md §2 bounds the part actually attributable
# to terminal draw at 0.002-0.009 cores/pane — i.e. 0.02-0.07 cores for 8 heavy panes — against a
# 0.20-0.42-core FLAT term that would read identically with zero panes open. Charging 100% of it to
# "terminal render" inflates the terminal's share with work the terminal did not do, and it is not
# a conservative error: it is the term that made the kitty-blind number look plausible (the two
# defects pushed in OPPOSITE directions).
#   The fix here is the ANNOTATE arm of 02-render.md §6, not a re-keying of the alarm: render_cores
#   still sums terminal+compositor, so the WARN/ALARM floors keep the calibration they were derived
#   against, but the emitted row and the human output now split
#       terminal_cores   = iTerm2 + kitty        ← the part panes can actually move
#       compositor_cores = WindowServer          ← SHARED: displays + browser + every other client
#   and say so at every render site. Re-keying the alarm onto terminal_cores alone would need
#   thresholds re-derived from a measured degradation point, which no document has; publishing a
#   number under a name that lies is what this change exists to stop.
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
#     matches — iTerm2, kitty, WindowServer, mdworker_shared (15) — all fit whole. Matching is
#     EXACT on the command field, never a substring, so `iTermServer` can never be counted as
#     `iTerm2`, and the short-lived `kitten` helpers can never be counted as `kitty`.
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

# One awk pass over the second sample. Emits: iterm_pid iterm_cpu kitty_cpu ws_cpu idx_cpu rows
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
    if (cmd == "kitty")        { kcpu += cpu }
    if (cmd == "WindowServer") { wcpu += cpu }
    if (cmd == "mds" || cmd == "mds_stores" || cmd == "mdworker" || \
        cmd == "mdworker_shared" || cmd == "corespotlightd") xcpu += cpu
  }
  END { printf "%s %.1f %.1f %.1f %.1f %d", (ipid == "" ? "0" : ipid), icpu+0, kcpu+0, wcpu+0, xcpu+0, rows+0 }
' 2>/dev/null || true)"

ITERM_PID=""; ITERM_CPU=""; KITTY_CPU=""; WS_CPU=""; IDX_CPU=""; TOP_ROWS=0
if [ -n "$RENDER_FIELDS" ]; then
  # shellcheck disable=SC2086  # deliberate word-split of the 6-field awk output
  set -- $RENDER_FIELDS
  ITERM_PID="${1:-0}"; ITERM_CPU="${2:-}"; KITTY_CPU="${3:-}"; WS_CPU="${4:-}"
  IDX_CPU="${5:-}"; TOP_ROWS="${6:-0}"
fi

# NO-DATA is keyed on the SAMPLE, not on the reading. top running fine on a box where iTerm2 happens
# not to be live is a legitimate 0.00 cores; top failing to produce a second sample asserts nothing.
# Conflating those two would let a broken instrument report the healthiest possible number.
#
# THE SPLIT (02-render.md §6 D2). render_cores keeps summing BOTH classes so the WARN/ALARM floors
# retain the calibration they were derived against — but the two halves are also emitted on their
# own, because only one of them is a terminal cost the operator's shed levers can move:
#   terminal_cores   iTerm2 + kitty   — panes move this
#   compositor_cores WindowServer     — SHARED whole-desktop compositor (displays + browser + …);
#                                       0.20-0.42 cores of it is flat and would read the same with
#                                       zero panes open. Only 0.002-0.009 cores/pane of it is the
#                                       terminal's.
RENDER_CORES=""; TERM_CORES="null"; COMP_CORES="null"
if [ "${TOP_ROWS:-0}" -gt 0 ] 2>/dev/null; then
  RENDER_CORES="$(awk -v a="${ITERM_CPU:-0}" -v k="${KITTY_CPU:-0}" -v b="${WS_CPU:-0}" \
    'BEGIN{printf "%.2f", (a+k+b)/100}')"
  TERM_CORES="$(awk -v a="${ITERM_CPU:-0}" -v k="${KITTY_CPU:-0}" 'BEGIN{printf "%.2f", (a+k)/100}')"
  COMP_CORES="$(awk -v b="${WS_CPU:-0}" 'BEGIN{printf "%.2f", b/100}')"
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

# Resolve the kitty binary ABSOLUTELY. Hooks and launchd jobs run with a minimal PATH that excludes
# Homebrew, so a bare `kitty` does not exist for exactly the AUTOMATED callers this file serves —
# green where a human tests it, dead where it runs. That is what left a teammate pane open for 3h09m
# with its 653 MB claude.exe resident on 2026-08-01 (full account: bin/cc-kitty-bin header).
# Falling back to the previous spelling keeps a partial deploy degraded rather than broken.
CC_KITTY_BIN="${CC_TERM_KITTY:-kitty}"
# Candidate order matters: the SYMLINK-RESOLVED sibling first. ~/.claude/scripts/*.sh are symlinks
# into this checkout, so `dirname "$0"/../bin` alone points at ~/.claude/bin — which only holds
# cc-kitty-bin AFTER install.sh runs. Resolving the link first finds the repo's own bin/ and makes
# the fix live the moment the file does, instead of waiting on a deploy it cannot trigger.
# ${HOME:-} DELIBERATELY: bash expands the ENTIRE for-list before the loop body runs, so a bare
# $HOME under `set -u` aborts this whole script on the third candidate even when the FIRST one
# resolves. With :- it degrades to a nonexistent path `[ -x ]` rejects. See bin/kitty-split-launch.sh.
_CC_KS="$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")"
for _CC_KB in "$(dirname "$_CC_KS")/../bin/cc-kitty-bin" "$(dirname "$0")/../bin/cc-kitty-bin" "${HOME:-}/.claude/bin/cc-kitty-bin"; do
  [ -x "$_CC_KB" ] || continue
  _CC_KR="$("$_CC_KB" 2>/dev/null)" && [ -n "$_CC_KR" ] && { CC_KITTY_BIN="$_CC_KR"; break; }
done
# NOTE the ${CC_KITTY_BIN:-…} fallback at every call site below. These functions are EXTRACTED
# INDIVIDUALLY with sed by tests/*.bats ("NOTHING HERE EXECUTES scripts/handoff-fire.sh"), so a
# function that depends on a top-level variable is unset in every extracted-function test — measured
# 2026-08-01, it turned `it2py bgtab` red. Each call site therefore re-states the pre-resolution
# spelling as its own default: production gets the absolute path from the block above, an extracted
# function degrades to exactly the behaviour it had before this change.

# ── pane count: ONE bounded terminal query, never a guess on failure ──────────────────────────────
# A failed pane query reports null. Substituting a remembered or derived number would make the log
# claim a measurement that never happened.
#
# iTerm2 is addressed by BUNDLE ID and short-circuited on `is running` (2026-07-31). "iTerm2" is
# only the CFBundleName of iTerm.app, so a NAME lookup resolves solely while iTerm2 is already
# running — once the fleet moved to kitty this query stopped measuring and could raise an
# undismissable "Where is iTerm2?" modal instead. `application id` cannot raise that modal, but it
# CAN launch the app, which a census must never do: an observer that starts its own subject is not
# an observer. Not running ⇒ zero iTerm2 panes, and that is a MEASUREMENT (0), not a failure (null).
#
# …AND THAT SHORT-CIRCUIT IS ONLY HALF THE FIX (2026-07-31). Inside kitty the AppleScript above is
# CORRECT and USELESS: it measures 0 iTerm2 panes truthfully while the fleet it was built to watch
# is elsewhere, so the render alarm's pane column — the operator's only shed lever (:278) — reads 0
# on a box with a dozen live panes. Under kitty the same quantity is the number of `windows` entries
# across every tab of every OS window in `kitty @ ls`; a kitty window IS a pane.
# The predicate MIRRORS bin/it2-wrapper:75 exactly, kill switch included, so this file cannot
# disagree with the handoff/pane machinery about which terminal this is.
# EVERY kitty failure mode lands on null, never on 0: no control socket, no kitty binary, no
# python3, a wedged socket cut by rc_bounded, or malformed JSON all yield EMPTY output, and the
# `case` below reads empty as INDETERMINATE. That asymmetry with the iTerm2 arm is deliberate —
# `is running` is a POSITIVE reading that no panes exist, whereas an unreadable socket asserts
# nothing at all, and a census that reports 0 for "could not look" lets a caller reap a live fleet.
rc_kitty() { # $1=seconds, rest=`kitty @` args — socket seam kept out of the call sites
  if [ -n "${CC_TERM_KITTY_TO:-}" ]; then
    rc_bounded "$1" "${CC_KITTY_BIN:-${CC_TERM_KITTY:-kitty}}" @ --to "$CC_TERM_KITTY_TO" "${@:2}"
  else
    rc_bounded "$1" "${CC_KITTY_BIN:-${CC_TERM_KITTY:-kitty}}" @ "${@:2}"
  fi
}
PANES="null"
if [ -n "${KITTY_WINDOW_ID:-}" ] && [ -z "${IT2_WRAPPER_NO_KITTY:-}" ]; then
  # python3 is the JSON reader this repo already uses for `kitty @ ls` (bin/it2-kitty:158), so the
  # two cannot drift on the os-windows→tabs→windows shape. Its absence is an unreadable terminal.
  PANE_OUT="$(rc_kitty 5 ls 2>/dev/null | python3 -c 'import json,sys
try: d = json.load(sys.stdin)
except Exception: sys.exit(1)
print(sum(len(t["windows"]) for ow in d for t in ow["tabs"]))' 2>/dev/null || true)"
else
  PANE_OUT="$(rc_bounded 5 osascript \
    -e 'if not (application id "com.googlecode.iterm2" is running) then return 0' \
    -e 'tell application id "com.googlecode.iterm2" to set n to 0' \
    -e 'tell application id "com.googlecode.iterm2" to repeat with w in windows' \
    -e 'repeat with t in tabs of w' \
    -e 'set n to n + (count of sessions of t)' \
    -e 'end repeat' -e 'end repeat' -e 'return n' 2>/dev/null || true)"
fi
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
  # kitty competes here too, else the census names iTerm2 (typically 0.0%) as the top consumer on a
  # kitty fleet — the platter would then point the operator's shed levers at an app that is not
  # running. WindowServer keeps the `(shared)` suffix wherever it wins: it is the desktop
  # compositor, so naming it bare invites the reader to shed panes at a browser and four displays.
  TOP_FIELDS="$(awk -v i="${ITERM_CPU:-0}" -v k="${KITTY_CPU:-0}" -v w="${WS_CPU:-0}" -v x="${IDX_CPU:-0}" 'BEGIN{
    n="iTerm2"; v=i+0
    if (k+0 > v) { n="kitty"; v=k+0 }
    if (w+0 > v) { n="WindowServer(shared)"; v=w+0 }
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
JSON="$(printf '{"ts":"%s","verdict":"%s","render_cores":%s,"terminal_cores":%s,"compositor_cores":%s,"compositor_attrib":"shared-desktop-not-terminal-only","iterm_cpu_pct":%s,"kitty_cpu_pct":%s,"windowserver_cpu_pct":%s,"hot_thread_pct":%s,"hot_thread_share":%s,"hot_thread_src":"ps-M-lifetime-avg","panes":%s,"sessions":%s,"indexing_cores":%s,"indexing_cpu_pct":%s,"mdworker_spawns_in_window":%s,"top_consumer":"%s","top_consumer_pct":%s,"sample_s":%s,"top_rows":%s,"warn_cores":%s,"alarm_cores":%s}' \
  "$TS" "$VERDICT" "${RENDER_CORES:-null}" "$TERM_CORES" "$COMP_CORES" \
  "${ITERM_CPU:-null}" "${KITTY_CPU:-null}" "${WS_CPU:-null}" \
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
      printf 'terminal (iTerm2+kitty): %s cores  ·  compositor (WindowServer, SHARED): %s cores\n' \
        "$TERM_CORES" "$COMP_CORES"
      printf 'top consumer: %s at %s%%  ·  panes: %s  ·  sessions: %s  ·  indexing: %s cores\n' \
        "$TOP_NAME" "$TOP_PCT" "$PANES" "$SESSIONS" "$IDX_CORES"
      printf 'shed it — in order of measured effect:\n'
      printf '  1. bin/cc-reaper --watchdog-census    (retire orphaned watchdogs + their panes)\n'
      printf '  2. /handoff the idle sessions          (each closed pane stops being drawn)\n'
      printf '  3. top consumer is %s — if that is iTerm2 or kitty, pane COUNT is the lever;\n' "$TOP_NAME"
      printf '     scripts/iterm2-perf-parity.sh reports which render knobs are still adrift.\n'
      printf '     If it is WindowServer, panes are NOT the lever: that is the whole-desktop\n'
      printf '     compositor — displays and browsers dominate it and shedding panes moves it\n'
      printf '     only 0.002-0.009 cores/pane (02-render.md §2).\n'
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
  echo "    terminal cores:       ${TERM_CORES}   (iTerm2 + kitty — the part panes move)"
  echo "    compositor cores:     ${COMP_CORES}   (WindowServer — SHARED desktop: displays + browser + all clients)"
  echo "  iTerm2 / kitty / WS:    ${ITERM_CPU:-?}% / ${KITTY_CPU:-?}% / ${WS_CPU:-?}%   (top -l 2 second sample)"
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
