#!/bin/bash
# session-load-marginal.sh — derive MARGINAL load per ACTIVE session, with a control that can fail.
#
# WHY THIS EXISTS (backlog 193ae8ddce72; DoD docs/research/gc-cpu-vs-session-ceiling-2026-08-18.md §5).
# This number is the DENOMINATOR of every capacity claim in the repo — `CC_ADMIT_ACTIVE_CEILING=8`,
# the felt ~15 wall, MACHINE_CAPACITY_V2's whole model and every "+N sessions" projection all divide
# by it. The wave that filed this item produced FOUR values spanning 30x, and each one is wrong in a
# NAMED way rather than merely imprecise:
#
#   0.172   pooled OLS of load1 on session count, over LEVELS. Attenuated to near-zero because the
#           regressor explains almost none of the outcome's variance: at a CONSTANT N=15-16 this box
#           read 11.21 / 19.06 / 27.26 / 29.67 / 32.14 / 36.07. A level regression charges that
#           +-8 swing to the residual and shrinks the slope toward 0.
#   0.566   in-band bucket median. Same confound, less power.
#   1.89    (44.4-27.4)/9 across nine sessions arriving together. The right KIND of estimator — a
#           difference — but n=1 pair, nine sessions at once, and no drift arm. The wave's own log
#           records one instrumentation run moving load 19 -> 36 with session count UNCHANGED, which
#           is larger than the entire quantity being estimated.
#   2.5-5   published in scripts/lib/spawn-presence.sh's header. An aggregate/N, not a marginal at
#           all (the repo's own `[Ratio != marginal]` defect).
#
# So the spread is not four noisy reads of one quantity. It is four DIFFERENT estimators, three of
# which cannot identify a marginal even in principle. Averaging them would be meaningless; picking
# one would be arbitrary. The number has to be re-derived by an estimator that can identify it.
#
# ══ THE ESTIMATOR: FIRST-DIFFERENCE OLS, NOT A LEVEL REGRESSION ═══════════════════════════════════
#
#     d_load = alpha + beta * d_census + e        over consecutive samples
#
# `beta` is the marginal; `alpha` is per-interval DRIFT — everything on this box that moves load
# without a session moving (Spotlight, mediaanalysisd, the TUI renderer, the fork storm, thermal).
#
# WHY DIFFERENCING IS THE WHOLE FIX. Levels ask "do busy moments have more sessions?", which on this
# box is dominated by confounders that vary on their own clock. Differences ask "when the census
# moved by one, did load move?" — identification is LOCAL to the transition, so any confounder that
# is slow relative to the sampling interval differences out. This is exactly why 0.172 and 1.89 can
# both be honest arithmetic over the same machine: they are answering different questions.
#
# WHY THE INTERCEPT IS LOAD-BEARING AND NOT DECORATION. The intervals where the census did NOT move
# are the drift arm. Without them, `beta` absorbs whatever the box was doing anyway — which is
# precisely how 1.89 was produced. Fitting `alpha` on the d_census==0 rows and `beta` on the
# transitions IS a difference-in-differences; OLS with an intercept is that estimator written
# compactly, and it extends to +-k transitions for free.
#
# WHY THE SAMPLES ARE NATURAL ARRIVALS AND NOT A STAGED EXPERIMENT. The DoD's sketch was a babysat
# two-arm run: hold a quiet window, fire ONE session, sample. That is one pair per sitting, and it
# needs N>=5 pairs at DIFFERENT baselines to say anything — days of supervised work, which is why
# the measurement has never happened. A recorder sampling the fleet at a fixed cadence harvests the
# same transitions for free, at every baseline the box naturally visits, and the analysis arm can be
# re-run over the accumulated series as often as one likes. Staged and natural transitions estimate
# the same beta; only the natural one is affordable.
#
# ══ THE TWO CENSUSES, RECORDED SIDE BY SIDE — because ACTIVE and RESIDENT are different quantities ═
#
#   active   cc_sp_active()  — the MID-TURN population, from the session beat's own `kind`. This is
#                              the item's estimand ("per ACTIVE session") and the population the
#                              admit gate binds on.
#   trees    cc_sp_trees()   — the RESIDENT population, matched at the COMMAND POSITION of argv.
#
# BOTH come from scripts/lib/spawn-presence.sh rather than being re-implemented here, and that reuse
# is not tidiness: that file's header records THREE measured census defects (a `pgrep -cf` that read
# 0 against 8 real sessions; two disjoint launch spellings whose intersection is zero, so the fleet
# is their SUM; and matching anywhere in argv reading 83 against a true 60 because wrappers merely
# NAME the binary). A fresh census here would re-commit all three by default. It also satisfies the
# DoD's "count by executable path, never argv" requirement in the only way that actually works on
# Darwin: `cc_sp_trees` matches the command position only, which is what the DoD's own one-liner was
# reaching for when it noted argv reads 30-33 against a true 15-16 because briefs mention the path.
#
# `active` is a PROVEN LOWER BOUND by construction (spawn-presence's own header: a session in a long
# turn correctly does not beat, and the busiest are the quietest). Under-counting the census BIASES
# BETA UPWARD — a real transition recorded as no transition lands in the drift arm — so a `beta`
# from this instrument is an UPPER bound on the truth. That direction is stated here because a
# ceiling derived from an upper-bounded cost is conservative, which is the safe direction for a gate,
# and because an unstated bias direction is how an estimate becomes a fact.
#
# ══ THE CONTROL THAT MUST BE ABLE TO FAIL ═════════════════════════════════════════════════════════
#
# The DoD states the acceptance criterion verbatim: "the sampler has to reproduce the load average it
# apportions. If the census stays flat while load moves, it is the instrument — which is exactly how
# this wave's '64% is our own automation' headline died. No attribution figure should be quoted again
# until a sampler clears that control."
#
# That is TWO distinct checks, and conflating them is what makes a control unfalsifiable:
#
#   C1  THE CENSUS MUST MOVE (the dead-instrument control).  A census flat at 19-20 across a 2.3x
#       load range cannot apportion anything; every figure computed from it is an artifact of the
#       arithmetic, not a reading of the box. FAILING C1 IS `BLIND`, AND UNDER `BLIND` NO MARGINAL
#       IS PRINTED AT ALL — not a wide one, not a zero. This is the arm that had to be able to fail,
#       and selftest case C1-FAIL replays the dead headline's own shape to prove it does.
#
#   C2  THE CENSUS SHOULD EXPLAIN (the correlation check).  r(load1, census) over the LEVEL series.
#       Reported always; it is NOT a gate, and the distinction is deliberate rather than lenient. A
#       census that MOVES while load does not follow is a RESULT (beta is small), not a blindness —
#       and treating it as a failure would make the control unable to return "sessions are cheap",
#       i.e. it could only ever confirm the hypothesis. Levels are also the wrong scale for it: this
#       box's level-r is attenuated by the same confounders that produced 0.172, which is why C2
#       failing while the first-difference fit is significant is a coherent state and is reported as
#       such (`census-moves-load-does-not` vs `census-flat`).
#
# ══ THE VERDICTS — four, never a boolean; "could not measure" must not read as a measurement ═══════
#   MEASURED      C1 passed, enough transitions at enough baselines, CI narrow enough to discriminate
#                 at least one incumbent value.                                            exit 0
#   INCONCLUSIVE  C1 passed, but too few transitions / too few distinct baselines / CI too wide to
#                 separate any of the incumbents. Prints the achieved half-width AND the n it would
#                 take — an inconclusive run must say what would end it.                   exit 1
#   BLIND         C1 FAILED. The census does not move while load does. No figure is emitted.  exit 2
#   NO-DATA       series absent/unreadable, or the probes could not be read at all.        exit 3
#
# ══ USAGE ═════════════════════════════════════════════════════════════════════════════════════════
#   session-load-marginal.sh sample            append ONE row to the series (cheap; for a timer)
#   session-load-marginal.sh analyze [--json]  fit the model over the series, emit a verdict
#   session-load-marginal.sh selftest          executable controls, including the failable C1
#
# SEAMS (every threshold; tuning must never need a code edit):
#   CC_MLOAD_SERIES          series path              (default ~/.claude/logs/session-load-marginal.jsonl)
#   CC_MLOAD_DT_MIN/MAX      admissible gap between consecutive samples, seconds  (30 / 300)
#   CC_MLOAD_KMAX            largest |d_census| kept in the fit                   (2)
#   CC_MLOAD_MIN_TRANS       minimum transitions required                         (5)
#   CC_MLOAD_MIN_BASELINES   minimum distinct baseline buckets                    (3)
#   CC_MLOAD_CTRL_LOAD_SD    load sd above which C1 is armed at all               (1.0)
#   CC_MLOAD_CTRL_CENSUS_SD  census sd below which C1 FAILS                       (0.30)
#   CC_MLOAD_TARGET_HALFW    half-width that counts as decisive                   (0.20)
#   CC_MLOAD_SYSCTL          explicit sysctl binary (Darwin)
#   CC_MLOAD_LOAD1_OVERRIDE  explicit load1 (testing)
#   CC_MLOAD_NCPU_OVERRIDE   explicit core count (testing)
#   CC_MLOAD_PRESENCE_LIB    explicit path to scripts/lib/spawn-presence.sh
set -uo pipefail

CC_MLOAD_SERIES="${CC_MLOAD_SERIES:-$HOME/.claude/logs/session-load-marginal.jsonl}"
CC_MLOAD_DT_MIN="${CC_MLOAD_DT_MIN:-30}"
CC_MLOAD_DT_MAX="${CC_MLOAD_DT_MAX:-300}"
CC_MLOAD_KMAX="${CC_MLOAD_KMAX:-2}"
CC_MLOAD_MIN_TRANS="${CC_MLOAD_MIN_TRANS:-5}"
CC_MLOAD_MIN_BASELINES="${CC_MLOAD_MIN_BASELINES:-3}"
CC_MLOAD_CTRL_LOAD_SD="${CC_MLOAD_CTRL_LOAD_SD:-1.0}"
CC_MLOAD_CTRL_CENSUS_SD="${CC_MLOAD_CTRL_CENSUS_SD:-0.30}"
CC_MLOAD_TARGET_HALFW="${CC_MLOAD_TARGET_HALFW:-0.20}"

# ── probes ────────────────────────────────────────────────────────────────────────────────────────
# Every probe swallows its own failure and returns an EMPTY STRING, never a non-zero status. A row
# with an unreadable field must reach the series as a recorded gap the analyzer skips, never as a
# zero that the fit would read as a real measurement — capacity-alarm's NO-DATA rule, same reason:
# "could not measure" and "measured zero" are different facts and must not share a representation.

_ml_sysctl() {
  if [ -n "${CC_MLOAD_SYSCTL:-}" ]; then printf '%s' "$CC_MLOAD_SYSCTL"; return 0; fi
  if [ -x /usr/sbin/sysctl ]; then printf '%s' /usr/sbin/sysctl; else printf '%s' sysctl; fi
}

# THE LOAD PROBE IS PER-PLATFORM AND DARWIN IS THE SUBJECT. The fleet is a 10-core Darwin box; the
# Linux arm exists so the suite runs on CI and so the analyzer is exercisable off-target. `vm.loadavg`
# renders as `{ 1.23 4.56 7.89 }`, so field 2 is the 1-minute average; /proc/loadavg puts it first.
# THE 1-MINUTE AVERAGE, not the 5- or 15-: a sampler differencing a 15-minute EWMA is reading an
# average whose window is longer than the interval it is trying to attribute a transition to, which
# would smear every transition across the following fifteen samples (capacity-alarm rung 7's reason,
# arriving here for a sharper one — we difference, so a lagged input biases beta toward zero).
#
# BOTH PROBES TAKE AN EXPLICIT OVERRIDE, honoured VERBATIM and never folded into the fallback chain
# (spawn-presence.sh's rule, same reason): /proc/loadavg cannot be stubbed through PATH, so without
# this seam the recorder would be untestable on the platform the suite runs on — and an untestable
# term is one that rots.
_ml_load1() {
  if [ -n "${CC_MLOAD_LOAD1_OVERRIDE:-}" ]; then printf '%s' "$CC_MLOAD_LOAD1_OVERRIDE"; return 0; fi
  if [ -r /proc/loadavg ]; then awk '{print $1}' /proc/loadavg 2>/dev/null || true; return 0; fi
  "$(_ml_sysctl)" -n vm.loadavg 2>/dev/null | awk '{print $2}' || true
}

_ml_ncpu() {
  if [ -n "${CC_MLOAD_NCPU_OVERRIDE:-}" ]; then printf '%s' "$CC_MLOAD_NCPU_OVERRIDE"; return 0; fi
  if command -v nproc >/dev/null 2>&1; then nproc 2>/dev/null || true; return 0; fi
  "$(_ml_sysctl)" -n hw.ncpu 2>/dev/null || true
}

# The two censuses come from the library. It is sourced DEFENSIVELY and its absence is a NO-DATA, not
# a zero: a missing library reading back as an empty fleet is the "positive control on the
# denominator" defect spawn-presence.sh's own header found and pinned.
#
# RESOLUTION ORDER IS spawn-presence.sh's OWN, and it is not copied for symmetry. Everything under
# ~/.claude/scripts/ is a directory of PER-FILE SYMLINKS into this checkout, so for an invocation
# through the live layer `dirname "$0"` is ~/.claude/scripts and a repo-relative reach can land in a
# tree with no lib/ at all (self-path-lint's three incidents). BASH_SOURCE on a symlinked entry is
# the LINK, so it is dereferenced first; script-relative is then tried before the live layer, which
# is what lets a fix go live on the trunk fast-forward instead of waiting behind a deploy. An
# EXPLICIT CC_MLOAD_PRESENCE_LIB is honoured VERBATIM and never folded into the fallback list —
# folding it in is how an override stops being one, and it is how the absent-library case is
# testable at all.
_ml_source_presence() {
  local self here cand lib=""
  if [ -n "${CC_MLOAD_PRESENCE_LIB:-}" ]; then
    [ -r "$CC_MLOAD_PRESENCE_LIB" ] || return 1
    lib="$CC_MLOAD_PRESENCE_LIB"
  else
    self="${BASH_SOURCE[0]:-$0}"
    while [ -L "$self" ]; do
      cand="$(readlink "$self" 2>/dev/null)" || break
      case "$cand" in /*) self="$cand" ;; *) self="$(dirname "$self")/$cand" ;; esac
    done
    here="$(cd "$(dirname "$self")" 2>/dev/null && pwd)" || here=""
    for cand in "${here:+$here/lib/spawn-presence.sh}" \
                "$HOME/.claude/scripts/lib/spawn-presence.sh"; do
      [ -n "$cand" ] && [ -r "$cand" ] && { lib="$cand"; break; }
    done
  fi
  [ -n "$lib" ] || return 1
  # shellcheck source=/dev/null
  . "$lib" 2>/dev/null || return 1
  command -v cc_sp_active >/dev/null 2>&1 || return 1
  command -v cc_sp_trees  >/dev/null 2>&1 || return 1
  return 0
}

# ── sample ────────────────────────────────────────────────────────────────────────────────────────
# One row, appended. Deliberately does no analysis: the recorder must stay cheap enough to run on a
# 60 s timer beside capacity-alarm without becoming part of the load it is measuring. An unreadable
# census is written as JSON `null` — the analyzer drops any PAIR touching a null rather than
# imputing, because an imputed census is a transition the box never had.
ml_sample() {
  local t load1 ncpu active trees
  t="$(date +%s 2>/dev/null)" || t=""
  [ -n "$t" ] || { printf 'NO-DATA clock unreadable\n' >&2; return 3; }
  load1="$(_ml_load1)"
  ncpu="$(_ml_ncpu)"
  [ -n "$load1" ] || { printf 'NO-DATA load1 unreadable\n' >&2; return 3; }
  active=""; trees=""
  if _ml_source_presence; then
    active="$(cc_sp_active 2>/dev/null)" || active=""
    trees="$(cc_sp_trees  2>/dev/null)" || trees=""
  fi
  mkdir -p "$(dirname "$CC_MLOAD_SERIES")" 2>/dev/null || true
  printf '{"t":%s,"load1":%s,"ncpu":%s,"active":%s,"trees":%s}\n' \
    "$t" "$load1" "${ncpu:-null}" "${active:-null}" "${trees:-null}" \
    >> "$CC_MLOAD_SERIES" || return 3
  return 0
}

# ── analyze ───────────────────────────────────────────────────────────────────────────────────────
# The whole fit is ONE awk pass over the series so the analyzer has no dependency the recorder does
# not already have (no jq, no python) — the parse is a fixed-shape field extract over rows this file
# is the sole writer of, which is why a regex reader is safe here and would not be over a foreign
# store.
ml_analyze() {
  local as_json=0 census="active"
  while [ $# -gt 0 ]; do
    case "$1" in
      --json)    as_json=1 ;;
      --census)  shift; census="${1:-active}" ;;
      *) printf 'unknown argument: %s\n' "$1" >&2; return 3 ;;
    esac
    shift
  done
  [ -r "$CC_MLOAD_SERIES" ] || { _ml_emit_nodata "$as_json" "series unreadable: $CC_MLOAD_SERIES"; return 3; }

  local out rc
  out="$(awk -v CENSUS="$census" \
             -v DTMIN="$CC_MLOAD_DT_MIN" -v DTMAX="$CC_MLOAD_DT_MAX" \
             -v KMAX="$CC_MLOAD_KMAX" \
             -v MINTRANS="$CC_MLOAD_MIN_TRANS" -v MINBASE="$CC_MLOAD_MIN_BASELINES" \
             -v CLOADSD="$CC_MLOAD_CTRL_LOAD_SD" -v CCENSD="$CC_MLOAD_CTRL_CENSUS_SD" \
             -v THALF="$CC_MLOAD_TARGET_HALFW" \
             -f /dev/stdin "$CC_MLOAD_SERIES" <<'AWK'
function num(s) { return s + 0 }
function get(line, key,   re, m) {
  re = "\"" key "\":"
  if (match(line, re "null")) return "NA"
  if (!match(line, re "-?[0-9.]+")) return "NA"
  m = substr(line, RSTART + length(key) + 3, RLENGTH - length(key) - 3)
  return m
}
BEGIN { n = 0 }
{
  t = get($0, "t"); l = get($0, "load1"); c = get($0, CENSUS)
  if (t == "NA" || l == "NA") next
  n++
  T[n] = num(t); L[n] = num(l); C[n] = c              # C may be "NA"; kept, dropped per-pair
  NC[n] = get($0, "ncpu")
}
END {
  if (n < 2) { print "NO-DATA|too few rows: " n; exit 3 }

  # ── C1/C2 inputs: level statistics over rows where BOTH load and census are readable ────────────
  ln = 0; sl = 0; sc = 0
  for (i = 1; i <= n; i++) if (C[i] != "NA") { ln++; SL[ln] = L[i]; SC[ln] = num(C[i]) }
  if (ln < 2) { print "NO-DATA|census never readable in " n " rows"; exit 3 }
  for (i = 1; i <= ln; i++) { sl += SL[i]; sc += SC[i] }
  ml = sl / ln; mc = sc / ln
  vl = 0; vc = 0; cov = 0
  for (i = 1; i <= ln; i++) {
    dl = SL[i] - ml; dc = SC[i] - mc
    vl += dl * dl; vc += dc * dc; cov += dl * dc
  }
  # Sample (n-1) denominators throughout: an sd threshold compared against a population sd would be
  # systematically lenient at exactly the small n where C1 matters most.
  sdl = (ln > 1) ? sqrt(vl / (ln - 1)) : 0
  sdc = (ln > 1) ? sqrt(vc / (ln - 1)) : 0
  r   = (vl > 0 && vc > 0) ? cov / sqrt(vl * vc) : 0
  rdef = (vl > 0 && vc > 0) ? 1 : 0

  # ── C1 — THE DEAD-INSTRUMENT CONTROL, and the one that must be able to fail ─────────────────────
  # Armed only when load actually moved: a quiet box where NOTHING moved is a NO-DATA-shaped
  # absence of evidence, and calling that "blind" would make the control fire on every idle series
  # and therefore carry no information. C1 fails exactly in the dead headline's shape — load moving
  # while the census sits still.
  c1_armed = (sdl >= CLOADSD) ? 1 : 0
  c1_fail  = (c1_armed && sdc < CCENSD) ? 1 : 0

  # ── first-difference model: d_load = alpha + beta*d_census + e ──────────────────────────────────
  m = 0; ntrans = 0
  for (i = 2; i <= n; i++) {
    if (C[i] == "NA" || C[i-1] == "NA") continue          # never impute a census
    dt = T[i] - T[i-1]
    if (dt < DTMIN || dt > DTMAX) continue                # a gap is not an interval
    dc = num(C[i]) - num(C[i-1])
    if (dc < 0) adc = -dc; else adc = dc
    if (adc > KMAX) continue                              # nine-at-once is a different regime
    m++
    X[m] = dc; Y[m] = L[i] - L[i-1]; B[m] = L[i-1]
    if (dc != 0) {
      ntrans++
      bucket = int(L[i-1] / 5)                            # 5-load-point baseline buckets
      seen[bucket] = 1
    }
  }
  nbase = 0; for (b in seen) nbase++

  if (m < 2) { print "NO-DATA|too few admissible intervals: " m; exit 3 }

  sx = 0; sy = 0
  for (i = 1; i <= m; i++) { sx += X[i]; sy += Y[i] }
  mx = sx / m; my = sy / m
  sxx = 0; sxy = 0
  for (i = 1; i <= m; i++) { sxx += (X[i]-mx)*(X[i]-mx); sxy += (X[i]-mx)*(Y[i]-my) }

  have_fit = (sxx > 0 && m > 2) ? 1 : 0
  beta = 0; alpha = 0; se = 0; half = 0; tmult = 0
  if (have_fit) {
    beta  = sxy / sxx
    alpha = my - beta * mx
    rss = 0
    for (i = 1; i <= m; i++) { e = Y[i] - alpha - beta*X[i]; rss += e*e }
    df = m - 2
    s2 = rss / df
    se = sqrt(s2 / sxx)
    # Two-sided 95% t multiplier. A normal 1.96 at df=4 understates the interval by ~40%, and this
    # estimator's whole point is that the incumbents were quoted without one.
    if      (df >= 30) tmult = 2.042
    else if (df >= 20) tmult = 2.086
    else if (df >= 15) tmult = 2.131
    else if (df >= 10) tmult = 2.228
    else if (df >= 8)  tmult = 2.306
    else if (df >= 6)  tmult = 2.447
    else if (df >= 4)  tmult = 2.776
    else if (df >= 3)  tmult = 3.182
    else if (df >= 2)  tmult = 4.303
    else               tmult = 12.706
    half = tmult * se
  }
  lo = beta - half; hi = beta + half

  # ── decidability against the four incumbents ────────────────────────────────────────────────────
  # An interval that excludes none of them has not moved the question, however tight it looks.
  nm[1]="0.172"; nv[1]=0.172; nm[2]="0.566"; nv[2]=0.566
  nm[3]="1.89";  nv[3]=1.89
  excl = ""; nexcl = 0
  if (have_fit) {
    for (k = 1; k <= 3; k++) if (nv[k] < lo || nv[k] > hi) { excl = excl (nexcl?",":"") nm[k]; nexcl++ }
    if (hi < 2.5 || lo > 5.0) { excl = excl (nexcl?",":"") "2.5-5"; nexcl++ }
  }

  # n needed for the target half-width, from the achieved se (se ~ 1/sqrt(m) at fixed design).
  nneed = 0
  if (have_fit && half > THALF) nneed = int(m * (half/THALF) * (half/THALF)) + 1

  # ── verdict ─────────────────────────────────────────────────────────────────────────────────────
  reason = ""
  if (c1_fail) {
    verdict = "BLIND"; ec = 2
    reason = sprintf("census-flat: sd(%s)=%.3f < %.2f while sd(load1)=%.3f >= %.2f", \
                     CENSUS, sdc, CCENSD, sdl, CLOADSD)
  } else if (ntrans < MINTRANS) {
    verdict = "INCONCLUSIVE"; ec = 1
    reason = sprintf("too few transitions: %d < %d", ntrans, MINTRANS)
  } else if (nbase < MINBASE) {
    verdict = "INCONCLUSIVE"; ec = 1
    reason = sprintf("too few distinct baselines: %d < %d", nbase, MINBASE)
  } else if (!have_fit) {
    verdict = "INCONCLUSIVE"; ec = 1
    reason = "no variance in d_census, or df<1"
  } else if (nexcl == 0) {
    verdict = "INCONCLUSIVE"; ec = 1
    reason = sprintf("CI [%.3f,%.3f] excludes none of the incumbents", lo, hi)
  } else {
    verdict = "MEASURED"; ec = 0
    if (rdef && sdc >= CCENSD && (r < 0.30 && r > -0.30) && (lo <= 0 && hi >= 0))
      reason = "census-moves-load-does-not: the transitions are real and beta is small"
    else
      reason = sprintf("excludes %s", excl)
  }

  printf "%s|%s|%.4f|%.4f|%.4f|%.4f|%.4f|%d|%d|%d|%d|%.4f|%.4f|%.4f|%d|%d|%d|%s|%s\n", \
     verdict, CENSUS, beta, lo, hi, half, alpha, m, ntrans, nbase, n, sdl, sdc, r, rdef, have_fit, nneed, excl, reason
  exit ec
}
AWK
)"
  rc=$?
  _ml_render "$rc" "$out" "$as_json" "$census"
  return $rc
}

_ml_emit_nodata() { # <as_json> <why>
  if [ "${1:-0}" = "1" ]; then printf '{"verdict":"NO-DATA","reason":"%s"}\n' "$2"
  else printf 'NO-DATA  %s\n' "$2"; fi
}

_ml_render() { # <rc> <awkout> <as_json> <census>
  local rc="$1" out="$2" as_json="$3" census="$4"
  if [ "$rc" = "3" ]; then
    _ml_emit_nodata "$as_json" "${out#NO-DATA|}"
    return 0
  fi
  local verdict cen beta lo hi half alpha m ntrans nbase nrows sdl sdc r rdef havefit nneed excl reason
  IFS='|' read -r verdict cen beta lo hi half alpha m ntrans nbase nrows sdl sdc r rdef havefit nneed excl reason <<EOF
$out
EOF
  if [ "$as_json" = "1" ]; then
    printf '{"verdict":"%s","census":"%s","reason":"%s","n_rows":%s,"n_intervals":%s,"n_transitions":%s,"n_baselines":%s,"sd_load1":%s,"sd_census":%s,"r_level":%s,"r_defined":%s' \
      "$verdict" "$cen" "$reason" "$nrows" "$m" "$ntrans" "$nbase" "$sdl" "$sdc" "$r" "$rdef"
    if [ "$verdict" = "BLIND" ]; then
      printf ',"marginal_load_per_session":null,"suppressed":"C1 failed — no attribution is emitted"}\n'
    elif [ "$havefit" != "1" ]; then
      printf ',"marginal_load_per_session":null,"suppressed":"no transition variance — nothing was fitted"}\n'
    else
      printf ',"marginal_load_per_session":%s,"ci95_lo":%s,"ci95_hi":%s,"half_width":%s,"drift_per_interval":%s,"excludes":"%s","n_needed_for_target":%s}\n' \
        "$beta" "$lo" "$hi" "$half" "$alpha" "$excl" "$nneed"
    fi
    return 0
  fi

  printf '%s  (census=%s)  %s\n' "$verdict" "$cen" "$reason"
  printf '  series      rows=%s  admissible intervals=%s  transitions=%s  baseline buckets=%s\n' \
    "$nrows" "$m" "$ntrans" "$nbase"
  printf '  control C1  sd(load1)=%s  sd(%s)=%s  -> %s\n' "$sdl" "$cen" "$sdc" \
    "$( [ "$verdict" = "BLIND" ] && echo FAIL || echo pass )"
  if [ "$rdef" = "1" ]; then
    printf '  control C2  r(load1,%s)=%s  (reported, not a gate — see header)\n' "$cen" "$r"
  else
    printf '  control C2  r undefined (a series with no variance) — reported, not a gate\n'
  fi
  if [ "$verdict" = "BLIND" ]; then
    # THE SUPPRESSION IS THE POINT. The DoD's rule is that no attribution figure may be quoted until
    # a sampler clears this control, so the figure is not printed wide, or hedged, or greyed out —
    # it is not printed. A number on the page is quotable no matter what qualifies it.
    printf '  marginal    SUPPRESSED — the census does not move while load does; any per-session\n'
    printf '              figure from this series would be an artifact of the arithmetic.\n'
    return 0
  fi
  if [ "$havefit" != "1" ]; then
    # A degenerate fit has no beta, and printing 0.0000 for it would be the same defect BLIND
    # suppresses: a number on the page is quotable regardless of the verdict beside it.
    printf '  marginal    NOT FITTED — no transition variance in the admissible intervals.\n'
    return 0
  fi
  printf '  marginal    beta = %s load points per ACTIVE session   95%% CI [%s, %s]\n' "$beta" "$lo" "$hi"
  printf '  drift       alpha = %s load points per interval (the arm 1.89 had no way to subtract)\n' "$alpha"
  if [ -n "$excl" ]; then
    printf '  excludes    %s\n' "$excl"
  else
    printf '  excludes    none of {0.172, 0.566, 1.89, 2.5-5} — the 30x spread is not yet narrowed\n'
  fi
  [ "$nneed" != "0" ] && printf '  to decide   ~%s admissible intervals for a half-width of %s (have %s)\n' \
    "$nneed" "$CC_MLOAD_TARGET_HALFW" "$m"
  return 0
}

# ── selftest ──────────────────────────────────────────────────────────────────────────────────────
# Fixtures are synthesized with a KNOWN beta, so the estimator is checked against ground truth rather
# than against its own output. Case C1-FAIL is the load-bearing one: it replays the dead headline's
# shape (a census flat at 19-20 across a 2.3x load range) and asserts BLIND with no figure printed.
# A control that cannot be shown failing is not a control.
ml_selftest() {
  local tmp rc fails=0
  tmp="$(mktemp -d)" || return 3
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" RETURN

  _ml_case() { # <name> <expect-verdict> <file>
    local name="$1" want="$2" f="$3" got
    got="$(CC_MLOAD_SERIES="$f" ml_analyze 2>&1)"; rc=$?
    local v="${got%%  *}"; v="${v%% *}"
    if [ "$v" = "$want" ]; then printf 'ok    %-28s %s\n' "$name" "$want"
    else printf 'FAIL  %-28s want=%s got=%s\n' "$name" "$want" "$v"; fails=$((fails+1)); fi
    printf '%s\n' "$got" | sed 's/^/        /'
  }

  # A — known beta = 1.00 with a WANDERING BASELINE and non-session drift, because a fixture that
  # holds the box still tests an estimator no real series will ever meet: the whole reason the
  # incumbents disagree is that this box's load moves for reasons the census cannot see. The drift
  # term here is deliberately larger per interval than beta, so recovering 1.00 demonstrates the
  # intercept is doing its job rather than that the problem was easy.
  # PARAMETERS ARE THE BOX'S OWN, not convenient ones. Non-session load moves on a slow wander whose
  # spread matches the measured 11.21-36.07 at a CONSTANT N=15-16 (sd ~ 8); the census wanders over
  # the 4-16 the fleet actually visits. Ground truth beta = 1.00. A fixture tuned easier than the
  # subject would certify an estimator that cannot survive contact with the series it is for.
  awk 'BEGIN{ t=1000; l=22; c=9; base=22
    for(i=0;i<400;i++){
      dc = 0
      if      ((i*13)%7 == 0) dc =  1
      else if ((i*13)%7 == 3) dc = -1
      c += dc; if (c < 4) { c = 4; dc = 0 } ; if (c > 16) { c = 16; dc = 0 }
      # slow non-session wander: two incommensurate cycles + a sawtooth, sd ~ 8 over the run
      nb = 22 + 9.0*sin(i/23.0) + 5.0*sin(i/7.3) + ((i*5)%17)*0.35 - 2.8
      dl = (nb - base) + dc*1.00
      base = nb
      l += dl; if (l < 0.5) l = 0.5
      t += 60
      printf "{\"t\":%d,\"load1\":%.3f,\"ncpu\":10,\"active\":%d,\"trees\":%d}\n", t, l, c, c+6
    }}' > "$tmp/known.jsonl"
  _ml_case "known-beta-1.0" "MEASURED" "$tmp/known.jsonl"
  local beta_seen
  beta_seen="$(CC_MLOAD_SERIES="$tmp/known.jsonl" ml_analyze --json | sed 's/.*"marginal_load_per_session":\([0-9.-]*\).*/\1/')"
  if awk -v b="$beta_seen" 'BEGIN{exit !(b>0.80 && b<1.20)}'; then
    printf 'ok    %-28s beta=%s in [0.80,1.20]\n' "beta-recovers-truth" "$beta_seen"
  else
    printf 'FAIL  %-28s beta=%s outside [0.80,1.20]\n' "beta-recovers-truth" "$beta_seen"; fails=$((fails+1))
  fi

  # A2 — THE INCUMBENT DISAGREEMENT, REPRODUCED FROM A KNOWN TRUTH.
  #
  # The same series whose true beta is 1.00 is refitted the way 0.172 and 0.566 were produced: OLS of
  # load1 on the census over LEVELS. The claim under test is NOT that the level fit is biased toward
  # zero — the first run of this case measured a level slope of 0.666 with r = 0.017, which is not
  # attenuation and is worth recording as the reason this case is worded the way it is. The claim is
  # that the level fit is UNIDENTIFIED: its slope is a near-zero covariance divided by a small census
  # variance, so it is a ratio of two quantities the box does not hold still, and it can land
  # anywhere. That is a better account of the incumbents than bias is, because it explains why TWO
  # level-family estimates over the same machine (0.172 and 0.566) differ from each other by 3.3x.
  #
  # Asserted, therefore: the level fit explains a negligible share of load variance, AND its own 95%
  # interval fails to separate the incumbents it was used to produce. An estimator whose interval
  # contains both 0.172 and 1.89 has not measured anything, whatever point value it prints.
  local lvl lr2 llo lhi
  read -r lvl lr2 llo lhi <<EOF
$(awk -F'[:,]' '{ for(i=1;i<=NF;i++){ if($i ~ /"load1"/) l=$(i+1); if($i ~ /"active"/) c=$(i+1) }
        n++; sl+=l; sc+=c; L[n]=l; C[n]=c }
      END{ if(n<4){print "NA NA NA NA"; exit} ml=sl/n; mc=sc/n
        for(i=1;i<=n;i++){ dl=L[i]-ml; dc=C[i]-mc; sxx+=dc*dc; syy+=dl*dl; sxy+=dc*dl }
        if(sxx<=0||syy<=0){print "NA NA NA NA"; exit}
        b=sxy/sxx; r2=(sxy*sxy)/(sxx*syy)
        for(i=1;i<=n;i++){ e=(L[i]-ml)-b*(C[i]-mc); rss+=e*e }
        se=sqrt((rss/(n-2))/sxx)
        printf "%.4f %.5f %.4f %.4f", b, r2, b-1.96*se, b+1.96*se }' "$tmp/known.jsonl")
EOF
  if [ "$lvl" = "NA" ]; then
    printf 'FAIL  %-28s level fit unavailable\n' "level-fit-unidentified"; fails=$((fails+1))
  elif awk -v r2="$lr2" -v lo="$llo" -v hi="$lhi" \
         'BEGIN{ exit !(r2 < 0.05 && lo <= 0.172 && hi >= 1.89) }'; then
    printf 'ok    %-28s level slope=%s r2=%s CI[%s,%s] spans 0.172..1.89; first-diff got %s\n' \
      "level-fit-unidentified" "$lvl" "$lr2" "$llo" "$lhi" "$beta_seen"
  else
    printf 'FAIL  %-28s level slope=%s r2=%s CI[%s,%s] — fixture no longer reproduces the defect\n' \
      "level-fit-unidentified" "$lvl" "$lr2" "$llo" "$lhi"; fails=$((fails+1))
  fi

  # B — THE CONTROL THAT MUST BE ABLE TO FAIL. The dead headline's own shape: load sweeps a 2.3x
  # range while the census sits at 19-20. Must be BLIND, and must print no marginal.
  awk 'BEGIN{ t=1000
    for(i=0;i<60;i++){
      l = 16 + 10*sin(i/6.0) + (i%5)*0.7          # sd well above 1.0
      c = 19 + (i%13==0 ? 1 : 0)                  # essentially flat, sd well below 0.30
      t += 60
      printf "{\"t\":%d,\"load1\":%.3f,\"ncpu\":10,\"active\":%d,\"trees\":%d}\n", t, l, c, c
    }}' > "$tmp/flat.jsonl"
  _ml_case "C1-fail-census-flat" "BLIND" "$tmp/flat.jsonl"
  # Captured first, then matched: `ml_analyze | grep` under `pipefail` takes the analyzer's own
  # non-zero verdict code as the pipeline status, so the assertion would read a correct BLIND as a
  # harness failure. (Found by this suite on its first run.)
  # Matched with bash globs rather than `printf | grep -q`: an early-exiting consumer SIGPIPEs its
  # producer and `set -o pipefail` promotes that 141 to the pipeline's status, so the assertion would
  # read a correct BLIND as a harness failure (pipefail-sigpipe-lint's class, in-tree at ec9a43a9).
  local blindout blindjson
  blindout="$(CC_MLOAD_SERIES="$tmp/flat.jsonl" ml_analyze)"
  if [[ "$blindout" == *SUPPRESSED* && "$blindout" != *"beta ="* ]]; then
    printf 'ok    %-28s no figure printed\n' "blind-suppresses-figure"
  else
    printf 'FAIL  %-28s a marginal was printed under BLIND\n' "blind-suppresses-figure"; fails=$((fails+1))
  fi
  blindjson="$(CC_MLOAD_SERIES="$tmp/flat.jsonl" ml_analyze --json)"
  if [[ "$blindjson" == *'"marginal_load_per_session":null'* ]]; then
    printf 'ok    %-28s json marginal is null\n' "blind-json-null"
  else
    printf 'FAIL  %-28s json emitted a marginal under BLIND\n' "blind-json-null"; fails=$((fails+1))
  fi

  # C — too few transitions. Must be INCONCLUSIVE, never MEASURED off three points.
  awk 'BEGIN{ t=1000; l=20; c=8
    for(i=0;i<20;i++){ dc=(i==5||i==11)?1:0; c+=dc; l+=dc*1.0+((i%3)-1)*0.4; t+=60
      printf "{\"t\":%d,\"load1\":%.3f,\"ncpu\":10,\"active\":%d,\"trees\":%d}\n", t,l,c,c }}' \
    > "$tmp/thin.jsonl"
  _ml_case "too-few-transitions" "INCONCLUSIVE" "$tmp/thin.jsonl"

  # D — quiet box: nothing moves at all. C1 must NOT arm (that is an absence of evidence, not
  # blindness), so this is INCONCLUSIVE rather than BLIND.
  awk 'BEGIN{ t=1000; for(i=0;i<40;i++){ t+=60
      printf "{\"t\":%d,\"load1\":2.000,\"ncpu\":10,\"active\":4,\"trees\":10}\n", t }}' > "$tmp/quiet.jsonl"
  _ml_case "quiet-box-not-blind" "INCONCLUSIVE" "$tmp/quiet.jsonl"

  # E — gaps are not intervals: a series sampled hours apart yields no admissible pair.
  awk 'BEGIN{ t=1000; c=8; for(i=0;i<20;i++){ t+=7200; c+=(i%2);
      printf "{\"t\":%d,\"load1\":%.3f,\"ncpu\":10,\"active\":%d,\"trees\":%d}\n", t, 20+i, c, c }}' \
    > "$tmp/gappy.jsonl"
  _ml_case "gaps-rejected" "NO-DATA" "$tmp/gappy.jsonl"

  # F — a null census is dropped, never imputed as a zero-transition. A row whose census is
  # unreadable straddles two intervals, and imputing it as "unchanged" would manufacture a drift
  # observation out of an absent measurement — the same conflation NO-DATA exists to prevent.
  awk 'BEGIN{ t=1000; l=12; c=8
    for(i=0;i<120;i++){
      dc = (i%4==0) ? 1 : ((i%4==2) ? -1 : 0)
      c += dc; if(c<3){c=3; dc=0}
      l += dc*1.00 + 3.0*sin(i/9.0) - 1.4*cos(i/4.0) + ((i*7)%11)*0.25 - 1.2
      if (l < 1) l = 1
      t += 60
      if(i%9==3) printf "{\"t\":%d,\"load1\":%.3f,\"ncpu\":10,\"active\":null,\"trees\":null}\n", t,l
      else printf "{\"t\":%d,\"load1\":%.3f,\"ncpu\":10,\"active\":%d,\"trees\":%d}\n", t,l,c,c }}' \
    > "$tmp/nulls.jsonl"
  local nullout
  nullout="$(CC_MLOAD_SERIES="$tmp/nulls.jsonl" ml_analyze --json)"
  if [[ "$nullout" == *'"verdict":"MEASURED"'* ]]; then
    printf 'ok    %-28s nulls dropped, fit survives\n' "null-census-dropped"
  else
    printf 'FAIL  %-28s %s\n' "null-census-dropped" "$nullout"; fails=$((fails+1))
  fi

  printf '\n%s\n' "$( [ "$fails" -eq 0 ] && echo 'selftest: all cases pass' || echo "selftest: $fails FAILURE(S)" )"
  [ "$fails" -eq 0 ]
}

# ── entry ─────────────────────────────────────────────────────────────────────────────────────────
main() {
  local verb="${1:-analyze}"
  [ $# -gt 0 ] && shift
  case "$verb" in
    sample)   ml_sample "$@" ;;
    analyze)  ml_analyze "$@" ;;
    selftest) ml_selftest "$@" ;;
    -h|--help|help)
      sed -n '/^# ══ USAGE/,/^set -uo/p' "${BASH_SOURCE[0]:-$0}" | sed 's/^# \{0,1\}//;$d' ;;
    *) printf 'unknown verb: %s (sample|analyze|selftest)\n' "$verb" >&2; return 3 ;;
  esac
}

# Sourced by the bats suite (which calls ml_analyze directly against fixtures); executed otherwise.
if [ "${BASH_SOURCE[0]:-$0}" = "${0}" ]; then main "$@"; fi
