#!/usr/bin/env python3
"""Join the hook replay (narrow verdicts) to transcript facts and price a DENY of each narrow call.
Usage: python3 -I analyze.py <out/bash.jsonl> <replay.jsonl> <days>"""

import json
import math
import statistics as S
import sys
from collections import Counter, defaultdict

SRC, REP, DAYS = sys.argv[1], sys.argv[2], float(sys.argv[3])
READ = (0.0057, 0.0076)
WRITE, OUT = 0.245, 0.404
# per extra request: cache write and output tokens. W measured: median/q3 next-request write after a
# compliant <=270 s poll (scan: 792 / 1234); O estimated (transcript output_tokens under-report).
LOW = dict(r=READ[0], w=500, o=60)
HIGH = dict(r=READ[1], w=1234, o=300)
SHORT = 270
U = {}
for l in open(SRC):
    r = json.loads(l)
    U.setdefault(r["id"], r)
V = {}
for l in open(REP):
    x = json.loads(l)
    V[x["tool_use_id"]] = x
rows = []
for tid, x in V.items():
    r = U[tid]
    r["narrow"], r["why"] = x["narrow"], x["why"]
    rows.append(r)
wk = 7.0 / DAYS


def rebuilt(r):
    return (
        "ncc" in r
        and r["ctx"] > 0
        and r["ncc"] >= 0.5 * r["ctx"]
        and r.get("gap", 0) > 300
    )


def extra_reqs(r):
    rt = r["rt"]
    if rt is None:
        return None
    return 1 + max(1, math.ceil(rt / 270.0))


def req_cost(ctx, k):
    return (ctx * k["r"] + k["w"] * WRITE + k["o"] * OUT) / 1e6


def price(r, k, comply=1.0):
    """net pp of denying r (positive = saving)."""
    n = extra_reqs(r)
    if n is None:
        return 0.0, 0.0, 0.0
    cost = n * req_cost(r["ctx"], k)
    save = 0.0
    if rebuilt(r):
        save = comply * min(r["ncc"], r["ctx"]) * (WRITE - k["r"]) / 1e6
    return save - cost, save, cost


def summarize(name, rs):
    res = [r for r in rs if r["rt"] is not None]
    short = [r for r in res if r["rt"] <= SHORT]
    lng = [r for r in res if r["rt"] > SHORT]
    reb = [r for r in res if rebuilt(r)]
    out = dict(
        name=name,
        calls=len(rs),
        resolved=len(res),
        no_result=len(rs) - len(res),
        finished_le_270=len(short),
        ran_gt_270=len(lng),
        rebuilt_after=len(reb),
        rebuild_Mtok=round(sum(min(r["ncc"], r["ctx"]) for r in reb) / 1e6, 2),
        false_deny_share=round(len(short) / len(res), 3) if res else None,
    )
    for tag, k in (("low_cost", LOW), ("high_cost", HIGH)):
        for comply in (1.0, 0.7, 0.5):
            tot = [price(r, k, comply) for r in res]
            net = sum(t[0] for t in tot) * wk
            out["net_pp_week_%s_c%.1f" % (tag, comply)] = round(net, 3)
        out["save_pp_week_%s" % tag] = round(sum(price(r, k)[1] for r in res) * wk, 3)
        out["cost_pp_week_%s" % tag] = round(sum(price(r, k)[2] for r in res) * wk, 3)
        out["wrong_cost_pp_week_%s" % tag] = round(
            sum(price(r, k)[2] for r in short) * wk, 4
        )
    out["extra_requests_per_week"] = round(sum(extra_reqs(r) for r in res) * wk, 1)
    out["mean_ctx_k"] = round(S.mean(r["ctx"] for r in res) / 1e3, 1) if res else None
    return out


narrow = [r for r in rows if r["narrow"]]
broad = rows
print(json.dumps(summarize("broad (timeout>270000, all)", broad)))
print(json.dumps(summarize("NARROW (would-deny)", narrow)))
print(
    json.dumps(
        summarize(
            "broad minus narrow (not denied)", [r for r in rows if not r["narrow"]]
        )
    )
)
for w in sorted(set(r["why"] for r in narrow)):
    print(json.dumps(summarize("narrow/" + w, [r for r in narrow if r["why"] == w])))
# runtime distribution of narrow calls
rt = [r["rt"] for r in narrow if r["rt"] is not None]
print("narrow runtime deciles s:", [round(x) for x in S.quantiles(rt, n=10)])
print("narrow timeout values:", Counter(r["to"] for r in narrow).most_common(6))
print("narrow by acct (first copy):", Counter(r["acct"] for r in narrow))
# share of all subagent fg-Bash-after rebuilds the narrow rule could reach
allreb = [r for r in rows if rebuilt(r)]
print(
    "rebuilds after broad calls: %d (%.1fM); narrow reaches %d (%.1fM)"
    % (
        len(allreb),
        sum(min(r["ncc"], r["ctx"]) for r in allreb) / 1e6,
        sum(1 for r in allreb if r["narrow"]),
        sum(min(r["ncc"], r["ctx"]) for r in allreb if r["narrow"]) / 1e6,
    )
)
# rebuild rate by runtime band, narrow
for lo, hi in ((0, 270), (270, 300), (300, 360), (360, 1e9)):
    s = [r for r in narrow if r["rt"] is not None and lo < r["rt"] <= hi]
    print(
        "narrow rt %s-%s: n=%d rebuilt=%d"
        % (lo, hi, len(s), sum(rebuilt(r) for r in s))
    )
json.dump(
    [
        dict(
            id=r["id"],
            acct=r["acct"],
            aid=r["aid"],
            t=r["t"],
            to=r["to"],
            why=r["why"],
            narrow=r["narrow"],
            rt=r["rt"],
            ctx=r["ctx"],
            ncc=r.get("ncc"),
            gap=r.get("gap"),
            rebuilt=rebuilt(r),
            cmd=r["cmd"][:300],
        )
        for r in rows
    ],
    open("/tmp/lean-idle/w3-subagent-deny/joined.json", "w"),
)
