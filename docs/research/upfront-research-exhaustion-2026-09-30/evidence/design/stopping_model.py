"""stopping_model.py - stopping behavior of the certification loop (reads cert_sim.py).
Run: python3 stopping_model.py > stopping_model.out
Sections: 1 null-run arithmetic; 2 panel composition; 3 round-1 population estimators;
4 fix-born rate b (convergence and divergence); 5 found-per-round shape under b."""
import math
from dataclasses import replace
import cert_sim as m

REPS = 1000


def line(*a):
    print(*a, flush=True)


line("# stopping_model.out  (cert_sim.py; REPS=%d per row; DIV8 = Opus x2, codex x2, gemini x2, Opus/Fable x2 rho 0.6)" % REPS)

line("\n## 1 Null-run arithmetic (exact): 95% upper bound on a miss rate after 0 misses in s seeds = 1-0.05^(1/s)")
for s in (10, 20, 30, 60, 100, 200, 300):
    line("  s=%-4d bound=%.4f   (rule of three 3/s=%.4f)" % (s, 1 - 0.05 ** (1 / s), 3 / s))
for F in (20, 60):
    s_mean = 10 * (F + 1) - 1                      # (F+1) * 0.5/(s+1) <= 0.05, all seeds caught, Jeffreys mean
    s_conf = next(s for s in range(1, 100000) if (F + 1) * (1 - 0.05 ** (1 / s)) <= 0.05)
    line("  'P(>=1 desk-detectable hole left) <= 5%%' with F=%d real holes found: s >= %d seeds all caught (posterior mean), "
         "s >= %d (95%% confidence)" % (F, s_mean, s_conf))

line("\n## 2 Panel composition (N0=60, u=0.05, b=0.1, K=3, stop on K dry rounds alone, s=60 carried seeds)")
line("  comp     rounds p50/p90   panel-runs p50/p90   desk-detectable left: mean  P(>=1)   universally-blind left: mean")
for name, comp in (("SAME8", m.SAME8), ("DIV8", m.DIV8), ("DIV8IND", m.DIV8IND), ("DIV16", m.DIV16)):
    R = m.run(m.Cfg(comp=comp, pred_draws=200), REPS, seed=11)
    rd = [r["rounds"] for r in R]
    pr = [r["panel_runs"] for r in R]
    line("  %-8s %4d / %-4d        %4d / %-4d            %.2f        %.2f          %.2f" % (
        name, m.pct(rd, .5), m.pct(rd, .9), m.pct(pr, .5), m.pct(pr, .9),
        m.mean([r["res_det"] for r in R]), m.mean([1 if r["res_det"] >= 1 else 0 for r in R]),
        m.mean([r["blind_left"] for r in R])))

line("\n## 3 Round-1 population estimates vs truth (desk-detectable holes at the first freeze), medians [P10, P90]")
for name, comp in (("SAME8", m.SAME8), ("DIV8", m.DIV8), ("DIV16", m.DIV16)):
    R = m.run(m.Cfg(comp=comp, pred_draws=50), REPS, seed=12)
    f = lambda k: "%.1f [%.1f, %.1f]" % (m.pct([r[k] for r in R], .5), m.pct([r[k] for r in R], .1), m.pct([r[k] for r in R], .9))
    line("  %-6s truth %s | S_obs %s | Chao2-bc %s | JK2 %s | Mills(seeds) %s" % (
        name, f("N0_det"), f("S1"), f("chao2"), f("jk2"), f("mills")))

line("\n## 4 Fix-born rate b (DIV8, N0=60, K=3, R_max=40): convergence needs q = 1 - R(1-b) < 1, i.e. b < 1")
line("  b      rounds p50/p90   no stop (R_max=40 or >800 live)   desk-detectable left mean   fix-born holes born mean")
for b in (0.0, 0.1, 0.3, 0.6, 0.9, 1.0, 1.2):
    R = m.run(m.Cfg(b=b, R_max=40, cap_live=800, pred_draws=50), 400 if b < 0.9 else 100, seed=13)
    rd = [r["rounds"] for r in R]
    line("  %-5.1f  %4d / %-4d        %5.1f%%               %.2f                       %.1f" % (
        b, m.pct(rd, .5), m.pct(rd, .9), 100 * m.mean([1 if r["status"] in ("timeout", "diverged") else 0 for r in R]),
        m.mean([r["res_det"] for r in R]), m.mean([r["fb_born"] for r in R])))

line("\n## 5 Found-per-round shape (mean over programs, rounds 1-8): what the lead SEES before any estimator")
for b in (0.1, 0.6, 1.2):
    R = m.run(m.Cfg(b=b, R_max=40, cap_live=800, pred_draws=50), 400 if b < 0.9 else 100, seed=14)
    cols = []
    for i in range(8):
        cols.append("%.1f" % m.mean([r["found"][i] if i < len(r["found"]) else 0 for r in R]))
    line("  b=%.1f  %s" % (b, "  ".join(cols)))
line("  Reading: at b>=1 the per-round count stops falling (the 23/21/24/28 critic loop, 7c395da7 15:58:52Z);")
line("  the diagnostic is the ratio of consecutive round counts, observable from round 2.")
