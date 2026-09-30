"""tier_curve.py - the price curve: what each stop rule costs and what it leaves, plus the resolution the
seed count buys and the terminating gate. Run: python3 tier_curve.py > tier_curve.out
All rows: DIV8/DIV16, b=0.1, u=0.05, carried s seeds + shadow seeds."""
import cert_sim as m

REPS = 1000
print("# tier_curve.out  (cert_sim.py; b=0.1; u=0.05; REPS=%d per row)" % REPS)
RULES = [("K=2,T=8", 2, m.DIV8), ("K=3,T=8", 3, m.DIV8), ("K=4,T=8", 4, m.DIV8),
         ("K=2,T=16", 2, m.DIV16), ("K=3,T=16", 3, m.DIV16), ("K=4,T=16", 4, m.DIV16)]
for N0 in (20, 60):
    print("\n## A  Stop on K dry rounds alone; N0=%d; s=100" % N0)
    print("  rule       rounds p50/p90  panel-runs p50/p90 | desk-detectable left mean  P(>=1) | stated n_pred95 median  holds | stated P(>=1) mean")
    for name, K, comp in RULES:
        R = m.run(m.Cfg(N0=N0, K=K, comp=comp, s=100, pred_draws=800), REPS, seed=51 + K + N0)
        rd = [r["rounds"] for r in R]
        pr = [r["panel_runs"] for r in R]
        print("  %-10s %3d / %-3d       %4d / %-4d        | %.2f                      %.2f   | %-3d                     %.1f%% | %.2f" % (
            name, m.pct(rd, .5), m.pct(rd, .9), m.pct(pr, .5), m.pct(pr, .9),
            m.mean([r["res_det"] for r in R]), m.mean([1 if r["res_det"] >= 1 else 0 for r in R]),
            m.pct([r["npred_tot"] for r in R], .5), 100 * m.mean([1 if r["res_det"] <= r["npred_tot"] else 0 for r in R]),
            m.mean([r["p_any"] for r in R])))

print("\n## B  Resolution the seed count buys (K=3, T=8, N0=60 and N0=20): the stated bound after the gate")
print("  N0  s    | stated n_pred95 median | stated P(>=1) mean | true P(>=1) | seeds left mean")
for N0 in (60, 20):
    for s in (60, 100, 200, 300):
        R = m.run(m.Cfg(N0=N0, s=s, pred_draws=800), 600, seed=61 + s + N0)
        print("  %-3d %-4d | %-22d | %.2f               | %.2f        | %.2f" % (
            N0, s, m.pct([r["npred_tot"] for r in R], .5), m.mean([r["p_any"] for r in R]),
            m.mean([1 if r["res_det"] >= 1 else 0 for r in R]), m.mean([r["seeds_left"] for r in R])))

print("\n## C  The terminating gate: K dry rounds AND mu_hat <= target, at most R_ext=2 extension rounds, then an")
print("     operator decision (never an open loop). K=3, T=8, s=100.")
print("  N0  target | ends at gate  ends in decision | rounds p50/p90 | desk-detectable left mean")
for N0 in (20, 60):
    for tgt in (2.0, 1.0, 0.5):
        R = m.run(m.Cfg(N0=N0, s=100, mu_target=tgt, R_ext=2, pred_draws=200), 600, seed=71 + N0 + int(10 * tgt))
        rd = [r["rounds"] for r in R]
        print("  %-3d %-6.1f | %5.1f%%        %5.1f%%          | %3d / %-3d      | %.2f" % (
            N0, tgt, 100 * m.mean([1 if r["status"] == "gate" else 0 for r in R]),
            100 * m.mean([1 if r["status"] == "decision" else 0 for r in R]), m.pct(rd, .5), m.pct(rd, .9),
            m.mean([r["res_det"] for r in R])))

print("\n## D  False positives that pass verification, and the hard cap R_max (K=3, T=8, s=100, N0=60)")
print("     A false MATERIAL item breaks a dry run exactly like a real one. stop = K dry rounds OR r = R_max.")
print("  fp/round  R_max | rounds p50/p90 | stopped by cap | desk-detectable left: dry-stopped  cap-stopped | stated n_pred95 holds")
for fp in (0.0, 0.1, 0.25, 0.5):
    for rmax in (12, 40):
        R = m.run(m.Cfg(N0=60, s=100, fp=fp, R_max=rmax, pred_draws=600), 600, seed=81 + int(100 * fp) + rmax)
        rd = [r["rounds"] for r in R]
        dryR = [r["res_det"] for r in R if r["status"] == "gate"]
        capR = [r["res_det"] for r in R if r["status"] == "timeout"]
        print("  %-8.2f  %-5d | %3d / %-3d      | %5.1f%%         | %.2f (n=%d)            %s        | %.1f%%" % (
            fp, rmax, m.pct(rd, .5), m.pct(rd, .9), 100 * len(capR) / len(R), m.mean(dryR), len(dryR),
            ("%.2f (n=%d)" % (m.mean(capR), len(capR))) if capR else "  -       ",
            100 * m.mean([1 if r["res_det"] <= r["npred_tot"] else 0 for r in R])))

print("\n## E  Seed orphaning: fixes rewrite a seed's anchor, the seed is censored (removed from the denominator)")
print("  orphan/fix | seeds orphaned mean | stated n_pred95 median | holds")
for o in (0.0, 0.004, 0.01):
    R = m.run(m.Cfg(N0=60, s=100, orphan=o, pred_draws=600), 600, seed=91 + int(1000 * o))
    print("  %-10.3f | %-19.1f | %-22d | %.1f%%" % (o, m.mean([r["orphaned"] for r in R]), m.pct([r["npred_tot"] for r in R], .5),
          100 * m.mean([1 if r["res_det"] <= r["npred_tot"] else 0 for r in R])))
