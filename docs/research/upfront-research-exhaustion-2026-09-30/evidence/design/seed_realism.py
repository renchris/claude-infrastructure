"""seed_realism.py - what happens when seeds are NOT like the real holes, and can the round-1 data see it?
Run: python3 seed_realism.py > seed_realism.out

Scenarios (DIV8, b=0.1, K=3, s=100, stop on K dry rounds):
  matched        seeds drawn from the same law as real holes
  easy+1         seeds 1 logit easier (Musa's critique: planted defects are easier)
  easy+0.5       seeds 0.5 logit easier
  disc           real holes are SURVIVORS of a pre-freeze discovery phase (P1-P3) whose catch logit is
                 a + lam*d + N(0,sd): the holes discovery missed are the hard ones; seeds are fresh
  disc+screen    same, but candidate seeds pass through the same discovery-like pre-screen first
                 (survivor-matched seeding); seeds the pre-screen catches are discarded and rewritten
Checks available on real data at round 1:
  MW   one-sided Mann-Whitney on 'panels that caught it' among caught items, seeds vs real holes
       (flag when seeds are caught by significantly MORE panels, z > 1.645)
  Q6   Mills N (S1 / round-1 seed recall) vs Mh-jackknife-2 of the round-1 matrix; flag outside [0.5, 2]"""
import cert_sim as m

REPS = 1500
DISC = {"N_pre": 143, "a": 0.5, "lam": 1.0, "sd": 1.0}
DISC_WEAK = {"N_pre": 110, "a": 0.0, "lam": 0.5, "sd": 1.0}
rows = [
    ("matched", dict()),
    ("easy+0.5", dict(seed_shift=0.5)),
    ("easy+1", dict(seed_shift=1.0)),
    ("disc", dict(disc=DISC, N0=0)),
    ("disc+screen", dict(disc=DISC, N0=0, prescreen=True)),
    ("discweak", dict(disc=DISC_WEAK, N0=0)),
    ("discweak+scr", dict(disc=DISC_WEAK, N0=0, prescreen=True)),
]
print("# seed_realism.out  (cert_sim.py; DIV8; b=0.1; K=3; s=100; REPS=%d per row)" % REPS)
print("  scenario       N0 mean | truth left mean | mu_hat mean | n_pred95 holds (claims 95%%) | MW flag | Q6 flag | Mills/truth median | JK2/truth median")
for name, kw in rows:
    cfg = m.Cfg(s=100, pred_draws=1200, **kw)
    R = m.run(cfg, REPS, seed=41)
    print("  %-14s %5.1f   | %.2f            | %.2f        | %.1f%%                       | %4.1f%%   | %4.1f%%   | %.2f               | %.2f" % (
        name, m.mean([r["N0_total"] for r in R]), m.mean([r["res_det"] for r in R]), m.mean([r["mu"] for r in R]),
        100 * m.mean([1 if r["res_det"] <= r["npred_tot"] else 0 for r in R]),
        100 * m.mean([1 if r["mw_z"] > 1.645 else 0 for r in R]),
        100 * m.mean([1 if not (0.5 <= r["mills"] / max(r["jk2"], 1e-9) <= 2) else 0 for r in R]),
        m.pct([r["mills"] / max(r["N0_det"], 1) for r in R], .5), m.pct([r["jk2"] / max(r["N0_det"], 1) for r in R], .5)))
print("Reading: a guard that fires in ~5% of matched runs and far more often in mismatched runs has power;")
print("a mismatch the guards cannot see must be caught by the W0 backtest on historical snapshots.")
