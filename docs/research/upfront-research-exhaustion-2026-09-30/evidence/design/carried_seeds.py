"""carried_seeds.py - calibration and resolution of the carried-seed estimators vs seed count s.
Run: python3 carried_seeds.py > carried_seeds.out
Estimators (original population; truth = desk-detectable original holes left at the gate):
  mu_hat  = F*pi~/(1-pi~), pi~ = (k_left+.5)/(s+1)                      point estimate
  mu_up   = F*pi_up/(1-pi_up), pi_up = one-sided Clopper-Pearson          bound on the MEAN residual
  n_pred95 (flat)  = 95% quantile, pi~Beta(k+.5, s-k+.5), R|pi ~ NegBin(F+1, 1-pi)   stated bound
  n_pred95 (scale) = same with NegBin(F, 1-pi)
Total = original + fix-born (shadow seeds, one per fix)."""
import cert_sim as m

REPS = 1000
print("# carried_seeds.out  (cert_sim.py; DIV8; b=0.1; K=3; stop on K dry rounds; REPS=%d per row)" % REPS)
for N0 in (60, 20):
    print("\n## N0 = %d real material holes at the first freeze" % N0)
    print("  s    | truth left mean | mu_hat mean | mu_up holds | n_pred95 flat holds  median | scale holds | total n_pred95 holds  median | stated P(>=1) mean vs true P(>=1)")
    for s in (20, 40, 60, 100, 200, 300):
        R = m.run(m.Cfg(N0=N0, s=s, pred_draws=800), REPS, seed=31 + s + N0)
        t = [r["res_orig"] for r in R]
        print("  %-4d | %.2f            | %.2f        | %.1f%%       | %.1f%%               %-3d | %.1f%%      | %.1f%%                 %-3d    | %.2f vs %.2f" % (
            s, m.mean(t), m.mean([r["mu_o"] for r in R]),
            100 * m.mean([1 if r["res_orig"] <= r["mu_up_o"] else 0 for r in R]),
            100 * m.mean([1 if r["res_orig"] <= r["npred_o"] else 0 for r in R]), m.pct([r["npred_o"] for r in R], .5),
            100 * m.mean([1 if r["res_orig"] <= r["npred_o_scale"] else 0 for r in R]),
            100 * m.mean([1 if r["res_det"] <= r["npred_tot"] else 0 for r in R]), m.pct([r["npred_tot"] for r in R], .5),
            m.mean([r["p_any"] for r in R]), m.mean([1 if r["res_det"] >= 1 else 0 for r in R])))
print("\nReading: the stated bound (n_pred95, flat prior) must hold >= 95%; its median width is the price of s.")
