#!/usr/bin/env python3
# Summarise wakes.jsonl: per wake kind, warm (gap<1h) vs cold, requests/turn and token cost per wake.
import json, collections, statistics as S
W=[json.loads(l) for l in open('/tmp/usage-audit/r2/cache-rebuilds/wakes.jsonl')]
def q(xs,p):
    xs=sorted(xs); return xs[min(len(xs)-1,int(p*len(xs)))] if xs else 0
print(f"{'kind':16s} {'warm':4s} {'n':>5s} {'gap_med_m':>9s} {'req/turn med':>12s} {'mean':>5s} {'ctx_med':>8s} {'cr/ctx mean':>11s} {'cc med':>7s} {'cc mean':>7s} {'out med':>7s} {'out mean':>8s}")
for kind in sorted({w['kind'] for w in W}):
    for warm in (True, False):
        xs=[w for w in W if w['kind']==kind and (w['gap']<3600)==warm and w['prev_pp']>20000]
        if not xs: continue
        cc_after=[w['cc']-(w['cc_first'] if not warm else 0) for w in xs]
        print(f"{kind:16s} {str(warm)[0]:4s} {len(xs):5d} {S.median([w['gap'] for w in xs])/60:9.1f} {S.median([w['n'] for w in xs]):12.1f} {S.mean([w['n'] for w in xs]):5.2f} {S.median([w['prev_pp'] for w in xs])/1e3:7.0f}k {S.mean([w['cr']/w['prev_pp'] for w in xs]):11.2f} {S.median([w['cc'] for w in xs])/1e3:6.1f}k {S.mean([w['cc'] for w in xs])/1e3:6.1f}k {S.median([w['out'] for w in xs]):7.0f} {S.mean([w['out'] for w in xs]):8.0f}")
# watcher timeout gaps distribution
xs=[w['gap']/60 for w in W if w['kind']=='watcher_timeout']
print('watcher_timeout gap minutes: n',len(xs),'p10',round(q(xs,.1)),'p50',round(q(xs,.5)),'p90',round(q(xs,.9)), 'share>60m', round(sum(x>60 for x in xs)/max(1,len(xs)),3))
xs=[w['gap']/60 for w in W if w['kind']=='goal_checkin']
print('goal_checkin gap minutes: n',len(xs),'p10',round(q(xs,.1)),'p50',round(q(xs,.5)),'p90',round(q(xs,.9)), 'share>60m', round(sum(x>60 for x in xs)/max(1,len(xs)),3))
c=collections.Counter(round(x/5)*5 for x in xs); print(' goal_checkin gap histogram (5m bins):', sorted(c.items())[:30])
