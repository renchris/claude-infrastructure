#!/usr/bin/env python3
"""Q2 — does an account with no live sessions on this Mac drift between reads?

Re-runnable, stdlib only, read-only. Input: ~/.claude/logs/account-utilization.jsonl (live rows only,
stale == false). For consecutive live reads P, N of one account, drift = N - P per meter, skipping a
meter whose reset stamp fell between P and N (a roll is not drift). Decreases are reported apart:
those are reset/redemption/relogin events (q3), never drift.
"""

import collections
import json
import os
from datetime import datetime

UTIL = os.path.expanduser("~/.claude/logs/account-utilization.jsonl")
GAPS = (
    (0, 300, "≤5m"),
    (300, 900, "5-15m"),
    (900, 3600, "15-60m"),
    (3600, 21600, "1-6h"),
    (21600, 1e12, ">6h"),
)


def ts(s):
    return datetime.fromisoformat(s).timestamp()


def q(xs, p):
    xs = sorted(xs)
    return xs[min(len(xs) - 1, int(p * len(xs)))] if xs else None


def passed(stamp, t0, t1):
    if not stamp:
        return False
    try:
        return t0 < ts(stamp) + 60 and ts(stamp) <= t1 + 60
    except ValueError:
        return False


def kb(k):
    return "0" if k == 0 else "1-3" if k <= 3 else "4-8" if k <= 8 else "9+"


def main():
    by = collections.defaultdict(list)
    with open(UTIL, errors="replace") as f:
        for ln in f:
            try:
                r = json.loads(ln)
            except ValueError:
                continue
            if not r.get("stale") and r.get("acct") and r.get("k") is not None:
                by[r["acct"]].append(r)
    up = collections.defaultdict(list)  # (class, gap, meter) -> [delta ≥ 0]
    rate = collections.defaultdict(list)  # k bucket -> [pp/h weekly], gap ≤ 15 min
    k0pos, down = [], []
    pairs = 0
    for a, rs in by.items():
        rs.sort(key=lambda r: r["ts"])
        for p, n in zip(rs, rs[1:]):
            t0, t1 = ts(p["ts"]), ts(n["ts"])
            g = t1 - t0
            if g <= 0:
                continue
            pairs += 1
            idle = (
                p["k"] == 0 and n["k"] == 0 and not (p.get("k_work") or n.get("k_work"))
            )
            cls = "k0" if idle else "k≥1"
            gl = next(
                lbl for lo, hi, lbl in GAPS if lo < g <= hi or (lo == 0 and g <= hi)
            )
            for m, stamp in (
                ("session", "session_reset_at"),
                ("weekly", "weekly_reset_at"),
            ):
                a0, a1 = p.get(f"{m}_pct"), n.get(f"{m}_pct")
                if a0 is None or a1 is None or passed(p.get(stamp), t0, t1):
                    continue
                d = a1 - a0
                if d < 0:
                    down.append((a, p["ts"], n["ts"], m, d, p["k"], n["k"]))
                    continue
                up[(cls, gl, m)].append(d)
                if idle and d >= 1:
                    k0pos.append((a, p["ts"][:19], n["ts"][11:19], m, d, g))
                if m == "weekly" and not idle and g <= 900:
                    rate[kb(max(p["k"], n["k"]))].append(d / (g / 3600))
    print(f"live pairs: {pairs}")
    print("\n1/3. upward drift (pp) by activity class × gap × meter")
    print(
        f"   {'class':4s} {'gap':7s} {'meter':8s} {'n':>6s} {'p50':>4s} {'p90':>4s} {'p99':>4s} "
        f"{'max':>4s} {'any>0':>6s}"
    )
    for cls in ("k0", "k≥1"):
        for _, _, gl in GAPS:
            for m in ("session", "weekly"):
                xs = up.get((cls, gl, m))
                if xs:
                    nz = sum(1 for x in xs if x > 0) / len(xs)
                    print(
                        f"   {cls:4s} {gl:7s} {m:8s} {len(xs):6d} {q(xs, 0.5):4d} {q(xs, 0.9):4d} "
                        f"{q(xs, 0.99):4d} {max(xs):4d} {nz:6.3f}"
                    )
    print(f"\n2. k=0 pairs with weekly/session drift ≥1pp: {len(k0pos)}")
    byacct = collections.Counter((x[0], x[3]) for x in k0pos)
    print("   by (acct, meter):", dict(byacct))
    big = [x for x in k0pos if x[4] >= 3]
    print(f"   of which ≥3pp: {len(big)}")
    for x in sorted(big, key=lambda x: -x[4])[:15]:
        print(
            f"   {x[0]:6s} {x[1]} → {x[2]}  {x[3]:7s} +{x[4]}pp over {x[5] / 60:.0f} min"
        )
    print("\n3. weekly drift rate (pp/h) for active accounts, gap ≤15 min, by max(k)")
    for b in ("1-3", "4-8", "9+"):
        xs = rate.get(b)
        if xs:
            print(
                f"   k {b:4s} n={len(xs):5d} p50 {q(xs, 0.5):.2f} p90 {q(xs, 0.9):.2f} "
                f"p99 {q(xs, 0.99):.2f}"
            )
    print(
        f"\n4. DECREASES with no reset stamp passing (events, not drift): {len(down)}"
    )
    big = [d for d in down if d[4] <= -5]
    print(f"   of which ≤ -5pp: {len(big)}")
    for d in big[:20]:
        print(
            f"   {d[0]:6s} {d[1][:19]} → {d[2][11:19]} {d[3]:7s} {d[4]:+d}pp  k {d[5]}→{d[6]}"
        )


if __name__ == "__main__":
    main()
