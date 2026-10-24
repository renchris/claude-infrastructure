import json,collections,re
G=json.load(open('G.json'))
want=collections.defaultdict(list)
for g in G:
    if g['busy_nn'] and g['reb'] and not g['term'] and g['stop']+3300<g['end']:
        want[g['sid']].append(g['stop']+3300)
F={}
for a in ['next','next2','next3','next4']:
    for line in open(a+'.jsonl'):
        f=json.loads(line)
        if f['fsid'] in want: F[f['fsid']]=f
IDRX=re.compile(r'with ID:?\s*([a-z0-9]{6,12})',re.I)
where=collections.Counter(); ex=[]
for sid,wts in want.items():
    f=F[sid]; notes={tu for t,tu in f['notes']}; last=max(x[9] for x in f['reqs'])
    tus={tu for tu,(js,kd,tmo) in f['jobs'].items() if kd in('bash','agent','workflow') and tu not in notes and any(js<=wt<last for wt in wts)}
    if not tus: continue
    lines=open(f['path'],errors='ignore').read().split('\n')
    for line in lines:
        if '"tool_result"' not in line: continue
        for tu in tus:
            if tu not in line: continue
            m=IDRX.search(line)
            if not m: continue
            t=m.group(1)
            seen=set()
            for l2 in lines:
                if t in l2 and tu not in l2:
                    try: r=json.loads(l2)
                    except Exception: continue
                    typ=r.get('type'); sub=r.get('subtype') or ((r.get('attachment') or {}).get('type') if isinstance(r.get('attachment'),dict) else '')
                    c=(r.get('message') or {}).get('content')
                    tl=''
                    if isinstance(c,list):
                        for b in c:
                            if isinstance(b,dict) and b.get('type')=='tool_use': tl='tool_use:'+b.get('name','')
                            if isinstance(b,dict) and b.get('type')=='tool_result': tl='tool_result'
                    seen.add((typ,sub,tl,'<task-id>' in l2))
            where[tuple(sorted(seen))[:4] if seen else ('never mentioned again',)]+=1
            if seen and len(ex)<3: ex.append([l2[:300] for l2 in lines if t in l2 and tu not in l2][:2])
for k,v in where.most_common(12): print(v,k)
for e in ex: print('---',e)
