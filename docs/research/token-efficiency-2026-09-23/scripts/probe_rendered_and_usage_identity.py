import json, glob, os, random, collections
random.seed(5)
fl=[]
for c in ['~/.claude','~/.claude-secondary','~/.claude-tertiary','~/.claude-quaternary']:
    r=os.path.expanduser(c)+'/projects'
    fl+=glob.glob(r+'/*/*.jsonl')+glob.glob(r+'/*/*/subagents/agent-*.jsonl')+glob.glob(r+'/*/*/subagents/workflows/*/agent-*.jsonl')
fl=sorted(fl,key=os.path.getmtime)[-1500:]
sample=random.sample(fl,80)
rshape=collections.Counter(); rlen=collections.defaultdict(list); same=collections.Counter(); stopdist=collections.Counter()
ex_shown=set(); iters_n=collections.Counter(); itdiff=0
for f in sample:
    seen={}
    for line in open(f,errors='replace'):
        try:r=json.loads(line)
        except: continue
        t=r.get('type')
        if t=='attachment' and 'rendered' in r:
            at=r['attachment'].get('type'); rd=r['rendered']
            shape=json.dumps([ (sorted(x.keys()) if isinstance(x,dict) else type(x).__name__) for x in rd[:2]])[:200]
            rshape[(at,shape)]+=1
            if at not in ex_shown and rd:
                ex_shown.add(at)
                x=rd[0]
                if isinstance(x,dict):
                    print(at, {k:(v if k!='content' and k!='message' else ('<'+type(v).__name__+'>')) for k,v in x.items()} )
                    msg = x.get('message') if isinstance(x.get('message'),dict) else None
                    if msg: print('   msg keys', list(msg.keys()), 'content type', type(msg.get('content')).__name__, (json.dumps(msg.get('content'))[:0]))
        elif t=='assistant':
            m=r['message']; mid=m.get('id'); u=json.dumps(m.get('usage'),sort_keys=True)
            it=(m.get('usage') or {}).get('iterations') or []
            iters_n[len(it)]+=1
            if it and len(it)==1:
                i0=it[0]
                if i0.get('input_tokens')!=m['usage'].get('input_tokens') or i0.get('output_tokens')!=m['usage'].get('output_tokens'): itdiff+=1
            if mid in seen:
                same['same' if seen[mid][0]==u else 'diff']+=1
                if seen[mid][0]!=u:
                    a=json.loads(seen[mid][0]); b=json.loads(u)
                    same['diffkeys:'+','.join(k for k in set(a)|set(b) if a.get(k)!=b.get(k))]+=1
            else: seen[mid]=(u,m.get('stop_reason'))
            stopdist[(m.get('stop_reason') is None, [b.get('type') for b in m.get('content',[]) if isinstance(b,dict)][:1].__str__())]+=1
for k,v in rshape.most_common(40): print(v,k)
print(same); print('iters len',iters_n,'itdiff',itdiff); print(stopdist.most_common(12))
