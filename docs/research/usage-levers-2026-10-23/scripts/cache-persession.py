import pickle,collections,statistics as st
R=pickle.load(open('/tmp/usage-audit/cache-rows.pkl','rb'))
def rel(p): return p.split('/projects/',1)[1]
seen=set(); F=collections.defaultdict(lambda:[0,0,0,0])
for r in R:
    k=(rel(r['file']),r['ts'],r['cc'])
    if k in seen: continue
    seen.add(k); x=F[(rel(r['file']),r['sub'])]; x[0]+=r['cc']; x[1]+=r['cr']; x[2]+=r['in']; x[3]+=1
for sub in (0,1):
    v=[(c/(c+cr+i)) for (f,s),(c,cr,i,n) in F.items() if s==sub and n>=5]
    v.sort(); q=lambda p:v[int(p*(len(v)-1))]
    print(f"{'subagent' if sub else 'main'} files(>=5 req) n={len(v)}: per-file cc/(cc+cr+in) median={q(.5):.1%} p10={q(.1):.1%} p90={q(.9):.1%}")
