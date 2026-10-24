#!/usr/bin/env python3
"""Re-price the poll-loop deny with the /goal-gate collision: for poll-loop calls made while the parent
had a live goal AND the loop is while/until (the shape validate-bash's goal gate denies when
backgrounded), add one extra denied request and scale the saving by goal_comply. variants.py's model
otherwise. Usage: python3 -I goal_adjust.py <joined.json> <bash.jsonl> <days>"""
import json, sys, math, re, subprocess
from datetime import datetime
from collections import defaultdict
def T(s):
    try: return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except Exception: return None
J = [r for r in json.load(open(sys.argv[1])) if r["why"] == "poll-loop" and r["rt"] is not None]
wk = 7.0 / float(sys.argv[3])
ids = {r["id"] for r in J}
tps = defaultdict(set)
for l in open(sys.argv[2]):
    r = json.loads(l)
    if r["id"] in ids and r.get("tp") not in (None, "-"): tps[r["id"]].add(r["tp"])
ev = {}
for p in set(x for s in tps.values() for x in s):
    out = subprocess.run(["/usr/bin/grep", "-a", "goal_status", p], capture_output=True, timeout=60).stdout.decode("utf-8", "replace")
    e = []
    for line in out.splitlines():
        try: d = json.loads(line)
        except Exception: continue
        a = d.get("attachment") or {}
        if d.get("type") == "attachment" and a.get("type") == "goal_status":
            e.append((T(d.get("timestamp") or "") or 0, (a.get("met") is False) and not a.get("failed")))
    ev[p] = sorted(e)
def live(i, t):
    for p in tps.get(i, ()):
        st = False
        for te, lv in ev.get(p, []):
            if te <= t: st = lv
        if st: return True
    return False
WU = re.compile(r"(^|[^\w])(while|until)\s")
READ = (0.0057, 0.0076); WRITE, OUT = 0.245, 0.404
K = dict(low=dict(r=READ[0], w=500, o=60), high=dict(r=READ[1], w=1234, o=300))
rc = lambda ctx, k: (ctx * k["r"] + k["w"] * WRITE + k["o"] * OUT) / 1e6
hit = [r for r in J if live(r["id"], r["t"]) and WU.search(r["cmd"])]
print("poll-loop calls: %d; under live goal AND while/until: %d (rebuilt %d)" % (len(J), len(hit), sum(r["rebuilt"] for r in hit)))
hs = {r["id"] for r in hit}
for kn, k in K.items():
    for comply in (1.0, 0.5):
        for gc in (1.0, 0.5, 0.0):
            s = c = 0.0
            for r in J:
                kk = math.ceil(r["rt"] / 270.0) if r["rt"] > 270 else 1
                polls = kk if r["rt"] > 270 else 1
                extra = 1 if r["id"] in hs else 0
                c += (polls + extra) * rc(r["ctx"], k)
                cp = comply * (gc if r["id"] in hs else 1.0)
                if r["rebuilt"]: s += cp * min(r["ncc"], r["ctx"]) * (WRITE - k["r"]) / 1e6
            print("  %s comply %.1f, goal-session comply %.1f: net %.2f pp/wk (save %.2f, cost %.2f)" % (kn, comply, gc, (s - c) * wk, s * wk, c * wk))
