#!/usr/bin/env python3
"""Reviewer: re-derive run/script/site counts and denied-runs-per-week from review-numbers/scan.py output."""

import collections
import json
from datetime import datetime, timezone

O = "/tmp/lean-idle/workflow-lean/review-numbers"
CUT_MS = 1790226000000  # 2026-09-24 00:00 CDT
END = datetime(2026, 10, 24, 23, 59, tzinfo=timezone.utc)
runs = [json.loads(l) for l in open(f"{O}/runs.jsonl")]
slots = collections.defaultdict(list)
for l in open(f"{O}/slots.jsonl"):
    s = json.loads(l)
    slots[s["runId"]].append(s)


def ts_ms(ts):
    return datetime.fromisoformat(ts.replace("Z", "+00:00")).timestamp() * 1000


def start_of(r):
    if r.get("start"):
        return r["start"]
    if r.get("ts_min"):
        return ts_ms(r["ts_min"])
    return None


inwin = [r for r in runs if (start_of(r) or 0) >= CUT_MS]
print("runs total", len(runs), "in window", len(inwin))
print(
    "  with script",
    sum(1 for r in inwin if r["sha"]),
    "no script",
    sum(1 for r in inwin if not r["sha"]),
)
print("  dir-only (no json)", sum(1 for r in inwin if not r["jsons"]))
print(
    "  with >1 dir copy",
    sum(1 for r in inwin if r["ncopies"] > 1),
    " shared aids",
    sum(len(r.get("shared_aids", [])) for r in inwin),
)
print("  zero slots", sum(1 for r in inwin if not slots.get(r["runId"])))
sc = [r for r in inwin if r["sha"]]
wd = [r for r in sc if r["would_deny"]]
allt = [
    r
    for r in sc
    if r["sites"] and all(s["verdict"] == "has-agent-type" for s in r["sites"])
]
print(
    "would-deny runs",
    len(wd),
    f"{100 * len(wd) / len(sc):.1f}% of scripted",
    "all-typed",
    len(allt),
)
shas = {}
for r in sc:
    shas[r["sha"]] = shas.get(r["sha"], False) or r["would_deny"]
print("unique scripts", len(shas), "would-deny", sum(shas.values()))
sv = collections.Counter(s["verdict"] for r in sc for s in r["sites"])
print("sites", dict(sv))
nslots = sum(len(slots.get(r["runId"], [])) for r in inwin)
print("slots in window", nslots)
wk = collections.Counter()
for r in wd:
    st = start_of(r)
    d = (END - datetime.fromtimestamp(st / 1000, tz=timezone.utc)).days
    wk[d // 7] += 1
print("denied runs by week (0=last 7d)", dict(sorted(wk.items())))
# would-deny runs by launch kind: names that look automated/probe
names = collections.Counter((r.get("name") or "?") for r in wd)
print("top wd names", names.most_common(8))
# test/probe/scratch runs (cwd in /tmp) among would-deny
tmp = 0
for r in wd:
    ss = slots.get(r["runId"], [])
    cw = [s.get("cwd") or "" for s in ss]
    if cw and all(c.startswith(("/tmp", "/private/tmp", "/var/folders")) for c in cw):
        tmp += 1
print("would-deny runs whose slots all ran in /tmp", tmp)
