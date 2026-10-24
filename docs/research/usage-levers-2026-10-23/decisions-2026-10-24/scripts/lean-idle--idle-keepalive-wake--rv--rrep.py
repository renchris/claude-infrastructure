#!/usr/bin/env python3
# Reviewer replay: price the keepalive variants over G.json (rsim.py). Independent of sim.py.
# usage: python3 -I rrep.py <dir> [term_mode=low|high]
import collections
import json
import os
import sys

D = sys.argv[1]
TERM = sys.argv[2] if len(sys.argv) > 2 else "low"
S, E = 1791655200.0, 1792864800.0
WK = 0.5
A = ["next", "next2", "next3", "next4"]
W_DEF, O = 0.245, 0.404
WAKE, TTL, TURN, RECAP_AT = 3300.0, 3600.0, 30.0, 190.0
G = json.load(open(os.path.join(D, "G.json")))
PROF = {
    # measured over job:watch:failed turns (rturn.py): nreq, cw, out, own growth (excl. next opener)
    "min": dict(nreq=1, cw=1000, out=300, grow=1000),
    "med": dict(nreq=3, cw=1519, out=522, grow=1748),
    "med_g": dict(nreq=3, cw=1519, out=522, grow=2664),
    "mean": dict(nreq=4.21, cw=6803, out=1115, grow=3537),
}


def wake_cost(g, r, p, prec, W, later=True):
    ctx = g["ctx"]
    c = (p["nreq"] + prec) * ctx * r + p["cw"] * W + p["out"] * O
    if later and not g["term"]:
        c += p["grow"] * g["later"] * r
    return c / 1e6


def end_eff(g):
    e = g["end"]
    if g["exit"]:
        e = min(e, g["exit"])
    if g["term"] and g["end_kind"] == "censored" and not g["alive"]:
        if TERM == "low":
            e = max(g["stop"], min(e, g["mt"]))
    return e


def run(policy, r, pname, prec=None, s_chain=0.43, W=W_DEF, sel=None, first_kill=True):
    """policy: literal (as coded: first timer dies on any write; chain timers survive w.p. s_chain)
    chain (re-arm every 3330 s, no kill), once (one wake per gap)."""
    p = PROF[pname]
    if prec is None:
        prec = 0.0 if pname == "min" else 0.57
    acc = {a: collections.Counter() for a in A}
    for g in G:
        if sel and not sel(g):
            continue
        C = acc[g["acct"]]
        ee = end_eff(g)
        w1 = g["stop"] + WAKE
        if w1 >= ee:
            continue
        if policy == "literal" and first_kill and g["kill"] is not None:
            continue
        ws = [w1]
        if policy != "once":
            while ws[-1] + TURN + WAKE < ee:
                ws.append(ws[-1] + TURN + WAKE)
        if policy == "literal":
            pw = [s_chain**k for k in range(len(ws))]
        else:
            pw = [1.0] * len(ws)
        nw = sum(pw)
        cost = nw * wake_cost(g, r, p, prec, W)
        ben = 0.0
        if g["reb"] and not g["term"] and not g["exit"]:
            K = len(ws)
            # warm at end if the chain is alive at the last wake before the end, and that wake is within TTL
            pr = pw[-1] if (g["end"] - (ws[-1] + TURN)) < TTL else 0.0
            if (
                policy == "literal"
                and K >= 2
                and g["end"] < ws[-2] + TURN + RECAP_AT + TTL
            ):
                pr += pw[-2] * (
                    1 - s_chain
                )  # chain died at the last wake, but its recap kept the cache warm
            ben = pr * g["saved"] * (W - r) / 1e6
            C["rescued"] += pr
        C["wakes"] += nw
        C["cost"] += cost
        C["ben"] += ben
        C["gaps"] += 1
        if g["term"]:
            C["term_cost"] += cost
    res = {a: {k: v * WK for k, v in acc[a].items()} for a in A}
    for a in A:
        res[a]["net"] = res[a].get("ben", 0) - res[a].get("cost", 0)
    res["all"] = {
        k: sum(res[a].get(k, 0) for a in A) for k in set().union(*[res[a] for a in A])
    }
    return res


def line(lab, res):
    T = res["all"]
    return (
        "%-52s | %s | %6.2f | wakes/wk %6.1f rescued/wk %5.1f cost %5.2f ben %5.2f term_cost %5.2f"
        % (
            lab,
            " ".join("%6.2f" % res[a]["net"] for a in A),
            T["net"],
            T.get("wakes", 0),
            T.get("rescued", 0),
            T.get("cost", 0),
            T.get("ben", 0),
            T.get("term_cost", 0),
        )
    )


if __name__ == "__main__":
    print(
        "TERM",
        TERM,
        "| per-account net pp/week:",
        " ".join("%6s" % a for a in A),
        "| all",
    )
    busy = lambda g: g["busy"]
    for pol, sel, lab in (
        ("literal", None, "AS CODED"),
        ("once", None, "once, fixed check"),
        ("chain", None, "chain, fixed check"),
        ("chain", busy, "R2 busy-scoped chain"),
    ):
        for pname in ("min", "med", "med_g", "mean"):
            for rn, r in (("low", 0.0057), ("high", 0.0076)):
                print(line("%s %s %s" % (lab, pname, rn), run(pol, r, pname, sel=sel)))
