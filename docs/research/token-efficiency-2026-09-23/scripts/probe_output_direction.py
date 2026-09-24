import json, glob, os, random, collections
random.seed(9)
fl=[]
for c in ['~/.claude','~/.claude-secondary','~/.claude-tertiary','~/.claude-quaternary']:
    r=os.path.expanduser(c)+'/projects'
    fl+=glob.glob(r+'/*/*.jsonl')+glob.glob(r+'/*/*/subagents/agent-*.jsonl')+glob.glob(r+'/*/*/subagents/workflows/*/agent-*.jsonl')
fl=sorted(fl,key=os.path.getmtime)[-2000:]
sample=random.sample(fl,120)
c=collections.Counter(); firstsum=0; maxsum=0; lastsum=0
for f in sample:
    d={}
    for line in open(f,errors='replace'):
        if '"usage"' not in line: continue
        try:r=json.loads(line)
        except: continue
        m=r.get('message')
        if not isinstance(m,dict) or not isinstance(m.get('usage'),dict): continue
        d.setdefault(m.get('id'),[]).append((m['usage'].get('output_tokens') or 0, m.get('stop_reason'), [b.get('type') for b in m.get('content',[]) if isinstance(b,dict)]))
    for mid,L in d.items():
        outs=[x[0] for x in L]
        firstsum+=outs[0]; maxsum+=max(outs); lastsum+=outs[-1]
        if len(set(outs))>1:
            c['nonmono' if outs!=sorted(outs) else 'increasing']+=1
            c['last_is_max' if outs[-1]==max(outs) else 'last_not_max']+=1
            c['stop_on_last' if L[-1][1] else 'nostop_last']+=1
            c['firstblock:'+str(L[0][2])]+=1
        c['n']+=1
print(c); print('first',firstsum,'max',maxsum,'last',lastsum, 'max/first',maxsum/firstsum)
