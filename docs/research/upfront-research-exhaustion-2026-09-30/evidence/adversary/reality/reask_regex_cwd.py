"""Distribution of §7.1 widened-regex hits by repo (cwd basename, worktrees folded), last 40 days."""
import json, re, glob, os, time, collections
Q = re.compile(r'100\.00\s*/\s*100\.00|100\s*/\s*100|are we (100%? )?(complete|done)|100% complete|absolute perfection|100th|perfect|exhaust|take[- ]?back|nothing left|good to close', re.I)
cut = time.time() - 40*86400
seen=set(); cnt=collections.Counter()
for f in glob.glob(os.path.expanduser('~/.claude*/projects/*/*.jsonl')):
    if os.path.getmtime(f) <= cut: continue
    try:
        for line in open(f,'rb'):
            if b'"type":"user"' not in line[:400]: continue
            try: r=json.loads(line)
            except Exception: continue
            if r.get('type')!='user' or r.get('isMeta'): continue
            c=(r.get('message') or {}).get('content')
            if not isinstance(c,str): continue
            s=c.strip()
            if not s or s.startswith('<') or len(s)>700 or s.startswith(('TASK','Caveat','[Workflow')) or 'Scope (frozen)' in s: continue
            if s[:200] in seen: continue
            seen.add(s[:200])
            if Q.search(s):
                cwd=r.get('cwd','?'); b=os.path.basename(cwd.rstrip('/'))
                if '.worktrees' in cwd or 'worktree' in cwd: b='(worktree) '+b[:12]
                cnt[b]+=1
    except Exception: pass
print('hits',sum(cnt.values()),'distinct cwds',len(cnt))
for k,v in cnt.most_common(25): print(v,k)
