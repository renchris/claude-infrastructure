#!/usr/bin/env python3
"""A6-harness: does the first turn wait on sync SessionStart hooks? Read-only.

Usage: python3 -I a6_firstturn.py /tmp/startup-hooks-census-files.txt
For each main transcript with a SessionStart:startup batch, compares:
  ss_end   = latest end (timestamp) of a sync startup hook record (hook_success/hook_cancelled/
             hook_non_blocking_error carry durationMs; async_hook_response does not)
  ss_start = earliest inferred start (timestamp - durationMs)
  u1       = timestamp of the first non-meta user record (the first prompt as processed)
  a1       = timestamp of the first assistant record
and reports gap = u1 - ss_end. A cluster of small positive gaps for prompts that existed at launch
is the signature of the first turn being held until the hooks finished.
Also reports, for sessions where u1 - ss_start < 30 s (prompt supplied at/near launch), how much of
the launch-to-first-prompt time was SessionStart hook time.
"""

import json, sys
from datetime import datetime


def ts(s):
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except Exception:
        return None


def pct(xs, p):
    if not xs:
        return None
    xs = sorted(xs)
    return xs[max(0, min(len(xs) - 1, int(round(p / 100 * (len(xs) - 1)))))]


gaps, near = [], []
hold = []
for f in (l.strip() for l in open(sys.argv[1]) if l.strip()):
    ss_end = ss_start = u1 = a1 = None
    try:
        fh = open(f, errors="replace")
    except OSError:
        continue
    with fh:
        for line in fh:
            try:
                r = json.loads(line)
            except Exception:
                continue
            t = ts(r.get("timestamp") or "")
            if t is None:
                continue
            a = r.get("attachment")
            if (
                isinstance(a, dict)
                and (a.get("hookName") or "") == "SessionStart:startup"
                and a.get("durationMs") is not None
            ):
                s = t - a["durationMs"] / 1000.0
                ss_start = s if ss_start is None else min(ss_start, s)
                ss_end = t if ss_end is None else max(ss_end, t)
            if r.get("type") == "user" and u1 is None and not r.get("isMeta"):
                c = r.get("message", {}).get("content")
                if isinstance(c, str) or (
                    isinstance(c, list)
                    and any(isinstance(x, dict) and x.get("type") == "text" for x in c)
                ):
                    u1 = t
            if r.get("type") == "assistant" and a1 is None:
                a1 = t
            if u1 and a1 and ss_end:
                break
    if ss_end is None or u1 is None:
        continue
    gaps.append(u1 - ss_end)
    if u1 - ss_start < 30:
        near.append((u1 - ss_start, ss_end - ss_start, u1 - ss_end))

print(f"sessions with startup batch + first prompt: {len(gaps)}")
neg = [g for g in gaps if g < 0]
print(f"  first prompt recorded BEFORE last startup hook ended: {len(neg)}")
for lo, hi in ((0, 0.5), (0.5, 2), (2, 10), (10, 60), (60, 1e9)):
    print(f"  gap in [{lo},{hi}) s: {sum(1 for g in gaps if lo <= g < hi)}")
print(f"prompt within 30 s of hook start (supplied at/near launch): n={len(near)}")
if near:
    print(
        "  launch->prompt s p50/p90/max:",
        [round(pct([x[0] for x in near], p), 2) for p in (50, 90, 100)],
    )
    print(
        "  hook span s      p50/p90/max:",
        [round(pct([x[1] for x in near], p), 2) for p in (50, 90, 100)],
    )
    print(
        "  prompt - hookend s p50/p90/min:",
        [round(pct([x[2] for x in near], p), 3) for p in (50, 90, 0)],
    )
