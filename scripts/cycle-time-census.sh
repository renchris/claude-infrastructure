#!/bin/bash
# cycle-time-census.sh — LAND_PIPELINE_V2 §8's "~2h sustained" revisit trigger, made executable.
#
# WHY THIS EXISTS. §8 rejected a second verification Mac with a conditional: "revisit only if cycle
# time under load exceeds ~2h sustained." That sentence was the whole mechanism — no definition of
# "cycle time", no way to read "under load", no denominator, and no sensor. It fired somewhere around
# 2026-07-30 and nothing noticed for nine days, until a human re-measured by hand (backlog
# 343d7cc392b6). The hand measurement was directionally right and arithmetically pooled: it reported
# "p50 ~3.2h" (the interval BETWEEN verdicts) beside "median run_s 8852s = 2h28m" (the duration OF a
# run) as if one supported the other, over a population mixing two execution paths. This script is
# the criterion with its terms pinned, so the next reading is a re-run and not a re-derivation.
#
# THE DENOMINATOR IS THE WHOLE GAME, and getting it wrong reads BACKWARDS. Two traps, both measured
# on the live store 2026-08-08:
#
#   1. NON-VERDICTS SHORTEN THE MEDIAN. A `cut` (truncated) or `hung` run writes a stamp with a small
#      run_s. Pooling those with completed runs makes a DEGRADING lane look FASTER: over 89 rolling
#      8-stamp windows, the naive p50 disagreed with the completed-runs-only p50 about whether the
#      trigger fires in 5 windows, and every disagreement ran one way — naive quiet, honest firing.
#      A lane collapsing into all-cuts would read as a lane that got fast. So: green|red only.
#
#   2. TWO POPULATIONS SHARE ONE STORE. Stamps are written both by the launchd job and by a run
#      invoked from inside a session, and they are 2.5x apart (p50 3.16h vs 1.28h). Pooling them
#      answers a question nobody asked. Only the SCHEDULED population is the lane; a hand-run is a
#      diagnostic. The discriminator is env.cc — env_fingerprint() records basename($CLAUDE_CODE_
#      EXECPATH) or the literal "unknown", so "unknown" IS "no Claude Code in the environment", i.e.
#      launchd. It is independent of the loadavg instrument, which matters because that instrument
#      was blind in every scheduled run until 4c58eaf5 (2026-08-06) and rendered its blindness as
#      "load":"0" — a dead sensor reading as a perfectly idle machine. 38 of 96 stamps carry it.
#      Cross-check that the partition is not an artifact of that fix: inside SCHEDULED, pre-fix p50
#      is 3.16h and post-fix p50 is 3.17h. The invocation path was always the discriminator.
#
# CENSORING IS REPORTED, NEVER SILENTLY MEDIANED. The corpus runs under `bounded "$SUITE_TO"`
# (POSTLAND_SUITE_TIMEOUT_S, default 10800s), so a run that hits the wall records the BOUND, not its
# work. 54% of runs in the current store are censored that way. Censoring is one-sided — from ABOVE —
# so a breach verdict stays sound (the true value is >= the observed one) while a WITHIN verdict over
# heavily-censored data is worth less. The census prints the censored fraction next to the verdict so
# a reader can price it, and refuses to call WITHIN on a majority-censored window (verdict=CENSORED).
#
# THREE-STATE VERDICT, never a boolean — a p50 over two scheduled runs is not a pass:
#   verdict=NO-VERDICT  fewer than CENSUS_MIN_N scheduled completed runs. Cannot judge. Exit 3.
#   verdict=WITHIN      p50 <= the threshold, on a window that is not majority-censored. Exit 0.
#   verdict=BREACH      p50 > the threshold. The §8 trigger is OPEN. Exit 1.
#   verdict=CENSORED    p50 <= threshold but >half the runs recorded the suite bound rather than
#                       their work — "within" is unproven, not established. Exit 4.
#
# READ-ONLY. Parses the stamp store and prints; writes nothing, runs no suite, spawns no daemon.
#
# Usage: cycle-time-census.sh [--window N] [--threshold-h H] [--all] [--json]
#   --window N       consider only the newest N stamps (default: every stamp in the store)
#   --threshold-h H  the §8 trigger, in hours (default 2)
#   --all            also print the SESSION-invoked population, for the band comparison
#   --json           one JSON object instead of the human table
#
# Seams (tests pin these): CC_POSTLAND_DIR (stamp store root) · CENSUS_MIN_N (floor, default 8) ·
# POSTLAND_SUITE_TIMEOUT_S (the censoring bound, default 10800 — must match postland-verify.sh).
#
# bash 3.2 safe. Stats are computed in python3 (/usr/bin, on every PATH including both plists'),
# never in bash — a negative array slice expands to NOTHING in bash and WHOLE in zsh, and this file
# is sourced by neither consistently enough to bet a diagnostic on it.

set -uo pipefail

POSTLAND_DIR="${CC_POSTLAND_DIR:-$HOME/.claude/autonomy/postland}"
STAMPS="$POSTLAND_DIR/stamps"
MIN_N="${CENSUS_MIN_N:-8}"
SUITE_TO="${POSTLAND_SUITE_TIMEOUT_S:-10800}"

WINDOW=0
THRESHOLD_H=2
SHOW_ALL=0
AS_JSON=0

while [ $# -gt 0 ]; do
  case "$1" in
    --window)       WINDOW="${2:-0}"; shift 2 ;;
    --threshold-h)  THRESHOLD_H="${2:-2}"; shift 2 ;;
    --all)          SHOW_ALL=1; shift ;;
    --json)         AS_JSON=1; shift ;;
    -h|--help)      sed -n '36,44p' "$0"; exit 0 ;;
    *)              printf 'cycle-time-census: unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

if [ ! -d "$STAMPS" ]; then
  printf 'verdict=NO-VERDICT reason=no-stamp-store path=%s\n' "$STAMPS"
  exit 3
fi

STAMPS="$STAMPS" WINDOW="$WINDOW" THRESHOLD_H="$THRESHOLD_H" MIN_N="$MIN_N" \
SUITE_TO="$SUITE_TO" SHOW_ALL="$SHOW_ALL" AS_JSON="$AS_JSON" python3 - <<'PY'
import json, os, glob, math, sys

stamps    = os.environ['STAMPS']
window    = int(os.environ['WINDOW'] or 0)
thresh_h  = float(os.environ['THRESHOLD_H'])
min_n     = int(os.environ['MIN_N'])
suite_to  = int(os.environ['SUITE_TO'])
show_all  = os.environ['SHOW_ALL'] == '1'
as_json   = os.environ['AS_JSON'] == '1'
thresh_s  = thresh_h * 3600.0

VERDICT = ('green', 'red')          # a COMPLETED corpus run. cut/hung produce no verdict.

rows = []
for f in glob.glob(os.path.join(stamps, '*.json')):
    try:
        with open(f) as fh:
            d = json.load(fh)
    except Exception:
        continue                     # an unparseable stamp is not a data point, and not a crash
    ts = d.get('ts')
    if not ts:
        continue
    env = d.get('env') or {}
    rows.append({
        'ts':      ts,
        'verdict': d.get('verdict'),
        'run_s':   int(d.get('run_s') or 0),
        'suites':  int(d.get('suites') or 0),
        'cc':      env.get('cc'),
    })
rows.sort(key=lambda r: r['ts'])
if window > 0:
    rows = rows[-window:]

def pct(vals, p):
    v = sorted(vals)
    if not v:
        return float('nan')
    k = (len(v) - 1) * p / 100.0
    lo, hi = math.floor(k), math.ceil(k)
    return v[lo] if lo == hi else v[lo] + (v[hi] - v[lo]) * (k - lo)

# SCHEDULED = the launchd lane. env.cc is "unknown" exactly when CLAUDE_CODE_EXECPATH was unset.
sched_all = [r for r in rows if r['cc'] == 'unknown']
sess_all  = [r for r in rows if r['cc'] and r['cc'] != 'unknown']
sched     = [r for r in sched_all if r['verdict'] in VERDICT]
sess      = [r for r in sess_all  if r['verdict'] in VERDICT]

n         = len(sched)
runs      = [r['run_s'] for r in sched]
censored  = [r for r in sched if r['run_s'] >= suite_to]
cens_frac = (len(censored) / n) if n else 0.0

p50 = pct(runs, 50) if n else float('nan')
p90 = pct(runs, 90) if n else float('nan')

if n < min_n:
    verdict, code = 'NO-VERDICT', 3
elif p50 > thresh_s:
    verdict, code = 'BREACH', 1
elif cens_frac > 0.5:
    verdict, code = 'CENSORED', 4
else:
    verdict, code = 'WITHIN', 0

def h(x):
    return float('nan') if x != x else x / 3600.0

if as_json:
    print(json.dumps({
        'verdict': verdict, 'threshold_h': thresh_h,
        'scheduled_completed_n': n, 'scheduled_p50_s': None if n == 0 else round(p50),
        'scheduled_p90_s': None if n == 0 else round(p90),
        'censored_n': len(censored), 'censored_frac': round(cens_frac, 3),
        'suite_bound_s': suite_to,
        'non_verdicts_excluded': len(sched_all) - n,
        'session_completed_n': len(sess),
        'session_p50_s': None if not sess else round(pct([r['run_s'] for r in sess], 50)),
        'stamps_considered': len(rows),
    }, sort_keys=True))
    sys.exit(code)

print('CYCLE-TIME CENSUS — LAND_PIPELINE_V2 §8 revisit trigger (>%.2gh sustained)' % thresh_h)
print('  store: %s   stamps considered: %d' % (stamps, len(rows)))
print('')
print('  SCHEDULED lane (launchd; env.cc="unknown") — THIS is the criterion\'s subject')
if n:
    print('    completed runs (green|red): %d      non-verdicts excluded (cut|hung): %d'
          % (n, len(sched_all) - n))
    print('    run_s p50: %7.2fh   p90: %7.2fh   max: %7.2fh' % (h(p50), h(p90), h(max(runs))))
    print('    censored at the %ds suite bound: %d/%d (%.0f%%) — p50 is a FLOOR where this is high'
          % (suite_to, len(censored), n, 100 * cens_frac))
else:
    print('    completed runs: 0 — nothing to judge')
if show_all and sess:
    sp50 = pct([r['run_s'] for r in sess], 50)
    print('')
    print('  SESSION-invoked (diagnostic runs, NOT the lane) — shown for comparison only')
    print('    completed runs: %d      run_s p50: %.2fh' % (len(sess), h(sp50)))
    if n and sp50 > 0:
        print('    scheduled/session ratio: %.2fx — the launchd envelope (ProcessType Background +'
              % (p50 / sp50))
        print('      Nice 10 + LowPriorityIO), NOT the corpus band: postland-verify.sh clamps the')
        print('      corpus to `taskpolicy -c background` for BOTH populations, unconditionally.')
print('')
print('verdict=%s' % verdict)
if verdict == 'BREACH':
    print('  The §8 trigger is OPEN: the scheduled lane exceeds the threshold. Read the §8 entry —')
    print('  the resolved verdict there is that a second host does NOT address this.')
elif verdict == 'CENSORED':
    print('  p50 sits under the threshold, but a majority of runs recorded the suite bound rather')
    print('  than their own work. "Within" is UNPROVEN here, not established.')
elif verdict == 'NO-VERDICT':
    print('  Fewer than %d scheduled completed runs. A median over this is not a measurement.' % min_n)
sys.exit(code)
PY
