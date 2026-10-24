#!/usr/bin/env python3
# Print a few task-notification bodies for cc-await-ping tasks from recent main transcripts.
import os, json, re, glob, time
root='/Users/chrisren/.claude/projects'
fs=sorted(glob.glob(root+'/*/*.jsonl'), key=lambda p: -os.path.getmtime(p))[:300]
n=0
for p in fs:
    ids={}
    for line in open(p,errors='replace'):
        if 'cc-await-ping' not in line and 'task-notification' not in line and 'running in background' not in line: continue
        try: d=json.loads(line)
        except: continue
        s=json.dumps(d)
        if 'task-notification' in s and any(i in s for i in ids):
            m=re.search(r'<task-notification>.*?</task-notification>', s)
            if m: print(p[-60:], m.group(0)[:600]); n+=1
        m=d.get('message') or {}
        for c in m.get('content') or [] if isinstance(m.get('content'),list) else []:
            if isinstance(c,dict) and c.get('type')=='tool_use' and 'cc-await-ping' in str((c.get('input') or {}).get('command','')) and (c.get('input') or {}).get('run_in_background'):
                ids[c['id']]=1
    if n>=4: break
