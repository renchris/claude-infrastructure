#!/usr/bin/env python3
"""Real behavior: what a SUBAGENT does right after a PreToolUse(Bash) hook deny, or after Claude
Code's built-in 'Blocked: sleep' refusal. Read-only over transcripts.
Usage: python3 -I deny_followups.py <files.txt> <out.jsonl>
One row per unique denied tool_use id (copies across accounts deduped): the deny class, the denied
input, and the next 3 tool calls (name, input) plus whether each of those was itself denied."""

import json, re, sys

CLASSES = [
    ("goal-gate", "A /goal is LIVE in this session"),
    ("dup-worker", "DUPLICATE WORKER"),
    ("spawn-cap", "SPAWN GENERATION CAP"),
    ("danger-rm", "Dangerous command pattern blocked"),
    ("headless-resume", "headless resume"),
    ("inert-kill-flag", "Inert flag in a kill"),
    ("unscoped-kill", "Worktree-UNSCOPED kill"),
    ("pattern-kill", "Pattern kill blocked"),
    ("empty-selector-kill", "Empty-selector kill blocked"),
    ("ddl", "DDL blocked"),
    ("drizzle", "drizzle-kit push"),
    ("git-add-force", "git add"),
    ("no-verify", "--no-verify blocked"),
    ("no-gpg", "--no-gpg-sign blocked"),
    ("commit-n", "git commit -n blocked"),
    ("identity", "identity"),
    ("shared-checkout", "SHARED CHECKOUT"),
    ("perm-harvest", "cc-permission-harvest"),
    ("dia-act", "cc-dia-act"),
    ("tabs", "TABS ARE RETIRED"),
    ("tabs", "kitty tabs are retired"),
    ("launcher", "hand-built"),
    ("launchagent", "LaunchAgent load refused"),
]


def classify(txt):
    if txt.startswith("<tool_use_error>Blocked: sleep"):
        return "builtin-sleep-block"
    for k, p in CLASSES:
        if p in txt[:600]:
            return k
    return "other:" + re.sub(
        r"\s+", " ", txt[len("PreToolUse:Bash hook error: ") :][:60]
    )


def result_text(c):
    if isinstance(c, str):
        return c
    if isinstance(c, list):
        return "\n".join(
            x.get("text", "")
            for x in c
            if isinstance(x, dict) and x.get("type") == "text"
        )
    return ""


seen = set()
out = open(sys.argv[2], "w")
for f in (l.strip() for l in open(sys.argv[1])):
    if not f:
        continue
    calls = []  # (id, name, input, ts)
    res = {}  # id -> text
    try:
        fh = open(f, errors="replace")
    except OSError:
        continue
    for line in fh:
        if "tool_use" not in line and "tool_result" not in line:
            continue
        try:
            d = json.loads(line)
        except Exception:
            continue
        m = d.get("message") if isinstance(d.get("message"), dict) else {}
        if d.get("type") == "assistant":
            for c in m.get("content") or []:
                if isinstance(c, dict) and c.get("type") == "tool_use":
                    calls.append(
                        (
                            c.get("id"),
                            c.get("name"),
                            c.get("input") or {},
                            d.get("timestamp"),
                        )
                    )
        elif d.get("type") == "user" and isinstance(m.get("content"), list):
            for x in m["content"]:
                if isinstance(x, dict) and x.get("type") == "tool_result":
                    res[x.get("tool_use_id")] = result_text(x.get("content"))
    for i, (cid, name, inp, ts) in enumerate(calls):
        t = res.get(cid) or ""
        if not (
            t.startswith("PreToolUse:Bash hook")
            or t.startswith("<tool_use_error>Blocked: sleep")
        ):
            continue
        if cid in seen:
            continue
        seen.add(cid)
        nxt = []
        for nid, nn, ni, nts in calls[i + 1 : i + 4]:
            nt = res.get(nid) or ""
            nxt.append(
                {
                    "name": nn,
                    "input": {
                        k: (v[:1500] if isinstance(v, str) else v)
                        for k, v in ni.items()
                        if k
                        in (
                            "command",
                            "timeout",
                            "run_in_background",
                            "description",
                            "timeout_ms",
                            "task_id",
                            "block",
                        )
                    },
                    "denied": nt.startswith("PreToolUse:Bash hook")
                    or nt.startswith("<tool_use_error>Blocked: sleep"),
                    "res_head": nt[:200],
                }
            )
        out.write(
            json.dumps(
                {
                    "id": cid,
                    "file": f,
                    "ts": ts,
                    "cls": classify(t),
                    "reason_head": t[:300],
                    "denied_input": {
                        k: (v[:1500] if isinstance(v, str) else v)
                        for k, v in inp.items()
                        if k
                        in ("command", "timeout", "run_in_background", "description")
                    },
                    "next": nxt,
                }
            )
            + "\n"
        )
out.close()
