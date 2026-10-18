#!/usr/bin/env python3
"""a2-hook-durations.py — per-hook SessionStart duration census (read-only).

Reads the transcript list (default /tmp/startup-hooks-census-files.txt), keeps attachment records
whose hookEvent is SessionStart and that carry a durationMs, groups by the hook script's basename
(from .command), and prints n / p50 / p75 / p90 / p95 / p99 / max (ms) plus timedOut counts.
Also prints, per hook, the mean chars of additionalContext / systemMessage content it emitted.

KNOWN BIAS (stated by the brief): hook_success with durationMs is recorded only when the hook
prints something, so a silent hook is under-sampled and its distribution is the PRINTING subset.
Usage: python3 -I a2-hook-durations.py [filelist]
"""

import json
import os
import sys
from collections import defaultdict

lst = sys.argv[1] if len(sys.argv) > 1 else "/tmp/startup-hooks-census-files.txt"
dur = defaultdict(list)
tout = defaultdict(int)
types = defaultdict(lambda: defaultdict(int))
ctx_chars = defaultdict(list)
by_trigger = defaultdict(lambda: defaultdict(int))


def q(v, p):
    if not v:
        return 0
    v = sorted(v)
    i = min(len(v) - 1, int(round(p * (len(v) - 1))))
    return v[i]


def name(cmd):
    if not cmd:
        return "?"
    first = cmd.split()[0]
    return os.path.basename(first)


for path in open(lst):
    path = path.strip()
    if not path or "/subagents/" in path:
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
            except ValueError:
                continue
            a = rec.get("attachment")
            if not isinstance(a, dict):
                continue
            if a.get("hookEvent") != "SessionStart" and not str(
                a.get("hookName", "")
            ).startswith("SessionStart"):
                continue
            n = name(a.get("command"))
            t = a.get("type", "?")
            types[n][t] += 1
            by_trigger[n][a.get("hookName", "?")] += 1
            if "durationMs" in a and isinstance(a["durationMs"], (int, float)):
                dur[n].append(a["durationMs"])
            if a.get("timedOut"):
                tout[n] += 1
            if t in ("hook_additional_context", "hook_system_message"):
                c = a.get("content")
                if isinstance(c, list):
                    c = "".join(str(x) for x in c)
                ctx_chars[(n, t)].append(len(str(c or "")))

print(
    f"{'hook':34} {'n':>5} {'p50':>6} {'p75':>6} {'p90':>6} {'p95':>6} {'p99':>6} {'max':>6} {'tOut':>5}"
)
for n in sorted(dur, key=lambda k: -q(dur[k], 0.5)):
    v = dur[n]
    print(
        f"{n:34} {len(v):5d} {q(v, 0.5):6.0f} {q(v, 0.75):6.0f} {q(v, 0.9):6.0f} {q(v, 0.95):6.0f} {q(v, 0.99):6.0f} {max(v):6.0f} {tout[n]:5d}"
    )
print()
print("record types per hook:")
for n in sorted(types):
    print(f"  {n:34} " + ", ".join(f"{k}={v}" for k, v in sorted(types[n].items())))
print()
print("content chars per (hook, channel): n mean p50 max")
for (n, t), v in sorted(ctx_chars.items()):
    print(
        f"  {n:34} {t:24} {len(v):5d} {sum(v) / len(v):8.0f} {q(v, 0.5):7.0f} {max(v):7d}"
    )
