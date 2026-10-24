#!/usr/bin/env python3
"""Natural experiment for the deny-compliant path: a subagent fg Bash that hit a tool timeout <= 270000
and was auto-moved to the background by the harness. What happened until its task-notification?
Read-only over transcripts. Usage: python3 -I after_moved.py <bash.jsonl> <out.jsonl>"""
import json, re, sys
from datetime import datetime
from collections import Counter

def T(s):
    try: return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except Exception: return None

MOV = re.compile(r"did not complete within its (\d+)s timeout and was moved to the background \(ID: ([A-Za-z0-9_-]+)\)")
TASK_RX = re.compile(r"<task-id>([^<]+)</task-id>")
LOOP = re.compile(r"(^|[;&|\s])(while|until|for)\s.*sleep\s", re.S)
want = {}
seen = set()
for l in open(sys.argv[1]):
    r = json.loads(l)
    if r["id"] in seen: continue
    seen.add(r["id"])
    h = r.get("res_head") or ""
    m = MOV.search(h)
    if m and not r["bg"]:
        want.setdefault(r["file"], []).append(r["id"])

def scan(p, ids):
    reqs = []; by = {}; res = {}; notes = {}
    for line in open(p, errors="replace"):
        try: d = json.loads(line)
        except Exception: continue
        t = T(d.get("timestamp") or "")
        if t is None: continue
        typ = d.get("type"); m = d.get("message") if isinstance(d.get("message"), dict) else {}
        blob = None
        if typ == "assistant":
            mid = m.get("id") or d.get("uuid"); u = m.get("usage") or {}
            r = by.get(mid)
            if r is None:
                r = dict(t0=t, cc=0, cr=0, inp=0, tools=[]); by[mid] = r; reqs.append(r)
            r["cc"] = max(r["cc"], int(u.get("cache_creation_input_tokens") or 0))
            r["cr"] = max(r["cr"], int(u.get("cache_read_input_tokens") or 0))
            r["inp"] = max(r["inp"], int(u.get("input_tokens") or 0))
            for c in m.get("content") or []:
                if isinstance(c, dict) and c.get("type") == "tool_use":
                    r["tools"].append((c.get("id"), c.get("name"), c.get("input") or {}))
        elif typ == "user":
            c = m.get("content")
            if isinstance(c, list):
                for x in c:
                    if isinstance(x, dict) and x.get("type") == "tool_result":
                        s = x.get("content"); s = s if isinstance(s, str) else " ".join(y.get("text", "") for y in (s or []) if isinstance(y, dict))
                        res.setdefault(x.get("tool_use_id"), (t, s[:400]))
                    elif isinstance(x, dict) and x.get("type") == "text" and "<task-notification>" in x.get("text", ""):
                        blob = x["text"]
            elif isinstance(c, str) and "<task-notification>" in c:
                blob = c
        elif typ == "attachment":
            a = d.get("attachment") if isinstance(d.get("attachment"), dict) else {}
            pr = a.get("prompt"); pr = pr if isinstance(pr, str) else (json.dumps(pr) if pr else "")
            if "<task-notification>" in pr: blob = pr
        if blob:
            for mm in TASK_RX.finditer(blob): notes.setdefault(mm.group(1), t)
    out = []
    ctx = lambda r: r["inp"] + r["cc"] + r["cr"]
    for i, r in enumerate(reqs):
        for tid, name, inp in r["tools"]:
            if tid not in ids: continue
            rt = res.get(tid)
            if not rt: continue
            m = MOV.search(rt[1])
            if not m: continue
            bgid = m.group(2); cmd = str(inp.get("command") or "")
            nt = notes.get(bgid)
            seq = [x for x in reqs[i+1:] if x["t0"] >= rt[0] - 1 and (nt is None or x["t0"] <= nt + 1)]
            prev = r; long_gaps = 0; reb = 0; reb_tok = 0; dup = 0; same_poll = 0; fg_long = 0
            for x in seq:
                g = x["t0"] - prev["t0"]
                if g > 300:
                    long_gaps += 1
                    if x["cc"] >= 0.5 * max(1, ctx(prev)):
                        reb += 1; reb_tok += x["cc"]
                for _, n2, i2 in x["tools"]:
                    if n2 == "Bash":
                        c2 = str(i2.get("command") or "")
                        if c2.strip() == cmd.strip(): dup += 1
                        to2 = i2.get("timeout")
                        if not i2.get("run_in_background") and isinstance(to2, (int, float)) and to2 > 270000: fg_long += 1
                prev = x
            ended_before = nt is None or (reqs[-1]["t0"] < nt)
            out.append(dict(file=p, id=tid, to=inp.get("timeout"), tsec=int(m.group(1)), loop=bool(LOOP.search(cmd)),
                            nreq=len(seq), notified=nt is not None, dur=(nt - r["t0"]) if nt else None,
                            long_gaps=long_gaps, rebuilds=reb, reb_tok=reb_tok, dup_reissue=dup, fg_long_after=fg_long,
                            ended_before_notification=ended_before, ctx=ctx(r), cmd=cmd[:200]))
    return out

rows = []
for p, ids in want.items():
    try: rows += scan(p, set(ids))
    except OSError: pass
with open(sys.argv[2], "w") as f:
    for r in rows: f.write(json.dumps(r) + "\n")
def summ(name, rs):
    n = len(rs)
    if not n: print(name, 0); return
    print("%s: n=%d notified=%d ended_before_notif=%d any_long_gap=%d rebuilt=%d (%.1fM tok) dup_reissue_calls=%d (agents with dup %d) fg_long_after=%d med_nreq=%s" % (
        name, n, sum(r["notified"] for r in rs), sum(r["ended_before_notification"] for r in rs),
        sum(r["long_gaps"] > 0 for r in rs), sum(r["rebuilds"] > 0 for r in rs), sum(r["reb_tok"] for r in rs) / 1e6,
        sum(r["dup_reissue"] for r in rs), sum(r["dup_reissue"] > 0 for r in rs), sum(r["fg_long_after"] > 0 for r in rs),
        sorted(r["nreq"] for r in rs)[n // 2]))
summ("all moved-to-bg", rows)
summ("moved, tool timeout 240-270 s", [r for r in rows if 240 <= r["tsec"] <= 270])
summ("moved, poll-loop command", [r for r in rows if r["loop"]])
