#!/usr/bin/env python3
# Orientation-only turn 1 (no Edit/Write in turn 1, turn 1 <= 30 requests, then >= 60 s before the next user
# message): its full cost beyond request 0, under life = sim replay (fixed), life_pol, life_end; with and
# without the 389/Mtok per-request input proxy. usage: python3 -I v9_oo.py <verify_dir> <sim_life>
import json, os, random, statistics as st, sys
V, SL = sys.argv[1], int(sys.argv[2])
WR, RD, OUT, INP = 0.245e-6, 0.0067e-6, 0.404e-6, 389e-6
PW = 155.0
P = [json.loads(l) for l in open(os.path.join(V, "v3.pairs.jsonl"))]
P = [p for p in P if "win" in p]
OO = [p for p in P if not p["t1_edit"] and 1 <= p["t1_end"] <= 30 and (p["t1_next_gap"] or 0) >= 60]
NOAG = [p for p in OO if not any(nm in ("Agent", "Task", "Workflow") for x in p["win"]["per"][:p["t1_end"]] for nm in x["names"])]
def boot(xs, n=2000):
    random.seed(11); b = sorted(sum(random.choice(xs) for _ in xs) / len(xs) for _ in range(n)); return b[int(.05*n)]*PW, b[int(.95*n)]*PW
def cost(p, lm, proxy):
    per = p["win"]["per"]; k = min(p["t1_end"], len(per))
    life = {"pol": p["win"]["life_pol"], "end": p["win"]["end"], "sim": SL}[lm]
    c = sum(x["cr"] * RD + x["cw"] * WR + x["out"] * OUT + (x["inp"] * INP if proxy else 0) for x in per[1:k])
    last = per[k - 1]
    c += max(0, last["ctx"] + last["out"] - per[0]["ctx"]) * RD * max(0, life - k)
    return c
for nm, X in (("orientation-only turn 1", OO), ("  ... and no Agent/Workflow launch in turn 1", NOAG),
              ("  ... policy-like (pred idle>=15m, 150-350k)", [p for p in OO if (p["pred_gap"] or 0) >= 900 and 150e3 <= p["pred_ctx"] < 350e3])):
    for lm in ("sim", "pol", "end"):
        row = []
        for proxy in (True, False):
            c = [cost(p, lm, proxy) for p in X]; lo, hi = boot(c)
            row.append("%.2f [%.2f-%.2f]" % (sum(c) / len(c) * PW, lo, hi))
        print("%-48s n=%3d life=%-7s with input proxy %s | without %s" % (nm, len(X), lm if lm != "sim" else "sim%d" % SL, row[0], row[1]))
