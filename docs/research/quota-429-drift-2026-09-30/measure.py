#!/usr/bin/env python3
"""How far does an account's quota move while its usage endpoint is throttled (HTTP 429)?

Question this answers (backlog row 1c20dc1e92db): claude-accounts excludes a 429-throttled account
from routing even when it holds a minutes-old last-good read. Is the last-good read close enough to
the truth to route on, and for how old a read?

Method:
  throttle events  ~/.claude/logs/claude-accounts.log  `<iso> probe <acct>: 429 poll-throttled ...`
  good reads       ~/.claude/logs/account-utilization.jsonl rows with stale == false (a throttled or
                   errored row is written with stale == true, so these are genuine live reads)
  For each event (acct, t): P = last good read before t, N = first good read after t,
  a = t - P.ts. drift = max over session/weekly/fable of |N - P| in percentage points, skipping a
  bucket whose reset stamp (from P) fell between P.ts and N.ts — that bucket rolled to ~0 and its
  delta is a reset, not drift.

  drift(P, N) spans a + (N.ts - t), which is LONGER than the age the router would actually be
  trusting at t, so it over-states the error of routing on P at t: a conservative bound.

Usage: python3 measure.py [--log PATH] [--util PATH] [--ttl 90] [--md]
"""

import argparse
import bisect
import json
import os
import re
from collections import defaultdict
from datetime import datetime

HOME = os.path.expanduser("~")
EVENT_RE = re.compile(r"^(\S+) probe (\S+): 429 poll-throttled")
BUCKETS = [
    90,
    300,
    600,
    900,
    1800,
    3600,
    None,
]  # upper bounds on a, seconds; None = open
METERS = ("session", "weekly", "fable")


def ts(s):
    return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()


def load_events(path):
    out = []
    with open(path, errors="replace") as f:
        for line in f:
            m = EVENT_RE.match(line)
            if m:
                try:
                    out.append((m.group(2), ts(m.group(1))))
                except ValueError:
                    continue
    return out


def load_good(path):
    by = defaultdict(list)
    with open(path, errors="replace") as f:
        for line in f:
            try:
                d = json.loads(line)
            except json.JSONDecodeError:
                continue
            if d.get("stale") is not False or not d.get("acct") or not d.get("ts"):
                continue
            try:
                d["_t"] = ts(d["ts"])
            except ValueError:
                continue
            by[d["acct"]].append(d)
    for rows in by.values():
        rows.sort(key=lambda r: r["_t"])
    return by


def drift(p, n):
    worst = None
    for m in METERS:
        a, b = p.get(f"{m}_pct"), n.get(f"{m}_pct")
        if a is None or b is None:
            continue
        stamp = p.get(f"{m}_reset_at")
        if stamp:
            try:
                if p["_t"] < ts(stamp) <= n["_t"]:
                    continue  # window rolled between the reads
            except ValueError:
                pass
        d = abs(b - a)
        worst = d if worst is None else max(worst, d)
    return worst


def pct(xs, q):
    if not xs:
        return None
    xs = sorted(xs)
    k = max(0, min(len(xs) - 1, int(round(q * (len(xs) - 1)))))
    return xs[k]


def bucket_of(a):
    for b in BUCKETS:
        if b is None or a <= b:
            return b
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--log", default=os.path.join(HOME, ".claude/logs/claude-accounts.log")
    )
    ap.add_argument(
        "--util", default=os.path.join(HOME, ".claude/logs/account-utilization.jsonl")
    )
    ap.add_argument("--ttl", type=int, default=90)
    ap.add_argument("--md", action="store_true")
    args = ap.parse_args()

    events = load_events(args.log)
    good = load_good(args.util)
    keys = {a: [r["_t"] for r in rows] for a, rows in good.items()}

    per = defaultdict(list)  # bucket -> drifts
    cum = []  # (a, drift) for cumulative ≤ bound stats
    skipped = 0
    for acct, t in events:
        rows, ks = good.get(acct), keys.get(acct)
        if not rows:
            skipped += 1
            continue
        i = bisect.bisect_left(ks, t)
        if i == 0 or i >= len(rows):
            skipped += 1
            continue
        p, n = rows[i - 1], rows[i]
        d = drift(p, n)
        if d is None:
            skipped += 1
            continue
        a = t - p["_t"]
        per[bucket_of(a)].append(d)
        cum.append((a, d))

    def label(b, prev):
        if b is None:
            return f">{prev}s"
        return f"≤{b}s" if prev is None else f"{prev}–{b}s"

    print(
        f"events={len(events)} measured={len(cum)} skipped={skipped} "
        f"(no good read on one side, or no comparable meter)"
    )
    hdr = "| age of last-good read | n | p50 pp | p90 pp | p99 pp | cumulative n (≤ upper) | cumulative p90 pp |"
    print(hdr)
    print("|---|---|---|---|---|---|---|")
    prev = None
    for b in BUCKETS:
        xs = per.get(b, [])
        c = [d for a, d in cum if b is None or a <= b]
        print(
            f"| {label(b, prev)} | {len(xs)} | {pct(xs, 0.5)} | {pct(xs, 0.9)} | {pct(xs, 0.99)} "
            f"| {len(c)} | {pct(c, 0.9)} |"
        )
        prev = b
    at_ttl = [d for a, d in cum if a <= args.ttl]
    print(
        f"\np90 drift at the cache TTL (a ≤ {args.ttl}s): {pct(at_ttl, 0.9)} pp over n={len(at_ttl)}"
    )
    # Largest cumulative bound whose p90 stays under 5pp — the admission rule's input.
    best = None
    for b in BUCKETS:
        if b is None:
            continue
        c = [d for a, d in cum if a <= b]
        if c and pct(c, 0.9) < 5:
            best = b
    print(
        f"largest bound with cumulative p90 < 5pp: {best}s"
        if best
        else "no bound qualifies (cumulative p90 ≥ 5pp everywhere)"
    )


if __name__ == "__main__":
    main()
