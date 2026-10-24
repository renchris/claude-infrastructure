#!/usr/bin/env python3
import json, sys, collections
from datetime import datetime, timezone, timedelta

cut = (
    datetime(2026, 10, 23, 23, 59, tzinfo=timezone.utc) - timedelta(days=7)
).isoformat()
rows = [json.loads(l) for l in open("/tmp/usage-audit/lever-subagents/subagents.jsonl")]; K = set(open("/tmp/usage-audit/lever-subagents/keep_paths.txt").read().split()); rows = [r for r in rows if r["path"] in K]
rows = [r for r in rows if r["t_first"] and r["t_first"] >= cut[:19]]
by = collections.defaultdict(list)
for r in rows:
    by[(r["acct"], r["agentType"])].append(r)
    by[("ALL", r["agentType"])].append(r)


def pct(xs, p):
    xs = sorted(xs)
    return xs[min(len(xs) - 1, int(p * len(xs)))] if xs else 0


# weighted input-equivalent: in*1 + cc*1.25 + cr*0.1 + out*5  (Opus API price ratios; estimate)
print(
    f"{'acct':5} {'agentType':28} {'n':>5} {'req':>7} {'first_mean':>10} {'first_p50':>9} {'first_p90':>9} {'inSide_M':>9} {'cc_M':>7} {'cr_M':>8} {'out_M':>7} {'wEq_M':>8} {'wEq/slot_k':>10}"
)
keys = sorted(
    by,
    key=lambda k: (
        k[0] != "ALL",
        k[0],
        -sum(r["cc"] * 1.25 + r["cr"] * 0.1 + r["inp"] + r["out"] * 5 for r in by[k]),
    ),
)
for k in keys:
    rs = [r for r in by[k] if r["first"] is not None]
    if not rs:
        continue
    n = len(rs)
    req = sum(r["nreq"] for r in rs)
    fs = [r["first"] for r in rs]
    ins = sum(r["inp"] + r["cc"] + r["cr"] for r in rs)
    cc = sum(r["cc"] for r in rs)
    cr = sum(r["cr"] for r in rs)
    out = sum(r["out"] for r in rs)
    w = sum(r["inp"] + r["cc"] * 1.25 + r["cr"] * 0.1 + r["out"] * 5 for r in rs)
    if n < 3 and k[0] != "ALL":
        continue
    print(
        f"{k[0]:5} {k[1][:28]:28} {n:5} {req:7} {sum(fs) / n / 1e3:9.1f}k {pct(fs, 0.5) / 1e3:8.1f}k {pct(fs, 0.9) / 1e3:8.1f}k {ins / 1e6:9.1f} {cc / 1e6:7.1f} {cr / 1e6:8.1f} {out / 1e6:7.2f} {w / 1e6:8.1f} {w / n / 1e3:10.1f}"
    )
print("rows", len(rows), "cut", cut)
