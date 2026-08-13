#!/usr/bin/env python3
"""Interleave CC's own Stop-payload registry reads with goal_status attachments."""
import json, sys, glob, os
arm = sys.argv[1]
stop_log = os.path.join(arm, "stop.log")
tr = glob.glob(os.path.join(arm, "cfg/projects/*/*.jsonl"))
rows = []
for l in open(stop_log):
    ts, p = l.rstrip("\n").split("\t", 1)
    bt = json.loads(p).get("background_tasks", [])
    desc = ", ".join(f"{t.get('type')}/{t.get('status')}" for t in bt) or "-"
    rows.append((ts.replace("+00:00", "Z"), f"STOP   background_tasks={len(bt):<2} [{desc}]"))
for f in tr:
    for l in open(f):
        try: d = json.loads(l)
        except Exception: continue
        if d.get("type") != "attachment": continue
        a = d.get("attachment", {})
        if a.get("type") != "goal_status": continue
        ts = d.get("timestamp", "")[:19] + "Z"
        if a.get("sentinel"):
            rows.append((ts, "GOAL   sentinel=true  (armed)"))
        else:
            rows.append((ts, f"GOAL   EVALUATION met={a.get('met')}"))
for ts, txt in sorted(rows, key=lambda r: r[0]):
    print(f"{ts}  {txt}")
