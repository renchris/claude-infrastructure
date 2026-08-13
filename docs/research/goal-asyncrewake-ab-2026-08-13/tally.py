#!/usr/bin/env python3
"""Pair every Stop with the goal_status evaluation (if any) that followed it before the next Stop.
The ONLY discriminator under test is CC's own background_tasks count in the Stop payload."""
import json, sys, glob, os, datetime
def parse(t):
    t = t.replace("Z", "+00:00")
    return datetime.datetime.fromisoformat(t)
grand = {}
for arm in sys.argv[1:]:
    name = os.path.basename(arm)
    stops = []
    for l in open(os.path.join(arm, "stop.log")):
        ts, p = l.rstrip("\n").split("\t", 1)
        stops.append((parse(ts), len(json.loads(p).get("background_tasks", []))))
    stops.sort()
    evals = []
    for f in glob.glob(os.path.join(arm, "cfg/projects/*/*.jsonl")):
        for l in open(f):
            try: d = json.loads(l)
            except Exception: continue
            if d.get("type") != "attachment": continue
            a = d.get("attachment", {})
            if a.get("type") == "goal_status" and not a.get("sentinel"):
                evals.append(parse(d["timestamp"]))
    evals.sort()
    occ_n = occ_e = emp_n = emp_e = 0
    for i, (ts, n) in enumerate(stops):
        nxt = stops[i + 1][0] if i + 1 < len(stops) else ts + datetime.timedelta(seconds=3600)
        hit = any(ts <= e < nxt for e in evals)
        if n: occ_n += 1; occ_e += hit
        else: emp_n += 1; emp_e += hit
    print(f"{name:8}  registry-EMPTY stops={emp_n:<3} → evaluations={emp_e:<3} | "
          f"registry-OCCUPIED stops={occ_n:<3} → evaluations={occ_e}")
    for k, v in (("emp_n",emp_n),("emp_e",emp_e),("occ_n",occ_n),("occ_e",occ_e)):
        grand[k] = grand.get(k, 0) + v
print(f"{'TOTAL':8}  registry-EMPTY stops={grand['emp_n']:<3} → evaluations={grand['emp_e']:<3} | "
      f"registry-OCCUPIED stops={grand['occ_n']:<3} → evaluations={grand['occ_e']}")
