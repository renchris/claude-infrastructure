"""synth_width.py - SYNTHESIS extension of tier_curve.out §A: one more width step (T=24, four families x six
strategies) and the max tier under 0.25 false-positive MATERIAL items per round with the build cap R_abs=16.
Same model and parameters as tier_curve.py (b=0.1, u=0.05, s=100). Run: python3 synth_width.py > synth_width.out"""
import cert_sim as m

REPS = 600
DIV24 = dict(panels=[(f, s) for f in "ABCD" for s in range(6)], corr={"D": ("A", 0.6)})
print("# synth_width.out  (cert_sim.py; b=0.1; u=0.05; s=100; REPS=%d per row)" % REPS)
ROWS = [("max      K=3,T=16", 3, m.DIV16, 0.0, 40), ("wide24   K=2,T=24", 2, DIV24, 0.0, 40),
        ("max24    K=3,T=24", 3, DIV24, 0.0, 40), ("max+fp   K=3,T=16 fp.25 cap16", 3, m.DIV16, 0.25, 16)]
for N0 in (20, 60):
    print("\n## N0=%d" % N0)
    print("  rule                          rounds p50/p90  panel-runs p50/p90 | desk-detectable left mean  P(>=1) | universally-blind left mean | stated n_pred95 median holds")
    for name, K, comp, fp, rmax in ROWS:
        R = m.run(m.Cfg(N0=N0, K=K, comp=comp, s=100, fp=fp, R_max=rmax, pred_draws=600), REPS, seed=501 + K + N0 + int(100 * fp))
        rd = [r["rounds"] for r in R]
        pr = [r["panel_runs"] for r in R]
        blind = [r.get("blind_left", float("nan")) for r in R]
        print("  %-29s %3d / %-3d       %4d / %-4d        | %.2f                      %.2f   | %-27s | %-3d %.1f%%" % (
            name, m.pct(rd, .5), m.pct(rd, .9), m.pct(pr, .5), m.pct(pr, .9),
            m.mean([r["res_det"] for r in R]), m.mean([1 if r["res_det"] >= 1 else 0 for r in R]),
            ("%.2f" % m.mean(blind)) if all(b == b for b in blind) else "n/a",
            m.pct([r["npred_tot"] for r in R], .5), 100 * m.mean([1 if r["res_det"] <= r["npred_tot"] else 0 for r in R])))
