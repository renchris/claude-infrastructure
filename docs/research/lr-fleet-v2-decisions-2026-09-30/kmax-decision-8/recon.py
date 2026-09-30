import os, json, sys, datetime as dt
H=os.path.expanduser('~')
dirs=[('next',H+'/.claude/projects'),('next4',H+'/.claude-quaternary/projects'),('next3',H+'/.claude-tertiary/projects'),('next2',H+'/.claude-secondary/projects')]
def P(s): return dt.datetime.fromisoformat(s.replace('Z','+00:00')).timestamp()
LO=P('2026-09-29T04:10:00Z'); HI=P('2026-09-29T06:25:00Z')
out=[]
for acct,pd in dirs:
    for slug in os.scandir(pd):
        if not slug.is_dir(follow_symlinks=False): continue
        for root,ds,fs in os.walk(slug.path):
            for f in fs:
                if not f.endswith('.jsonl'): continue
                top = root==slug.path
                if not top and not f.startswith('agent-'): continue
                p=os.path.join(root,f)
                try: m=os.lstat(p).st_mtime
                except OSError: continue
                if m<LO: continue
                ts=[]
                try:
                    with open(p,'rb') as fh:
                        for line in fh:
                            try: o=json.loads(line)
                            except Exception: continue
                            s=o.get('timestamp') if isinstance(o,dict) else None
                            if not isinstance(s,str): continue
                            try: t=P(s)
                            except Exception: continue
                            if LO-700<=t<=HI: ts.append(t)
                except OSError: continue
                if ts:
                    out.append({'acct':acct,'top':top,'path':p,'ts':sorted(set(ts)),'mtime':m})
json.dump(out,open('/tmp/kmaxq/files.json','w'))
print(len(out))
