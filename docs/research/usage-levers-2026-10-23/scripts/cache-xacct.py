import pickle,collections,re
R=pickle.load(open('/tmp/usage-audit/cache-rows.pkl','rb'))
def M(x): return f"{x/1e6:,.1f}M"
def rel(p): return p.split('/projects/',1)[1]
own=collections.defaultdict(set)
for r in R:
    r['key']=(rel(r['file']),r['ts'],r['cc'],r['cr'],r['out']); own[r['key']].add(r['acct'])
dup=[r for r in R if len(own[r['key']])>1]
uniq={}
for r in R: uniq.setdefault(r['key'],r)
U=list(uniq.values())
print(f"rows={len(R)} unique={len(U)} rows-in>1-acct={len(dup)} dup cc={M(sum(r['cc'] for r in dup))} dup cr={M(sum(r['cr'] for r in dup))}")
CC=sum(r['cc'] for r in U); CR=sum(r['cr'] for r in U); IN=sum(r['in'] for r in U); OUT=sum(r['out'] for r in U)
print(f"DEDUPED: cc={M(CC)} cr={M(CR)} in={M(IN)} out={M(OUT)} cc:cr:in={CC/IN:.0f}:{CR/IN:.0f}:1 cc/(cc+cr+in)={CC/(CC+CR+IN):.2%}")
# account-switch points: in an account's file, request present only in this acct whose prev request (same file) is present in other acct(s) and not this-only
byf=collections.defaultdict(list)
for r in R: byf[(r['acct'],r['file'])].append(r)
sw=[]
for (a,f),rs in byf.items():
    rs.sort(key=lambda r:r['t'])
    for p,r in zip(rs,rs[1:]):
        if own[r['key']]=={a} and len(own[p['key']])>1: sw.append(r)
print(f"account-switch resume points: n={len(sw)} busts={sum(r['kind']=='bust' for r in sw)} cc={M(sum(r['cc'] for r in sw))} cr_mean={sum(r['cr'] for r in sw)/max(1,len(sw)):.0f} cc_mean={sum(r['cc'] for r in sw)/max(1,len(sw)):.0f} sub={sum(r['sub'] for r in sw)}")
gb=collections.Counter()
for r in sw: gb['<5m' if r['gap']<300 else '5m-1h' if r['gap']<3600 else '>1h']+=r['cc']
print('  switch cc by gap',{k:M(v) for k,v in gb.items()})
# Recompute bust table on deduped rows, with account-switch cause first
swk=set(r['key'] for r in sw)
def cause(r):
    if r['key'] in swk: return 'account_switch'
    th='sub(5m TTL)' if r['sub'] else 'main(1h TTL)'
    if r['gap']>3600: return th+' idle>1h'
    if r['gap']>300: return th+' idle 5m-1h'
    return th+' <5m other'
c=collections.Counter(); n=collections.Counter()
for r in U:
    if r['kind']!='bust' and r['key'] not in swk: continue
    k=cause(r); c[k]+=r['cc']; n[k]+=1
B=sum(c.values())
kinds=collections.Counter()
for r in U:
    if r['key'] in swk or r['kind']=='bust': kinds['bust']+=r['cc']
    elif r['kind']=='first': kinds['first-'+('sub' if r['sub'] else 'main')]+=r['cc']
    else: kinds['normal']+=r['cc']
print('DEDUPED cc split:',{k:f"{M(v)} {v/CC:.1%}" for k,v in kinds.items()})
for k,v in c.most_common(): print(f"   {k:28s} n={n[k]:5d} cc={M(v):>8s} {v/CC:.1%} of cc, {v/B:.0%} of bust cc")
# per-account deduped by owner = first acct? report per-account bust share (non-deduped view, own rows)
for a in ['next','next2','next3','next4']:
    rs=[r for r in R if r['acct']==a]; cc=sum(r['cc'] for r in rs)
    b=sum(r['cc'] for r in rs if r['kind']=='bust' or r['key'] in swk)
    s=sum(r['cc'] for r in rs if r['key'] in swk)
    print(f"  {a}: bust share {b/cc:.1%} (acct-switch {s/cc:.1%})")
# per-session (main files) distribution of bust share
ps=[]
for (a,f),rs in byf.items():
    if '/subagents/' in f: continue
    cc=sum(r['cc'] for r in rs)
    if cc<1e6: continue
    b=sum(r['cc'] for r in rs if r['kind']=='bust')
    ps.append((b/cc,cc,a,f))
ps.sort()
import statistics
q=[x[0] for x in ps]
print(f"main sessions with cc>=1M: n={len(ps)} median bust-share={statistics.median(q):.1%} p75={q[int(.75*len(q))]:.1%} p90={q[int(.9*len(q))]:.1%} sessions with any bust={sum(1 for x in q if x>0)}")
for x in sorted(ps,key=lambda x:-x[0]*x[1])[:8]: print(f"   bust {x[0]:.0%} of {M(x[1])} {x[2]} {x[3][-70:]}")
