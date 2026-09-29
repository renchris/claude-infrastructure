import json,glob,os,sys
audit=[json.loads(l) for l in open('audit_snapshot.jsonl')]
asks=[r for r in audit if r['decision']=='ask']
ids={r['tool_use_id'] for r in asks}
sids={r['session_id'] for r in asks}
files=[]
for root in ['/Users/chrisren/.claude/projects','/Users/chrisren/.claude-tertiary/projects','/Users/chrisren/.claude-quaternary/projects','/Users/chrisren/.claude-next4/projects','/Users/chrisren/.claude-secondary/projects']:
    for pd in os.listdir(root):
        p=os.path.join(root,pd)
        if not os.path.isdir(p): continue
        for s in sids:
            f=os.path.join(p,s+'.jsonl')
            if os.path.exists(f): files.append(f)
            sd=os.path.join(p,s)
            if os.path.isdir(sd): files+=glob.glob(sd+'/**/*.jsonl',recursive=True)
files=sorted(set(os.path.realpath(f) for f in files))
print('files',len(files),file=sys.stderr)
out={}
for f in files:
    with open(f,errors='replace') as fh:
        for l in fh:
            if 'tool_result' not in l: continue
            if not any(i in l for i in ()) and 'toolu_' not in l: continue
            try: d=json.loads(l)
            except: continue
            c=(d.get('message') or {}).get('content')
            if not isinstance(c,list): continue
            for it in c:
                if isinstance(it,dict) and it.get('type')=='tool_result' and it.get('tool_use_id') in ids:
                    txt=it.get('content')
                    if isinstance(txt,list): txt=' '.join(x.get('text','') for x in txt if isinstance(x,dict))
                    out[it['tool_use_id']]={'is_error':bool(it.get('is_error')),'text':str(txt)[:400],'ts':d.get('timestamp'),'file':f}
json.dump(out,open('results.json','w'))
print('matched',len(out),'of',len(ids),file=sys.stderr)
