#!/usr/bin/env python3
# Subagent busts: share whose pre-gap request issued a foreground Bash that ran > 270 s (tool_use -> tool_result).
import json, collections, glob, statistics as S
D="/tmp/usage-audit/r2/idle-cache-review"
best={}
for p in sorted(glob.glob(D+"/gaps-next*.jsonl")):
    for l in open(p):
        g=json.loads(l)
        if g["mid"] not in best or g["nreq"]>best[g["mid"]]["nreq"]: best[g["mid"]]=g
G=[g for g in best.values() if g["sub"]]
M=lambda x:f"{x/1e6:.1f}M"
B=[g for g in G if g["bust"]]
print(f"sub busts n={len(B)} cc={M(sum(g['cc'] for g in B))}; with gap>270: {sum(g['gap']>270 for g in B)}")
long=[g for g in B if any(f[1]>270 for f in g["fgb"])]
print(f"  after fg Bash runtime>270s: n={len(long)} cc={M(sum(g['cc'] for g in long))} ({sum(g['cc'] for g in long)/sum(g['cc'] for g in B):.1%})")
to_hi=[g for g in long if any(f[1]>270 and (f[0] or 0)>270000 for f in g["fgb"])]
print(f"    of which timeout param >270s: n={len(to_hi)} cc={M(sum(g['cc'] for g in to_hi))}")
to_lo=[g for g in long if not any(f[1]>270 and (f[0] or 0)>270000 for f in g["fgb"])]
print(f"    timeout param <=270s or unset: n={len(to_lo)} cc={M(sum(g['cc'] for g in to_lo))}")
print("      sample cmds:", [ (f[0],f[1],f[2][:50]) for g in to_lo[:8] for f in g["fgb"] if f[1]>270][:8])
d=[g["gs_gap"]-max(f[1] for f in g["fgb"]) for g in long]
print(f"    gap minus fg runtime: median {S.median(d):.0f}s p90 {sorted(d)[int(.9*len(d))]:.0f}s")
rest=[g for g in B if g not in long]
print(f"  other sub busts: n={len(rest)} cc={M(sum(g['cc'] for g in rest))}; end-kind:", collections.Counter(g["end"] for g in rest).most_common(6))
print("   late non-Bash tool:", collections.Counter(x[0] for g in rest for x in g["late"]).most_common(6))
# 5-min TTL check: bust rate by gap band (all sub gaps emitted are >270 or bust)
bands=[(270,300),(300,330),(330,400),(400,600),(600,3600),(3600,1e9)]
for lo,hi in bands:
    sel=[g for g in G if lo<g["gap"]<=hi and g["pp"]>=20000]
    print(f"  sub gap ({lo},{hi}] n={len(sel)} bust={sum(g['bust'] for g in sel)}")
