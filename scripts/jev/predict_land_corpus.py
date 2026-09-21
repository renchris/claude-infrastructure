#!/usr/bin/env python3
"""predict_land_corpus.py — the corpus, the null arithmetic, the sampler and the scorer for the
pre-flight land-refusal predictor. Pure arithmetic and store-reading; every git and every Jev call
lives in predict-land.sh beside it.

WHY A SECOND READER OF land.log EXISTS AT ALL, AND WHAT MAKES IT NOT A SECOND AUTHORITY.
scripts/gate-red-census.sh's header states the rule this file had to get past: "land.log is ONE
store and a second reader of it would be a second authority on the same rows — the exact defect one
renderer exists to prevent." That rule is right, and the census still cannot serve this job: it is a
RENDERER. `--json` emits aggregate counts, and a predictor needs the per-row `head`/`base` pair to
join a diff onto a label. So this file reads rows, and pays for the privilege by PROVING it agrees:
`census` cross-checks its own population counts against `gate-red-census.sh --json` and REFUSES
(exit 4) on any disagreement. The census stays the authority; this is a derived reader that has to
show its work. Losing that assert is losing the only thing separating the two.

THE FIVE TRAPS ARE THE CENSUS'S, RESTATED HERE BECAUSE THIS FILE MUST OBEY THEM TOO (its header
§§1-5 is the record; every one of them reads quieter than the truth):
  1. the population is rows with a POSITIVE "tool":"ship-land" claim, never "rows lacking `event`".
  2. exit 6 (GATE RED — a verdict about the TREE) and exit 9 (GATE-KILLED — a claim about the
     MACHINE) are claims about different objects and are never summed.
  3. `red` has FOUR states: "" (no arm went red), a named list, "unattributed" (a red that indicts
     the instrument), and ABSENT (before the field's birthday it did not exist).
  4. an unparseable row is counted, never dropped — a shrinking denominator reads as improvement.
  5. a stage:"round" row is an INTERNAL re-round signal, not an attempt.

AND THE TRAP THAT IS THIS FILE'S OWN, because it only appears once you try to PREDICT the label.
A pre-flight predictor reads a DIFF. Trap 2 is therefore not a reporting nicety here, it is a
ceiling: a diff cannot determine an exit 9, a lock timeout, a push race or a verify retry
exhaustion, so every such row in the positive class is a refusal no correct instrument can catch.
Pooling them (which `select(.tool=="ship-land" and .head and .base)` does) does not add noise
symmetrically — it caps RECALL, and it caps it below the number an acceptance condition is about to
be written against. `null` computes that ceiling and says whether the bar is reachable at all.
"""

import json
import math
import os
import random
import sys

# The `red` field's birthday. Same default and same full-STAMP form as gate-red-census.sh, and for
# the same measured reason its header gives: rounded down to 2026-08-08T00:00:00Z it swallows the
# 20h before the field shipped and re-files 37 birthday reds as a producer regression.
BIRTHDAY = os.environ.get("GATE_RED_ATTRIB_BIRTHDAY", "2026-08-08T20:56:59Z")

# Exit codes, from scripts/ship-land.sh. Only these two are named, because only these two have a
# documented claim attached: 6 is about the tree, 9 is about the box. Everything else non-zero is
# OTHER_REFUSED on purpose — inventing a taxonomy for codes whose producer does not enumerate them
# here would be this file asserting something ship-land never said.
EXIT_GATE_RED = 6
EXIT_GATE_KILLED = 9


def epoch(stamp):
    """UTC ISO stamp -> seconds, or None. No dateutil, no tz guessing: the producer writes Z."""
    if not isinstance(stamp, str) or not stamp.endswith("Z"):
        return None
    body = stamp[:-1]
    try:
        date, _, time = body.partition("T")
        y, mo, d = (int(x) for x in date.split("-"))
        h, mi, s = (int(float(x)) for x in time.split(":"))
    except (ValueError, AttributeError):
        return None
    # days-from-civil (Howard Hinnant), so this needs no library and no local timezone.
    y2 = y - (1 if mo <= 2 else 0)
    era = (y2 if y2 >= 0 else y2 - 399) // 400
    yoe = y2 - era * 400
    doy = (153 * (mo + (-3 if mo > 2 else 9)) + 2) // 5 + d - 1
    doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
    days = era * 146097 + doe - 719468
    return days * 86400 + h * 3600 + mi * 60 + s


def read_store(path):
    """-> (recs, round_recs, counters). Trap 1 and trap 4 both live here."""
    counters = {"lines": 0, "bad_json": 0, "non_invocation": 0}
    recs, round_recs = [], []
    if not os.path.exists(path):
        return recs, round_recs, counters
    with open(path, "r") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            counters["lines"] += 1
            try:
                d = json.loads(line)
            except ValueError:
                # Trap 4: it cannot be classified, so it cannot be in the population — and it is
                # still counted, because a dropped row would shrink a denominator silently.
                counters["bad_json"] += 1
                continue
            if not isinstance(d, dict) or d.get("tool") != "ship-land":
                # Trap 1: the discriminator is the producer's POSITIVE claim about itself. Keying on
                # the absence of `event` pooled 1,592 lock rows into the denominator and reported
                # 16% where the truth was 32%.
                counters["non_invocation"] += 1
                continue
            rec = _classify(d)
            # Trap 5: ABSENT stage reads as "land" — every pre-P0 row is a terminal outcome, and a
            # default of "round" would retroactively empty the store.
            (round_recs if d.get("stage") == "round" else recs).append(rec)
    return recs, round_recs, counters


def _intfield(d, key):
    """An int field or None. bool is an int subclass in python and would pass silently."""
    v = d.get(key)
    return v if (isinstance(v, int) and not isinstance(v, bool)) else None


def _classify(d):
    ts = d.get("ts") if isinstance(d.get("ts"), str) else None
    e = _intfield(d, "exit")
    red = d.get("red")
    has_red = "red" in d
    t = epoch(ts) if ts else None
    birth = epoch(BIRTHDAY) or epoch(BIRTHDAY + "T00:00:00Z")

    # Trap 3, all four states, and the bucket names are the census's so the two can be diffed.
    if not has_red or red is None:
        bucket = "instrument_birthday" if (t is not None and birth is not None and t < birth) \
                 else "field_absent_post_birthday"
        arm = None
    elif red == "":
        bucket = "no_arm_went_red"
        arm = None
    elif red == "unattributed":
        # A red WAS raised and no arm claimed it. This indicts the INSTRUMENT, not the tree, so it
        # is never a training label for "which arm" — a reader subtracts it.
        bucket = "unattributed"
        arm = None
    else:
        bucket = "attributed"
        # `red` is a comma-joined list of `arm[:subject]`. The FIRST arm is the one that fired
        # fail-fast; the subject after the colon is a path and is not a class.
        arm = red.split(",")[0].split(":")[0].strip() or None

    if e == 0:
        klass = "LANDED"
    elif e is None:
        klass = "NO_EXIT"
    elif e == EXIT_GATE_RED:
        klass = "GATE_RED"
    elif e == EXIT_GATE_KILLED:
        klass = "GATE_KILLED"
    else:
        klass = "OTHER_REFUSED"

    return {
        "ts": ts, "t": t, "exit": e, "class": klass,
        "red": red, "red_bucket": bucket, "arm": arm,
        "head": d.get("head"), "base": d.get("base"), "tree": d.get("tree"),
        "smoke": d.get("smoke"), "gate_scope": d.get("gate_scope"),
        "total_s": _intfield(d, "total_s"),
        "repo": d.get("repo"), "branch": d.get("branch"),
    }


def joinable(recs):
    """Rows a diff can be recovered for AT ALL: both shas present and neither the '?' placeholder.

    attest_land writes "?" when ATTEST_HEAD/ATTEST_BASE were never set — a land that died before
    the shas were resolved. A bare `.head and .base` jq test passes on "?" because it is a non-empty
    string, so the receipt's count of "6,286 rows carrying both head and base" includes rows whose
    diff does not exist. Reachability is checked in the shell (it needs git); this is the cheap half.
    """
    out = []
    for r in recs:
        h, b = r.get("head"), r.get("base")
        if isinstance(h, str) and isinstance(b, str) and h not in ("", "?") and b not in ("", "?"):
            out.append(r)
    return out


# ── THE NULL ARITHMETIC ───────────────────────────────────────────────────────────────────────
# docs/research/jev-100p-2026-09-21/a10-prior-art-and-labels.md closes on this instruction and it is
# the reason this function exists before the calling one: "Before any of that, run the arithmetic
# Addendum 3 wishes it had run: at the sampled REFUSED rate, what would a PERFECT detector return,
# and what would a COIN return? Write both numbers down first. A count is not a measurement until
# you know what a working instrument would have produced."
#
# A coin is the trap the receipt is pointing at. At prevalence p a random warner that fires on a
# fraction f of lands gets recall f and precision p — for FREE, at every operating point. So the
# pass bar "precision >= 0.85 at recall >= 0.20" is not a bar of 0.85 against 0.5; it is a lift of
# (0.85 - p) against a coin, and if p were ever to reach 0.85 the condition would be satisfiable by
# an instrument that reads nothing at all.

def null_arithmetic(recs, positive="any-nonzero"):
    """Prevalence, the coin, and the ceiling a PERFECT diff-reading detector cannot exceed.

    `positive` names the label definition:
      any-nonzero  the receipt's — exit != 0. Includes GATE_KILLED, lock timeouts, push races.
      gate-red     exit == 6 only: the codes whose producer says they are about the TREE.
      attributed   exit == 6 AND an arm named it: the only rows where "which arm" is scoreable.
    """
    pop = [r for r in recs if r["exit"] is not None]
    n = len(pop)
    if n == 0:
        return {"n": 0, "verdict": "NO-CORPUS"}

    def is_pos(r):
        if positive == "gate-red":
            return r["class"] == "GATE_RED"
        if positive == "attributed":
            return r["class"] == "GATE_RED" and r["red_bucket"] == "attributed"
        return r["exit"] != 0

    n_pos = sum(1 for r in pop if is_pos(r))
    prev = n_pos / n

    # The ceiling. A diff can only determine a refusal the GATE raised about the tree; every other
    # non-zero exit is a fact about the machine, the lock, the remote or the operator's flags. Even
    # granting a perfect reader every single exit-6 row, it cannot reach the rest.
    #
    # 🚨 INTERSECTED WITH is_pos, NOT counted over the whole population — and the first version was
    # not. Measured on the real-diff fixture 2026-09-21: under positive="attributed" the numerator
    # counted all 16 exit-6 rows against a denominator of 8 positives and printed a recall ceiling
    # of 2.0 ("16 of 8 positives"). A ratio above 1 is not a near miss, it is the reading that waves
    # the acceptance bar through — the one direction this whole function exists to stop. A ceiling is
    # |positives a diff can determine| / |positives|, so both terms must be under the SAME predicate.
    determinable = sum(1 for r in pop if is_pos(r) and r["class"] == "GATE_RED")
    ceiling = (determinable / n_pos) if n_pos else 0.0
    # And the arm question is narrower still: only `attributed` rows carry the label it is scored
    # against, and that bucket has a BIRTHDAY, so its population is a recency stratum of the
    # binary question's. The two questions cannot be asked of one uniformly-spanning sample.
    arm_scoreable = sum(1 for r in pop if is_pos(r)
                        and r["class"] == "GATE_RED" and r["red_bucket"] == "attributed")
    arm_ceiling = (arm_scoreable / n_pos) if n_pos else 0.0

    return {
        "n": n, "positive_def": positive, "n_positive": n_pos, "prevalence": round(prev, 4),
        # A coin's numbers, at every operating point. Precision does not move with f.
        "coin": {"auroc": 0.5, "precision": round(prev, 4),
                 "recall_at_fire_rate_0.20": 0.20,
                 "note": "precision == prevalence at EVERY firing rate; f buys recall, never precision"},
        # The degenerate always-warn predictor, which reads nothing and is worth naming because it
        # is the thing a headline recall number is most easily confused with.
        "always_warn": {"precision": round(prev, 4), "recall": 1.0},
        "perfect_diff_reader": {
            "gate_red_rows": determinable,
            "recall_ceiling": round(ceiling, 4),
            "arm_scoreable_rows": arm_scoreable,
            "arm_recall_ceiling": round(arm_ceiling, 4),
        },
        "class_census": _tally(pop, "class"),
        "red_bucket_census": _tally(pop, "red_bucket"),
    }


def _tally(rows, key):
    out = {}
    for r in rows:
        out[r.get(key)] = out.get(r.get(key), 0) + 1
    return dict(sorted(out.items(), key=lambda kv: -kv[1]))


def pass_bar_reachable(null, min_recall=0.20, min_precision=0.85):
    """Is the frozen acceptance bar reachable BY A PERFECT INSTRUMENT on this label definition?

    This is not a gate that tightens with evidence (docs/lessons/gate-must-ease-with-evidence.md):
    the ceiling is a property of the LABEL DEFINITION, not of the sample, so more rows move it only
    if the composition of refusals changes. That is exactly why it must be answered BEFORE the
    sample is drawn — no amount of collecting gets past it, and finding out afterwards means the
    calls were spent measuring a bar nobody could clear.
    """
    reasons = []
    if null.get("n", 0) == 0:
        return {"reachable": None, "why": ["no corpus"]}
    ceiling = null["perfect_diff_reader"]["recall_ceiling"]
    # A ceiling outside [0,1] is not a fact about the corpus, it is this instrument being broken —
    # and the defect it catches shipped here once already (see null_arithmetic's numerator note).
    # Reported as its OWN state rather than as unreachability, because the two demand opposite
    # actions: one is "re-define the positive class", the other is "fix the arithmetic".
    if not 0.0 <= ceiling <= 1.0:
        return {"reachable": None,
                "why": ["INSTRUMENT FAULT: recall ceiling %.4f is outside [0,1] — the numerator and "
                        "denominator are not under the same positive predicate. No verdict." % ceiling]}
    if ceiling < min_recall:
        reasons.append(
            "recall ceiling %.3f < required %.2f — %d of %d positives are refusals a DIFF cannot "
            "determine (GATE_KILLED, lock, push, verify), so a perfect reader still misses them"
            % (ceiling, min_recall, null["n_positive"] - null["perfect_diff_reader"]["gate_red_rows"],
               null["n_positive"]))
    if null["prevalence"] >= min_precision:
        reasons.append(
            "prevalence %.3f >= required precision %.2f — the bar is satisfiable by a coin, which "
            "gets precision == prevalence at every operating point" % (null["prevalence"], min_precision))
    return {"reachable": not reasons, "why": reasons,
            "headroom_recall": round(ceiling - min_recall, 4),
            "lift_required_over_coin": round(min_precision - null["prevalence"], 4)}


# ── SAMPLING ──────────────────────────────────────────────────────────────────────────────────
def stratified_sample(recs, n, holdout, seed, months=True):
    """Preserve the class ratio AND span the time range; freeze a holdout before any threshold.

    Recency-only would measure today's gate config rather than the gate (the receipt's own warning),
    so strata are (class, calendar month). The holdout is carved from the SAME strata, not from the
    tail, or it would be a different population from the training half and the comparison would be
    between periods rather than between instruments.
    """
    rng = random.Random(seed)
    strata = {}
    for r in recs:
        mon = (r["ts"] or "")[:7] if months else "all"
        strata.setdefault((r["class"], mon), []).append(r)
    for key in strata:
        strata[key].sort(key=lambda r: (r["ts"] or "", r["head"] or ""))
        rng.shuffle(strata[key])

    total = sum(len(v) for v in strata.values())
    if total == 0:
        return [], []
    want = min(n, total)
    # Proportional allocation with largest-remainder, so a small stratum is not rounded out of
    # existence -- an emptied stratum is the "aggregate control cannot see a per-member zero" shape.
    quota, rema = {}, []
    for key, rows in strata.items():
        exact = want * len(rows) / total
        quota[key] = min(len(rows), int(exact))
        rema.append((exact - int(exact), key))
    rema.sort(reverse=True)
    i = 0
    while sum(quota.values()) < want and i < len(rema) * 4:
        key = rema[i % len(rema)][1]
        if quota[key] < len(strata[key]):
            quota[key] += 1
        i += 1

    train, held = [], []
    for key, rows in strata.items():
        take = rows[:quota[key]]
        # Holdout share is applied WITHIN each stratum for the reason in the docstring.
        k = int(round(len(take) * holdout))
        held.extend(take[:k])
        train.extend(take[k:])
    train.sort(key=lambda r: (r["ts"] or ""))
    held.sort(key=lambda r: (r["ts"] or ""))
    return train, held


# ── SCORING ───────────────────────────────────────────────────────────────────────────────────
def auroc(scores, labels):
    """Rank AUROC with proper tie handling. None when either class is empty -- NOT 0.5.

    A degenerate corpus returning 0.5 would read as "chance", i.e. as a measurement, when the true
    state is that no measurement was made (docs/lessons/fail-safe-default-mimics-the-healthy-state.md
    is this exact shape: a fail-safe default matching a legible output is unfalsifiable).
    """
    pairs = sorted(zip(scores, labels), key=lambda x: x[0])
    n_pos = sum(1 for _, y in pairs if y)
    n_neg = len(pairs) - n_pos
    if n_pos == 0 or n_neg == 0:
        return None
    ranks, i = [0.0] * len(pairs), 0
    while i < len(pairs):
        j = i
        while j + 1 < len(pairs) and pairs[j + 1][0] == pairs[i][0]:
            j += 1
        avg = (i + j) / 2.0 + 1.0
        for k in range(i, j + 1):
            ranks[k] = avg
        i = j + 1
    s_pos = sum(ranks[k] for k, (_, y) in enumerate(pairs) if y)
    return (s_pos - n_pos * (n_pos + 1) / 2.0) / (n_pos * n_neg)


def auroc_ci(scores, labels, iters=2000, seed=7, alpha=0.05):
    """Percentile bootstrap. Resamples are stratified by class, so a draw cannot empty one class and
    silently drop out of the distribution -- that would bias the interval toward whatever the
    surviving class implies."""
    point = auroc(scores, labels)
    if point is None:
        return {"auroc": None, "lo": None, "hi": None, "n": len(labels)}
    rng = random.Random(seed)
    pos = [s for s, y in zip(scores, labels) if y]
    neg = [s for s, y in zip(scores, labels) if not y]
    boots = []
    for _ in range(iters):
        ps = [pos[rng.randrange(len(pos))] for _ in pos]
        ns = [neg[rng.randrange(len(neg))] for _ in neg]
        v = auroc(ps + ns, [1] * len(ps) + [0] * len(ns))
        if v is not None:
            boots.append(v)
    boots.sort()
    lo = boots[int((alpha / 2) * len(boots))]
    hi = boots[min(len(boots) - 1, int((1 - alpha / 2) * len(boots)))]
    return {"auroc": round(point, 4), "lo": round(lo, 4), "hi": round(hi, 4),
            "n": len(labels), "n_pos": len(pos), "iters": len(boots)}


def pr_curve(scores, labels):
    """Every operating point, so the best precision AT a recall floor is read off rather than
    assumed. Thresholds are the distinct scores, descending."""
    n_pos = sum(1 for y in labels if y)
    if n_pos == 0:
        return []
    pts, order = [], sorted(zip(scores, labels), key=lambda x: -x[0])
    tp = fp = 0
    prev = None
    for s, y in order:
        if prev is not None and s != prev:
            pts.append({"threshold": prev, "precision": tp / (tp + fp), "recall": tp / n_pos,
                        "fired": tp + fp})
        tp += 1 if y else 0
        fp += 0 if y else 1
        prev = s
    if prev is not None:
        pts.append({"threshold": prev, "precision": tp / (tp + fp), "recall": tp / n_pos,
                    "fired": tp + fp})
    return pts


def best_point_at_recall(scores, labels, min_recall):
    pts = [p for p in pr_curve(scores, labels) if p["recall"] >= min_recall]
    if not pts:
        return None
    return max(pts, key=lambda p: (p["precision"], p["recall"]))


def precision_diff_ci(scores_a, scores_b, labels, min_recall, iters=2000, seed=11, alpha=0.05):
    """CI on (precision_a - precision_b) at a shared recall floor, PAIRED on the row.

    Paired, because an unpaired interval over two instruments scored on the same rows credits the
    corpus's own variance to the difference and widens until nothing is ever separable. Condition
    (c) of the receipt's acceptance bar demands an interval excluding zero, so the interval has to
    be the one that can exclude it.
    """
    idx = list(range(len(labels)))
    rng = random.Random(seed)

    def at(sub, sc):
        p = best_point_at_recall([sc[i] for i in sub], [labels[i] for i in sub], min_recall)
        return None if p is None else p["precision"]

    point_a, point_b = at(idx, scores_a), at(idx, scores_b)
    if point_a is None or point_b is None:
        return {"delta": None, "lo": None, "hi": None,
                "why": "one instrument cannot reach recall %.2f at any threshold" % min_recall}
    boots = []
    pos = [i for i in idx if labels[i]]
    neg = [i for i in idx if not labels[i]]
    for _ in range(iters):
        sub = [pos[rng.randrange(len(pos))] for _ in pos] + \
              [neg[rng.randrange(len(neg))] for _ in neg]
        a, b = at(sub, scores_a), at(sub, scores_b)
        if a is not None and b is not None:
            boots.append(a - b)
    if not boots:
        return {"delta": round(point_a - point_b, 4), "lo": None, "hi": None,
                "why": "no bootstrap resample reached the recall floor for both instruments"}
    boots.sort()
    return {"delta": round(point_a - point_b, 4),
            "precision_a": round(point_a, 4), "precision_b": round(point_b, 4),
            "lo": round(boots[int((alpha / 2) * len(boots))], 4),
            "hi": round(boots[min(len(boots) - 1, int((1 - alpha / 2) * len(boots)))], 4),
            "excludes_zero": boots[int((alpha / 2) * len(boots))] > 0,
            "iters": len(boots)}


# ── CLI ───────────────────────────────────────────────────────────────────────────────────────
def _emit(obj):
    sys.stdout.write(json.dumps(obj, sort_keys=True, default=str) + "\n")


def _cmd_census(argv):
    """Read the store, emit rows + counts. The shell wrapper runs the census parity assert."""
    path = argv[0] if argv else os.path.expanduser("~/.claude/land.log")
    recs, rounds, counters = read_store(path)
    join = joinable(recs)
    _emit({
        "store": path,
        "lines": counters["lines"],
        "bad_json": counters["bad_json"],
        "non_invocation_rows": counters["non_invocation"],
        # The two numbers gate-red-census.sh --json also reports. The wrapper compares them.
        "invocations": len(recs),
        "round_rows": len(rounds),
        "joinable": len(join),
        "placeholder_sha_rows": len(recs) - len(join),
        "class_census": _tally(recs, "class"),
        "red_bucket_census": _tally(recs, "red_bucket"),
        "arm_census": _tally([r for r in recs if r["arm"]], "arm"),
    })
    return 0


def _cmd_rows(argv):
    path = argv[0] if argv else os.path.expanduser("~/.claude/land.log")
    recs, _, _ = read_store(path)
    for r in joinable(recs):
        _emit(r)
    return 0


def _cmd_null(argv):
    path = argv[0] if argv else os.path.expanduser("~/.claude/land.log")
    recs, _, _ = read_store(path)
    pop = joinable(recs)
    out = {"store": path, "definitions": {}}
    for d in ("any-nonzero", "gate-red", "attributed"):
        n = null_arithmetic(pop, positive=d)
        n["pass_bar"] = pass_bar_reachable(n)
        out["definitions"][d] = n
    _emit(out)
    # A definition whose bar no perfect instrument can clear is a refusal to spend, not a warning.
    prim = out["definitions"]["any-nonzero"].get("pass_bar", {})
    return 5 if prim.get("reachable") is False else 0


def main(argv):
    if not argv:
        sys.stderr.write("usage: predict_land_corpus.py {census|rows|null} [land.log]\n")
        return 2
    cmd, rest = argv[0], argv[1:]
    if cmd == "census":
        return _cmd_census(rest)
    if cmd == "rows":
        return _cmd_rows(rest)
    if cmd == "null":
        return _cmd_null(rest)
    sys.stderr.write("predict_land_corpus.py: unknown command %s\n" % cmd)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
