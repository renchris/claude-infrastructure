#!/usr/bin/env python3
"""Which narrow calls ran while the PARENT session had a live /goal (goal-state.sh predicate, made
time-aware: the last goal_status attachment at or before the call has met==false and not failed).
Read-only. Usage: python3 -I goal_overlap.py <joined.json> <bash.jsonl>"""
import json, sys, subprocess
from datetime import datetime
from collections import Counter, defaultdict
def T(s):
    try: return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except Exception: return None
J = {r["id"]: r for r in json.load(open(sys.argv[1])) if r["narrow"]}
tps = defaultdict(set)  # id -> parent transcript candidates (all copies)
for l in open(sys.argv[2]):
    r = json.loads(l)
    if r["id"] in J and r.get("tp") and r["tp"] != "-":
        tps[r["id"]].add(r["tp"])
alltp = set(p for s in tps.values() for p in s)
recs = {}
for p in alltp:
    ev = []
    try:
        out = subprocess.run(["/usr/bin/grep", "-a", "goal_status", p], capture_output=True, timeout=60).stdout.decode("utf-8", "replace")
    except Exception:
        out = ""
    for line in out.splitlines():
        try: d = json.loads(line)
        except Exception: continue
        if d.get("type") != "attachment": continue
        a = d.get("attachment") or {}
        if a.get("type") != "goal_status": continue
        t = T(d.get("timestamp") or "")
        if t is None: continue
        live = (a.get("met") is False) and not a.get("failed")
        ev.append((t, live, str(a.get("condition") or "")[:80]))
    recs[p] = sorted(ev)
def live_at(p, t):
    st = False; cond = ""
    for (te, lv, c) in recs.get(p, []):
        if te <= t: st, cond = lv, c
        else: break
    return st, cond
c = Counter(); reb = Counter(); agents = defaultdict(set); conds = Counter()
for i, r in J.items():
    lv = False
    for p in tps.get(i, ()):
        s, cond = live_at(p, r["t"])
        if s: lv = True; conds[cond[:60]] += 1
    k = (r["why"], lv)
    c[k] += 1; reb[k] += bool(r["rebuilt"]); agents[k].add(r["aid"])
print("parent transcripts read:", len(alltp), "with any goal_status attachment:", sum(1 for v in recs.values() if v))
for k in sorted(c): print(k, "calls", c[k], "rebuilt", reb[k], "agents", len(agents[k]))
print("top live goal conditions:", conds.most_common(5))
