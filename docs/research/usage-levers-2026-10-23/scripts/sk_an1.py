#!/usr/bin/env python3
"""Skeptic analysis 1: dedup check, first-request size and cache split per agentType."""

import json, collections, statistics as st

rows = [json.loads(l) for l in open("/tmp/usage-audit/skeptic-subagents/sk_rows.jsonl")]
print("rows (files with >=1 request in window):", len(rows))
by = collections.defaultdict(list)
for r in rows:
    by[r["aid"]].append(r)
dups = {k: v for k, v in by.items() if len(v) > 1}
print("unique aids:", len(by), "aids in >1 file:", len(dups))
same_usage = sum(1 for v in dups.values() if all(x["tot"] == v[0]["tot"] for x in v))
same_acct = sum(1 for v in dups.values() if len({x["acct"] for x in v}) < len(v))
pairs = collections.Counter(tuple(sorted(x["acct"] for x in v)) for v in dups.values())
print(
    "dup groups with identical window usage:",
    same_usage,
    "| groups with 2 copies in same acct:",
    same_acct,
)
print("dup acct pairs:", dict(pairs.most_common(8)))
intm = sum(
    1 for v in dups.values() if sum(1 for x in v if float(x["mtime"]).is_integer()) == 1
)
print("dup groups with exactly one integer-mtime copy:", intm)

# keep one copy per aid: prefer non-integer mtime
keep = []
for k, v in by.items():
    v2 = sorted(v, key=lambda x: (float(x["mtime"]).is_integer(), -x["mtime"]))
    keep.append(v2[0])
json.dump(
    [r["path"] for r in keep],
    open("/tmp/usage-audit/skeptic-subagents/sk_keep.json", "w"),
)

W = lambda t: t[0] + t[1] * 1.25 + t[2] * 0.1 + t[3] * 5
W1h = lambda t: t[0] + t[4] * 1.25 + t[5] * 2.0 + t[2] * 0.1 + t[3] * 5


def pct(a, q):
    a = sorted(a)
    return a[min(len(a) - 1, int(q * len(a)))] if a else 0


print()
print(
    f"{'type':22} {'n':>5} {'req':>7} {'first_p50':>9} {'p10':>7} {'p90':>7} | first req: cr_share_p50 cr_share_mean frac_cr>50% | 1h_share_of_cc(all req) | wEq_M wEq1h_M"
)
agg = collections.defaultdict(list)
for r in keep:
    if not r["first_in_window"]:
        continue
    agg[r["agentType"]].append(r)
for t, rs in sorted(agg.items(), key=lambda kv: -len(kv[1])):
    if len(rs) < 20:
        continue
    f = [sum(r["first"][:3]) for r in rs]
    crs = [r["first"][2] / max(1, sum(r["first"][:3])) for r in rs]
    cc_all = sum(r["tot"][1] for r in rs)
    cc1h = sum(r["tot"][5] for r in rs)
    req = sum(r["nreq"] for r in rs)
    w = sum(W(r["tot"]) for r in rs)
    w1 = sum(W1h(r["tot"]) for r in rs)
    print(
        f"{t:22} {len(rs):5} {req:7} {pct(f, 0.5):9} {pct(f, 0.1):7} {pct(f, 0.9):7} | {pct(crs, 0.5):.2f} {st.mean(crs):.2f} {sum(1 for c in crs if c > 0.5) / len(crs):.2f} | {cc1h / max(1, cc_all):.2f} | {w / 1e6:7.1f} {w1 / 1e6:7.1f}"
    )
