#!/usr/bin/env python3
"""Reviewer: forward-looking gross saving on the 2.1.293 population (wk-0, wk-1), split b13 / rest,
under multiplicative and additive turn-penalty models, plus break-even turn ratio."""

import collections
import json
import runpy

g = runpy.run_path(
    "/tmp/lean-idle/workflow-lean/review-numbers/savings.py", run_name="lib"
)
elig, week, strip_prefix, runs = g["elig"], g["week"], g["strip_prefix"], g["runs"]
WW, WO, PERREQ = 0.245, 0.404, 0.0006


def sv(s, wr, D, turns=1.195, add=None, perreq=True):
    D = min(D, max(0, s["first_cw"] + s["first_cr"] + s["first_in"] - 6500))
    pr = PERREQ if perreq else 0
    base = (WW * s["cw"] + wr * s["cr"] + WO * s["out"]) / 1e6 + pr * s["nreq"]
    cw, cr = strip_prefix(s, D)
    resid = (WW * cw + wr * cr + WO * s["out"]) / 1e6 + pr * s["nreq"]
    if add is None:
        lean = resid * turns
    else:  # additive: `add` extra requests, each at the slot's mean residual request cost
        lean = resid * (1 + add / s["nreq"])
    return base - lean


rec = [s for s in elig if week(s["first_ts"]) <= 1]
isb = lambda s: (runs[s["runId"]].get("name") or "").startswith("b13")
print(
    "wk0-1 eligible slots",
    len(rec),
    "b13",
    sum(map(isb, rec)),
    "rest",
    sum(not isb(s) for s in rec),
)
for grp, ss in (
    ("b13", [s for s in rec if isb(s)]),
    ("rest", [s for s in rec if not isb(s)]),
):
    n = len(ss)
    mr = sum(s["nreq"] for s in ss) / n
    print(f"  {grp}: slots {n} mean nreq {mr:.1f} runs {len({s['runId'] for s in ss})}")
print("per-week (mean of wk-0, wk-1) gross saving, pp/week fleet:")
for D in (39085, 42565):
    for wr in (0.0048, 0.0057, 0.0076):
        row = []
        for label, kw in (
            ("x1.195", dict(turns=1.195)),
            ("x1.0", dict(turns=1.0)),
            ("+1 req", dict(add=1)),
            ("+3 req", dict(add=3)),
            ("x1.195 no-perreq", dict(turns=1.195, perreq=False)),
        ):
            b = sum(sv(s, wr, D, **kw) for s in rec if isb(s)) / 2
            r = sum(sv(s, wr, D, **kw) for s in rec if not isb(s)) / 2
            row.append(f"{label}: b13 {b:5.1f} rest {r:5.1f}")
        print(f" D={D} reads={wr}: " + " | ".join(row))
# break-even multiplicative ratio for rest and b13
for grp, ss in (
    ("b13", [s for s in rec if isb(s)]),
    ("rest", [s for s in rec if not isb(s)]),
):
    for wr in (0.0057, 0.0076):
        lo, hi = 1.0, 3.0
        for _ in range(40):
            mid = (lo + hi) / 2
            if sum(sv(s, wr, 42565, turns=mid) for s in ss) > 0:
                lo = mid
            else:
                hi = mid
        print(f"break-even turn ratio {grp} reads {wr}: {lo:.3f}")
# by nreq bucket, rest only
bk = collections.defaultdict(lambda: [0, 0.0, 0.0])
for s in rec:
    if isb(s):
        continue
    b = (
        "1-5"
        if s["nreq"] <= 5
        else "6-15"
        if s["nreq"] <= 15
        else "16-40"
        if s["nreq"] <= 40
        else "41-100"
        if s["nreq"] <= 100
        else ">100"
    )
    bk[b][0] += 1
    bk[b][1] += sv(s, 0.0057, 42565) / 2
    bk[b][2] += sv(s, 0.0057, 42565, add=1) / 2
print(
    "rest by nreq bucket [slots, pp/wk x1.195, pp/wk +1req] (reads .0057, D 42.6k):",
    {k: [v[0], round(v[1], 2), round(v[2], 2)] for k, v in sorted(bk.items())},
)
