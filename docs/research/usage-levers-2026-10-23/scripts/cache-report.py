import pickle,collections
R=pickle.load(open('/tmp/usage-audit/cache-rows.pkl','rb'))
def M(x): return f"{x/1e6:,.1f}M"
def cause(r):
    ev=r['events']
    if r['model']!=r['pmodel']: return 'model_switch'
    if r['gap']>3600: return 'gap>1h'
    if 'compact' in ev or r['shrink']: return 'compaction/shrink'
    if r['gap']>300 and r['cc5m']>0: return 'gap>5m(5m-ttl)'
    if r['ver']!=r['pver']: return 'version_change'
    if r['effort']!=r['peff']: return 'effort_switch'
    if r['gap']>300: return 'gap5m-1h(1h-ttl)'
    return 'unexplained(<5m,same model)'
for a in ['next','next2','next3','next4','ALL']:
    rs=[r for r in R if a=='ALL' or r['acct']==a]
    s=lambda k,f=lambda r:True: sum(r[k] for r in rs if f(r))
    IN,CC,CR,OUT=s('in'),s('cc'),s('cr'),s('out')
    print(f"== {a}: requests={len(rs)} files={len(set(r['file'] for r in rs))} input={M(IN)} cc={M(CC)} cr={M(CR)} out={M(OUT)}  cc:cr:in = {CC/IN:.1f}:{CR/IN:.1f}:1  cc/cr={CC/CR:.3f}  cc share of prompt={CC/(CC+CR+IN):.3f}  cc5m={M(s('cc5m'))}")
    for lab,f in [('first-req main file',lambda r:r['kind']=='first' and not r['sub']),('first-req subagent file',lambda r:r['kind']=='first' and r['sub']),('mid-session bust',lambda r:r['kind']=='bust'),('normal incremental',lambda r:r['kind']=='normal')]:
        n=sum(1 for r in rs if f(r)); c=s('cc',f)
        print(f"   {lab:26s} n={n:6d} cc={M(c):>9s} ({c/CC:.1%})")
    b=[r for r in rs if r['kind']=='bust']
    rew=sum(min(r['cc'],r['lost']) for r in b)
    print(f"   bust rewritten-prefix tokens={M(rew)} ({rew/CC:.1%} of cc); bust main={sum(r['cc'] for r in b if not r['sub'])/CC:.1%} sub={sum(r['cc'] for r in b if r['sub'])/CC:.1%}")
    cc_=collections.Counter(); cn=collections.Counter()
    for r in b: k=cause(r); cc_[k]+=r['cc']; cn[k]+=1
    for k,v in cc_.most_common(): print(f"      cause {k:30s} n={cn[k]:5d} cc={M(v):>8s} ({v/CC:.1%} of all cc, {v/sum(cc_.values()):.0%} of bust cc)")
