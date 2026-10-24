import json,glob,os,re,collections
rows=json.load(open('/tmp/conv-tests/regate-briefs/ci30_rows.json'))
ids={d['tool_use_id'] for d in rows}
sess={d['session_id'] for d in rows}
files=[]
for root in ['~/.claude','~/.claude-secondary','~/.claude-tertiary','~/.claude-quaternary']:
    for s in sess:
        files+=glob.glob(os.path.expanduser(f'{root}/projects/*/{s}.jsonl'))
        files+=glob.glob(os.path.expanduser(f'{root}/projects/*/{s}/subagents/**/*.jsonl'),recursive=True)
print('files',len(files),'sessions',len(sess))
res={}
for p in files:
    with open(p,errors='replace') as f:
        for l in f:
            if 'tool_use_id' not in l: continue
            if not any(i in l for i in ids if i in l): 
                continue
            try: d=json.loads(l)
            except Exception: continue
            c=(d.get('message') or {}).get('content')
            if not isinstance(c,list): continue
            for x in c:
                if x.get('type')=='tool_result' and x.get('tool_use_id') in ids:
                    t=x.get('content'); t=json.dumps(t) if not isinstance(t,str) else t
                    if "doesn't want to proceed" in t or 'rejected' in t[:200].lower(): v='denied'
                    else: v='granted'
                    res.setdefault(x["tool_use_id"],v)
                    if v=="denied": print("TXT",x["tool_use_id"],t[:200])
print(collections.Counter(res.values()),'unknown',len(ids-set(res)))
for i in sorted(ids):
    if res.get(i)=='denied': print('denied',i,[ (d['ts'],d['host']) for d in rows if d['tool_use_id']==i][:1])
