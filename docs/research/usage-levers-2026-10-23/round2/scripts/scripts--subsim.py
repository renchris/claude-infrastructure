#!/usr/bin/env python3
# Subagent fix economics: replace each foreground Bash (timeout param >270 s) that ran >270 s and preceded a bust
# by ceil(runtime/270) foreground slices. Extra requests = slices-1, each re-reading the context once (+ a small
# write and output). Per-request write/output = medians of subagent requests that follow a <=270 s gap while a
# background job is live is not stored, so use all non-bust subagent requests after a 60-270 s gap (TSV).
import json, csv, math, statistics as S, collections
from datetime import datetime
csv.field_size_limit(10**9)
T=lambda s: datetime.fromisoformat(s.replace("Z","+00:00")).timestamp()
S_=[json.loads(l) for l in open('/tmp/usage-audit/r2/cache-rebuilds/subwait.jsonl')]
tgt=[s for s in S_ if s['bust'] and s['kind'].startswith('fg Bash') and 'timeout>270s' in s['kind'] and s['rt'] and s['rt']>270]
# per-request write/output for sub requests after a 60-270 s gap (non-bust)
U={}
for a in ("next","next2","next3","next4"):
    for r in csv.DictReader(open(f"/tmp/usage-audit/sk-cache-{a}.tsv"),delimiter="\t"):
        if r['sub']!='1': continue
        if r['mid'] in U: continue
        U[r['mid']]=(r['rel'],T(r['ts']),int(r['in']),int(r['cc']),int(r['cr']),int(r['out_max']))
TL=collections.defaultdict(list)
for v in U.values(): TL[v[0]].append(v)
ccs=[];outs=[]
for rel,rs in TL.items():
    rs.sort(key=lambda x:x[1])
    for p,c in zip(rs,rs[1:]):
        g=c[1]-p[1]; pp=p[2]+p[3]+p[4]
        if 60<g<=270 and pp>20000 and c[4]>=0.5*pp:
            ccs.append(c[3]); outs.append(c[5])
dW=S.mean(ccs); dO=S.mean(outs)
print(f"slice request (sub, gap 60-270s, warm): n={len(ccs)} write mean={dW:.0f} median={S.median(ccs):.0f}; output mean={dO:.0f} median={S.median(outs):.0f} (out_max, lower bound)")
TOT=dict(cc5=536.8e6, cc1=308.2e6, cr=37101.8e6, out=87.9e6)
WS={"API list":dict(cc5=1.25,cc1=2,cr=0.1,out=5),
    "meter reads count (sk_bc_meter2 weekly)":dict(cc5=0.3473,cc1=0.2896,cr=0.0067,out=0.9248),
    "meter reads at bound 0.049":dict(cc5=0.2848,cc1=1.0678,cr=0.049,out=0.4731),
    "meter reads free (sk-cache-ttlfit2)":dict(cc5=0.2852,cc1=1.0767,cr=0.0,out=0.4519)}
extra=[max(0,math.ceil(s['rt']/270)-1) for s in tgt]
print(f"target busts n={len(tgt)} cc={sum(s['cc'] for s in tgt)/1e6:.1f}M; extra slice requests total={sum(extra)} (median {S.median(extra)} per avoided bust); mean context={S.mean(s['pp'] for s in tgt)/1e3:.0f}k")
for n,w in WS.items():
    tot=sum(TOT[k]*w[k] for k in TOT)
    save=sum(s['cc']*(w['cc5']-w['cr']) for s in tgt)
    cost=sum(e*(s['pp']*w['cr']+dW*w['cc5']+dO*w['out']) for s,e in zip(tgt,extra))
    C=174e3
    kstar=C*(w['cc5']-w['cr'])/(C*w['cr']+dW*w['cc5']+dO*w['out'])
    print(f"  {n:42s} break-even slices per avoided rebuild k*={kstar:5.1f} (= {kstar*4.5:.0f} min of waiting) | saved={save/tot:.2%} cost={cost/tot:.2%} net={(save-cost)/tot:+.2%} of weekly")
