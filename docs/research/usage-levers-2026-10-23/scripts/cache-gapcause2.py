import pickle,collections,json
R=pickle.load(open('/tmp/usage-audit/cache-rows.pkl','rb'))
def M(x): return f"{x/1e6:,.1f}M"
def rel(p): return p.split('/projects/',1)[1]
seen=set(); B=[]
for r in R:
    k=(rel(r['file']),r['ts'],r['cc'])
    if k in seen: continue
    seen.add(k)
    if r['kind']=='bust' and r['gap']>300: B.append(r)
byfile=collections.defaultdict(list)
for r in B: byfile[r['file']].append(r)
tool=collections.Counter(); toolcc=collections.Counter(); trig=collections.Counter(); trigcc=collections.Counter(); samples=collections.defaultdict(list)
for f,bs in byfile.items():
    recs=[]
    for line in open(f,errors='replace'):
        try: d=json.loads(line)
        except: continue
        recs.append(d)
    for b in bs:
        # index of first assistant rec with ts == b.ts
        idx=next((i for i,d in enumerate(recs) if d.get('type')=='assistant' and d.get('timestamp')==b['ts']),None)
        if idx is None: continue
        # previous assistant record before the gap
        pa=None
        for j in range(idx-1,-1,-1):
            d=recs[j]
            if d.get('type')=='assistant' and d.get('timestamp','')<b['ts'] and (b['t']-0)>0:
                pa=d; break
        th='sub' if b['sub'] else 'main'
        name='(text/no tool)'; detail=''
        if pa:
            for c in (pa.get('message') or {}).get('content') or []:
                if isinstance(c,dict) and c.get('type')=='tool_use':
                    name=c.get('name'); inp=c.get('input') or {}
                    detail=(inp.get('command') or inp.get('prompt') or inp.get('description') or json.dumps(inp))[:110].replace('\n',' ')
                    if inp.get('run_in_background'): name+='(bg)'
            if pa.get('message',{}).get('stop_reason')=='end_turn' and name=='(text/no tool)': name='(end_turn)'
        tool[(th,name)]+=1; toolcc[(th,name)]+=b['cc']
        samples[(th,name)].append(f"gap={b['gap']/60:.0f}m cc={b['cc']} {detail}")
        # what woke it: records between pa and bust
        kinds=set()
        for d in recs[(recs.index(pa)+1 if pa else 0):idx]:
            t=d.get('type')
            if t=='user':
                m=d.get('message',{}); c=m.get('content')
                s=c if isinstance(c,str) else ' '.join((x.get('text') or str(x.get('content'))[:200]) for x in c if isinstance(x,dict)) if isinstance(c,list) else ''
                if isinstance(c,list) and any(isinstance(x,dict) and x.get('type')=='tool_result' for x in c): kinds.add('tool_result')
                elif '<task-notification>' in s: kinds.add('task-notification')
                elif 'autonomous-loop' in s or '<<' in s[:5]: kinds.add('loop/sentinel')
                elif d.get('isMeta'): kinds.add('meta')
                else: kinds.add('human/other prompt')
            elif t=='attachment':
                a=d.get('attachment') or {}
                if a.get('type') in ('queued_command',): kinds.add('queued_command')
        k=(th,'+'.join(sorted(kinds)) or 'none')
        trig[k]+=1; trigcc[k]+=b['cc']

cat=__import__('collections').Counter(); catcc=__import__('collections').Counter()
import re
with open('/tmp/usage-audit/cache-sub-bash-busts.txt','w') as o:
    for x in samples[('sub','Bash')]:
        o.write(x+"\n")
        m=re.search(r'timeout (\d+)',x); t=int(m.group(1)) if m else 0
        cc=int(re.search(r'cc=(\d+)',x).group(1))
        k='timeout>300' if t>300 else ('poll-loop' if re.search(r'until |while |range\(|sleep',x) else ('test-runner' if re.search(r'pytest|bats|npm test|cargo test|go test',x) else 'other'))
        cat[k]+=1; catcc[k]+=cc
for k,v in cat.most_common(): print(k,v,f"{catcc[k]/1e6:.1f}M")
