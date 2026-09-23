import json, math
rows=[json.loads(l) for l in open('/Users/chrisren/.reso/land.log') if l.startswith('{"v":3')]
w=[r for r in rows if r['ts_start']>='2026-09-16T04:59:00Z' and not (r['exit']==0 and r['rounds']==0)]
g=lambda p,k:(p.get(k) or 0)
code=[p for r in w for p in r['per_round'] if p.get('suite_mode') in ('union','full') and p.get('push_s') is not None]
ncp=sorted(g(p,'push_s') for r in w for p in r['per_round'] if p.get('suite_mode')=='none' and p.get('push_s') is not None)
med=ncp[len(ncp)//2]
V0=[sum(g(p,k) for k in ('reconcile_s','tsc_s','sem_wait_s','suite_s','push_s')) for p in code]
V1=[sum(g(p,k) for k in ('reconcile_s','tsc_s','sem_wait_s','suite_s'))+med for p in code]
V2=[sum(g(p,k) for k in ('reconcile_s','tsc_s','suite_s'))+med for p in code]
Vc=[1+x for x in ncp]   # carried retry: reconcile + push (non-code push dist)
Vh=[g(p,'reconcile_s')+g(p,'suite_s')+x for p in code for x in ncp[::6]]  # slot-hold window, tsc outside
def p(lam,V): return sum(math.exp(-lam*v) for v in V)/len(V)
def mean(a): return sum(a)/len(a)
print('fitted: E[V_today]=%.0f E[V_cf1]=%.0f E[V_cf2]=%.0f E[V_carry]=%.0f E[V_hold]=%.0f  (s)'%(mean(V0),mean(V1),mean(V2),mean(Vc),mean(Vh)))
print('%-26s %6s %6s | %-34s | %-34s | %-40s'%('scenario','Lam/h','lam/h','today: P(loss) E[rnd] P(exh5)','cf1 no-hook: P(loss) E[rnd] E[lat]','cf2+carry q=.42/.72: P1loss E[lat]'))
for name,N,Tc in (('wave-6 peak (obs)',5,None),('N=10 @60min',10,60),('N=15 @60min',15,60),('N=15 @45min',15,45),('N=15 @30min',15,30),('N=20 @45min',20,45),('N=30 @45min',30,45)):
    Lam = 5.79 if Tc is None else N*60/Tc
    lam = Lam*(N-1)/N/3600
    p0=p(lam,V0); p1=p(lam,V1); p2=p(lam,V2); pc=p(lam,Vc)
    er0=1/p0; ex0=(1-p0)**5
    er1=1/p1; lat1=mean(V1)/p1
    out=[]
    for q in (.42,.72):
        # first round V2; after a loss: carried retry (Vc) w.p. 1-q else full V2 again
        # E[L] = E[V2] + (1-p2) * R, R = expected time to land from a retry state
        # R = (1-q)*(E[Vc] + (1-pc)*R) + q*(E[V2] + (1-p2)*R)
        a=(1-q)*mean(Vc)+q*mean(V2); b=(1-q)*(1-pc)+q*(1-p2)
        R=a/(1-b); L=mean(V2)+(1-p2)*R
        out.append('%.2f %4.0fs'%(1-p2,L))
    print('%-26s %6.1f %6.1f | %.2f  %.2f  %.3f               | %.2f  %.2f  %4.0fs               | %s'%(name,Lam,lam*3600,1-p0,er0,ex0,1-p1,er1,lat1,' / '.join(out)))
