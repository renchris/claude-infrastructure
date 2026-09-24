#!/usr/bin/env python3
"""Side requests (prompt suggestion, away summary, titles, goal evaluator, hooks, compaction forks):
spend that Claude Code counts in per-session cost-state but never writes to a transcript.

Run:  python3 <dir>/scripts/synth_side_requests.py
Reads: data/selfcheck_cost_state.txt (check_cost_state.py, 812 sessions started in the window)
Writes: data/synth_side_requests.json

Method (ESTIMATED): per model, cost-state minus extract for uncached input and cache reads; Haiku in
full (it never appears in transcripts). Opus 5.5 / Fable cache-read deltas are negative (their
cost-state snapshots lag live sessions, EXTRACT.md L2) and are floored at 0. The 812 sessions hold
35.73B of the fleet's 40.95B transcript cache-read tokens, so fleet totals scale by 40.95/35.73.
"""

import json, os, re

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
txt = open(os.path.join(BASE, "data", "selfcheck_cost_state.txt")).read()
PRICE = {
    "claude-opus-5": (5.0, 0.1),
    "claude-opus-5[1m]": (5.0, 0.1),
    "claude-opus-5-5": (4.0, 0.05),
    "claude-opus-5-5[1m]": (4.0, 0.05),
    "claude-fable-5-1": (10.0, 0.025),
    "claude-sonnet-5": (2.0, 0.1),
    "claude-opus-4-8": (5.0, 0.1),
    "claude-haiku-4-5-20251001": (1.0, 0.1),
}
cs, ex = {}, {}
for line in txt.splitlines():
    m = re.match(
        r"\s+(claude-\S+)\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)\s+\|\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)",
        line,
    )
    if not m:
        continue
    k = m.group(1)
    base = k.replace("[1m]", "")
    v = [float(x) for x in m.groups()[1:]]
    c = cs.setdefault(base, [0, 0, 0, 0])
    e = ex.setdefault(base, [0, 0, 0, 0, 0])
    for i in range(4):
        c[i] += v[i]  # in, out, cr, cc (M tokens)
    for i in range(5):
        e[i] += v[4 + i]  # in, out_final, out_est, cr, cc
res = {"per_model": {}, "own": 0.0, "o55": 0.0}
for base, c in cs.items():
    e = ex[base]
    p_in, crm = PRICE[base]
    if base.startswith("claude-haiku"):
        own = c[0] * p_in + c[3] * 1.25 * p_in + c[1] * 5.0 + c[2] * crm * p_in
        o55 = own  # Haiku side queries stay on Haiku; not re-priced
    else:
        d_in = max(c[0] - e[0], 0.0)
        d_cr = max(c[2] - e[3], 0.0)
        own = d_in * p_in + d_cr * crm * p_in
        o55 = d_in * 4.0 + d_cr * 0.05 * 4.0
    res["per_model"][base] = {"usd_own": own, "usd_o55": o55}
    res["own"] += own
    res["o55"] += o55
scale = 40952.17 / 35734.38
res["scale_to_fleet"] = scale
res["fleet_own"] = res["own"] * scale
res["fleet_o55"] = res["o55"] * scale
res["fleet_share_own"] = res["fleet_own"] / 32517.42
json.dump(
    res, open(os.path.join(BASE, "data", "synth_side_requests.json"), "w"), indent=1
)
print(
    {
        k: (
            round(v, 1)
            if isinstance(v, float)
            else {m: {a: round(b, 1) for a, b in x.items()} for m, x in v.items()}
        )
        for k, v in res.items()
    }
)
