"""P(at least one post-gate MATERIAL in-frame hole) = P(res_det + surfaced blind >= 1) at max24, vs the
certificate's printed P(>=1) which counts desk-detectable only. cert_sim.py model, synth_width params."""
import sys, random
sys.path.insert(0, "/tmp/rescomp/design")
import cert_sim as m
DIV24 = dict(panels=[(f, s) for f in "ABCD" for s in range(6)], corr={"D": ("A", 0.6)})
for N0 in (20, 60):
    R = m.run(m.Cfg(N0=N0, K=3, comp=DIV24, s=100, fp=0.0, R_max=14, pred_draws=400), 300, seed=4242 + N0)
    rng = random.Random(5)
    out = []
    for f in (1.0, 0.5):
        any_ = sum(1 for r in R if r["res_det"] + sum(1 for _ in range(r["blind_left"]) if rng.random() < f) >= 1) / len(R)
        out.append("f=%.1f P(>=1 post-gate in-frame MATERIAL)=%.2f" % (f, any_))
    print("N0=%d printed P(>=1) median %.2f | desk-only actual %.2f | %s" % (
        N0, m.pct([r["p_any"] for r in R], .5), m.mean([1 if r["res_det"] >= 1 else 0 for r in R]), " | ".join(out)))
