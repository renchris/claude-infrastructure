import json, datetime as dt, collections as C, subprocess, re
R='/Users/chrisren/Development/reso-management-app'
def G(*a): return subprocess.run(['git','-C',R]+list(a),capture_output=True,text=True).stdout
rows=[json.loads(l) for l in open('/Users/chrisren/.reso/land.log') if l.startswith('{"v":3')]
t=lambda s: dt.datetime.strptime(s,'%Y-%m-%dT%H:%M:%SZ').timestamp()
w=[r for r in rows if r['ts_start']>='2026-09-16T04:59:00Z' and not (r['exit']==0 and r['rounds']==0)]
lands=sorted([r for r in w if r['exit']==0],key=lambda r:r['ts_end'])
# landed ranges: first-parent predecessor head
fp=G('rev-list','--first-parent','origin/main','-n','400').split()
idx={c:i for i,c in enumerate(fp)}
heads=[r['head'] for r in lands]
files={}
for r in lands:
    h=r['head']
    # previous landed head = nearest older first-parent commit that is a logged head, else walk until another head
    i=idx.get(h)
    if i is None: files[h]=set(); continue
    j=i+1
    while j<len(fp) and fp[j] not in set(heads): j+=1
    base=fp[j] if j<len(fp) else fp[i]+'~1'
    files[h]=set(G('diff','--name-only',base,h).split())
INERT=re.compile(r'\.(md|mdx|txt|sh|bash|bats|py|yml|yaml|toml|png|jpe?g|webp|gif|avif|ico|svg|pdf|mmd|csv|log|patch)$',re.I)
CODE=re.compile(r'^(src|lib|replicache)/.*\.(ts|tsx)$')
def klass(fs):
    if not fs: return 'empty'
    if all(INERT.search(f) for f in fs): return 'tsc-inert'
    if any(CODE.search(f) for f in fs): return 'code'
    return 'noncode-ts/json'
def own(r):
    h=r['head']
    if h in files: return files[h]
    mb=G('merge-base',h,'origin/main').strip()
    return set(G('diff','--name-only',mb,h).split())
land_t=[(t(r['ts_end'])-2,r) for r in lands]
def dur(p): return sum((p.get(k) or 0) for k in ('reconcile_s','tsc_s','sem_wait_s','suite_s','push_s'))
res=[]
for r in w:
    pr=r['per_round']
    if not pr: continue
    end=t(r['ts_end'])-2; wins=[]
    for i in range(len(pr)-1,-1,-1):
        d=dur(pr[i]); s=end-d; wins.append((i,s,end,pr[i])); end=s-3.5
    myf=own(r); mydirs={'/'.join(f.split('/')[:2]) for f in myf}
    for i,s,e,p in wins:
        if p.get('push_rc') in (None,0): continue
        tail=p.get('push_tail') or ''
        if not (p['rc']==99 or 'cannot lock ref' in tail): continue
        comp=[x for tt,x in land_t if s<tt<e and x['branch']!=r['branch']]
        inc=set().union(*[files.get(x['head'],set()) for x in comp]) if comp else set()
        ov=myf & inc; dov=mydirs & {'/'.join(f.split('/')[:2]) for f in inc}
        res.append((r['branch'][:24],i+1,p.get('sem_wait_s'),klass(inc),len(ov),sorted(ov)[:3],len(dov),[x['branch'][:18] for x in comp]))
for x in res: print(x)
print('incoming class:',C.Counter(x[3] for x in res))
print('lost rounds with file overlap:',sum(1 for x in res if x[4]>0),'of',len(res))
print('lost rounds with top-2-dir overlap:',sum(1 for x in res if x[6]>0),'of',len(res))
