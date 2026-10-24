import pickle,collections,os
R=pickle.load(open('/tmp/usage-audit/cache-rows.pkl','rb'))
def rel(p): return p.split('/projects/',1)[1]
own=collections.defaultdict(set)
for r in R: own[(rel(r['file']),r['ts'],r['cc'])].add(r['acct'])
c=collections.Counter()
for r in R:
    s=own[(rel(r['file']),r['ts'],r['cc'])]
    if len(s)>1: c[(tuple(sorted(s)),'sub' if r['sub'] else 'main', 'wf' if '/workflows/' in r['file'] else '')]+=1
for k,v in c.most_common(12): print(v,k)
ex=[r['file'] for r in R if '/workflows/wf_b79c16b7' in r['file']][:1]+[r['file'] for r in R if '/workflows/wf_b79c16b7' in r['file'] and r['acct']=='next4'][:1]
for p in ex: print(p, os.path.realpath(p), os.stat(p).st_ino)
