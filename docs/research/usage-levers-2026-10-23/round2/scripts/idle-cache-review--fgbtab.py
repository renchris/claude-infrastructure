#!/usr/bin/env python3
# Collateral of a "deny subagent foreground Bash with timeout param > 270 s" rule: how many such calls
# finish in <= 270 s (denied for no cache benefit), and what one extra request each would cost vs the
# rebuilds the rule targets. Weights = the same sets the researcher used.
import json, glob, statistics as S
D="/tmp/usage-audit/r2/idle-cache-review"
U={}
for p in sorted(glob.glob(D+"/fgb-next*.jsonl")):
    for l in open(p):
        r=json.loads(l); U.setdefault(r["id"], r)
A=list(U.values())
print("subagent fg Bash calls (deduped by tool_use id):", len(A))
hi=[r for r in A if isinstance(r["to"],(int,float)) and r["to"]>270000]
print("  timeout param > 270 s:", len(hi))
short=[r for r in hi if r["rt"] is not None and r["rt"]<=270]
long=[r for r in hi if r["rt"] is not None and r["rt"]>270]
nores=[r for r in hi if r["rt"] is None]
print(f"    ran <= 270 s: {len(short)}   ran > 270 s: {len(long)}   no result: {len(nores)}")
print(f"    short ones: median runtime {S.median(r['rt'] for r in short):.0f}s, mean context {S.mean(r['pp'] for r in short)/1e3:.0f}k")
lo=[r for r in A if not (isinstance(r["to"],(int,float)) and r["to"]>270000) and r["rt"] is not None and r["rt"]>270]
print("  timeout <=270 s or unset but ran > 270 s:", len(lo))
# cost of ONE extra request per denied short call (re-issue with a lower timeout); the researcher's per-slice
# write/output means (subsim.out: write 3054, output 799) and the 250 targeted busts' 46.3M saving.
dW,dO=3054,799
TOT=dict(cc5=536.8e6, cc1=308.2e6, cr=37101.8e6, out=87.9e6)
WS={"API list":dict(cc5=1.25,cc1=2,cr=0.1,out=5),
    "meter reads count":dict(cc5=0.3473,cc1=0.2896,cr=0.0067,out=0.9248),
    "meter reads at 0.049":dict(cc5=0.2848,cc1=1.0678,cr=0.049,out=0.4731),
    "meter reads free":dict(cc5=0.2852,cc1=1.0767,cr=0.0,out=0.4519)}
for n,w in WS.items():
    tot=sum(TOT[k]*w[k] for k in TOT)
    c1=sum(r["pp"]*w["cr"]+dW*w["cc5"]+dO*w["out"] for r in short)
    c1lo=sum(r["pp"]*w["cr"] for r in short)
    print(f"  {n:22s} collateral (1 extra req per short denied call) = {c1/tot:.2%} of weekly (reads only {c1lo/tot:.2%})")
