#!/usr/bin/env python3
# List Agent/Task/Workflow launches in each successor's first 10 requests. usage: python3 -I v7_launches.py <verify_dir>
import json, os, sys, collections
V = sys.argv[1]
P = [json.loads(l) for l in open(os.path.join(V, "v3.pairs.jsonl"))]
VP = {json.loads(l)["succ"]: json.loads(l) for l in open(os.path.join(V, "vpairs.jsonl"))}
out = []
for p in P:
    if "win" not in p:
        continue
    path = VP[p["succ"]]["succ_path"]
    idx = {}
    with open(path, "rb") as fh:
        for line in fh:
            if b'"type":"assistant"' not in line or b'"isSidechain":true' in line:
                continue
            r = json.loads(line)
            m = r.get("message") or {}
            if m.get("model") == "<synthetic>":
                continue
            k = r.get("requestId") or m.get("id")
            if k not in idx:
                idx[k] = len(idx)
            if idx[k] >= 10:
                break
            for b in m.get("content") or []:
                if isinstance(b, dict) and b.get("type") == "tool_use" and b.get("name") in ("Agent", "Task", "Workflow"):
                    i = b.get("input") or {}
                    out.append((p["succ"][:8], idx[k], b["name"], i.get("subagent_type") or i.get("scriptPath", "")[-40:] or i.get("name", ""),
                                (i.get("description") or "")[:60], (i.get("prompt") or i.get("args") and json.dumps(i.get("args"))[:0] or "")[:110].replace("\n", " ")))
for o in out:
    print(o)
print(len(out), "launches in", len({o[0] for o in out}), "successors")
