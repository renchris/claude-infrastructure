#!/usr/bin/env python3
"""Natural experiment: what a SUBAGENT does right after validate-bash's /goal gate denies its
backgrounded poll loop. Read-only. Usage: python3 -I after_goaldeny.py <bash.jsonl>"""
import json, sys, re
from collections import Counter
seen = set(); hits = {}
for l in open(sys.argv[1]):
    r = json.loads(l)
    if r["id"] in seen: continue
    seen.add(r["id"])
    if "A /goal is LIVE in this session" in (r.get("res_head") or ""):
        hits.setdefault(r["file"], []).append(r["id"])
LOOP = re.compile(r"(^|[^\w])(while|until)\s")
nxt_kind = Counter(); ex = []
for f, ids in hits.items():
    calls = []  # (t, id, name, input)
    res = {}
    for line in open(f, errors="replace"):
        try: d = json.loads(line)
        except Exception: continue
        m = d.get("message") if isinstance(d.get("message"), dict) else {}
        if d.get("type") == "assistant":
            for c in m.get("content") or []:
                if isinstance(c, dict) and c.get("type") == "tool_use":
                    calls.append((d.get("timestamp"), c.get("id"), c.get("name"), c.get("input") or {}))
                if isinstance(c, dict) and c.get("type") == "text":
                    calls.append((d.get("timestamp"), None, "TEXT", {"text": c.get("text", "")[:120]}))
    idx = {c[1]: i for i, c in enumerate(calls) if c[1]}
    for i in ids:
        j = idx.get(i)
        if j is None: continue
        follow = [c for c in calls[j+1:j+4]]
        if not follow:
            nxt_kind["subagent ended (no further call)"] += 1; continue
        n = follow[0]
        if n[2] == "Bash":
            inp = n[3]; bg = bool(inp.get("run_in_background")); to = inp.get("timeout"); cmd = str(inp.get("command") or "")
            k = "Bash %s, timeout %s, %s" % ("bg" if bg else "fg", ">270000" if isinstance(to, (int, float)) and to > 270000 else "<=270000/none", "loop" if LOOP.search(cmd) else ("cc-await-ping" if "cc-await-ping" in cmd else "other"))
            nxt_kind[k] += 1
            if len(ex) < 8: ex.append((k, cmd[:140]))
        elif n[2] == "TEXT":
            nxt_kind["text then " + (follow[1][2] if len(follow) > 1 else "END")] += 1
        else:
            nxt_kind[n[2]] += 1
print("goal-gate denies in subagents:", sum(len(v) for v in hits.values()), "files", len(hits))
for k, v in nxt_kind.most_common(): print(v, k)
for e in ex: print("  ", e)
