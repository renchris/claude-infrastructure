import json, datetime as dt, collections as C, math, random
rows=[json.loads(l) for l in open('/Users/chrisren/.reso/land.log') if l.startswith('{"v":3')]
t=lambda s: dt.datetime.strptime(s,'%Y-%m-%dT%H:%M:%SZ').timestamp()
w=[r for r in rows if r['ts_start']>='2026-09-16T04:59:00Z' and not (r['exit']==0 and r['rounds']==0)]
lands=sorted([r for r in w if r['exit']==0],key=lambda r:r['ts_end'])
def pct(a,p):
    a=sorted(a);k=(len(a)-1)*p;f=int(k);c=min(f+1,len(a)-1);return a[f]+(a[c]-a[f])*(k-f)
def P(a): return 'n=%d p50=%.0f p90=%.0f p95=%.0f mean=%.0f'%(len(a),pct(a,.5),pct(a,.9),pct(a,.95),sum(a)/len(a))
g=lambda p,k:(p.get(k) or 0)
code=[p for r in w for p in r['per_round'] if p.get('suite_mode') in ('union','full') and p.get('push_s') is not None]
nc =[p for r in w for p in r['per_round'] if p.get('suite_mode')=='none' and p.get('push_s') is not None]
ncpush=[g(p,'push_s') for p in nc]
print('non-code push_s',P(ncpush))
print('non-code round window',P([sum(g(p,k) for k in ('reconcile_s','tsc_s','push_s')) for p in nc]))
for k in ('reconcile_s','tsc_s','sem_wait_s','suite_s','push_s'): print('code',k,P([g(p,k) for p in code]))
V0=[sum(g(p,k) for k in ('reconcile_s','tsc_s','sem_wait_s','suite_s','push_s')) for p in code]
print('V_today (code rounds)',P(V0))
med=pct(ncpush,.5)
V1=[sum(g(p,k) for k in ('reconcile_s','tsc_s','sem_wait_s','suite_s'))+med for p in code]
print('V_cf1 (hook suite removed, push=nc median %.0f)'%med,P(V1))
random.seed(1); V1b=[]
for _ in range(200):
    for p in code: V1b.append(sum(g(p,k) for k in ('reconcile_s','tsc_s','sem_wait_s','suite_s'))+random.choice(ncpush))
print('V_cf1 bootstrap push~nc dist',P(V1b))
V2=[sum(g(p,k) for k in ('reconcile_s','tsc_s','suite_s'))+med for p in code]
print('V_cf2 (also sem wait out of window)',P(V2))
print('hook-suite estimate push_s - nc_median',P([g(p,'push_s')-med for p in code]))
for name,V in (('today',V0),('cf1',V1),('cf2',V2)):
    for q in (.5,.9,.95):
        v=pct(V,q); print('  %s V_p%d=%.0fs -> lambda* (P(no competing land)=0.5) = %.2f lands/h'%(name,int(q*100),v,math.log(2)/v*3600))
    # Laplace: lambda where E[exp(-lambda V)] = 0.5
    lo,hi=0,1
    for _ in range(60):
        m=(lo+hi)/2
        if sum(math.exp(-m*v) for v in V)/len(V)>0.5: lo=m
        else: hi=m
    print('  %s lambda* over full V distribution (E[e^-lV]=0.5) = %.2f lands/h'%(name,lo*3600))
# peak rates
def rate(a,b):
    n=sum(1 for r in lands if a<=r['ts_end']<b); h=(t(b)-t(a))/3600; return n,h,n/h
for a,b in (('2026-09-22T18:45:00Z','2026-09-22T20:20:00Z'),('2026-09-23T02:45:00Z','2026-09-23T05:10:00Z'),('2026-09-22T00:00:00Z','2026-09-24T00:00:00Z'),('2026-09-21T04:00:00Z','2026-09-21T06:00:00Z')):
    n,h,rt=rate(a,b); print('lands %s..%s: %d in %.2fh = %.2f/h'%(a,b,n,h,rt))
