#!/bin/bash
# unit-segment-cost.sh — what ONE orchestration unit costs in VM-compressor SEGMENTS.
#
# ── THE GAP THIS CLOSES ────────────────────────────────────────────────────────────────────────
# docs/research/orchestration-units-2026-08-19.md §5 ranks the memory wall at
# `26.6 GB ÷ ~375 MB = ~70 sessions` and, in the SAME cell, names the failure mode correctly:
# *"Swap 0.00 MB — the failure mode is compressor exhaustion / watchdog panic, not OOM"*. Those two
# sentences do not compose. The number divides RESIDENT BYTES by RESIDENT BYTES; the failure mode is
# a SEGMENT-DESCRIPTOR table, whose ceiling this box has hit four times at only ~28–33% mean segment
# fill with ~20 GB free and `memoryPressure` reading False. A ranking computed in the wrong resource
# cannot be repaired by re-reading it more carefully — the denominator has to change.
# (Z-completeness-critic.md G3: *"Per-unit segment cost is UNMEASURED for every one of the seven
# units in §2, so the wall with four incidents behind it has no number and no rank."*)
#
# ── WHY A NEW SCRIPT AND NOT A RUNG ON THE SENTINEL ────────────────────────────────────────────
# scripts/compressor-sentinel.sh already computes this box's segment occupancy every 10 s, and
# scripts/lib/capacity-admit.sh already exposes it as a function. Neither can answer THIS question,
# for one structural reason: **the meter is global.** `c_segment_count` is a machine-wide pool, so
# no single read can attribute a segment to a unit. The only instrument that reads descriptors
# per-owner is `zprint`, and it HANGS under the very storm it measures (§7.7 — banned from every hot
# path, this one included). So a per-unit number can only ever be a DIFFERENTIAL, and a differential
# needs a harness that owns the baseline. That is all this file is.
#
# THE ARITHMETIC IS NOT RE-IMPLEMENTED HERE. It is sourced from scripts/lib/capacity-admit.sh
# (`cc_hw_compressor_segment_pct`), which is the same §7.7 recipe the sentinel runs and which
# tests/capacity-admit-active.bats case 06 already pins against the sentinel's own arithmetic over a
# shared fixture. A fourth copy of `in-core = pages / (buf/pgsz)` is how one subject's tuning becomes
# another's regression; there are three readers of vm_stat in this tree already and that is the cap.
#
# ── THE ONE DESIGN DECISION THAT DECIDES WHETHER THIS INSTRUMENT IS WORTH ANYTHING ─────────────
# The same document REFUTES the naive form of this measurement. §6 N9 — *"Watch `uptime` / fork rate
# to price one unit"* — is marked REFUTED WITH DATA: during a probe the box load FELL (28.96 → 26.75
# → 25.81), and **"the paired arrival differential failed independently for two agents (Δ never
# returned to baseline; drift > signal)"**. A before/after subtraction on a live box measures the
# box's mood, not the unit, and it does so while LOOKING like a measurement.
#
# So the drift is not a caveat here, it is a TERM. Every run spends its first window measuring how
# far this box moves on its own, and the unit's Δ is reported only when it clears that band:
#
#     band = max( baseline peak-to-trough span , observed drift rate × the run's own elapsed )
#     |Δ| ≤ band  ⇒  verdict INDETERMINATE, and the number is WITHHELD, not printed with a caveat
#
# A withheld number is the point. N9's differential did not fail loudly — it produced values. An
# instrument that cannot say "the box moved more than the unit did" will publish drift as a cost.
#
# ── PEAK AND RETAINED ARE DIFFERENT NUMBERS AND BOTH ARE REPORTED ──────────────────────────────
# Segments are reclaimed, so an endpoint delta undercounts the occupancy a unit actually held — and
# §6 N5 measures the other half: a *finished* bg job held 217.8/207.4/225.2 MB and 18–19 threads two
# minutes after reporting `state:"done"`, with residency flat at ONE HOUR. So `peak` (what the unit
# held against the limit at its worst — the number the ceiling cares about) and `retained` (what it
# still holds after the settle window — the number a fleet's steady state cares about) are separate
# fields. Collapsing them would answer the capacity question with the leak number or vice versa.
#
# ── RATES DIVIDE BY MEASURED ELAPSED, NEVER BY THE CONFIGURED INTERVAL ─────────────────────────
# Inherited verbatim from the sentinel's header, for the same reason: under the storm this subject
# exists inside, a 2 s sleep takes far longer, and dividing a stretched delta by the nominal interval
# manufactures a rate out of an unchanged machine.
#
# ── FAILURE IS VISIBLE, NEVER ZERO ─────────────────────────────────────────────────────────────
# An unreadable probe aborts the run with `verdict:"SKIP"` and a `blind` field naming the sysctl that
# would not answer. It never renders as 0.00%, and it never renders as a cost of zero. That is the
# exact defect capacity-alarm.sh ate on its launchd PATH (a dead rung reporting the healthy value)
# and the reason the sentinel skips a tick rather than emitting a row.
#
# ── USAGE ──────────────────────────────────────────────────────────────────────────────────────
#   unit-segment-cost.sh sample [--human]
#       One read. The composable form — the critic's prescription is *"two 30-second reads around
#       waves that are going to run anyway"*, and this is that read.
#
#   unit-segment-cost.sh watch --label <unit> --units <n> [--duration <s>] [-- <cmd> ...]
#       Baseline window → the unit's lifetime (the command's, or --duration) → settle window → ONE
#       cost row. With `-- <cmd>` the window is the command's own runtime; with --duration it is a
#       fixed wall-clock window, which is the form to use when the wave is fired by hand elsewhere.
#
# Exit: 0 a row was emitted (including INDETERMINATE — that IS a result) · 3 the machine could not be
# read at all · 64 usage.
#
# Seams: CC_USC_SYSCTL · CC_USC_INTERVAL (2) · CC_USC_BASELINE_S (30) · CC_USC_SETTLE_S (60) ·
#        CC_USC_CEILING_PCT (50, capacity-admit's own) · CC_USC_LOG · CC_USC_LIB
set -uo pipefail

INTERVAL="${CC_USC_INTERVAL:-2}"
BASELINE_S="${CC_USC_BASELINE_S:-30}"
# 60 s, matching the sentinel's COOLDOWN by construction rather than by taste. N5 measures residency
# at one hour, so this window does NOT claim to see a unit fully released; it claims to see what is
# still held one minute after the unit reported done, which is the number a wave-planner needs.
SETTLE_S="${CC_USC_SETTLE_S:-60}"
CEILING_PCT="${CC_USC_CEILING_PCT:-50}"
LOG="${CC_USC_LOG:-$HOME/.claude/logs/unit-segment-cost.jsonl}"

usage() {
  sed -n 's/^# \{0,1\}//p' "$0" | sed -n '/^── USAGE/,/^Exit:/p'
  exit 64
}
die_usage() { printf 'unit-segment-cost.sh: %s\n' "$1" >&2; exit 64; }

# ── the instrument ────────────────────────────────────────────────────────────────────────────
# Sourced, never copied. See the header: the §7.7 arithmetic has exactly one implementation per
# INSTRUMENT class in this tree, and this file is a consumer, not a fourth instrument.
LIB="${CC_USC_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/capacity-admit.sh}"
[ -r "$LIB" ] || { printf 'unit-segment-cost.sh: cannot read %s\n' "$LIB" >&2; exit 3; }
# shellcheck source=/dev/null
. "$LIB"

# The sysctl binary is resolved ABSOLUTELY for the reason capacity-admit.sh:155 records with a
# measurement: /usr/sbin is absent from a launchd PATH, and 222 of 239 capacity rows once read
# `unreadable` because the bare name never resolved.
SYSCTL="$(cc_hw_resolve_sysctl "${CC_USC_SYSCTL:-}")"

# → "<pct> <segs> <limit>" on stdout, or rc 1 and NOTHING. No fallback, by contract.
read_segs() { cc_hw_compressor_segment_pct "$SYSCTL"; }

now_s() { date +%s 2>/dev/null || echo 0; }

json_str() { printf '%s' "${1:-}" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

emit() { # <the JSON body, already assembled>
  printf '%s\n' "$1"
  if [ -n "$LOG" ]; then
    mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
    printf '%s\n' "$1" >> "$LOG" 2>/dev/null || true
  fi
}

blind_exit() { # <what could not be read>
  emit "$(printf '{"ts":"%s","verdict":"SKIP","blind":"%s"}' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(json_str "$1")")"
  exit 3
}

# ── sample ────────────────────────────────────────────────────────────────────────────────────
cmd_sample() {
  local human=0 row pct segs lim
  while [ $# -gt 0 ]; do
    case "$1" in
      --human) human=1; shift ;;
      -h|--help) usage ;;
      *) die_usage "unknown option '$1'" ;;
    esac
  done
  row="$(read_segs)" || blind_exit "vm.compressor_segment_limit / vm.compressor_segment_buffer_size / vm.swapusage / vm_stat"
  pct="${row%% *}"; lim="${row##* }"; segs="$(printf '%s' "$row" | awk '{print $2}')"
  if [ "$human" -eq 1 ]; then
    printf 'segments %s of %s (%s%%)\n' "$segs" "$lim" "$pct"
    return 0
  fi
  emit "$(printf '{"ts":"%s","verdict":"SAMPLE","seg_pct":%s,"segs":%s,"seg_limit":%s}' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$pct" "$segs" "$lim")"
}

# ── watch ─────────────────────────────────────────────────────────────────────────────────────
# Samples into two parallel space-separated accumulators (bash 3.2 — no arrays needed, and awk is
# the only arithmetic in this file anyway).
SAMPLES=""   # segment counts, in order
STAMPS=""    # the measured epoch second of each, in order

collect() { # <until-epoch> — samples until the deadline; rc 1 the moment the box goes unreadable
  local until="$1" row t
  while :; do
    t="$(now_s)"
    [ "$t" -ge "$until" ] && return 0
    row="$(read_segs)" || return 1
    SAMPLES="$SAMPLES $(printf '%s' "$row" | awk '{print $2}')"
    STAMPS="$STAMPS $t"
    sleep "$INTERVAL"
  done
}

collect_while_running() { # <pid> — samples until the child exits, then returns
  local pid="$1" row t
  while kill -0 "$pid" 2>/dev/null; do
    t="$(now_s)"
    row="$(read_segs)" || return 1
    SAMPLES="$SAMPLES $(printf '%s' "$row" | awk '{print $2}')"
    STAMPS="$STAMPS $t"
    sleep "$INTERVAL"
  done
  return 0
}

# The drift band, and the whole reason this file is not N9 again. Returns
# "<mean> <min> <max> <span> <maxrate>" over the sample/stamp window it is given.
#
# `maxrate` is the LARGEST per-second movement between two adjacent baseline samples, not the mean:
# the band has to bound the worst the box did on its own, because a single burst inside the unit's
# window is exactly what would otherwise be attributed to the unit. A pair whose measured elapsed is
# 0 s contributes no rate — dividing by it would manufacture an infinite one.
window_stats() { # <samples> <stamps>
  awk -v s="$1" -v t="$2" 'BEGIN {
    n = split(s, S, " "); m = split(t, T, " ")
    k = 0
    for (i = 1; i <= n; i++) if (S[i] != "") { k++; V[k] = S[i] + 0 }
    j = 0
    for (i = 1; i <= m; i++) if (T[i] != "") { j++; W[j] = T[i] + 0 }
    if (k == 0 || k != j) exit 1
    mn = V[1]; mx = V[1]; sum = 0; rate = 0
    for (i = 1; i <= k; i++) {
      sum += V[i]
      if (V[i] < mn) mn = V[i]
      if (V[i] > mx) mx = V[i]
      if (i > 1) {
        dt = W[i] - W[i - 1]
        if (dt > 0) { r = (V[i] - V[i - 1]) / dt; if (r < 0) r = -r; if (r > rate) rate = r }
      }
    }
    printf "%.2f %d %d %d %.4f", sum / k, mn, mx, mx - mn, rate
  }'
}

cmd_watch() {
  local label="" units="" duration="" have_cmd=0
  local CMD=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --label)    [ $# -ge 2 ] || die_usage "--label needs a value"; label="$2"; shift 2 ;;
      --units)    [ $# -ge 2 ] || die_usage "--units needs a value"; units="$2"; shift 2 ;;
      --duration) [ $# -ge 2 ] || die_usage "--duration needs a value"; duration="$2"; shift 2 ;;
      -h|--help)  usage ;;
      --)         shift; have_cmd=1; CMD=("$@"); break ;;
      *)          die_usage "unknown option '$1'" ;;
    esac
  done
  [ -n "$label" ] || die_usage "--label is required (the unit being priced)"
  cc_hw_is_int "$units" && [ "$units" -gt 0 ] || die_usage "--units must be a positive integer"
  if [ "$have_cmd" -eq 1 ]; then
    [ "${#CMD[@]}" -gt 0 ] || die_usage "-- needs a command after it"
  else
    cc_hw_is_int "$duration" && [ "$duration" -gt 0 ] \
      || die_usage "give either --duration <s> or -- <cmd>"
  fi

  local t0 base_stats base_mean base_span base_rate base_elapsed
  t0="$(now_s)"

  # 1. BASELINE — the box's own movement, measured before the unit exists.
  collect "$((t0 + BASELINE_S))" || blind_exit "segment probe unreadable during the baseline window"
  base_elapsed="$(( $(now_s) - t0 ))"
  [ "$base_elapsed" -gt 0 ] || base_elapsed=1
  base_stats="$(window_stats "$SAMPLES" "$STAMPS")" \
    || blind_exit "baseline window produced no usable samples"
  base_mean="$(printf '%s' "$base_stats" | awk '{print $1}')"
  base_span="$(printf '%s' "$base_stats" | awk '{print $4}')"
  base_rate="$(printf '%s' "$base_stats" | awk '{print $5}')"

  # 2. THE UNIT'S LIFETIME. Both forms sample on the same cadence; only the stopping rule differs.
  SAMPLES=""; STAMPS=""
  local rc=0 child_rc=0 t_run_start t_run_end
  t_run_start="$(now_s)"
  if [ "$have_cmd" -eq 1 ]; then
    "${CMD[@]}" & local child=$!
    collect_while_running "$child" || rc=1
    wait "$child" 2>/dev/null; child_rc=$?
  else
    collect "$((t_run_start + duration))" || rc=1
  fi
  [ "$rc" -eq 0 ] || blind_exit "segment probe went unreadable during the unit's lifetime"
  t_run_end="$(now_s)"

  # 3. SETTLE — what is still held after the unit reports done (N5: residency is an hour, flat).
  local run_stats peak
  run_stats="$(window_stats "$SAMPLES" "$STAMPS")" \
    || blind_exit "the unit's window produced no usable samples"
  peak="$(printf '%s' "$run_stats" | awk '{print $3}')"

  SAMPLES=""; STAMPS=""
  collect "$(( $(now_s) + SETTLE_S ))" || blind_exit "segment probe went unreadable during the settle window"
  local settle_stats retained_abs settle_peak
  settle_stats="$(window_stats "$SAMPLES" "$STAMPS")" \
    || blind_exit "settle window produced no usable samples"
  retained_abs="$(printf '%s' "$settle_stats" | awk '{print $1}')"
  # THE PEAK SPANS BOTH WINDOWS, and that is physics, not tidiness: compression LAGS the allocation
  # that causes it, so a unit's worst segment occupancy routinely lands after the unit itself has
  # exited. Taking the peak from the run window alone produced `retained > peak` on the very first
  # fixture that moved the meter — an incoherent row, and the incoherence was the instrument's, not
  # the box's.
  settle_peak="$(printf '%s' "$settle_stats" | awk '{print $3}')"
  peak="$(awk -v a="$peak" -v b="$settle_peak" 'BEGIN { print (b > a ? b : a) }')"

  local row lim
  row="$(read_segs)" || blind_exit "final segment read"
  lim="${row##* }"

  # 4. THE VERDICT. Everything above is arithmetic; this is the judgment, and it is the one the
  # header argues for: the band is what the box could have done to itself over the same wall-clock,
  # and a delta inside it is NOT a cost — it is drift wearing a cost's clothes.
  emit "$(awk \
      -v ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      -v label="$(json_str "$label")" -v units="$units" -v lim="$lim" \
      -v bmean="$base_mean" -v bspan="$base_span" -v brate="$base_rate" \
      -v peak="$peak" -v ret="$retained_abs" \
      -v elapsed="$(( t_run_end - t_run_start + SETTLE_S ))" -v ceil="$CEILING_PCT" \
      -v belapsed="$base_elapsed" -v crc="$child_rc" 'BEGIN {
    dpeak = peak - bmean
    dret  = ret  - bmean

    # THE UNOBSERVED-DRIFT FLOOR. A baseline that saw NO movement has not measured this box to be
    # still. It has established only that the box drifts slower than the meter can resolve over the
    # window it watched: under one segment in `belapsed` seconds. Taking that as rate 0 makes the
    # band 0, and a band of 0 promotes any single-segment blip to MEASURED. That is precisely the
    # failure this file exists to refuse, arriving through the back door of a QUIET box rather than
    # a noisy one, so the floor is one segment over the window the baseline actually watched.
    rate = brate
    floor_rate = 1 / belapsed
    if (floor_rate > rate) rate = floor_rate
    band = bspan
    if (rate * elapsed > band) band = rate * elapsed
    apeak = (dpeak < 0) ? -dpeak : dpeak
    verdict = (apeak > band) ? "MEASURED" : "INDETERMINATE"

    printf "{\"ts\":\"%s\",\"verdict\":\"%s\",\"label\":\"%s\",\"units\":%d", ts, verdict, label, units
    printf ",\"seg_limit\":%d,\"baseline_segs\":%.2f,\"baseline_span\":%d,\"baseline_rate_per_s\":%.4f", \
           lim, bmean, bspan, brate
    printf ",\"peak_segs\":%d,\"elapsed_s\":%d,\"drift_band_segs\":%.2f", peak, elapsed, band
    printf ",\"delta_peak_segs\":%.2f,\"delta_retained_segs\":%.2f", dpeak, dret
    if (verdict == "MEASURED" && units > 0) {
      pu   = dpeak / units
      pur  = dret  / units
      printf ",\"per_unit_peak_segs\":%.2f,\"per_unit_retained_segs\":%.2f", pu, pur
      printf ",\"per_unit_peak_pct\":%.4f", 100 * pu / lim
      if (pu > 0) printf ",\"wall_units_at_%d_pct\":%d", ceil, int((ceil / 100 * lim) / pu)
    } else if (verdict == "INDETERMINATE") {
      # WITHHELD, not caveated. See the header: N9 failed by publishing a number, not by refusing to.
      printf ",\"per_unit_peak_segs\":null,\"why\":\"delta within the baseline drift band\""
    }
    if (crc != 0) printf ",\"child_rc\":%d", crc
    printf "}\n"
  }')"
}

# ── entry ─────────────────────────────────────────────────────────────────────────────────────
[ $# -ge 1 ] || usage
VERB="$1"; shift
case "$VERB" in
  sample) cmd_sample "$@" ;;
  watch)  cmd_watch  "$@" ;;
  -h|--help) usage ;;
  *) die_usage "unknown verb '$VERB' (sample | watch)" ;;
esac
