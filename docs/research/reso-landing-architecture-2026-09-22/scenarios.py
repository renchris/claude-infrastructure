#!/usr/bin/env python3
"""scenarios.py — every model table in ../reso-landing-architecture-2026-09-22.md beyond landsim.py's base grid.

  python3 scenarios.py            # all sections (~1 min, pure CPU, no I/O)
  python3 scenarios.py validate   # one section: validate | sensitivity | admission | fullsuite | phases
"""
import importlib.util, os, sys
here = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location('ls', os.path.join(here, 'landsim.py'))
ls = importlib.util.module_from_spec(spec); spec.loader.exec_module(ls)
U, H, TF = ls.union, ls.hookfull, ls.tsc_full
def reset(pf=0.4, tf=0.3):
    ls.union = U; ls.partial = lambda L: pf * U(L); ls.tsc_incr = lambda L: tf * TF(L)
def row(tag, r): print('%-6s | %7.1f %7.1f %7.1f | %8.1f' % (tag, r['lands_h'], r['p50_min'], r['p95_min'], r['cpu_min_per_land']))
HDR = '%-6s | %7s %7s %7s | %8s' % ('cell', 'lands/h', 'p50min', 'p95min', 'cpu/land')

def validate():
    print('\n== VALIDATE: today (P0) at the SHIPPED admission K=1; measured: 92% one-round lands, unit p95 48 min, max 82 min')
    print('%3s %4s | %9s %7s %7s %7s %9s' % ('N', 'Lbg', '1-round%', 'p50min', 'p95min', 'maxmin', 'lands/h'))
    reset()
    for Lbg in (45, 100):
        for N in (2, 3, 4, 6, 8):
            rounds, lat, lands = [], [], 0
            for sd in range(4):
                w = ls.World('P0', N, Lbg, seed=77 * sd + N, k_land=1)
                for i in range(N): w.sim.spawn(w.session(i))
                w.sim.spawn(w.sampler()); w.sim.run(48 * 3600)
                rounds += w.rounds; lat += w.lat; lands += w.lands
            one = sum(1 for r in rounds if r == 1) / max(len(rounds), 1)
            print('%3d %4d | %8.0f%% %7.1f %7.1f %7.1f %9.1f' % (N, Lbg, 100 * one, ls.pct(lat, .5) / 60, ls.pct(lat, .95) / 60, max(lat) / 60, lands / 192))

def sensitivity():
    print('\n== SENSITIVITY (background 150, K=2): q = P(incoming commit intersects), pf = partial/union, tf = incr/full tsc'); print(HDR)
    for q, pf, tf in [(0.1, .4, .3), (0.3, .4, .3), (0.6, .4, .3), (1.0, .4, .3), (1.0, 1.0, 1.0)]:
        reset(pf, tf)
        for P in ('P2', 'P3', 'P5'):
            for N in (15, 25, 40): row('%s%d q%.1f pf%.1f tf%.1f' % (P, N, q, pf, tf), ls.run(P, N, 150, hours=48, seeds=3, q=q))
    reset()
    for P in ('P0', 'P1', 'P2', 'P3', 'P4', 'P5'):
        for N in (15, 25): row('%s%d T15' % (P, N), ls.run(P, N, 150, hours=48, seeds=3, T_work=900))
    for P in ('P2', 'P3', 'P4', 'P5'):
        for N in (15, 25): row('%s%d flake.10' % (P, N), ls.run(P, N, 150, hours=48, seeds=3, p_flake=0.10))

def admission():
    print('\n== ADMISSION WIDTH K of cc-sem reso-land (shipped: K=1), background 150'); print(HDR)
    reset()
    for P in ('P0', 'P1', 'P3', 'P5'):
        for N in (8, 15, 25, 40):
            for K in (1, 2, 3): row('%s%d K%d' % (P, N, K), ls.run(P, N, 150, hours=48, seeds=3, k_land=K))

def fullsuite():
    print('\n== FULL SUITE ONCE (C11: the hook may skip only on a full-suite token), background 150'); print(HDR)
    for K in (1, 2, 3):
        for N in (8, 15, 25, 40):
            reset(); ls.union = H
            row('P1f%d K%d' % (N, K), ls.run('P1', N, 150, hours=48, seeds=3, k_land=K))
            for tf in (0.3, 1.0):
                reset(tf=tf); ls.partial = H
                row('P5f%d K%d tf%.1f' % (N, K, tf), ls.run('P5', N, 150, hours=48, seeds=3, k_land=K, q=1.0))

def phases():
    print('\n== THE PLAN\'S THREE STATES, background 150: PS = Phase 2 serialized lane · P5f = Phase 3 combiner · P5 = Phase 4 pruning'); print(HDR)
    for Tw in (2700, 1800, 900):
        for N in (8, 15, 25, 40):
            reset(); row('PS%d T%d' % (N, Tw // 60), ls.run('PS', N, 150, hours=48, seeds=3, T_work=Tw))
            reset(); ls.partial = H; row('P5f%d T%d' % (N, Tw // 60), ls.run('P5', N, 150, hours=48, seeds=3, T_work=Tw, k_land=2, q=1.0))
            reset(); row('P5%d T%d' % (N, Tw // 60), ls.run('P5', N, 150, hours=48, seeds=3, T_work=Tw, k_land=2, q=0.3))

SECTIONS = {'validate': validate, 'sensitivity': sensitivity, 'admission': admission, 'fullsuite': fullsuite, 'phases': phases}
for name in (sys.argv[1:] or SECTIONS): SECTIONS[name]()
