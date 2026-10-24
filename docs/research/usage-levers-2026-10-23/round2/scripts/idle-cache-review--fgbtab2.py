#!/usr/bin/env python3
# Collateral bounds for the timeout-based deny rule: upper = one extra request per short denied call,
# lower = one extra request per subagent FILE that has >=1 short denied call (agent learns after one deny).
# Lean round-trip cost: the deny turn re-reads context, writes ~300 tok, outputs ~150 tok (estimated).
import json, glob, collections, statistics as S
D="/tmp/usage-audit/r2/idle-cache-review"
U={}
for p in sorted(glob.glob(D+"/fgb-next*.jsonl")):
    for l in open(p):
        r=json.loads(l); U.setdefault(r["id"], r)
A=list(U.values())
hi=[r for r in A if isinstance(r["to"],(int,float)) and r["to"]>270000 and r["rt"] is not None]
short=[r for r in hi if r["rt"]<=270]
# first short denied call per file (dedupe copies by rel)
first={}
for r in sorted(short,key=lambda r:r["ts"]):
    first.setdefault(r["rel"], r)
files_any=set(r["rel"] for r in hi)
print(f"short denied calls={len(short)} in {len(first)} subagent files; files with any timeout>270 call={len(files_any)}")
print("short calls per file: median", S.median(collections.Counter(r['rel'] for r in short).values()), "max", max(collections.Counter(r['rel'] for r in short).values()))
print("top timeout values among short:", collections.Counter(r["to"] for r in short).most_common(5))
print("wf/agent split:", collections.Counter(('workflows' in r['rel']) for r in short))
TOT=dict(cc5=536.8e6, cc1=308.2e6, cr=37101.8e6, out=87.9e6)
WS={"API list":dict(cc5=1.25,cc1=2,cr=0.1,out=5),
    "meter reads count":dict(cc5=0.3473,cc1=0.2896,cr=0.0067,out=0.9248),
    "meter reads at 0.049":dict(cc5=0.2848,cc1=1.0678,cr=0.049,out=0.4731),
    "meter reads free":dict(cc5=0.2852,cc1=1.0767,cr=0.0,out=0.4519)}
SAVED={"API list":0.98,"meter reads count":2.60,"meter reads at 0.049":0.47,"meter reads free":2.52}
SLICE={"API list":0.19,"meter reads count":0.19,"meter reads at 0.049":0.17,"meter reads free":0.09}
for n,w in WS.items():
    tot=sum(TOT[k]*w[k] for k in TOT)
    c=lambda rs: sum(r["pp"]*w["cr"]+300*w["cc5"]+150*w["out"] for r in rs)/tot*100
    up=c(short); lo=c(first.values())
    print(f"  {n:22s} collateral {lo:.2f}% (one deny per file) .. {up:.2f}% (one per call); researcher net {SAVED[n]-SLICE[n]:+.2f}% -> {SAVED[n]-SLICE[n]-up:+.2f}% .. {SAVED[n]-SLICE[n]-lo:+.2f}%")
