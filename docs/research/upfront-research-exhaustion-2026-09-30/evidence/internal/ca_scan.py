#!/usr/bin/env python3
"""For each transcript, find genuine human prompts that ask the completeness question,
then capture the first assistant text reply after it. Classify reply as YES / NO / other."""
import json, re, sys, os

Q = re.compile(r'100\.00\s*/\s*100\.00|100\s*/\s*100|are we (100%? )?(complete|done)|100% complete|absolute perfection', re.I)
NO = re.compile(r'^\W*(no\b|not yet|not quite|actually|almost|close,? but|nearly)|good to close:\s*no|\bnot (100|complete)|\b(one|a few|two|three|several) (more|remaining|small|other)\b|\bgaps?\b|\bholes?\b|\bmissing\b', re.I)
YES = re.compile(r'^\W*(✅|yes\b)|good to close:\s*yes|100\.00\s*/\s*100\.00 complete|\bexhaustively done\b', re.I)

files = [l.strip() for l in open(sys.argv[1]) if l.strip()]
rows = []
for f in files:
    try:
        recs = []
        with open(f, 'rb') as fh:
            for line in fh:
                try: recs.append(json.loads(line))
                except Exception: pass
    except Exception:
        continue
    for i, r in enumerate(recs):
        if r.get('type') != 'user' or r.get('isMeta'): continue
        c = (r.get('message') or {}).get('content')
        if not isinstance(c, str): continue
        if c.lstrip().startswith('<') or 'Workflow harness' in c or len(c) > 4000: continue
        if not Q.search(c): continue
        reply = ''
        ts2 = ''
        for r2 in recs[i+1:]:
            if r2.get('type') == 'user' and isinstance((r2.get('message') or {}).get('content'), str) and not r2.get('isMeta'):
                break
            if r2.get('type') == 'assistant':
                for b in (r2.get('message') or {}).get('content') or []:
                    if isinstance(b, dict) and b.get('type') == 'text' and b.get('text', '').strip():
                        reply = b['text']; ts2 = r2.get('timestamp', ''); break
            if reply: break
        head = reply[:600]
        cls = 'NO' if NO.search(head) and not YES.search(head.split('\n')[0]) else ('YES' if YES.search(head) else 'OTHER')
        if not reply: cls = 'NOREPLY'
        rows.append({'file': f.replace(os.path.expanduser('~'), '~'), 'ts': r.get('timestamp', ''), 'prompt': c[:300].replace('\n', ' '),
                     'reply_ts': ts2, 'reply': head.replace('\n', ' ⏎ '), 'cls': cls})
json.dump(rows, open(sys.argv[2], 'w'), indent=1, ensure_ascii=False)
from collections import Counter
print(len(rows), Counter(x['cls'] for x in rows))
