#!/usr/bin/env python3
# Cross-tab of main busts in a gap window: coarse state at gap start x what ended the gap.
import json, collections, sys
R=[json.loads(l) for l in open('/tmp/usage-audit/r2/cache-rebuilds/mainstate.jsonl')]
lo,hi=float(sys.argv[1]),float(sys.argv[2])
sel=[r for r in R if lo<r['gap']<=hi and r['bust']]
M=lambda x:f"{x/1e6:.1f}M"
def st(r):
    if r['fg_pending']: return 'A blocked in foreground tool ('+r['fg_pending'][0][0]+')'
    w=[x for x in r['live'] if x['kind']=='watcher']
    if w:
        return 'B idle, model watcher armed, term '+('<=3300s' if min(x['to'] for x in w)<=3300 else '>=10800s')
    if r['live']: return 'C idle, own background job running (no watcher)'
    return 'D idle, nothing running'
def tg(r):
    t=r['trig']
    if t.startswith('fg_tool'): return 'tool returned'
    if t.startswith('task_notif:watcher'): return 'watcher exit'
    if t.startswith('task_notif:Workflow') or t.startswith('task_notif:Agent'): return 'workflow/agent done'
    if t.startswith('task_notif'): return 'bg bash done'
    if t in ('prompt','slash_or_bang'): return 'operator/injected prompt'
    return t
tot=sum(r['cc'] for r in sel)
print(f"n={len(sel)} cc={M(tot)}")
for name,fn in (('STATE',st),):
    c=collections.Counter(); cc=collections.Counter(); g=collections.Counter(); tm=collections.Counter()
    for r in sel:
        k=fn(r); c[k]+=1; cc[k]+=r['cc']; g[k]+=r['goal_live']; tm[k]+=r['teammate']
    for k in sorted(c): print(f"  {k:52s} n={c[k]:4d} cc={M(cc[k]):>6s} ({cc[k]/tot:.0%}) goal-live={g[k]} teammate={tm[k]}")
x=collections.Counter(); xc=collections.Counter()
for r in sel: k=(st(r)[:1],tg(r)); x[k]+=1; xc[k]+=r['cc']
print('STATE x TRIGGER')
for k in sorted(x): print(f"  {k[0]} {k[1]:28s} n={x[k]:4d} cc={M(xc[k])}")
print('goal-live total', sum(r['goal_live'] for r in sel), M(sum(r['cc'] for r in sel if r['goal_live'])), '| teammate total', sum(r['teammate'] for r in sel), M(sum(r['cc'] for r in sel if r['teammate'])))
print('goal-paused (live but paused)', sum(r['goal_paused'] for r in sel))
