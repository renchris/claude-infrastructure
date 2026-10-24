#!/usr/bin/env python3
# Wake-turn cost distribution from turns.jsonl (turns.py).
# usage: python3 -I wakestats.py <dir> [read_w]
# Population: interactive main sessions, 2026-10-10T18Z..10-24T18Z, turn opened by a machine wake
# (no operator prompt opened it and none was queued during it), cache warm (60 s <= gap < 3500 s and the
# first request did not rebuild). "nothing to do" = the turn made no state-changing tool call
# (res noop or look; see turns.py tool_class).
import collections
import json
import os
import statistics as st
import sys

D = sys.argv[1]
R = float(sys.argv[2]) if len(sys.argv) > 2 else 0.0067
WW, O = 0.245, 0.404
T = [json.loads(l) for l in open(os.path.join(D, "turns.jsonl"))]
MACH = {
    "watch_timeout",
    "watch_completed",
    "watch_failed",
    "mail_rewake",
    "goal_checkin",
    "monitor_expired",
    "monitor_event",
    "bash_completed",
    "bash_failed",
    "bash_killed",
    "workflow_completed",
    "agent_completed",
    "peer_msg",
    "cron",
    "notif_other",
    "watch_timeout_guess",
}
BANDS = [
    (0, 150e3, "<150k"),
    (150e3, 200e3, "150-200k"),
    (200e3, 300e3, "200-300k"),
    (300e3, 500e3, "300-500k"),
    (500e3, 1e9, ">=500k"),
]


def band(c):
    for lo, hi, n in BANDS:
        if lo <= c < hi:
            return n


def pp(t):
    return (t["cr"] * R + t["cc"] * WW + t["out"] * O) / 1e6


def q(xs, p):
    xs = sorted(xs)
    return xs[min(len(xs) - 1, int(p * len(xs)))] if xs else float("nan")


def warm(t):
    return t["gap"] is not None and 60 <= t["gap"] < 3500 and not t["reb"]


def summ(L, lab):
    if not L:
        print("%-44s n=0" % lab)
        return
    f = lambda k: [t[k] for t in L]
    P = [pp(t) for t in L]
    ov = [pp(t) - t["ctx1"] * R / 1e6 for t in L]  # beyond one context read
    print(
        "%-44s n=%5d | req med %d p90 %d mean %.2f 1req %.0f%% 3+ %.0f%% | out med %d p90 %d mean %d | cw med %d p90 %d mean %d"
        " | cr med %.0fk p90 %.0fk | cr/ctx med %.2f mean %.2f | pp med %.4f p90 %.4f mean %.4f | over1read med %.4f mean %.4f"
        " | stopfb %.0f%% | 1h-share of cw %.0f%%"
        % (
            lab,
            len(L),
            q(f("nreq"), 0.5),
            q(f("nreq"), 0.9),
            st.mean(f("nreq")),
            100 * sum(t["nreq"] == 1 for t in L) / len(L),
            100 * sum(t["nreq"] >= 3 for t in L) / len(L),
            q(f("out"), 0.5),
            q(f("out"), 0.9),
            st.mean(f("out")),
            q(f("cc"), 0.5),
            q(f("cc"), 0.9),
            st.mean(f("cc")),
            q(f("cr"), 0.5) / 1e3,
            q(f("cr"), 0.9) / 1e3,
            q([t["cr"] / t["ctx1"] for t in L], 0.5),
            st.mean([t["cr"] / t["ctx1"] for t in L]),
            q(P, 0.5),
            q(P, 0.9),
            st.mean(P),
            q(ov, 0.5),
            st.mean(ov),
            100 * sum(t["nstopfb"] > 0 for t in L) / len(L),
            100 * sum(t["cc1"] for t in L) / max(1, sum(t["cc"] for t in L)),
        )
    )


base = [t for t in T if t["kind"] in MACH and not t["op_during"] and t["ctx1"] > 0]
W_ = [t for t in base if warm(t)]
nothing = lambda t: t["res"] in ("noop", "look")
print("read weight %.4f, write %.3f, output %.3f pp/Mtok weekly" % (R, WW, O))
print(
    "machine-wake turns in window: %d; warm %d; cold/rebuild-first %d; <60 s gap %d"
    % (
        len(base),
        len(W_),
        sum(1 for t in base if t["gap"] is not None and t["gap"] >= 60 and not warm(t)),
        sum(1 for t in base if t["gap"] is not None and t["gap"] < 60),
    )
)
print(
    "\n== A. all machine wakes, warm, ctx >= 150k, 'nothing to do' (noop+look), by band"
)
A = [t for t in W_ if t["ctx1"] >= 150e3 and nothing(t)]
summ(A, "ALL >=150k nothing-to-do")
for lo, hi, n in BANDS:
    summ([t for t in W_ if lo <= t["ctx1"] < hi and nothing(t)], "  " + n)
print("\n== B. by wake kind, warm, ctx >= 150k, nothing-to-do")
for k in (
    "watch_timeout",
    "monitor_expired",
    "goal_checkin",
    "mail_rewake",
    "watch_completed",
    "monitor_event",
    "bash_completed",
    "peer_msg",
    "cron",
):
    summ([t for t in W_ if t["ctx1"] >= 150e3 and nothing(t) and t["kind"] == k], k)
print("\n== C. by wake kind, warm, ctx >= 150k, ALL results (incl. act)")
for k in ("watch_timeout", "monitor_expired", "goal_checkin", "mail_rewake"):
    summ([t for t in W_ if t["ctx1"] >= 150e3 and t["kind"] == k], k + " (all results)")
print(
    "\n== D. no-news wakes (watch_timeout + monitor_expired), warm, nothing-to-do, by band"
)
NN = {"watch_timeout", "monitor_expired", "watch_timeout_guess"}
for lo, hi, n in BANDS:
    summ(
        [t for t in W_ if lo <= t["ctx1"] < hi and nothing(t) and t["kind"] in NN],
        "  " + n,
    )
summ(
    [t for t in W_ if t["ctx1"] >= 150e3 and nothing(t) and t["kind"] in NN],
    "  ALL >=150k",
)
print(
    "\n== E. busy at wake (own non-watcher background job running), warm, nothing-to-do, by band"
)
for lo, hi, n in BANDS:
    summ([t for t in W_ if lo <= t["ctx1"] < hi and nothing(t) and t["busy"]], "  " + n)
summ(
    [t for t in W_ if t["ctx1"] >= 150e3 and nothing(t) and t["busy"]],
    "  ALL >=150k busy",
)
summ(
    [
        t
        for t in W_
        if t["ctx1"] >= 150e3 and nothing(t) and t["kind"] == "goal_checkin"
    ],
    "  goal check-ins >=150k",
)
print("\n== F. result-class split, warm machine wakes >= 150k")
c = collections.Counter(t["res"] for t in W_ if t["ctx1"] >= 150e3)
print(dict(c))
print(
    "\n== G. cold/rebuild-first machine wakes >= 150k (gap >= 3500 s or first request rebuilt)"
)
summ(
    [
        t
        for t in base
        if t["ctx1"] >= 150e3
        and t["gap"] is not None
        and t["gap"] >= 60
        and not warm(t)
    ],
    "cold all",
)
print(
    "\n== H. long-idle no-news wakes: gap 3000-3500 s (watcher 55-min timeouts), nothing-to-do, >=150k"
)
summ(
    [
        t
        for t in W_
        if t["ctx1"] >= 150e3
        and nothing(t)
        and t["kind"] in NN
        and 3000 <= t["gap"] < 3500
    ],
    "gap 3000-3500",
)
