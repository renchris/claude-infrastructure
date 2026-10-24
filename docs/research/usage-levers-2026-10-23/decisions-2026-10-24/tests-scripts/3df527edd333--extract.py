#!/usr/bin/env python3
"""For each sampled call, write cases/NN.md: brief excerpt, the last turns before the call, the
call, and (separately, for grading only) what really happened next. Read-only on transcripts.
Usage: python3 -I extract.py <sample.json> <outdir>"""

import json, os, re, sys, subprocess
from datetime import datetime

S = json.load(open(sys.argv[1]))
OUT = sys.argv[2]
os.makedirs(OUT, exist_ok=True)


def T(s):
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except Exception:
        return None


def txt(c):
    if isinstance(c, str):
        return c
    if isinstance(c, list):
        return "\n".join(
            x.get("text", "")
            if isinstance(x, dict) and x.get("type") == "text"
            else (json.dumps(x)[:300] if not isinstance(x, str) else x)
            for x in c
        )
    return json.dumps(c)


def goal_live(parent, t):
    try:
        out = subprocess.run(
            ["/usr/bin/grep", "-a", "goal_status", parent],
            capture_output=True,
            timeout=60,
        ).stdout.decode("utf-8", "replace")
    except Exception:
        return None, ""
    st, cond = False, ""
    ev = []
    for line in out.splitlines():
        try:
            d = json.loads(line)
        except Exception:
            continue
        a = d.get("attachment") or {}
        if d.get("type") != "attachment" or a.get("type") != "goal_status":
            continue
        te = T(d.get("timestamp") or "")
        if te is not None:
            ev.append(
                (
                    te,
                    (a.get("met") is False) and not a.get("failed"),
                    str(a.get("condition") or "")[:100],
                )
            )
    for te, lv, c in sorted(ev):
        if te <= t:
            st, cond = lv, c
    return st, cond


summary = []
for n, r in enumerate(S, 1):
    f = r["file"]
    ev = []  # (kind, ts, payload)
    for line in open(f, errors="replace"):
        try:
            d = json.loads(line)
        except Exception:
            continue
        m = d.get("message") if isinstance(d.get("message"), dict) else {}
        ts = d.get("timestamp")
        if d.get("type") == "assistant":
            for c in m.get("content") or []:
                if not isinstance(c, dict):
                    continue
                if c.get("type") == "text" and c.get("text", "").strip():
                    ev.append(("A-text", ts, c["text"]))
                elif c.get("type") == "tool_use":
                    ev.append(
                        (
                            "A-tool",
                            ts,
                            {
                                "id": c.get("id"),
                                "name": c.get("name"),
                                "input": c.get("input"),
                            },
                        )
                    )
        elif d.get("type") == "user":
            cont = m.get("content")
            if isinstance(cont, list) and any(
                isinstance(x, dict) and x.get("type") == "tool_result" for x in cont
            ):
                for x in cont:
                    if isinstance(x, dict) and x.get("type") == "tool_result":
                        ev.append(
                            (
                                "U-result",
                                ts,
                                {
                                    "id": x.get("tool_use_id"),
                                    "content": txt(x.get("content")),
                                    "is_error": x.get("is_error"),
                                },
                            )
                        )
            else:
                ev.append(("U-text", ts, txt(cont)))
    brief = next((p for k, _, p in ev if k == "U-text"), "")
    idx = next(
        (i for i, e in enumerate(ev) if e[0] == "A-tool" and e[2]["id"] == r["id"]),
        None,
    )
    if idx is None:
        print(n, "call not found", r["id"], f)
        continue
    parent = re.sub(r"/subagents/.*$", ".jsonl", f)
    gl, gcond = goal_live(parent, r["t"])
    call = ev[idx][2]
    # last 8 events before the call
    pre = ev[max(1, idx - 8) : idx]
    post = ev[idx + 1 : idx + 9]
    has_pre = ("270 seconds" in brief) or ("270 s" in brief) or ("in slices" in brief)
    L = []
    L.append(
        "# Case %02d  %s  acct=%s  agent=%s"
        % (n, r["id"], r["acct"], f.rsplit("/", 1)[-1])
    )
    L.append("file: %s" % f)
    L.append(
        "parent live /goal at call: %s %s" % (gl, ("(" + gcond + ")") if gl else "")
    )
    L.append(
        "brief carries the 270 s slice preamble: %s ; brief chars %d ; event index %d of %d"
        % (has_pre, len(brief), idx, len(ev))
    )
    L.append("\n## Brief excerpt (task part; the first 300 and the last 1500 chars)\n")
    L.append(
        brief[:300]
        + ("\n[...]\n" + brief[-1500:] if len(brief) > 1800 else brief[300:])
    )
    L.append("\n## Last turns before the call\n")
    for k, ts, p in pre:
        if k == "A-tool":
            L.append("[%s] %s %s" % (k, p["name"], json.dumps(p["input"])[:700]))
        elif k == "U-result":
            L.append("[%s] %s" % (k, p["content"][:500].replace("\n", "\\n")))
        else:
            L.append("[%s] %s" % (k, str(p)[:700].replace("\n", "\\n")))
    L.append("\n## THE CALL (would be denied)\n")
    L.append(json.dumps(call["input"], indent=1))
    L.append(
        "\n## GRADING ONLY: what really happened (runtime %.0f s, rebuilt %s, ctx %s)\n"
        % (r["rt"] or -1, r["reb"], r["ctx"])
    )
    for k, ts, p in post:
        if k == "A-tool":
            L.append("[%s] %s %s" % (k, p["name"], json.dumps(p["input"])[:400]))
        elif k == "U-result":
            L.append("[%s] %s" % (k, p["content"][:300].replace("\n", "\\n")))
        else:
            L.append("[%s] %s" % (k, str(p)[:300].replace("\n", "\\n")))
    open(os.path.join(OUT, "%02d.md" % n), "w").write("\n".join(L) + "\n")
    summary.append(
        {
            "n": n,
            "id": r["id"],
            "acct": r["acct"],
            "file": f,
            "goal_live": gl,
            "preamble": has_pre,
            "to": call["input"].get("timeout"),
            "rt": r["rt"],
            "reb": r["reb"],
            "loop": (
                re.search(r"(while|until|for)\s", call["input"].get("command", ""))
                or [None, "?"]
            )[1]
            if re.search(r"(while|until|for)\s", call["input"].get("command", ""))
            else "?",
        }
    )
json.dump(summary, open(os.path.join(OUT, "summary.json"), "w"), indent=1)
for s in summary:
    print(
        s["n"],
        s["acct"],
        "goal",
        s["goal_live"],
        "pre",
        s["preamble"],
        "to",
        s["to"],
        "rt %.0f" % (s["rt"] or -1),
        "reb",
        s["reb"],
        s["loop"],
    )
