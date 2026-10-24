#!/usr/bin/env python3
"""Static classifier for agent() calls in a Workflow script: the logic a PreToolUse(Workflow) hook
would run. A character-level JS masker blanks string literals, template-literal text and comments
(keeping ${...} expressions as code, nested to any depth), then finds `agent(` at an identifier
boundary (not `.agent(`, not `subagent(`), extracts the balanced argument text and classifies:
  set           an `agentType` key at depth 1 of the options object literal
  spread_set    no literal key, but a spread `...X` whose `const X = {...}` definition mentions agentType
  indeterminate options passed as an identifier/expression, or a spread of an unknown X
  missing       one argument, or an object literal with neither agentType nor a spread
Marker: a comment containing `needs-default` on the call's line or the line above exempts it.
Library: classify(src) -> list of dicts. CLI: agentcalls.py <file.js>"""

import re, sys, json


def mask(src):
    """Return (masked, comments). masked has the same length as src; string/template text and
    comments become spaces (newlines kept); string literals keep a '"' at each end."""
    n = len(src)
    out = list(src)
    comments = []
    i = 0
    # stack of contexts: 'code' (with brace depth) or 'tpl'
    stack = [["code", 0]]

    def blank(a, b):
        for k in range(a, min(b, n)):
            if out[k] != "\n":
                out[k] = " "

    while i < n:
        ctx = stack[-1]
        c = src[i]
        if ctx[0] == "tpl":
            if c == "\\":
                blank(i, i + 2)
                i += 2
                continue
            if c == "`":
                out[i] = '"'
                stack.pop()
                i += 1
                continue
            if c == "$" and i + 1 < n and src[i + 1] == "{":
                blank(i, i + 2)
                stack.append(["code", 0])
                i += 2
                continue
            blank(i, i + 1)
            i += 1
            continue
        # code context
        if c == "/" and i + 1 < n and src[i + 1] == "/":
            j = src.find("\n", i)
            j = n if j < 0 else j
            comments.append((i, src[i:j]))
            blank(i, j)
            i = j
            continue
        if c == "/" and i + 1 < n and src[i + 1] == "*":
            j = src.find("*/", i + 2)
            j = n if j < 0 else j + 2
            comments.append((i, src[i:j]))
            blank(i, j)
            i = j
            continue
        if c in ('"', "'"):
            j = i + 1
            while j < n and src[j] != c and src[j] != "\n":
                if src[j] == "\\":
                    j += 1
                j += 1
            blank(i, j + 1)
            out[i] = '"'
            if j < n:
                out[j] = '"'
            i = j + 1
            continue
        if c == "`":
            out[i] = '"'
            stack.append(["tpl"])
            i += 1
            continue
        if c == "{":
            ctx[1] += 1
        elif c == "}":
            if ctx[1] == 0 and len(stack) > 1:
                # end of a ${...} expression inside a template
                out[i] = " "
                stack.pop()
                i += 1
                continue
            ctx[1] -= 1
        i += 1
    return "".join(out), comments


def split_top(s):
    parts, d, cur = [], 0, []
    for ch in s:
        if ch in "([{":
            d += 1
        elif ch in ")]}":
            d -= 1
        if ch == "," and d == 0:
            parts.append("".join(cur))
            cur = []
        else:
            cur.append(ch)
    parts.append("".join(cur))
    return parts


def classify(src):
    m, comments = mask(src)
    marker_lines = set()
    for pos, txt in comments:
        if "needs-default" in txt:
            ln = src.count("\n", 0, pos)
            marker_lines.add(ln)
            marker_lines.add(ln + 1)
    defs_at = set()
    for dm in re.finditer(r"(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*\{", m):
        k = dm.end()
        d = 1
        while k < len(m) and d:
            if m[k] in "([{":
                d += 1
            elif m[k] in ")]}":
                d -= 1
            k += 1
        if re.search(r"(?<![\w$])agentType(?![\w$])", m[dm.end() : k]):
            defs_at.add(dm.group(1))
    calls = []
    for mm in re.finditer(r"(?<![\w$.])agent\s*\(", m):
        pre = m[max(0, mm.start() - 12) : mm.start()]
        if re.search(r"function\s*$", pre):
            continue
        start = mm.end()
        d = 1
        k = start
        while k < len(m) and d:
            if m[k] in "([{":
                d += 1
            elif m[k] in ")]}":
                d -= 1
            k += 1
        args = m[start : k - 1]
        parts = split_top(args)
        line = src.count("\n", 0, mm.start())
        marked = line in marker_lines
        spreads = []
        if len(parts) < 2 or not parts[1].strip():
            verdict = "missing"
        else:
            opt = parts[1].strip()
            if opt.startswith("{"):
                body = opt[1:-1] if opt.endswith("}") else opt[1:]
                keys = []
                for p in split_top(body):
                    p = p.strip()
                    if p.startswith("..."):
                        spreads.append(p[3:].strip())
                    else:
                        km = re.match(r"\"?([A-Za-z_$][\w$]*)\"?\s*(?::|$|\()", p)
                        if km:
                            keys.append(km.group(1))
                if "agentType" in keys:
                    verdict = "set"
                elif spreads:
                    verdict = (
                        "spread_set"
                        if any(s in defs_at for s in spreads)
                        else "indeterminate"
                    )
                else:
                    verdict = "missing"
            else:
                verdict = "indeterminate"
        calls.append(
            {
                "line": line + 1,
                "verdict": verdict,
                "marked": marked,
                "spreads": spreads,
                "args_head": " ".join(args.split())[:140],
            }
        )
    return calls


if __name__ == "__main__":
    src = open(sys.argv[1], errors="replace").read()
    for c in classify(src):
        print(json.dumps(c))
