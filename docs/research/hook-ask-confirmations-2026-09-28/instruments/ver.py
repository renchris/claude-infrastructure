import os,re,json,collections
ca=[json.loads(l) for l in open('/Users/chrisren/.reso/curl-audit.jsonl')]
tids={r['tool_use_id']:r for r in ca if r['decision']=='ask' and (r.get('tool_use_id') or '').startswith('toolu_')}
print('curl ask tids',len(tids))
att=set()
for l in open('asks2.jsonl'):
    r=json.loads(l)
    if (r['hook'] or '').endswith('curl-gate-scope.sh'): att.add(r['tid'])
roots=[os.path.expanduser(p) for p in ['~/.claude/projects','~/.claude-secondary/projects','~/.claude-tertiary/projects','~/.claude-quaternary/projects','~/.claude-next4/projects']]
seen=set();found={}
idre=re.compile(rb'"type":"tool_use","id":"(toolu_[A-Za-z0-9_]+)"')
vre=re.compile(rb'"version":"([0-9.]+)"')
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
                if b'"tool_use"' not in line: continue
                for m in idre.finditer(line):
                    t=m.group(1).decode()
                    if t in tids and t not in found:
                        v=vre.search(line); found[t]=v.group(1).decode() if v else '?'
print('found in transcripts',len(found))
c=collections.Counter((v, t in att) for t,v in found.items())
for k in sorted(c): print(k,c[k])
m=collections.Counter()
for t,r in tids.items(): m[(r['ts'][:7], t in found)]+=1
print(sorted(m.items()))
