"""A9: UserPromptSubmit chain wall-time proxy from transcript timestamps (read-only).

Usage: python3 -I a9-ups-latency.py <file-list> <since-iso>

For each UserPromptSubmit hook_additional_context / hook_cancelled / hook_system_message record,
delta = its timestamp - the timestamp of the most recent prompt record before it (a string-content
user record, or a queued_command attachment). CC writes these after the prompt's hooks settle, so
the delta approximates how long the prompt waited on its UserPromptSubmit chain. Only prompts where
some UPS hook printed or was cancelled are measurable (KNOWN BIAS). One sample per prompt (max).
"""

import json
import sys
from datetime import datetime

flist, since = sys.argv[1], sys.argv[2]


def t(s):
    return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()


vals = {"machine": [], "human": []}
for path in open(flist):
    path = path.strip()
    try:
        fh = open(path, errors="replace")
    except OSError:
        continue
    last, kind, best = None, "human", None
    with fh:
        for ln in fh:
            if not (
                '"type":"user"' in ln
                or '"queued_command"' in ln
                or '"UserPromptSubmit"' in ln
            ):
                continue
            try:
                r = json.loads(ln)
            except ValueError:
                continue
            ts = r.get("timestamp") or ""
            if ts < since:
                continue
            a = r.get("attachment") if isinstance(r.get("attachment"), dict) else {}
            newp = None
            if r.get("type") == "user" and not r.get("isMeta"):
                c = (r.get("message") or {}).get("content")
                if isinstance(c, str):
                    newp = (
                        "machine"
                        if c.lstrip().startswith("<")
                        or c.startswith("Another Claude session")
                        else "human"
                    )
            elif a.get("type") == "queued_command":
                p = a.get("prompt")
                p = p if isinstance(p, str) else ""
                newp = "machine" if p.lstrip().startswith("<") else "human"
            if newp:
                if best is not None:
                    vals[kind].append(best)
                last, kind, best = t(ts), newp, None
                continue
            if a.get("hookEvent") == "UserPromptSubmit" and last is not None:
                d = (t(ts) - last) * 1000
                if 0 <= d < 120000:
                    best = d if best is None else max(best, d)
    if best is not None:
        vals[kind].append(best)


def q(xs):
    if not xs:
        return "n=0"
    xs = sorted(xs)

    def p(v):
        return int(xs[min(len(xs) - 1, int(round(v / 100.0 * (len(xs) - 1))))])

    return f"n={len(xs)} p50={p(50)} p75={p(75)} p90={p(90)} p95={p(95)} p99={p(99)} max={int(xs[-1])}"


for k, v in vals.items():
    print(f"UPS chain proxy ms, {k} prompts: {q(v)}")
print(f"all: {q(vals['machine'] + vals['human'])}")
