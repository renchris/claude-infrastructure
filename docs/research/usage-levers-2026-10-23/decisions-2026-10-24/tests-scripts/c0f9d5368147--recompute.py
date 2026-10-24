#!/usr/bin/env python3
# Recompute net pp/week for today's code (as coded, chain survival 0.89) and the busy-scoped
# redesign (R2 busy2, R4 busy2 & no model watcher) with the wake cost MEASURED per context band
# from turns.jsonl, using the numbers reviewer's replay engine (rv/rrep.py) unchanged otherwise.
# usage: python3 -I recompute.py <dir>
import importlib.util
import json
import os
import statistics as st
import sys

D = sys.argv[1]
RV = "/tmp/lean-idle/idle-keepalive-wake/rv"
T = [json.loads(l) for l in open(os.path.join(D, "turns.jsonl"))]
BANDS = [
    (0, 150e3, "<150k"),
    (150e3, 200e3, "150-200k"),
    (200e3, 300e3, "200-300k"),
    (300e3, 500e3, "300-500k"),
    (500e3, 1e12, ">=500k"),
]
NN = {"watch_timeout", "monitor_expired", "watch_timeout_guess"}


def warm(t):
    return (
        t["gap"] is not None
        and 60 <= t["gap"] < 3500
        and not t["reb"]
        and not t["op_during"]
        and t["ctx1"] > 0
    )


def nothing(t):
    return t["res"] in ("noop", "look")


POPS = {
    "nonews_nothing": lambda t: t["kind"] in NN and nothing(t),
    "busy_nothing": lambda t: (
        t["busy"] and nothing(t) and t["kind"] not in ("operator", "sdk", "other")
    ),
    "goal_nothing": lambda t: t["kind"] == "goal_checkin" and nothing(t),
    "nonews_all": lambda t: t["kind"] in NN,
    "goal_all": lambda t: t["kind"] == "goal_checkin",
    "busy_all": lambda t: t["busy"] and t["kind"] not in ("operator", "sdk", "other"),
    "monitor_event_nothing": lambda t: t["kind"] == "monitor_event" and nothing(t),
}


def prof(L, how):
    agg = st.mean if how == "mean" else st.median
    g = [t["grow"] for t in L if t["grow"] is not None]
    return dict(
        nreq=agg([t["cr"] / t["ctx1"] for t in L]),
        cw=agg([t["cc"] for t in L]),
        out=agg([t["out"] for t in L]),
        grow=max(0.0, agg(g)),
        n=len(L),
    )


PB = {}
for pn, sel in POPS.items():
    for how in ("mean", "median"):
        PB[(pn, how)] = {}
        for lo, hi, b in BANDS:
            L = [t for t in T if warm(t) and sel(t) and lo <= t["ctx1"] < hi]
            if len(L) < 15:  # thin band: borrow the pooled >=150k profile
                L = [t for t in T if warm(t) and sel(t) and t["ctx1"] >= 150e3]
            PB[(pn, how)][b] = prof(L, how)

spec = importlib.util.spec_from_file_location("rrep", os.path.join(RV, "rrep.py"))
sys.argv = ["rrep.py", RV, "low"]
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
m.G[:] = json.load(open(os.path.join(RV, "G2.json")))
orig_wake_cost = m.wake_cost
CUR = {"pb": None}


def band(c):
    for lo, hi, b in BANDS:
        if lo <= c < hi:
            return b


def wake_cost_banded(g, r, p, prec, W, later=True):
    if CUR["pb"] is None:
        return orig_wake_cost(g, r, p, prec, W, later)
    return orig_wake_cost(g, r, CUR["pb"][band(g["ctx"])], prec, W, later)


m.wake_cost = wake_cost_banded

print("measured band profiles (reads in context units, cw, out, own growth):")
for k, v in PB.items():
    print(
        " ",
        k,
        {
            b: "n=%d r=%.2f cw=%.0f out=%.0f g=%.0f"
            % (x["n"], x["nreq"], x["cw"], x["out"], x["grow"])
            for b, x in v.items()
        },
    )

busy2 = lambda g: g["busy2"]
r4 = lambda g: g["busy2"] and not g["watch2"]
print(
    "\nengine check (reviewer 'med' profile, no banding; expect as-coded 3.79/2.67 low/high, R2 busy2 5.07/4.23):"
)
for lab, pol, sel, kw in (
    ("AS CODED s=0.89", "literal", None, dict(s_chain=0.89)),
    ("R2 busy2", "chain", busy2, {}),
):
    for rn, r in (("low", 0.0057), ("high", 0.0076)):
        print(m.line("  %s med %s" % (lab, rn), m.run(pol, r, "med", sel=sel, **kw)))

print(
    "\nmeasured banded profiles; read weights low 0.0057 / mid 0.0067 / high 0.0076; W=0.245; prec 0.57"
)
for lab, pol, sel, kw, pops in (
    (
        "AS CODED s=0.89",
        "literal",
        None,
        dict(s_chain=0.89),
        ("nonews_nothing", "nonews_all", "monitor_event_nothing"),
    ),
    (
        "R2 busy2",
        "chain",
        busy2,
        {},
        ("busy_nothing", "goal_nothing", "goal_all", "busy_all", "monitor_event_nothing"),
    ),
    (
        "R4 busy2+no watcher",
        "chain",
        r4,
        {},
        ("busy_nothing", "goal_nothing", "goal_all", "busy_all"),
    ),
):
    for pn in pops:
        for how in ("median", "mean"):
            CUR["pb"] = PB[(pn, how)]
            for rn, r in (("low", 0.0057), ("mid", 0.0067), ("high", 0.0076)):
                print(
                    m.line(
                        "%s | %s %s %s" % (lab, pn, how, rn),
                        m.run(pol, r, "med", sel=sel, **kw),
                    )
                )
    CUR["pb"] = None

print(
    "\n1h-write premium sensitivity (W=0.3325 on both the wake's writes and the rescued rebuild), mean profiles, mid reads"
)
for lab, pol, sel, kw, pn in (
    ("AS CODED s=0.89", "literal", None, dict(s_chain=0.89), "nonews_nothing"),
    ("R2 busy2", "chain", busy2, {}, "busy_nothing"),
    ("R4 busy2+no watcher", "chain", r4, {}, "busy_nothing"),
):
    for W in (0.245, 0.2866, 0.3325):
        CUR["pb"] = PB[(pn, "mean")]
        print(
            m.line(
                "%s | %s mean mid W=%.4f" % (lab, pn, W),
                m.run(pol, 0.0067, "med", sel=sel, W=W, **kw),
            )
        )
CUR["pb"] = None
