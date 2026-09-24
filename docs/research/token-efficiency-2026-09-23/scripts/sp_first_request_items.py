#!/usr/bin/env python3
"""Static prefix: which items sit in the context BEFORE the first response, per ctx_type.
Population: files whose first response (seq=0) is in-window and not a cross-dir copy (xdup=0).
Prints, per ctx_type x kind/subkind: #contexts carrying it, share, mean/median visible chars."""
import sqlite3, statistics, sys, os
DB = os.path.join(os.path.dirname(__file__), '..', 'data', 'extract.sqlite')
c = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
pop = {}
for f, ct in c.execute("""select r.file, r.ctx_type from resp r where r.seq=0 and r.xdup=0
                          and r.model!='<synthetic>'"""):
    pop[f] = ct
n_by = {}
for ct in pop.values(): n_by[ct] = n_by.get(ct, 0) + 1
print("population (contexts with in-window seq0, xdup=0):", n_by)
agg = {}
for f, kind, sub, chars, vis, raw in c.execute("""select file, kind, subkind, chars, visible, raw_chars
      from item where resp_before=-1 and xdup=0"""):
    ct = pop.get(f)
    if ct is None: continue
    key = (ct, kind, sub.split(':')[0] if sub.startswith('hook_') else sub, vis)
    d = agg.setdefault(key, {})
    d[f] = d.get(f, 0) + (chars or 0 if vis else (raw or 0))
for key in sorted(agg, key=lambda k: (k[0], -len(agg[k]))):
    ct, kind, sub, vis = key
    vals = list(agg[key].values())
    print(f"{ct:15s} {kind:14s} {sub:40s} vis={vis} ctx={len(vals):5d} ({100*len(vals)/n_by[ct]:5.1f}%) "
          f"mean={statistics.mean(vals):9.0f} med={statistics.median(vals):9.0f} chars")
