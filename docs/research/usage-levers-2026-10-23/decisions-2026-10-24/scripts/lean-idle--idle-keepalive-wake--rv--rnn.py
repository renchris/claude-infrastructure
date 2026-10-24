import json,collections,re
S,E=1791655200,1792864800
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
kinds=collections.Counter(); ids=collections.defaultdict(set); per_gap_jobs=collections.Counter()
for sid,wts in want.items():
    f=F[sid]; notes={tu for t,tu in f['notes']}
    last=max(x[9] for x in f['reqs'])
    for wt in wts:
        n=0
        for tu,(js,kd,tmo) in f['jobs'].items():
            if kd in('bash','agent','workflow') and tu not in notes and js<=wt<last:
                kinds[kd]+=1; ids[f['path']].add(tu); n+=1
        per_gap_jobs[min(n,5)]+=1
print('no-notification jobs covering a busy rebuild wake, by kind:',dict(kinds))
print('gaps by # of such jobs:',dict(per_gap_jobs))
# fetch commands + age
cmds=collections.Counter(); ex=[]
for p,tus in ids.items():
    for line in open(p,errors='ignore'):
        if '"tool_use"' not in line: continue
        try: r=json.loads(line)
        except Exception: continue
        for b in (r.get('message') or {}).get('content') or []:
            if isinstance(b,dict) and b.get('id') in tus:
                c=str((b.get('input') or {}).get('command') or (b.get('input') or {}).get('description') or b.get('name'))
                key=re.sub(r'\s+',' ',c)[:70]
                cmds[key.split(' ')[0] if b.get('name')=='Bash' else b.get('name')]+=1
                if len(ex)<25: ex.append((b.get('name'),key))
print(cmds.most_common(20))
for e in ex: print(e)
