#!/usr/bin/env python3
# For subagent busts after a 5-60 min gap: what tool call preceded the gap, and what was the Bash TOOL's
# timeout parameter (not a shell `timeout N` in the command text)? Independent of cache-gapcause2.py.
import csv, collections, json, os, re
from datetime import datetime

csv.field_size_limit(10**9)
H = os.path.expanduser("~")
ROOT = {
    "next": H + "/.claude/projects",
    "next2": H + "/.claude-secondary/projects",
    "next3": H + "/.claude-tertiary/projects",
    "next4": H + "/.claude-quaternary/projects",
}
T = lambda s: datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
U = {}
for a in ROOT:
    for r in csv.DictReader(open(f"/tmp/usage-audit/sk-cache-{a}.tsv"), delimiter="\t"):
        if r["mid"] not in U:
            U[r["mid"]] = r
TL = collections.defaultdict(list)
for r in U.values():
    if r["sub"] == "1":
        TL[r["rel"]].append(r)
targets = collections.defaultdict(list)  # (acct, rel) -> [(prev_mid, cc, gap)]
for rel, rs in TL.items():
    rs.sort(key=lambda r: r["ts"])
    for p, r in zip(rs, rs[1:]):
        pp = int(p["in"]) + int(p["cc"]) + int(p["cr"])
        gap = T(r["ts"]) - T(p["ts"])
        if (
            300 < gap <= 3600
            and pp >= 20000
            and int(r["cr"]) < 0.5 * pp
            and int(r["cc"]) >= 0.5 * pp
        ):
            targets[(p["acct"], rel)].append((p["mid"], int(r["cc"]), gap))
cls = collections.Counter()
clscc = collections.Counter()
tmo = collections.Counter()
for (a, rel), lst in targets.items():
    want = {m: (cc, g) for m, cc, g in lst}
    found = {}
    with open(os.path.join(ROOT[a], rel), errors="replace") as fh:
        for line in fh:
            if '"assistant"' not in line:
                continue
            try:
                d = json.loads(line)
            except Exception:
                continue
            m = d.get("message") or {}
            if m.get("id") in want:
                for c in m.get("content") or []:
                    if isinstance(c, dict) and c.get("type") == "tool_use":
                        found.setdefault(m["id"], []).append(c)
    for mid, (cc, g) in want.items():
        tus = found.get(mid, [])
        if not tus:
            k = "no tool_use (text/end of turn)"
        else:
            c = tus[-1]
            name = c.get("name")
            inp = c.get("input") or {}
            if name == "Bash":
                t = inp.get("timeout")
                bg = inp.get("run_in_background")
                cmd = inp.get("command") or ""
                poll = bool(
                    re.search(r"\b(until|while)\b", cmd)
                    and re.search(r"\bsleep\b", cmd)
                )
                tb = (
                    "bg"
                    if bg
                    else (
                        "none(default 120s)"
                        if t is None
                        else (">270s" if float(t) > 270000 else "<=270s")
                    )
                )
                tmo[tb] += 1
                k = f"Bash tool-timeout={tb} poll={poll}"
            else:
                k = f"tool {name}"
        cls[k] += 1
        clscc[k] += cc
print(
    f"subagent busts with 5-60 min gap: n={sum(cls.values())} cc={sum(clscc.values()) / 1e6:.1f}M"
)
for k, v in cls.most_common():
    print(f"   {v:4d} {clscc[k] / 1e6:6.1f}M  {k}")
print("Bash tool timeout parameter:", dict(tmo))
