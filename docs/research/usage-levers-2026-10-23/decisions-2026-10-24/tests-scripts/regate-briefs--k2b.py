import json,collections,re
HI='2026-09-29T00:00:00Z'
def cls(r):
    for p in ('No URL parsed','Non-HTTP scheme'):
        if r.startswith(p): return p
    m=re.match(r'([A-Z]+) to (unknown|unvetted) host',r)
    if m: return f'{m.group(1)} to {m.group(2)} host'+(' (confirm intent)' if 'confirm intent' in r else '')
    return 'other:'+r[:40]
for lo in ('','2026-08-30T00:00:00Z'):
    a=[d for d in (json.loads(l) for l in open('/Users/chrisren/.reso/curl-audit.jsonl')) if lo<=d.get('ts','')<HI and d.get('decision')=='ask']
    print('window from',lo or 'start','asks',len(a),'sessions',len({d.get('session_id') for d in a}))
    for k,v in collections.Counter(cls(d.get('reason') or '') for d in a).most_common(): print('  ',v,k)
    print('  host==mozilla',sum(1 for d in a if d.get('host')=='mozilla'))
    print('  top hosts',collections.Counter(d.get('host') for d in a).most_common(5))
