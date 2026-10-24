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
# where else does each unmatched tool-use id appear in the transcript?
where=collections.Counter(); n=0
for sid,wts in list(want.items()):
    f=F[sid]; notes={tu for t,tu in f['notes']}; last=max(x[9] for x in f['reqs'])
    tus={tu for tu,(js,kd,tmo) in f['jobs'].items() if kd in('bash','agent','workflow') and tu not in notes and any(js<=wt<last for wt in wts)}
    if not tus: continue
    for line in open(f['path'],errors='ignore'):
        for tu in tus:
            if tu in line:
                try: r=json.loads(line)
                except Exception: continue
                typ=r.get('type'); sub=r.get('subtype') or ((r.get('attachment') or {}).get('type') if isinstance(r.get('attachment'),dict) else '')
                c=(r.get('message') or {}).get('content')
                tr=isinstance(c,list) and any(isinstance(b,dict) and b.get('type')=='tool_result' for b in c)
                isuse=isinstance(c,list) and any(isinstance(b,dict) and b.get('type')=='tool_use' and b.get('id')==tu for b in c)
                k=(typ,sub,'tool_result' if tr else '','tool_use' if isuse else '','task-notif' if 'task-notification' in line else '')
                where[k]+=1
    n+=1
    if n>=60: break
for k,v in where.most_common(): print(v,k)
