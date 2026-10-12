"""Attribute an eslogger exec trace: who is spawning ~30k processes/min.

Usage: python3 -I o5-attribute.py <trace.jsonl>
Groups every exec by (a) cwd root, (b) target binary, (c) the script it runs (first arg that looks
like a file path to a script/hook), (d) session id with its most common cwd.
"""

import collections
import json
import os
import sys

path = sys.argv[1]
n = 0
t0 = t1 = None
by_cwd, by_bin, by_script, by_sess, sess_cwd = (collections.Counter() for _ in range(5))
by_sess_bin = collections.defaultdict(collections.Counter)
home = os.path.expanduser("~")


def cwd_root(p):
    if not p:
        return "?"
    p = p.replace(home, "~")
    parts = p.split("/")
    if p.startswith("~/Development/.worktrees/"):
        return "/".join(parts[:5])
    if p.startswith("~/Development/"):
        return "/".join(parts[:3])
    if p.startswith("~/.claude"):
        return "/".join(parts[:2])
    return "/".join(parts[:3]) or "/"


for line in open(path, errors="replace"):
    try:
        d = json.loads(line)
    except ValueError:
        continue
    ex = d.get("event", {}).get("exec") or {}
    tgt = ex.get("target") or {}
    n += 1
    t = d.get("time")
    t0 = t0 or t
    t1 = t
    exe = (tgt.get("executable") or {}).get("path") or "?"
    b = os.path.basename(exe)
    by_bin[b] += 1
    cwd = (ex.get("cwd") or {}).get("path") or ""
    cr = cwd_root(cwd)
    by_cwd[cr] += 1
    script = None
    for a in (ex.get("args") or [])[1:4]:
        if (
            isinstance(a, str)
            and "/" in a
            and (a.endswith((".sh", ".py", ".bats")) or "/hooks/" in a or "/bin/" in a)
        ):
            script = a.replace(home, "~")
            break
    if script:
        by_script[script] += 1
    sid = tgt.get("session_id")
    by_sess[sid] += 1
    sess_cwd[(sid, cr)] += 1
    by_sess_bin[sid][b] += 1

print(f"events={n} window={t0} .. {t1}")


def top(title, c, k=20):
    print(f"\n== {title} (top {k}) ==")
    for key, v in c.most_common(k):
        print(f"{v:7d} {100 * v / max(n, 1):5.1f}%  {key}")


top("cwd root", by_cwd)
top("target binary", by_bin)
top("script in args", by_script, 30)
print("\n== session (top 15): count, main cwd, top binaries ==")
for sid, v in by_sess.most_common(15):
    cw = max(
        ((c, cr) for (s, cr), c in sess_cwd.items() if s == sid), default=(0, "?")
    )[1]
    bins = ", ".join(f"{b}:{c}" for b, c in by_sess_bin[sid].most_common(4))
    print(f"{v:7d} {100 * v / max(n, 1):5.1f}%  sid={sid} cwd={cw}  [{bins}]")
