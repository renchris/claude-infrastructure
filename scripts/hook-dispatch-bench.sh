#!/usr/bin/env bash
# hook-dispatch-bench.sh — does SERIALISING a session's hook chain actually cut occupancy?
#
# ── WHY THIS EXISTS, AND WHY WALL-CLOCK COULD NOT ANSWER IT ────────────────────────────────────
# CONCURRENCY_PROGRAM.md §S6.4 (Phase B) prescribes: "Serialise each session's hooks (one at a
# time) rather than shrinking their count — per S6.1 the count is not the variable." That lever
# rests on two claims, and until this script neither was measured:
#
#   1. That Claude Code dispatches a matcher group's hooks CONCURRENTLY today. Established
#      independently 2026-08-09 — see docs/research/active-session-occupancy-2026-08-09.md §2 for
#      the live process sample, corroborated by the static bundle read at
#      docs/research/goal-in-handoff-2026-08-08.md:439 (`uL` @237793 maps every resolved hook to a
#      concurrent async generator). HOOK_CHAIN_COST.md:396-399 had named this "Unresolved, and
#      named as unresolved" — every per-hook timing in this repo was taken by invoking the hook
#      DIRECTLY, outside the harness, so none of them observes the harness's own scheduling.
#
#   2. That serialising the dispatch REDUCES load. This is the claim this script exists to test,
#      and it is NOT obvious — it is very nearly false on the arithmetic:
#
# ⚠ THE FIRST-ORDER TERM CANCELS. READ THIS BEFORE QUOTING ANY NUMBER BELOW.
#   load = the time-average of the runnable-thread count, so an event's contribution to it is
#   ∫(runnable) dt = the SUM over member processes of the time each spends runnable. Running ten
#   members at once for d ms contributes 10*d thread-ms; running them one at a time for 10*d ms
#   contributes 10*d thread-ms. IDENTICAL. Serialisation cannot win on the first-order term, and a
#   bench that reported a win there would be measuring its own error.
#
#   The entire effect is SECOND-ORDER, and it is a queueing effect: a process waiting in the run
#   queue is in state R. It accrues runnable-time while doing NO work. So once the box is
#   oversubscribed, each member's runnable-time inflates by roughly the oversubscription factor,
#   and the sum inflates with it. Serialising cuts the instantaneous oversubscription, which
#   deflates every member's R-time — a win that exists ONLY in the contended regime.
#
#   That is exactly what §S6.1's cross-over already implies, read carefully: 2,376 forks/s at
#   concurrency 4 adds +1.6 load, while 1,255 forks/s at concurrency 16 adds +17.5. Rate DOWN 1.9x,
#   load UP 11x ⇒ cost-per-fork rose ~21x between concurrency 4 and 16. That 21x IS the inflation
#   term, measured on this box, and it is the whole prize.
#
#   hooks/hook-chain.sh:41-46 reached the same conclusion from the other side and stopped there:
#   "the collapse's benefit is proportional to cost-per-fork, which is O(load), so it only pays in
#   the high-load regime it exists to prevent — and therefore cannot be validated by measurement at
#   normal load." It was right that WALL-CLOCK at normal load cannot adjudicate it. The error was
#   concluding the question was unmeasurable: sweep the concurrency instead of holding it at
#   whatever the box happened to be doing, and the cross-over is directly observable.
#
# ── WHAT IS MEASURED ───────────────────────────────────────────────────────────────────────────
# Metric = RUNNABLE-THREAD-SECONDS PER DISPATCH, not per second and not wall-clock. Equal-work
# comparison is mandatory here: the serial arm takes longer per dispatch, so at a fixed time budget
# it completes fewer dispatches and would post a lower load for having done less. Dividing by
# completed dispatches removes that, and a bench that omitted it would manufacture the result the
# wave was hoping for (the trap idle-slope-sweep.sh:148-158 records against itself).
#
# Three arms, CYCLED not blocked — IDLE, SERIAL, PARALLEL, repeated. Ambient load on this box swings
# 2x at constant session count (MACHINE_CAPACITY_V2 §8.5.7) and drifted enough during wave A's sweep
# to INVERT its slope, so arms must be interleaved to be comparable at all; cross-run comparison is
# invalid by this repo's own standing rule (hook-chain-bench.sh trap 3). IDLE is carried through the
# cycle as the ambient baseline, so each cycle yields its own attributable deltas.
#
# ── THE NULL CONTROL ───────────────────────────────────────────────────────────────────────────
# --control runs SERIAL against SERIAL under the identical harness. It must report a delta
# indistinguishable from zero. A rig that cannot report "no difference" cannot report a difference
# either, and this one is measuring a second-order effect on a noisy box — precisely where a
# credulous rig invents an answer. The control is not optional decoration: run it whenever a
# headline number is going to be quoted.
#
# ── WHAT IT DOES NOT DO ────────────────────────────────────────────────────────────────────────
# It NEVER executes a real hook. Members are synthetic and calibrated to the measured chain profile
# (--profile). Running the live PreToolUse/Bash chain here would fire six safety gates against a
# fabricated payload and write to their real state — the bench would perturb the box it measures,
# and a `waiting-recycle` arming a watcher mid-run is not a hypothetical.
#
# FIXED WINDOW, COUNTED WORK — not fixed work in an unbounded window. Each arm runs for exactly
# CC_HDB_SECONDS while the probe samples it, and the dispatches COMPLETED in that window are
# counted. The alternative (run a fixed dispatch count, probe for a fixed time) cannot make the two
# windows coincide: a fast arm finishes early and the probe then averages its idle tail into
# mean_runnable, which flatters precisely the arm that did the work fastest.
#
# Seams: CC_HDB_SESSIONS · CC_HDB_MEMBERS · CC_HDB_CYCLES · CC_HDB_SECONDS · CC_HDB_PROFILE
#        CC_HDB_MAX_PROCS (fork-bomb bound) · CC_HDB_MAX_START_LOAD
# Exits: 0 completed · 64 usage · 3 could not measure · 4 refused (box too loaded / bound exceeded)
set -uo pipefail

# Resolve $0 through its symlinks BEFORE deriving the root: ~/.claude/scripts/ are per-file symlinks
# into the checkout, so `dirname "$0"/..` through the LIVE path is ~/.claude — no tests/, no docs/.
# Canonical loop from scripts/ship-land.sh `_resolve_self` (no `readlink -f`: GNU-only, box is BSD).
_self="${BASH_SOURCE[0]}"
while [ -L "$_self" ]; do
  _d="$(cd "$(dirname "$_self")" && pwd)"; _self="$(readlink "$_self")"
  case "$_self" in /*) ;; *) _self="$_d/$_self" ;; esac
done
REPO="$(cd "$(dirname "$_self")/.." && pwd)"
PROBE="$REPO/scripts/occupancy-probe.sh"

SESSIONS="${CC_HDB_SESSIONS:-6}"
MEMBERS="${CC_HDB_MEMBERS:-10}"
CYCLES="${CC_HDB_CYCLES:-3}"
WINDOW_S="${CC_HDB_SECONDS:-6}"
PROFILE="${CC_HDB_PROFILE:-git}"
MAX_PROCS="${CC_HDB_MAX_PROCS:-160}"
MAX_START_LOAD="${CC_HDB_MAX_START_LOAD:-14}"
CONTROL=0
ANALYSE=""
OUT=""

usage() {
  sed -n '2,/^set -uo/p' "$0" | sed 's/^# \{0,1\}//; /^set -uo/d'
  exit 0
}

die64() { printf 'hook-dispatch-bench.sh: %s\n' "$1" >&2; exit 64; }

while [ $# -gt 0 ]; do
  case "$1" in
    --sessions)    SESSIONS="${2:-}"; shift 2 ;;
    --members)     MEMBERS="${2:-}"; shift 2 ;;
    --cycles)      CYCLES="${2:-}"; shift 2 ;;
    --seconds)     WINDOW_S="${2:-}"; shift 2 ;;
    --profile)     PROFILE="${2:-}"; shift 2 ;;
    --control)     CONTROL=1; shift ;;
    --analyse)     ANALYSE="${2:-}"; shift 2 ;;
    --out)         OUT="${2:-}"; shift 2 ;;
    -h|--help)     usage ;;
    *)             die64 "unknown arg '$1'" ;;
  esac
done

for pair in "SESSIONS:$SESSIONS" "MEMBERS:$MEMBERS" "CYCLES:$CYCLES" "SECONDS:$WINDOW_S"; do
  n="${pair#*:}"; k="${pair%%:*}"
  case "$n" in ''|*[!0-9]*) die64 "$k must be a positive integer (got \"$n\")" ;; esac
  [ "$n" -gt 0 ] || die64 "$k must be a positive integer (got \"$n\")"
done
case "$PROFILE" in git|cached|noop) ;; *) die64 "--profile must be git|cached|noop (got \"$PROFILE\")" ;; esac

# ── VERDICT ────────────────────────────────────────────────────────────────────────────────────
# Per CYCLE, the attributable occupancy of an arm is (meanR - meanR_idle) * wall / dispatches. The
# idle row is subtracted INSIDE the cycle it was measured in, never against a run-level average —
# that is the correction wave A's sweep lacked, and the reason its slope came out negative.
#
# Separated from the run so it can be re-read later (--analyse) and, more importantly, so its
# arithmetic is testable without a live box. An unrunnable verdict is an unverifiable one.
verdict() { # <results-tsv> <load-start> <load-end>
awk -F'\t' -v ctrl="$CONTROL" -v armb="$ARM_B" -v ls="$2" -v le="$3" '
  { meanR[$1"/"$2]=$3; bucket[$1"/"$2]=$4; wall[$1"/"$2]=$5; disp[$1"/"$2]=$6; cyc[$1]=1 }
  END {
    n=0
    for (c in cyc) {
      is=meanR[c"/idle"]; s=meanR[c"/serial"]; b=meanR[c"/" armb]
      if (is=="" || s=="" || b=="") continue
      ds = (s-is)*wall[c"/serial"]/disp[c"/serial"]
      db = (b-is)*wall[c"/" armb]/disp[c"/" armb]
      n++; S[n]=ds; B[n]=db
      idle[n]=is
    }
    if (n < 2) {
      printf "  VERDICT: not computed — %d usable cycle(s). One cycle is one draw from a 2x-swinging\n", n
      printf "           ambient; it cannot separate an effect from the swing. Re-run with >= 2 cycles.\n"
      exit 0
    }
    # PER-CYCLE RATIOS, then the MEDIAN — not the ratio of the means. One cycle contaminated by a
    # burst from a sibling moves a mean without bound; it moves a median by at most one rank. The spread
    # is printed beside it because a median over a wide spread is a point estimate with no power,
    # and hiding that is how a noisy rig comes to look decisive.
    lo=hi=idle[1]; m=0
    for (i=1;i<=n;i++) {
      if (idle[i]<lo) lo=idle[i]; if (idle[i]>hi) hi=idle[i]
      if (S[i] > 0.0000001) { m++; R[m]=B[i]/S[i] }
      ms += S[i]; mb += B[i]
    }
    ms/=n; mb/=n
    for (i=1;i<=m;i++) for (j=i+1;j<=m;j++) if (R[j]<R[i]) { t=R[i]; R[i]=R[j]; R[j]=t }
    med = (m==0) ? 0 : ((m%2) ? R[int((m+1)/2)] : (R[m/2]+R[m/2+1])/2)

    printf "  ATTRIBUTABLE OCCUPANCY (runnable-thread-seconds per dispatch, ambient subtracted per cycle)\n"
    printf "    serial      %10.5f   (mean over %d cycles)\n", ms, n
    printf "    %-10s  %10.5f\n", armb, mb
    if (m > 0) {
      printf "    per-cycle %s/serial ratios:", armb
      for (i=1;i<=m;i++) printf " %.2f", R[i]
      printf "\n    MEDIAN RATIO = %.2fx   (spread %.2f..%.2f over %d cycles)\n", med, R[1], R[m], m
    }

    # ── ACCEPTANCE ──────────────────────────────────────────────────────────────────────────
    # The rig certifies itself or it does not. A control that reports a ratio it cannot justify
    # must SAY so; a live run whose control was never seen is not evidence.
    spread_bad = (m >= 2 && R[1] > 0.0000001 && R[m]/R[1] > 2.5)
    if (ctrl) {
      printf "\n  NULL CONTROL: both arms dispatch SERIALLY; only the results key differs.\n"
      if (med < 0.80 || med > 1.25)
        printf "  ⛔ CONTROL FAILED — median %.2fx, and a null must sit at 1.00x. The rig is BIASED,\n     not merely noisy: one arm is being measured differently from the other. Do NOT quote\n     a live run taken under this ambient.\n", med
      else if (spread_bad)
        printf "  ⛔ CONTROL FAILED ON SPREAD — the median is %.2fx (correct), but the per-cycle ratios\n     run %.2f..%.2f, so the noise floor here is wider than most effects worth finding.\n     It is UNBIASED and UNDERPOWERED. A live median is quotable only if its own spread\n     clears this band; say so explicitly rather than quoting the number bare.\n", med, R[1], R[m]
      else
        printf "  ✅ CONTROL PASSED — median %.2fx, spread %.2f..%.2f. A live run under this ambient\n     is quotable.\n", med, R[1], R[m]
    } else if (spread_bad) {
      printf "\n  ⚠ SPREAD %.2f..%.2f exceeds 2.5x — the median is a point estimate with little power\n    here. Re-run quieter, or with more cycles, before quoting it.\n", R[1], R[m]
    }

    # AMBIENT drift is the idle arm across cycles — NOT load1 start-vs-end, which this bench
    # moves by construction (it is the load). Checking the latter would fire on every healthy run.
    printf "\n  ambient (idle arm) %.3f..%.3f runnable over %d cycles", lo, hi, n
    if (lo > 0.0000001 && hi/lo > 2.0)
      printf "\n  ⚠ AMBIENT MOVED >2x BETWEEN CYCLES — the per-cycle subtraction handles drift between\n    cycles but not within one. Treat the ratio as indicative and re-run when the box is quieter."
    printf "\n  load1 %s -> %s (this bench generates the delta; not a drift signal)\n", ls, le
  }
' "$1"
}

if [ -n "$ANALYSE" ]; then
  [ -r "$ANALYSE" ] || die64 "--analyse: cannot read '$ANALYSE'"
  ARM_B="${CC_HDB_ARMB:-parallel}"; [ "$CONTROL" -eq 1 ] && ARM_B="serial-b"
  verdict "$ANALYSE" "n/a" "n/a"
  exit 0
fi

[ -x "$PROBE" ] || { printf 'hook-dispatch-bench.sh: occupancy-probe.sh not executable at %s\n' "$PROBE" >&2; exit 4; }

# ── FORK-BOMB BOUND. The parallel arm holds SESSIONS*MEMBERS processes at once by construction;
# that IS the quantity under test, so it cannot be throttled, only refused. A bench for a capacity
# ceiling must not be the thing that breaches it — §S6.5's crash wall is a 736-proc wave.
PEAK=$((SESSIONS * MEMBERS))
if [ "$PEAK" -gt "$MAX_PROCS" ]; then
  printf 'hook-dispatch-bench.sh: REFUSED — parallel arm would hold %s processes (%s sessions x %s members), over the %s bound.\n' \
    "$PEAK" "$SESSIONS" "$MEMBERS" "$MAX_PROCS" >&2
  printf '  Raise CC_HDB_MAX_PROCS deliberately, or lower --sessions/--members.\n' >&2
  exit 4
fi

load_now() { sysctl -n vm.loadavg 2>/dev/null | tr -d '{}' | awk '{print $1}'; }
LOAD_START="$(load_now)"
[ -n "$LOAD_START" ] || { echo 'hook-dispatch-bench.sh: cannot read vm.loadavg — no verdict' >&2; exit 3; }
if awk -v a="$LOAD_START" -v b="$MAX_START_LOAD" 'BEGIN{exit !(a>b)}'; then
  printf 'hook-dispatch-bench.sh: REFUSED — load1 %s exceeds the %s start floor. A second-order effect is not resolvable above it.\n' \
    "$LOAD_START" "$MAX_START_LOAD" >&2
  exit 4
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/hdb.XXXXXX")" || { echo 'hook-dispatch-bench.sh: mktemp failed' >&2; exit 3; }
# BSD mktemp takes only TRAILING Xs (memory: prescribed-remedy-worse-than-the-bug) — the template
# above is correct for this box; a mid-string X would mint a CONSTANT name.
cleanup() { [ -n "${WORK:-}" ] && rm -rf "$WORK"; }
trap cleanup EXIT TERM INT HUP

# ── THE SYNTHETIC MEMBER ───────────────────────────────────────────────────────────────────────
# Its basename is what occupancy-probe.sh buckets on (command position, never argv substring), so
# it is deliberately distinctive: `hdb-member.sh` cannot collide with an ambient process, which is
# what makes the per-bucket figure attributable rather than merely correlated.
MEMBER="$WORK/hdb-member.sh"
case "$PROFILE" in
  git)    BODY='git rev-parse --show-toplevel >/dev/null 2>&1; git rev-parse --abbrev-ref HEAD >/dev/null 2>&1' ;;
  cached) BODY='read -r _a < "$CACHE" 2>/dev/null; read -r _b < "$CACHE" 2>/dev/null' ;;
  noop)   BODY=':' ;;
esac
cat > "$MEMBER" <<EOF
#!/bin/bash
# synthetic hook member — profile=$PROFILE. Never a real hook; see hook-dispatch-bench.sh header.
CACHE="\$1"
$BODY
EOF
chmod +x "$MEMBER"
printf 'refs/heads/bench\nclean\n' > "$WORK/cache"

# One dispatch = one hook EVENT: MEMBERS members, launched the way the arm says.
dispatch_parallel() { local _m; for _m in $(seq "$MEMBERS"); do : "$_m"; "$MEMBER" "$WORK/cache" & done; wait; }
dispatch_serial()   { local _m; for _m in $(seq "$MEMBERS"); do : "$_m"; "$MEMBER" "$WORK/cache"; done; }

# One simulated session: dispatch events back to back until the stop flag appears, counting
# COMPLETED dispatches. A dispatch in flight when the flag lands is NOT counted — counting it would
# credit an arm with work whose occupancy the window only partly saw, and the parallel arm (longer
# in-flight tail) would collect the bigger unearned credit.
session_loop() { # <arm> <counter-file>
  local arm="$1" cf="$2" n=0
  while [ ! -f "$WORK/stop" ]; do
    if [ "$arm" = parallel ]; then dispatch_parallel; else dispatch_serial; fi
    n=$((n + 1))
  done
  printf '%s\n' "$n" > "$cf"
}

# ── ONE ARM ────────────────────────────────────────────────────────────────────────────────────
# Runs SESSIONS concurrent session loops while the probe samples, and reports
#   mean_runnable · member-bucket occupancy · wall · completed dispatches
# The probe is started FIRST and outlives the work, so the window brackets it.
run_arm() { # <mode: idle|serial|parallel> <tag>   (the results KEY is the caller's label)
  local arm="$1" tag="$2" pids=() s out total=0 cf

  rm -f "$WORK/stop" "$WORK"/count.*
  if [ "$arm" != idle ]; then
    for s in $(seq "$SESSIONS"); do
      cf="$WORK/count.$s"
      session_loop "$arm" "$cf" & pids+=("$!")
    done
  fi
  # The probe defines the window. --hz 4 so a ~7 ms member is not systematically missed; 2 Hz would
  # sample the gaps as often as the members and understate both arms — unequally, because the arms
  # have different gap structure, which is the one bias a ratio cannot survive.
  out="$("$PROBE" --hz 4 --seconds "$WINDOW_S" --json --label "$tag" 2>/dev/null)"
  touch "$WORK/stop"
  if [ "$arm" != idle ]; then
    wait "${pids[@]}" 2>/dev/null
    for s in $(seq "$SESSIONS"); do
      [ -r "$WORK/count.$s" ] && total=$((total + $(cat "$WORK/count.$s")))
    done
  fi

  [ -n "$out" ] || { echo "BLIND"; return 1; }
  # wall IS the probe window by construction — the whole point of fixed-window/counted-work.
  printf '%s\t%s\t%s\n' "$out" "$WINDOW_S" "$total"
}

jfield() { # <json> <key>  — numeric field, no jq fork in the hot path
  printf '%s' "$1" | sed -n "s/.*\"$2\":\([-0-9.]*\).*/\1/p"
}
jtop() { # <json> — the NAME of the heaviest bucket. Diagnostic, not attribution.
  # occupancy-probe.sh emits buckets already sorted by count desc, so the first key is the top one.
  # This is deliberately not "the member bucket": a member that forks `git` parks most of its
  # runnable time in the `git` bucket, so a per-member figure would read ~0 and be mistaken for
  # "the bench did nothing". Attribution is carried by the per-cycle idle subtraction instead.
  printf '%s' "$1" | sed -n 's/.*"buckets":{"\([^"]*\)".*/\1/p' | head -1
}

# MODE is what the arm DOES; LABEL is how it is keyed. They differ only under --control,
# and keeping them equal there is exactly what made the control vacuous.
ARM_B_MODE="parallel"; ARM_B="parallel"
if [ "$CONTROL" -eq 1 ]; then ARM_B_MODE="serial"; ARM_B="serial-b"; fi

printf '─── hook dispatch bench ───\n'
printf '  sessions=%s members=%s window=%ss profile=%s cycles=%s%s\n' \
  "$SESSIONS" "$MEMBERS" "$WINDOW_S" "$PROFILE" "$CYCLES" \
  "$([ "$CONTROL" -eq 1 ] && printf '  [NULL CONTROL: serial vs serial]')"
printf '  peak parallel processes = %s   load1 at start = %s   ncpu = %s\n\n' \
  "$PEAK" "$LOAD_START" "$(sysctl -n hw.ncpu 2>/dev/null || echo '?')"
printf '  %-6s %-9s %9s %8s %7s %12s  %s\n' cycle arm meanR wall disp 'R-s/dispatch' 'top holder'

RESULTS="$WORK/results"
: > "$RESULTS"
for c in $(seq "$CYCLES"); do
  for arm in idle serial "$ARM_B"; do
    mode="$arm"; [ "$arm" = "$ARM_B" ] && mode="$ARM_B_MODE"
    row="$(run_arm "$mode" "c${c}-${arm}")" || { printf '  %-6s %-9s %s\n' "$c" "$arm" 'BLIND — probe returned nothing'; continue; }
    json="${row%%$'\t'*}"; rest="${row#*$'\t'}"; wall="${rest%%$'\t'*}"; disp="${rest##*$'\t'}"
    meanR="$(jfield "$json" mean_runnable)"; top="$(jtop "$json")"; top="${top:-?}"
    rsd="$(awk -v m="$meanR" -v w="$wall" -v d="$disp" 'BEGIN{ if (d+0==0) printf "—"; else printf "%.5f", m*w/d }')"
    printf '  %-6s %-9s %9s %8s %7s %12s  %s\n' "$c" "$arm" "$meanR" "$wall" "$disp" "$rsd" "$top"
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$c" "$arm" "$meanR" "$top" "$wall" "$disp" >> "$RESULTS"
  done
done

LOAD_END="$(load_now)"
if [ -n "$OUT" ]; then
  cp "$RESULTS" "$OUT" 2>/dev/null \
    && printf '  results: %s   (re-read with --analyse %s)\n' "$OUT" "$OUT" \
    || printf '  results: could not write %s\n' "$OUT" >&2
fi
printf '\n'
verdict "$RESULTS" "$LOAD_START" "$LOAD_END"


exit 0
