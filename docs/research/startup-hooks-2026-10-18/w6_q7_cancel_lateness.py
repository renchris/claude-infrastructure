#!/usr/bin/env python3
"""Q7 census: how late do harness hook timeouts fire? Reads `hook_cancelled` attachment records
(durationMs, timeoutMs, timedOut) from every account's transcripts modified in the last N days.
Read-only. Usage: python3 -I docs/research/startup-hooks-2026-10-18/w6_q7_cancel_lateness.py [days]"""

import glob, json, os, re, sys, time, collections

days = float(sys.argv[1]) if len(sys.argv) > 1 else 3
cut = time.time() - days * 86400
pat = re.compile(r'\{[^{}]*"type":"hook_cancelled"[^{}]*\}')
rows, files, seen = [], 0, set()
for d in glob.glob(os.path.expanduser("~/.claude*/projects")):
    for p in glob.glob(d + "/**/*.jsonl", recursive=True):
        rp = os.path.realpath(p)
        if rp in seen:
            continue
        seen.add(rp)
        try:
            if os.path.getmtime(p) < cut:
                continue
            s = open(p, errors="replace").read()
        except OSError:
            continue
        files += 1
        for m in pat.finditer(s):
            try:
                r = json.loads(m.group(0))
            except ValueError:
                continue
            if (
                r.get("timedOut")
                and isinstance(r.get("durationMs"), int)
                and isinstance(r.get("timeoutMs"), int)
            ):
                rows.append(
                    (
                        r.get("hookEvent", "?"),
                        r.get("command", "?"),
                        r["durationMs"],
                        r["timeoutMs"],
                    )
                )


def pct(xs, q):
    xs = sorted(xs)
    return xs[min(len(xs) - 1, int(q * (len(xs) - 1) + 0.5))] if xs else None


late = [d - t for _, _, d, t in rows]
print(
    f"window={days}d transcripts={files} timed-out cancels={len(rows)} (records may repeat when a session is resumed/forked)"
)
if late:
    print(
        f"lateness ms (durationMs - timeoutMs): min={min(late)} p50={pct(late, 0.5)} p90={pct(late, 0.9)} p99={pct(late, 0.99)} max={max(late)}"
    )
    for lim in (100, 1000, 5000, 10000):
        print(f"  > {lim} ms late: {sum(1 for x in late if x > lim)}")
by = collections.defaultdict(list)
for e, c, d, t in rows:
    by[e].append(d - t)
for e, xs in sorted(by.items(), key=lambda kv: -len(kv[1])):
    print(f"{e:18} n={len(xs):5} p50={pct(xs, 0.5)} p90={pct(xs, 0.9)} max={max(xs)}")
top = sorted(rows, key=lambda r: r[2] - r[3], reverse=True)[:5]
for e, c, d, t in top:
    print(f"latest: {e} {c} durationMs={d} timeoutMs={t} late={d - t}")
