import json,glob,bisect,collections,datetime
exec(open('join.py').read().split('# curl')[0])
rows=[json.loads(l) for l in open('asks2.jsonl')]
hk=lambda r:(r['hook'] or '').rsplit('/',1)[-1]
d={}
for r in rows: d[(r['tid'],hk(r))]=r
u=[r for r in d.values() if r['ts']]
def ep(s): return datetime.datetime.fromisoformat(s.replace('Z','+00:00')).timestamp()
c=collections.Counter()
for r in u:
    t=ep(r['ts'])
    if not(amin<=t<=amax): continue
    c[(hk(r),r['outcome'],hit(r['sid'],t))]+=1
for k,v in sorted(c.items()): print(v,k)
# version x archived for ran asks
cv=collections.Counter()
for r in u:
    if r['outcome']=='ran': cv[(r['version'],hit(r['sid'],ep(r['ts'])))]+=1
print(sorted(cv.items()))
print('---')
import os
cc=collections.Counter()
same=collections.Counter()
for r in u:
    if r['sub']:
        parent=r['file'].split('/subagents/')[0].rsplit('/',1)[-1]
        same[parent==r['sid']]+=1
    if r['outcome']=='ran':
        cc[(r['sub'],hit(r['sid'],ep(r['ts'])))]+=1
print('subagent sid==parent dir',same)
print('ran by sub x archived',cc)
# unarchived ran: another ask in same sid within 120s?
bysid=collections.defaultdict(list)
for r in u: bysid[r['sid']].append(ep(r['ts']))
nb=collections.Counter()
for r in u:
    if r['outcome']=='ran' and not hit(r['sid'],ep(r['ts'])):
        t=ep(r['ts']); others=[x for x in bysid[r['sid']] if x!=t and abs(x-t)<=120]
        nb[bool(others)]+=1
print('unarchived ran with neighbour ask <=120s',nb)
