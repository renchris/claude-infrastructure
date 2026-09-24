import json, glob, os, random, collections, re
random.seed(13)
fl=[]
for c in ['~/.claude','~/.claude-secondary','~/.claude-tertiary','~/.claude-quaternary']:
    r=os.path.expanduser(c)+'/projects'; fl+=glob.glob(r+'/*/*.jsonl')
fl=[f for f in fl if os.path.getmtime(f)>1789000000]
c=collections.Counter(); o=collections.Counter()
for f in random.sample(fl,150):
    for line in open(f,errors='replace'):
        if '"type":"user"' not in line[:400] and '"type": "user"' not in line[:400]:
            try: r=json.loads(line)
            except: continue
            if r.get('type')!='user': continue
        else: r=json.loads(line)
        m=r['message']; cont=m.get('content')
        if isinstance(cont,list):
            if any(isinstance(b,dict) and b.get('type')=='tool_result' for b in cont): continue
            cont=' '.join(b.get('text','') for b in cont if isinstance(b,dict) and b.get('type')=='text')
        s=re.sub(r'[0-9a-f]{6,}','H',re.sub(r'\d+','N',(cont or '').lstrip()[:28]))
        key=('meta' if r.get('isMeta') else 'user', s)
        c[key]+=1
        if not r.get('isMeta'): o[(json.dumps(r.get('origin'))[:40], r.get('promptSource'))]+=1
for k,v in c.most_common(45): print(v,k)
print(o.most_common(12))
