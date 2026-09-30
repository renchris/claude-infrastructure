"""Scan genuine human prompts (type=user, string content, not isMeta, not '<'-prefixed, <=700 chars)
in transcripts modified in the last 40 days; report completeness-shaped asks the §7.1 widened regex misses."""
import json, re, glob, os, time
Q = re.compile(r'100\.00\s*/\s*100\.00|100\s*/\s*100|are we (100%? )?(complete|done)|100% complete|absolute perfection|100th|perfect|exhaust|take[- ]?back|nothing left|good to close', re.I)
C = re.compile(r"(anything else (we|i|you) (need|should|missed|forgot)|what'?s left\b|what else (is|do|should|remains)|are we good\b|are we (all )?set\b|did (you|we) (miss|forget|overlook)|is that everything|is (this|that|it) (final|complete|done|finished)\b|any (more )?loose ends|ready to (build|ship|deploy|implement|start (building|implementation))|can anything beat|nothing can beat|fully (done|complete|researched)|are we finished|all done\?|what('?s| is) (still )?(missing|remaining|outstanding)|any (remaining )?(gaps|holes)\b|covered everything|safe to close|is there anything (else|more|left)|what are we missing|is (it|this|the plan) (ready|airtight|bulletproof|solid)|confident (this|that|it'?s) (is )?(complete|right|correct)|(truly|really) (done|complete|finished)|good to go\?|ship it\?|is research (done|complete|finished))", re.I)
cut = time.time() - 40*86400
files = [f for f in glob.glob(os.path.expanduser('~/.claude*/projects/*/*.jsonl')) if os.path.getmtime(f) > cut]
seen=set(); nq=0; miss=[]
for f in files:
    try:
        with open(f,'rb') as fh:
            for line in fh:
                if b'"type":"user"' not in line[:400] and b'"type": "user"' not in line[:400]:
                    continue
                try: r=json.loads(line)
                except Exception: continue
                if r.get('type')!='user' or r.get('isMeta'): continue
                c=(r.get('message') or {}).get('content')
                if not isinstance(c,str): continue
                s=c.strip()
                if not s or s.startswith('<') or len(s)>700 or s.startswith(('TASK','Caveat','[Workflow')): continue
                if 'Scope (frozen)' in s or 'SendMessage' in s: continue
                k=s[:200]
                if k in seen: continue
                seen.add(k)
                if Q.search(s): nq+=1; continue
                m=C.search(s)
                if m: miss.append((r.get('timestamp','')[:16], os.path.basename(f)[:8], s.replace('\n',' ')))
    except Exception: pass
print('files',len(files),'unique genuine prompts',len(seen),'widened-Q hits',nq,'completeness-shaped misses',len(miss))
for t,sid,s in sorted(miss):
    print('-',t,sid,'|',s[:230])
