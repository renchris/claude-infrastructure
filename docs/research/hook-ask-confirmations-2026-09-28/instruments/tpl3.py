import json,collections
exec(open('tpl.py').read().split('for since')[0])
a=[r for r in rows if r['decision']=='ask' and r['ts']>='2026-09-25T02:30' and r.get('tool_use_id')!='unknown']
a.sort(key=lambda r:r['ts'])
c=collections.Counter()
for i,r in enumerate(a,1):
    c[tpl(r)]+=1
    if i==151: print(r['ts'],dict(c))
# edaaa897d time
