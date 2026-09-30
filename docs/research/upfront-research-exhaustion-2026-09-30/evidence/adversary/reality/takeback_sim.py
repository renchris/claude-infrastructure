"""takeback_sim.py - adversary check: does the take-back rule (§8.3: escapes > n_pred95) fire on the
protocol's OWN declared residual? cert_sim.py model, max24 composition, same params as synth_width.py.
An escape at build = a residual desk-detectable hole OR a universally-blind hole that build/contact
surfaces (fraction f). Also: fp>0 rows, where dry rounds are rarer and stop=cap dominates."""
import sys, random
sys.path.insert(0, "/tmp/rescomp/design")
import cert_sim as m
REPS = 400
DIV24 = dict(panels=[(f, s) for f in "ABCD" for s in range(6)], corr={"D": ("A", 0.6)})
print("# takeback_sim.out (max24 K=3 T=24; b=0.1 u=0.05 s=100; REPS=%d)" % REPS)
for N0 in (20, 60):
    for fp in (0.0, 0.25, 1.0, 2.0):
        R = m.run(m.Cfg(N0=N0, K=3, comp=DIV24, s=100, fp=fp, R_max=14, pred_draws=600), REPS, seed=777 + N0 + int(10*fp))
        rng = random.Random(9)
        line = []
        for f in (1.0, 0.5, 0.25):
            tb = 0
            for r in R:
                surf = sum(1 for _ in range(r["blind_left"]) if rng.random() < f)
                if r["res_det"] + surf > r["npred_tot"]:
                    tb += 1
            line.append("f=%.2f P(take-back)=%.2f" % (f, tb / len(R)))
        cap = sum(1 for r in R if r["status"] == "timeout") / len(R)
        print("N0=%d fp=%.2f  stop=cap %.2f  rounds p50/p90 %d/%d  npred95 median %d  blind mean %.2f | %s" % (
            N0, fp, cap, m.pct([r["rounds"] for r in R], .5), m.pct([r["rounds"] for r in R], .9),
            m.pct([r["npred_tot"] for r in R], .5), m.mean([r["blind_left"] for r in R]), " | ".join(line)))
