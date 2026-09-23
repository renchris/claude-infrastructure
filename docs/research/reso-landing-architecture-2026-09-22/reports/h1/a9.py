import json, datetime as dt, math
rows=[json.loads(l) for l in open('/Users/chrisren/.reso/land.log') if l.startswith('{"v":3')]
t=lambda s: dt.datetime.strptime(s,'%Y-%m-%dT%H:%M:%SZ').timestamp()
w=[r for r in rows if r['ts_start']>='2026-09-16T04:59:00Z' and not (r['exit']==0 and r['rounds']==0)]
lands=sorted([t(r['ts_end']) for r in w if r['exit']==0])
g=lambda p,k:(p.get(k) or 0)
def V(p): return sum(g(p,k) for k in ('reconcile_s','tsc_s','sem_wait_s','suite_s','push_s'))
code=[(r,p) for r in w for p in r['per_round'] if p.get('suite_mode') in ('union','full') and p.get('push_s') is not None]
def lost(p): return p['rc']==99 or 'cannot lock ref' in (p.get('push_tail') or '')
dec=[(r,p) for r,p in code if p['push_rc']==0 or lost(p)]
a=[lost(p) for r,p in dec if g(p,'sem_wait_s')>0]; b=[lost(p) for r,p in dec if g(p,'sem_wait_s')==0]
print('P(loss|sem_wait>0)=%d/%d=%.2f  P(loss|sem_wait=0)=%d/%d=%.2f'%(sum(a),len(a),sum(a)/len(a),sum(b),len(b),sum(b)/len(b)))
# calibration: local lambda = other lands within +-60min of round start (excluding own), predicted 1-exp(-lam*V)
pred=[];obs=[]
for r,p in dec:
    s=t(r['ts_start'])
    n=sum(1 for x in lands if abs(x-s)<=3600)-(1 if r['exit']==0 else 0)
    lam=max(n,0)/7200.0
    pred.append(1-math.exp(-lam*V(p))); obs.append(lost(p))
print('decided code rounds n=%d observed loss=%.2f predicted mean=%.2f'%(len(dec),sum(obs)/len(obs),sum(pred)/len(pred)))
for lo,hi in ((0,.2),(.2,.4),(.4,.6),(.6,1.01)):
    sel=[(pp,o) for pp,o in zip(pred,obs) if lo<=pp<hi]
    if sel: print('  pred bin [%.1f,%.1f): n=%d pred=%.2f obs=%.2f'%(lo,hi,len(sel),sum(x for x,_ in sel)/len(sel),sum(o for _,o in sel)/len(sel)))
# wave-6 window first-round loss rate for code
for a0,b0 in (('2026-09-22T18:45:00Z','2026-09-22T20:20:00Z'),('2026-09-23T02:45:00Z','2026-09-23T05:10:00Z')):
    sel=[(r,p) for r,p in dec if a0<=r['ts_start']<b0]
    print(a0[:13],'decided code rounds',len(sel),'lost',sum(lost(p) for r,p in sel),'mean V %.0f'%(sum(V(p) for r,p in sel)/max(1,len(sel))))
