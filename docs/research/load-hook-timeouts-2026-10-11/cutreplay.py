"""Reconstruct the exact Stop inputs of recorded hook cancels.

Usage: python3 -I cutreplay.py <hook-basename> <n> <outdir> [since-iso]
For the n most recent hook_cancelled records of <hook>, writes <outdir>/<k>/transcript.jsonl (the
transcript as it stood when that Stop fired: every line before the first Stop attachment of that
Stop), a symlink to the session's subagents dir, and <outdir>/<k>/stdin.json. Prints one line each.

       python3 -I cutreplay.py --event PreToolUse <hook-basename> <n> <outdir> [since-iso]
PreToolUse (startup-hooks-2026-10-18 README §5 Wave 7, A9-F9): the cancel record carries the
toolUseID, so the transcript is cut just after the assistant line holding that tool_use, and
stdin.json is the PreToolUse payload rebuilt from it (tool_name, tool_input, tool_use_id,
permission_mode). Replay those with a9-replay-pretooluse.py in a hermetic HOME: validate-bash
appends to logs under $HOME, so a replay against the real one would write into the live audit log.
"""

import datetime as dt
import glob
import json
import os
import sys

args = sys.argv[1:]
event = "Stop"
if args[:1] == ["--event"]:
    event, args = args[1], args[2:]
hook, n, out = args[0], int(args[1]), args[2]
since = args[3] if len(args) > 3 else None
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
            if a.get("type") != "hook_cancelled" or a.get("hookEvent") != event:
                continue
            if hook not in (a.get("command") or ""):
                continue
            if event != "Stop":
                # the transcript as the hook saw it: through the assistant line holding this tool_use
                tid = a.get("toolUseID") or ""
                j, use = i, None
                while tid and j > 0 and use is None:
                    j -= 1
                    if tid not in lines[j]:
                        continue
                    try:
                        pr = json.loads(lines[j])
                    except ValueError:
                        continue
                    for b in ((pr.get("message") or {}).get("content") or []):
                        if isinstance(b, dict) and b.get("type") == "tool_use" and b.get("id") == tid:
                            use = (b, pr.get("permissionMode") or r.get("permissionMode"))
                if use is None:
                    continue
                hits.append(
                    (
                        r.get("timestamp", ""),
                        p,
                        j + 1,
                        r.get("cwd") or "",
                        r.get("sessionId") or "",
                        use,
                    )
                )
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
                    None,
                )
            )
hits.sort(key=lambda h: h[:5], reverse=True)
seen = set()
k = 0
for ts, p, j, cwd, sid, use in hits:
    # ~/.claude-next/projects is a symlink to ~/.claude/projects: one transcript, two glob paths
    key = (os.path.realpath(p), j)
    if key in seen:
        continue
    seen.add(key)
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
    if use is None:
        payload = {
            "session_id": sid,
            "transcript_path": tp,
            "cwd": cwd,
            "hook_event_name": "Stop",
            "stop_hook_active": False,
        }
    else:
        payload = {
            "session_id": sid,
            "transcript_path": tp,
            "cwd": cwd,
            "permission_mode": use[1] or "default",
            "hook_event_name": event,
            "tool_name": use[0].get("name") or "",
            "tool_input": use[0].get("input") or {},
            "tool_use_id": use[0].get("id") or "",
        }
    with open(os.path.join(d, "stdin.json"), "w") as fh:
        json.dump(payload, fh)
    acct = p.split("/projects/")[0]
    print(k, ts, acct, cwd, len(lines), os.path.join(d, "stdin.json"))
