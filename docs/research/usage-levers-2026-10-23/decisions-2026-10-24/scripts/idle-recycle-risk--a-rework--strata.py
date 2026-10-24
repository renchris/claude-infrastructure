#!/usr/bin/env python3
# Rework by stratum: predecessor context at recycle and idle gap before the recycling turn.
# usage: python3 -I strata.py <workdir> <N> <P>  (reads analysis.N*.P*.json, analysis2.N*.P*.json, ev.*, pairs)
import glob, json, os, sys
from datetime import datetime

W, N, P = sys.argv[1], sys.argv[2], sys.argv[3]
ep = lambda s: (
    datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp() if s else None
)
E = {}
for f in glob.glob(os.path.join(W, "ev.*.jsonl")):
    for l in open(f):
        e = json.loads(l)
        E[e["path"]] = e
gap = {}
for l in open(os.path.join(W, "pairs.jsonl")):
    p = json.loads(l)
    q = E.get(p["pred_path"] or "")
    if not q:
        continue
    cut = ep(p["brief_ts"])
    R = q["reqs"]
    pend = len([r for r in R if (ep(r["ts"]) or 0) < cut])
    pr = [x for x in q["prompts"] if 0 < x[1] < pend]
    if pr:
        i = pr[-1][1]
        gap[p["succ"]] = (ep(R[i]["ts"]) or 0) - (ep(R[i - 1]["ts"]) or 0)
A1 = {
    r["succ"]: r
    for r in json.load(open(os.path.join(W, "analysis.N%s.P%s.json" % (N, P))))["rows"]
}
A2 = {
    r["succ"]: r
    for r in json.load(open(os.path.join(W, "analysis2.N%s.P%s.json" % (N, P))))["rows"]
}
S = [(k, A1[k], A2[k]) for k in A1 if k in A2]
strata = {
    "pred ctx 150-350k": lambda k, a, b: 150000 <= a["pred_ctx"] < 350000,
    "pred ctx >=350k": lambda k, a, b: a["pred_ctx"] >= 350000,
    "idle >=15m before recycle": lambda k, a, b: gap.get(k, 0) >= 900,
    "idle <15m before recycle": lambda k, a, b: k in gap and gap[k] < 900,
    "idle>=15m & ctx 150-350k": lambda k, a, b: (
        gap.get(k, 0) >= 900 and 150000 <= a["pred_ctx"] < 350000
    ),
}
print("N=%s P=%s  (pp/week = mean per recycle x 155)" % (N, P))
for nm, f in strata.items():
    X = [(a, b) for k, a, b in S if f(k, a, b)]
    if not X:
        continue
    n = len(X)
    t1 = sum(a["wr_pp"] + a["rd_end_pp"] + a["xreq_pp"] for a, b in X) / n * 155
    t2 = sum(b["t2_pp_end"] for a, b in X) / n * 155
    t2p = sum(b["t2_pp_pol"] for a, b in X) / n * 155
    t3 = sum(b["t3_pp_end"] for a, b in X) / n * 155
    print(
        "  %-28s n=%3d  T1 %.2f  T2 %.2f (policy-life %.2f)  T3 %.2f  T2 tok/recycle %.0f"
        % (nm, n, t1, t2, t2p, t3, sum(b["t2_tok"] for a, b in X) / n)
    )
