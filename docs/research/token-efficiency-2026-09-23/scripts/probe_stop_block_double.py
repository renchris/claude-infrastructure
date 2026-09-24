#!/usr/bin/env python3
"""Does a Stop-hook block reach the model ONCE (the 'Stop hook feedback:' meta user message)
or TWICE (that message + the rendered hook_blocking_error attachment)?

Method (MEASURED): for main-thread response pairs (s, s+1) where the only visible non-assistant
items appended between them are stop-hook items, compare the prefix growth
  delta = (input+cc_total+cache_read)(s+1) - (input+cc_total+cache_read)(s)
with output(s) + tokens(meta) [+ tokens(attachment)]. The implied chars/token under each
hypothesis is compared with the ~2.5-2.6 chars/token measured for this prose via /context.
"""

import collections
import sqlite3

DB = "/Users/chrisren/Development/.worktrees/wt-feat-token-efficiency-2026-09-23/docs/research/token-efficiency-2026-09-23/data/extract.sqlite"
db = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
OTHER = (
    "visible=1 AND kind NOT LIKE 'assistant_%' AND kind<>'tool_use_input' "
    "AND subkind<>'stop_hook_feedback' AND subkind NOT LIKE 'hook_blocking_error:Stop%'"
)
rows = db.execute(f"""
WITH blk AS (
  SELECT file, resp_before s,
    SUM(CASE WHEN subkind='stop_hook_feedback' THEN chars ELSE 0 END) meta_c,
    SUM(CASE WHEN subkind LIKE 'hook_blocking_error:Stop%' AND visible=1 THEN chars ELSE 0 END) att_c,
    SUM(CASE WHEN {OTHER} THEN 1 ELSE 0 END) other_n
  FROM item WHERE xdup=0 GROUP BY file, resp_before
  HAVING meta_c>0)
SELECT b.meta_c, b.att_c, b.other_n,
  (a2.input_tokens+a2.cc_total+a2.cache_read)-(a1.input_tokens+a1.cc_total+a1.cache_read) delta,
  a1.output_tokens, a1.has_thinking
FROM blk b JOIN ctx c ON c.file=b.file AND c.ctx_type='main'
JOIN resp a1 ON a1.file=b.file AND a1.seq=b.s AND a1.xdup=0
JOIN resp a2 ON a2.file=b.file AND a2.seq=b.s+1 AND a2.xdup=0
WHERE a1.output_final=1""").fetchall()
print("pairs (meta present) between two main responses:", len(rows))
print(
    "  with attachment too:",
    sum(1 for r in rows if r[1] > 0),
    " meta only:",
    sum(1 for r in rows if r[1] == 0),
)
print("  other visible items:", collections.Counter(min(r[2], 3) for r in rows))


def q(v):
    v = sorted(v)
    return (
        [round(v[int(len(v) * p)], 2) for p in (0.1, 0.25, 0.5, 0.75, 0.9)]
        if v
        else None
    )


for label, sel in [
    ("meta+att, no thinking", lambda r: r[1] > 0 and r[5] == 0),
    ("meta+att, thinking", lambda r: r[1] > 0 and r[5] == 1),
    ("meta only (no att)", lambda r: r[1] == 0),
]:
    clean = [r for r in rows if r[2] == 0 and sel(r)]
    once, twice = [], []
    for meta_c, att_c, _, delta, out, _ in clean:
        resid = delta - out
        if resid <= 0:
            continue
        once.append(meta_c / resid)
        twice.append((meta_c + att_c) / resid)
    print(f"--- {label}: clean pairs {len(clean)} (resid>0: {len(once)})")
    print("   chars/token implied if ONCE  p10,25,50,75,90:", q(once))
    print("   chars/token implied if TWICE p10,25,50,75,90:", q(twice))
