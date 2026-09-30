#!/usr/bin/env python3
"""Correlate the data.kalloc.1024 series in capacity-alarm.jsonl (+ rotated .gz) against fleet activity.

Reads every ~/.claude/logs/capacity-alarm.jsonl* file, keeps rows whose kalloc value was MEASURED
this tick (src == "measured"; carried rows repeat an old sample), orders them by timestamp, splits
them into boot segments at each drop, and for every segment reports:

  * the level slope (least squares, GB/day) and the first/last sample;
  * hourly increments d(kalloc) against the hourly mean of each activity column, as Pearson r.

A driver that is ACTIVITY-proportional shows up as r >= 0.6 between the increment and its column;
a driver that is time-proportional (a steady leak independent of load) shows up as a straight
line in level with low r everywhere.

Usage: analyze.py [--json]
"""

import glob
import gzip
import json
import math
import os
import sys
from collections import defaultdict
from datetime import datetime, timezone

COLS = [
    "sessions",
    "load_1m",
    "coal_procs",
    "coal_true_procs",
    "auto_coal_procs",
    "ptys_used",
    "active_gb",
    "max_proc_gb",
    "swapfiles",
]


def ts(s):
    return (
        datetime.strptime(s, "%Y-%m-%dT%H:%M:%SZ")
        .replace(tzinfo=timezone.utc)
        .timestamp()
    )


def load_rows():
    rows, allrows = {}, []
    for f in glob.glob(os.path.expanduser("~/.claude/logs/capacity-alarm.jsonl*")):
        op = gzip.open if f.endswith(".gz") else open
        with op(f, "rt") as fh:
            for line in fh:
                try:
                    r = json.loads(line)
                    t = ts(r["ts"])
                except Exception:
                    continue
                allrows.append((t, r))
                if (
                    r.get("kalloc1024_src") == "measured"
                    and r.get("kalloc1024_gb") is not None
                ):
                    rows[t] = r
    allrows.sort(key=lambda x: x[0])
    return sorted(rows.items()), allrows


def pearson(xs, ys):
    n = len(xs)
    if n < 3:
        return None
    mx, my = sum(xs) / n, sum(ys) / n
    sxy = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
    sxx = sum((x - mx) ** 2 for x in xs)
    syy = sum((y - my) ** 2 for y in ys)
    if sxx == 0 or syy == 0:
        return None
    return sxy / math.sqrt(sxx * syy)


def slope(ts_, ys):
    n = len(ts_)
    if n < 2:
        return None
    mt, my = sum(ts_) / n, sum(ys) / n
    sxx = sum((t - mt) ** 2 for t in ts_)
    return (
        None
        if sxx == 0
        else sum((t - mt) * (y - my) for t, y in zip(ts_, ys)) / sxx * 86400
    )


def segments(rows):
    segs, cur, prev = [], [], None
    for t, r in rows:
        g = r["kalloc1024_gb"]
        if prev is not None and g < prev - 0.5:
            segs.append(cur)
            cur = []
        cur.append((t, r))
        prev = g
    if cur:
        segs.append(cur)
    return segs


BUCKET_S = 3600
for _i, _a in enumerate(sys.argv):
    if _a == "--bucket-hours" and _i + 1 < len(sys.argv):
        BUCKET_S = int(float(sys.argv[_i + 1]) * 3600)


def detrended_cumulative_r(seg, allrows, col):
    """Partial test: does the level track CUMULATIVE activity better than wall time?

    Integrate `col` over the segment (trapezoid on every row, measured or not), then remove the
    linear time trend from both the kalloc level and the integral and correlate the residuals.
    A time-only leak gives r ~ 0; an activity-driven one gives a clearly positive r."""
    t0, t1 = seg[0][0], seg[-1][0]
    pts = [
        (t, r.get(col))
        for t, r in allrows
        if t0 <= t <= t1 and isinstance(r.get(col), (int, float))
    ]
    if len(pts) < 10:
        return None
    cum, acc = {}, 0.0
    for (ta, va), (tb, vb) in zip(pts, pts[1:]):
        acc += (va + vb) / 2 * (tb - ta)
        cum[tb] = acc
    keys = sorted(cum)
    import bisect

    xs, ys, ts_ = [], [], []
    for t, r in seg:
        i = bisect.bisect_right(keys, t) - 1
        if i < 0:
            continue
        xs.append(cum[keys[i]])
        ys.append(r["kalloc1024_gb"])
        ts_.append(t)

    if len(ts_) < 10 or max(ts_) == min(ts_):
        return None

    def resid(vals):
        n = len(vals)
        mt, mv = sum(ts_) / n, sum(vals) / n
        sxx = sum((t - mt) ** 2 for t in ts_)
        b = sum((t - mt) * (v - mv) for t, v in zip(ts_, vals)) / sxx
        return [v - (mv + b * (t - mt)) for t, v in zip(ts_, vals)]

    r = pearson(resid(xs), resid(ys))
    return None if r is None else round(r, 3)


def hourly(seg, allrows):
    """Bucket by BUCKET_S: kalloc increment (last measured - first measured) and mean of activity cols."""
    t0, t1 = seg[0][0], seg[-1][0]
    k = defaultdict(list)
    for t, r in seg:
        k[int(t // BUCKET_S)].append(r["kalloc1024_gb"])
    a = defaultdict(lambda: defaultdict(list))
    for t, r in allrows:
        if t0 <= t <= t1:
            h = int(t // BUCKET_S)
            for c in COLS:
                v = r.get(c)
                if isinstance(v, (int, float)):
                    a[h][c].append(v)
    hours = sorted(h for h in k if h in a)
    out = []
    prev_last = None
    for h in hours:
        first = prev_last if prev_last is not None else k[h][0]
        last = k[h][-1]
        prev_last = last
        row = {"hour": h, "dk": last - first}
        for c in COLS:
            vs = a[h][c]
            row[c] = sum(vs) / len(vs) if vs else None
        out.append(row)
    return out


def main():
    rows, allrows = load_rows()
    report = []
    for seg in segments(rows):
        tt = [t for t, _ in seg]
        gg = [r["kalloc1024_gb"] for _, r in seg]
        hrs = hourly(seg, allrows)[1:]  # first hour has no predecessor increment
        corr = {}
        for c in COLS:
            pairs = [(h[c], h["dk"]) for h in hrs if h[c] is not None]
            r = pearson([p[0] for p in pairs], [p[1] for p in pairs])
            corr[c] = None if r is None else round(r, 3)
        report.append(
            {
                "first": datetime.fromtimestamp(tt[0], timezone.utc).strftime(
                    "%Y-%m-%dT%H:%MZ"
                ),
                "last": datetime.fromtimestamp(tt[-1], timezone.utc).strftime(
                    "%Y-%m-%dT%H:%MZ"
                ),
                "samples": len(seg),
                "hours": len(hrs),
                "gb_first": gg[0],
                "gb_last": gg[-1],
                "days": round((tt[-1] - tt[0]) / 86400, 2),
                "slope_gb_day": None
                if slope(tt, gg) is None
                else round(slope(tt, gg), 3),
                "bucket_hours": BUCKET_S / 3600,
                "r_hourly_increment_vs": corr,
                "r_detrended_cumulative_vs": {
                    c: detrended_cumulative_r(seg, allrows, c) for c in COLS
                },
            }
        )
    if "--json" in sys.argv:
        print(json.dumps(report, indent=1))
        return
    for s in report:
        print(
            f"{s['first']} -> {s['last']}  n={s['samples']} h={s['hours']}  "
            f"{s['gb_first']:.2f} -> {s['gb_last']:.2f} GB over {s['days']} d  "
            f"slope {s['slope_gb_day']} GB/day"
        )
        print(
            "   r(hourly dk, col): "
            + "  ".join(f"{c}={v}" for c, v in s["r_hourly_increment_vs"].items())
        )
        print(
            "   r(detrended level, detrended cumulative col): "
            + "  ".join(f"{c}={v}" for c, v in s["r_detrended_cumulative_vs"].items())
        )


if __name__ == "__main__":
    main()
