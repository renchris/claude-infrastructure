import json, collections, re, statistics as st, sys
sys.dont_write_bytecode = True
W='/tmp/lean-idle/workflow-lean'
runs={}
for l in open(f'{W}/runs.jsonl'):
    r=json.loads(l); runs[r['runId']]=r
def norm(x):
    return re.sub(r'\d+','#',(x or '').lower()).strip()
g=collections.defaultdict(lambda: collections.defaultdict(list))
for l in open(f'{W}/slots.jsonl'):
    s=json.loads(l)
    if s['nreq']==0 or s['agentType'] not in ('workflow-subagent','workflow-lean'): continue
    if s.get('version')!='2.1.293': continue
    name=norm(re.sub(r'-?(wf_.*|\d{4}-\d\d-\d\d.*)$','',(runs.get(s['runId'],{}).get('name') or '')))
    lab=norm(s.get('label'))
    if not lab or not name: continue
    g[(name,lab)][s['agentType']].append((s['nreq'], s['out'], s['runId']))
pairs=[]
for k,v in g.items():
    if v.get('workflow-subagent') and v.get('workflow-lean'):
        d=[x[0] for x in v['workflow-subagent']]; ln=[x[0] for x in v['workflow-lean']]
        pairs.append((k, len(d), len(ln), st.median(d), st.median(ln)))
print('matched (workflow name, label) groups on 2.1.293 with both types:', len(pairs))
rat=[p[4]/p[3] for p in pairs if p[3]>0]
if rat:
    print('median per-group lean/default nreq ratio', round(st.median(rat),2), 'mean', round(st.mean(rat),2), 'n', len(rat))
    w=sorted(rat); print('p25', round(w[len(w)//4],2), 'p75', round(w[3*len(w)//4],2))
for p in sorted(pairs, key=lambda p:-(p[1]+p[2]))[:25]:
    print(p)
