import json,re,sys,random
sys.path.insert(0,'/tmp/lean-idle/workflow-lean')
slots=[json.loads(l) for l in open('/tmp/lean-idle/workflow-lean/slots.jsonl')]
cls=sys.argv[1]; n=int(sys.argv[2]); rx=re.compile(sys.argv[3])
wd=[s for s in slots if s['agentType']=='workflow-subagent' and s['site_verdict']=='would-deny' and s['cls']==cls]
random.seed(2)
print(cls,len(wd))
for s in random.sample(wd,min(n,len(wd))):
    p=s.get('path')
    # find path from runs dir
    import glob
    r=[json.loads(l) for l in open('/tmp/lean-idle/workflow-lean/runs.jsonl') if s['runId'] in l][0]
    f=f"{r['dir']}/agent-{s['aid']}.jsonl"
    hits=[]
    for line in open(f,'rb'):
        if b'tool_use' not in line: continue
        try: d=json.loads(line)
        except: continue
        if d.get('type')!='assistant': continue
        for c in d['message'].get('content') or []:
            if isinstance(c,dict) and c.get('type')=='tool_use':
                t=json.dumps(c.get('input'))
                if c.get('name')=='Skill' or c.get('name','').startswith('mcp__') or c.get('name') in ('Agent','Task'):
                    hits.append(c['name']+':'+t[:120])
                elif rx.search(t): hits.append(c['name']+':'+t[:160])
    print(' ',s['runId'],s['label'][:28],'|',hits[:2])
