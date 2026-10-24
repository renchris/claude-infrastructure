#!/usr/bin/env python3
# Replay hooks/idle-keepalive.sh in WAKE mode over 14 days of interactive main-session idle gaps.
# usage: python3 -I sim.py <dir>   (reads gaps.tsv from gaps.py)
import collections
import csv
import json
import os
import sys

D = sys.argv[1]
S, E = (float(x) for x in open(os.path.join(D, "window")).read().split())
WK = 7.0 / ((E - S) / 86400.0)
ACCTS = ["next", "next2", "next3", "next4"]
WAKE_S, TTL, SETTLE, DELTA = (
    3300,
    3600,
    20,
    30,
)  # DELTA: wake turn + Stop hooks until the re-armed timer
W, O = 0.245, 0.404  # weekly pp/Mtok (round 2 fit4)
W_INP = 389.0  # fit4 uncached-input weight, used by w4/sim.py as a per-request proxy
READS = {"low": 0.0057, "high": 0.0076}
P_AWAY = 0.64  # measured: share of >=3300 s gaps after a watcher-timeout wake turn whose timer an away_summary kills
RP_CTX = 43779 + 14781 + 240  # w4 re-prime (median first request of a fresh session)

# wake-turn cost profiles: requests (each reads the context), tokens written, output, uncached input,
# context growth left behind; measured from real warm wake turns (an4.py, wturns.tsv)
PROFILES = {
    "brief_min": dict(nreq=1, cw=1000, out=300, inp=4, grow=1000, away=0.0),
    "proxy_med": dict(nreq=3, cw=1515, out=522, inp=6, grow=2696, away=P_AWAY),
    "proxy_mean": dict(nreq=4.2, cw=6921, out=1108, inp=9.4, grow=4871, away=P_AWAY),
}

G = list(csv.DictReader(open(os.path.join(D, "gaps.tsv")), delimiter="\t"))
ALIVE = set(open(os.path.join(D, "alive_sids.txt")).read().split())
MT = {}
for _a in ACCTS:
    for _l in open(os.path.join(D, _a + ".files")):
        _p = _l.rstrip("\n").split("\t", 7)
        MT[_p[3]] = max(MT.get(_p[3], 0.0), float(_p[1]))
TERM_MODE = os.environ.get("TERM_MODE", "low")  # low: dead w/o SessionEnd died at last write; high: lived to window end


def wake_cost(ctx, r, prof, inp_on, later):
    c = (prof["nreq"] + prof["away"]) * ctx * r + prof["cw"] * W + prof["out"] * O
    if inp_on:
        c += prof["inp"] * W_INP
    c += prof["grow"] * later * r  # every later request re-reads what the wake added
    return c / 1e6


def wakes_for(st, end_eff, policy, first_kill_t):
    """-> list of wake times inside [st, end_eff) for one gap."""
    out = []
    if policy == "once":
        t = st + WAKE_S
        if t < end_eff:
            out.append(t)
        return out
    t = st + WAKE_S
    if policy == "literal" and first_kill_t is not None and first_kill_t < t:
        return out
    k = 0
    while t < end_eff:
        out.append(t)
        k += 1
        if policy == "literal":
            # chained timers die with p=P_AWAY: count the expected chain via a deterministic thinning
            # (every wake after the first survives with 1-P_AWAY) -> handled by weights below
            pass
        t = t + DELTA + WAKE_S
    return out


def run(policy, rname, pname, inp_on=False, w4=False, sel=None):
    r = READS[rname]
    prof = PROFILES[pname]
    acc = collections.defaultdict(lambda: collections.Counter())
    for g in G:
        if sel and not sel(g):
            continue
        a = g["acct"]
        st, end, dur = float(g["start"]), float(g["end"]), float(g["dur"])
        term = g["terminal"] == "1"
        ctx = int(g["ctx"])
        later = int(g["later_reqs"])
        exit_t = float(g["exit_t"]) if g["exit_t"] else None
        end_eff = min(end, exit_t) if exit_t else end
        if term and g["end_kind"] == "censored" and g["sid"] not in ALIVE:
            if g["closed"] == "1" or TERM_MODE == "low":
                end_eff = max(st, min(end, MT.get(g["sid"], st)))
        rebuild = g["rebuild"] == "1"
        saved = int(g["saved_tok"])
        fk = None
        if g["first_ev_t"]:
            t = float(g["first_ev_t"])
            if t < end - 5:
                fk = t
        C = acc[a]
        if dur >= WAKE_S:
            C["gaps_ge_3300"] += 1
        if rebuild:
            C["rebuilds"] += 1
            C["rebuild_pp"] += saved * (W - r) / 1e6
        # W4: recycled at idle minute 15 when ctx >= 150k and not busy -> the successor idles instead
        if w4 and ctx >= 150000 and dur >= 900 and g["busy_at_15"] == "0":
            C["w4_recycled"] += 1
            s_st = st + 960
            s_dur = end_eff - s_st
            s_rebuild = (not term) and s_dur > TTL
            wl = wakes_for(s_st, end_eff, "once" if policy == "once" else "chain", None)
            if policy == "literal":
                n_eff = (1 - (fk is not None and fk < s_st + WAKE_S)) * sum(
                    (1 - P_AWAY) ** i for i in range(len(wl))
                )
            else:
                n_eff = len(wl)
            cost = n_eff * wake_cost(RP_CTX, r, prof, inp_on, 0 if term else later)
            rescued = s_rebuild and wl and (end - wl[-1] - DELTA) < TTL and not exit_t
            if policy == "literal" and rescued:
                rescued_frac = (1 - P_AWAY) ** max(0, len(wl) - 1) * (
                    0 if (fk is not None and fk < s_st + WAKE_S) else 1
                )
            else:
                rescued_frac = 1.0 if rescued else 0.0
            ben = rescued_frac * RP_CTX * (W - r) / 1e6
            C["wakes"] += n_eff
            C["cost"] += cost
            C["benefit"] += ben
            if term:
                C["term_wakes"] += n_eff
                C["term_cost"] += cost
            continue
        wl = wakes_for(st, end_eff, policy, fk)
        if not wl:
            continue
        if policy == "literal":
            # first timer already survived (else wl is empty); each later timer survives with 1-P_AWAY
            weights = [(1 - P_AWAY) ** i for i in range(len(wl))]
            n_eff = sum(weights)
            # rescued only if the chain reaches the last wake before the gap end
            p_reach_last = weights[-1]
        else:
            n_eff = len(wl)
            p_reach_last = 1.0
        cost = n_eff * wake_cost(ctx, r, prof, inp_on, 0 if term else later)
        rescued = (
            (not term) and rebuild and (end - (wl[-1] + DELTA)) < TTL and not exit_t
        )
        ben = (p_reach_last if rescued else 0.0) * saved * (W - r) / 1e6
        C["wakes"] += n_eff
        C["woken_gaps"] += 1
        C["cost"] += cost
        C["benefit"] += ben
        C["rescued"] += p_reach_last if rescued else 0.0
        if term:
            C["term_gaps"] += 1
            C["term_wakes"] += n_eff
            C["term_cost"] += cost
        if dur >= 3 * 3600:
            C["long_gaps"] += 1
            C["long_wakes"] += n_eff
            C["long_cost"] += cost
            C["long_benefit"] += ben
        if WAKE_S <= dur < TTL and not term:
            C["pre_ttl_wakes"] += (
                n_eff  # cache still warm when the gap ended: pure cost
            )
            C["pre_ttl_cost"] += cost
        if g["watcher_at_wake"] == "1":
            C["watcher_wakes"] += n_eff
    res = {}
    for a in ACCTS:
        C = acc[a]
        res[a] = {
            k: round(v * WK, 3) if isinstance(v, float) else round(v * WK, 2)
            for k, v in C.items()
        }
        res[a]["net"] = round((C["benefit"] - C["cost"]) * WK, 3)
    res["total"] = {
        k: round(sum(res[a].get(k, 0) for a in ACCTS), 3)
        for k in set().union(*[res[a] for a in ACCTS])
    }
    return res


if __name__ == "__main__":
    out = {}
    hdr = "%-8s %-5s %-10s %-4s %-3s | %s | %7s | wakes/wk rescued/wk cost benefit | term wakes/cost | long>3h gaps/wakes/cost/ben | pre-TTL wakes/cost"
    print(
        hdr
        % (
            "policy",
            "reads",
            "profile",
            "inp",
            "w4",
            " ".join("%7s" % a for a in ACCTS),
            "total",
        )
    )
    for policy in ("once", "chain", "literal"):
        for pname in ("brief_min", "proxy_med", "proxy_mean"):
            for rname in ("low", "high"):
                for inp_on in (False, True):
                    for w4 in (False, True):
                        res = run(policy, rname, pname, inp_on, w4)
                        key = "%s/%s/%s/%s/%s" % (
                            policy,
                            rname,
                            pname,
                            "inp" if inp_on else "noinp",
                            "w4" if w4 else "now4",
                        )
                        out[key] = res
                        T = res["total"]
                        print(
                            "%-8s %-5s %-10s %-4s %-3s | %s | %7.2f | %6.1f %6.1f %6.2f %6.2f | %6.1f %6.2f | %4.1f %6.1f %5.2f %5.2f | %5.1f %5.2f"
                            % (
                                policy,
                                rname,
                                pname,
                                "inp" if inp_on else "-",
                                "w4" if w4 else "-",
                                " ".join("%7.2f" % res[a]["net"] for a in ACCTS),
                                T["net"],
                                T.get("wakes", 0),
                                T.get("rescued", 0),
                                T.get("cost", 0),
                                T.get("benefit", 0),
                                T.get("term_wakes", 0),
                                T.get("term_cost", 0),
                                T.get("long_gaps", 0),
                                T.get("long_wakes", 0),
                                T.get("long_cost", 0),
                                T.get("long_benefit", 0),
                                T.get("pre_ttl_wakes", 0),
                                T.get("pre_ttl_cost", 0),
                            )
                        )
    json.dump(out, open(os.path.join(D, "sim.json"), "w"), indent=1)
