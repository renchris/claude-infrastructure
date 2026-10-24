# Key for brief B2 (curl-gate ask census). Usage: python3 -I key2.py
import json,re,collections,datetime as D
HI='2026-09-29T00:00:00Z'; LO30='2026-08-30T00:00:00Z'
rows=[json.loads(l) for l in open('/Users/chrisren/.reso/curl-audit.jsonl')]
rows=[d for d in rows if d.get('ts','')<HI]
ts=[d['ts'] for d in rows]; p=lambda s:D.datetime.strptime(s,'%Y-%m-%dT%H:%M:%SZ')
print('first',ts[0],'last',ts[-1],'gaps>3d',[(a,b) for a,b in zip(ts,ts[1:]) if (p(b)-p(a)).days>=3])
def cls(r):
    if 'confirm intent' in r: return 'confirm-intent'
    for q in ('No URL parsed','Non-HTTP scheme'):
        if r.startswith(q): return q
    m=re.match(r'([A-Z]+) to (unknown|unvetted) host',r)
    return f'{m.group(1)} to {m.group(2)} host' if m else 'other'
for name,lo in (('ALL',''),('30D',LO30)):
    a=[d for d in rows if d['ts']>=lo and d.get('decision')=='ask']
    ci=[d for d in a if 'confirm intent' in d['reason']]
    print(name,'ask_rows',len(a),'ask_prompts',len({d['tool_use_id'] for d in a}),'sessions',len({d['session_id'] for d in a}))
    print('  classes(rows)',dict(collections.Counter(cls(d['reason']) for d in a).most_common()))
    print('  confirm-intent rows',len(ci),'prompts',len({d['tool_use_id'] for d in ci}),
          'POST-unknown-host',sum(d['reason'].startswith('POST to unknown host') for d in ci),'method+host',sum(not d['reason'].startswith('POST to unknown host') for d in ci))
    print('  ci method field',dict(collections.Counter(d.get('method') for d in ci)))
    print('  ci top hosts',collections.Counter(d.get('host') for d in ci).most_common(6),'distinct',len({d.get('host') for d in ci}))
