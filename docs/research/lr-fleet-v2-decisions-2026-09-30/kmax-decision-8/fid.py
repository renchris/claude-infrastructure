exec(open('/tmp/kmaxq/count.py').read().split("print(f\"{'ts'")[0])
import collections
d=collections.Counter(); absd=0; n=0
for r in rows:
    kw=r['k_work']; k=r['k']
    if kw is None: continue
    T=P(r['ts']); a=r['acct']
    hit=[f for f in F if f['acct']==a and any(T-600<t<=T for t in f['ts'])]
    top=sum(f['top'] for f in hit); sub=len(hit)-top
    rec=min(top,k)+sub; d[rec-kw]+=1; absd+=abs(rec-kw); n+=1
print(n, sorted(d.items()), 'mean|diff|', absd/n)
