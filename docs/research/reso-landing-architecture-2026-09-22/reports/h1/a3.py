import json, datetime as dt, collections as C, math
rows=[json.loads(l) for l in open('/Users/chrisren/.reso/land.log') if l.startswith('{"v":3')]
t=lambda s: dt.datetime.strptime(s,'%Y-%m-%dT%H:%M:%SZ').timestamp()
cut=t('2026-09-16T04:59:00Z'); w=[r for r in rows if t(r['ts_start'])>=cut]
for r in w:
    if r['head'].startswith('85d23a404'): print(json.dumps({k:v for k,v in r.items() if k!='per_round'})); print([ (p['rc'],p.get('push_tail','')[-200:]) for p in r['per_round']])
lands=[r for r in w if r['exit']==0 and r['rounds']>=1]
land_t=[(t(r['ts_end'])-2, r['branch'], r['per_round'][-1].get('suite_mode')) for r in lands]
def dur(pr): return sum((pr.get(k) or 0) for k in ('reconcile_s','tsc_s','sem_wait_s','suite_s','push_s'))
out=[]
for r in w:
    pr=r['per_round']
    if not pr: continue
    end=t(r['ts_end'])-2
    # backward reconstruction
    wins=[]
    for i in range(len(pr)-1,-1,-1):
        d=dur(pr[i]); s=end-d
        wins.append((i,s,end,pr[i]))
        end=s-3.5  # backoff+fetch
    for i,s,e,p in wins:
        if p.get('push_rc') is None: continue
        comp=[x for x in land_t if s<x[0]<e and x[1]!=r['branch']]
        tail=p.get('push_tail') or ''
        if p['push_rc']==0: o='won'
        elif 'cannot lock ref' in tail: o='lost-reflock'
        elif p['rc']==99: o='lost-nff'
        else: o='rejected-other'
        out.append((o,e-s,len(comp),p.get('suite_mode'),r['branch'],r['ts_start']))
tab=C.Counter((o,min(n,3)) for o,_,n,_,_,_ in out)
print('outcome x #competing lands in reconstructed window (3=3+):')
for o in ('won','lost-nff','lost-reflock','rejected-other'):
    print('  ',o,[tab.get((o,k),0) for k in range(4)])
# anomalies
for o,L,n,m,b,ts in out:
    if (o=='won' and n>0) or (o.startswith('lost') and n==0): print('  anomaly',o,round(L),n,m,b,ts)
# P(loss) by window-length bucket, code rounds only (exclude rejected-other)
print('code rounds (suite ran): outcome by V bucket')
for lo,hi in ((0,60),(60,300),(300,450),(450,600),(600,2000)):
    sel=[x for x in out if lo<=x[1]<hi and x[0]!='rejected-other']
    if sel: print('   V[%d,%d) n=%d lost=%d'%(lo,hi,len(sel),sum(x[0].startswith('lost') for x in sel)))
