#!/usr/bin/env python3
# Tabulate mainstate.jsonl: buckets of main 1-2h busts by state at gap start and by trigger.
import json, collections, sys
R=[json.loads(l) for l in open('/tmp/usage-audit/r2/cache-rebuilds/mainstate.jsonl')]
lo,hi=float(sys.argv[1]),float(sys.argv[2])
sel=[r for r in R if lo<r['gap']<=hi and r['bust']]
M=lambda x:f"{x/1e6:.1f}M"
print(f"n={len(sel)} cc={M(sum(r['cc'] for r in sel))}")
def state(r):
    if r['fg_pending']: return 'A fg-tool-blocked:'+r['fg_pending'][0][0]
    w=[x for x in r['live'] if x['kind']=='watcher']
    other=[x for x in r['live'] if x['kind']!='watcher']
    g='goal' if r['goal_live'] else 'nogoal'
    if w: s='B idle+model-watcher'
    elif other: s='C idle+bg-task('+ '/'.join(sorted({x['kind'] for x in other}))+')'
    else: s='D idle,no-bg'
    return s+'|'+g+('|teammate' if r['teammate'] else '')
c=collections.Counter(); cc=collections.Counter()
for r in sel: k=state(r); c[k]+=1; cc[k]+=r['cc']
for k,v in sorted(c.items(), key=lambda kv:-cc[kv[0]]): print(f"  {k:60s} n={v:4d} cc={M(cc[k])}")
print('TRIGGER')
c=collections.Counter(); cc=collections.Counter()
for r in sel: k=r['trig']; c[k]+=1; cc[k]+=r['cc']
for k,v in sorted(c.items(), key=lambda kv:-cc[kv[0]]): print(f"  {k:60s} n={v:4d} cc={M(cc[k])}")
