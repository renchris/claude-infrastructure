#!/bin/bash
# gate-red-census.sh — how often does a land's own gate refuse it, and WHICH arm did the refusing.
#
# WHY THIS EXISTS. The gate-red rate is the single number that says whether the land pipeline is
# serving the author or fighting them, and until now it was no document's and no tool's first-class
# metric: land-architecture-100p-2026-08-10 §5 had to RECONSTRUCT it by hand out of land.log to
# discover it is rising (27% over 14d -> 39% over 3d -> 45% over the last day). A number that costs
# an investigation to read is a number nobody reads, so it moves for weeks before anyone notices —
# the same shape as the §8 cycle-time trigger that fired for nine days into an empty room. This is
# that reconstruction, with its terms pinned, so the next reading is a re-run and not a re-derivation.
#
# THE DENOMINATOR IS THE WHOLE GAME, and every trap here reads the SAME direction — quieter than the
# truth. All four were measured on the live store 2026-08-11 (3272 lines, 1636 invocations):
#
#   1. TWO RECORD TYPES SHARE ONE STORE, AND THE DISCRIMINATOR YOU REACH FOR FIRST IS WRONG.
#      land.log carries ship-land invocations AND land-lock lifecycle rows. The obvious filter —
#      "a lock row has an `event` key, so exclude those" — selects 45 of the 1637 lock rows: the
#      other 1592 predate the `event` field entirely and are otherwise shaped like an invocation
#      (ts/repo/branch/exit). Keying on the ABSENCE of `event` therefore pools them into the
#      denominator and reports 525/3228 = 16% where the truth is 525/1636 = 32%. This census keys on
#      the PRESENCE of "tool":"ship-land" — a positive claim the producer makes about itself.
#
#   2. exit 6 AND exit 9 ARE CLAIMS ABOUT DIFFERENT OBJECTS. exit 6 is GATE RED: a named failure in
#      your diff's suites, a verdict about the TREE, "fix it". exit 9 is GATE-KILLED: the gate died
#      without earning a verdict — a claim about the MACHINE, explicitly NOT evidence about your tree
#      (ship-land.sh:2508). Pooling them inflates a tree-quality metric with box noise, and does it
#      exactly when the box is loaded, which is when someone is most likely to be reading. They are
#      reported side by side here and never summed; exit 9 is printed as a count a reader subtracts.
#
#   3. THE `red` FIELD HAS THREE STATES AND A FOURTH THAT ONLY HISTORY EXPLAINS. The producer's own
#      comment (ship-land.sh attest_land) is emphatic that "" (no arm went red), a named arm list,
#      and "unattributed" (a red WAS raised and no arm claimed it — which indicts the INSTRUMENT,
#      not the tree) must never collapse into two. The fourth is that the field did not exist before
#      2026-08-08T20:56:59Z — the first row in the live store that carries it, and the default
#      birthday below — so it is ABSENT on 1295 of 1636 rows, 391 of which are gate-reds. Read
#      as "" those become 391 clean lands; read as "unattributed" they become 391 indictments of an
#      instrument that had not been built yet. They are their own bucket — instrument-birthday — and
#      attribution coverage is printed against the ATTRIBUTABLE population as well as against all
#      reds, so a reader can price the gap instead of guessing at it. The birthday is a full STAMP
#      and not a date on purpose: rounded to 2026-08-08T00:00:00Z it swallows the 20h before the
#      field actually shipped, and 37 birthday reds get re-filed as "the producer regressed" — an
#      alarm about a real bucket, fired entirely by the instrument's own rounding.
#
#   4. AN UNPARSEABLE ROW IS COUNTED, NEVER DROPPED. A shrinking denominator reads as an improving
#      rate. Two distinct classes, kept apart because only one can be in a denominator at all: a
#      line that is not JSON cannot be classified as an invocation, so it is counted and reported
#      OUTSIDE the population; an invocation whose `exit` is missing or non-integer IS an invocation,
#      so it stays in the denominator and lands in no exit bucket.
#
# CAUSES ARE MENTIONS, NOT A PARTITION. GATE_RED_WHY is a comma-joined, fire-ordered list, so one
# land can name several arms (`shellcheck,hermeticity`) and the per-arm counts sum to MORE than the
# number of reds. The panel prints both totals rather than letting a reader assume a partition. Two
# further shapes the producer creates and a naive split would mangle: an entry may carry a subject
# (`smoke:tests/foo.bats` — the arm is `smoke`), and a list over 240 chars is truncated with a
# `+truncated` suffix glued onto a half-written arm name, which is counted as truncation rather than
# minted as a bogus arm.
#
# THREE-STATE VERDICT, never a boolean — a rate over four lands is not a measurement:
#   verdict=MEASURED    the headline window holds >= GATE_RED_CENSUS_MIN_N invocations. Exit 0.
#   verdict=NO-VERDICT  it does not, or there is no store. Cannot judge. Exit 3.
# and a trend token that abstains on the same rule, independently per window:
#   trend=RISING|FLAT|FALLING   short-window rate vs long-window rate, outside/inside a margin.
#   trend=NO-VERDICT            either window is under the floor. Two thin windows differ by noise.
#
# READ-ONLY. Parses land.log and prints. Writes nothing, runs no gate, spawns nothing.
#
# Usage: gate-red-census.sh [--window N] [--days D] [--json]
#   --window N  consider only the newest N ship-land invocations (default: all of them)
#   --days D    consider only invocations in the trailing D days, and report that single window
#   --json      one JSON object instead of the human panel
#
# Seams (tests pin these): LAND_LOG (the store) · GATE_RED_CENSUS_MIN_N (floor, default 8) ·
# GATE_RED_ATTRIB_BIRTHDAY (when the `red` field began — a full UTC stamp, or a bare date which is
# read as its 00:00:00Z; default 2026-08-08T20:56:59Z) ·
# GATE_RED_TREND_PP (trend margin in percentage points, default 5).
#
# bash 3.2 safe. All parsing and arithmetic is python3 (/usr/bin, on every PATH including both
# plists'), never bash — a negative array slice expands to NOTHING in bash and WHOLE in zsh, and a
# rate is not a thing to bet on which shell sourced you.

set -uo pipefail

LOG="${LAND_LOG:-$HOME/.claude/land.log}"
MIN_N="${GATE_RED_CENSUS_MIN_N:-8}"
BIRTHDAY="${GATE_RED_ATTRIB_BIRTHDAY:-2026-08-08T20:56:59Z}"
TREND_PP="${GATE_RED_TREND_PP:-5}"

WINDOW=0
DAYS=""
AS_JSON=0

usage() {
  cat <<'USAGE'
gate-red-census.sh [--window N] [--days D] [--json]
  --window N  consider only the newest N ship-land invocations (default: all)
  --days D    consider only the trailing D days, and report that single window
  --json      one JSON object instead of the human panel
exit: 0 verdict=MEASURED · 3 verdict=NO-VERDICT (no store, or under the floor) · 2 bad usage
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --window)   WINDOW="${2:-}"; shift 2 ;;
    --days)     DAYS="${2:-}"; shift 2 ;;
    --json)     AS_JSON=1; shift ;;
    -h|--help)  usage; exit 0 ;;
    *)          printf 'gate-red-census: unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

case "$WINDOW" in
  ''|*[!0-9]*) printf 'gate-red-census: --window wants a non-negative integer\n' >&2; exit 2 ;;
esac
if [ -n "$DAYS" ]; then
  case "$DAYS" in
    ''|*[!0-9.]*|.|*.*.*) printf 'gate-red-census: --days wants a positive number\n' >&2; exit 2 ;;
  esac
fi

# NOW is passed IN rather than read inside python: the literal Z below is a UTC assertion, and the
# only thing entitled to make it is `date -u` (utc-stamp-lint's rule). Every window is measured
# against this one stamp, so the panel and its --json twin cannot disagree by a tick.
NOW_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

LOG="$LOG" MIN_N="$MIN_N" BIRTHDAY="$BIRTHDAY" TREND_PP="$TREND_PP" \
WINDOW="$WINDOW" DAYS="$DAYS" AS_JSON="$AS_JSON" NOW_ISO="$NOW_ISO" python3 - <<'PY'
import calendar, json, os, sys, time

log       = os.environ['LOG']
min_n     = int(os.environ['MIN_N'] or 8)
birthday  = os.environ['BIRTHDAY']
trend_pp  = float(os.environ['TREND_PP'] or 5)
window    = int(os.environ['WINDOW'] or 0)
days_arg  = os.environ['DAYS'].strip()
as_json   = os.environ['AS_JSON'] == '1'
now_iso   = os.environ['NOW_ISO']

TS_FMT = '%Y-%m-%dT%H:%M:%SZ'

def epoch(ts):
    """UTC ISO stamp -> epoch seconds, or None if it is not one. calendar.timegm, never mktime:
    mktime would apply the box's TZ to a stamp that already asserted Z."""
    try:
        return calendar.timegm(time.strptime(ts, TS_FMT))
    except Exception:
        return None

now_s   = epoch(now_iso)
# A bare date is read as its 00:00:00Z. That is a convenience, never the default — see the header:
# rounding the real birthday DOWN by 20h re-files 37 birthday reds as a producer regression.
birth_s = epoch(birthday) if 'T' in birthday else epoch(birthday + 'T00:00:00Z')
if birth_s is None:
    sys.stderr.write('gate-red-census: GATE_RED_ATTRIB_BIRTHDAY is not a UTC stamp: %s\n' % birthday)
    sys.exit(2)

# ---- read the store ------------------------------------------------------------------------------
# Three populations, and only ONE of them is a denominator:
#   tool rows          — "tool":"ship-land" is present. THE population.
#   non-invocation     — anything else that parsed. Lock rows, both schemas. Excluded, and counted.
#   unparseable JSON   — cannot be classified at all, so it cannot be in the population. Counted.
rows, non_inv, bad_json, lines_total = [], 0, 0, 0
if os.path.exists(log):
    with open(log, 'r') as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            lines_total += 1
            try:
                d = json.loads(line)
            except Exception:
                bad_json += 1
                continue
            if not isinstance(d, dict) or d.get('tool') != 'ship-land':
                non_inv += 1
                continue
            rows.append(d)

# ---- classify each invocation --------------------------------------------------------------------
recs = []
for d in rows:
    e = d.get('exit')
    # bool is an int subclass in python and would silently pass as an exit code.
    exit_ok = isinstance(e, int) and not isinstance(e, bool)
    ts = d.get('ts') if isinstance(d.get('ts'), str) else None
    recs.append({
        'ts':      ts,
        't':       epoch(ts) if ts else None,
        'exit':    e if exit_ok else None,
        'exit_ok': exit_ok,
        'red':     d.get('red'),
        'has_red': 'red' in d,
        'smoke':   d.get('smoke'),
    })

# Newest-first ordering is by ts; an UNDATED row cannot be ordered, so it sorts to the front rather
# than being dropped — --window may exclude it, no other read may.
recs.sort(key=lambda r: (r['t'] is not None, r['t'] or 0))
if window > 0:
    recs = recs[-window:]

if days_arg:
    cutoff = now_s - float(days_arg) * 86400.0
    recs = [r for r in recs if r['t'] is not None and r['t'] >= cutoff]
    win_days = [float(days_arg)]
else:
    win_days = [1.0, 3.0, 14.0]

undated = sum(1 for r in recs if r['t'] is None)

# ---- per-window rates ----------------------------------------------------------------------------
# THE denominator is every invocation in the window, including one whose exit we could not parse.
# The numerator is exit 6 alone. exit 9 rides alongside as a count, never inside either.
def measure(pop):
    n   = len(pop)
    red = sum(1 for r in pop if r['exit'] == 6)
    kil = sum(1 for r in pop if r['exit'] == 9)
    bad = sum(1 for r in pop if not r['exit_ok'])
    return {
        'n': n, 'gate_red': red, 'gate_killed': kil, 'unparseable_exit': bad,
        'rate': (red / float(n)) if n else None,
    }

windows = []
for d in win_days:
    cut = now_s - d * 86400.0
    pop = [r for r in recs if r['t'] is not None and r['t'] >= cut]
    m = measure(pop)
    m['label'] = ('%gd' % d)
    m['days']  = d
    windows.append(m)
allw = measure(recs)
allw['label'] = 'all'
allw['days']  = None
windows.append(allw)

headline = windows[-2] if len(windows) >= 2 else allw   # the longest bounded window, else `all`

# ---- verdict + trend -----------------------------------------------------------------------------
if headline['n'] >= min_n:
    verdict, code = 'MEASURED', 0
else:
    verdict, code = 'NO-VERDICT', 3

trend, trend_delta = 'NO-VERDICT', None
if len(win_days) >= 2:
    short, long_ = windows[0], windows[-2]
    if short['n'] >= min_n and long_['n'] >= min_n:
        trend_delta = (short['rate'] - long_['rate']) * 100.0
        if trend_delta > trend_pp:
            trend = 'RISING'
        elif trend_delta < -trend_pp:
            trend = 'FALLING'
        else:
            trend = 'FLAT'

# ---- causes ---------------------------------------------------------------------------------------
# Over the GATE-RED rows only: a `red` value on a row that did not exit 6 is not a cause of a red.
reds = [r for r in recs if r['exit'] == 6]
causes, subjects = {}, {}
buckets = {
    'attributed': 0,           # >=1 arm named it
    'unattributed': 0,         # the producer's own literal: a red no arm claimed. The INSTRUMENT.
    'instrument_birthday': 0,  # the `red` field did not exist yet. Not a mystery — an absence.
    'field_absent_post_birthday': 0,  # absent AFTER the field shipped: a STALE producer (the live
                                      # layer lags the checkout) or a regression. Either way the red
                                      # is unattributable — never quietly folded in as "no arm".
    'empty_on_red': 0,         # red:"" on an exit-6 row. Self-contradictory; must never be silent.
    'truncated': 0,            # the 240-char cap ate the tail of the arm list.
}
for r in reds:
    if not r['has_red']:
        if r['t'] is not None and r['t'] < birth_s:
            buckets['instrument_birthday'] += 1
        else:
            buckets['field_absent_post_birthday'] += 1
        continue
    v = r['red'] if isinstance(r['red'], str) else ''
    if v == '':
        buckets['empty_on_red'] += 1
        continue
    if v == 'unattributed':
        buckets['unattributed'] += 1
        continue
    buckets['attributed'] += 1
    for part in v.split(','):
        part = part.strip()
        if not part:
            continue
        if part.endswith('+truncated'):
            # A half-written arm name plus a marker. Minting it as an arm would invent a cause.
            buckets['truncated'] += 1
            continue
        arm = part.split(':', 1)[0]
        causes[arm] = causes.get(arm, 0) + 1
        subjects[part] = subjects.get(part, 0) + 1

cause_list   = sorted(causes.items(), key=lambda kv: (-kv[1], kv[0]))
subject_list = sorted(subjects.items(), key=lambda kv: (-kv[1], kv[0]))
mentions     = sum(causes.values())

attributable = len(reds) - buckets['instrument_birthday']
cov_attributable = (buckets['attributed'] / float(attributable)) if attributable else None
cov_all          = (buckets['attributed'] / float(len(reds))) if reds else None

# ---- exit histogram + smoke ------------------------------------------------------------------------
hist = {}
for r in recs:
    k = str(r['exit']) if r['exit_ok'] else 'unparseable'
    hist[k] = hist.get(k, 0) + 1
hist_list = sorted(hist.items(), key=lambda kv: (-kv[1], kv[0]))

smoke = {}
for r in recs:
    k = r['smoke'] if isinstance(r['smoke'], str) else 'absent'
    smoke[k] = smoke.get(k, 0) + 1
smoke_list = sorted(smoke.items(), key=lambda kv: (-kv[1], kv[0]))
smoke_carried = sum(v for k, v in smoke.items() if k != 'absent')
quiet = smoke.get('none', 0) + smoke.get('skipped', 0)

def pctf(x):
    return '   n/a' if x is None else ('%5.1f%%' % (100.0 * x))

if as_json:
    print(json.dumps({
        'store': log,
        'generated_at': now_iso,
        'verdict': verdict,
        'trend': trend,
        'trend_delta_pp': None if trend_delta is None else round(trend_delta, 1),
        'trend_margin_pp': trend_pp,
        'min_n': min_n,
        'headline_window': headline['label'],
        'lines_total': lines_total,
        'unparseable_json_lines': bad_json,
        'non_invocation_rows': non_inv,
        'invocations': len(recs),
        'undated_invocations': undated,
        'windows': [
            {'label': w['label'], 'days': w['days'], 'n': w['n'], 'gate_red': w['gate_red'],
             'gate_killed': w['gate_killed'], 'unparseable_exit': w['unparseable_exit'],
             'rate': None if w['rate'] is None else round(w['rate'], 4)}
            for w in windows
        ],
        'exit_histogram': hist,
        'causes': [{'arm': a, 'n': n} for a, n in cause_list],
        'cause_subjects': [{'subject': s, 'n': n} for s, n in subject_list],
        'cause_mentions': mentions,
        'red_rows': len(reds),
        'red_buckets': buckets,
        'attribution': {
            'attributable': attributable,
            'attributed': buckets['attributed'],
            'coverage_of_attributable': None if cov_attributable is None else round(cov_attributable, 4),
            'coverage_of_all_reds': None if cov_all is None else round(cov_all, 4),
            'birthday': birthday,
        },
        'smoke': smoke,
        'smoke_quiet_n': quiet,
        'smoke_field_carried': smoke_carried,
    }, sort_keys=True))
    sys.exit(code)

print('GATE-RED CENSUS — how often the land gate refuses a land, and which arm did it')
print('  store: %s' % log)
print('  lines: %d   ship-land invocations: %d   non-invocation rows excluded: %d   '
      'unparseable JSON lines: %d' % (lines_total, len(recs), non_inv, bad_json))
if undated:
    print('  undated invocations (no parseable ts): %d — in `all`, in no day-window' % undated)
print('')
print('  GATE-RED RATE — exit 6 is a verdict about the TREE. exit 9 (GATE-KILLED) is a claim about')
print('  the MACHINE and is NOT pooled into it; it is shown so a reader can subtract it.')
print('    %-7s %14s   %7s   %s' % ('window', 'gate-red/lands', 'rate', 'exit 9 (non-verdict)'))
for w in windows:
    print('    %-7s %7d /%5d   %7s   %d%s'
          % (w['label'], w['gate_red'], w['n'], pctf(w['rate']), w['gate_killed'],
             ('   [+%d unparseable exit]' % w['unparseable_exit']) if w['unparseable_exit'] else ''))
if trend == 'NO-VERDICT':
    print('  trend=NO-VERDICT — a window under %d invocations cannot move a rate, only noise can.'
          % min_n)
else:
    print('  trend=%s — %s %s vs %s %s = %+.1fpp (margin %gpp)'
          % (trend, windows[0]['label'], pctf(windows[0]['rate']),
             windows[-2]['label'], pctf(windows[-2]['rate']), trend_delta, trend_pp))
print('')
print('  CAUSES — which arm(s) claimed the red. A land may name several, so mentions >= reds:')
print('    %d gate-reds, %d arm-mentions. This is NOT a partition.' % (len(reds), mentions))
if cause_list:
    for arm, n in cause_list:
        print('      %-32s %5d' % (arm, n))
else:
    print('      (no attributed red in this population)')
print('    -- unattributed  %5d   a red no arm claimed — indicts the INSTRUMENT, not the tree'
      % buckets['unattributed'])
print('    -- birthday      %5d   before %s the `red` field did not exist: an absence, not a mystery'
      % (buckets['instrument_birthday'], birthday))
if buckets['field_absent_post_birthday']:
    print('    -- NO FIELD      %5d   absent AFTER %s — a STALE producer or a regression, not "no arm"'
          % (buckets['field_absent_post_birthday'], birthday))
if buckets['empty_on_red']:
    print('    -- empty-on-red  %5d   red:"" on an exit-6 row — self-contradictory, read the producer'
          % buckets['empty_on_red'])
if buckets['truncated']:
    print('    -- truncated     %5d   the 240-char cap ate the tail of an arm list'
          % buckets['truncated'])
print('    attribution coverage: %d/%d of the attributable reds (%s) · %d/%d of ALL reds (%s)'
      % (buckets['attributed'], attributable, pctf(cov_attributable),
         buckets['attributed'], len(reds), pctf(cov_all)))
print('')
print('  EXIT HISTOGRAM — every exit in proportion, so no code hides inside "not 0"')
for k, n in hist_list:
    print('      exit %-11s %5d   %s' % (k, n, pctf(n / float(len(recs))) if recs else '   n/a'))
print('')
print('  SMOKE STATE — the headline\'s own evidence. "reds are statics" holds only if smoke rarely ran.')
for k, n in smoke_list:
    print('      %-12s %5d   %s' % (k, n, pctf(n / float(len(recs))) if recs else '   n/a'))
print('      none+skipped: %d/%d of all invocations (%s) · %d/%d of those carrying the field (%s)'
      % (quiet, len(recs), pctf(quiet / float(len(recs))) if recs else '   n/a',
         quiet, smoke_carried, pctf(quiet / float(smoke_carried)) if smoke_carried else '   n/a'))
print('')
print('verdict=%s' % verdict)
if verdict == 'NO-VERDICT':
    if not os.path.exists(log):
        print('  No store at %s. Nothing to measure — this is an absence, not a zero rate.' % log)
    else:
        print('  Fewer than %d invocations in the %s window. A rate over that is not a measurement.'
              % (min_n, headline['label']))
sys.exit(code)
PY
