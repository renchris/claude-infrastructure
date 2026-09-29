import os,re,json,collections,glob,bisect,datetime
ca=[json.loads(l) for l in open('/Users/chrisren/.reso/curl-audit.jsonl')]
tids={r['tool_use_id']:r for r in ca if r['decision']=='ask' and (r.get('tool_use_id') or '').startswith('toolu_')}
roots=[os.path.expanduser(p) for p in ['~/.claude/projects','~/.claude-secondary/projects','~/.claude-tertiary/projects','~/.claude-quaternary/projects','~/.claude-next4/projects']]
seen=set();out={}
tre=re.compile(rb'"tool_use_id":"(toolu_[A-Za-z0-9_]+)"')
for r in roots:
    for dp,dn,fn in os.walk(r,followlinks=True):
        for f in fn:
            if not f.endswith('.jsonl'): continue
            p=os.path.realpath(os.path.join(dp,f))
            if p in seen: continue
            seen.add(p)
            try: b=open(p,'rb').read()
            except Exception: continue
            if b'curl' not in b: continue
            for line in b.split(b'\n'):
                if b'"tool_result"' not in line: continue
                m=tre.search(line)
                if not m: continue
                t=m.group(1).decode()
                if t not in tids: continue
                try: o=json.loads(line)
                except Exception: continue
                for it in (o.get('message') or {}).get('content') or []:
                    if isinstance(it,dict) and it.get('type')=='tool_result' and it.get('tool_use_id')==t:
                        cc=it.get('content')
                        if isinstance(cc,list): cc=' '.join(x.get('text','') for x in cc if isinstance(x,dict))
                        S=str(cc)
                        k='denied' if (S.startswith('Permission to use') and 'has been denied' in S[-300:]) else ('user-rejected' if ("doesn't want to proceed" in S[:400]) else 'ran')
                        out[t]=(k,o.get('timestamp'))
print('curl ask tids',len(tids),'with tool_result',len(out),collections.Counter(v[0] for v in out.values()))
arch=[]
for f in glob.glob('/Users/chrisren/.claude/autonomy/permission-archive/*.jsonl'):
    for l in open(f,errors='replace'): arch.append(json.loads(l))
by=collections.defaultdict(list)
for r in arch: by[r['session_id']].append(r)
def ep(s): return datetime.datetime.strptime(s,'%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=datetime.timezone.utc).timestamp()
c=collections.Counter()
for t,(k,_) in out.items():
    a=tids[t]; ts=ep(a['ts'])
    cand=[x for x in by.get(a['session_id'],[]) if abs(x['ts']-ts)<=15]
    if not cand: c[(k,'noarch')]+=1; continue
    x=min(cand,key=lambda x:abs(x['ts']-ts))
    sig='nosig' if not x.get('tool_sig') else ('match' if x.get('tool_sig')==x.get('cleared_tool_sig') else 'mismatch')
    c[(k,x['resolved_by'],sig)]+=1
for k in sorted(c): print(k,c[k])
