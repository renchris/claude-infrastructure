import json, collections, sys
sys.dont_write_bytecode = True
sys.path.insert(0, '/nonexistent')
W='/tmp/lean-idle/workflow-lean'
HARD={"skill","mcp","agent_tool","ship","git_real","claude_home_write"}
WW,WO=0.245,0.404; LEAN_FIRST=9200; TURNS=1.195
def pp(cw,cr,out,inp,wr): return (WW*(cw+inp)+wr*cr+WO*out)/1e6
def lean_cf(s):
    d=max(0,(s["first_tokens"] or 0)-LEAN_FIRST); fw=s["first_cw"] or 0; w=min(fw,d)
    r=(d-w)+d*max(0,s["nreq"]-1)
    return max(0,s["cw"]-w)*TURNS, max(0,s["cr"]-r)*TURNS, s["out"]*TURNS, s["inp"]*TURNS
sites=collections.defaultdict(list)
for l in open(f'{W}/slots.jsonl'):
    s=json.loads(l)
    if s['agentType']!='workflow-subagent' or s['site_verdict']!='would-deny' or s['nreq']==0: continue
    sites[(s['runId'], json.dumps(s['site']))].append(s)
mixed=0; mixed_runs=set(); save_mixed={'lo':0,'hi':0}; save_all={'lo':0,'hi':0}; hard_only=0
for k,ss in sites.items():
    h=[s for s in ss if s['cls'] in HARD]; nh=[s for s in ss if s['cls'] not in HARD]
    for wr,t in ((0.0057,'lo'),(0.0076,'hi')):
        sv=sum(pp(s['cw'],s['cr'],s['out'],s['inp'],wr)-pp(*lean_cf(s),wr) for s in nh)
        save_all[t]+=sv
        if h: save_mixed[t]+=sv
    if h and nh: mixed+=1; mixed_runs.add(k[0])
    if h and not nh: hard_only+=1
print('wd sites (run,site) with slots', len(sites), 'mixed hard+lean-able', mixed, 'in runs', len(mixed_runs), 'hard-only sites', hard_only)
print('30d strict saving all', {k:round(v,1) for k,v in save_all.items()}, 'of which at sites that also hold a HARD slot', {k:round(v,1) for k,v in save_mixed.items()})
