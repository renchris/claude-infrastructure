"""Recall of the protocol's re-ask detector (ca_scan Q widened per SYNTHESIS §7.1) against genuine human
prompts that seek completeness/gaps in other words. Read-only over transcripts; last 60 days."""
import json, re, glob, os, time, sys
Q = re.compile(r'100\.00\s*/\s*100\.00|100\s*/\s*100|are we (100%? )?(complete|done)|100% complete|absolute perfection', re.I)
WIDE = re.compile(Q.pattern + r'|100th|perfect|exhaust|take[- ]?back|nothing left|good to close', re.I)
GAP = re.compile(r"anything (else )?(we'?re |we are |i'?m )?(missing|overlook|left)|what(?:'s| is| else is)? (still )?(missing|left|remaining)|any (more )?(gaps?|holes?|loose ends)|"
                 r"what else (do|should|could|would|can)|fresh[- ]eyes|double[- ]check|are you (sure|certain|confident)|"
                 r"left on the table|what would (make|bring|get)|can (anything|anyone|we) (beat|do better)|best possible|optimum|"
                 r"is (this|that|it) (really )?(everything|all)|did we (miss|forget|cover)|what did (we|you) miss|"
                 r"end[- ]?game|no[- ]take[- ]?backs?|fully (done|complete|covered)|truly (done|complete)|really (done|complete)", re.I)
cut = time.time() - 60*86400
files = [f for f in glob.glob(os.path.expanduser('~/.claude*/projects/*/*.jsonl')) if os.path.getmtime(f) >= cut]
seen=set(); gap=0; gap_missed=0; wide=0; ex=[]
for f in files:
    try:
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
                k=s[:200]
                if k in seen: continue
                seen.add(k)
                w=bool(WIDE.search(s)); g=bool(GAP.search(s))
                wide+=w
                if g:
                    gap+=1
                    if not w:
                        gap_missed+=1
                        if len(ex)<40: ex.append((r.get('timestamp','')[:19], os.path.basename(f)[:8], s[:160].replace('\n',' ')))
    except Exception: pass
print(f"files_scanned={len(files)} unique_human_prompts={len(seen)} wide_regex_hits={wide} gap_seeking={gap} gap_seeking_MISSED_by_wide_regex={gap_missed}")
for e in ex: print(" ", e[0], e[1], "|", e[2])
