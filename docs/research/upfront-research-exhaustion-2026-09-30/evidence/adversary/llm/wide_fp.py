import json, re, glob, os, time, random
Q = re.compile(r'100\.00\s*/\s*100\.00|100\s*/\s*100|are we (100%? )?(complete|done)|100% complete|absolute perfection', re.I)
WIDE = re.compile(Q.pattern + r'|100th|perfect|exhaust|take[- ]?back|nothing left|good to close', re.I)
cut=time.time()-60*86400; seen=set(); only_wide=[]; q=0
for f in glob.glob(os.path.expanduser('~/.claude*/projects/*/*.jsonl')):
    if os.path.getmtime(f)<cut: continue
    with open(f,'rb') as fh:
        for line in fh:
            if b'"type":"user"' not in line: continue
            try: r=json.loads(line)
            except Exception: continue
            if r.get('type')!='user' or r.get('isMeta'): continue
            c=(r.get('message') or {}).get('content')
            if not isinstance(c,str): continue
            s=c.strip()
            if not s or s.startswith('<') or 'Workflow harness' in s or len(s)>1500 or s.startswith('TASK') or 'Scope (frozen)' in s: continue
            if s[:200] in seen: continue
            seen.add(s[:200])
            if Q.search(s): q+=1
            elif WIDE.search(s): only_wide.append(s[:150].replace('\n',' '))
print("Q_hits",q,"widened_only_hits",len(only_wide))
random.seed(7)
for s in random.sample(only_wide,min(25,len(only_wide))): print(" -",s)
