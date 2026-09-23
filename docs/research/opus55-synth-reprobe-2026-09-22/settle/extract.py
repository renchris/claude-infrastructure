#!/usr/bin/env python3
"""Write a settle Workflow's return value to <out>/arms/<brief>-<arm>.md and
<out>/judges/<brief>-J<n>.json (same record shape as ../judges/)."""
import json, os, sys
src, out = sys.argv[1], sys.argv[2]
r = json.load(open(src))
res = r["result"] if isinstance(r, dict) and "result" in r else r
os.makedirs(os.path.join(out, "arms"), exist_ok=True)
os.makedirs(os.path.join(out, "judges"), exist_ok=True)
for b in res:
    for a in b["arms"]:
        if a and a.get("text"):
            open(os.path.join(out, "arms", f"{b['id']}-{a['arm']}.md"), "w").write(a["text"])
    for j in b["judges"]:
        if not j or not j.get("verdict"):
            continue
        rec = {"brief": b["id"], "judge": f"J{j['j']}", "model": j["model"], "effort": j["effort"],
               "label_map": dict(zip("XYZ", j["perm"])), "verdict": j["verdict"], "retried": j.get("retried", False)}
        json.dump(rec, open(os.path.join(out, "judges", f"{b['id']}-J{j['j']}.json"), "w"), indent=1)
print("ok", len(res), "briefs")
