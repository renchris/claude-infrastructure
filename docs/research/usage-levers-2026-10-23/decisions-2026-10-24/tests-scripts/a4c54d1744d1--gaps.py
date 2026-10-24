"""Per-request timeline for one agent transcript: gap since previous request, cw, cr, out, tool names.
Usage: python3 -I gaps.py <agent.jsonl>"""
import json, sys
from datetime import datetime
req = {}; order = []
for l in open(sys.argv[1]):
    r = json.loads(l)
    if r.get("type") != "assistant": continue
    rid = r.get("requestId"); u = r["message"].get("usage") or {}
    if rid not in req:
        order.append(rid); req[rid] = dict(ts=r["timestamp"], cw=0, cr=0, out=0, tools=[])
    q = req[rid]
    q["cw"] = max(q["cw"], u.get("cache_creation_input_tokens", 0)); q["cr"] = max(q["cr"], u.get("cache_read_input_tokens", 0))
    q["out"] = max(q["out"], u.get("output_tokens", 0))
    for c in r["message"].get("content") or []:
        if isinstance(c, dict) and c.get("type") == "tool_use":
            inp = c.get("input") or {}
            q["tools"].append(c["name"] + ("(bg)" if inp.get("run_in_background") else "") + (f"[to={inp.get('timeout')}]" if inp.get("timeout") else ""))
prev = None
for i, rid in enumerate(order):
    q = req[rid]; t = datetime.fromisoformat(q["ts"].replace("Z", "+00:00"))
    gap = (t - prev).total_seconds() if prev else 0; prev = t
    print(f"{i:2d} {q['ts'][11:19]} gap={gap:7.0f}s cw={q['cw']:7d} cr={q['cr']:7d} out={q['out']:5d} {q['tools']}")
