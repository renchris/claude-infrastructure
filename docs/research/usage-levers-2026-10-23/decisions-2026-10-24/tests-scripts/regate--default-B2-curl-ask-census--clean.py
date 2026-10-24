import json, sys, re, collections
CUT="2026-09-29T00:00:00Z"; W30="2026-08-30T00:00:00Z"
def cls(s):
    if "confirm intent" in s: return "confirm intent"
    for p in ("No URL parsed","Non-HTTP scheme","GET to unknown host","GET to unvetted host"):
        if s.startswith(p): return p
    return "OTHER:"+s[:40]
asks=[]
for l in open(sys.argv[1], encoding="utf-8"):
    r=json.loads(l)
    if r['ts']>=CUT or r['decision']!='ask': continue
    if r['tool_use_id']=='unknown' or r['session_id'] in ('smoke','probe'): continue
    asks.append(r)
out=[]
for lab,sel in (("ALL",asks),("LAST30",[r for r in asks if r['ts']>=W30])):
    print(f"== CLEAN {lab}: rows={len(sel)} prompts={len({r['tool_use_id'] for r in sel})} sessions={len({r['session_id'] for r in sel})}")
    c=collections.Counter(cls(r['reason']) for r in sel)
    for k,v in c.most_common(): print(f"  {v:5d} {100*v/len(sel):5.1f}%  {k}  sessions={len({r['session_id'] for r in sel if cls(r['reason'])==k})}")
    ci=[r for r in sel if cls(r['reason'])=='confirm intent']
    print("  CI split", collections.Counter('POST to unknown host' if r['reason'].startswith('POST to unknown host') else '<METHOD> <host>' for r in ci))
    print("  CI method field", collections.Counter(r['method'] for r in ci))
    hc=collections.Counter(r['host'] for r in ci); print("  CI distinct hosts", len(hc), "top5", hc.most_common(5))
    print("  CI method!=reason verb:", sum(1 for r in ci if r['reason'].split(' ',1)[0]!=r['method']))
    print("  CI host artifacts (mozilla/research-agent/$h/None):", sum(1 for r in ci if r['host'] in ('mozilla','research-agent','$h',None)))
    print("  CI loopback hosts (127.0.0.1/localhost/gn.localhost):", sum(1 for r in ci if r['host'] in ('127.0.0.1','localhost','gn.localhost')))
    if lab=="LAST30":
        for r in ci: out.append(r)
json.dump(out, open(sys.argv[2],"w"))
