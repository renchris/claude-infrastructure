import json,os,glob,collections
ids=set(l.strip() for l in open('curl_ids.txt'))
res={}
dirs=[]
for base in ['/Users/chrisren/.claude','/Users/chrisren/.claude-tertiary','/Users/chrisren/.claude-quaternary','/Users/chrisren/.claude-secondary']:
    for d in glob.glob(base+'/projects/*'):
        n=os.path.basename(d)
        if 'reso' in n or 'worktrees' in n: dirs.append(d)
nf=0
for d in dirs:
    for root,_,fs in os.walk(d):
        for f in fs:
            if not f.endswith('.jsonl'): continue
            nf+=1
            p=os.path.join(root,f)
            try:
                for line in open(p,errors='replace'):
                    if '"tool_result"' not in line or 'toolu_' not in line: continue
                    try: r=json.loads(line)
                    except Exception: continue
                    c=(r.get('message') or {}).get('content')
                    if not isinstance(c,list): continue
                    for b in c:
                        if isinstance(b,dict) and b.get('type')=='tool_result' and b.get('tool_use_id') in ids:
                            t=b.get('content')
                            if isinstance(t,list): t=' '.join(x.get('text','') for x in t if isinstance(x,dict))
                            t=str(t)
                            res[b['tool_use_id']]=('denied' if t.startswith('Permission to use') and 'has been denied' in t else 'user-rejected' if "doesn't want to proceed" in t else 'ran', t[:120])
            except Exception: pass
print('files',nf,'ids',len(ids),'with result',len(res))
print(collections.Counter(v[0] for v in res.values()))
json.dump(res,open('curl_res.json','w'))
