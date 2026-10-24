#!/usr/bin/env python3
# Scan main-session transcripts (not subagents) for Workflow tool_use inputs: key census, and how the
# script is supplied (inline `script` vs `scriptPath`). Streaming, mtime-bounded to the last N days.
import json, glob, os, sys, time, collections

DAYS = float(sys.argv[1]) if len(sys.argv) > 1 else 14
OUT = "/tmp/usage-audit/r2/lean-default/wf_inputs.jsonl"
cut = time.time() - DAYS * 86400
accts = {
    "next": "~/.claude-next",
    "next2": "~/.claude-secondary",
    "next3": "~/.claude-tertiary",
    "next4": "~/.claude-quaternary",
}
keys = collections.Counter()
shapes = collections.Counter()
n = 0
files = 0
seen = set()
with open(OUT, "w") as fo:
    for a, d in accts.items():
        for f in glob.glob(os.path.expanduser(d) + "/projects/*/*.jsonl"):
            try:
                if os.path.getmtime(f) < cut:
                    continue
            except OSError:
                continue
            files += 1
            with open(f, errors="replace") as fh:
                for line in fh:
                    if '"Workflow"' not in line:
                        continue
                    try:
                        r = json.loads(line)
                    except Exception:
                        continue
                    m = r.get("message") or {}
                    if not isinstance(m, dict) or m.get("role") != "assistant":
                        continue
                    for c in m.get("content") or []:
                        if (
                            isinstance(c, dict)
                            and c.get("type") == "tool_use"
                            and c.get("name") == "Workflow"
                        ):
                            if c.get("id") in seen:
                                continue
                            seen.add(c.get("id"))
                            inp = c.get("input") or {}
                            n += 1
                            for k in inp:
                                keys[k] += 1
                            sh = (
                                ("script" if inp.get("script") else "")
                                + ("+scriptPath" if inp.get("scriptPath") else "")
                                + ("+name" if inp.get("name") else "")
                            )
                            shapes[sh or "none"] += 1
                            fo.write(
                                json.dumps(
                                    {
                                        "acct": a,
                                        "file": f,
                                        "ts": r.get("timestamp"),
                                        "id": c.get("id"),
                                        "keys": sorted(inp),
                                        "scriptPath": inp.get("scriptPath"),
                                        "name": inp.get("name"),
                                        "script_len": len(inp.get("script") or ""),
                                        "script": inp.get("script"),
                                    }
                                )
                                + "\n"
                            )
print("files scanned", files, "Workflow tool_use (unique ids)", n)
print("input keys", keys.most_common())
print("shapes", shapes.most_common())
