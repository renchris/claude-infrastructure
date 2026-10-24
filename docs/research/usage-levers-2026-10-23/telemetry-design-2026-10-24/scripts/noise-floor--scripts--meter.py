#!/usr/bin/env python3
# Weekly-meter pp consumed per account per America/Chicago day, from account-utilization.jsonl.
# usage: python3 -I meter.py <out_json>
# Consumption = sum of positive weekly_pct steps between consecutive good readings in the same weekly
# window (window id = weekly_reset_at rounded to the hour) + the first reading of a new window (its
# pct accrued since the reset). Good reading = auth in (ok, healed) and not stale.
# Saturation: minutes an account spent with weekly_pct >= 100 (consumption is censored there).
import json
import sys
from collections import defaultdict
from datetime import datetime, timedelta, timezone

S = 1790398800  # 2026-09-26 00:00 CDT
E = S + 28 * 86400
CDT = timezone(timedelta(hours=-5))
out = sys.argv[1]


def day_of(t):
    return datetime.fromtimestamp(t, CDT).strftime("%Y-%m-%d")


rows = defaultdict(list)
for line in open("/Users/chrisren/.claude/logs/account-utilization.jsonl"):
    try:
        r = json.loads(line)
    except Exception:
        continue
    t = datetime.fromisoformat(r["ts"]).timestamp()
    if t < S - 8 * 86400 or t > E + 3600:
        continue
    if r.get("auth") not in ("ok", "healed") or r.get("stale"):
        continue
    wp = r.get("weekly_pct")
    if wp is None or not r.get("weekly_reset_at"):
        continue
    wr = round(datetime.fromisoformat(r["weekly_reset_at"]).timestamp() / 3600.0)
    rows[r["acct"]].append((t, int(wp), wr))

res = {}
for a, rs in rows.items():
    rs.sort()
    pp = defaultdict(float)
    sat = defaultdict(float)
    neg = 0
    neg_pp = 0
    resets = 0
    prev = None
    for t, wp, wr in rs:
        if prev is not None:
            pt, pwp, pwr = prev
            if wr == pwr:
                d = wp - pwp
                if d > 0:
                    pp[day_of(t)] += d
                elif d < 0:
                    neg += 1
                    neg_pp += -d
                if pwp >= 100 and t - pt < 3600:
                    sat[day_of(t)] += (t - pt) / 60.0
            elif wr > pwr:
                resets += 1
                pp[day_of(t)] += wp
            # wr < pwr: a stale window id reappearing; skip the step
        prev = (t, wp, wr)
    days = [day_of(S + i * 86400 + 3600) for i in range(28)]
    res[a] = {
        "pp": {d: pp.get(d, 0.0) for d in days},
        "sat_min": {d: round(sat.get(d, 0.0), 1) for d in days},
        "neg_steps": neg,
        "neg_pp": neg_pp,
        "resets": resets,
        "n_readings": len(rs),
    }
json.dump(res, open(out, "w"), indent=1)
for a in sorted(res):
    v = res[a]
    tot = sum(v["pp"].values())
    satd = sum(1 for x in v["sat_min"].values() if x > 0)
    print(
        "%s pp_28d=%.0f pp/week=%.1f sat_days=%d sat_hours=%.1f resets=%d neg_steps=%d neg_pp=%d"
        % (
            a,
            tot,
            tot / 4,
            satd,
            sum(v["sat_min"].values()) / 60,
            v["resets"],
            v["neg_steps"],
            v["neg_pp"],
        )
    )
print("fleet pp/week=%.1f" % (sum(sum(v["pp"].values()) for v in res.values()) / 4))
