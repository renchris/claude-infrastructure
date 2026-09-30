"""Of genuine prompts matching the §7.1 widened completeness regex, how many are NOT completeness asks
(imperatives to research/fix, acknowledgements)? Heuristic split, printed for eyeballing."""
import json, re, glob, os, time
Q = re.compile(r'100\.00\s*/\s*100\.00|100\s*/\s*100|are we (100%? )?(complete|done)|100% complete|absolute perfection|100th|perfect|exhaust|take[- ]?back|nothing left|good to close', re.I)
ASK = re.compile(r'\?|\b(are we|is (it|this|that)|have (you|we)|do (you|we) deem)\b', re.I)
IMP = re.compile(r'^\s*(please\s+)?(exhaustively|research|fix|implement|build|do|run|make|continue|proceed|go|let\'?s|now|ultracode|drive|start|create|write|update|redo|re-?run)\b', re.I)
cut = time.time() - 40*86400
files = [f for f in glob.glob(os.path.expanduser('~/.claude*/projects/*/*.jsonl')) if os.path.getmtime(f) > cut]
seen=set(); hits=[]
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
                if not s or s.startswith('<') or len(s)>700 or s.startswith(('TASK','Caveat','[Workflow')): continue
                if 'Scope (frozen)' in s or 'SendMessage' in s: continue
                k=s[:200]
                if k in seen: continue
                seen.add(k)
                if Q.search(s): hits.append((r.get('timestamp','')[:16], os.path.basename(f)[:8], s.replace('\n',' ')))
    except Exception: pass
imp=[h for h in hits if IMP.search(h[2]) and not re.search(r'\bare we\b|\bis (it|this|that)\b|do you deem', h[2], re.I)]
noask=[h for h in hits if not ASK.search(h[2])]
print('widened-Q hits',len(hits),'imperative-led, no completeness question',len(imp),'no question form at all',len(noask))
print('\n## imperative-led hits (would receive RELAY VERBATIM / do not start a new panel)')
for t,sid,s in sorted(imp)[:60]: print('-',t,sid,'|',s[:200])
print('\n## no-question hits')
for t,sid,s in sorted(noask)[:40]: print('-',t,sid,'|',s[:200])
