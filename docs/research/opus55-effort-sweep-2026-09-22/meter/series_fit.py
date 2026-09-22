#!/usr/bin/env python3
"""series_fit.py — do the two capped-out max cells' 1.02M output tokens show up on the 5h meter?

Each cell's tokens are spread uniformly over [started_at, ended_at]; other consumers' tokens are
placed at their transcript timestamps (deduped on message.id). Both are priced with the Opus-5
marginal list (360K out / 3.4M cache_creation per weekly pp, x4.0 for the 5h meter). Model A counts
the failed cells, model B drops them. For each, a one-parameter least-squares scale k (meter pp per
predicted pp, intercept = first reading) is fitted to the 2-minute series; lower RMSE wins.

  series_fit.py <runs/o55/index.jsonl> <meter/series.jsonl> <config-dir>
"""
import json, sys
from datetime import datetime
from pathlib import Path

def ts(s): return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
def pp(out, cc): return 4 * (out / 360_000 + cc / 3_400_000)

idx, ser, cfg = sys.argv[1:4]
cells = [json.loads(l) for l in open(idx) if l.strip()]
series = [json.loads(l) for l in open(ser) if l.strip()]
t0, t1 = ts(cells[0]["started_at"]) - 60, max(ts(c["ended_at"]) for c in cells)
series = [s for s in series if t0 <= ts(s["t"]) <= t1 + 300]
# other consumers, deduped
best = {}
for f in Path(cfg, "projects").rglob("*.jsonl"):
    if f.stat().st_mtime < t0: continue
    for line in open(f, errors="replace"):
        if '"assistant"' not in line: continue
        try: r = json.loads(line)
        except ValueError: continue
        m = r.get("message") or {}; u = m.get("usage"); t = r.get("timestamp")
        if r.get("type") != "assistant" or not u or not m.get("id") or not t: continue
        if not (t0 <= ts(t) <= t1 + 300): continue
        b = best.setdefault(m["id"], [ts(t), 0, 0])
        b[1] = max(b[1], u.get("output_tokens") or 0); b[2] = max(b[2], u.get("cache_creation_input_tokens") or 0)
def cum(t, drop_failed):
    x = sum(pp(o, c) for tt, o, c in best.values() if tt <= t)
    for c in cells:
        if drop_failed and c.get("is_error"): continue
        a, b = ts(c["started_at"]), ts(c["ended_at"])
        frac = min(max((t - a) / (b - a), 0), 1) if b > a else float(t >= b)
        x += frac * pp(c["output_tokens"] or 0, c["cache_create"] or 0)
    return x
y0 = series[0]["session_pct"]
for name, drop in (("A: failed cells metered", False), ("B: failed cells NOT metered", True)):
    xs = [cum(ts(s["t"]), drop) - cum(ts(series[0]["t"]), drop) for s in series]
    ys = [s["session_pct"] - y0 for s in series]
    k = sum(x * y for x, y in zip(xs, ys)) / sum(x * x for x in xs)
    rmse = (sum((y - k * x) ** 2 for x, y in zip(xs, ys)) / len(xs)) ** 0.5
    print(f"{name}: n={len(xs)} k={k:.2f} (5h pp per predicted pp) rmse={rmse:.2f} pp  final pred={xs[-1]:.1f} obs={ys[-1]}")
