#!/usr/bin/env python3
# For A-bucket (foreground tool blocked) main 1-2h busts: list hook events and record kinds inside the gap.
import json, collections
G={(g['rel'],g['ts']):g for g in map(json.loads,open('/tmp/usage-audit/r2/cache-rebuilds/gaps.jsonl'))}
R=[json.loads(l) for l in open('/tmp/usage-audit/r2/cache-rebuilds/mainstate.jsonl')]
sel=[r for r in R if 3600<r['gap']<=7200 and r['bust'] and r['fg_pending']]
for r in sel:
    g=G[(r['rel'],r['ts'])]; p=g['root']+'/'+g['rel']
    L=open(p,errors='replace').read().splitlines()
    b=next(i for i,l in enumerate(L) if g['mid'] in l)
    a=max(i for i,l in enumerate(L[:b]) if g['prev_mid'] in l)
    ev=[]
    for l in L[a+1:b]:
        try: d=json.loads(l)
        except: continue
        at=(d.get('attachment') or {})
        ts=(d.get('timestamp') or '')[11:16]
        if at.get('hookEvent'): ev.append(f"{ts} {at.get('type')}:{at.get('hookEvent')}:{at.get('hookName','')[:24]}")
        elif d.get('type') in ('user','system'): ev.append(f"{ts} {d.get('type')}:{d.get('subtype','')}")
        elif d.get('type')=='attachment': ev.append(f"{ts} att:{at.get('type')}")
    print(r['acct'], r['ts'][:16], round(r['gap']/60), r['fg_pending'][0][0], '|', ' ; '.join(ev)[:400])
