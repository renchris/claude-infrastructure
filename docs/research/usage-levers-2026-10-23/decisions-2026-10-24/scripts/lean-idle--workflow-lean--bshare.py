import json,collections
HARD={"skill","mcp","agent_tool","ship","git_real","claude_home_write"}
WW,WO=0.245,0.404
def pp(cw,cr,out,inp,wr): return (WW*(cw+inp)+wr*cr+WO*out)/1e6
def lean_cf(s,turns=1.195):
    d=max(0,(s["first_tokens"] or 0)-9200); fw=s["first_cw"] or 0
    ws=min(fw,d); rs=(d-ws)+d*max(0,s["nreq"]-1)
    return max(0,s["cw"]-ws)*turns, max(0,s["cr"]-rs)*turns, s["out"]*turns, s["inp"]*turns
runs={json.loads(l)["runId"]:json.loads(l) for l in open('runs.jsonl')}
slots=[json.loads(l) for l in open('slots.jsonl')]
save=collections.Counter()
for s in slots:
    if s['agentType']=='workflow-subagent' and s['site_verdict']=='would-deny' and s['cls'] not in HARD and s['nreq']:
        save[s['runId']]+=pp(s['cw'],s['cr'],s['out'],s['inp'],0.0057)-pp(*lean_cf(s),0.0057)
sess=collections.defaultdict(list)
for rid,r in runs.items():
    if r.get('would_deny') and r.get('dir'):
        sess[r['dir'].split('/subagents/')[0]].append((r.get('start') or 0, rid))
first=later=0
for k,v in sess.items():
    v.sort()
    first+=save[v[0][1]]; later+=sum(save[x[1]] for x in v[1:])
# b13 family: by name
b13=sum(v for rid,v in save.items() if (runs[rid].get('name') or '').startswith(('b13','round')))
print('30d save total',round(first+later,1),'first-in-session',round(first,1),'later-in-session',round(later,1),'b13',round(b13,1))
# deny overhead: per denied run, main-session round trip
import statistics
ch=[r['script_chars'] for r in runs.values() if r.get('would_deny') and r.get('script_chars')]
print('denied scripts chars median',statistics.median(ch),'p90',sorted(ch)[int(.9*len(ch))], 'n',len(ch))
