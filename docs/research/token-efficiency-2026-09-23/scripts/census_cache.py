#!/usr/bin/env python3
"""Census supplement: setup-prefix re-read cost, cache misses, and a 5m-vs-1h TTL replay.

Reads data/extract.sqlite (read-only, xdup=0). Writes measure/census_cache.json.

A. Setup prefix (MEASURED per file, ESTIMATED as an attribution):
   F = the first request's prefix (input+cc+cr at seq=0) of each context whose seq=0 is in
   the window. F is an UPPER BOUND on the static setup (it also holds the first prompt/brief).
   setup re-read cost = sum over later responses of min(F, prefix) * cache-read price;
   setup write cost   = the seq=0 cache write.
B. Cache misses on later requests: cc_total >= 0.5 * prefix and prefix >= 20k (a re-write of
   most of the context rather than an incremental append). MEASURED.
C. TTL replay on MAIN threads (ESTIMATED): walk each main file in seq order with the gap
   between consecutive response timestamps. Under a 5m TTL, a later request whose gap > 300 s
   is modelled as a full miss (prefix re-written at 1.25x); otherwise its cache-read tokens stay
   reads and its cache-write tokens are billed at 1.25x instead of 2x. Requests that actually
   missed under 1h are kept as misses. Gap = response-record timestamp difference, which
   overstates the idle time by the previous response's streaming time (conservative for 5m).
"""

import json, os, sqlite3
from collections import defaultdict
from datetime import datetime

D = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB = os.path.join(D, "data", "extract.sqlite")
OUT = os.path.join(D, "measure", "census_cache.json")


def ts(s):
    return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()


def main():
    c = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
    rows = c.execute(
        "SELECT file, ctx_type, seq, ts, model, input_tokens, cc_5m, cc_1h, cache_read, "
        "in_per_mtok, cr_mult FROM resp_priced WHERE xdup=0 AND model!='<synthetic>' "
        "ORDER BY file, seq"
    ).fetchall()
    by_file = defaultdict(list)
    for r in rows:
        by_file[r[0]].append(r)
    A = defaultdict(lambda: defaultdict(float))
    B = defaultdict(lambda: defaultdict(float))
    C = defaultdict(float)
    gaps = []
    for f, rs in by_file.items():
        ct = rs[0][1]
        first = rs[0]
        has_first = first[2] == 0
        F = (first[5] + first[6] + first[7] + first[8]) if has_first else None
        prev_ts = None
        for _, _, seq, t, model, inp, c5, c1, cr, pin, crm in rs:
            prefix = inp + c5 + c1 + cr
            cc = c5 + c1
            a = A[ct]
            a["responses"] += 1
            a["cr_usd"] += cr * pin * crm / 1e6
            if has_first:
                a["responses_in_files_with_first"] += 1
                if seq == 0:
                    a["setup_write_usd"] += (c5 * 1.25 + c1 * 2.0) * pin / 1e6
                    a["setup_write_tokens"] += cc
                    a["n_contexts"] += 1
                    a["F_sum"] += F
                else:
                    reread = min(F, cr)
                    a["setup_reread_tokens"] += reread
                    a["setup_reread_usd"] += reread * pin * crm / 1e6
            b = B[ct]
            if seq > 0:
                b["later_requests"] += 1
                if prefix >= 20000 and cc >= 0.5 * prefix:
                    b["misses"] += 1
                    b["miss_write_usd"] += (c5 * 1.25 + c1 * 2.0) * pin / 1e6
                    b["miss_tokens"] += cc
            # C: TTL replay, main only
            if ct == "main":
                t_s = ts(t) if t else None
                gap = (
                    (t_s - prev_ts)
                    if (t_s is not None and prev_ts is not None)
                    else None
                )
                prev_ts = t_s if t_s is not None else prev_ts
                actual = (inp + c5 * 1.25 + c1 * 2.0 + cr * crm) * pin / 1e6
                C["actual_usd"] += actual
                if seq == 0 or gap is None:
                    alt = (inp + (c5 + c1) * 1.25 + cr * crm) * pin / 1e6
                elif gap > 300 and cr > 0:
                    alt = (inp + (cc + cr) * 1.25) * pin / 1e6
                    C["forced_misses"] += 1
                    C["forced_miss_tokens"] += cc + cr
                else:
                    alt = (inp + cc * 1.25 + cr * crm) * pin / 1e6
                C["alt5m_usd"] += alt
                C["n"] += 1
                if gap is not None and seq > 0:
                    gaps.append(gap)
    gaps.sort()
    q = lambda p: gaps[int(p * (len(gaps) - 1))]
    C["gap_quantiles_s"] = {p: q(p) for p in (0.5, 0.75, 0.9, 0.95, 0.99)}
    C["share_gaps_gt_300s"] = sum(1 for g in gaps if g > 300) / len(gaps)
    C["share_gaps_gt_3600s"] = sum(1 for g in gaps if g > 3600) / len(gaps)
    C["delta_usd"] = C["alt5m_usd"] - C["actual_usd"]
    out = {
        "setup_prefix": {k: dict(v) for k, v in A.items()},
        "cache_misses_later": {k: dict(v) for k, v in B.items()},
        "ttl_replay_main_input_side": dict(C),
    }
    for k, v in out["setup_prefix"].items():
        v["mean_F_tokens"] = v["F_sum"] / v["n_contexts"] if v["n_contexts"] else None
        v["setup_reread_share_of_cr_usd"] = (
            v["setup_reread_usd"] / v["cr_usd"] if v["cr_usd"] else None
        )
    # D. main-thread miss causes (MEASURED): model switch vs gap since previous response
    cats = {}
    for f, rs in by_file.items():
        if rs[0][1] != "main":
            continue
        prev = None
        for _, _, seq, t, model, inp, c5, c1, cr, pin, crm in rs:
            pre = inp + c5 + c1 + cr
            cc = c5 + c1
            if prev and seq > 0 and pre >= 20000 and cc >= 0.5 * pre and t and prev[0]:
                gap = ts(t) - ts(prev[0])
                k = (
                    "model_switch"
                    if model != prev[1]
                    else "gap_gt_1h"
                    if gap > 3600
                    else "gap_5m_1h"
                    if gap > 300
                    else "gap_le_5m"
                )
                a = cats.setdefault(k, {"n": 0, "usd": 0.0, "tokens": 0})
                a["n"] += 1
                a["usd"] += (c5 * 1.25 + c1 * 2.0) * pin / 1e6
                a["tokens"] += cc
            prev = (t, model)
    out["main_miss_causes"] = cats
    # merge into census.json (run scripts/census.py first)
    cj = os.path.join(D, "measure", "census.json")
    if os.path.exists(cj):
        base = json.load(open(cj))
        base["cache_supplement"] = out
        json.dump(base, open(cj, "w"), indent=1, default=str)
    with open(OUT, "w") as fh:
        json.dump(out, fh, indent=1, default=str)
    print(json.dumps(out, indent=1, default=str))


if __name__ == "__main__":
    main()
