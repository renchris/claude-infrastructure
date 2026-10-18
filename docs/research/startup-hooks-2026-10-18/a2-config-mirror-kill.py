#!/usr/bin/env python3
"""a2-config-mirror-kill.py — is config-mirror-assert.sh the dispatcher child killed at the 9 s bound?

config-mirror-assert.sh runs only for non-default accounts (CLAUDE_CONFIG_DIR=~/.claude-*), and when
it finds a standing warning it prints a top-level systemMessage starting "knowledge-layer mirror".
If that warning is present in fast dispatcher runs and ABSENT in runs that hit the bound, the child
was killed (its output is dropped with no record). Also prints optional-marker rates for the other
silent-when-healthy children, split by account and by duration bin, and samples the message text.

Read-only. Usage: python3 -I a2-config-mirror-kill.py [filelist]
"""

import json
import re
import sys
from collections import Counter, defaultdict

lst = sys.argv[1] if len(sys.argv) > 1 else "/tmp/startup-hooks-census-files.txt"
M = {
    "config-mirror": "knowledge-layer mirror",
    "escalation": "ESCALATION PIPELINE",
    "activation": "ACTIVATION",
    "session-index": "Session index:",
    "frontier": "Frontier:",
}
stat = defaultdict(Counter)
durs = defaultdict(list)
samples = Counter()
for path in open(lst):
    path = path.strip()
    if not path or "/subagents/" in path:
        continue
    m = re.search(r"/\.claude(-[a-z]+)?/projects/", path)
    acct = (m.group(1) or "-default") if m else "?"
    try:
        fh = open(path, errors="replace")
    except OSError:
        continue
    with fh:
        for line in fh:
            if "session-start-dispatch" not in line:
                continue
            try:
                a = json.loads(line).get("attachment")
            except ValueError:
                continue
            if not isinstance(a, dict) or a.get("type") != "hook_success":
                continue
            d = a.get("durationMs") or 0
            b = "<9s" if d < 9000 else ">=9s"
            out = a.get("stdout") or ""
            key = (acct, b)
            stat[key]["n"] += 1
            durs[acct].append(d)
            for k, mk in M.items():
                if mk in out:
                    stat[key][k] += 1
            i = out.find("knowledge-layer mirror")
            if i >= 0:
                samples[re.sub(r"\d+", "N", out[i : i + 160])] += 1

print("account        bin    n  " + "  ".join(f"{k:>13}" for k in M))
for key in sorted(stat):
    c = stat[key]
    print(f"{key[0]:14} {key[1]:5} {c['n']:4d}  " + "  ".join(f"{c[k]:13d}" for k in M))
print()
for acct, v in sorted(durs.items()):
    v.sort()
    q = lambda p: v[min(len(v) - 1, int(round(p * (len(v) - 1))))]
    print(
        f"{acct:14} dispatcher n={len(v):4d} p50 {q(0.5):6.0f} p90 {q(0.9):6.0f} share>=9s {sum(1 for x in v if x >= 9000) / len(v):5.1%}"
    )
print("\nconfig-mirror message shapes (digits->N):")
for s, n in samples.most_common(5):
    print(f"  {n:4d}  {s!r}")
