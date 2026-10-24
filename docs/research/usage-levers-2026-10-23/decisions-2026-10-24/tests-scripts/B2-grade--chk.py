import json,sys,collections,datetime
rows=[]
for l in open(sys.argv[1]):
    try: r=json.loads(l)
    except: continue
    if r.get('ts','')<'2026-09-29T00:00:00Z': rows.append(r)
u=[r for r in rows if r.get('decision')=='ask' and r.get('tool_use_id')=='unknown']
ts=sorted(r['ts'] for r in u); print('unknown ask rows',len(u),ts[0],ts[-1])
print('hours',collections.Counter(t[:13] for t in ts))
ci=[r for r in u if 'confirm intent' in r.get('reason','')]
t2=sorted(r['ts'] for r in ci); print('ci unknown',len(ci),t2[:1],t2[-1:])
days=sorted({r['ts'][:10] for r in rows})
d=[datetime.date.fromisoformat(x) for x in days]
for a,b in zip(d,d[1:]):
    if (b-a).days-1>=3: print('gap',a,b,(b-a).days-1)
w=[r['ts'] for r in rows if r['ts']>='2026-08-30T00:00:00Z']; print('first in window',min(w), 'days w data',len({x[:10] for x in w}))
