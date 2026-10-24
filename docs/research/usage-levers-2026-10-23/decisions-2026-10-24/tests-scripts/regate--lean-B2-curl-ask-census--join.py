import json, sys, os, glob
D=sys.argv[1]
ci=json.load(open(D+'/ci30.json'))
want={r['tool_use_id'] for r in ci if r['tool_use_id']!='unknown'}
files=[]
for p in open(D+'/ci30-paths.txt').read().split():
    if p.endswith('.jsonl'): files.append(p)
    else: files+=glob.glob(p+'/subagents/**/*.jsonl',recursive=True)
if len(sys.argv)>2: files=open(sys.argv[2]).read().split()
res={}
def txt(c):
    if isinstance(c,str): return c
    if isinstance(c,list): return ' '.join(x.get('text','') for x in c if isinstance(x,dict))
    return ''
for f in files:
    with open(f,errors='replace') as fh:
        for ln in fh:
            if 'tool_result' not in ln: continue
            if not any(t in ln for t in want): continue
            try: o=json.loads(ln)
            except Exception: continue
            c=(o.get('message') or {}).get('content')
            if not isinstance(c,list): continue
            for b in c:
                if isinstance(b,dict) and b.get('type')=='tool_result' and b.get('tool_use_id') in want:
                    res.setdefault(b['tool_use_id'],[]).append((txt(b.get('content')),f))
json.dump({k:[(t[:400],f) for t,f in v] for k,v in res.items()},open(D+'/join-out.json','w'))
print('files scanned',len(files),'wanted',len(want),'found',len(res))
