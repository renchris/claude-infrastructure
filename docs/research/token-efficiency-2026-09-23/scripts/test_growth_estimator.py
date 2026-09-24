#!/usr/bin/env python3
"""Test a context-growth estimator of a response's output tokens, on responses whose output IS known.
growth(s) = prefix(s+1) - prefix(s), prefix = input+cc_total+cache_read; between(s) = chars of non-assistant
items with resp_before = s. Estimator: out_hat = growth - between/cpt. Reports the sum ratio out_hat/actual
and the median per-response ratio, by ctx_type x version x model, for a few chars-per-token values."""
import os, sqlite3, statistics, collections
D = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "data")
db = sqlite3.connect(os.path.join(D, "extract.sqlite"))
db.execute("""create temp table b as select file, resp_before s, sum(chars) ch, sum(n_images) im from item
              where kind not in ('assistant_text','assistant_thinking','tool_use_input') and (visible=1) group by 1,2""")
q = """select r.ctx_type, substr(r.version,1,7), r.model, r.output_tokens, r.output_final,
       (n.input_tokens+n.cc_total+n.cache_read)-(r.input_tokens+r.cc_total+r.cache_read) growth, coalesce(b.ch,0), coalesce(b.im,0)
       from resp r join resp n on n.file=r.file and n.seq=r.seq+1 left join b on b.file=r.file and b.s=r.seq
       where r.xdup=0 and r.model<>'<synthetic>'"""
rows = db.execute(q).fetchall()
for cpt in (3.0, 3.5, 4.0):
    g = collections.defaultdict(lambda: [0, 0, [], 0])
    for ct, v, m, out, fin, growth, ch, im in rows:
        if not fin or im or growth <= 0: continue
        est = growth - ch / cpt
        k = (ct != "main", v, m)
        g[k][0] += est; g[k][1] += out; g[k][3] += 1
        if out > 50: g[k][2].append(est / out)
    print(f"cpt={cpt}")
    for k, (e, a, rs, n) in sorted(g.items(), key=lambda x: -x[1][3])[:8]:
        print(f"   agent={k[0]!s:5} {k[1]} {k[2]:18s} n={n:6d} sum_est/actual={e / a if a else 0:.3f} median_ratio={statistics.median(rs) if rs else 0:.3f}")
