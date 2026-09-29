import json,re,collections,os
files=[l.strip() for l in open('files.txt')]
askre=re.compile(r'"permissionDecision"\s*:\s*"ask"')
seen=collections.defaultdict(list)
for f in files:
    for line in open(f,errors='replace'):
        if 'hook_success' in line and 'ask' in line:
            try: r=json.loads(line)
            except Exception: continue
            a=r.get('attachment') or {}
            if a.get('type')!='hook_success' or not askre.search(a.get('stdout') or ''): continue
            seen[(a.get('toolUseID'),os.path.basename(a.get('command','')))].append((f,r.get('uuid')))
c=collections.Counter()
for k,v in seen.items():
    if len(v)>1:
        fs=set(x[0] for x in v); us=set(x[1] for x in v)
        c[('samefile' if len(fs)==1 else 'difffiles', 'sameuuid' if len(us)==1 else 'diffuuid', len(v))]+=1
print(c)
ex=[v for v in seen.values() if len(v)>1 and len(set(x[0] for x in v))>1][:2]
for v in ex: print([x[0].replace('/Users/chrisren/','~/')[-110:] for x in v])
