import pickle,collections
R=pickle.load(open('/tmp/usage-audit/cache-rows.pkl','rb'))
def M(x): return f"{x/1e6:,.1f}M"
c=collections.defaultdict(lambda:[0,0,0])
for r in R:
    k=(r['acct'],'sub' if r['sub'] else 'main', 'side' if r['side'] else '')
    c[k][0]+=r['cc1h']; c[k][1]+=r['cc5m']; c[k][2]+=1
for k in sorted(c): v=c[k]; print(k,'n',v[2],'cc1h',M(v[0]),'cc5m',M(v[1]),f"5m share {v[1]/max(1,v[0]+v[1]):.0%}")
# 5m by version / model main only
c2=collections.defaultdict(lambda:[0,0,0])
for r in R:
    if r['sub']: continue
    k=(r['ver'][:9],r['model'])
    c2[k][0]+=r['cc1h']; c2[k][1]+=r['cc5m']; c2[k][2]+=1
print('--- main thread by version/model')
for k,v in sorted(c2.items(),key=lambda x:-(x[1][0]+x[1][1]))[:15]: print(k,'n',v[2],'cc1h',M(v[0]),'cc5m',M(v[1]),f"5m share {v[1]/max(1,v[0]+v[1]):.0%}")
# per-file TTL mix in main files
mix=collections.Counter()
for f in set(r['file'] for r in R if not r['sub']): pass
