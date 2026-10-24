#!/usr/bin/env python3
"""Cache tier (5m vs 1h) and agentType per subagent file that holds a narrow call. Read-only.
Usage: python3 -I tier.py <joined.json> <bash.jsonl>"""
import json, sys, os
from collections import Counter, defaultdict
J = json.load(open(sys.argv[1]))
ids = {r["id"]: r for r in J if r["narrow"]}
files = {}
for l in open(sys.argv[2]):
    r = json.loads(l)
    if r["id"] in ids:
        files.setdefault(r["file"], set()).add(ids[r["id"]]["why"])
tier = Counter(); bytype = defaultdict(Counter); f1h = []
for f, whys in files.items():
    m = f[:-len(".jsonl")] + ".meta.json"
    at = "?"
    try:
        at = json.load(open(m)).get("agentType", "?")
    except Exception:
        pass
    w5 = w1 = 0
    with open(f, errors="replace") as fh:
        for line in fh:
            if '"ephemeral_' not in line:
                continue
            try:
                d = json.loads(line)
            except Exception:
                continue
            u = (d.get("message") or {}).get("usage") or {}
            cc = u.get("cache_creation") or {}
            w5 += int(cc.get("ephemeral_5m_input_tokens") or 0)
            w1 += int(cc.get("ephemeral_1h_input_tokens") or 0)
    k = "1h" if w1 > 0 else "5m-only"
    tier[k] += 1
    for w in whys:
        bytype[(w, at)][k] += 1
    if w1 > 0:
        f1h.append((f, at, w1, w5))
print("files", len(files), "tier", dict(tier))
for k, v in sorted(bytype.items(), key=lambda x: -sum(x[1].values())):
    print(k, dict(v))
for x in f1h[:10]:
    print("1h:", x)
