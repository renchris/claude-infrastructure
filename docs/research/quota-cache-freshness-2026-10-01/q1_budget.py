#!/usr/bin/env python3
"""Q1 — the 429 poll budget on /api/oauth/usage: scope, window, who spends it.

Re-runnable, stdlib only, read-only. Inputs:
  ~/.claude/logs/claude-accounts.log           probe lines (429 always logged; success only near-wall)
  ~/.claude/logs/account-utilization.jsonl     k / k_work per account per recorded read
Prints the tables quoted in q1-budget.md.
"""

import bisect
import collections
import json
import os
import re
from datetime import datetime

LOG = os.path.expanduser("~/.claude/logs/claude-accounts.log")
UTIL = os.path.expanduser("~/.claude/logs/account-utilization.jsonl")
LINE = re.compile(r"^(\S+) probe (\S+): (429 poll-throttled|wire —)")


def ts(s):
    return datetime.fromisoformat(s).timestamp()


def load_probes():
    out = []  # (t, acct, ok)
    with open(LOG, errors="replace") as f:
        for ln in f:
            m = LINE.match(ln)
            if m:
                out.append(
                    (ts(m.group(1)), m.group(2), not m.group(3).startswith("429"))
                )
    out.sort()
    return out


def load_util():
    by = collections.defaultdict(list)
    with open(UTIL, errors="replace") as f:
        for ln in f:
            try:
                r = json.loads(ln)
            except ValueError:
                continue
            by[r.get("acct")].append(r)
    for a in by:
        by[a].sort(key=lambda r: r["ts"])
    return by


def q(xs, p):
    if not xs:
        return None
    xs = sorted(xs)
    return xs[min(len(xs) - 1, int(p * len(xs)))]


def main():
    P = load_probes()
    thr = [p for p in P if not p[1 + 1]]
    print(
        f"probe lines: {len(P)}  429s: {len(thr)}  span {datetime.utcfromtimestamp(P[0][0]):%F} → "
        f"{datetime.utcfromtimestamp(P[-1][0]):%F %H:%MZ}"
    )

    # 1. SCOPE — other accounts' probes within ±3 s of a 429
    times = [p[0] for p in P]
    solo = allthr = alone = 0
    for t, a, ok in thr:
        lo, hi = bisect.bisect_left(times, t - 3), bisect.bisect_right(times, t + 3)
        others = [P[i] for i in range(lo, hi) if P[i][1] != a]
        if not others:
            alone += 1
        elif any(o[2] for o in others):
            solo += 1
        else:
            allthr += 1
    print("\n1. SCOPE (other accounts' logged probes within ±3 s of a 429)")
    print(f"   another account SUCCEEDED in the same sweep : {solo}")
    print(f"   every co-swept logged account also 429'd    : {allthr}")
    print(f"   no other account logged within ±3 s        : {alone}")

    # 1b. per account 429 counts + simultaneous multi-account 429 bursts
    per = collections.Counter(a for _, a, _ in thr)
    print("   429s per account:", dict(per))

    # 2. WINDOW — per account gaps
    by = collections.defaultdict(list)
    for t, a, ok in P:
        by[a].append((t, ok))
    prev_gap, to_ok, run_len, run_span = [], [], [], []
    for a, xs in by.items():
        i = 0
        while i < len(xs):
            if not xs[i][1]:
                j = i
                while j + 1 < len(xs) and not xs[j + 1][1]:
                    j += 1
                if i > 0:
                    prev_gap.append(xs[i][0] - xs[i - 1][0])
                run_len.append(j - i + 1)
                run_span.append(xs[j][0] - xs[i][0])
                if j + 1 < len(xs):
                    to_ok.append(xs[j + 1][0] - xs[i][0])
                i = j + 1
            else:
                i += 1
    print(
        "\n2. WINDOW (per account; 429 runs = consecutive logged 429s of one account)"
    )
    print(
        f"   runs: {len(run_len)}  run length p50 {q(run_len, 0.5)} p90 {q(run_len, 0.9)} max {max(run_len)}"
    )
    print(
        f"   run span s     p50 {q(run_span, 0.5):.0f} p90 {q(run_span, 0.9):.0f} max {max(run_span):.0f}"
    )
    print(
        f"   gap prev-probe→first-429 s p10 {q(prev_gap, 0.1):.0f} p50 {q(prev_gap, 0.5):.0f} "
        f"p90 {q(prev_gap, 0.9):.0f}  (n={len(prev_gap)})"
    )
    print(
        f"   first-429→next-logged-success s p50 {q(to_ok, 0.5):.0f} p90 {q(to_ok, 0.9):.0f} "
        f"max {max(to_ok):.0f}  (n={len(to_ok)}; an UPPER bound — unlogged successes)"
    )

    # 3. 429 rate vs k — join each probe to the nearest earlier utilization row for that account
    U = load_util()
    uts = {a: [ts(r["ts"]) for r in rs] for a, rs in U.items()}

    def k_at(a, t):
        xs = uts.get(a)
        if not xs:
            return None, None
        i = bisect.bisect_right(xs, t) - 1
        if i < 0 or t - xs[i] > 900:
            return None, None
        r = U[a][i]
        return r.get("k"), r.get("k_work")

    def bucket(k):
        if k is None:
            return "unk"
        return "0" if k == 0 else "1-3" if k <= 3 else "4-8" if k <= 8 else "9+"

    tab = collections.defaultdict(lambda: [0, 0])
    tabw = collections.defaultdict(lambda: [0, 0])
    for t, a, ok in P:
        k, kw = k_at(a, t)
        tab[bucket(k)][0 if ok else 1] += 1
        tabw[bucket(kw)][0 if ok else 1] += 1
    print(
        "\n3. 429 share of LOGGED probes by live sessions k (nearest util row ≤900 s before)"
    )
    print(
        "   NB: successes are logged only for near-wall accounts, so this is a ratio over a biased"
    )
    print("   denominator; compare buckets with each other, not with 0.")
    for name, tb in (("k", tab), ("k_work", tabw)):
        for b in ("0", "1-3", "4-8", "9+", "unk"):
            okc, th = tb[b]
            n = okc + th
            if n:
                print(f"   {name:6s} {b:4s} n={n:6d}  429={th:5d}  share={th / n:.3f}")

    # 4. POLLS PER ACCOUNT PER HOUR — logged probes only, last 7 days
    end = P[-1][0]
    win = [p for p in P if p[0] > end - 7 * 86400]
    hrs = collections.defaultdict(collections.Counter)
    for t, a, ok in win:
        hrs[a][int(t // 3600)] += 1
    print(
        "\n4. LOGGED probes per account-hour, last 7 d (only hours with ≥1 logged probe)"
    )
    for a in sorted(hrs):
        v = list(hrs[a].values())
        print(
            f"   {a:6s} hours={len(v):4d}  p50 {q(v, 0.5)}  p90 {q(v, 0.9)}  max {max(v)}"
        )

    # 5. 429 after usage-lowering events (weekly fell, weekly_reset_at did not pass)
    ev = []
    for a, rs in U.items():
        live = [r for r in rs if not r.get("stale")]
        for p, n in zip(live, live[1:]):
            if (
                p.get("weekly_pct") is not None
                and n.get("weekly_pct") is not None
                and n["weekly_pct"] < p["weekly_pct"] - 5
            ):
                wr = p.get("weekly_reset_at")
                passed = wr is not None and ts(wr) <= ts(n["ts"])
                if not passed:
                    ev.append((a, ts(p["ts"]), ts(n["ts"])))
    print(
        f"\n5. redemption-shaped events (weekly fell >5pp, weekly reset not passed): {len(ev)}"
    )
    for a, t0, t1 in ev:
        near = [x for x in thr if x[1] == a and t0 <= x[0] <= t1 + 900]
        print(
            f"   {a:6s} {datetime.utcfromtimestamp(t0):%F %H:%M}Z→{datetime.utcfromtimestamp(t1):%H:%M}Z  "
            f"429s in [prev read, next read + 15 min]: {len(near)}"
        )
    span_h = (P[-1][0] - P[0][0]) / 3600
    for a in sorted(per):
        print(f"   baseline {a}: {per[a] / span_h:.3f} 429/h over {span_h:.0f} h")


if __name__ == "__main__":
    main()


def window_after_429():
    """P(next event of the same account is another 429 | gap since a 429). Success markers are
    BOTH the logged wire successes and the utilization series' live rows (stale == false), so the
    near-wall-only blindness of the log is covered by the series for every account."""
    ev = collections.defaultdict(list)          # acct -> [(t, ok)]
    for t, a, ok in load_probes():
        ev[a].append((t, ok))
    for a, rs in load_util().items():
        for r in rs:
            if not r.get("stale"):
                ev[a].append((ts(r["ts"]), True))
    bins = ((0, 30), (30, 60), (60, 120), (120, 180), (180, 300), (300, 600), (600, 1800))
    tab = collections.defaultdict(lambda: [0, 0])
    for a, xs in ev.items():
        xs.sort()
        for (t0, ok0), (t1, ok1) in zip(xs, xs[1:]):
            if ok0:
                continue
            g = t1 - t0
            for lo, hi in bins:
                if lo <= g < hi:
                    tab[(lo, hi)][0 if ok1 else 1] += 1
    print("\n2b. after a 429, is the SAME account's next event another 429? (by gap)")
    for lo, hi in bins:
        okc, th = tab[(lo, hi)]
        n = okc + th
        if n:
            print(f"   gap {lo:4d}-{hi:<4d}s n={n:5d}  next-is-429={th / n:.3f}")


if __name__ == "__main__":
    window_after_429()


def wall_share():
    """Is the 429 an AT-THE-WALL phenomenon? Compare the share of 429s whose account's last good
    read was at a wall (session or weekly ≥ 99, or a rejected wire) with the share of all good
    reads that were. Claude Code's own `/api/oauth/usage?at_wall=1` read (binary 2.1.284) fires
    from a walled session, so a per-token budget predicts a strong over-representation."""
    U = load_util()
    live = {a: [r for r in rs if not r.get("stale")] for a, rs in U.items()}
    lts = {a: [ts(r["ts"]) for r in rs] for a, rs in live.items()}

    def walled(r):
        return ((r.get("session_pct") or 0) >= 99 or (r.get("weekly_pct") or 0) >= 99
                or r.get("wire_7d_status") == "rejected" or r.get("wire_5h_status") == "rejected")
    hit = n = 0
    for t, a, ok in load_probes():
        if ok:
            continue
        i = bisect.bisect_right(lts.get(a, []), t) - 1
        if i < 0:
            continue
        n += 1
        hit += walled(live[a][i])
    base = [walled(r) for rs in live.values() for r in rs]
    print(f"\n6. 429s whose account was at a wall at its last good read: {hit}/{n} = {hit / n:.3f}")
    print(f"   baseline: good reads at a wall {sum(base)}/{len(base)} = {sum(base) / len(base):.3f}")


if __name__ == "__main__":
    wall_share()


def stale_share_by_k():
    """The unbiased form of question 3. The utilization series samples throttled (stale) and
    good rows the SAME way, so the stale share per k bucket is a like-for-like rate. Restricted
    to auth == ok so a logged-out account's error rows do not count as throttles."""
    U = load_util()
    tab = collections.defaultdict(lambda: [0, 0])
    since = collections.defaultdict(lambda: [0, 0])
    cut = max(ts(r["ts"]) for rs in U.values() for r in rs) - 14 * 86400
    for a, rs in U.items():
        for r in rs:
            if r.get("auth") != "ok" or r.get("k") is None:
                continue
            k = r["k"]
            b = "0" if k == 0 else "1-3" if k <= 3 else "4-8" if k <= 8 else "9+"
            tab[b][1 if r.get("stale") else 0] += 1
            if ts(r["ts"]) > cut:
                since[b][1 if r.get("stale") else 0] += 1
    print("\n7. stale (throttled) share of utilization rows by live sessions k, auth ok")
    for name, tb in (("all", tab), ("last 14 d", since)):
        for b in ("0", "1-3", "4-8", "9+"):
            g, s = tb[b]
            if g + s:
                print(f"   {name:9s} k {b:4s} n={g + s:6d} stale={s:5d} share={s / (g + s):.4f}")


if __name__ == "__main__":
    stale_share_by_k()


def episode_length():
    """A throttle EPISODE = first 429 of an account until that account's next success (logged
    wire success or live utilization row). Its length is how long every caller is blind."""
    ev = collections.defaultdict(list)
    for t, a, ok in load_probes():
        ev[a].append((t, ok))
    for a, rs in load_util().items():
        for r in rs:
            if not r.get("stale"):
                ev[a].append((ts(r["ts"]), True))
    lens, polls = [], []
    for a, xs in ev.items():
        xs.sort()
        start = None
        k = 0
        for t, ok in xs:
            if not ok:
                if start is None:
                    start, k = t, 0
                k += 1
            elif start is not None:
                lens.append(t - start)
                polls.append(k)
                start = None
    lens_m = [x / 60 for x in lens]
    print(f"\n8. throttle episodes: {len(lens)}  length min p50 {q(lens_m, .5):.1f} "
          f"p75 {q(lens_m, .75):.1f} p90 {q(lens_m, .9):.1f} p99 {q(lens_m, .99):.1f}")
    print(f"   logged 429s per episode p50 {q(polls, .5)} p90 {q(polls, .9)} max {max(polls)}")
    short = sum(1 for x in lens if x <= 360)
    print(f"   episodes cleared within 6 min (≈ one series sample): {short}/{len(lens)}")


if __name__ == "__main__":
    episode_length()
