#!/usr/bin/env python3
"""Criterion (c), real behavior, from transcripts: a subagent's own bounded FOREGROUND wait slice
(a while/until/for…sleep loop under an inner `timeout N`, N < 300, tool timeout <= 270000 or none)
that ran out (result shows exit 124). What is the agent's NEXT tool call?
  RESUMED     another bounded foreground loop slice (inner < 300, tool timeout <= 270000/none)
  ESCALATED   a foreground loop with inner >= 300 or tool timeout > 270000 (what W3 would deny)
  BACKGROUND  a backgrounded Bash
  MONITOR     Monitor
  CHECK       a one-shot Bash check (no loop)
  OTHER       any other tool / ended
Copies deduped by tool_use id. Usage: python3 -I slice_timeouts_tx.py <files.txt> <out.jsonl>"""

import json, re, sys
from collections import Counter, defaultdict

TO_RX = re.compile(r"(?:^|[;&|\s(])g?timeout\s+(?:-\S+\s+)*([0-9]+)([sm]?)\s")
LOOP = re.compile(r"(^|[;&|\s(])(while|until|for)\s.*sleep\s", re.S)
T124 = re.compile(r"\b124\b")


def inner(cmd):
    ns = [
        int(m.group(1)) * (60 if m.group(2) == "m" else 1) for m in TO_RX.finditer(cmd)
    ]
    return max(ns) if ns else None


def rtext(c):
    if isinstance(c, str):
        return c
    if isinstance(c, list):
        return "\n".join(
            x.get("text", "")
            for x in c
            if isinstance(x, dict) and x.get("type") == "text"
        )
    return ""


def kind(n):
    if n is None:
        return "OTHER (ended)"
    nm, inp = n[1], n[2]
    if nm == "Monitor":
        return "MONITOR"
    if nm != "Bash":
        return "OTHER (%s)" % nm
    c = inp.get("command") or ""
    if inp.get("run_in_background"):
        return "BACKGROUND"
    to = inp.get("timeout")
    long_to = isinstance(to, (int, float)) and to > 270000
    nn = inner(c)
    if LOOP.search(c):
        if long_to or (nn is not None and nn >= 300):
            return "ESCALATED (long fg loop; W3 would deny)"
        return (
            "RESUMED (bounded fg slice)"
            if nn is not None
            else "RESUMED-unwrapped (fg loop, tool timeout <=270000/none)"
        )
    return "CHECK (one-shot Bash)"


seen = set()
k = Counter()
out = open(sys.argv[2], "w")
per_agent = defaultdict(list)
for f in (l.strip() for l in open(sys.argv[1])):
    calls = []
    res = {}
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
                    calls.append((c.get("id"), c.get("name"), c.get("input") or {}))
        elif d.get("type") == "user" and isinstance(m.get("content"), list):
            for x in m["content"]:
                if isinstance(x, dict) and x.get("type") == "tool_result":
                    res[x.get("tool_use_id")] = rtext(x.get("content"))
    for i, (cid, nm, inp) in enumerate(calls):
        if nm != "Bash" or cid in seen or inp.get("run_in_background"):
            continue
        c = inp.get("command") or ""
        n = inner(c)
        to = inp.get("timeout")
        if (
            n is None
            or n >= 300
            or not LOOP.search(c)
            or (isinstance(to, (int, float)) and to > 270000)
        ):
            continue
        t = res.get(cid) or ""
        if not T124.search(t[-400:] if len(t) > 400 else t):
            continue
        seen.add(cid)
        nx = calls[i + 1] if i + 1 < len(calls) else None
        kk = kind(nx)
        k[kk] += 1
        per_agent[f].append(kk)
        out.write(
            json.dumps(
                {
                    "id": cid,
                    "file": f,
                    "cmd": c[:300],
                    "inner": n,
                    "to": to,
                    "next_kind": kk,
                    "next": None
                    if nx is None
                    else {
                        "name": nx[1],
                        "command": (nx[2].get("command") or "")[:300],
                        "timeout": nx[2].get("timeout"),
                    },
                }
            )
            + "\n"
        )
out.close()
tot = sum(k.values())
print(
    "timed-out bounded foreground wait slices:",
    tot,
    "in",
    len(per_agent),
    "agent files",
)
for a, b in k.most_common():
    print("  %4d  %4.0f%%  %s" % (b, 100.0 * b / max(tot, 1), a))
# per agent: did the agent EVER escalate after a timed-out slice?
esc = sum(1 for v in per_agent.values() if any(x.startswith("ESCALATED") for x in v))
print(
    "agents that escalated at least once after a timed-out slice: %d of %d"
    % (esc, len(per_agent))
)
