#!/usr/bin/env python3
"""draw.py — quota draw of a sweep phase against the Opus-5 price list.

Predictor (docs/research/fable51-vs-opus5-routing-2026-09-16/V-quota.md "What survives" §2, from
docs/research/usage-telemetry-100p-2026-08-16/skeptic-exchange-rate.md): one weekly pp of Opus 5
buys ~360K output tokens OR ~3.4M cache_creation tokens at the MARGIN, 261K / 3.19M on the fleet's
realised AVERAGE. Cache reads and uncached input carry no identifiable weight. The same doc's
positive control read Opus obs/pred 1.23 (marginal) / 1.03 (average).

  draw.py <index.jsonl> <meter-before.json> <meter-after.json> [<others.json>]

Prints tokens, predicted weekly pp, observed weekly/5h pp (integer meter => +-1 pp on any
difference of two readings), and the implied obs/pred ratio interval.
"""

import json, sys

MARGINAL = (360_000, 3_400_000)
AVERAGE = (261_000, 3_190_000)


def pred(out, cc, rate):
    return out / rate[0] + cc / rate[1]


def meter(path):
    r = next(r for r in json.load(open(path))["rows"] if r["acct"] == "next4")
    return r["weekly_pct"], r["session_pct"]


def main(idx, before, after, others=None):
    rows = [json.loads(l) for l in open(idx) if l.strip()]
    out = sum(r.get("output_tokens") or 0 for r in rows)
    cc = sum(r.get("cache_create") or 0 for r in rows)
    cost = sum(r.get("cost_usd") or 0 for r in rows)
    (w0, s0), (w1, s1) = meter(before), meter(after)
    oth_out = oth_cc = 0
    if others:
        for m in json.load(open(others))["by_model"].values():
            oth_out += m["output_tokens"]
            oth_cc += m["cache_creation_input_tokens"]
    res = {
        "cells": len(rows),
        "output_tokens": out,
        "cache_creation_tokens": cc,
        "cost_usd_list": round(cost, 2),
        "weekly_pp_observed": w1 - w0,
        "session_pp_observed": s1 - s0,
        "others_output_tokens": oth_out,
        "others_cache_creation_tokens": oth_cc,
    }
    for name, rate in (("marginal", MARGINAL), ("average", AVERAGE)):
        p, po = pred(out, cc, rate), pred(oth_out, oth_cc, rate)
        obs = w1 - w0
        # Integer meter: each reading is floor/round of a continuous value, so a difference of two
        # readings carries +-1 pp. The contaminator is subtracted at its PREDICTED draw.
        lo, hi = max(obs - 1 - po, 0), obs + 1 - po
        # 5h meter: ~4.0 five-hour allowances per weekly allowance (skeptic-exchange-rate.md table),
        # so predicted session pp = 4.0 x predicted weekly pp. Derived, not separately fitted.
        sobs = s1 - s0
        slo, shi = max(sobs - 1 - 4 * po, 0), sobs + 1 - 4 * po
        res[name] = {
            "pred_weekly_pp": round(p, 3),
            "pred_others_pp": round(po, 3),
            "ratio_point": round((obs - po) / p, 2) if p else None,
            "ratio_interval": [round(lo / p, 2), round(hi / p, 2)] if p else None,
            "pred_session_pp": round(4 * p, 2),
            "session_ratio_point": round((sobs - 4 * po) / (4 * p), 2) if p else None,
            "session_ratio_interval": [round(slo / (4 * p), 2), round(shi / (4 * p), 2)]
            if p
            else None,
        }
    print(json.dumps(res, indent=1))


if __name__ == "__main__":
    main(*sys.argv[1:5])
