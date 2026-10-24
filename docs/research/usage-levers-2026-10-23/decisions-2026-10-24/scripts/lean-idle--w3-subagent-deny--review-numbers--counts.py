#!/usr/bin/env python3
"""Re-derive the load-bearing counts. Usage: python3 -I counts.py broad_v.jsonl"""

import json, sys, statistics as st
from collections import Counter, defaultdict

B = [json.loads(l) for l in open(sys.argv[1])]
for r in B:
    r["rt"] = (r["tres"] - r["tl"]) if r.get("tres") is not None else None
    r["gap"] = (r["nt0"] - r["t"]) if r.get("nt0") is not None else None
    r["reb"] = bool(
        r.get("gap") is not None
        and r["ctx"] > 0
        and r["ncc"] >= 0.5 * r["ctx"]
        and r["gap"] > 300
    )
    # alternative rebuild def: next request reads < 20% of ctx and writes >= 50%
    r["reb2"] = bool(
        r.get("gap") is not None
        and r["ctx"] > 0
        and r["ncc"] >= 0.5 * r["ctx"]
        and r["ncr"] < 0.5 * r["ctx"]
    )
N = [r for r in B if r["why"]]
print(
    "broad",
    len(B),
    "narrow",
    len(N),
    "agents",
    len(set(r["file"].rsplit("/", 1)[1] for r in N)),
)
res = [r for r in N if r["rt"] is not None]
sh = [r for r in res if r["rt"] <= 270]
print(
    "narrow resolved",
    len(res),
    "short<=270",
    len(sh),
    "share %.3f" % (len(sh) / len(res)),
)
for w in ("poll-loop", "long-runner", "waiter", "long-sleep"):
    s = [r for r in N if r["why"] == w]
    rs = [r for r in s if r["rt"] is not None]
    k = [r for r in rs if r["rt"] <= 270]
    rb = [r for r in s if r["reb"]]
    print(
        "  %-11s n=%d resolved=%d false=%.3f rebuilt=%d (%.1fM) reb2=%d"
        % (
            w,
            len(s),
            len(rs),
            len(k) / max(1, len(rs)),
            len(rb),
            sum(min(r["ncc"], r["ctx"]) for r in rb) / 1e6,
            sum(r["reb2"] for r in s),
        )
    )
rb = [r for r in N if r["reb"]]
print(
    "narrow rebuilt",
    len(rb),
    "%.1fM" % (sum(min(r["ncc"], r["ctx"]) for r in rb) / 1e6),
    "| using ncc not min: %.1fM" % (sum(r["ncc"] for r in rb) / 1e6),
)
ab = [r for r in B if r["reb"]]
print(
    "broad rebuilt", len(ab), "%.1fM" % (sum(min(r["ncc"], r["ctx"]) for r in ab) / 1e6)
)
print(
    "runtime deciles narrow",
    [round(x) for x in st.quantiles([r["rt"] for r in res], n=10)],
)
for lo, hi in ((-1e9, 270), (270, 300), (300, 360), (360, 1e12)):
    s = [r for r in res if lo < r["rt"] <= hi]
    print("  rt %s..%s n=%d rebuilt=%d" % (lo, hi, len(s), sum(r["reb"] for r in s)))
# double counting: >1 broad/narrow call in the same issuing request
byreq = defaultdict(list)
for r in N:
    byreq[r["mid"]].append(r)
multi = {k: v for k, v in byreq.items() if len(v) > 1}
print(
    "narrow issuing requests",
    len(byreq),
    "with >1 narrow call",
    len(multi),
    "calls in them",
    sum(len(v) for v in multi.values()),
    "rebuilds double-counted",
    sum(
        sum(x["reb"] for x in v) - (1 if any(x["reb"] for x in v) else 0)
        for v in multi.values()
    ),
)
byreqB = defaultdict(list)
for r in B:
    byreqB[r["mid"]].append(r)
print(
    "broad issuing requests",
    len(byreqB),
    "with >1 broad call",
    sum(1 for v in byreqB.values() if len(v) > 1),
    "broad rebuild double-count",
    sum(
        sum(x["reb"] for x in v) - (1 if any(x["reb"] for x in v) else 0)
        for v in byreqB.values()
    ),
)
# model mix
print("narrow model mix", Counter(r["model"] for r in N).most_common(6))
print("narrow rebuilt model mix", Counter(r["model"] for r in rb).most_common(6))
# write tier on rebuilds
print(
    "rebuild next-write tiers: 5m %.1fM 1h %.1fM"
    % (sum(r["ncc5"] for r in rb) / 1e6, sum(r["ncc1"] for r in rb) / 1e6)
)
print("narrow by acct (chosen copy)", Counter(r["acct"] for r in N))
print(
    "narrow ctx mean %.1fk median %.1fk"
    % (st.mean(r["ctx"] for r in res) / 1e3, st.median(r["ctx"] for r in res) / 1e3)
)
print(
    "rt None narrow",
    sum(1 for r in N if r["rt"] is None),
    "next None narrow",
    sum(1 for r in N if r.get("nt0") is None),
)
json.dump(
    [
        {
            k: r.get(k)
            for k in (
                "id",
                "acct",
                "file",
                "mid",
                "t",
                "to",
                "why",
                "rt",
                "ctx",
                "ncc",
                "ncc5",
                "ncc1",
                "ncr",
                "gap",
                "reb",
                "nb",
                "nt",
                "model",
                "bgid",
                "intr",
                "err",
                "cmd",
                "rhead",
            )
        }
        for r in B
    ],
    open("/tmp/lean-idle/w3-subagent-deny/review-numbers/myjoined.json", "w"),
)
