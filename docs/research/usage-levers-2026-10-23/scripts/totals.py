#!/usr/bin/env python3
"""7-day total weighted usage per account (main + subagents), dedup by message.id across copied transcripts.
Copies carry integer mtimes (measured: 1207/1263 dup subagent pairs), so non-integer-mtime files are read first."""

import json, os, time

roots = {
    "next": "~/.claude-next/projects/",
    "next2": "~/.claude-secondary/projects/",
    "next3": "~/.claude-tertiary/projects/",
    "next4": "~/.claude-quaternary/projects/",
}
CUT = "2026-10-16T23:59"
files = []
for a, r in roots.items():
    r = os.path.expanduser(r)
    for dp, dn, fns in os.walk(r):
        for fn in fns:
            if fn.endswith(".jsonl"):
                p = os.path.join(dp, fn)
                try:
                    st = os.stat(p)
                except OSError:
                    continue
                if st.st_mtime >= time.time() - 7.2 * 86400:
                    files.append((float(st.st_mtime).is_integer(), a, p, st.st_size))
files.sort()
seen = {}
tot = {a: {"main": [0, 0, 0, 0, 0], "sub": [0, 0, 0, 0, 0]} for a in roots}
gb = 0
t0 = time.time()
for isint, a, p, sz in files:
    gb += sz
    sub = "/subagents/" in p
    with open(p, "rb") as fh:
        for line in fh:
            if b'"type":"assistant"' not in line or b'"usage"' not in line:
                continue
            try:
                d = json.loads(line)
            except Exception:
                continue
            if d.get("type") != "assistant" or (d.get("timestamp") or "") < CUT:
                continue
            m = d.get("message") or {}
            if m.get("model") == "<synthetic>":
                continue
            u = m.get("usage") or {}
            mid = m.get("id")
            v = (
                u.get("input_tokens") or 0,
                u.get("cache_creation_input_tokens") or 0,
                u.get("cache_read_input_tokens") or 0,
                u.get("output_tokens") or 0,
            )
            prev = seen.get(mid)
            if prev is None:
                seen[mid] = (a, "sub" if sub else "main", list(v))
                t = tot[a]["sub" if sub else "main"]
                for i in range(4):
                    t[i] += v[i]
                t[4] += 1
            else:
                pa, pk, pv = prev
                t = tot[pa][pk]
                for i in range(4):
                    if v[i] > pv[i]:
                        t[i] += v[i] - pv[i]
                        pv[i] = v[i]
json.dump(tot, open("/tmp/usage-audit/lever-subagents/totals.json", "w"))
print("files", len(files), "GB", round(gb / 1e9, 2), "t", int(time.time() - t0))
for a, x in tot.items():
    for k, t in x.items():
        w = t[0] + t[1] * 1.25 + t[2] * 0.1 + t[3] * 5
        print(
            a,
            k,
            "req",
            t[4],
            "in",
            t[0],
            "cc",
            t[1],
            "cr",
            t[2],
            "out",
            t[3],
            "wEq_M",
            round(w / 1e6, 1),
        )
print("DONE")
