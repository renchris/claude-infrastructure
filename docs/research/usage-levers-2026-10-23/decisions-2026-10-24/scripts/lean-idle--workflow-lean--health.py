"""2.1.293 observational health: lean vs default slots of class none/soft. tool_result is_error per
slot, StructuredOutput errors, journal result present. Read-only."""
import json,collections,os,sys
from concurrent.futures import ProcessPoolExecutor
runs={json.loads(l)["runId"]:json.loads(l) for l in open('/tmp/lean-idle/workflow-lean/runs.jsonl')}
slots=[json.loads(l) for l in open('/tmp/lean-idle/workflow-lean/slots.jsonl')]
def scan(a):
    path,=a
    err=so_err=safety=0
    try:
        for line in open(path,'rb'):
            if b'tool_result' not in line: continue
            try: d=json.loads(line)
            except: continue
            c=(d.get('message') or {}).get('content')
            if not isinstance(c,list): continue
            for x in c:
                if isinstance(x,dict) and x.get('type')=='tool_result' and x.get('is_error'):
                    err+=1
                    t=json.dumps(x.get('content'))[:400]
                    if 'StructuredOutput' in t or 'schema' in t.lower(): so_err+=1
                    if 'safety check' in t: safety+=1
    except OSError: return None
    return err,so_err,safety
def main():
    pick=[s for s in slots if s['version']=='2.1.293' and s['agentType'] in ('workflow-lean','workflow-subagent') and s['cls'] in ('none','soft')]
    res={}
    jobs=[]
    for s in pick:
        r=runs[s['runId']]; jobs.append((f"{r['dir']}/agent-{s['aid']}.jsonl",))
    with ProcessPoolExecutor(8) as ex: out=list(ex.map(scan,jobs,chunksize=16))
    # journal results
    got=collections.defaultdict(set)
    for rid in {s['runId'] for s in pick}:
        p=os.path.join(runs[rid]['dir'],'journal.jsonl')
        if os.path.exists(p):
            for l in open(p):
                try: j=json.loads(l)
                except: continue
                if j.get('type')=='result' and j.get('agentId'): got[rid].add(j['agentId'])
    agg=collections.defaultdict(collections.Counter)
    for s,o in zip(pick,out):
        if o is None: continue
        a=agg[s['agentType']]; a['n']+=1; a['err']+=o[0]; a['so_err']+=o[1]; a['safety']+=o[2]
        a['slots_with_err']+=o[0]>0; a['result']+=s['aid'] in got[s['runId']]; a['nreq']+=s['nreq']
    for k,a in agg.items():
        n=a['n']; print(k, dict(n=n, err_per_slot=round(a['err']/n,2), err_per_req=round(a['err']/max(1,a['nreq']),3), so_err_per_slot=round(a['so_err']/n,3), safety_per_slot=round(a['safety']/n,3), result_rate=round(a['result']/n,3), mean_nreq=round(a['nreq']/n,1)))
if __name__ == "__main__":
    main()
