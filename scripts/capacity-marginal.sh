#!/bin/bash
# capacity-marginal.sh — measure the MARGINAL load of one ACTIVE session, and refuse to state a
# number that its own controls cannot support.
#
# WHY THIS EXISTS (backlog 193ae8ddce72; DoD docs/research/gc-cpu-vs-session-ceiling-2026-08-18.md
# §5). Marginal load per ACTIVE session is the denominator of every capacity claim in this repo —
# `CC_ADMIT_ACTIVE_CEILING=8`, the felt ~15 wall, MACHINE_CAPACITY_V2's whole model and every
# "+N sessions" projection divide by it. The repo has published FOUR values for it spanning 30x:
#
#     0.172   pooled OLS                  (no committed derivation)
#     0.566   in-band bucket median       (no committed derivation)
#     1.89    (44.4-27.4)/9, a two-point delta-marginal
#     2.5-5   an aggregate/N, i.e. a RATIO, not a marginal at all
#
# and not one of them was produced by an instrument that cleared a control. The DoD names the
# control in one sentence and this file is its implementation:
#
#     "The sampler has to reproduce the load average it apportions. If the census stays flat while
#      load moves, it is the instrument. No attribution figure should be quoted again until a
#      sampler clears that control."
#
# THE CONTROL IS THE PRODUCT. The coefficient is the by-product. This script's contract is that it
# emits a number ONLY when three named controls pass, and that when they do not it says which one
# failed and emits NOTHING quotable. A sampler that always answers is the failure mode the four
# values above already demonstrate.
#
# ══ WHY NOT THE OBVIOUS INSTRUMENT (load1 regressed on session count) ═══════════════════════════
# Because it is not identified on this box, and trunk already measured why:
#   · B3 (docs/research/breaking-the-ceiling-2026-08-19/B3-ambient-load.md §2a) attributed the load
#     numerator four ways across load1 8.35 -> 46.39 IN ONE DAY: Claude sessions and every process
#     they spawn are 12.7% of it; `claude.exe` itself is 4.2%. The confounder is 87.3% of the signal
#     and it moves further than the treatment ever does.
#   · A8 (docs/research/orchestration-units-2026-08-19/A8-marginal-cost.md §6.1) ran the probe
#     anyway and the box load FELL while a unit was added (28.96 -> 26.75; a second run went
#     19.40 -> 35.58 with the probe already dead). "Whole-box Delta-load cannot price one unit."
# So a pooled `load1 ~ N` fit is a regression of a quantity onto 13% of itself against a confounder
# with 3x the variance. It will always return SOMETHING — which is exactly how 0.172 and 0.566 were
# born. This script fits the marginal on the ATTRIBUTED series (Claude-owned runnable processes),
# converts to load units with a ratio the SAME window measures, and reports the naive pooled slope
# beside it, labelled unidentified, so the two can never again be confused for each other.
#
# ══ THE THREE CONTROLS ══════════════════════════════════════════════════════════════════════════
# C1 LEVEL — does the census reproduce the load average it apportions?
#     The load/census ratio is computed in load TERTILES, not once. A ratio fitted at one point is
#     a fudge factor, not a calibration: A8's `x1.553` was a single-point fit and B3 killed it by
#     failing to reproduce it in any of three windows (0.913 / 1.077 / 1.235). PASS requires the
#     tertile ratios to agree within CC_MARG_RATIO_TOL *and* requires the tertiles to actually span
#     different loads — a ratio that "agrees" across three identical loads has reproduced nothing.
#
# C2 DYNAMICS — does the census MOVE when the load moves?
#     corr(load1, total census) over INDEPENDENT observations. This is the control that killed the
#     "64% of the runnable population is our own launchd automation" headline (corr = -0.05, census
#     flat at 19-20 across a 2.3x load range), and it is the one B3 could not clear: its windows
#     were 2.5-4 min against load1's 60 s time constant, i.e. ~2.5 independent observations, so its
#     correlation was uninformative rather than refuting. Hence n_eff, not n: samples closer
#     together than CC_MARG_TAU are not independent evidence about a 60 s moving average, and this
#     script counts them as if they were not.
#
# C3 IDENTIFIABILITY — did the regressor vary at all?
#     A slope needs the active count to move. Fitting one across two levels is the 1.89 defect
#     (a two-point delta reported as a marginal); fitting one across one level is division by zero
#     wearing a decimal point.
#
# ONLY C1 AND C2 AND C3 yields a coefficient. Any failure yields NO-ATTRIBUTION plus the term that
# failed, and exit 1 — a REPORT, never a silent empty answer, because "could not measure" must not
# read as "small".
#
# ══ WHAT IS COUNTED, AND WITH WHICH FIELD ═══════════════════════════════════════════════════════
# ACTIVE sessions come from `cc_sp_active` (scripts/lib/spawn-presence.sh) — the mid-turn census,
# which is the population the box binds on and the one CC_ADMIT_ACTIVE_CEILING is denominated in.
# It is a PROVEN LOWER BOUND, so this coefficient is an upper bound on cost per active session.
#
# RESIDENT sessions are counted by `ps -o comm=` — the EXECUTABLE PATH, never argv. The DoD is
# explicit about this and about why: argv reads 30-33 against a true 15-16, because session briefs
# quote the interpreter path and every brief then counts as a session.
#
# THE CENSUS UNIT IS THE PROCESS, deliberately, and it is recorded in every row. B3 showed the
# THREAD-level census reproduces load better (ratio 0.913 vs the process census's 1.30-1.55), but
# Darwin's per-thread `ps -axM` needs a parser this repo has no captured fixture to test against,
# and shipping an untested parser inside a control is how a control becomes decorative. The process
# census is the instrument A8 ran successfully on this box; C1 measures its ratio rather than
# assuming one, so the coarser unit costs accuracy in the ratio, never validity in the verdict.
# `analyze` REFUSES a file whose rows mix units.
#
# Usage:
#   capacity-marginal.sh sample  [--window-s N] [--interval-s N] [--out FILE]
#   capacity-marginal.sh analyze [--in FILE] [--json]
#   capacity-marginal.sh run     [--out FILE] [--increment-s N] [--max-s N] [--repeat-k N]
#                                [--interval-s N] [--preflight]
#
# `run --preflight` answers only "can THIS box answer the question at all?" and exits — worth the
# two seconds before committing an hour of the box's time to a window that cannot conclude.
#
# `run` is §6 of marginal-load-per-active-session-2026-08-19.md, DRIVEN. That section is a
# protocol, not a command: preflight nothing, sample, analyze, "extend the window until the verdict
# stops being NO-ATTRIBUTION OR the refusal repeats with the same term across several windows —
# which would itself be the finding". Left as prose, the operator is the interpreter of that loop
# for an hour. `run` is the same protocol with the loop inside the program, and it terminates on
# every one of §6's three outcomes with a distinct exit code.
#
# Exit: 0 coefficient emitted (all controls passed) ·
#       1 NO-ATTRIBUTION — a control failed; from `run`, the SAME control refused K windows
#         running, which §6 names as itself the finding (the thread-unit census of §7.3 becomes the
#         next increment, not a nicety) ·
#       2 usage error ·
#       3 NO-DATA (nothing sampled / file unreadable) ·
#       4 run: the max window elapsed with the failing term still moving — inconclusive, extend ·
#       5 run: preflight refused — THIS BOX cannot answer the question (it prints which check).
#
# Seams (all read with an explicit default; none may be empty):
#   CC_MARG_TAU(60)                 load1 time constant, seconds — the independence spacing
#   CC_MARG_MIN_N(20)               minimum INDEPENDENT observations for C2
#   CC_MARG_MIN_R(0.30)             minimum corr(load1, census) for C2
#   CC_MARG_MIN_LOAD_SPREAD(1.5)    max/min load1 the window must span for C1/C2 to mean anything
#   CC_MARG_RATIO_TOL(1.35)         max/min of the tertile load/census ratios allowed by C1
#   CC_MARG_MIN_ACTIVE_SPREAD(2)    max-min of the active count required by C3
#   CC_MARG_MIN_ACTIVE_LEVELS(3)    distinct active levels required by C3
#   CC_MARG_EXEC_RE                 regex matching a session's executable path (comm), default below
#   CC_MARG_OUT                     default sample output path
#   CC_MARG_RUN_INCREMENT_S(900)    `run`: seconds sampled before each re-analysis
#   CC_MARG_RUN_MAX_S(10800)        `run`: total wall clock after which an unstable refusal is
#                                   reported as inconclusive rather than extended again
#   CC_MARG_RUN_REPEAT_K(3)         `run`: identical consecutive refusals that make a refusal STABLE
#   CC_MARG_RUN_MIN_RESIDENT(3)     `run`: sessions the box must be carrying for C3 to be reachable
set -uo pipefail

CC_MARG_TAU="${CC_MARG_TAU:-60}"
CC_MARG_MIN_N="${CC_MARG_MIN_N:-20}"
CC_MARG_MIN_R="${CC_MARG_MIN_R:-0.30}"
CC_MARG_MIN_LOAD_SPREAD="${CC_MARG_MIN_LOAD_SPREAD:-1.5}"
CC_MARG_RATIO_TOL="${CC_MARG_RATIO_TOL:-1.35}"
CC_MARG_MIN_ACTIVE_SPREAD="${CC_MARG_MIN_ACTIVE_SPREAD:-2}"
CC_MARG_MIN_ACTIVE_LEVELS="${CC_MARG_MIN_ACTIVE_LEVELS:-3}"
# Matches the launcher's real executable path. `claude.exe` is the agent/teammate image; the
# `.claude-NNN/node_modules` form is the versioned launcher every interactive session runs.
CC_MARG_EXEC_RE="${CC_MARG_EXEC_RE:-\\.claude-[0-9]+/node_modules/|claude\\.exe$}"
CC_MARG_OUT="${CC_MARG_OUT:-${TMPDIR:-/tmp}/capacity-marginal.tsv}"
CC_MARG_RUN_INCREMENT_S="${CC_MARG_RUN_INCREMENT_S:-900}"
CC_MARG_RUN_MAX_S="${CC_MARG_RUN_MAX_S:-10800}"
CC_MARG_RUN_REPEAT_K="${CC_MARG_RUN_REPEAT_K:-3}"
CC_MARG_RUN_MIN_RESIDENT="${CC_MARG_RUN_MIN_RESIDENT:-3}"

SCHEMA='#ts	load1	unit	total_run	claude_run	active	resident'

die() { printf 'capacity-marginal: %s\n' "$*" >&2; exit 2; }

# ── load1 ───────────────────────────────────────────────────────────────────────────────────────
# Darwin: `sysctl -n vm.loadavg` -> `{ 1.23 4.56 7.89 }`. Linux: /proc/loadavg field 1. Empty on
# neither, and an empty load is dropped by the sampler rather than recorded as 0 — a zero load is a
# measurement, an unreadable one is not.
read_load1() {
  local v=""
  if [ -r /proc/loadavg ]; then
    v="$(awk '{print $1}' /proc/loadavg 2>/dev/null)"
  elif command -v sysctl >/dev/null 2>&1; then
    v="$(sysctl -n vm.loadavg 2>/dev/null | awk '{print $2}')"
  fi
  case "$v" in ''|*[!0-9.]*) return 1 ;; esac
  printf '%s' "$v"
}

# ── the runnable census, attributed ─────────────────────────────────────────────────────────────
# ONE `ps`, four fields. A process counts as runnable when STAT begins R (on-CPU/runnable) or
# D/U (uninterruptible) — the two states the run queue is built from. A process is CLAUDE-OWNED
# when its own comm, or any ancestor's comm, matches CC_MARG_EXEC_RE: the hook forks, `jq` storms
# and MCP servers a session spawns are the session's cost, and B3 measured them at 3x `claude.exe`
# itself, so attributing only the launcher process would undercount by two thirds.
#
# The ancestor walk is bounded (32 hops) — a pid table torn between reads can contain a cycle, and
# an unbounded walk over one hangs the sampler inside a loop with no timeout.
#
# CC_MARG_PS_OVERRIDE names a file standing in for `ps` output. It exists so the ATTRIBUTION can be
# tested against a fixed process table — an ancestor walk that is only ever exercised against the
# live box is a walk nobody has checked, and this one decides two thirds of the numerator.
census_row() { # -> "<total_run> <claude_run> <resident>"
  local ps_out
  if [ -n "${CC_MARG_PS_OVERRIDE:-}" ]; then
    [ -r "$CC_MARG_PS_OVERRIDE" ] || return 1
    ps_out="$(cat "$CC_MARG_PS_OVERRIDE")"
  else
    ps_out="$(ps -axo pid=,ppid=,stat=,comm= 2>/dev/null || ps -eo pid=,ppid=,stat=,comm= 2>/dev/null)" || return 1
  fi
  [ -n "$ps_out" ] || return 1
  printf '%s\n' "$ps_out" | awk -v re="$CC_MARG_EXEC_RE" '
    {
      pid = $1; ppid = $2; st = $3
      cmd = ""
      for (i = 4; i <= NF; i++) cmd = cmd (i > 4 ? " " : "") $i
      par[pid] = ppid; own[pid] = (cmd ~ re) ? 1 : 0
      run[pid] = (st ~ /^[RDU]/) ? 1 : 0
      seen[pid] = 1
      if (own[pid]) resident++
    }
    END {
      for (p in seen) {
        if (!run[p]) continue
        total++
        q = p; hops = 0
        while (q != "" && (q in seen) && hops < 32) {
          if (own[q]) { claude++; break }
          q = par[q]; hops++
        }
      }
      printf "%d %d %d", total + 0, claude + 0, resident + 0
    }'
}

# ── the ACTIVE (mid-turn) census ────────────────────────────────────────────────────────────────
# Sourced from the repo's own library so there is ONE definition of "active" on the box. An
# unavailable or unmeasurable census records `-`, never 0: `analyze` drops those rows from the C3
# and slope arms and says how many it dropped. Manufacturing a 0 here would let a dead sensor look
# like a quiet box, which is the exact failure cc_sp_active's own existence gate exists to refuse.
read_active() {
  local lib v
  lib="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/spawn-presence.sh"
  if [ -r "$lib" ]; then
    # shellcheck source=/dev/null
    . "$lib" 2>/dev/null || { printf '%s' -; return 0; }
    if command -v cc_sp_active >/dev/null 2>&1; then
      v="$(cc_sp_active 2>/dev/null)" || v=""
      case "$v" in ''|*[!0-9]*) v="-" ;; esac
      printf '%s' "$v"; return 0
    fi
  fi
  printf '%s' -
}

cmd_sample() {
  local window=1800 interval="$CC_MARG_TAU" out="$CC_MARG_OUT" quiet=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --window-s)   window="${2:-}"; shift 2 ;;
      --interval-s) interval="${2:-}"; shift 2 ;;
      --out)        out="${2:-}"; shift 2 ;;
      --quiet)      quiet=1; shift ;;
      *) die "sample: unknown argument '$1'" ;;
    esac
  done
  case "$window$interval" in *[!0-9]*) die "sample: --window-s/--interval-s must be integers" ;; esac
  [ "$interval" -ge 1 ] || die "sample: --interval-s must be >= 1"

  [ -s "$out" ] || printf '%s\n' "$SCHEMA" > "$out" || die "sample: cannot write '$out'"

  # THE WINDOW IS A DEADLINE, NOT A COUNT — a sampler that loops N times drifts with its own cost.
  local start now deadline load cen tot cl res n=0
  start="$(date +%s)"; deadline=$(( start + window ))
  [ -n "$quiet" ] || printf 'capacity-marginal: sampling %ss at %ss -> %s\n' "$window" "$interval" "$out" >&2
  while :; do
    now="$(date +%s)"
    [ "$now" -lt "$deadline" ] || break
    if load="$(read_load1)" && cen="$(census_row)"; then
      read -r tot cl res <<<"$cen"
      printf '%s\t%s\tproc\t%s\t%s\t%s\t%s\n' \
        "$now" "$load" "$tot" "$cl" "$(read_active)" "$res" >> "$out"
      n=$(( n + 1 ))
    fi
    now="$(date +%s)"
    [ "$now" -lt "$deadline" ] || break
    sleep "$interval"
  done
  [ -n "$quiet" ] || printf 'capacity-marginal: %d samples\n' "$n" >&2
  [ "$n" -gt 0 ] || return 3
  return 0
}

cmd_analyze() {
  local in="$CC_MARG_OUT" json=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --in)   in="${2:-}"; shift 2 ;;
      --json) json=1; shift ;;
      *) die "analyze: unknown argument '$1'" ;;
    esac
  done
  [ -r "$in" ] || { printf 'CAPACITY-MARGINAL: NO-DATA — cannot read %s\n' "$in"; return 3; }

  awk -F'\t' \
    -v tau="$CC_MARG_TAU" -v minn="$CC_MARG_MIN_N" -v minr="$CC_MARG_MIN_R" \
    -v minspread="$CC_MARG_MIN_LOAD_SPREAD" -v ratiotol="$CC_MARG_RATIO_TOL" \
    -v minas="$CC_MARG_MIN_ACTIVE_SPREAD" -v minal="$CC_MARG_MIN_ACTIVE_LEVELS" \
    -v want_json="$json" '
    function abs(x) { return x < 0 ? -x : x }
    /^#/ { next }
    NF < 7 { malformed++; next }
    {
      ts = $1 + 0; load = $2 + 0; unit = $3; tot = $4 + 0; cl = $5 + 0; act = $6; res = $7 + 0
      if (load <= 0 || tot < 0) { malformed++; next }
      if (units == "") units = unit; else if (units != unit) mixed = 1
      n++
      T[n] = ts; L[n] = load; TOT[n] = tot; CL[n] = cl; RES[n] = res
      if (act ~ /^[0-9]+$/) { A[n] = act + 0; hasA[n] = 1; na++ } else { A[n] = -1; nodrop++ }
    }
    END {
      if (mixed) { print "CAPACITY-MARGINAL: NO-DATA — rows mix census units; refusing to pool them"; exit 3 }
      if (n < 3) { printf "CAPACITY-MARGINAL: NO-DATA — %d usable row(s)%s\n", n, (malformed ? sprintf(" (%d malformed)", malformed) : ""); exit 3 }

      # ── window shape ─────────────────────────────────────────────────────────────────────────
      tmin = T[1]; tmax = T[1]; lmin = L[1]; lmax = L[1]
      for (i = 1; i <= n; i++) {
        if (T[i] < tmin) tmin = T[i]; if (T[i] > tmax) tmax = T[i]
        if (L[i] < lmin) lmin = L[i]; if (L[i] > lmax) lmax = L[i]
      }
      span = tmax - tmin
      # INDEPENDENCE, not sample count: load1 is a 60 s moving average, so two samples 5 s apart are
      # one observation of it read twice. This is precisely the arithmetic that made B3 undecided.
      neff = span / tau + 1
      if (neff > n) neff = n
      lspread = (lmin > 0) ? lmax / lmin : 0

      # ── C1 LEVEL: does the census reproduce the load, at more than one load? ─────────────────
      # Tertiles BY LOAD (not by time): the question is whether the same ratio holds at a quiet
      # box and a busy one, which is what a calibration means and what a fudge factor cannot do.
      for (i = 1; i <= n; i++) idx[i] = i
      for (i = 2; i <= n; i++) { k = idx[i]; j = i - 1
        while (j >= 1 && L[idx[j]] > L[k]) { idx[j+1] = idx[j]; j-- }
        idx[j+1] = k }
      c1_ok = 1; rmin = 0; rmax = 0; tert_desc = ""
      for (g = 0; g < 3; g++) {
        lo = int(g * n / 3) + 1; hi = int((g + 1) * n / 3)
        sl = 0; sc = 0; gn = 0
        for (i = lo; i <= hi; i++) { sl += L[idx[i]]; sc += TOT[idx[i]]; gn++ }
        if (gn == 0 || sc <= 0) { c1_ok = 0; tert_desc = tert_desc (g ? " / " : "") "n-a"; continue }
        r = sl / sc
        tert_desc = tert_desc (g ? " / " : "") sprintf("%.3f", r)
        if (rmin == 0 || r < rmin) rmin = r
        if (r > rmax) rmax = r
      }
      ratio_swing = (rmin > 0) ? rmax / rmin : 0
      if (ratio_swing == 0 || ratio_swing > ratiotol) c1_ok = 0
      # A window that never moved cannot have reproduced anything — C1 is vacuous there, so it FAILS.
      if (lspread < minspread) { c1_ok = 0; c1_why = sprintf("load span %.2fx < %.2fx required", lspread, minspread) }
      else if (!c1_ok) c1_why = sprintf("tertile ratios %s swing %.2fx > %.2fx", tert_desc, ratio_swing, ratiotol)
      else c1_why = sprintf("tertile ratios %s swing %.2fx", tert_desc, ratio_swing)

      # ── C2 DYNAMICS: corr(load1, census) over independent observations ───────────────────────
      sx = 0; sy = 0
      for (i = 1; i <= n; i++) { sx += L[i]; sy += TOT[i] }
      mx = sx / n; my = sy / n
      sxx = 0; syy = 0; sxy = 0
      for (i = 1; i <= n; i++) { dx = L[i] - mx; dy = TOT[i] - my; sxx += dx*dx; syy += dy*dy; sxy += dx*dy }
      rr = (sxx > 0 && syy > 0) ? sxy / sqrt(sxx * syy) : 0
      c2_ok = 1
      if (neff < minn) { c2_ok = 0; c2_why = sprintf("corr %.3f but n_eff %.1f < %d independent observations (span %ds / tau %ds) — uninformative, not refuting", rr, neff, minn, span, tau) }
      else if (syy <= 0) { c2_ok = 0; c2_why = sprintf("census is CONSTANT at %.2f across a %.2fx load range — the instrument, not the box", my, lspread) }
      else if (rr < minr) { c2_ok = 0; c2_why = sprintf("corr(load1, census) = %.3f < %.2f over n_eff %.1f — the census does not track the load it apportions", rr, minr, neff) }
      else c2_why = sprintf("corr(load1, census) = %.3f over n_eff %.1f", rr, neff)

      # ── C3 IDENTIFIABILITY: did the active count move? ───────────────────────────────────────
      amin = -1; amax = -1
      for (i = 1; i <= n; i++) if (hasA[i]) {
        if (amin < 0 || A[i] < amin) amin = A[i]
        if (A[i] > amax) amax = A[i]
        if (!(A[i] in lev)) { lev[A[i]] = 1; levels++ }
      }
      aspread = (amin < 0) ? 0 : amax - amin
      c3_ok = 1
      if (na < 3) { c3_ok = 0; c3_why = sprintf("%d row(s) carry an ACTIVE count (%d unmeasurable)", na, nodrop) }
      else if (levels < minal || aspread < minas) { c3_ok = 0; c3_why = sprintf("active spans %d..%d over %d level(s) — need spread >= %d across >= %d levels", amin, amax, levels, minas, minal) }
      else c3_why = sprintf("active spans %d..%d over %d levels, %d rows", amin, amax, levels, na)

      # ── the coefficient, and the naive one it replaces ───────────────────────────────────────
      # Fit on the ATTRIBUTED series, then convert with the ratio THIS window measured.
      ratio = (sy > 0) ? sx / sy : 0
      bx = 0; by = 0; bn = 0
      for (i = 1; i <= n; i++) if (hasA[i]) { bx += A[i]; by += CL[i]; bn++ }
      slope = 0; se = 0; naive = 0
      if (bn >= 3) {
        mbx = bx / bn; mby = by / bn
        bxx = 0; byy = 0; bxy = 0
        for (i = 1; i <= n; i++) if (hasA[i]) { dx = A[i] - mbx; dy = CL[i] - mby; bxx += dx*dx; byy += dy*dy; bxy += dx*dy }
        if (bxx > 0) {
          slope = (bxy / bxx) * ratio
          resid = byy - (bxy * bxy) / bxx
          if (resid < 0) resid = 0
          if (bn > 2) se = sqrt(resid / (bn - 2) / bxx) * ratio
        }
        # the pooled load1 ~ active fit: what 0.172 and 0.566 are, kept only to be labelled
        nxx = 0; nxy = 0; mnl = 0
        for (i = 1; i <= n; i++) if (hasA[i]) mnl += L[i]
        mnl = mnl / bn
        for (i = 1; i <= n; i++) if (hasA[i]) { dx = A[i] - mbx; nxx += dx*dx; nxy += dx * (L[i] - mnl) }
        if (nxx > 0) naive = nxy / nxx
      }

      pass = (c1_ok && c2_ok && c3_ok)
      if (want_json) {
        printf "{\"n\":%d,\"n_eff\":%.2f,\"span_s\":%d,\"unit\":\"%s\",\"load_min\":%.2f,\"load_max\":%.2f,", n, neff, span, units, lmin, lmax
        printf "\"c1_level\":%s,\"c1_why\":\"%s\",\"c2_dynamics\":%s,\"c2_why\":\"%s\",\"c3_identify\":%s,\"c3_why\":\"%s\",", (c1_ok?"true":"false"), c1_why, (c2_ok?"true":"false"), c2_why, (c3_ok?"true":"false"), c3_why
        printf "\"ratio\":%.4f,\"naive_slope\":%.4f,", ratio, naive
        if (pass) printf "\"verdict\":\"MARGINAL\",\"marginal_load_per_active_session\":%.4f,\"se\":%.4f}\n", slope, se
        else      printf "\"verdict\":\"NO-ATTRIBUTION\"}\n"
        exit (pass ? 0 : 1)
      }
      printf "CAPACITY-MARGINAL  n=%d  n_eff=%.1f  span=%ds  unit=%s  load1 %.2f..%.2f (%.2fx)\n", n, neff, span, units, lmin, lmax, lspread
      printf "  C1 LEVEL      %-4s  %s\n", (c1_ok ? "PASS" : "FAIL"), c1_why
      printf "  C2 DYNAMICS   %-4s  %s\n", (c2_ok ? "PASS" : "FAIL"), c2_why
      printf "  C3 IDENTIFY   %-4s  %s\n", (c3_ok ? "PASS" : "FAIL"), c3_why
      if (pass) {
        printf "VERDICT: MARGINAL %.3f load units per ACTIVE session  (+/- %.3f, 1 s.e.; ratio %.3f load/runnable-%s)\n", slope, se, ratio, units
        printf "  for contrast, the pooled load1~active fit this replaces: %.3f  [UNIDENTIFIED — 87%% of the numerator is not Claude]\n", naive
        exit 0
      }
      print  "VERDICT: NO-ATTRIBUTION — a control failed; no coefficient is quotable from this window."
      printf "  (the fit that WOULD have been reported: %.3f load units per ACTIVE session — withheld)\n", slope
      exit 1
    }' "$in"
}

# ── run: §6's protocol, with the loop inside the program ────────────────────────────────────────
# WHY PREFLIGHT EXISTS, AND WHY IT IS THE POINT OF THIS SUBCOMMAND. A triple-FAIL from a box that
# has no fleet is textually identical to a triple-FAIL from the 10-core box during a dispatch wave,
# and only the second one is a finding. That is not hypothetical: §6a of the adjudication doc
# records exactly such an off-box smoke run — `C1 FAIL / C2 FAIL / C3 FAIL / NO-ATTRIBUTION` — and
# it means nothing about capacity. So `run` refuses to start where the answer is structurally
# unreachable, rather than spending an hour producing a refusal about itself.
#
# The two checks are the two ways C3 can be unreachable no matter how long the window runs:
#   · the ACTIVE sensor is blind — cc_sp_active reads `-`, so EVERY row is blind and C3 fails on
#     "0 row(s) carry an ACTIVE count" (the shape tests/capacity-marginal.bats already pins);
#   · the box carries fewer sessions than C3 needs levels — C3 wants the ACTIVE count at
#     >= CC_MARG_MIN_ACTIVE_LEVELS distinct levels with spread >= CC_MARG_MIN_ACTIVE_SPREAD, and a
#     fleet smaller than that cannot produce those levels even in principle.
#
# It deliberately does NOT gate on `uname` being Darwin. The sampler reads /proc/loadavg on Linux
# and vm.loadavg on Darwin, and the thing that decides whether this box can answer is the fleet and
# the sensor, not the kernel. A uname gate would be a check on the spelling of the box.
run_preflight() {
  local cen tot cl res act
  if ! cen="$(census_row)"; then
    printf 'PREFLIGHT FAIL  census — ps returned nothing; this box cannot be sampled at all.\n'
    return 1
  fi
  read -r tot cl res <<<"$cen"
  act="${CC_MARG_RUN_ACTIVE_OVERRIDE:-$(read_active)}"
  case "$act" in
    ''|*[!0-9]*)
      printf 'PREFLIGHT FAIL  active — cc_sp_active is unmeasurable here (it reads as a dash), so\n'
      printf '                would be blind and C3 IDENTIFY can never pass. Fix the sensor, not\n'
      printf '                the window: scripts/lib/spawn-presence.sh must be sourceable and its\n'
      printf '                beat directory readable by this user.\n'
      return 1 ;;
  esac
  if [ "$res" -lt "$CC_MARG_RUN_MIN_RESIDENT" ]; then
    printf 'PREFLIGHT FAIL  fleet — %d resident session(s), need >= %d. C3 needs the ACTIVE count\n' \
      "$res" "$CC_MARG_RUN_MIN_RESIDENT"
    printf '                at %s distinct levels; a fleet this small cannot reach them however\n' \
      "$CC_MARG_MIN_ACTIVE_LEVELS"
    printf '                long the window runs. Run this ON the box, during a dispatch wave.\n'
    return 1
  fi
  printf 'PREFLIGHT PASS  %d resident session(s), %d ACTIVE now, %d/%d runnable procs are ours.\n' \
    "$res" "$act" "$cl" "$tot"
  return 0
}

# THE DECISION, AS A PURE FUNCTION. Extracted so §6's stopping rule can be tested without sampling
# anything — this suite's own header forbids a gate test that depends on how busy the operator is,
# and a loop tested only against the live box is a loop nobody has checked.
#   run_decide <analyze_rc> <sig> <prev_sig> <streak> <elapsed_s> <max_s> <k>  ->  "<verdict> <streak>"
# rc 3 reaching here is already adjudicated TERMINAL by the caller (a file that mixes census units,
# or one that cannot be read); the transient "too few rows yet" form never gets this far.
run_decide() {
  local rc="$1" sig="$2" prev="$3" streak="$4" elapsed="$5" max="$6" k="$7" now
  case "$rc" in
    0) printf 'PASS %d' "$streak"; return 0 ;;
    3) printf 'NO-DATA %d' "$streak"; return 0 ;;
  esac
  if [ "$sig" = "$prev" ]; then now=$(( streak + 1 )); else now=1; fi
  if [ "$now" -ge "$k" ];        then printf 'STABLE %d' "$now"; return 0; fi
  if [ "$elapsed" -ge "$max" ];  then printf 'INCONCLUSIVE %d' "$now"; return 0; fi
  printf 'CONTINUE %d' "$now"
}

# On a PASS the remaining edits are RE-GREPPED, never listed. The 2026-08-26 ban pass found THREE
# live citation sites where the doc named two, and the one it missed was the library that defines
# the ACTIVE population the coefficient is denominated in. A hard-coded path list here would ship
# that same defect a second time.
#
# THE SELF-PATH MUST BE RESOLVED FIRST, and this hand-off is exactly where an unresolved one would
# bite. ~/.claude/scripts/ is a tree of per-file SYMLINKS into the checkout, so through the live
# layer `dirname "$0"/..` is ~/.claude — no docs/, no .git, no repo. The grep below would then match
# nothing and print an empty list, silently, on the one path the operator actually runs: a hand-off
# that says "no sites remain" when three do. Canonical loop, matching _resolve_self in
# scripts/ship-land.sh (no `readlink -f` — GNU-only, and the target box is BSD).
_marg_resolve_self() {
  local p="$1" d
  while [ -L "$p" ]; do
    d="$(cd "$(dirname "$p")" && pwd)"
    p="$(readlink "$p")"
    case "$p" in /*) ;; *) p="$d/$p" ;; esac
  done
  printf '%s/%s\n' "$(cd "$(dirname "$p")" && pwd)" "$(basename "$p")"
}

# $1 is this script's own path, passed in rather than read from BASH_SOURCE inside: BASH_SOURCE
# cannot be assigned in a subshell, so a self-read here could only ever be exercised on the path it
# is already on, and the symlink resolution above would be untestable.
run_next_steps() { # <self path>
  local self repo hits
  self="$(_marg_resolve_self "$1")" || return 0
  repo="$(cd "$(dirname "$self")/.." && pwd)" || return 0
  printf '\nNEXT — quote the coefficient WITH its standard error and its window, then update every\n'
  printf 'live site that still points at this adjudication (re-grepped just now, not listed):\n'
  # The sampler and its own suite name that doc as their provenance, not as a citation of a value,
  # so they are excluded by name — otherwise this file lists itself and the operator's edit list
  # opens with a false positive.
  hits="$(cd "$repo" && grep -rl 'marginal-load-per-active-session-2026-08-19' \
      --exclude-dir=.git --exclude-dir=docs --exclude='capacity-marginal.*' . 2>/dev/null \
      | sed 's|^\./|  |')"
  # An EMPTY result is reported as unknown, never as "none". Zero hits here means either that the
  # ban really is discharged or that the root above is wrong, and those two must never render alike.
  if [ -n "$hits" ]; then
    printf '%s\n' "$hits"
  else
    printf '  (no live citation site found under %s — verify that root before reading this as none)\n' "$repo"
  fi
  printf '  docs/research/marginal-load-per-active-session-2026-08-19.md   (record the run: §6)\n'
  printf 'Then land it and close the item:  cc-backlog done 193ae8ddce72 --evidence "<landed sha>"\n'
}

cmd_run() {
  local out="$CC_MARG_OUT" inc="$CC_MARG_RUN_INCREMENT_S" max="$CC_MARG_RUN_MAX_S"
  local k="$CC_MARG_RUN_REPEAT_K" interval="$CC_MARG_TAU" only_preflight=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --out)         out="${2:-}"; shift 2 ;;
      --increment-s) inc="${2:-}"; shift 2 ;;
      --max-s)       max="${2:-}"; shift 2 ;;
      --repeat-k)    k="${2:-}"; shift 2 ;;
      --interval-s)  interval="${2:-}"; shift 2 ;;
      --preflight)   only_preflight=1; shift ;;
      *) die "run: unknown argument '$1'" ;;
    esac
  done
  case "$inc$max$k$interval" in *[!0-9]*) die "run: --increment-s/--max-s/--repeat-k/--interval-s must be integers" ;; esac
  [ "$inc" -ge 1 ] || die "run: --increment-s must be >= 1"
  [ "$k" -ge 1 ]   || die "run: --repeat-k must be >= 1"
  [ "$max" -ge "$inc" ] || die "run: --max-s must be >= --increment-s"

  run_preflight || return 5
  [ -z "$only_preflight" ] || return 0

  local start now elapsed rc aout sig prev="" streak=0 decision iter=0
  start="$(date +%s)"
  while :; do
    iter=$(( iter + 1 ))
    cmd_sample --window-s "$inc" --interval-s "$interval" --out "$out" --quiet
    rc=$?
    if [ "$rc" -eq 3 ]; then
      printf 'CAPACITY-MARGINAL: NO-DATA — window %d recorded no rows; load1 or ps is unreadable.\n' "$iter"
      return 3
    fi
    aout="$(cmd_analyze --in "$out")"; rc=$?
    now="$(date +%s)"; elapsed=$(( now - start ))

    # NO-DATA splits, and conflating the halves is how a young window gets reported as a verdict.
    # "rows mix census units" and an unreadable file are TERMINAL — more sampling cannot unmix a
    # file. "N usable row(s)" is the opposite: it says the window is younger than the 3 rows the
    # estimator needs, which is exactly what the next increment fixes.
    if [ "$rc" -eq 3 ]; then
      case "$aout" in
        *'mix census units'*|*'cannot read'*) printf '%s\n' "$aout"; return 3 ;;
      esac
      if [ "$elapsed" -ge "$max" ]; then printf '%s\n' "$aout"; return 3; fi
      printf 'capacity-marginal: window %d (%ds elapsed) too few rows yet — extending\n' \
        "$iter" "$elapsed" >&2
      continue
    fi

    sig="$(printf '%s\n' "$aout" | awk '$1 ~ /^C[123]$/ && $3 == "FAIL" { printf "%s%s", (n++ ? "+" : ""), $1 }')"
    [ -n "$sig" ] || sig="-"
    read -r decision streak <<<"$(run_decide "$rc" "$sig" "$prev" "$streak" "$elapsed" "$max" "$k")"
    prev="$sig"
    case "$decision" in
      PASS)
        printf '%s\n' "$aout"; run_next_steps "${BASH_SOURCE[0]:-$0}"; return 0 ;;
      NO-DATA)
        printf '%s\n' "$aout"; return 3 ;;
      STABLE)
        printf '%s\n' "$aout"
        printf '\nSTABLE REFUSAL — %s refused %d consecutive windows over %ds. Per §6 this IS the\n' "$sig" "$streak" "$elapsed"
        printf 'finding, not a failed run: the process-unit census is not the instrument for this box,\n'
        printf 'and the thread-unit census of §7.3 becomes the next increment. It wants a captured\n'
        printf 'ps -axM fixture before its parser can be tested — capture one from THIS box.\n'
        return 1 ;;
      INCONCLUSIVE)
        printf '%s\n' "$aout"
        printf '\nINCONCLUSIVE — %ds elapsed (max %ds) and the failing term is still moving (now %s).\n' "$elapsed" "$max" "$sig"
        printf 'Nothing is quotable and nothing is concluded. Re-run with the same --out to extend the\n'
        printf 'window; the file accumulates and analyze re-reads all of it.\n'
        return 4 ;;
      *)
        printf 'capacity-marginal: window %d (%ds elapsed) NO-ATTRIBUTION [%s] — extending\n' \
          "$iter" "$elapsed" "$sig" >&2 ;;
    esac
  done
}

case "${1:-}" in
  sample)  shift; cmd_sample "$@" ;;
  analyze) shift; cmd_analyze "$@" ;;
  run)     shift; cmd_run "$@" ;;
  -h|--help|'') sed -n '/^# Usage:/,/^#       5 run: preflight/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 2 ;;
  *) die "unknown subcommand '$1' (sample | analyze | run)" ;;
esac
