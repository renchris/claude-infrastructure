#!/usr/bin/env python3
"""Natural experiment: subagent reaction to a wait-related deny it was told how to fix — the
harness's built-in 'Blocked: sleep N followed by' refusal. Read-only. Usage: python3 -I after_sleepblock.py <bash.jsonl>"""
import json, sys, re
from collections import Counter
seen = set(); hits = {}; full = None
for l in open(sys.argv[1]):
    r = json.loads(l)
    if r["id"] in seen: continue
    seen.add(r["id"])
    if (r.get("res_head") or "").startswith("<tool_use_error>Blocked: sleep"):
        hits.setdefault(r["file"], []).append(r["id"])
LOOP = re.compile(r"(^|[^\w])(while|until|for)\s.*sleep", re.S)
k = Counter()
for f, ids in hits.items():
    calls = []; res = {}
    for line in open(f, errors="replace"):
        try: d = json.loads(line)
        except Exception: continue
        m = d.get("message") if isinstance(d.get("message"), dict) else {}
        if d.get("type") == "assistant":
            for c in m.get("content") or []:
                if isinstance(c, dict) and c.get("type") == "tool_use": calls.append((c.get("id"), c.get("name"), c.get("input") or {}))
        elif d.get("type") == "user" and isinstance(m.get("content"), list):
            for x in m["content"]:
                if isinstance(x, dict) and x.get("type") == "tool_result" and x.get("tool_use_id") in ids and full is None:
                    s = x.get("content"); full = s if isinstance(s, str) else json.dumps(s)
    pos = {c[0]: i for i, c in enumerate(calls)}
    for i in ids:
        j = pos.get(i)
        if j is None: continue
        nx = calls[j + 1] if j + 1 < len(calls) else None
        if nx is None: k["subagent ended"] += 1; continue
        if nx[1] == "Bash":
            inp = nx[2]; to = inp.get("timeout")
            k["Bash %s timeout %s %s" % ("bg" if inp.get("run_in_background") else "fg", ">270000" if isinstance(to, (int, float)) and to > 270000 else "<=270000/none", "loop" if LOOP.search(str(inp.get("command") or "")) else "other")] += 1
        else:
            k[nx[1]] += 1
print("built-in sleep blocks:", sum(len(v) for v in hits.values()))
print("full text of one:", (full or "")[:700])
for a, b in k.most_common(): print(b, a)
