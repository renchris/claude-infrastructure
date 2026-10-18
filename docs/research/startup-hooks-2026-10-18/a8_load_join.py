#!/usr/bin/env python3
"""a8_load_join.py — axis A8: does SessionStart hook duration track machine load?

READ-ONLY. Joins every SessionStart attachment of the dispatcher / dod-persist / mailbox-drain
(transcript list, default /tmp/startup-hooks-census-files.txt) to the nearest load_1m sample in
~/.claude/logs/capacity-alarm.jsonl (60 s cadence, com.claude.capacity-alarm), then prints the
duration distribution per load band and the Spearman rank correlation.

Usage: python3 -I a8_load_join.py [file_list] [capacity_jsonl]
"""

import json, sys, os, bisect, collections
from datetime import datetime

HOOKS = ("session-start-dispatch.sh", "dod-persist.sh", "mailbox-drain.sh")


def ts(s):
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except Exception:
        return None


def pct(xs, p):
    xs = sorted(xs)
    return (
        xs[max(0, min(len(xs) - 1, int(round(p / 100 * (len(xs) - 1)))))]
        if xs
        else None
    )


def ranks(v):
    o = sorted(range(len(v)), key=lambda i: v[i])
    r = [0.0] * len(v)
    i = 0
    while i < len(o):
        j = i
        while j + 1 < len(o) and v[o[j + 1]] == v[o[i]]:
            j += 1
        for k in range(i, j + 1):
            r[o[k]] = (i + j) / 2.0
        i = j + 1
    return r


def spearman(x, y):
    if len(x) < 3:
        return None
    rx, ry = ranks(x), ranks(y)
    n = len(x)
    mx, my = sum(rx) / n, sum(ry) / n
    cov = sum((a - mx) * (b - my) for a, b in zip(rx, ry))
    vx = sum((a - mx) ** 2 for a in rx) ** 0.5
    vy = sum((b - my) ** 2 for b in ry) ** 0.5
    return cov / (vx * vy) if vx and vy else None


def main():
    flist = sys.argv[1] if len(sys.argv) > 1 else "/tmp/startup-hooks-census-files.txt"
    cap = (
        sys.argv[2]
        if len(sys.argv) > 2
        else os.path.expanduser("~/.claude/logs/capacity-alarm.jsonl")
    )
    lt, lv = [], []
    with open(cap, errors="replace") as fh:
        for line in fh:
            if '"load_1m"' not in line:
                continue
            try:
                r = json.loads(line)
            except Exception:
                continue
            t = ts(r.get("ts", ""))
            v = r.get("load_1m")
            if t is not None and isinstance(v, (int, float)):
                lt.append(t)
                lv.append(float(v))
    order = sorted(range(len(lt)), key=lambda i: lt[i])
    lt = [lt[i] for i in order]
    lv = [lv[i] for i in order]
    runs = collections.defaultdict(list)  # hook -> [(load, ms, timedOut)]
    for path in open(flist).read().split():
        try:
            fh = open(path, errors="replace")
        except OSError:
            continue
        with fh:
            for line in fh:
                if '"SessionStart' not in line:
                    continue
                try:
                    r = json.loads(line)
                except Exception:
                    continue
                a = r.get("attachment") or {}
                if a.get("type") not in ("hook_success", "hook_cancelled"):
                    continue
                if not str(a.get("hookName", "")).startswith("SessionStart"):
                    continue
                h = next((x for x in HOOKS if x in str(a.get("command", ""))), None)
                ms = a.get("durationMs")
                t = ts(r.get("timestamp", ""))
                if not h or ms is None or t is None:
                    continue
                st = t - ms / 1000.0
                i = bisect.bisect_left(lt, st)
                best = min(
                    (j for j in (i - 1, i) if 0 <= j < len(lt)),
                    key=lambda j: abs(lt[j] - st),
                    default=None,
                )
                if best is None or abs(lt[best] - st) > 120:
                    continue
                runs[h].append((lv[best], int(ms), bool(a.get("timedOut"))))
    print(
        f"load samples: {len(lt)}  span: {datetime.fromtimestamp(lt[0]):%m-%d %H:%M} .. {datetime.fromtimestamp(lt[-1]):%m-%d %H:%M}"
    )
    bands = [(0, 100), (100, 200), (200, 300), (300, 400), (400, 500), (500, 9999)]
    for h in HOOKS:
        xs = runs[h]
        if not xs:
            continue
        rho = spearman([a for a, _, _ in xs], [b for _, b, _ in xs])
        print(
            f"\n{h}: n={len(xs)} spearman(load_1m, ms)={rho:.2f}"
            if rho is not None
            else f"\n{h}: n={len(xs)}"
        )
        for lo, hi in bands:
            ys = [(m, to) for l, m, to in xs if lo <= l < hi]
            if ys:
                ms = [m for m, _ in ys]
                print(
                    f"  load {lo:>3}-{hi:<4}: n={len(ys):4d} p50={pct(ms, 50):6d} p90={pct(ms, 90):6d} "
                    f">=9s={sum(1 for m in ms if m >= 9000):3d} timedOut={sum(1 for _, t in ys if t):3d}"
                )


if __name__ == "__main__":
    main()
