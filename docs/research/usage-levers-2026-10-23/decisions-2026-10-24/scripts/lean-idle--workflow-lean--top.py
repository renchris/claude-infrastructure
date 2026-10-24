import json,collections,sys,importlib.util
sys.dont_write_bytecode=True
spec=importlib.util.spec_from_file_location('an','/tmp/lean-idle/workflow-lean/analyze.py')
# reuse functions without running main body: copy minimal
HARD = {"skill", "mcp", "agent_tool", "ship", "git_real", "claude_home_write"}
WW,WO=0.245,0.404
def pp(cw,cr,out,inp,wr): return (WW*(cw+inp)+wr*cr+WO*out)/1e6
def lean_cf(s,turns=1.195):
    d=max(0,(s["first_tokens"] or 0)-9200); fw=s["first_cw"] or 0
    ws=min(fw,d); rs=(d-ws)+d*max(0,s["nreq"]-1)
    return max(0,s["cw"]-ws)*turns, max(0,s["cr"]-rs)*turns, s["out"]*turns, s["inp"]*turns
from datetime import datetime,timezone
def week(ts):
    t=datetime.fromisoformat(ts.replace("Z","+00:00")); return (datetime(2026,10,24,23,59,tzinfo=timezone.utc)-t).days//7
runs={json.loads(l)["runId"]:json.loads(l) for l in open('runs.jsonl')}
slots=[json.loads(l) for l in open('slots.jsonl')]
agg=collections.defaultdict(lambda: collections.Counter())
for s in slots:
    if s['agentType']!='workflow-subagent' or s['site_verdict']!='would-deny' or s['cls'] in HARD or not s['first_ts'] or not s['nreq']: continue
    w=week(s['first_ts']); nm=(runs[s['runId']].get('name') or '?')
    fam=nm.split('-round')[0] if 'round' in nm else nm
    d=pp(s['cw'],s['cr'],s['out'],s['inp'],0.0057)
    agg[w][fam]+=d-pp(*lean_cf(s),0.0057)
for w in sorted(agg):
    tot=sum(agg[w].values()); print('wk',w,'total',round(tot,2))
    for k,v in agg[w].most_common(6): print('   ',k[:40],round(v,2))
# distribution of saving per slot and fraction with negative saving
vals=[]; neg=0
for s in slots:
    if s['agentType']!='workflow-subagent' or s['site_verdict']!='would-deny' or s['cls'] in HARD or not s['nreq']: continue
    v=pp(s['cw'],s['cr'],s['out'],s['inp'],0.0057)-pp(*lean_cf(s),0.0057); vals.append(v); neg+=v<0
vals.sort(); print('slots',len(vals),'neg',neg,'median',round(vals[len(vals)//2],4),'p90',round(vals[int(.9*len(vals))],4),'sum',round(sum(vals),1))
# no-turn-penalty variant
v2=sum(pp(s['cw'],s['cr'],s['out'],s['inp'],0.0057)-pp(*lean_cf(s,1.0),0.0057) for s in slots if s['agentType']=='workflow-subagent' and s['site_verdict']=='would-deny' and s['cls'] not in HARD and s['nreq'])
print('no-turn-penalty sum 30d', round(v2,1))
