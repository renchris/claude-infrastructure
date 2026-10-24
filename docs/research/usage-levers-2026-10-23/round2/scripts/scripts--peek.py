#!/usr/bin/env python3
# Print a compact view of the records between the request before a gap and the request after it.
import json, sys
R=[json.loads(l) for l in open('/tmp/usage-audit/r2/cache-rebuilds/gaps.jsonl')]
sel=[r for r in R if not r['sub'] and r['bust'] and 3600<r['gap']<=7200]
idxs=[int(x) for x in sys.argv[1:]]
def summ(d):
    t=d.get('type'); m=d.get('message') or {}
    s=f"{d.get('timestamp','')[:19]} {t}"
    if t=='assistant':
        s+=f" id={m.get('id','')[-6:]} stop={m.get('stop_reason')}"
        for c in m.get('content') or []:
            if isinstance(c,dict):
                if c.get('type')=='tool_use':
                    inp=c.get('input') or {}
                    s+=f" TOOL {c.get('name')} bg={inp.get('run_in_background')} to={inp.get('timeout')} :: {str(inp.get('command') or inp.get('description') or inp.get('prompt') or '')[:140]!r}"
                elif c.get('type')=='text': s+=f" TEXT {c.get('text','')[:120]!r}"
    elif t=='user':
        c=m.get('content')
        if isinstance(c,str): s+=f" STR {c[:300]!r}"
        elif isinstance(c,list):
            for x in c:
                if isinstance(x,dict):
                    if x.get('type')=='tool_result': s+=f" RESULT {str(x.get('content'))[:200]!r}"
                    elif x.get('type')=='text': s+=f" TEXT {x.get('text','')[:300]!r}"
        if d.get('isMeta'): s+=' [meta]'
    elif t=='attachment':
        a=d.get('attachment') or {}
        s+=f" {a.get('type')} {json.dumps(a)[:300]}"
    elif t=='system':
        s+=f" {d.get('subtype')} {str(d.get('content'))[:200]!r}"
    else:
        s+=' '+json.dumps(d)[:200]
    return s
for i in idxs:
    r=sel[i]; p=r['root']+'/'+r['rel']
    print('='*20,i,r['acct'],r['rel'],'gap',round(r['gap']/60),'m cc',r['cc'])
    recs=[json.loads(l) for l in open(p,errors='replace') if l.strip()]
    a=next(j for j,d in enumerate(recs) if (d.get('message') or {}).get('id')==r['prev_mid'])
    b=next(j for j,d in enumerate(recs) if (d.get('message') or {}).get('id')==r['mid'])
    # last record of prev request
    while a+1<b and (recs[a+1].get('message') or {}).get('id')==r['prev_mid']: a+=1
    for d in recs[max(0,a-3):b+1]: print('  ',summ(d)[:600])
