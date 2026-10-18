#!/usr/bin/env python3
"""a8_burst_census.py — axis A8 (precompute/load): do slow SessionStart hook runs cluster in
startup BURSTS (many sessions starting together, each recomputing the same fleet-global state)?

READ-ONLY. Reads the transcript list (default /tmp/startup-hooks-census-files.txt). For every
SessionStart hook attachment of the dispatcher, dod-persist, desk-brief-inject and mailbox-drain it
records (timestamp, hook, durationMs, timedOut, config-dir guess). Then, for each dispatcher run,
counts how many OTHER dispatcher runs (any transcript) started within +/-W seconds, and reports the
duration distribution by concurrency band. Also prints per-hook duration percentiles for the three
separate SYNC hooks, whose output never reaches the dispatcher's 9 s child bound.

KNOWN BIAS (from the brief): hook_success with durationMs is recorded only when the hook printed.

Usage: python3 -I a8_burst_census.py [file_list] [--window 30]
"""

import json, sys, bisect, collections
from datetime import datetime

HOOKS = (
    "session-start-dispatch.sh",
    "dod-persist.sh",
    "desk-brief-inject.sh",
    "mailbox-drain.sh",
)


def ts_of(rec):
    t = rec.get("timestamp")
    if not t:
        return None
    try:
        return datetime.fromisoformat(t.replace("Z", "+00:00")).timestamp()
    except Exception:
        return None


def pct(xs, p):
    if not xs:
        return None
    xs = sorted(xs)
    return xs[max(0, min(len(xs) - 1, int(round(p / 100 * (len(xs) - 1)))))]


def main():
    args = sys.argv[1:]
    win = 30.0
    if "--window" in args:
        i = args.index("--window")
        win = float(args[i + 1])
        del args[i : i + 2]
    flist = args[0] if args else "/tmp/startup-hooks-census-files.txt"
    rows = []  # (ts, hook, ms, timedOut, file)
    for path in open(flist).read().split():
        if "/subagents/" in path:
            continue
        try:
            fh = open(path, errors="replace")
        except OSError:
            continue
        with fh:
            for line in fh:
                if '"SessionStart' not in line:
                    continue
                try:
                    rec = json.loads(line)
                except Exception:
                    continue
                a = rec.get("attachment") or {}
                if not str(a.get("hookName", "")).startswith("SessionStart"):
                    continue
                cmd = str(a.get("command", ""))
                hook = next((h for h in HOOKS if h in cmd), None)
                if not hook or a.get("type") not in ("hook_success", "hook_cancelled"):
                    continue
                ms = a.get("durationMs")
                if ms is None:
                    continue
                t = ts_of(rec)
                if t is None:
                    continue
                rows.append((t, hook, int(ms), bool(a.get("timedOut")), path))

    print(f"records: {len(rows)}  window: +/-{win:.0f}s")
    by_hook = collections.defaultdict(list)
    for t, h, ms, to, p in rows:
        by_hook[h].append((ms, to))
    for h in HOOKS:
        xs = [m for m, _ in by_hook[h]]
        tos = sum(1 for _, to in by_hook[h] if to)
        if xs:
            print(
                f"  {h:28s} n={len(xs):4d} p50={pct(xs, 50)} p90={pct(xs, 90)} p99={pct(xs, 99)} max={max(xs)} timedOut={tos}"
            )

    # dispatcher burst analysis. NOTE the record timestamp is when the attachment was WRITTEN
    # (i.e. at hook END); start ~= ts - ms/1000.
    d = sorted((t - ms / 1000.0, ms, to) for t, h, ms, to, _ in rows if h == HOOKS[0])
    starts = [s for s, _, _ in d]
    bands = collections.defaultdict(list)
    for s, ms, to in d:
        lo = bisect.bisect_left(starts, s - win)
        hi = bisect.bisect_right(starts, s + win)
        n = hi - lo - 1
        b = (
            "0"
            if n == 0
            else "1-2"
            if n <= 2
            else "3-5"
            if n <= 5
            else "6-10"
            if n <= 10
            else ">10"
        )
        bands[b].append(ms)
    print(
        f"\ndispatcher duration by number of OTHER dispatcher starts within +/-{win:.0f}s:"
    )
    for b in ("0", "1-2", "3-5", "6-10", ">10"):
        xs = bands.get(b, [])
        if xs:
            ge9 = sum(1 for x in xs if x >= 9000)
            print(
                f"  {b:>5s}: n={len(xs):4d} p50={pct(xs, 50):6d} p90={pct(xs, 90):6d} >=9s={ge9:4d} ({100 * ge9 / len(xs):.0f}%)"
            )

    # hour-of-day (local) profile: is slowness a time-of-load effect?
    hours = collections.defaultdict(list)
    for s, ms, to in d:
        hours[datetime.fromtimestamp(s).strftime("%m-%d %H")].append(ms)
    print("\ndispatcher by local hour (n, p50, share >=9s):")
    for k in sorted(hours):
        xs = hours[k]
        ge9 = sum(1 for x in xs if x >= 9000)
        print(f"  {k}: n={len(xs):3d} p50={pct(xs, 50):6d} >=9s={ge9:3d}")


if __name__ == "__main__":
    main()
