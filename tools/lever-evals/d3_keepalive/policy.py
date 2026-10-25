#!/usr/bin/env python3
"""policy.py — the D3 keepalive policy replay (docs/plans/USAGE_LEVERS.md § W7+ §2 D3 "Offline").

WHAT IT PRICES. One case per main-session idle gap (build_cases.py, or the reviewer's G2.json).
A policy decides, at the gap's wake moment, whether to wake the session; the replay prices every
wake it fires and every cache rebuild it rescues, in weekly-meter pp, per account, scaled to a week.

WHERE THE RULES COME FROM. Two sources, kept separate on purpose:
  * the wake schedule, the rescue verdict and the prices are hooks/lib/idle_gap.py's own:
    outcome() (wake count, rebuild-with), wake_cost() / rebuild_extra() and READ_PP / WRITE_PP /
    OUT_PP — the production shadow's model, so the replay cannot drift from what the hook logs;
  * the wake TURN profile, the chain-survival odds of today's code and the recap credit are the
    numbers reviewer's engine (rv/rrep.py, imported under ~/.claude/hillclimb/_imports/lean-idle-rv),
    which produced the figures this replay must reproduce: recompute.out's engine check, as coded
    3.79 / 2.67 and R2 busy2 5.07 / 4.23 pp/wk at read weights low / high.

THE MAPPING ONTO outcome(). rrep wakes at stop+WAKE, then every TURN+WAKE while before the gap's
effective end, and a wake rescues iff end - (last wake + TURN) < TTL. In shifted time
tau = t - stop + TURN that is exactly outcome(span + TURN, wake_s=WAKE + TURN, ttl_s=TTL + TURN):
wakes land at k*(WAKE+TURN), and rebuild_with is "not rescued". The observed rebuild (case `reb`)
replaces outcome()'s rebuild_without, because the transcript says what the first request paid.

A wake later than TTL after the last refresh finds the cache already gone, so wake_s above TTL
rescues nothing (the reviewer engine never priced that range; the tunable is bounded here).

Stdlib only, Python 3.9-safe. usage: python3 -I policy.py <cases.json|cases.jsonl[.gz]> [policy...]
"""

import collections
import gzip
import importlib.util
import json
import os
import sys

HERE = os.path.dirname(os.path.realpath(__file__))
IDLE_GAP = os.path.normpath(
    os.path.join(HERE, "..", "..", "..", "hooks", "lib", "idle_gap.py")
)


def _load_idle_gap():
    spec = importlib.util.spec_from_file_location("idle_gap", IDLE_GAP)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


IG = _load_idle_gap()

ACCTS = ("next", "next2", "next3", "next4")
WAKE, TTL, TURN, RECAP_AT = 3300.0, 3600.0, 30.0, 190.0
READS = (("low", IG.READ_PP[0]), ("high", IG.READ_PP[1]))
S_CHAIN_AS_CODED = (
    0.89  # chain-timer survival of today's code (recompute.py "AS CODED s=0.89")
)
PREC = 0.57  # reads of the request that preceded the wake turn, in context units (rrep)

# wake-turn profiles: requests, cache-write tokens, output tokens, own growth read by later requests
PROF = {
    "med": dict(
        nreq=3, cw=1519, out=522, grow=1748
    ),  # rrep "med", measured over watch turns
    "idle_gap": dict(  # the shadow hook's own one-request wake (idle_gap.wake_cost)
        nreq=1, cw=IG.WAKE_WRITE_TOK, out=IG.WAKE_OUT_TOK, grow=0
    ),
}

# the decision-time features a policy may read; everything else on a case is the world's answer
DECISION_FIELDS = ("acct", "ctx", "busy2", "watch2", "prev")

TUNABLE = {"wake_s": 3300, "skip_watcher": True, "min_ctx_k": 0}


class TruncationError(KeyError):
    pass


def _running(jobs, t, kinds):
    """rjobs.py busy2 rule: an unknown-end job is taken as done 1 h after launch."""
    return any(
        kd in kinds and js <= t < (je if je is not None else js + 3600)
        for js, je, kd in jobs
    )


class DecisionView(dict):
    """A case as a policy may see it at wake time t. Reading an outcome field is a harness bug (the
    truncation check), so it raises instead of returning the future. busy2/watch2 come from the
    case's job intervals at t; a case without them (the reference G2 rows) carries them only at
    feat_at = stop + 3300, and asking for them at any other moment raises too."""

    def __init__(self, g, t):
        super().__init__((k, g.get(k)) for k in DECISION_FIELDS)
        if g.get("jobs") is not None:
            self["busy2"] = _running(g["jobs"], t, ("bash", "agent", "workflow"))
            self["watch2"] = _running(g["jobs"], t, ("watch",))
        elif abs(t - g.get("feat_at", g["stop"] + WAKE)) > 1e-6:
            for k in ("busy2", "watch2"):
                del self[k]
            self._why = "case has busy/watch only at stop+%d, not at wake time t" % WAKE

    def __missing__(self, k):
        raise TruncationError(
            getattr(self, "_why", None)
            if k in ("busy2", "watch2") and hasattr(self, "_why")
            else "policy read outcome field %r at decision time" % k
        )


def load_cases(path):
    op = gzip.open if path.endswith(".gz") else open
    with op(path, "rt") as fh:
        head = fh.read(1)
        fh.seek(0)
        if head == "[":
            return json.load(fh)
        return [json.loads(ln) for ln in fh if ln.strip()]


def wake_cost(g, r, prof, prec):
    """pp of one wake turn on this gap (rrep.wake_cost; equals idle_gap.wake_cost on PROF idle_gap)."""
    p = PROF[prof]
    if prof == "idle_gap":
        return IG.wake_cost(g["ctx"], r)
    c = (p["nreq"] + prec) * g["ctx"] * r + p["cw"] * IG.WRITE_PP + p["out"] * IG.OUT_PP
    if not g["term"]:
        c += p["grow"] * g["later"] * r
    return c / 1e6


def end_eff(g, term_mode):
    """The moment the gap stops being wakeable: its end, an earlier exit, and (term_mode low) a dead
    censored terminal gap cut at the transcript's last write."""
    e = g["end"]
    if g["exit"]:
        e = min(e, g["exit"])
    if (
        g["term"]
        and g["end_kind"] == "censored"
        and not g["alive"]
        and term_mode == "low"
    ):
        e = max(g["stop"], min(e, g["mt"]))
    return e


def schedule(stop, ee, wake_s, max_wakes):
    """→ (wake times, rescued-if-rebuild) through idle_gap.outcome() in shifted time (module doc)."""
    k, _without, with_, _label = IG.outcome(
        ee - stop + TURN, wake_s=wake_s + TURN, ttl_s=TTL + TURN, max_wakes=max_wakes
    )
    ws = [stop + wake_s + i * (wake_s + TURN) for i in range(k)]
    return ws, (not with_) and wake_s <= TTL


def k_min(g):
    """Fewest wakes that keep the cache warm to the gap's end: each wake at the latest moment the
    cache is still alive (stop+TTL, then every TTL+TURN), through the same outcome()."""
    k, _w, _r, _l = IG.outcome(
        g["end"] - g["stop"] + TURN,
        wake_s=TTL + TURN,
        ttl_s=TTL + TURN,
        max_wakes=10**6,
    )
    return max(1, k)


def _new():
    return {a: collections.Counter() for a in ACCTS}


def run(
    cases, policy, r, prof="med", term_mode="low", wk=0.5, params=None, per_case=None
):
    """Price `policy` over `cases` at read weight r. → {acct: {net, wakes, rescued, cost, ben, gaps,
    term_cost}, 'all': ...}, pp per week (x wk = 7 d / case window). per_case, if a dict, receives
    case_id -> unscaled net pp for every case (0.0 where the policy did nothing)."""
    prm = dict(TUNABLE)
    prm.update(params or {})
    prec = 0.0 if prof == "idle_gap" else PREC
    acc = _new()
    for g in cases:
        net = 0.0
        if policy != "never":
            net = _price(g, policy, r, prof, prec, term_mode, prm, acc[g["acct"]])
        if per_case is not None:
            per_case[g.get("case_id") or "%s:%s" % (g["sid"], g["stop"])] = net
    res = {a: {k: v * wk for k, v in acc[a].items()} for a in ACCTS}
    for a in ACCTS:
        res[a]["net"] = res[a].get("ben", 0.0) - res[a].get("cost", 0.0)
    keys = set().union(*[res[a] for a in ACCTS])
    res["all"] = {k: sum(res[a].get(k, 0.0) for a in ACCTS) for k in keys}
    return res


def _selected(g, policy, prm, t):
    v = DecisionView(g, t)
    if prm["min_ctx_k"] and v["ctx"] < prm["min_ctx_k"] * 1000:
        return False
    if policy in ("r2_busy", "candidate"):
        if not v["busy2"]:
            return False
        if policy == "candidate" and prm["skip_watcher"] and v["watch2"]:
            return False
    if policy == "r4_busy_nowatch" and not (v["busy2"] and not v["watch2"]):
        return False
    return True


def _price(g, policy, r, prof, prec, term_mode, prm, C):
    """Price one gap into counter C; → its unscaled net pp."""
    rebuildable = g["reb"] and not g["term"] and not g["exit"]
    c1 = wake_cost(g, r, prof, prec)
    if policy == "perfect_foresight":
        if not rebuildable:
            return 0.0
        k = k_min(g)
        ben = IG.rebuild_extra(g["saved"], r)
        if ben - k * c1 <= 0:
            return 0.0
        C["wakes"] += k
        C["rescued"] += 1
        C["cost"] += k * c1
        C["ben"] += ben
        C["gaps"] += 1
        return ben - k * c1
    if policy == "shadow_model":
        # the shadow hook's own ledger arithmetic, gap by gap: idle_gap.gap_costs on stop→end
        gc = IG.gap_costs(g["ctx"], end_eff(g, term_mode) - g["stop"])
        net = gc["net_pp"][1] if r == IG.READ_PP[0] else gc["net_pp"][0]
        if gc["wakes"]:
            C["wakes"] += gc["wakes"]
            C["gaps"] += 1
            C["rescued"] += gc["outcome"] == "wake_saves"
            C["ben"] += net + gc["wakes"] * IG.wake_cost(g["ctx"], r)
            C["cost"] += gc["wakes"] * IG.wake_cost(g["ctx"], r)
        return net
    wake_s = WAKE if policy == "literal" else float(prm["wake_s"])
    if not _selected(g, policy, prm, g["stop"] + wake_s):
        return 0.0
    ee = end_eff(g, term_mode)
    if g["stop"] + wake_s >= ee:
        return 0.0
    if policy == "literal" and g["kill"] is not None:
        return 0.0  # today's code: any write after the stop kills the first timer
    max_wakes = 1 if policy in ("once", "candidate") else 10**6
    ws, rescued = schedule(g["stop"], ee, wake_s, max_wakes)
    s = prm.get("s_chain", S_CHAIN_AS_CODED)
    pw = [s**i for i in range(len(ws))] if policy == "literal" else [1.0] * len(ws)
    nw = sum(pw)
    cost = nw * c1
    ben = 0.0
    if rebuildable:
        pr = pw[-1] if rescued else 0.0
        if (
            policy == "literal"
            and len(ws) >= 2
            and g["end"] < ws[-2] + TURN + RECAP_AT + TTL
        ):
            pr += pw[-2] * (
                1 - s
            )  # the chain died at the last wake, but its recap kept it warm
        ben = pr * IG.rebuild_extra(g["saved"], r)
        C["rescued"] += pr
    C["wakes"] += nw
    C["cost"] += cost
    C["ben"] += ben
    C["gaps"] += 1
    if g["term"]:
        C["term_cost"] += cost
    return ben - cost


POLICIES = (
    "literal",
    "once",
    "chain",
    "r2_busy",
    "r4_busy_nowatch",
    "candidate",
    "shadow_model",
    "perfect_foresight",
    "never",
)


def line(lab, res):
    T = res["all"]
    return (
        "%-40s | %s | %6.2f | wakes/wk %6.1f rescued/wk %5.1f cost %5.2f ben %5.2f term_cost %5.2f"
        % (
            lab,
            " ".join("%6.2f" % res[a]["net"] for a in ACCTS),
            T["net"],
            T.get("wakes", 0),
            T.get("rescued", 0),
            T.get("cost", 0),
            T.get("ben", 0),
            T.get("term_cost", 0),
        )
    )


def main(argv):
    if not argv:
        sys.stderr.write(__doc__.rsplit("usage: ", 1)[1])
        return 2
    cases = load_cases(argv[0])
    pols = argv[1:] or list(POLICIES)
    for pol in pols:
        for rn, r in READS:
            print(line("%s %s" % (pol, rn), run(cases, pol, r)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
