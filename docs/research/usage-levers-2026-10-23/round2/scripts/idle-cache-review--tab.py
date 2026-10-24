#!/usr/bin/env python3
# Merge the four reviewer gap files, dedupe by post-gap message.id (keep the longest timeline),
# and tabulate main 1-2h busts by independent state, plus subagent busts by pre-gap foreground Bash.
import json, collections, glob, sys
D="/tmp/usage-audit/r2/idle-cache-review"
best={}
for p in sorted(glob.glob(D+"/gaps-next*.jsonl")):
    for l in open(p):
        g=json.loads(l)
        k=g["mid"]
        if k not in best or g["nreq"]>best[k]["nreq"]: best[k]=g
G=list(best.values())
M=lambda x:f"{x/1e6:.1f}M"
lo,hi=float(sys.argv[1]) if len(sys.argv)>1 else 3600, float(sys.argv[2]) if len(sys.argv)>2 else 7200
main=[g for g in G if not g["sub"] and g["bust"] and lo<g["gap"]<=hi]
print(f"main busts gap in ({lo},{hi}]: n={len(main)} cc={M(sum(g['cc'] for g in main))}")
def st(g, stale=None, use_reset=True):
    if g["late"]: return "A"
    lv=[x for x in g["live"] if (not use_reset or not x["reset"]) and (stale is None or x["age"]<=stale)]
    if any(x["kind"]=="watcher" for x in lv): return "B"
    if lv: return "C"
    return "D"
for label,kw in (("no staleness cut, restart resets registry",dict()),("6h staleness cut, restart resets",dict(stale=6*3600)),("6h cut, ignore restarts (researcher-like)",dict(stale=6*3600,use_reset=False))):
    c=collections.Counter(); cc=collections.Counter()
    for g in main: k=st(g,**kw); c[k]+=1; cc[k]+=g["cc"]
    tot=sum(cc.values())
    print(" ",label, {k:(c[k],M(cc[k]),f"{cc[k]/tot:.0%}") for k in sorted(c)})
# C: what ended the gap, and did a live bg task end inside the gap
C=[g for g in main if st(g)=="C"]
e=collections.Counter(g["end"] for g in C); print("  C end-kind:", dict(e.most_common()))
print("  C with a live bg task whose notification landed inside the gap:", sum(any(x["ended_in_gap"] for x in g["live"] if not x["reset"]) for g in C))
print("  C live kinds:", collections.Counter(x["kind"] for g in C for x in g["live"] if not x["reset"]).most_common())
print("  C min live-task age at gap start (min):", sorted(round(min(x["age"] for x in g["live"] if not x["reset"])/60) for g in C)[::6])
json.dump([g for g in main], open(D+"/main12.json","w"))
