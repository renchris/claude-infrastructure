import json,collections
exec(open('tpl.py').read().split('for since')[0])
a=[r for r in rows if r['decision']=='ask' and '2026-09-25T02:30'<=r['ts']<='2026-09-29T01:50:30Z' and r.get('tool_use_id')!='unknown']
print(collections.Counter(r['reason'].split('carries ')[1] if 'carries' in r['reason'] else '' for r in a if tpl(r)=='cred'))
print(collections.Counter(r['host'] for r in a if tpl(r)=='cred').most_common(10))
print(collections.Counter((r['method'],r['host']) for r in a if tpl(r) in ('post-confirm','method-confirm')).most_common(40))
