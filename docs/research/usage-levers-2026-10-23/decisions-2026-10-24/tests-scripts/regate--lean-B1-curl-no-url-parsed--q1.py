import json,sys,collections
P='/Users/chrisren/.reso/curl-audit.jsonl'
LO,HI='2026-09-25T02:22:56Z','2026-09-29T00:00:00Z'
rows=[];bad=0
for l in open(P):
    try: r=json.loads(l)
    except Exception: bad+=1; continue
    ts=r.get('ts','')
    if LO<=ts<HI: rows.append(r)
print('bad_lines',bad,'window_rows',len(rows))
print('ts formats sample',sorted({len(r['ts']) for r in rows}))
dec=collections.Counter(r['decision'] for r in rows); print('decisions',dec)
ask=[r for r in rows if r['decision']=='ask']
nou=[r for r in ask if (r.get('reason') or '').startswith('No URL parsed')]
print('ask rows',len(ask),'ask distinct tool_use_id',len({r.get('tool_use_id') for r in ask}))
print('nourl rows',len(nou),'nourl distinct tool_use_id',len({r.get('tool_use_id') for r in nou}))
print('nourl null tuid',sum(1 for r in nou if not r.get('tool_use_id')))
print('nourl reasons',collections.Counter(r['reason'] for r in nou))
print('other ask reasons',collections.Counter(r['reason'][:60] for r in ask if r not in nou).most_common(15))
s=collections.Counter(r.get('session_id') for r in nou); print('sessions',len(s)); 
for k,v in s.most_common(): print(' ',k,v,len({r['tool_use_id'] for r in nou if r.get('session_id')==k}))
top=s.most_common(1)[0][0]
t=sorted(r['ts'] for r in nou if r['session_id']==top); print('top first',t[0],'last',t[-1])
h=collections.Counter(x[:13] for x in t)
for k in sorted(h): print('  hour',k,h[k])
json.dump(nou,open('/tmp/conv-tests/regate/lean-B1-curl-no-url-parsed/nourl.json','w'))
