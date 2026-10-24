import json, collections, sys
sys.dont_write_bytecode = True
W='/tmp/lean-idle/workflow-lean'
WW,WO=0.245,0.404
def pp(s,wr): return (WW*(s['cw']+s['inp'])+wr*s['cr']+WO*s['out'])/1e6
res=json.load(open(f'{W}/review-mechanism/resumes.json'))
wd_rids={r['rid'] for r in res if r['run_wd']}
all_rids={r['rid'] for r in res}
cost=collections.defaultdict(lambda:[0,0,0,0])
for l in open(f'{W}/slots.jsonl'):
    s=json.loads(l)
    if s['runId'] in all_rids:
        c=cost[s['runId']]; c[0]+=1; c[1]+=pp(s,0.0057); c[2]+=pp(s,0.0076); c[3]+= s['agentType']=='workflow-subagent'
tot=[0,0]
for rid in sorted(wd_rids):
    c=cost.get(rid,[0,0,0,0]); tot[0]+=c[1]; tot[1]+=c[2]
    print(rid, 'slots', c[0], 'default', c[3], 'pp %.2f-%.2f'%(c[1],c[2]))
print('would-deny resumed runs', len(wd_rids), 'of', len(all_rids), 'resumed runs; total slot cost 30d pp %.1f-%.1f'%tuple(tot))
