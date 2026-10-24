#!/usr/bin/env python3
"""Skeptic denominator: all transcripts (main + subagents) in the 4 config dirs, requests with
timestamp >= now-7d, deduplicated GLOBALLY by message.id (last usage record wins). Read-only."""

import json, os, time, collections
from datetime import datetime, timezone

ACCTS = {
    "next": "~/.claude-next/projects",
    "next2": "~/.claude-secondary/projects",
    "next3": "~/.claude-tertiary/projects",
    "next4": "~/.claude-quaternary/projects",
}
NOW = time.time()
CUT = datetime.fromtimestamp(NOW - 7 * 86400, tz=timezone.utc).strftime(
    "%Y-%m-%dT%H:%M:%S"
)
seen = {}
raw_records = 0
nf = nb = 0
t0 = time.time()
for acct, root in ACCTS.items():
    root = os.path.realpath(os.path.expanduser(root))
    for dp, dns, fns in os.walk(root):
        for fn in fns:
            if not fn.endswith(".jsonl"):
                continue
            p = os.path.join(dp, fn)
            try:
                stt = os.stat(p)
            except OSError:
                continue
            if stt.st_mtime < NOW - 8 * 86400:
                continue
            nf += 1
            nb += stt.st_size
            is_sub = "/subagents/" in p
            intm = float(stt.st_mtime).is_integer()
            with open(p, "rb") as fh:
                for line in fh:
                    if b'"usage"' not in line or b'"assistant"' not in line:
                        continue
                    try:
                        d = json.loads(line)
                    except Exception:
                        continue
                    if d.get("type") != "assistant":
                        continue
                    if (d.get("timestamp") or "") < CUT:
                        continue
                    m = d.get("message") or {}
                    if m.get("model") == "<synthetic>":
                        continue
                    u = m.get("usage")
                    mid = m.get("id")
                    if not u or not mid:
                        continue
                    raw_records += 1
                    t = (
                        u.get("input_tokens") or 0,
                        u.get("cache_creation_input_tokens") or 0,
                        u.get("cache_read_input_tokens") or 0,
                        u.get("output_tokens") or 0,
                    )
                    mid = (acct, mid); prev = seen.get(mid)
                    if prev is None or (prev[3] and not intm):
                        seen[mid] = (acct, is_sub, t, intm)
                    elif prev[0] == acct:
                        seen[mid] = (acct, is_sub, t, intm)
    print(
        f"acct {acct} files={nf} GB={nb / 1e9:.2f} t={time.time() - t0:.0f}s",
        flush=True,
    )
W = lambda t: t[0] + t[1] * 1.25 + t[2] * 0.1 + t[3] * 5
agg = collections.defaultdict(lambda: [0, 0.0, [0, 0, 0, 0]])
for mid, (a, s, t, _) in seen.items():
    for k in ((a, "sub" if s else "main"), ("ALL", "all")):
        x = agg[k]
        x[0] += 1
        x[1] += W(t)
        for i in range(4):
            x[2][i] += t[i]
for k in sorted(agg):
    x = agg[k]
    print(
        k,
        "req",
        x[0],
        "wEq_M",
        round(x[1] / 1e6, 1),
        "in/cc/cr/out_M",
        [round(v / 1e6, 1) for v in x[2]],
    )
print(
    f"raw assistant usage records in window {raw_records}, unique message.id {len(seen)}"
)
print(
    f"DONE files={nf} GB={nb / 1e9:.2f} cut={CUT} t={time.time() - t0:.0f}s", flush=True
)
