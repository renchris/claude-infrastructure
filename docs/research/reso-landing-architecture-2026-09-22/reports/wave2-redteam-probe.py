#!/usr/bin/env python3
"""Red-team probes of landsim.py (read-only against the evidence dir; writes nothing there).

Probe 1: how often does P5f's combiner skip the suite it is said to run once per batch (k==0)?
Probe 2: P5f with the full suite forced on every code batch (what §5.3 says Phase 3 does).
Probe 3: E's load law (+45 s per other concurrent suite) applied to PS / P5f / P5.
Probe 4: PS non-code latency and share of PS lands whose latency exceeds 600 s (Bash tool max).
"""

import importlib.util, os, sys

HERE = "/Users/chrisren/Development/.worktrees/research/reso-landing-arch/docs/research/reso-landing-architecture-2026-09-22"
spec = importlib.util.spec_from_file_location("ls", os.path.join(HERE, "landsim.py"))
ls = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ls)
U, H, TF = ls.union, ls.hookfull, ls.tsc_full

FORCE_FULL = False
E_LAW = False
STATS = {"batches": 0, "code_batches": 0, "k0_skips": 0, "suite_runs": 0}


class W(ls.World):
    def __init__(s, *a, **kw):
        super().__init__(*a, **kw)
        s.lat_code = []
        s.lat_noncode = []

    def run_stage(s, kind, f):
        d = s.dur(f)
        if kind == "suite":
            if E_LAW:
                d += 45.0 * s.suites  # E: +45 s per OTHER concurrently running suite
            s.suites += 1
            s.cpu += 4 * f(0)
        elif kind == "tsc":
            s.tscs += 1
            s.cpu += 1.5 * f(0)
        yield ("sleep", d)
        if kind == "suite":
            s.suites -= 1
        elif kind == "tsc":
            s.tscs -= 1
        return d

    def pint(s, k):
        if FORCE_FULL and s.P == "P5":
            return 1.0
        return super().pint(k)

    def verify_batch(s, batch):
        yield ("sleep", 1.0 + 0.5 * len(batch))
        codes = [t for t in batch if t["code"]]
        STATS["batches"] += 1
        if not codes:
            return "ok"
        STATS["code_batches"] += 1
        if s.P == "P4":
            yield from s.run_stage("tsc", ls.tsc_full)
            b = len(codes)
            yield from s.run_stage(
                "suite", lambda L: ls.union(L) * (1 + 0.15 * (b - 1))
            )
            if any(t["bad"] for t in codes):
                return "red"
            return "flake" if s.flaked() else "ok"
        k = max(s.trunk - min(t["base"] for t in codes), 0) + len(codes) - 1
        yield from s.run_stage("tsc", ls.tsc_incr)
        if s.rng.random() < s.pint(k):
            STATS["suite_runs"] += 1
            yield from s.run_stage("suite", ls.partial)
            if s.flaked():
                return "flake"
        else:
            STATS["k0_skips"] += 1
        return "ok"

    def session(s, i):
        yield ("sleep", s.rng.uniform(0, s.T_work))
        while True:
            code = s.rng.random() < s.f_code
            bad = code and s.rng.random() < s.p_self
            t0 = s.sim.t
            while True:
                res = yield from s.land(code, bad)
                if res == "landed":
                    dt = s.sim.t - t0
                    s.lat.append(dt)
                    (s.lat_code if code else s.lat_noncode).append(dt)
                    s.lands += 1
                    break
                if res == "red":
                    yield ("sleep", s.rng.expovariate(1 / 600))
                    bad = False
                    t0 = s.sim.t
                    continue
                yield ("sleep", 60)
            yield ("sleep", s.rng.expovariate(1 / s.T_work))


def run(P, N, Lbg=150, hours=48, seeds=3, **kw):
    lat, lc, ln, lands = [], [], [], 0
    for sd in range(seeds):
        w = W(P, N, Lbg, seed=1000 * sd + N, **kw)
        for i in range(N):
            w.sim.spawn(w.session(i))
        if P in ("P4", "P5"):
            w.sim.spawn(w.lander())
        w.sim.spawn(w.sampler())
        w.sim.run(hours * 3600)
        lat += w.lat
        lc += w.lat_code
        ln += w.lat_noncode
        lands += w.lands
    p = ls.pct
    return dict(
        lands_h=lands / (hours * seeds),
        p50=p(lat, 0.5) / 60,
        p95=p(lat, 0.95) / 60,
        code_p50=p(lc, 0.5) / 60,
        code_p95=p(lc, 0.95) / 60,
        nc_p50=p(ln, 0.5) / 60,
        nc_p95=p(ln, 0.95) / 60,
        over600=sum(1 for x in lat if x > 600) / max(len(lat), 1),
        over900=sum(1 for x in lat if x > 900) / max(len(lat), 1),
    )


def reset(pf=0.4, tf=0.3):
    ls.union = U
    ls.partial = lambda L: pf * U(L)
    ls.tsc_incr = lambda L: tf * TF(L)


def fmt(tag, r):
    print(
        "%-22s | %6.1f/h  p50 %5.1f  p95 %5.1f | code p50/p95 %5.1f/%5.1f | non-code p50/p95 %5.1f/%5.1f | >10min %4.0f%%  >15min %4.0f%%"
        % (
            tag,
            r["lands_h"],
            r["p50"],
            r["p95"],
            r["code_p50"],
            r["code_p95"],
            r["nc_p50"],
            r["nc_p95"],
            100 * r["over600"],
            100 * r["over900"],
        )
    )


if __name__ == "__main__":
    T = 1800
    print(
        "== Probe 1/2: P5f (Phase 3, 'full suite once per batch') — how many code batches ran NO suite (k==0)?"
    )
    for N in (8, 15, 25):
        for force in (False, True):
            FORCE_FULL = force
            E_LAW = False
            for k in STATS:
                STATS[k] = 0
            reset()
            ls.partial = H
            r = run("P5", N, T_work=T, k_land=2, q=1.0)
            fmt("P5f N=%d %s" % (N, "forced-full" if force else "as-shipped "), r)
            if not force:
                print(
                    "      code batches %d, suite runs %d, k==0 suite SKIPS %d (%.0f%%)"
                    % (
                        STATS["code_batches"],
                        STATS["suite_runs"],
                        STATS["k0_skips"],
                        100 * STATS["k0_skips"] / max(STATS["code_batches"], 1),
                    )
                )
    print()
    print(
        "== Probe 3/4: E's load law (+45 s per other concurrent suite) vs the model's ~1.4 s; PS non-code latency; share of PS lands > Bash tool max (10 min)"
    )
    for N in (8, 15, 25):
        for elaw in (False, True):
            E_LAW = elaw
            FORCE_FULL = False
            reset()
            r = run("PS", N, T_work=T)
            fmt("PS  N=%d %s" % (N, "E-law" if elaw else "model"), r)
            FORCE_FULL = True
            reset()
            ls.partial = H
            r = run("P5", N, T_work=T, k_land=2, q=1.0)
            fmt("P5f N=%d %s (forced)" % (N, "E-law" if elaw else "model"), r)
            FORCE_FULL = False
            reset()
            r = run("P5", N, T_work=T, k_land=2, q=0.3)
            fmt("P5  N=%d %s" % (N, "E-law" if elaw else "model"), r)
