#!/usr/bin/env python3
# Show the task-notification blocks behind trig=task_notif:unknown for main 1-2h busts.
import json, re
R=[json.loads(l) for l in open('/tmp/usage-audit/r2/cache-rebuilds/mainstate.jsonl')]
G={(g['rel'],g['ts']):g for g in map(json.loads,open('/tmp/usage-audit/r2/cache-rebuilds/gaps.jsonl'))}
sel=[r for r in R if 3600<r['gap']<=7200 and r['bust'] and r['trig'].startswith('task_notif:unknown')][:6]
for r in sel:
    g=G[(r['rel'],r['ts'])]; p=g['root']+'/'+g['rel']
    lines=open(p,errors='replace').read().splitlines()
    b=next(i for i,l in enumerate(lines) if g['mid'] in l)
    a=max(i for i,l in enumerate(lines[:b]) if g['prev_mid'] in l)
    for l in lines[a+1:b]:
        if 'task-notification' in l:
            m=re.search(r'<task-notification>.*?</task-notification>', l)
            print(r['rel'][-40:], (m.group(0) if m else l)[:500]); break
