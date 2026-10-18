#!/usr/bin/env python3
"""a2-child-presence.py — infer WHICH dispatcher child was killed, from the dispatcher's own stdout.

The dispatcher (hooks/session-start-dispatch.sh) prints one merged JSON; its hook_success record
carries that stdout verbatim. Several children print an unconditional marker:
    session-start.sh        -> "MCP:"   (always, every source)
    setup-plan-symlinks.sh  -> "Plans:" (always)
    setup-task-symlinks.sh  -> "Tasks:" (always)
    accounts-board.sh       -> a top-level systemMessage on every source except compact
A marker ABSENT from a run's stdout means that child produced nothing, i.e. (for these
always-print children) it was killed at CC_SSD_BOUND_S or crashed. Runs are binned by dispatcher
durationMs. Also: per SessionStart event (toolUseID), which sync hook was the slowest (the
critical path), using hook_success/hook_cancelled durationMs of the four sync registrations.

Read-only. Usage: python3 -I a2-child-presence.py [filelist]
"""

import json
import os
import sys
from collections import Counter, defaultdict

lst = sys.argv[1] if len(sys.argv) > 1 else "/tmp/startup-hooks-census-files.txt"
MARKERS = {"session-start.sh": "MCP:", "setup-plan": "Plans:", "setup-task": "Tasks:"}
SYNC = {
    "session-start-dispatch.sh",
    "dod-persist.sh",
    "mailbox-drain.sh",
    "desk-brief-inject.sh",
}

runs = []  # (dur, source, present-dict, cancelled)
events = defaultdict(dict)  # (file, toolUseID) -> {hook: dur}


def base(cmd):
    return os.path.basename((cmd or "?").split()[0])


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
                a = json.loads(line).get("attachment")
            except ValueError:
                continue
            if not isinstance(a, dict) or a.get("type") not in (
                "hook_success",
                "hook_cancelled",
            ):
                continue
            h = base(a.get("command"))
            src = str(a.get("hookName", "")).split(":")[-1]
            d = a.get("durationMs")
            if h in SYNC and isinstance(d, (int, float)):
                events[(path, a.get("toolUseID"))][h] = (
                    d,
                    a.get("type") == "hook_cancelled",
                )
            if h != "session-start-dispatch.sh":
                continue
            if a.get("type") == "hook_cancelled":
                runs.append((d or 0, src, None, True))
                continue
            out = a.get("stdout") or ""
            ctx, sm = "", ""
            try:
                j = json.loads(out.strip().splitlines()[-1]) if out.strip() else {}
                ctx = (j.get("hookSpecificOutput") or {}).get(
                    "additionalContext", ""
                ) or ""
                sm = j.get("systemMessage", "") or ""
            except (ValueError, IndexError, AttributeError):
                ctx = out
            pres = {k: (m in ctx) for k, m in MARKERS.items()}
            pres["accounts-board"] = bool(sm) if src != "compact" else None
            pres["_ctxlen"] = len(ctx)
            pres["_smlen"] = len(sm)
            runs.append((d or 0, src, pres, False))

print(
    f"dispatcher runs: {len(runs)}  cancelled(whole output lost): {sum(1 for r in runs if r[3])}"
)
print("source mix:", dict(Counter(r[1] for r in runs)))
for lo, hi, label in ((0, 9000, "<9s"), (9000, 1e9, ">=9s")):
    sel = [r for r in runs if not r[3] and lo <= r[0] < hi]
    print(f"\n== dispatcher duration {label}: n={len(sel)}")
    for k in ("session-start.sh", "setup-plan", "setup-task", "accounts-board"):
        vals = [r[2][k] for r in sel if r[2][k] is not None]
        miss = sum(1 for v in vals if not v)
        print(
            f"  {k:18} missing {miss:4d} / {len(vals):4d}  ({(100.0 * miss / len(vals)) if vals else 0:5.1f}%)"
        )
    combos = Counter(
        tuple(
            k
            for k in ("session-start.sh", "setup-plan", "setup-task", "accounts-board")
            if r[2][k] is False
        )
        for r in sel
    )
    print("  missing-set combos:", dict(combos.most_common(8)))

# critical path per event
crit = Counter()
crit_dur = defaultdict(list)
spans = []
for key, hs in events.items():
    if "session-start-dispatch.sh" not in hs:
        continue
    top = max(hs.items(), key=lambda kv: kv[1][0])
    crit[top[0]] += 1
    crit_dur[top[0]].append(top[1][0])
    spans.append(top[1][0])
print(
    f"\n== critical path (slowest SYNC hook per SessionStart event, events with a dispatcher record): n={sum(crit.values())}"
)
for h, n in crit.most_common():
    v = sorted(crit_dur[h])
    print(f"  {h:28} {n:4d}  median span when critical {v[len(v) // 2]:6.0f} ms")
spans.sort()
if spans:
    q = lambda p: spans[min(len(spans) - 1, int(round(p * (len(spans) - 1))))]
    print(
        f"  sync span (max of sync hooks) p50 {q(0.5):.0f} p90 {q(0.9):.0f} p95 {q(0.95):.0f} max {spans[-1]:.0f} ms"
    )
# how often each non-dispatcher sync hook is within 500ms of / above the dispatcher
for h in ("dod-persist.sh", "mailbox-drain.sh"):
    both = [
        (hs[h][0], hs["session-start-dispatch.sh"][0])
        for hs in events.values()
        if h in hs and "session-start-dispatch.sh" in hs
    ]
    above = sum(1 for a, b in both if a > b)
    print(f"  {h:28} slower than the dispatcher in {above}/{len(both)} events")
