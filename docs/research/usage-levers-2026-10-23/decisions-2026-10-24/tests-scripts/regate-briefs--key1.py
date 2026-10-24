# Key for brief B1 (curl-gate "No URL parsed" asks). Usage: python3 -I key1.py
import json,re,collections
LO,HI='2026-09-25T02:22:56Z','2026-09-29T00:00:00Z'
rows=[json.loads(l) for l in open('/Users/chrisren/.reso/curl-audit.jsonl')]
w=[d for d in rows if LO<=d.get('ts','')<HI]
a=[d for d in w if d.get('decision')=='ask']
n=[d for d in a if (d.get('reason') or '').startswith('No URL parsed')]
print('rows',len(w),'ask_rows',len(a),'ask_prompts',len({d['tool_use_id'] for d in a}),'nup_rows',len(n),'nup_prompts',len({d['tool_use_id'] for d in n}))
for s,c in collections.Counter(d['session_id'] for d in n).most_common():
    t=sorted(d['ts'] for d in n if d['session_id']==s); print(' session',s,c,t[0],t[-1])
print(' by hour',sorted(collections.Counter((d['session_id'][:8],d['ts'][:13]) for d in n).items()))
k=collections.Counter()
for d in n:
    c=d['cmd_redacted']; m=re.search(r'\bfor\s+(\w+)\s+in\s+([^;]*?);\s*do',c)
    if m: k['for-literal' if not re.search(r'[\$`*?]',m.group(2)) else 'for-dynamic']+=1
    elif re.search(r'while\s+read',c): k['while-read']+=1
    elif '$(' in c: k['cmdsubst-noloop']+=1
    else: k['other']+=1
print(' shapes',dict(k))
