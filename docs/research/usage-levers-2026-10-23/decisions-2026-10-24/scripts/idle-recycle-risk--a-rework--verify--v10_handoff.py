#!/usr/bin/env python3
# Predecessor's final turn (last user message before the brief -> brief) for recycles taken after >=900 s idle:
# request count and cost beyond ONE request (sim.py prices the handoff as one request: read ctx + 1500 out).
# usage: python3 -I v10_handoff.py <verify_dir>
import json, os, random, statistics as st, sys
from datetime import datetime
V = sys.argv[1]
WR, RD, OUT, INP = 0.245e-6, 0.0067e-6, 0.404e-6, 389e-6
ep = lambda s: datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
def series(path):
    reqs, idx, turn = [], {}, []
    pend = False
    with open(path, "rb") as fh:
        for line in fh:
            if b'"isSidechain":true' in line or (b'"type":"user"' not in line and b'"type":"assistant"' not in line):
                continue
            try: r = json.loads(line)
            except Exception: continue
            if r.get("type") == "user":
                c = (r.get("message") or {}).get("content")
                if not (isinstance(c, list) and any(isinstance(b, dict) and b.get("type") == "tool_result" for b in c)) and not r.get("isMeta"):
                    pend = True
                continue
            if r.get("type") != "assistant": continue
            m = r.get("message") or {}
            if m.get("model") == "<synthetic>": continue
            u = m.get("usage") or {}
            k = r.get("requestId") or m.get("id")
            if k in idx:
                reqs[idx[k]][4] = max(reqs[idx[k]][4], u.get("output_tokens") or 0); continue
            idx[k] = len(reqs)
            if pend: turn.append(len(reqs)); pend = False
            reqs.append([ep(r["timestamp"]), u.get("input_tokens") or 0, u.get("cache_creation_input_tokens") or 0, u.get("cache_read_input_tokens") or 0, u.get("output_tokens") or 0])
    return reqs, turn
P = [json.loads(l) for l in open(os.path.join(V, "vpairs.jsonl")) if json.loads(l).get("pred_path")]
rows = []
for p in P:
    R, T = series(p["pred_path"])
    cut = ep(p["brief_ts"])
    pe = len([r for r in R if r[0] < cut])
    ts = [t for t in T if 0 < t < pe]
    if not ts: continue
    t0 = ts[-1]
    gap = R[t0][0] - R[t0 - 1][0]
    if gap < 900: continue
    n = pe - t0
    extra = sum(r[3] * RD + r[2] * WR + r[4] * OUT + r[1] * INP for r in R[t0 + 1:pe])
    rows.append((n, extra, R[t0 - 1][1] + R[t0 - 1][2] + R[t0 - 1][3]))
n = [r[0] for r in rows]
print("recycles after >=900 s idle: %d; final-turn requests median %d mean %.1f p75 %d p90 %d" % (len(rows), st.median(n), sum(n) / len(n), sorted(n)[3 * len(n) // 4], sorted(n)[int(.9 * len(n))]))
print("cost of the final turn beyond its first request: mean %.4f pp/recycle -> %.2f pp/week at 155 recycles/week; without input proxy see below" % (sum(r[1] for r in rows) / len(rows), sum(r[1] for r in rows) / len(rows) * 155))
pl = [r for r in rows if 150e3 <= r[2] < 350e3]
print("policy-like (ctx 150-350k at idle): n=%d requests median %d, extra %.2f pp/week" % (len(pl), st.median(r[0] for r in pl), sum(r[1] for r in pl) / len(pl) * 155))
