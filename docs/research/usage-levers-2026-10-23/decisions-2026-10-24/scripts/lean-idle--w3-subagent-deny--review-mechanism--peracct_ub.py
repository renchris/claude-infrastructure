#!/usr/bin/env python3
"""Upper bound per account: charge a poll-loop call's wrong-deny cost to EVERY account dir holding a copy.
Usage: python3 -I peracct_ub.py <joined.json> <bash.jsonl> <days>"""
import json, math, sys
from collections import defaultdict
J = json.load(open(sys.argv[1])); wk = 7.0 / float(sys.argv[3])
READ = (0.0057, 0.0076); WRITE, OUT = 0.245, 0.404
K = dict(low=dict(r=READ[0], w=500, o=60), high=dict(r=READ[1], w=1234, o=300))
rc = lambda ctx, k: (ctx * k["r"] + k["w"] * WRITE + k["o"] * OUT) / 1e6
pl = {r["id"]: r for r in J if r["why"] == "poll-loop" and r["rt"] is not None}
acc = defaultdict(set)
for l in open(sys.argv[2]):
    r = json.loads(l)
    if r["id"] in pl: acc[r["id"]].add(r["acct"])
w = defaultdict(lambda: [0.0, 0.0])
for i, r in pl.items():
    if r["rt"] > 270: continue
    for a in acc[i]:
        w[a][0] += rc(r["ctx"], K["low"]) * wk; w[a][1] += rc(r["ctx"], K["high"]) * wk
for a, v in sorted(w.items()): print("%-10s wrong pp/wk upper bound %.3f-%.3f" % (a, v[0], v[1]))
