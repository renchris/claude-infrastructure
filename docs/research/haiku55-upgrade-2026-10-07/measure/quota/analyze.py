# analyze.py — 5h-meter draw per M output tokens per phase, integer-meter bounds, hold drift.
import json
D='/tmp/haiku55-measure/quota/'
ph=[json.loads(l) for l in open(D+'phases.jsonl')]
S=[json.loads(l) for l in open(D+'series.jsonl') if l.strip()]
S=[s for s in S if s.get('wire') and s['wire'].get('5h_util') is not None]
def at(ts, side):  # reading nearest at/after ts (side=+1) or at/before (side=-1)
    c=[s for s in S if (s['ts']>=ts if side>0 else s['ts']<=ts)]
    if not c: return None
    s=min(c,key=lambda s:abs(s['ts']-ts)); return round(s['wire']['5h_util']*100), round(s['wire']['7d_util']*100), s['iso']
bounds=[(p['phase'],p['ts']) for p in ph]
seg={}
for i,(name,ts) in enumerate(bounds[:-1]):
    nxt=bounds[i+1][1]
    seg[name]=(ts,nxt)
def tokens(f):
    try: R=[json.loads(l) for l in open(D+f+'.jsonl')]
    except FileNotFoundError: return None
    return sum(r.get('output_tokens') or 0 for r in R), sum(r.get('cache_create') or 0 for r in R), len(R), sorted({m for r in R for m in r.get('served') or []})
out={}
for name,(a,b) in seg.items():
    s0=at(a,-1) or at(a,1); s1=at(b,-1)
    out[name]={'from':s0,'to':s1,'d5h':s1[0]-s0[0],'d7d':s1[1]-s0[1],'minutes':round((b-a)/60,1)}
    # a burn phase is measured from its start to the END of the following hold (meter catch-up)
for burn,hold in (('H1','hold1'),('O','hold2'),('H2','hold3')):
    if burn not in seg or hold not in seg: continue
    a=seg[burn][0]; b=seg[hold][1]
    s0=at(a,-1) or at(a,1); s1=at(b,-1)
    t=tokens(burn); d=s1[0]-s0[0]
    out[burn+'+'+hold]={'d5h':d,'d7d':s1[1]-s0[1],'out':t[0],'cc':t[1],'calls':t[2],'served':t[3],
      'pp_per_M_out':round(d/(t[0]/1e6),2),'bound_pp_per_M':[round(max(d-1,0)/(t[0]/1e6),2),round((d+1)/(t[0]/1e6),2)]}
print(json.dumps(out,indent=1))
