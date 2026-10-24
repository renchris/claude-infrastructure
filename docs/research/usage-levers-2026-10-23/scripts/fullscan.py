#!/usr/bin/env python3
# Read-only. Stream every transcript modified in the last 7 days; for assistant records with a
# timestamp in the last 7 days, dedupe by requestId (fallback message.id) and sum usage per
# account and main/subagent. Only lines containing '"assistant"' are parsed.
import json, os, time, datetime

ACCTS = {
    "next": "~/.claude-next",
    "next2": "~/.claude-secondary",
    "next3": "~/.claude-tertiary",
    "next4": "~/.claude-quaternary",
}
NOW = time.time()
CUTOFF = NOW - 7 * 86400
CUT_ISO = datetime.datetime.utcfromtimestamp(CUTOFF).strftime("%Y-%m-%dT%H:%M:%S")
agg = {}
seen_root = set()
nbytes = 0
for acct, base in ACCTS.items():
    root = os.path.realpath(os.path.expanduser(base + "/projects"))
    if root in seen_root:
        continue
    seen_root.add(root)
    for dp, dn, fn in os.walk(root):
        for f in fn:
            if not f.endswith(".jsonl"):
                continue
            p = os.path.join(dp, f)
            try:
                if os.stat(p).st_mtime < CUTOFF:
                    continue
            except OSError:
                continue
            kind = "sub" if "/subagents/" in p else "main"
            k = (acct, kind)
            a = agg.setdefault(k, {"req": 0, "inp": 0, "cc": 0, "cr": 0, "out": 0})
            seen = set()
            try:
                with open(p, "rb") as fh:
                    for raw in fh:
                        nbytes += len(raw)
                        if b'"type":"assistant"' not in raw:
                            continue
                        try:
                            r = json.loads(raw)
                        except Exception:
                            continue
                        if (r.get("timestamp") or "") < CUT_ISO:
                            continue
                        m = r.get("message") or {}
                        u = m.get("usage")
                        if not u:
                            continue
                        rid = r.get("requestId") or m.get("id")
                        if rid in seen:
                            continue
                        seen.add(rid)
                        a["req"] += 1
                        a["inp"] += u.get("input_tokens", 0) or 0
                        a["cc"] += u.get("cache_creation_input_tokens", 0) or 0
                        a["cr"] += u.get("cache_read_input_tokens", 0) or 0
                        a["out"] += u.get("output_tokens", 0) or 0
            except OSError:
                continue
json.dump(
    {
        "cutoff": CUT_ISO,
        "bytes_scanned": nbytes,
        "agg": {f"{a}|{k}": v for (a, k), v in agg.items()},
    },
    open("/tmp/usage-audit/fullscan.json", "w"),
    indent=1,
)
print("DONE")
