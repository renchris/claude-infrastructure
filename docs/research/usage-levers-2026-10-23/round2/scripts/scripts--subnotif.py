#!/usr/bin/env python3
# Do subagent transcripts that launch a background Bash ever receive a task-notification for it?
import glob, os, json, re, time
W0=time.time()-8*86400
n=hit=0; ex=None
for root in ["/Users/chrisren/.claude/projects","/Users/chrisren/.claude-secondary/projects"]:
    for p in glob.glob(root+"/*/*/subagents/*.jsonl")+glob.glob(root+"/*/*/subagents/*/*/*.jsonl"):
        try:
            if os.path.getmtime(p)<W0 or os.path.getsize(p)>30e6: continue
        except OSError: continue
        t=open(p,errors='replace').read()
        if '"run_in_background":true' not in t: continue
        n+=1
        if 'task-notification' in t:
            hit+=1
            if ex is None:
                m=re.search(r'task-notification.{0,300}',t); ex=(p[-70:], m.group(0)[:300])
        if n>=400: break
print('subagent files with bg Bash:',n,'with task-notification text:',hit); print(ex)
