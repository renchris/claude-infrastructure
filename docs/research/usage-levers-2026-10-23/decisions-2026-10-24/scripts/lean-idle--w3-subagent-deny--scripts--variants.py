#!/usr/bin/env python3
"""Deny-cost variants over joined.json (written by analyze.py). Usage: python3 -I variants.py <joined.json> <days>"""

import json
import math
import re
import sys
from collections import Counter, defaultdict

J = json.load(open(sys.argv[1]))
wk = 7.0 / float(sys.argv[2])
READ = (0.0057, 0.0076)
WRITE, OUT = 0.245, 0.404
K = dict(low=dict(r=READ[0], w=500, o=60), high=dict(r=READ[1], w=1234, o=300))
TO_RX = re.compile(r"(?:^|[;&|\s(])g?timeout\s+(?:-\S+\s+)*([0-9]+)([sm]?)\s")


def selfbound(cmd):
    """True if every `timeout N` in the command is < 300 s and there is at least one."""
    ns = []
    for m in TO_RX.finditer(cmd):
        n = int(m.group(1)) * (60 if m.group(2) == "m" else 1)
        ns.append(n)
    return bool(ns) and max(ns) < 300


def rc(ctx, k):
    return (ctx * k["r"] + k["w"] * WRITE + k["o"] * OUT) / 1e6


def net(rs, k, comply=1.0, learn=False, short_extra=2):
    seen = set()
    s = c = wrong = 0.0
    nden = 0
    for r in sorted(rs, key=lambda r: r["t"]):
        if r["rt"] is None:
            continue
        kk = math.ceil(r["rt"] / 270.0) if r["rt"] > 270 else 1
        if r["why"] == "poll-loop":
            polls = kk  # re-issue IS the first slice
        else:
            polls = 1 + kk  # re-issue as bg + kk poll slices
        if r["rt"] <= 270:
            polls = short_extra if r["why"] != "poll-loop" else 1
        deny = 1
        if learn and r["aid"] in seen:
            deny = (
                0  # agent already told: skips the denied attempt, pays only the polls
            )
            polls = polls - 1 if r["why"] != "poll-loop" else polls - 1
            polls = max(polls, 0) if r["rt"] <= 270 else max(polls, 1)
        seen.add(r["aid"])
        nden += deny
        cost = polls * rc(r["ctx"], k)
        c += cost
        if r["rt"] <= 270:
            wrong += cost
        if r["rebuilt"]:
            s += comply * min(r["ncc"], r["ctx"]) * (WRITE - k["r"]) / 1e6
    return dict(
        net=round((s - c) * wk, 2),
        save=round(s * wk, 2),
        cost=round(c * wk, 2),
        wrong=round(wrong * wk, 2),
        denies_wk=round(nden * wk),
    )


V = {
    "narrow (as shipped)": [r for r in J if r["narrow"]],
    "narrow minus self-bounded (timeout N<300 in cmd)": [
        r for r in J if r["narrow"] and not selfbound(r["cmd"])
    ],
    "poll-loop only": [r for r in J if r["why"] == "poll-loop"],
    "poll-loop + long-sleep": [r for r in J if r["why"] in ("poll-loop", "long-sleep")],
    "broad (all timeout>270000)": J,
}
for name, rs in V.items():
    res = [r for r in rs if r["rt"] is not None]
    short = sum(1 for r in res if r["rt"] <= 270)
    print(
        "## %s: calls/wk %.0f, false-deny share %.3f, rebuilds/wk %.1f, agents %d"
        % (
            name,
            len(rs) * wk,
            short / max(1, len(res)),
            sum(r["rebuilt"] for r in res) * wk,
            len(set(r["aid"] for r in rs)),
        )
    )
    for kn, k in K.items():
        for comply in (1.0, 0.7, 0.5):
            a = net(rs, k, comply)
            b = net(rs, k, comply, learn=True)
            c1 = net(rs, k, comply, short_extra=1)
            print(
                "   %-4s comply %.1f  per-call deny: %s | learns after 1st deny/agent: %s | short re-run fg (1 extra): net %s"
                % (kn, comply, a, b, c1["net"])
            )
# self-bounded share among narrow, by class
nb = [r for r in J if r["narrow"]]
print(
    "self-bounded among narrow by class:",
    Counter((r["why"], selfbound(r["cmd"])) for r in nb),
)
print(
    "self-bounded narrow that rebuilt:",
    sum(1 for r in nb if selfbound(r["cmd"]) and r["rebuilt"]),
)
per_agent = Counter(r["aid"] for r in nb)
vals = sorted(per_agent.values())
print(
    "narrow calls per agent: agents %d, median %d, p90 %d, max %d"
    % (len(vals), vals[len(vals) // 2], vals[int(len(vals) * 0.9)], vals[-1])
)
