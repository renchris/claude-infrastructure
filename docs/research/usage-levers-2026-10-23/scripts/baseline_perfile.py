#!/usr/bin/env python3
# Read-only. Per transcript (mtime < 7d): unique requests in the last 7 days, summed cache_read,
# cache_creation, and the min cache_read+cache_creation+input seen (floor of the context).
import json, os, time, datetime

ACCTS = {
    "next": "~/.claude-next",
    "next2": "~/.claude-secondary",
    "next3": "~/.claude-tertiary",
    "next4": "~/.claude-quaternary",
}
CUTOFF = time.time() - 7 * 86400
CUT_ISO = datetime.datetime.utcfromtimestamp(CUTOFF).strftime("%Y-%m-%dT%H:%M:%S")
out = open("/tmp/usage-audit/baseline_perfile.jsonl", "w")
seen_root = set()
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
            seen = set()
            req = cr = cc = 0
            try:
                with open(p, "rb") as fh:
                    for raw in fh:
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
                        req += 1
                        cr += u.get("cache_read_input_tokens", 0) or 0
                        cc += u.get("cache_creation_input_tokens", 0) or 0
            except OSError:
                continue
            out.write(
                json.dumps({"acct": acct, "path": p, "req": req, "cr": cr, "cc": cc})
                + "\n"
            )
out.close()
print("DONE")
