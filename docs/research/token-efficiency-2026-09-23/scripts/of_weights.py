#!/usr/bin/env python3
"""of_weights.py — persistence weights: list-price $ per token appended to a context after response s.

A token appended after response s (item.resp_before = s) is cache-WRITTEN once by response s+1
(1.25x input at 5m TTL, 2x at 1h TTL) and cache-READ by every later response in the same file
(cr_mult x input). So

    W(s) = p_in(r[s+1]) * wmult(r[s+1])  +  sum_{k >= s+2} p_in(r[k]) * cr_mult(r[k])      ($/token)

using only xdup=0 responses (copies are billed once, in the original file). W is computed at each
response's own model and re-priced at Opus 5.5 ($4, cr 0.05x). TTL of the write = 1h if that
response's cc_1h >= cc_5m and it wrote anything, else 5m; responses that wrote nothing fall back to
the file's majority TTL.

Limitations (ESTIMATED): compaction is ignored (a compacted item stops being read; 39 compactions
fleet-wide per CONTEXT_ECONOMY_V2), cache expiry re-writes are ignored (under-weights), and
uncached input (tiny: $7 fleet-wide) is ignored.

Writes table `w(file, s, w_own, w_o55, n_later)` into data/output_formats.sqlite.
"""

import os, sqlite3
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
BASE = os.path.dirname(HERE)
X = os.path.join(BASE, "data", "extract.sqlite")
OUT = os.path.join(BASE, "data", "output_formats.sqlite")

x = sqlite3.connect(X)
rows = x.execute(
    """SELECT r.file, r.seq, r.xdup, r.cc_5m, r.cc_1h, r.cc_total, COALESCE(p.in_per_mtok,0), COALESCE(p.cr_mult,0.1), c.ctx_type
       FROM resp r LEFT JOIN price p ON p.model=r.model JOIN ctx c ON c.file=r.file ORDER BY r.file, r.seq"""
).fetchall()
byf = defaultdict(list)
for r in rows:
    byf[r[0]].append(r[1:])

db = sqlite3.connect(OUT)
db.execute("DROP TABLE IF EXISTS w")
db.execute(
    "CREATE TABLE w (file TEXT, s INTEGER, w_own REAL, w_o55 REAL, n_later INTEGER, PRIMARY KEY(file, s))"
)
out = []
for f, rs in byf.items():
    ctx_type = rs[0][7]
    tot5 = sum(r[2] for r in rs)
    tot1 = sum(r[3] for r in rs)
    maj1h = tot1 >= tot5 if (tot1 + tot5) else ctx_type == "main"
    n = len(rs)
    # suffix sums of cache-read price over xdup=0 responses
    suf_own = [0.0] * (n + 1)
    suf_o55 = [0.0] * (n + 1)
    suf_n = [0] * (n + 1)
    for i in range(n - 1, -1, -1):
        seq, xd, c5, c1, ct, pin, crm, _ = rs[i]
        a = pin * crm / 1e6 if not xd else 0.0
        b = 4.0 * 0.05 / 1e6 if not xd else 0.0
        suf_own[i] = suf_own[i + 1] + a
        suf_o55[i] = suf_o55[i + 1] + b
        suf_n[i] = suf_n[i + 1] + (0 if xd else 1)
    # position index: seq values are 0..n-1 in order but may start >0 for window-straddling files
    for i in range(-1, n):
        j = i + 1  # the writer
        if j >= n:
            out.append((f, rs[i][0] if i >= 0 else rs[0][0] - 1, 0.0, 0.0, 0))
            continue
        seq_j, xd, c5, c1, ct, pin, crm, _ = rs[j]
        is1h = (c1 >= c5) if ct > 0 else maj1h
        wm = 2.0 if is1h else 1.25
        wo = (pin * wm / 1e6 if not xd else 0.0) + suf_own[j + 1]
        w55 = (4.0 * wm / 1e6 if not xd else 0.0) + suf_o55[j + 1]
        s = rs[i][0] if i >= 0 else seq_j - 1
        out.append((f, s, wo, w55, suf_n[j]))
db.executemany("INSERT OR REPLACE INTO w VALUES (?,?,?,?,?)", out)
db.commit()
print("files", len(byf), "rows", len(out))
