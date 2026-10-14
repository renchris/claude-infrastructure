"""Per-hook Stop runtime from transcript history: runs, cancels, cancels/hour, p50/p95/p99 ms.

Usage: python3 -I stop-hook-durations.py <since-iso> [until-iso]
A RUN is any transcript attachment with hookEvent == "Stop" whose command names one of the
four hooks; durationMs is read from hook_success and hook_cancelled alike (a cancel's duration
is its timeout plus the kill latency, so a percentile at or over the timeout means "cancelled").
Load per minute (1-min, from ~/.claude/logs/capacity-alarm.jsonl) is reported as context.
"""

import datetime as dt
import glob
import json
import os
import sys

HOOKS = (
    "operator-readout.sh",
    "session-continue.sh",
    "completion-assert.sh",
    "boundary-handoff.sh",
)
P = lambda s: dt.datetime.fromisoformat(s.replace("Z", "+00:00"))
t0 = P(sys.argv[1])
t1 = P(sys.argv[2]) if len(sys.argv) > 2 else dt.datetime.now(dt.timezone.utc)
hours = (t1 - t0).total_seconds() / 3600

loads = []
for line in open(os.path.expanduser("~/.claude/logs/capacity-alarm.jsonl")):
    try:
        r = json.loads(line)
        t = P(r["ts"])
    except (ValueError, KeyError, TypeError):
        continue
    if t0 <= t <= t1 and isinstance(r.get("load_1m"), (int, float)):
        loads.append(r["load_1m"])

dur = {h: [] for h in HOOKS}
canc = {h: 0 for h in HOOKS}
seen = set()
cut = t0.timestamp() - 60
for root in glob.glob(os.path.expanduser("~") + "/.claude*/projects"):
    for dp, _, fns in os.walk(root):
        for fn in fns:
            if not fn.endswith(".jsonl"):
                continue
            p = os.path.join(dp, fn)
            try:
                if os.path.getmtime(p) < cut:
                    continue
                fh = open(p, errors="replace")
            except OSError:
                continue
            with fh:
                for line in fh:
                    if '"Stop"' not in line or "durationMs" not in line:
                        continue
                    try:
                        r = json.loads(line)
                    except ValueError:
                        continue
                    a = r.get("attachment") or {}
                    if a.get("hookEvent") != "Stop" or not r.get("timestamp"):
                        continue
                    t = P(r["timestamp"])
                    if not t0 <= t <= t1:
                        continue
                    h = os.path.basename((a.get("command") or "?").split()[0])
                    if h not in dur or not isinstance(
                        a.get("durationMs"), (int, float)
                    ):
                        continue
                    # a resumed/forked transcript can replay a record: count each uuid once
                    key = r.get("uuid") or (p, line[:200])
                    if key in seen:
                        continue
                    seen.add(key)
                    dur[h].append(a["durationMs"])
                    if a.get("type") == "hook_cancelled":
                        canc[h] += 1


def pct(xs, q):
    if not xs:
        return float("nan")
    xs = sorted(xs)
    return xs[min(len(xs) - 1, int(q * len(xs)))]


ls = sorted(loads)
print(
    f"window {t0:%Y-%m-%dT%H:%MZ} -> {t1:%Y-%m-%dT%H:%MZ} ({hours:.2f} h); "
    f"1-min load samples={len(ls)} median={pct(ls, 0.5):.0f} p95={pct(ls, 0.95):.0f}"
)
print(
    f"{'hook':22s} {'runs':>6s} {'cancels':>7s} {'canc/h':>7s} {'p50ms':>7s} {'p95ms':>7s} {'p99ms':>7s}"
)
for h in HOOKS:
    xs = dur[h]
    print(
        f"{h:22s} {len(xs):6d} {canc[h]:7d} {canc[h] / max(hours, 1e-9):7.2f} "
        f"{pct(xs, 0.5):7.0f} {pct(xs, 0.95):7.0f} {pct(xs, 0.99):7.0f}"
    )
