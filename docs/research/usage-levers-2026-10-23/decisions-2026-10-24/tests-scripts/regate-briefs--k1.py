import json,collections,sys
lo,hi=sys.argv[1],sys.argv[2]
asks=0; nup=[]; dec=collections.Counter()
for l in open('/Users/chrisren/.reso/curl-audit.jsonl'):
    try: d=json.loads(l)
    except Exception: continue
    ts=d.get('ts','')
    if not (lo<=ts<hi): continue
    dec[d.get('decision')]+=1
    if d.get('decision')=='ask':
        asks+=1
        if 'No URL parsed' in (d.get('reason') or ''): nup.append(d)
print('window',lo,hi,'decisions',dict(dec))
print('asks',asks,'no_url_parsed',len(nup))
s=collections.Counter(d['session_id'] for d in nup); print('sessions',len(s),s.most_common(3))
print('days',collections.Counter(d['ts'][:10] for d in nup))
print('reasons',collections.Counter(d['reason'][:60] for d in nup).most_common(5))
print('distinct tool_use_id',len({d.get('tool_use_id') for d in nup}))
