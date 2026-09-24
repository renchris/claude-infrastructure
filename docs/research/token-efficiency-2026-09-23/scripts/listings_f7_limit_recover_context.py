#!/usr/bin/env python3
"""What preceded each model-made Skill call to limit-recover since 2026-09-09 (F7 review minor 4).
Scans the 30 records before each call across all five config dirs, skipping skill_listing, prompt
snapshot, hook context and session context attachments (the old description itself carries the error
strings). Result 2026-09-23: 11 calls; 1 preceded by a tool_result containing "hit your session";
the other hits were CLAUDE.md instruction text. Usage: python3 listings_f7_limit_recover_context.py"""
import json, glob, os, re, sys, collections
roots = [os.path.expanduser(p) for p in ["~/.claude/projects","~/.claude-next/projects","~/.claude-secondary/projects","~/.claude-tertiary/projects","~/.claude-quaternary/projects"]]
files=set()
for r in roots:
    for p in glob.glob(r+"/*/*.jsonl"):
        try:
            if os.path.getmtime(p) > 1757376000-0: files.add(os.path.realpath(p))  # since 2025-09-09 placeholder
        except: pass
pat = re.compile(r"hit your (session|weekly|monthly)|usage limit|limit reached|Can't reach the API|ENOTFOUND|ECONNRESET|stalled on all|no progress for|watchdog|Not logged in|invalid_grant|logged-out", re.I)
res = collections.Counter(); examples=[]
for p in files:
    try: data=open(p,'rb').read()
    except: continue
    if b'limit-recover' not in data or b'"Skill"' not in data: continue
    recs=[]
    for line in data.split(b"\n"):
        try: recs.append(json.loads(line))
        except: pass
    for i,r in enumerate(recs):
        if r.get("type")!="assistant": continue
        if (r.get("timestamp") or "") < "2026-09-09": continue
        for c in (r.get("message") or {}).get("content") or []:
            if isinstance(c,dict) and c.get("type")=="tool_use" and c.get("name")=="Skill" and "limit-recover" in json.dumps(c.get("input")):
                # previous user-side records until last genuine prompt, up to 8
                ctx=[]; src=[]
                for j in range(i-1, max(-1,i-30), -1):
                    q=recs[j]
                    if q.get("type") in ("user","attachment","system"):
                        a=q.get("attachment") or {}
                        if a.get("type") in ("skill_listing","prompt_snapshot","hook_additional_context","session_context"): continue
                        t=json.dumps(q.get("message") or a or q.get("content") or "")
                        for m in pat.finditer(t): src.append((q.get("type"), a.get("type") or ("tool_result" if "tool_result" in t[:200] else "text"), m.group(0)))
                        ctx.append(t)
                blob=" ".join(ctx)
                hits=sorted(set(m.group(0).lower() for m in pat.finditer(blob)))
                res[tuple(hits)]+=1
                examples.append((os.path.basename(p)[:8], r.get("timestamp"), hits, str(sorted(set(src)))))
print(sum(res.values()), "calls"); 
for k,v in res.most_common(): print(v, k)
for e in examples: print(e[:3]); print("   ", e[3][:300])
