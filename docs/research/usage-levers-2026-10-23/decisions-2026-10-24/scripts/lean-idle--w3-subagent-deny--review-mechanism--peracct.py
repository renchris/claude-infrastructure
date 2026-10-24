#!/usr/bin/env python3
"""Per-account poll-loop deny pricing with variants.py's model (one deny per call). Read-only.
Usage: python3 -I peracct.py <joined.json> <days> [classes,comma]"""
import json, math, sys
from collections import defaultdict
J = json.load(open(sys.argv[1])); wk = 7.0 / float(sys.argv[2])
cls = set((sys.argv[3] if len(sys.argv) > 3 else "poll-loop").split(","))
READ = (0.0057, 0.0076); WRITE, OUT = 0.245, 0.404
K = dict(low=dict(r=READ[0], w=500, o=60), high=dict(r=READ[1], w=1234, o=300))
rc = lambda ctx, k: (ctx * k["r"] + k["w"] * WRITE + k["o"] * OUT) / 1e6
acc = defaultdict(lambda: defaultdict(float))
for r in J:
    if r["why"] not in cls or r["rt"] is None: continue
    kk = math.ceil(r["rt"] / 270.0) if r["rt"] > 270 else 1
    polls = kk if r["why"] == "poll-loop" else 1 + kk
    if r["rt"] <= 270: polls = 1 if r["why"] == "poll-loop" else 2
    for kn, k in K.items():
        c = polls * rc(r["ctx"], k)
        a = acc[r["acct"]]
        a["cost_" + kn] += c * wk
        if r["rt"] <= 270: a["wrong_" + kn] += c * wk
        if r["rebuilt"]:
            for comp in (1.0, 0.5):
                a["save_%s_c%.1f" % (kn, comp)] += comp * min(r["ncc"], r["ctx"]) * (WRITE - k["r"]) / 1e6 * wk
    acc[r["acct"]]["n"] += 1
    acc[r["acct"]]["reb"] += r["rebuilt"]
for a, v in sorted(acc.items()):
    print("%-10s calls %4d rebuilt %3d | wrong pp/wk %.3f-%.3f | net hi-cost c1.0 %.2f c0.5 %.2f | net lo-cost c1.0 %.2f" % (
        a, v["n"], v["reb"], v["wrong_low"], v["wrong_high"],
        v["save_high_c1.0"] - v["cost_high"], v["save_high_c0.5"] - v["cost_high"], v["save_low_c1.0"] - v["cost_low"]))
