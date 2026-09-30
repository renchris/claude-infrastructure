"""Count genuine operator prompts of the 'recommendation + conviction % + research if it moves conviction' frame,
and whether each also matches the §7.1 widened completeness regex. Last 40 days."""
import json, re, glob, os, time
Q = re.compile(r'100\.00\s*/\s*100\.00|100\s*/\s*100|are we (100%? )?(complete|done)|100% complete|absolute perfection|100th|perfect|exhaust|take[- ]?back|nothing left|good to close', re.I)
CF = re.compile(r'conviction', re.I); RS = re.compile(r'research', re.I)
cut = time.time() - 40*86400
files = [f for f in glob.glob(os.path.expanduser('~/.claude*/projects/*/*.jsonl')) if os.path.getmtime(f) > cut]
seen=set(); rows=[]
for f in files:
    try:
        with open(f,'rb') as fh:
            for line in fh:
                if b'"type":"user"' not in line[:400]: continue
                try: r=json.loads(line)
                except Exception: continue
                if r.get('type')!='user' or r.get('isMeta'): continue
                c=(r.get('message') or {}).get('content')
                if not isinstance(c,str): continue
                s=c.strip()
                if not s or s.startswith('<') or len(s)>900 or s.startswith(('TASK','Caveat','[Workflow')): continue
                if 'Scope (frozen)' in s or 'SendMessage' in s: continue
                k=s[:200]
                if k in seen: continue
                seen.add(k)
                if CF.search(s) and RS.search(s): rows.append((r.get('timestamp','')[:16], os.path.basename(f)[:8], bool(Q.search(s)), s.replace('\n',' ')))
    except Exception: pass
print('conviction+research frame prompts:', len(rows), '| of which match widened completeness regex:', sum(1 for r in rows if r[2]), '| distinct sessions:', len({r[1] for r in rows}))
for t,sid,q,s in sorted(rows): print('-',t,sid,'Q' if q else '-','|',s[:170])
