import pickle,collections,bisect
R=pickle.load(open('/tmp/usage-audit/cache-rows.pkl','rb'))
def M(x): return f"{x/1e6:,.1f}M"
CC=sum(r['cc'] for r in R)
# bust by thread x gap bucket
def gb(g):
    for lim,l in [(300,'<5m'),(600,'5-10m'),(1800,'10-30m'),(3600,'30-60m'),(7200,'1-2h'),(28800,'2-8h')]:
        if g<lim: return l
    return '>8h'
t=collections.defaultdict(lambda:[0,0]); 
for r in R:
    if r['kind']!='bust': continue
    k=('sub' if r['sub'] else 'main',gb(r['gap'])); t[k][0]+=1; t[k][1]+=r['cc']
print('BUSTS by thread x preceding gap')
for k in sorted(t): print('  ',k,'n',t[k][0],'cc',M(t[k][1]),f"{t[k][1]/CC:.1%} of all cc")
# hit rate: for non-first requests, P(bust | gap bucket, thread)
h=collections.defaultdict(lambda:[0,0])
for r in R:
    if r['kind']=='first': continue
    k=('sub' if r['sub'] else 'main',gb(r['gap'])); h[k][0]+=1; h[k][1]+=(r['kind']=='bust')
print('P(bust | thread, gap)')
for k in sorted(h): print('  ',k,'requests',h[k][0],'busts',h[k][1],f"rate {h[k][1]/h[k][0]:.1%}")
# git commit correlation, main thread, gap<300
cts=[]
for line in open('/tmp/usage-audit/cache-gitlog.txt'):
    if line.startswith('C '): cts.append(int(line.split()[1]))
cts.sort()
a=[0,0];b=[0,0]
for r in R:
    if r['kind']=='first' or r['gap']>=300: continue
    lo=r['t']-r['gap']; i=bisect.bisect_left(cts,lo)
    span= i<len(cts) and cts[i]<=r['t']+1
    x=a if span else b; x[0]+=1; x[1]+=(r['kind']=='bust')
print(f"git: requests (gap<5m) whose interval spans an always-loaded-file commit: {a[0]} busts {a[1]}; others {b[0]} busts {b[1]} rate {b[1]/b[0]:.3%}; commits={len(cts)}")
# events correlation (gap<300 non-first)
ev=collections.defaultdict(lambda:[0,0])
for r in R:
    if r['kind']=='first' or r['gap']>=300: continue
    for e in (r['events'].split(',') if r['events'] else ['(none)']):
        ev[e][0]+=1; ev[e][1]+=(r['kind']=='bust')
print('events preceding request (gap<5m): n, busts')
for e,v in sorted(ev.items(),key=lambda x:-x[1][0])[:30]: print(f"   {e:40s} {v[0]:7d} {v[1]:4d} {v[1]/v[0]:.2%}")
# model/effort/version switch outcomes
for lab,f in [('model',lambda r:r['model']!=r['pmodel']),('effort',lambda r:r['effort']!=r['peff']),('version',lambda r:r['ver']!=r['pver'])]:
    s=[r for r in R if r['kind']!='first' and f(r)]
    print(f"switch {lab}: n={len(s)} busts={sum(r['kind']=='bust' for r in s)} cc={M(sum(r['cc'] for r in s))} lost={M(sum(max(0,r['lost']) for r in s))}")
# unexplained detail
u=[r for r in R if r['kind']=='bust' and r['gap']<300]
for r in sorted(u,key=lambda r:-r['cc'])[:25]:
    print(f"  UNEXP {r['acct']} sub={r['sub']} gap={r['gap']:.0f}s cr={r['cr']} cc={r['cc']} lost={r['lost']} model={r['model']}/{r['pmodel']} eff={r['effort']}/{r['peff']} miss={r['miss'][:60]} ev={r['events'][:120]} {r['file'][-60:]}")
