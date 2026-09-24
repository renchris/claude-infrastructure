#!/usr/bin/env python3
"""Calibrate chars-per-token for tool_result text (MEASURED from context growth).

For consecutive responses s, s+1 in one MAIN file where tool_results carry >= 90% of the
chars appended between them (plus the tool_use_input/assistant items produced BY s), the prompt
grows by: output_tokens(s) [its content is now history] + tokens(tool_result) + small framing.
So tokens(tool_result) ~= prompt(s+1) - prompt(s) - output_tokens(s).
We keep only final-recorded outputs, results >= 2,000 chars, and non-negative residuals, and
report the ratio of summed chars to summed token residuals (plus the median per-pair ratio).

Usage: nice -n 10 python3 tool_result_tok_ratio.py
"""

import sqlite3, statistics, os

DB = os.path.join(os.path.dirname(__file__), "..", "data", "extract.sqlite")
db = sqlite3.connect(f"file:{os.path.abspath(DB)}?mode=ro", uri=True)

resp = {}
for f, seq, inp, cc, cr, out, fin in db.execute(
    "SELECT r.file, r.seq, r.input_tokens, r.cc_total, r.cache_read, r.output_tokens, r.output_final "
    "FROM resp r JOIN ctx c ON c.file=r.file WHERE c.ctx_type='main' AND r.xdup=0"
):
    resp[(f, seq)] = (inp + cc + cr, out, fin)

# items grouped by (file, resp_before), excluding the items produced by the response itself
groups = {}
for f, rb, kind, sk, ch in db.execute(
    "SELECT i.file, i.resp_before, i.kind, i.subkind, i.chars FROM item i JOIN ctx c ON c.file=i.file "
    "WHERE c.ctx_type='main' AND i.xdup=0 AND i.visible=1"
):
    if kind in ("tool_use_input", "assistant_text", "assistant_thinking"):
        continue
    groups.setdefault((f, rb), []).append((kind, sk, ch))

pairs = []
for (f, rb), its in groups.items():
    trs = [x for x in its if x[0] == "tool_result"]
    trc = sum(x[2] for x in trs)
    allc = sum(x[2] for x in its)
    # relaxed: tool_results carry >= 90% of the appended chars and >= 2,000 chars
    if not trs or trc < 2000 or trc < 0.9 * allc:
        continue
    a, b = resp.get((f, rb)), resp.get((f, rb + 1))
    if not a or not b or not a[2]:
        continue
    resid = b[0] - a[0] - a[1]
    if resid <= 0:
        continue
    pairs.append((allc, resid, trs[0][1]))

tc = sum(p[0] for p in pairs)
tt = sum(p[1] for p in pairs)
print(
    f"pairs={len(pairs)} chars={tc} tokens={tt} chars_per_token(sum)={tc / tt:.3f} "
    f"median_pair={statistics.median(p[0] / p[1] for p in pairs):.3f}"
)
by = {}
for ch, t, sk in pairs:
    by.setdefault(sk, [0, 0, 0])
    by[sk][0] += 1
    by[sk][1] += ch
    by[sk][2] += t
for sk, (n, ch, t) in sorted(by.items(), key=lambda x: -x[1][0])[:8]:
    print(f"  {sk:20s} n={n:6d} chars/token={ch / t:.3f}")
