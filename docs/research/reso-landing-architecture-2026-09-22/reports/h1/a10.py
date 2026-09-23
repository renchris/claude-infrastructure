import json, datetime as dt
rows=[json.loads(l) for l in open('/Users/chrisren/.reso/land.log') if l.startswith('{"v":3')]
t=lambda s: dt.datetime.strptime(s,'%Y-%m-%dT%H:%M:%SZ').timestamp()
w=[r for r in rows if r['ts_start']>='2026-09-16T04:59:00Z' and not (r['exit']==0 and r['rounds']==0)]
g=lambda p,k:(p.get(k) or 0)
# reconstruct per-round absolute stage times (backward from ts_end)
R=[]
for r in w:
    pr=r['per_round']
    if not pr: continue
    end=t(r['ts_end'])-2
    for i in range(len(pr)-1,-1,-1):
        p=pr[i]
        push_end=end; push_start=push_end-g(p,'push_s'); suite_end=push_start; suite_start=suite_end-g(p,'suite_s'); acq=suite_start
        wait_start=acq-g(p,'sem_wait_s'); start=wait_start-g(p,'tsc_s')-g(p,'reconcile_s')
        R.append(dict(r=r,i=i,p=p,start=start,acq=acq,suite_end=suite_end,push_end=push_end))
        end=start-3.5
lands=[x for x in R if x['p'].get('push_rc')==0]
def lost(p): return p['rc']==99 or 'cannot lock ref' in (p.get('push_tail') or '')
n=0; prevholder=0; other=0
for x in R:
    p=x['p']
    if not (p.get('push_rc') not in (None,0) and lost(p) and g(p,'sem_wait_s')>0): continue
    n+=1
    comp=[y for y in lands if x['start']<y['push_end']<x['push_end'] and y['r']['branch']!=x['r']['branch']]
    # was a competitor the slot holder immediately before our acquisition? (its suite ended within 20s of our acq)
    hit=[y for y in comp if y['p'].get('suite_mode') in ('union','full') and abs(y['suite_end']-x['acq'])<=20]
    if hit: prevholder+=1
    else: other+=1
    print(x['r']['branch'][:22],'rnd',x['i']+1,'sem_wait',g(p,'sem_wait_s'),'competitors',[ (y['r']['branch'][:16], round(y['suite_end']-x['acq'])) for y in comp])
print('lost rounds with sem_wait>0: %d; competitor was the slot holder just before us (|suite_end-acq|<=20s): %d; other: %d'%(n,prevholder,other))
