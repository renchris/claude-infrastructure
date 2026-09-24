#!/usr/bin/env python3
"""Classify every cache write in the extract as START / INCREMENTAL / REWRITE.

Reads data/extract.sqlite (read-only), writes data/cache_walk.sqlite with one row per
response (table `walk`). Aggregation lives in scripts/cache_writes_report.py.

Per context (file), responses are walked in seq order with
    prefix_i = input_tokens + cc_total + cache_read.
  START        first response of the file (seq == 0)
  START_TRUNC  first IN-WINDOW response of a file that straddles the window start (prev unknown)
  INCREMENTAL  cache_read_i >= HIT_FRAC * prefix_(i-1)
  REWRITE      otherwise (a miss that re-wrote the context)
REWRITE sub-classes, in priority order:
  model_switch   prev response had a different model (caches are per model)
  shrink         prefix_i < SHRINK_FRAC * prefix_(i-1)  (compaction / context edit / clear)
  gap_gt_1h, gap_5m_1h, gap_lt_5m   by the gap since the previous response
The walk includes xdup rows so the prefix sequence stays continuous; every aggregate must
filter xdup = 0. Responses with a zero prefix (<synthetic>, errors) are skipped and never
become `prev`. Experiment sessions (project_slug LIKE '%tokeff%') are excluded.

gap = ts(first record of response i) - ts(first record of response i-1). This is a
send-to-send proxy (both carry a time-to-first-block latency, which mostly cancels).
"""

import datetime as dt
import os
import sqlite3
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SRC = os.path.join(ROOT, "data", "extract.sqlite")
OUT = os.path.join(ROOT, "data", "cache_walk.sqlite")
HIT_FRAC = float(os.environ.get("HIT_FRAC", "0.9"))
SHRINK_FRAC = 0.9


def ts_sec(s):
    return dt.datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()


def main():
    src = sqlite3.connect(f"file:{SRC}?mode=ro", uri=True)
    straddle = {
        f for (f,) in src.execute("SELECT file FROM ctx WHERE spans_window_start=1")
    }
    rows = src.execute(
        """SELECT file, ctx_type, session_id, seq, ts, model, input_tokens, cc_5m, cc_1h,
                  cc_total, cache_read, xdup, project_slug, config_dir
           FROM resp
           WHERE model != '<synthetic>' AND project_slug NOT LIKE '%tokeff%'
           ORDER BY file, seq"""
    )
    tmp = OUT + ".tmp"
    if os.path.exists(tmp):
        os.remove(tmp)
    out = sqlite3.connect(tmp)
    out.execute(
        """CREATE TABLE walk (file TEXT, ctx_type TEXT, session_id TEXT, seq INT, ts TEXT,
           model TEXT, prev_model TEXT, prev_seq INT, input_tokens INT, cc_5m INT, cc_1h INT,
           cc_total INT, cache_read INT, prefix INT, prev_prefix INT, prev_ttl TEXT,
           gap_s REAL, cls TEXT, sub TEXT, xdup INT, project_slug TEXT, config_dir TEXT,
           first_cache_read INT)"""
    )
    buf = []
    cur_file = None
    prev = None
    first_cr = None
    n = 0
    for f, ctype, sid, seq, ts, model, inp, c5, c1, cct, cr, xdup, slug, cdir in rows:
        prefix = (inp or 0) + (cct or 0) + (cr or 0)
        if f != cur_file:
            cur_file, prev, first_cr = f, None, None
        if prefix <= 0:
            continue
        if prev is None:
            cls = "START" if (seq == 0 and f not in straddle) else "START_TRUNC"
            if seq != 0 and f not in straddle:
                cls = "START_TRUNC"
            sub = None
            gap = None
            pp = pm = ps = pt = None
            first_cr = cr
        else:
            p_prefix, p_ts, p_model, p_seq, p_ttl = prev
            gap = ts_sec(ts) - ts_sec(p_ts)
            pp, pm, ps, pt = p_prefix, p_model, p_seq, p_ttl
            if cr >= HIT_FRAC * p_prefix:
                cls, sub = "INCREMENTAL", None
            else:
                cls = "REWRITE"
                if p_model != model:
                    sub = "model_switch"
                elif prefix < SHRINK_FRAC * p_prefix:
                    sub = "shrink"
                elif gap > 3600:
                    sub = "gap_gt_1h"
                elif gap > 300:
                    sub = "gap_5m_1h"
                else:
                    sub = "gap_lt_5m"
        ttl = (
            "1h"
            if (c1 or 0) > 0 and (c5 or 0) == 0
            else (
                "5m"
                if (c5 or 0) > 0 and (c1 or 0) == 0
                else ("mixed" if (c1 or 0) > 0 else "none")
            )
        )
        buf.append(
            (
                f,
                ctype,
                sid,
                seq,
                ts,
                model,
                pm,
                ps,
                inp,
                c5,
                c1,
                cct,
                cr,
                prefix,
                pp,
                pt,
                gap,
                cls,
                sub,
                xdup,
                slug,
                cdir,
                first_cr,
            )
        )
        # a response that wrote nothing keeps the previous TTL as the live one
        prev = (
            prefix,
            ts,
            model,
            seq,
            ttl if ttl != "none" else (prev[4] if prev else "none"),
        )
        n += 1
        if len(buf) >= 20000:
            out.executemany("INSERT INTO walk VALUES (" + ",".join("?" * 23) + ")", buf)
            buf = []
    if buf:
        out.executemany("INSERT INTO walk VALUES (" + ",".join("?" * 23) + ")", buf)
    out.execute("CREATE INDEX walk_file ON walk(file, seq)")
    out.execute("CREATE INDEX walk_cls ON walk(cls, sub)")
    out.commit()
    out.close()
    os.replace(tmp, OUT)
    print(f"walked {n} responses -> {OUT} (HIT_FRAC={HIT_FRAC})", file=sys.stderr)


if __name__ == "__main__":
    main()
