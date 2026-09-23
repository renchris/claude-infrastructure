#!/usr/bin/env python3
"""landsim v2 — discrete-event model of reso's land path under N concurrent sessions.

Policies (see ../reso-landing-architecture-2026-09-22.md §4):
  P0   today: optimistic CAS, 5 rounds; each round = reconcile + tsc + cc-sem(reso-land) + union
       suite + the pre-push FULL suite inside the push (git runs the hook even on a doomed push).
  P1   P0 minus the waste: the hook honours the tree token, an ls-remote precheck skips a doomed
       push, ref-lock = race. A lost round still re-verifies in full. (P1f: set union := full.)
  P2   P1 + cheap revalidation of a lost round (incremental tsc; a partial suite w.p. 1-(1-q)^k).
  PS   Phase 2 serialized lane: every land takes ONE FIFO turn from before its fetch through its
       push; code lands run tsc + one full suite inside it. prio=True lets non-code lands jump the
       code queue (they wait only for the current holder).
  P3   verify in parallel (Phase A), commit through one FIFO critical section (revalidate as P2).
  P4   the brief's literal hypothesis: enqueue UNVERIFIED; one lander verifies trunk+batch in full.
  P5   recommended: Phase A in the session, then one combiner that group-commits every ready
       ticket. full_combine=True (Phase 3, "P5f"): the combiner runs the FULL suite on any candidate
       that differs from a ticket's verified tree; False (Phase 4): pruned revalidation.

v2 changes, all from the wave-2 red-team (reports/wave2-redteam.md):
  * law='E' (default): the measured interference law (reports/E-load-capacity.md): every OTHER
    concurrently running suite adds +45 s to a union/partial suite, +49 s to a full suite and
    +11 s to tsc; ambient load enters only through the fitted a + b*L_bg. law='load' is v1.
  * phaseA='full' (default for P3/P5): Phase A runs the FULL suite, so its verdict is a mode=full
    record for the exact tree and a lone ticket on an unmoved trunk needs no re-verification.
    v1 skipped the combiner's suite at k=0 while Phase A had run only the union (flattering).
  * code and non-code latencies are reported separately, plus the share of lands over 600 s
    (the Claude Code Bash tool's foreground ceiling).
"""

import heapq, random, itertools, sys, json


def tsc_full(L):
    return 28 + 0.23 * L


def tsc_incr(L):
    return 0.30 * tsc_full(L)  # ASSUMPTION — warm .tsbuildinfo; Phase 1 measures it


def union(L):
    return 121 + 0.27 * L


def hookfull(L):
    return 143 + 0.36 * L


def partial(L):
    return 0.40 * union(L)  # ASSUMPTION — intersection re-run; Phase 1 measures it


RECONCILE, PRECHECK, PUSH_NET, CV, NONCODE_V = 2.0, 1.0, 4.0, 2.0, 5.0
BACKOFF = (1, 4)
E_PER_OTHER = {
    "union": 45.0,
    "full": 49.0,
    "partial": 45.0,
    "tsc": 11.0,
}  # E §b, s per other suite


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
            try:
                cmd = g.send(v)
            except StopIteration:
                continue
            if cmd[0] == "sleep":
                s.at(max(0.0, cmd[1]), g)
            elif cmd[0] == "acq":
                cmd[1].acq(s, g, *cmd[2:])
            elif cmd[0] == "wait":
                cmd[1].append(g)
            else:
                raise ValueError(cmd)


class Sem:  # FIFO counting semaphore
    def __init__(s, k):
        s.k = k
        s.used = 0
        s.w = []

    def acq(s, sim, g, prio=False):
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


class PrioLock(Sem):  # one holder; high-priority waiters served first
    def __init__(s):
        super().__init__(1)
        s.hi = []

    def acq(s, sim, g, prio=False):
        if s.used < s.k:
            s.used += 1
            sim.at(0, g)
        else:
            (s.hi if prio else s.w).append(g)

    def rel(s, sim):
        if s.hi:
            sim.at(0, s.hi.pop(0))
        elif s.w:
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
        law="E",
        phaseA="full",
        prio=True,
        full_combine=True,
    ):
        s.sim = Sim(seed)
        s.P, s.N, s.Lbg = P, N, Lbg
        s.T_work, s.f_code, s.p_self, s.p_flake, s.q = (
            T_work,
            f_code,
            p_self,
            p_flake,
            q,
        )
        s.law, s.phaseA, s.prio, s.full_combine, s.Bmax = (
            law,
            phaseA,
            prio,
            full_combine,
            Bmax,
        )
        s.trunk = 0
        s.suites = 0
        s.tscs = 0
        s.sem_land = Sem(k_land)
        s.lock = PrioLock() if prio else Sem(1)
        s.lat_code = []
        s.lat_nc = []
        s.cpu = 0.0
        s.lands = 0
        s.rounds = []
        s.loadsamp = []
        s.queue = []
        s.lander_idle = []
        s.batches = []
        s.rng = s.sim.rng

    def L(s):
        return s.Lbg + 4 * s.suites + 1 * s.tscs

    def run_stage(s, kind, f):
        """kind in union|full|partial|tsc. Duration by the chosen law, lognormal noise sigma 0.25."""
        if s.law == "E":
            d = f(s.Lbg) + E_PER_OTHER[kind] * s.suites
        else:
            d = f(s.L())
        d *= s.rng.lognormvariate(0, 0.25)
        suite = kind != "tsc"
        if suite:
            s.suites += 1
            s.cpu += 4 * f(0)
        else:
            s.tscs += 1
            s.cpu += 1.5 * f(0)
        yield ("sleep", d)
        if suite:
            s.suites -= 1
        else:
            s.tscs -= 1
        return d

    def flaked(s):
        return s.rng.random() < s.p_flake

    def pint(s, k):
        return 1 - (1 - s.q) ** max(0, k)

    def session(s, i):
        yield ("sleep", s.rng.uniform(0, s.T_work))
        while True:
            code = s.rng.random() < s.f_code
            bad = code and s.rng.random() < s.p_self
            t0 = s.sim.t
            while True:
                res = yield from s.land(code, bad)
                if res == "landed":
                    (s.lat_code if code else s.lat_nc).append(s.sim.t - t0)
                    s.lands += 1
                    break
                if res == "red":
                    yield ("sleep", s.rng.expovariate(1 / 600))
                    bad = False
                    t0 = s.sim.t
                    continue
                yield ("sleep", 60)
            yield ("sleep", s.rng.expovariate(1 / s.T_work))

    def phase_a(s, code, bad, kind=None):
        """tsc + an admitted suite in the session's own worktree. -> 'ok'|'red'|'flake'."""
        if not code:
            yield ("sleep", NONCODE_V)
            return "ok"
        kind = kind or s.phaseA
        yield from s.run_stage("tsc", tsc_full)
        yield ("acq", s.sem_land)
        yield from s.run_stage(kind, hookfull if kind == "full" else union)
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
                    v = yield from s.phase_a(code, bad, "union")
                    if v != "ok":
                        s.rounds.append(r + 1)
                        return v
                    verified_base = base
                else:
                    k = base - verified_base
                    if code:
                        yield from s.run_stage("tsc", tsc_incr)
                        if s.rng.random() < s.pint(k):
                            yield from s.run_stage("partial", partial)
                            if s.flaked():
                                s.rounds.append(r + 1)
                                return "flake"
                    verified_base = base
                if P == "P0":
                    if code:
                        yield from s.run_stage("full", hookfull)
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
                if P == "P2":
                    full_needed = False
                yield ("sleep", s.rng.uniform(*BACKOFF))
            s.rounds.append(5)
            return "exhausted"

        if P == "PS":
            yield ("acq", s.lock, not code)  # non-code jumps the code queue if prio
            yield ("sleep", RECONCILE)
            if code:
                yield from s.run_stage("tsc", tsc_full)
                yield from s.run_stage("full", hookfull)
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

        if P == "P3":
            base = s.trunk
            yield ("sleep", RECONCILE)
            v = yield from s.phase_a(code, bad)
            if v != "ok":
                return v
            yield ("acq", s.lock, not code)
            yield ("sleep", 1.0)
            k = s.trunk - base
            if k > 0 and code:
                yield ("sleep", 1.0)
                yield from s.run_stage("tsc", tsc_incr)
                if s.rng.random() < s.pint(k):
                    yield from s.run_stage("partial", partial)
                    if s.flaked():
                        s.lock.rel(s.sim)
                        return "flake"
            yield ("sleep", PUSH_NET + CV)
            s.trunk += 1
            s.lock.rel(s.sim)
            s.rounds.append(1)
            return "landed"

        if P in ("P4", "P5"):
            base = s.trunk
            if P == "P5":
                yield ("sleep", RECONCILE)
                v = yield from s.phase_a(code, bad)
                if v != "ok":
                    return v
            t = {
                "code": code,
                "bad": bad if P == "P4" else False,
                "base": base,
                "res": None,
                "waiter": [],
            }
            s.queue.append(t)
            if s.lander_idle:
                s.sim.at(0, s.lander_idle.pop())
            yield ("wait", t["waiter"])
            s.rounds.append(1)
            return t["res"]

    # ── the combiner (P4 / P5) ───────────────────────────────────────────────
    def lander(s):
        while True:
            if not s.queue:
                yield ("wait", s.lander_idle)
                continue
            nc = [t for t in s.queue if not t["code"]]
            if s.prio and nc and s.P == "P5":  # non-code first: seconds, no suite
                for t in nc:
                    s.queue.remove(t)
                yield from s.land_batch(nc)
                continue
            batch = s.queue[: s.Bmax]
            del s.queue[: len(batch)]
            yield from s.land_batch(batch)

    def verify_batch(s, batch):
        yield ("sleep", 1.0 + 0.5 * len(batch))
        codes = [t for t in batch if t["code"]]
        if not codes:
            return "ok"
        if s.P == "P4":
            yield from s.run_stage("tsc", tsc_full)
            b = len(codes)
            yield from s.run_stage("full", lambda L: hookfull(L) * (1 + 0.15 * (b - 1)))
            if any(t["bad"] for t in codes):
                return "red"
            return "flake" if s.flaked() else "ok"
        # P5: a lone code ticket on the trunk it was verified on IS its verified tree (Phase A full)
        moved = any(t["base"] != s.trunk for t in codes) or len(batch) > 1
        if s.phaseA == "full" and not moved:
            return "ok"
        k = max(s.trunk - min(t["base"] for t in codes), 0) + len(batch) - 1
        yield from s.run_stage("tsc", tsc_incr)
        if s.full_combine:
            b = len(codes)
            yield from s.run_stage("full", lambda L: hookfull(L) * (1 + 0.15 * (b - 1)))
            return "flake" if s.flaked() else "ok"
        if s.rng.random() < s.pint(k):
            yield from s.run_stage("partial", partial)
            if s.flaked():
                return "flake"
        return "ok"

    def land_batch(s, batch):
        s.batches.append(len(batch))
        v = yield from s.verify_batch(batch)
        if v == "ok":
            yield ("sleep", PUSH_NET + CV)
            s.trunk += 1
            for t in batch:
                t["res"] = "landed"
                if t["waiter"]:
                    s.sim.at(0, t["waiter"].pop())
            return
        if len(batch) == 1:
            t = batch[0]
            t["res"] = "red" if v == "red" else "flake"
            if t["waiter"]:
                s.sim.at(0, t["waiter"].pop())
            return
        h = len(batch) // 2
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
    lc, ln, lands, cpu, rounds, batches = [], [], 0, 0.0, [], []
    for sd in range(seeds):
        w = World(P, N, Lbg, seed=1000 * sd + N, **kw)
        for i in range(N):
            w.sim.spawn(w.session(i))
        if P in ("P4", "P5"):
            w.sim.spawn(w.lander())
        w.sim.spawn(w.sampler())
        w.sim.run(hours * 3600)
        lc += w.lat_code
        ln += w.lat_nc
        lands += w.lands
        cpu += w.cpu
        rounds += w.rounds
        batches += w.batches
    al = lc + ln
    return {
        "P": P,
        "N": N,
        "Lbg": Lbg,
        "lands_h": lands / (hours * seeds),
        "p50_min": pct(al, 0.5) / 60,
        "p95_min": pct(al, 0.95) / 60,
        "max_min": (max(al) / 60) if al else 0,
        "code_p50": pct(lc, 0.5) / 60,
        "code_p95": pct(lc, 0.95) / 60,
        "nc_p50": pct(ln, 0.5) / 60,
        "nc_p95": pct(ln, 0.95) / 60,
        "over600": 100.0 * sum(1 for x in al if x > 600) / max(len(al), 1),
        "cpu_min_per_land": cpu / max(lands, 1) / 60,
        "rounds_p95": pct(rounds, 0.95),
        "mean_batch": (sum(batches) / len(batches)) if batches else float("nan"),
    }


HDR = "%-3s %3s %4s | %7s %6s %6s | %6s %6s | %6s %6s | %5s | %6s" % (
    "P",
    "N",
    "Lbg",
    "lands/h",
    "p50",
    "p95",
    "c.p50",
    "c.p95",
    "nc.p50",
    "nc.p95",
    ">10m%",
    "cpu",
)


def fmt(r):
    return (
        "%-3s %3d %4d | %7.1f %6.1f %6.1f | %6.1f %6.1f | %6.1f %6.1f | %5.0f | %6.1f"
        % (
            r["P"],
            r["N"],
            r["Lbg"],
            r["lands_h"],
            r["p50_min"],
            r["p95_min"],
            r["code_p50"],
            r["code_p95"],
            r["nc_p50"],
            r["nc_p95"],
            r["over600"],
            r["cpu_min_per_land"],
        )
    )


if __name__ == "__main__":
    kw = json.loads(sys.argv[1]) if len(sys.argv) > 1 else {}
    Ns = kw.pop("Ns", [4, 8, 15, 25, 40])
    Lbgs = kw.pop("Lbgs", [45, 150])
    Ps = kw.pop("Ps", ["P0", "P1", "P2", "PS", "P3", "P4", "P5"])
    print(
        "base grid, law=%s (minutes; c.=code, nc.=non-code, >10m%% = share of lands over the Bash tool ceiling)"
        % kw.get("law", "E")
    )
    print(HDR)
    for Lbg in Lbgs:
        for P in Ps:
            k = dict(kw)
            if P in ("P0", "P1", "P2"):
                k.setdefault("k_land", 1)
            for N in Ns:
                print(fmt(run(P, N, Lbg, **k)))
