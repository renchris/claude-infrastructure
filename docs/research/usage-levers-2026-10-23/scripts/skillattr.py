import os, json, sys, time, collections
roots={'next':'~/.claude-next/projects/','next2':'~/.claude-secondary/projects/','next3':'~/.claude-tertiary/projects/','next4':'~/.claude-quaternary/projects/'}
cut=time.time()-7*86400
c=collections.Counter()
for a,r in roots.items():
  r=os.path.expanduser(r)
  for dp,dn,fns in os.walk(r):
    for fn in fns:
      if not fn.endswith('.jsonl'): continue
      p=os.path.join(dp,fn)
      try:
        if os.stat(p).st_mtime<cut: continue
      except OSError: continue
      sub='/subagents/' in p
      with open(p,'rb') as fh:
        for line in fh:
          if b'"attributionSkill"' not in line or b'"type":"assistant"' not in line: continue
          try: d=json.loads(line)
          except Exception: continue
          if d.get('type')!='assistant': continue
          c[(a,d.get('attributionSkill'),'subfile' if sub else 'mainfile',bool(d.get('isSidechain')),d.get('attributionAgent'))]+=1
for k,v in sorted(c.items(),key=lambda x:-x[1])[:45]: print(v,k)
