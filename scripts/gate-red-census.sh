#!/bin/bash
# gate-red-census.sh — the land pipeline's census: what a land COSTS, how often its own gate
# refuses it, which arm did the refusing, and how much of the work is thrown away as stale.
#
# SCOPE NOTE (P0, 2026-08-11). This started as the gate-red panel alone (P2) and now renders every
# question land.log can answer, because land.log is ONE store and a second reader of it would be a
# second authority on the same rows — the exact defect one renderer exists to prevent. It is NOT
# merged with scripts/cycle-time-census.sh and should not be: that tool reads a different store
# (the postland STAMP directory) about a different subject (the VERIFIER lane's cycle time), and
# neither calls the other. Two stores, two subjects, two tools; one renderer each.
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
#   5. A `stage`:"round" ROW IS NOT AN ATTEMPT (P0). ship-land now attests its stale-gate re-rounds,
#      which are INTERNAL signals — the same land continues — so pooling them would have DILUTED
#      every rate here by however often siblings happened to move the trunk, i.e. the new
#      instrument would have improved this tool's own headline number by adding rows. They are
#      excluded from the population and reported in their own panel. ABSENT `stage` reads as
#      "land", so every pre-P0 row keeps the classification it already had (memory:
#      new-enum-member-falls-into-fail-closed-default).
#
# WHAT A LAND COSTS (P0 panels). land.log carried no duration at all until 2026-08-11, so v2's own
# acceptance criterion ("land latency p50 <= 30s, p99 <= 3 min — measure it, do not narrate it")
# named an artifact that could not answer it, and the published figures drifted unrefuted in two
# directions at once (README said the mutex hold was 5-15s, ship.md said 84-302s; the store said
# neither). Three panels close it, and each prints its own COVERAGE rather than a bare percentile,
# because these fields have a birthday and the population that carries them grows one land at a
# time (memory: published-figure-decays-with-its-source):
#
#   LAND LATENCY   total_s percentiles, split by outcome. A refused land and a landed one answer
#                  different questions and their medians are minutes apart; pooling them produces a
#                  number that describes no actual experience.
#   GATE COST      gate_rounds, and where gate_s went (arms vs statics). §5.P3 measured the fifteen
#                  ratchet arms at ~112s of a 127-137s re-round, so this is the panel that says
#                  whether a slow land was re-gated or merely gated.
#   STALENESS      P(stale | waited) and the WAIT-FREE staleness column, which §2.B found to be the
#                  rising one — the lock ledger can only see rounds that QUEUED, so the tool-side
#                  round rows are the half that was structurally invisible.
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
lock_rows = []
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
                # Kept as well as counted: the STALENESS panel's denominator is the lock ledger's
                # wait column, which lives only here. They stay OUT of the invocation population —
                # the header's trap 1 is precisely that they are shaped like one.
                if isinstance(d, dict) and ('wait_s' in d or 'hold_s' in d):
                    lock_rows.append(d)
                continue
            rows.append(d)

# ---- classify each invocation --------------------------------------------------------------------
def num(d, k):
    """An int field, or None. bool is an int subclass in python and would pass silently."""
    v = d.get(k)
    return v if (isinstance(v, int) and not isinstance(v, bool)) else None

recs, round_recs = [], []
for d in rows:
    e = d.get('exit')
    exit_ok = isinstance(e, int) and not isinstance(e, bool)
    ts = d.get('ts') if isinstance(d.get('ts'), str) else None
    r = {
        'ts':      ts,
        't':       epoch(ts) if ts else None,
        'exit':    e if exit_ok else None,
        'exit_ok': exit_ok,
        'red':     d.get('red'),
        'has_red': 'red' in d,
        'smoke':   d.get('smoke'),
        # P0 fields. ABSENT is the pre-2026-08-11 state and is carried as None all the way to the
        # panels, which report coverage rather than substituting a zero — a missing duration read
        # as 0s would make the pipeline look instantaneous for its entire recorded history.
        'total_s':        num(d, 'total_s'),
        'gate_rounds':    num(d, 'gate_rounds'),
        'gate_s':         num(d, 'gate_s'),
        'gate_arms_s':    num(d, 'gate_arms_s'),
        'gate_statics_s': num(d, 'gate_statics_s'),
    }
    # ABSENT stage ⇒ "land": every row written before P0 is a terminal outcome, which is what every
    # rate in this tool already assumed. A default of "round" would retroactively empty the store.
    (round_recs if d.get('stage') == 'round' else recs).append(r)

# Newest-first ordering is by ts; an UNDATED row cannot be ordered, so it sorts to the front rather
# than being dropped — --window may exclude it, no other read may.
recs.sort(key=lambda r: (r['t'] is not None, r['t'] or 0))
round_recs.sort(key=lambda r: (r['t'] is not None, r['t'] or 0))
if window > 0:
    recs = recs[-window:]
    # The round rows are windowed by TIME to the surviving population rather than by count: they
    # are not attempts, so "the newest N rounds" would be a different window from "the newest N
    # lands" and the two panels would silently describe different periods.
    if recs and recs[0]['t'] is not None:
        round_recs = [r for r in round_recs if r['t'] is None or r['t'] >= recs[0]['t']]

if days_arg:
    cutoff = now_s - float(days_arg) * 86400.0
    recs = [r for r in recs if r['t'] is not None and r['t'] >= cutoff]
    round_recs = [r for r in round_recs if r['t'] is not None and r['t'] >= cutoff]
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
# PREFIX, not equality. P0 split `none` into six causes, and this line — the tool's own "83% of
# lands run no test of their own diff" headline — would have kept matching only the bare legacy
# token and reported the quiet fraction COLLAPSING to the skipped column as the new rows arrived.
# A consumer that keys on an enum's spelling breaks the moment the enum grows; keying on the class
# is what makes the growth additive (memory: new-enum-member-falls-into-fail-closed-default).
def is_quiet(k):
    return k == 'none' or k.startswith('none-') or k == 'skipped'
quiet = sum(v for k, v in smoke.items() if is_quiet(k))
# The breakdown the split bought: which CAUSE the quiet lands had. `none` (bare) is the pre-P0
# population and is reported as its own row — it is an absence of attribution, not a cause.
smoke_causes = sorted(((k, v) for k, v in smoke.items() if k == 'none' or k.startswith('none-')),
                      key=lambda kv: (-kv[1], kv[0]))

# ---- P0 panels ------------------------------------------------------------------------------------
def pctile(vals, p):
    """Nearest-rank-with-interpolation over a SORTED copy. Empty ⇒ None, never 0."""
    if not vals:
        return None
    v = sorted(vals)
    if len(v) == 1:
        return float(v[0])
    k = (len(v) - 1) * (p / 100.0)
    f = int(k)
    c = min(f + 1, len(v) - 1)
    return float(v[f]) + (float(v[c]) - float(v[f])) * (k - f)

def latency(pop, field='total_s'):
    """Percentiles + the coverage they rest on. A percentile over 3 of 400 rows is not a
    measurement of the pipeline, it is a measurement of the instrument's age, so `n` and the
    carried fraction ride WITH the numbers rather than in a footnote."""
    vals = [r[field] for r in pop if r[field] is not None]
    return {
        'n': len(pop), 'carried': len(vals),
        'coverage': (len(vals) / float(len(pop))) if pop else None,
        'p50': pctile(vals, 50), 'p90': pctile(vals, 90), 'p99': pctile(vals, 99),
        'max': float(max(vals)) if vals else None,
    }

# SPLIT BY OUTCOME, never pooled. A refused land (exit 6) stops at the gate; a landed one pays the
# gate AND a fetch, a rebase, a lock round-trip and a content-verify. Their medians answer
# different questions, and v2's acceptance criterion is about the SUCCESSFUL path.
lat_landed = latency([r for r in recs if r['exit'] == 0])
lat_red    = latency([r for r in recs if r['exit'] == 6])
lat_all    = latency(recs)

gate_pop   = [r for r in recs if r['gate_rounds'] is not None]
rounds_hist = {}
for r in gate_pop:
    rounds_hist[str(r['gate_rounds'])] = rounds_hist.get(str(r['gate_rounds']), 0) + 1
gate_cost = {
    'n': len(recs), 'carried': len(gate_pop),
    'coverage': (len(gate_pop) / float(len(recs))) if recs else None,
    'rounds_hist': rounds_hist,
    'multi_round': sum(1 for r in gate_pop if (r['gate_rounds'] or 0) > 1),
    'gate_s':         latency(gate_pop, 'gate_s'),
    'gate_arms_s':    latency(gate_pop, 'gate_arms_s'),
    'gate_statics_s': latency(gate_pop, 'gate_statics_s'),
}

# ---- STALENESS ------------------------------------------------------------------------------------
# TWO INDEPENDENT SENSORS, deliberately reported side by side rather than summed.
#   lock side  — every LOCK row that resolved (exit != -1) carries wait_s and the wrapped command's
#                exit, so P(exit-42 | wait>0) is computable here and was the audit's headline. Its
#                blind spot is structural: it can only see rounds that took the mutex.
#   tool side  — the stage:"round" rows P0 added. Every re-round, queued or not, and therefore the
#                only view of the WAIT-FREE column §2.B measured as the rising one.
lock_recs = []
for d in lock_rows:
    ts = d.get('ts') if isinstance(d.get('ts'), str) else None
    lock_recs.append({'t': epoch(ts) if ts else None, 'wait_s': num(d, 'wait_s'),
                      'hold_s': num(d, 'hold_s'),
                      'exit': num(d, 'exit'), 'event': d.get('event')})

def staleness(cut):
    pop = [r for r in lock_recs
           if r['t'] is not None and r['t'] >= cut and r['exit'] is not None and r['exit'] != -1
           and r['wait_s'] is not None]
    waited = [r for r in pop if r['wait_s'] > 0]
    free   = [r for r in pop if r['wait_s'] == 0]
    sw = sum(1 for r in waited if r['exit'] == 42)
    sf = sum(1 for r in free if r['exit'] == 42)
    tool_rounds = sum(1 for r in round_recs if r['t'] is not None and r['t'] >= cut)
    lands = sum(1 for r in recs if r['t'] is not None and r['t'] >= cut)
    # THE HOLD, rendered so the published figure has a re-run instead of a re-derivation. README
    # said 5-15s and ship.md said 84-302s while the store said neither, for weeks, because the
    # number lived only in prose — the decay mode a figure with no tool behind it always takes.
    holds = [r['hold_s'] for r in pop if r['hold_s'] is not None]
    return {
        'hold_n': len(holds), 'hold_p50': pctile(holds, 50), 'hold_p90': pctile(holds, 90),
        'hold_p99': pctile(holds, 99), 'hold_max': (float(max(holds)) if holds else None),
        'lock_n': len(pop), 'waited': len(waited), 'stale_given_waited': sw,
        'p_stale_given_waited': (sw / float(len(waited))) if waited else None,
        'wait_free': len(free), 'stale_wait_free': sf,
        'p_stale_wait_free': (sf / float(len(free))) if free else None,
        'tool_rounds': tool_rounds, 'lands': lands,
        'rounds_per_land': (tool_rounds / float(lands)) if lands else None,
    }

stale_windows = []
for d in win_days:
    m = staleness(now_s - d * 86400.0)
    m['label'] = ('%gd' % d)
    stale_windows.append(m)

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
        'smoke_none_causes': [{'cause': c, 'n': n} for c, n in smoke_causes],
        'round_rows': len(round_recs),
        'land_latency': {'landed': lat_landed, 'gate_red': lat_red, 'all': lat_all},
        'gate_cost': gate_cost,
        'staleness': stale_windows,
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
    print('      %-16s %5d   %s' % (k, n, pctf(n / float(len(recs))) if recs else '   n/a'))
print('      none*+skipped: %d/%d of all invocations (%s) · %d/%d of those carrying the field (%s)'
      % (quiet, len(recs), pctf(quiet / float(len(recs))) if recs else '   n/a',
         quiet, smoke_carried, pctf(quiet / float(smoke_carried)) if smoke_carried else '   n/a'))
if smoke_causes:
    print('      WHY no smoke ran — one token per cause since 2026-08-11. A bare `none` is a row from')
    print('      before the split: an absence of attribution, never a sixth cause.')
    for c, n in smoke_causes:
        print('        %-16s %5d' % (c, n))

def secs(x):
    return '    n/a' if x is None else ('%6.0fs' % x)

print('')
print('  LAND LATENCY — total_s, end to end. THE field v2\'s acceptance criterion names and the store')
print('  did not carry until 2026-08-11, which is why "p50 <= 30s" was never once checked against it.')
print('  Landed and refused are never pooled: they are different journeys, minutes apart.')
print('    %-10s %14s   %7s %7s %7s   %s' % ('outcome', 'carried/rows', 'p50', 'p90', 'p99', 'coverage'))
for lbl, m in (('landed', lat_landed), ('gate-red', lat_red), ('all', lat_all)):
    print('    %-10s %6d /%6d   %7s %7s %7s   %s'
          % (lbl, m['carried'], m['n'], secs(m['p50']), secs(m['p90']), secs(m['p99']),
             pctf(m['coverage'])))
if lat_all['carried'] < min_n:
    print('    coverage is under the %d-row floor — these are the instrument\'s first rows, not a rate.'
          % min_n)

print('')
print('  GATE COST — where a land\'s seconds went. The arms dominate by construction (§5.P3 measured')
print('  the fifteen ratchet arms at ~112s of a 127-137s re-round), so a total alone cannot say')
print('  whether a slow land was RE-gated or merely gated.')
print('    gate_rounds carried on %d/%d rows (%s) · %d land(s) gated more than once'
      % (gate_cost['carried'], gate_cost['n'], pctf(gate_cost['coverage']), gate_cost['multi_round']))
if rounds_hist:
    print('      rounds:  %s'
          % ('  '.join('%s×%d' % (k, rounds_hist[k]) for k in sorted(rounds_hist, key=lambda x: int(x)))))
for lbl, key in (('gate_s', 'gate_s'), ('  of which arms', 'gate_arms_s'), ('  of which statics', 'gate_statics_s')):
    m = gate_cost[key]
    print('      %-18s p50 %s  p90 %s  max %s' % (lbl, secs(m['p50']), secs(m['p90']), secs(m['max'])))

print('')
print('  STALENESS — work the pipeline threw away. A waiter queued during a successful hold is by')
print('  construction gating against a base the holder is about to move, so it acquires, discovers')
print('  staleness in seconds, discards its gate and re-rounds. TWO sensors, never summed: the lock')
print('  ledger sees only rounds that QUEUED; the tool-side round rows see every one.')
print('    %-7s %22s   %22s   %s'
      % ('window', 'P(stale | waited)', 'P(stale | NO wait)', 'rounds/land (tool side)'))
for m in stale_windows:
    print('    %-7s %8d /%6d %6s   %8d /%6d %6s   %8s  (%d rounds, %d lands)'
          % (m['label'], m['stale_given_waited'], m['waited'], pctf(m['p_stale_given_waited']),
             m['stale_wait_free'], m['wait_free'], pctf(m['p_stale_wait_free']),
             ('n/a' if m['rounds_per_land'] is None else '%.2f' % m['rounds_per_land']),
             m['tool_rounds'], m['lands']))
print('    The wait-FREE column is the one to watch: it is push-RATE pressure, not lock contention,')
print('    and it is invisible to the lock ledger\'s own utilization figure.')
print('    MUTEX HOLD — the figure README and ship.md each published a different wrong value for.')
print('    %-7s %8s   %8s %8s %8s %8s' % ('window', 'holds', 'p50', 'p90', 'p99', 'max'))
for m in stale_windows:
    print('    %-7s %8d   %8s %8s %8s %8s'
          % (m['label'], m['hold_n'], secs(m['hold_p50']), secs(m['hold_p90']),
             secs(m['hold_p99']), secs(m['hold_max'])))
print('    The p99 tail is the in-lock fallback lane (statics + ratchets under the mutex, ~112s per')
print('    §5.P3) — visible per land in gate_rounds/gate_s, not merely as an unexplained tail.')
print('    A window that SPANS a change to the hold pools two mechanisms and describes neither:')
print('    P1 (145fab7d, 2026-08-11T01:32Z) moved the sweep + reap out of the mutex and the same')
print('    measure went from p50 61s / max 6771s to p50 3s. Prefer the shortest window with n above')
print('    the floor, and say which window a published figure came from.')
if not any(m['tool_rounds'] for m in stale_windows):
    print('    tool-side rounds are 0 — either nothing went stale, or these rows predate 2026-08-11.')
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
