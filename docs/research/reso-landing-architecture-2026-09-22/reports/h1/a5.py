import json, datetime as dt, collections as C
rows=[json.loads(l) for l in open('/Users/chrisren/.reso/land.log') if l.startswith('{"v":3')]
t=lambda s: dt.datetime.strptime(s,'%Y-%m-%dT%H:%M:%SZ').timestamp()
w=[r for r in rows if r['ts_start']>='2026-09-16T04:59:00Z' and not (r['exit']==0 and r['rounds']==0)]
def cause(r):
    if r['exit']==0: return 'landed'
    last=r['per_round'][-1] if r['per_round'] else {}
    tail=last.get('push_tail') or ''
    if r['exit']==9 and 'cannot lock ref' in tail: return 'reflock-race(exit9)'
    if r['exit']==9 and 'unit tests failed' in tail: return 'hook-suite-red(exit9)'
    if r['exit']==9: return 'exit9-other'
    return {6:'statics-red',8:'cas-exhausted',10:'unadmitted',12:'push-timeout',64:'usage'}.get(r['exit'],'x%d'%r['exit'])
by=C.defaultdict(list)
for r in sorted(w,key=lambda r:r['ts_start']): by[r['branch']].append(r)
units=[]; gapc=C.defaultdict(list); dec=C.Counter()
for b,rs in by.items():
    cur=[]
    for r in rs:
        cur.append(r)
        if r['exit']==0:
            units.append(cur); cur=[]
tot=C.Counter()
for u in units:
    for i,r in enumerate(u):
        d=t(r['ts_end'])-t(r['ts_start'])
        # split attempt time into lost-round time vs final
        lost=0
        for p in r['per_round']:
            if p['rc']==99: lost+=sum((p.get(k) or 0) for k in ('reconcile_s','tsc_s','sem_wait_s','suite_s','push_s'))
        tot['cas-lost-rounds']+=lost
        tot['attempt:'+cause(r)]+=d-lost
        if i+1<len(u):
            g=t(u[i+1]['ts_start'])-t(r['ts_end'])
            gapc[cause(r)].append(g); tot['gap-after:'+cause(r)]+=g
T=sum(tot.values())
print('units',len(units),'total unit-seconds',round(T))
for k,v in tot.most_common(): print('  %-34s %7.0f s  %5.1f%%'%(k,v,100*v/T))
print('gap after failed attempt (s) by cause:')
for k,v in gapc.items(): print('  ',k,sorted(round(x) for x in v))
# multi-attempt units: share of unit latency
L=sorted(t(u[-1]['ts_end'])-t(u[0]['ts_start']) for u in units)
import statistics
def pct(a,p):
    a=sorted(a);k=(len(a)-1)*p;f=int(k);c=min(f+1,len(a)-1);return a[f]+(a[c]-a[f])*(k-f)
print('unit latency n=%d p50=%.0f p90=%.0f p95=%.0f'%(len(L),pct(L,.5),pct(L,.9),pct(L,.95)))
single=[t(u[-1]['ts_end'])-t(u[0]['ts_start']) for u in units if len(u)==1]
print('single-attempt units n=%d p50=%.0f p90=%.0f p95=%.0f'%(len(single),pct(single,.5),pct(single,.9),pct(single,.95)))
code_units=[u for u in units if u[-1]['per_round'][-1].get('suite_mode') in ('union','full')]
Lc=[t(u[-1]['ts_end'])-t(u[0]['ts_start']) for u in code_units]
print('code units n=%d p50=%.0f p90=%.0f p95=%.0f'%(len(Lc),pct(Lc,.5),pct(Lc,.9),pct(Lc,.95)))
nc=[t(u[-1]['ts_end'])-t(u[0]['ts_start']) for u in units if u not in code_units]
print('non-code units n=%d p50=%.0f p90=%.0f'%(len(nc),pct(nc,.5),pct(nc,.9)))
