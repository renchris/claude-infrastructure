#!/usr/bin/env python3
"""scenarios.py — every model table in ../reso-landing-architecture-2026-09-22.md (landsim v2).

  python3 scenarios.py            # all sections (a few minutes, pure CPU, no I/O)
  python3 scenarios.py phases     # one section: validate | phases | keyed | sensitivity | admission | law

All cells: 48 simulated hours x 3 seeds, background load 150 unless stated. v2 defaults (landsim.py
docstring): E's interference law, full-suite Phase A, non-code priority. v1 of this model is in the
commit that first landed this directory; its numbers were superseded after the wave-2 red-team.
"""

import importlib.util, os, sys

here = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("ls", os.path.join(here, "landsim.py"))
ls = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ls)
H0, U0, TF0 = ls.hookfull, ls.union, ls.tsc_full


def suite_factor(f):  # B9 keying: shell-out specs keyed out => suites at f x
    ls.hookfull = lambda L: f * H0(L)
    ls.union = lambda L: f * U0(L)


def show(tag, r):
    r = dict(r)
    r["P"] = tag[:3]
    print(ls.fmt(r), " ", tag)


def validate():
    print(
        "\n== VALIDATE today (P0, shipped K=1, law=E): measured 92% one-round lands, unit p95 48 min, max 82 min"
    )
    print(
        "%3s %4s | %9s %7s %7s %7s %9s"
        % ("N", "Lbg", "1-round%", "p50min", "p95min", "maxmin", "lands/h")
    )
    suite_factor(1.0)
    for Lbg in (45, 100):
        for N in (2, 3, 4, 6, 8):
            rounds, lat, lands = [], [], 0
            for sd in range(4):
                w = ls.World("P0", N, Lbg, seed=77 * sd + N, k_land=1, prio=False)
                for i in range(N):
                    w.sim.spawn(w.session(i))
                w.sim.spawn(w.sampler())
                w.sim.run(48 * 3600)
                rounds += w.rounds
                lat += w.lat_code + w.lat_nc
                lands += w.lands
            one = 100.0 * sum(1 for r in rounds if r == 1) / max(len(rounds), 1)
            print(
                "%3d %4d | %8.0f%% %7.1f %7.1f %7.1f %9.1f"
                % (
                    N,
                    Lbg,
                    one,
                    ls.pct(lat, 0.5) / 60,
                    ls.pct(lat, 0.95) / 60,
                    max(lat) / 60,
                    lands / 192,
                )
            )


CELLS = (
    ("P0", dict(k_land=1, prio=False), "P0 today"),
    ("PS", dict(prio=True), "PS Phase 2 lane"),
    ("P5", dict(full_combine=True), "P5f Phase 3 combiner"),
    ("P5", dict(full_combine=False), "P5 Phase 4 pruned"),
    ("P4", dict(), "P4 enqueue-unverified"),
)


def phases():
    print("\n== THE PLAN'S STATES (suites at 1.0x, i.e. before B9 keying)")
    print(ls.HDR)
    suite_factor(1.0)
    for Tw in (2700, 1800):
        for N in (8, 15, 25, 40):
            for P, kw, tag in CELLS:
                show("%s T%d" % (tag, Tw // 60), ls.run(P, N, 150, T_work=Tw, **kw))


def keyed():
    print(
        "\n== WITH B9 KEYING (Phase 2e: shell-out specs keyed on inputs, suites at 0.6x)"
    )
    print(ls.HDR)
    suite_factor(0.6)
    for Tw in (2700, 1800, 900):
        for N in (8, 15, 25, 40):
            for P, kw, tag in CELLS[1:4]:
                show(
                    "%s T%d keyed" % (tag, Tw // 60), ls.run(P, N, 150, T_work=Tw, **kw)
                )
    suite_factor(1.0)


def sensitivity():
    print(
        "\n== PRUNING SENSITIVITY (P5 pruned, keyed 0.6x, T30): q, partial-run fraction pf, incr-tsc fraction tf"
    )
    print(ls.HDR)
    suite_factor(0.6)
    for q, pf, tf in (
        (0.1, 0.4, 0.3),
        (0.42, 0.4, 0.3),
        (0.72, 0.4, 0.3),
        (1.0, 0.4, 0.3),
        (1.0, 1.0, 1.0),
    ):
        ls.partial = lambda L, pf=pf: pf * ls.union(L)
        ls.tsc_incr = lambda L, tf=tf: tf * TF0(L)
        for N in (15, 25, 40):
            show(
                "P5 q%.2f pf%.1f tf%.1f" % (q, pf, tf),
                ls.run("P5", N, 150, T_work=1800, q=q, full_combine=False),
            )
    ls.partial = lambda L: 0.4 * ls.union(L)
    ls.tsc_incr = lambda L: 0.3 * TF0(L)
    for fl in (0.03, 0.10):
        for P, kw, tag in CELLS[1:]:
            show(
                "%s flake%.2f keyed" % (tag, fl),
                ls.run(P, 15, 150, T_work=1800, p_flake=fl, **kw),
            )
    suite_factor(1.0)


def admission():
    print(
        "\n== PHASE A ADMISSION WIDTH K (P5f, keyed 0.6x, T30); reso ships reso-land K=1"
    )
    print(ls.HDR)
    suite_factor(0.6)
    for N in (15, 25, 40):
        for K in (1, 2, 3):
            show(
                "P5f K%d keyed" % K,
                ls.run("P5", N, 150, T_work=1800, k_land=K, full_combine=True),
            )
    suite_factor(1.0)


def law():
    print(
        "\n== LOAD LAW: v1 (load1 term only) vs E (measured +45/+49 s per other concurrent suite), T30, 1.0x"
    )
    print(ls.HDR)
    suite_factor(1.0)
    for lw in ("load", "E"):
        for N in (15, 40):
            for P, kw, tag in CELLS[1:4]:
                show(
                    "%s law=%s" % (tag, lw),
                    ls.run(P, N, 150, T_work=1800, law=lw, **kw),
                )


SECTIONS = {
    "validate": validate,
    "phases": phases,
    "keyed": keyed,
    "sensitivity": sensitivity,
    "admission": admission,
    "law": law,
}
for name in sys.argv[1:] or SECTIONS:
    SECTIONS[name]()
