import json,collections
HI='2026-09-29T00:00:00Z'; LO30='2026-08-30T00:00:00Z'
rows=[]
bad=0
for l in open('/Users/chrisren/.reso/curl-audit.jsonl'):
    try: rows.append(json.loads(l))
    except Exception: bad+=1
print('unparseable',bad)
def ci(d): return d.get('decision')=='ask' and 'confirm intent' in (d.get('reason') or '')
for name,lo in (('all',''),('30d',LO30)):
    w=[d for d in rows if lo<=d.get('ts','')<HI]
    a=[d for d in w if ci(d)]
    allask=[d for d in w if d.get('decision')=='ask']
    print(name,'rows',len(w),'asks',len(allask),'confirm_intent',len(a),'first',min(d['ts'] for d in w))
    cls=collections.Counter('POST-unknown-host' if (d['reason'] or '').startswith('POST to unknown host') else 'method+host' for d in a); print(' class',dict(cls))
    print(' method',collections.Counter(d.get('method') for d in a).most_common(6))
    print(' hosts',len({d.get('host') for d in a}),collections.Counter(d.get('host') for d in a).most_common(8))
    print(' sessions',len({d.get('session_id') for d in a}))
