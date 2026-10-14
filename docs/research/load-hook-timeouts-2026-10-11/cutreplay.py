"""Reconstruct the exact Stop inputs of recorded hook cancels.

Usage: python3 -I cutreplay.py <hook-basename> <n> <outdir> [since-iso]
For the n most recent hook_cancelled records of <hook>, writes <outdir>/<k>/transcript.jsonl (the
transcript as it stood when that Stop fired: every line before the first Stop attachment of that
Stop), a symlink to the session's subagents dir, and <outdir>/<k>/stdin.json. Prints one line each.
"""

import datetime as dt
import glob
import json
import os
import sys

hook, n, out = sys.argv[1], int(sys.argv[2]), sys.argv[3]
since = sys.argv[4] if len(sys.argv) > 4 else None
cut = 0
if since:
    cut = dt.datetime.fromisoformat(since.replace("Z", "+00:00")).timestamp()
hits = []
for root in glob.glob(os.path.expanduser("~") + "/.claude*/projects"):
    for p in glob.glob(root + "/*/*.jsonl"):
        try:
            if os.path.getmtime(p) < cut:
                continue
            lines = open(p, errors="replace").read().split("\n")
        except OSError:
            continue
        for i, line in enumerate(lines):
            if hook not in line or "hook_cancelled" not in line:
                continue
            try:
                r = json.loads(line)
            except ValueError:
                continue
            a = r.get("attachment") or {}
            if a.get("type") != "hook_cancelled" or a.get("hookEvent") != "Stop":
                continue
            if hook not in (a.get("command") or ""):
                continue
            # walk back to the first attachment of this Stop (all Stop attachments are contiguous)
            j = i
            while j > 0:
                try:
                    pr = json.loads(lines[j - 1])
                except ValueError:
                    break
                if (pr.get("attachment") or {}).get("hookEvent") == "Stop" or pr.get(
                    "type"
                ) in ("system",):
                    j -= 1
                    continue
                break
            hits.append(
                (
                    r.get("timestamp", ""),
                    p,
                    j,
                    r.get("cwd") or "",
                    r.get("sessionId") or "",
                )
            )
hits.sort(reverse=True)
seen = set()
k = 0
for ts, p, j, cwd, sid in hits:
    if (p, j) in seen:
        continue
    seen.add((p, j))
    k += 1
    if k > n:
        break
    d = os.path.join(out, str(k))
    os.makedirs(d, exist_ok=True)
    lines = open(p, errors="replace").read().split("\n")[:j]
    tp = os.path.join(d, sid + ".jsonl")
    with open(tp, "w") as fh:
        fh.write("\n".join(lines) + "\n")
    sub = p[: -len(".jsonl")] + "/subagents"
    if os.path.isdir(sub) and not os.path.exists(os.path.join(d, sid, "subagents")):
        os.makedirs(os.path.join(d, sid), exist_ok=True)
        os.symlink(sub, os.path.join(d, sid, "subagents"))
    with open(os.path.join(d, "stdin.json"), "w") as fh:
        json.dump(
            {
                "session_id": sid,
                "transcript_path": tp,
                "cwd": cwd,
                "hook_event_name": "Stop",
                "stop_hook_active": False,
            },
            fh,
        )
    acct = p.split("/projects/")[0]
    print(k, ts, acct, cwd, len(lines), os.path.join(d, "stdin.json"))
