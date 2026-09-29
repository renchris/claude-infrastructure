import json,collections
exec(open('tpl.py').read().split('for since')[0])
last={};first={}
for r in rows:
    if r['decision']!='ask' or r.get('tool_use_id')=='unknown': continue
    t=tpl(r); last[t]=max(last.get(t,''),r['ts']); first[t]=min(first.get(t,'z'),r['ts'])
for k in last: print(k,first[k],last[k])
# get-unknown-host reasons sample
print(collections.Counter(r['reason'].split(' ')[0]+' '+' '.join(r['reason'].split(' ')[1:4]) for r in rows if r['decision']=='ask' and tpl(r)=='get-unknown-host').most_common(3))
# post-confirm by method field
print(collections.Counter(r.get('method') for r in rows if r['decision']=='ask' and r.get('tool_use_id')!='unknown' and tpl(r) in('post-confirm','method-confirm')))
# since 2026-09-25T02:30
c=collections.Counter(); ses=collections.Counter()
for r in rows:
    if r['decision']=='ask' and r['ts']>='2026-09-25T02:30' and r.get('tool_use_id')!='unknown':
        c[tpl(r)]+=1
        if tpl(r)=='nourl': ses[r['session_id']]+=1
print('since fix',sum(c.values()),dict(c),ses.most_common(2))
c=collections.Counter()
for r in rows:
    if r['decision']=='ask' and r['ts']>='2026-09-25T02:30':
        c[tpl(r)]+=1
print('since fix incl unknown',sum(c.values()),dict(c))
