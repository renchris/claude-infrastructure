"""Final tally: probe usage from its own records, meter deltas, and predictions under both hypotheses.

Weights are round 2's fits (fit4.py, Opus 5.5, Sep 28-Oct 24): weekly pp/Mtok reads 0.00481,
writes 0.245, output 0.404; 5h reads 0.0199 (5h write/output scaled by the same 5h/weekly ratio).
"""

import json
import collections

calls = [json.loads(line) for line in open("/tmp/w2probe/calls.jsonl")]
pre, post = calls[:2], calls[2:]
tot = collections.Counter()
for d in post:
    if d.get("rc") != 0:
        tot["failed"] += 1
        continue
    tot["calls"] += 1
    for model, mu in (d.get("modelUsage") or {}).items():
        tot["models:" + model] += 1
        tot["input"] += mu.get("inputTokens", 0)
        tot["output"] += mu.get("outputTokens", 0)
        tot["cache_read"] += mu.get("cacheReadInputTokens", 0)
        tot["cache_write"] += mu.get("cacheCreationInputTokens", 0)
    tot["list_usd_x1000"] += int(1000 * d.get("total_cost_usd", 0))
meters = [json.loads(line) for line in open("/tmp/w2probe/meters.jsonl")]
W = {"read": 0.00481, "write": 0.245, "output": 0.404}
R5 = 0.0199 / 0.00481
M = 1e6
other = W["write"] * tot["cache_write"] / M + W["output"] * tot["output"] / M
pred = {
    "weekly_if_charged": W["read"] * tot["cache_read"] / M + other,
    "weekly_if_free": other,
    "5h_if_charged": R5 * (W["read"] * tot["cache_read"] / M + other),
    "5h_if_free": R5 * other,
}
print(json.dumps({"probe": dict(tot), "predicted_pp": pred}, indent=1))
print("\nlabel                ts                         wire5h wire7d  ep5h  ep7d")
for m in meters:
    w = m.get("wire") or {}
    print(
        f"{m['label']:<20} {m['ts']:<26} {w.get('5h_util')!s:>6} {w.get('7d_util')!s:>6} "
        f"{(m['usage'].get('five_hour') or {}).get('utilization', '429')!s:>5} {(m['usage'].get('seven_day') or {}).get('utilization', '429')!s:>5}"
    )
