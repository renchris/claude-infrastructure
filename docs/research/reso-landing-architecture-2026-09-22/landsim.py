#!/usr/bin/env python3
"""landsim — discrete-event model of reso's land path under N concurrent sessions.

Policies (see docs/research/reso-landing-architecture-2026-09-22.md §4):
  P0  today: optimistic CAS, 5 rounds; each round = reconcile + tsc + cc-sem(reso-land) + union
      suite + pre-push FULL suite (inside the push, so inside the CAS window; the hook runs even
      on a push git already knows is doomed — measured, git 2.54).
  P1  P0 minus the duplicate: hook honours the tree token; ls-remote precheck skips a doomed push;
      ref-lock race classified as a race. Every retry round still re-verifies in full.
  P2  P1 + cheap revalidation: a retry round runs incremental tsc + a partial suite only when the
      incoming trunk delta intersects the change's related-test set (prob 1-(1-q)^k).
  P3  two-phase: verify in parallel (Phase A, lock-free), commit through ONE short FIFO critical
      section (fetch, rebase, revalidate as P2, push). Single pusher => no CAS losses.
  P4  the brief's literal hypothesis: sessions enqueue immediately (no presubmit); one lander
      verifies trunk+batch in full (tsc + union over the batch), bisects a red batch.
  P5  P3's commit step run by a lander daemon that also GROUP-COMMITS every ready ticket.

Every stage law is fitted from ~/.reso/land.log v3 (7 days to 2026-09-23): stage(L) = a + b*L,
L = background load + contribution of concurrently running verifications.
"""

import heapq, random, math, statistics as st, sys, itertools, json


# ── fitted stage laws (seconds) ──────────────────────────────────────────────
def tsc_full(L):
    return 28 + 0.23 * L


def tsc_incr(L):
    return 0.30 * tsc_full(L)  # ASSUMPTION — warm .tsbuildinfo; Phase 0 measures it


def union(L):
    return 121 + 0.27 * L


def hookfull(L):
    return 143 + 0.36 * L


def partial(L):
    return 0.40 * union(L)  # ASSUMPTION — intersection re-run; Phase 0 measures it


RECONCILE, PRECHECK, PUSH_NET, CV, NONCODE_V = 2.0, 1.0, 4.0, 2.0, 5.0
BACKOFF = (1, 4)


class Sim:
    def __init__(s, seed):
        s.t = 0.0
        s.q = []
        s.n = itertools.count()
        s.rng = random.Random(seed)

    def at(s, dt, g, v=None):
        heapq.heappush(s.q, (s.t + dt, next(s.n), g, v))

    def spawn(s, g):
        s.at(0, g)

    def run(s, until):
        while s.q and s.q[0][0] <= until:
            s.t, _, g, v = heapq.heappop(s.q)
            s.step(g, v)

    def step(s, g, v):
        try:
            cmd = g.send(v)
        except StopIteration:
            return
        if cmd[0] == "sleep":
            s.at(max(0.0, cmd[1]), g)
        elif cmd[0] == "acq":
            cmd[1].acq(s, g)
        elif cmd[0] == "wait":
            cmd[1].append(g)  # park on a list; woken by whoever owns it
        else:
            raise ValueError(cmd)


class Sem:  # FIFO counting semaphore
    def __init__(s, k):
        s.k = k
        s.used = 0
        s.w = []

    def acq(s, sim, g):
        if s.used < s.k:
            s.used += 1
            sim.at(0, g)
        else:
            s.w.append(g)

    def rel(s, sim):
        if s.w:
            sim.at(0, s.w.pop(0))
        else:
            s.used -= 1


class World:
    def __init__(
        s,
        P,
        N,
        Lbg,
        seed,
        T_work=1800,
        f_code=0.55,
        p_self=0.05,
        p_flake=0.03,
        q=0.3,
        k_land=2,
        Bmax=8,
    ):
        s.sim = Sim(seed)
        s.P = P
        s.N = N
        s.Lbg = Lbg
        s.T_work, s.f_code, s.p_self, s.p_flake, s.q = (
            T_work,
            f_code,
            p_self,
            p_flake,
            q,
        )
        s.trunk = 0
        s.suites = 0
        s.tscs = 0
        s.sem_land = Sem(k_land)
        s.lock = Sem(1)
        s.Bmax = Bmax
        s.lat = []
        s.cpu = 0.0
        s.lands = 0
        s.rounds = []
        s.loadsamp = []
        s.queue = []
        s.lander_idle = []  # P4/P5
        s.rng = s.sim.rng

    # load-dependent duration with lognormal noise; suites ~4 runnable workers, tsc ~1
    def L(s):
        return s.Lbg + 4 * s.suites + 1 * s.tscs

    def dur(s, f):
        return f(s.L()) * s.rng.lognormvariate(0, 0.25)

    def run_stage(s, kind, f):
        d = s.dur(f)
        if kind == "suite":
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

    def flaked(s):
        return s.rng.random() < s.p_flake

    def pint(s, k):
        return 1 - (1 - s.q) ** max(0, k)

    # ── a session: work, then land one change; loop ──────────────────────────
    def session(s, i):
        yield ("sleep", s.rng.uniform(0, s.T_work))
        while True:
            code = s.rng.random() < s.f_code
            bad = (
                code and s.rng.random() < s.p_self
            )  # a real defect in the author's change
            t0 = s.sim.t
            while True:
                res = yield from s.land(code, bad)
                if res == "landed":
                    s.lat.append(s.sim.t - t0)
                    s.lands += 1
                    break
                if res == "red":  # deterministic red: fix, new version
                    yield ("sleep", s.rng.expovariate(1 / 600))
                    bad = False
                    t0 = s.sim.t
                    continue
                yield ("sleep", 60)  # exit 8 / flake: operator-less re-invoke
            yield ("sleep", s.rng.expovariate(1 / s.T_work))

    def verify_full(s, code, bad, with_hook):
        """tsc + admitted union suite (+ the hook's full suite in P0). -> 'ok'|'red'|'flake'."""
        if not code:
            yield ("sleep", NONCODE_V)
            return "ok"
        yield from s.run_stage("tsc", tsc_full)
        yield ("acq", s.sem_land)
        yield from s.run_stage("suite", union)
        s.sem_land.rel(s.sim)
        if bad:
            return "red"
        if s.flaked():
            return "flake"
        return "ok"

    def land(s, code, bad):
        P = s.P
        if P in ("P0", "P1", "P2"):
            full_needed = True
            verified_base = None
            for r in range(5):
                base = s.trunk
                yield ("sleep", RECONCILE)
                if full_needed:
                    v = yield from s.verify_full(code, bad, P == "P0")
                    if v != "ok":
                        s.rounds.append(r + 1)
                        return v
                    verified_base = base
                else:  # P2 cheap revalidation of a rebase
                    k = base - verified_base
                    if code:
                        yield from s.run_stage("tsc", tsc_incr)
                        if s.rng.random() < s.pint(k):
                            yield from s.run_stage("suite", partial)
                            if s.flaked():
                                s.rounds.append(r + 1)
                                return "flake"
                    verified_base = base
                if P == "P0":
                    # the push fires the hook's FULL suite even if git already knows it is doomed
                    if code:
                        yield from s.run_stage("suite", hookfull)
                        if s.flaked():
                            s.rounds.append(r + 1)
                            return "flake"
                    yield ("sleep", PUSH_NET)
                    if s.trunk == base:
                        s.trunk += 1
                        s.rounds.append(r + 1)
                        return "landed"
                else:
                    yield ("sleep", PRECHECK)
                    if s.trunk == base:
                        yield ("sleep", PUSH_NET)
                        if s.trunk == base:
                            s.trunk += 1
                            s.rounds.append(r + 1)
                            return "landed"
                # lost the race
                if P == "P2":
                    full_needed = False
                yield ("sleep", s.rng.uniform(*BACKOFF))
            s.rounds.append(5)
            return "exhausted"

        if P == "P3":
            base = s.trunk
            yield ("sleep", RECONCILE)
            v = yield from s.verify_full(
                code, bad, False
            )  # Phase A: parallel, lock-free
            if v != "ok":
                return v
            yield ("acq", s.lock)  # Phase B: one short critical section
            yield ("sleep", 1.0)  # fetch
            k = s.trunk - base
            if k > 0 and code:
                yield ("sleep", 1.0)  # rebase
                yield from s.run_stage("tsc", tsc_incr)
                if s.rng.random() < s.pint(k):
                    yield from s.run_stage("suite", partial)
                    if s.flaked():
                        s.lock.rel(s.sim)
                        return "flake"
            yield ("sleep", PUSH_NET + CV)
            s.trunk += 1
            s.lock.rel(s.sim)
            s.rounds.append(1)
            return "landed"

        if P == "PS":
            # Serialized lane (Phase 2d; H1's C8): EVERY land takes one FIFO lease from before
            # its fetch through its push, so no on-box land moves trunk under a holder. Code
            # lands run tsc + ONE full suite inside it (the hook then skips on the full token);
            # non-code lands hold it only for their push.
            yield ("acq", s.lock)
            yield ("sleep", RECONCILE)
            if code:
                yield from s.run_stage("tsc", tsc_full)
                yield from s.run_stage("suite", hookfull)
                if bad:
                    s.lock.rel(s.sim)
                    return "red"
                if s.flaked():
                    s.lock.rel(s.sim)
                    return "flake"
            else:
                yield ("sleep", NONCODE_V)
            yield ("sleep", PUSH_NET + CV)
            s.trunk += 1
            s.lock.rel(s.sim)
            s.rounds.append(1)
            return "landed"

        if P in ("P4", "P5"):
            if P == "P5":  # presubmit in the session, as P3
                base = s.trunk
                yield ("sleep", RECONCILE)
                v = yield from s.verify_full(code, bad, False)
                if v != "ok":
                    return v
            else:
                base = s.trunk
            ticket = {
                "code": code,
                "bad": bad if P == "P4" else False,
                "base": base,
                "res": None,
                "waiter": [],
            }
            s.queue.append(ticket)
            if s.lander_idle:
                s.sim.at(0, s.lander_idle.pop())
            yield ("wait", ticket["waiter"])
            s.rounds.append(1)
            return ticket["res"]

    # ── the lander daemon for P4 / P5 ────────────────────────────────────────
    def lander(s):
        while True:
            if not s.queue:
                yield ("wait", s.lander_idle)
                continue
            batch = s.queue[: s.Bmax]
            del s.queue[: len(batch)]
            yield from s.land_batch(batch)

    def verify_batch(s, batch):
        """P4: full tsc + union over the batch. P5: revalidation only (as P3's critical section)."""
        yield ("sleep", 1.0 + 0.5 * len(batch))  # fetch + rebase/cherry-pick
        codes = [t for t in batch if t["code"]]
        if not codes:
            return "ok"
        if s.P == "P4":
            yield from s.run_stage("tsc", tsc_full)
            b = len(codes)
            yield from s.run_stage("suite", lambda L: union(L) * (1 + 0.15 * (b - 1)))
            if any(t["bad"] for t in codes):
                return "red"
            return "flake" if s.flaked() else "ok"
        k = max(s.trunk - min(t["base"] for t in codes), 0) + len(codes) - 1
        yield from s.run_stage("tsc", tsc_incr)
        if s.rng.random() < s.pint(k):
            yield from s.run_stage("suite", partial)
            if s.flaked():
                return "flake"
        return "ok"

    def land_batch(s, batch):
        v = yield from s.verify_batch(batch)
        if v == "ok":
            yield ("sleep", PUSH_NET + CV)
            s.trunk += 1
            for t in batch:
                t["res"] = "landed"
                s.sim.at(0, t["waiter"].pop()) if t["waiter"] else None
            return
        if len(batch) == 1:
            t = batch[0]
            t["res"] = "red" if v == "red" else "flake"
            if t["waiter"]:
                s.sim.at(0, t["waiter"].pop())
            return
        h = len(batch) // 2  # bors bisection
        yield from s.land_batch(batch[:h])
        yield from s.land_batch(batch[h:])

    def sampler(s):
        while True:
            s.loadsamp.append(s.L())
            yield ("sleep", 30)


def pct(a, p):
    a = sorted(a)
    if not a:
        return float("nan")
    k = (len(a) - 1) * p
    f = int(k)
    c = min(f + 1, len(a) - 1)
    return a[f] + (a[c] - a[f]) * (k - f)


def run(P, N, Lbg, hours=48, seeds=3, **kw):
    lat = []
    lands = 0
    cpu = 0.0
    rounds = []
    loads = []
    for sd in range(seeds):
        w = World(P, N, Lbg, seed=1000 * sd + N, **kw)
        for i in range(N):
            w.sim.spawn(w.session(i))
        if P in ("P4", "P5"):
            w.sim.spawn(w.lander())
        w.sim.spawn(w.sampler())
        w.sim.run(hours * 3600)
        lat += w.lat
        lands += w.lands
        cpu += w.cpu
        rounds += w.rounds
        loads += w.loadsamp
    return {
        "P": P,
        "N": N,
        "Lbg": Lbg,
        "lands_h": lands / (hours * seeds),
        "p50_min": pct(lat, 0.5) / 60,
        "p95_min": pct(lat, 0.95) / 60,
        "max_min": max(lat) / 60 if lat else 0,
        "cpu_min_per_land": cpu / max(lands, 1) / 60,
        "mean_load": sum(loads) / max(len(loads), 1),
        "rounds_p95": pct(rounds, 0.95),
    }


if __name__ == "__main__":
    kw = json.loads(sys.argv[1]) if len(sys.argv) > 1 else {}
    Ns = kw.pop("Ns", [4, 8, 15, 25, 40])
    Lbgs = kw.pop("Lbgs", [45, 150])
    Ps = kw.pop("Ps", ["P0", "P1", "P2", "P3", "P4", "P5"])
    print(
        "%-3s %3s %4s | %7s %7s %7s %7s | %8s %6s %5s"
        % (
            "P",
            "N",
            "Lbg",
            "lands/h",
            "p50min",
            "p95min",
            "maxmin",
            "cpu/land",
            "load",
            "rnd95",
        )
    )
    for Lbg in Lbgs:
        for P in Ps:
            for N in Ns:
                r = run(P, N, Lbg, **kw)
                print(
                    "%-3s %3d %4d | %7.1f %7.1f %7.1f %7.1f | %8.1f %6.0f %5.0f"
                    % (
                        P,
                        N,
                        Lbg,
                        r["lands_h"],
                        r["p50_min"],
                        r["p95_min"],
                        r["max_min"],
                        r["cpu_min_per_land"],
                        r["mean_load"],
                        r["rounds_p95"],
                    )
                )
