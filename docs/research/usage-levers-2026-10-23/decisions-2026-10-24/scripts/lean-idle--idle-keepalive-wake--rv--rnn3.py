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
IDRX=re.compile(r'(?:with ID|task[_ -]?id|Task ID|ID)[:=]?\s*`?([a-z0-9]{6,12})`?',re.I)
res=collections.Counter(); samples=[]
for sid,wts in want.items():
    f=F[sid]; notes={tu for t,tu in f['notes']}; last=max(x[9] for x in f['reqs'])
    tus={tu for tu,(js,kd,tmo) in f['jobs'].items() if kd in('bash','agent','workflow') and tu not in notes and any(js<=wt<last for wt in wts)}
    if not tus: continue
    lines=open(f['path'],errors='ignore').read().split('\n')
    tid={}
    for line in lines:
        if '"tool_result"' not in line: continue
        for tu in tus:
            if tu in line:
                try: r=json.loads(line)
                except Exception: continue
                for b in (r.get('message') or {}).get('content') or []:
                    if isinstance(b,dict) and b.get('tool_use_id')==tu:
                        c=b.get('content'); c=c if isinstance(c,str) else json.dumps(c)
                        m=IDRX.search(c)
                        tid[tu]=(m.group(1) if m else None, c[:160])
    for tu in tus:
        t,c=tid.get(tu,(None,''))
        if not t: res['no id in result']+=1; 
        else:
            hit=[l for l in lines if '<task-id>'+t+'</task-id>' in l]
            if hit:
                r=json.loads(hit[0]); res['notif by task-id found, type=%s'%r.get('type')]+=1
                if len(samples)<4: samples.append(hit[0][:400])
            else: res['no notification at all']+=1
        if len(samples)<8 and not t: samples.append('RESULT: '+c)
print(dict(res))
for s in samples: print('---',s)
