#!/usr/bin/env python3
# Orientation phase = successor requests before its first action (Edit/Write/NotebookEdit/Agent/Task/Workflow)
# or the end of turn 1, whichever is first; capped at 30. Everything it costs beyond request 0 is overhead an
# idle-triggered recycle adds (the no-recycle session runs no such turn). usage: python3 -I v8_orient.py <verify_dir> <sim_life>
import json, os, random, statistics as st, sys
V, SL = sys.argv[1], int(sys.argv[2])
WR, RD, OUT, INP = 0.245e-6, 0.0067e-6, 0.404e-6, 389e-6
PW = 155.0
ACT = {"Edit", "MultiEdit", "Write", "NotebookEdit", "Agent", "Task", "Workflow"}
P = [json.loads(l) for l in open(os.path.join(V, "v3.pairs.jsonl"))]
P = [p for p in P if "win" in p]
def boot(xs, n=2000):
    random.seed(11); b = sorted(sum(random.choice(xs) for _ in xs) / len(xs) for _ in range(n)); return b[int(.05*n)]*PW, b[int(.95*n)]*PW
def cost(p, life_mode, proxy=True):
    per = p["win"]["per"]
    k = min(p["t1_end"], len(per), 30)
    for x in per[:k]:
        if ACT & set(x["names"]):
            k = x["i"] + 1  # the acting request itself is the first non-orientation request
            k = max(1, k - 1) if x["i"] > 0 else 1
            break
    life = {"pol": p["win"]["life_pol"], "end": p["win"]["end"], "sim": SL}[life_mode]
    c = 0.0
    for x in per[1:k]:
        c += x["cr"] * RD + x["cw"] * WR + x["out"] * OUT + (x["inp"] * INP if proxy else 0)
    last = per[k - 1]
    grow = max(0, last["ctx"] + last["out"] - per[0]["ctx"]) if k > 1 else 0
    c += grow * RD * max(0, life - k)
    return c, grow, k
for nm, X in (("all successors", P), ("pred idle>=15m & 150-350k", [p for p in P if (p["pred_gap"] or 0) >= 900 and 150e3 <= p["pred_ctx"] < 350e3])):
    for lm in ("sim", "pol", "end"):
        for proxy in (True, False):
            v = [cost(p, lm, proxy) for p in X]
            c = [a for a, _, _ in v]
            lo, hi = boot(c)
            print("%-28s life=%s proxy=%s n=%d orient requests median %d mean %.1f growth median %.0f mean %.0f -> %.2f pp/week [%.2f-%.2f]" % (
                nm, lm if lm != "sim" else "sim(%d)" % SL, proxy, len(X), st.median(k for _, _, k in v), sum(k for _, _, k in v) / len(v),
                st.median(g for _, g, _ in v), sum(g for _, g, _ in v) / len(v), sum(c) / len(c) * PW, lo, hi))
f = [p["win"]["per"][0] for p in P]
print("successor request 0: cw median %.0f, cr median %.0f, ctx median %.0f, out median %.0f" % (
    st.median(x["cw"] for x in f), st.median(x["cr"] for x in f), st.median(x["ctx"] for x in f), st.median(x["out"] for x in f)))
