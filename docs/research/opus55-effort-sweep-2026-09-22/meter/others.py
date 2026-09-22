#!/usr/bin/env python3
"""others.py — tokens the OTHER consumers of a config dir spent inside a time window.

The sweep cells run with --no-session-persistence, so they write no transcript; every assistant
record under <config>/projects/**.jsonl whose timestamp falls in the window therefore belongs to a
different consumer of the same account. Claude Code writes one transcript line per content block,
all carrying the same message.id, so records are deduped on message.id taking the MAX per counter
(docs/research/usage-telemetry-100p-2026-08-16/skeptic-exchange-rate.md §1 — summing them triple-counts).

  others.py <config-dir> <start-iso> <end-iso>     # prints one JSON object: per-model token sums
"""

import json, os, sys
from datetime import datetime
from pathlib import Path

KEYS = (
    "input_tokens",
    "output_tokens",
    "cache_creation_input_tokens",
    "cache_read_input_tokens",
)


def ts(s):
    return datetime.fromisoformat(s.replace("Z", "+00:00"))


def main(cfg, start, end):
    t0, t1 = ts(start), ts(end)
    best = {}
    for f in Path(cfg, "projects").rglob("*.jsonl"):
        if os.path.getmtime(f) < t0.timestamp():
            continue
        for line in open(f, errors="replace"):
            if '"assistant"' not in line:
                continue
            try:
                r = json.loads(line)
            except ValueError:
                continue
            m = r.get("message") or {}
            u, mid, t = m.get("usage"), m.get("id"), r.get("timestamp")
            if (
                r.get("type") != "assistant"
                or not u
                or not mid
                or not t
                or not (t0 <= ts(t) <= t1)
            ):
                continue
            cur = best.setdefault(
                mid, {"model": m.get("model"), "file": str(f), **{k: 0 for k in KEYS}}
            )
            for k in KEYS:
                cur[k] = max(cur[k], u.get(k) or 0)
    out = {}
    for r in best.values():
        o = out.setdefault(
            r["model"], {"messages": 0, "files": set(), **{k: 0 for k in KEYS}}
        )
        o["messages"] += 1
        o["files"].add(Path(r["file"]).stem)
        for k in KEYS:
            o[k] += r[k]
    for o in out.values():
        o["files"] = sorted(o["files"])
    print(
        json.dumps(
            {"config": cfg, "start": start, "end": end, "by_model": out}, indent=1
        )
    )


if __name__ == "__main__":
    main(*sys.argv[1:4])
