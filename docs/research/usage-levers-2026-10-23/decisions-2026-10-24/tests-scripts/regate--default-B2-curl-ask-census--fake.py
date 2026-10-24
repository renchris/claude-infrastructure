import json, sys, collections, re
rows=[json.loads(l) for l in open(sys.argv[1], encoding="utf-8") if json.loads(l)['ts']<"2026-09-29"]
a=[r for r in rows if r['decision']=='ask']
print("ask session_id=='unknown':", sum(1 for r in a if r['session_id']=='unknown'))
pat=re.compile(r'^toolu_[A-Za-z0-9]{20,}$')
odd=collections.Counter(r['tool_use_id'] for r in a if not pat.match(r['tool_use_id']) and r['tool_use_id']!='unknown')
print("ask rows with non-toolu_ tid:", sum(odd.values()), odd.most_common(10))
oddsid=collections.Counter(r['session_id'] for r in a if not re.match(r'^[0-9a-f-]{36}$', r['session_id']))
print("ask rows with non-uuid session_id:", sum(oddsid.values()), oddsid.most_common(10))
for r in a:
    if 'example.org' in (r.get('host') or ''): print(r)
