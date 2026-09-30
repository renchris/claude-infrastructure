"""forecast_check.py - is the round-1 forecast of the timeline trustworthy? Run: python3 forecast_check.py > forecast_check.out

For each test program: read only what round 1 reveals (JK2 of the round-1 matrix, round-1 carried-seed recall),
then forecast the number of rounds to the gate two ways:
  closed form   ceil(ln(N0_hat)/ln(1/q)) + K,  q = 1 - R1*(1 - b_prior)
  simulation    invert R1 -> alpha through a calibration table, simulate 150 programs with N0 = JK2,
                b = b_prior, report p50/p90 (this is what `cc-research forecast` would run)
Truth variants: 'spec' = the forecast model's own law; 'misspec' = heavier heterogeneity and a higher b
than the forecast assumes (sd_d 1.6, sd_f 1.3, b 0.25 vs the prior 0.1)."""
import math
import random
from dataclasses import replace
import cert_sim as m

B_PRIOR = 0.1
K = 3


def calib_table():
    tab = []
    a = -3.0
    while a <= 1.01:
        R = m.run(m.Cfg(alpha=a, N0=5, s=200, pred_draws=10, R_max=1), 12, seed=int(1000 + 100 * a))
        tab.append((a, m.mean([r["R1_seed"] for r in R])))
        a += 0.25
    return tab


def invert(tab, r1):
    if r1 <= tab[0][1]:
        return tab[0][0]
    for (a0, y0), (a1, y1) in zip(tab, tab[1:]):
        if y0 <= r1 <= y1:
            return a0 + (a1 - a0) * (r1 - y0) / max(1e-9, (y1 - y0))
    return tab[-1][0]


tab = calib_table()
print("# forecast_check.out  (cert_sim.py; DIV8; K=3; s=60; stop on K dry rounds)")
print("  calibration table alpha -> mean round-1 seed recall: " + ", ".join("%.2f:%.2f" % x for x in tab[::2]))
for name, kw in (("spec", dict()), ("misspec", dict(sd_d=1.6, sd_f=1.3, b=0.25))):
    rng = random.Random(81)
    truth_cfg = m.Cfg(s=60, K=K, pred_draws=20, **kw)
    n_test = 150
    in90 = in_cf = 0
    in92 = in94 = 0
    err50, errcf = [], []
    actual_all = []
    for i in range(n_test):
        r = m.program(rng, truth_cfg)
        actual = r["rounds"]
        actual_all.append(actual)
        n0 = max(1.0, r["jk2"])
        q = 1 - r["R1_seed"] * (1 - B_PRIOR)
        cf = math.ceil(math.log(n0) / math.log(1 / q)) + K if 0 < q < 1 else 99
        a_hat = invert(tab, r["R1_seed"])
        F = m.run(m.Cfg(alpha=a_hat, N0=int(round(n0)), u=0.0, b=B_PRIOR, s=0, shadow=False, K=K, pred_draws=5), 150, seed=9000 + i)
        fr = [x["rounds"] for x in F]
        p50, p90 = m.pct(fr, .5), m.pct(fr, .9)
        in90 += 1 if actual <= p90 else 0
        in92 += 1 if actual <= p90 + 2 else 0
        in94 += 1 if actual <= p90 + 4 else 0
        in_cf += 1 if actual <= cf else 0
        err50.append(actual - p50)
        errcf.append(actual - cf)
    print("\n## truth=%s  (actual rounds p50/p90 = %d/%d)" % (name, m.pct(actual_all, .5), m.pct(actual_all, .9)))
    print("  simulation forecast: actual <= forecast p90 in %.1f%% of programs; actual - p50: median %+d, P10 %+d, P90 %+d" % (
        100 * in90 / n_test, m.pct(err50, .5), m.pct(err50, .1), m.pct(err50, .9)))
    print("  timebox coverage:    actual <= p90+2 in %.1f%%, actual <= p90+4 in %.1f%%" % (100 * in92 / n_test, 100 * in94 / n_test))
    print("  closed form:         actual <= forecast in %.1f%% of programs; actual - forecast: median %+d, P10 %+d, P90 %+d" % (
        100 * in_cf / n_test, m.pct(errcf, .5), m.pct(errcf, .1), m.pct(errcf, .9)))
print("\nReading: the round-1 forecast is a plan, not a promise; the timebox R_max = forecast p90 + 2 absorbs model error")
print("of the size in the 'misspec' row, and every later round re-forecasts from observed counts.")
