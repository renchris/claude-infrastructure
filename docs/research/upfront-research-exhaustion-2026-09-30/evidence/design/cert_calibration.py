"""cert_calibration.py - does the certificate's stated bound hold? End-planted fresh seeds (the naive design)
vs carried seeds (the chosen design). Run: python3 cert_calibration.py > cert_calibration.out

Truth = desk-detectable material holes left at the gate (original + fix-born; universally blind excluded,
because the certificate declares that mass rather than estimating it).
Naive bound: fresh seeds planted on the final snapshot; recall R over the K dry rounds; 'no real hole caught
in K rounds' => residual n satisfies (1-R)^n >= 0.05 => n <= ln(0.05)/ln(1-R). Two variants: R point, and
R's Clopper-Pearson lower bound.
Carried bound: n_pred95 = 95% posterior-predictive quantile of the residual from carried + shadow seeds."""
import math
from dataclasses import replace
import cert_sim as m

REPS = 1500


def naive(n_caught, n_planted, use_lo):
    if n_planted == 0:
        return 0
    R = m.cp_lower(n_caught, n_planted) if use_lo else n_caught / n_planted
    if R <= 0:
        return float("inf")
    if R >= 1:
        return 0
    return math.floor(math.log(0.05) / math.log(1 - R))


print("# cert_calibration.out  (cert_sim.py; DIV8; K=3; stop on K dry rounds; REPS=%d per row)" % REPS)
print("  claimed confidence of every bound below: 95%")
print("  N0  b    fresh  | naive(point) holds  naive(CP-lower) holds | carried n_pred95 holds  median stated | fresh recall median")
for N0 in (20, 60):
    for b in (0.1, 0.3):
        cfg = m.Cfg(N0=N0, b=b, s=60, fresh_end=20, pred_draws=1000)
        R = m.run(cfg, REPS, seed=21 + N0 + int(10 * b))
        h1 = m.mean([1 if r["res_det"] <= naive(r["fresh_caught"], r["fresh_planted"], False) else 0 for r in R])
        h2 = m.mean([1 if r["res_det"] <= naive(r["fresh_caught"], r["fresh_planted"], True) else 0 for r in R])
        h3 = m.mean([1 if r["res_det"] <= r["npred_tot"] else 0 for r in R])
        rec = [r["fresh_caught"] / r["fresh_planted"] for r in R if r["fresh_planted"]]
        print("  %-3d %.1f  20     |  %.1f%%              %.1f%%                  |  %.1f%%                  %d               |  %.2f" % (
            N0, b, 100 * h1, 100 * h2, 100 * h3, m.pct([r["npred_tot"] for r in R], .5), m.pct(rec, .5)))
print("  Reading: fresh end-seeds measure recall on YOUNG holes; the residual is SURVIVORS of several rounds,")
print("  so the naive bound overstates recall on exactly the holes that remain. Carried seeds survive the same filter.")
