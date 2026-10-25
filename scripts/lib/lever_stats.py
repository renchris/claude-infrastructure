#!/usr/bin/env python3
"""lever_stats.py — the usage-lever scorer's statistics (docs/plans/USAGE_LEVERS.md § W7+ §2
"Common to all four levers", "Shared guards", "Plumbing gate"; §3 row "Scorer"; wave S5).

PORTS, with the source each reproduces (the receipts live under
~/.claude/hillclimb/_imports/lev-design/ and docs/research/usage-levers-2026-10-23/
telemetry-design-2026-10-24/scripts/):
  mde()            option-c-staged-canary/stage_mde.py mde(): fleet pp/wk at 80% power, two-sided 5%
  event_mde()      noise-floor/scripts/eventmde.py summ(): per-event SD → pp/wk at a 50/50 split
  ols_resid_var()  noise-floor/scripts/cuped.py (and cuped_strict.py, its one-covariate form)
  ratio(), cv(), week_mdes(), aa_ratio_mde()   noise-floor/scripts/stats.py
  meter_consumption()                          noise-floor/scripts/meter.py
  wilson(), wilson_n_min(), poisson_sf()       stage_mde.py's compliance and PTL arithmetic

NEW (the plan's rules, no earlier code):
  cluster_bootstrap_diff()  savings per event (ctrl mean − treat mean), sessions resampled whole
                            within their account stratum; its SD is the CI's scale
  cluster_robust_diff()     the same estimate with an analytic stratified CR1 variance (fast; the
                            A/A and the guards use it)
  pseudo_salt_aa()          re-randomize units 50/50 by sha256(salt:i:unit), --reps times; FPR at
                            |z| >= 1.96 must sit in [2%, 8%]
  cuped()                   theta = cov(y, x) / var(x), pooled over both arms
  srm_p(), chi2_sf(), contingency_p()          sample-ratio mismatch, arm x account
  ks_2samp(), smd()         covariate balance: KS p >= 0.05 and |SMD| < 0.1
  hp_bound()                Haybittle-Peto: |z| >= 3.0 at an interim look, 1.96 at the final
  holm()                    Holm step-down over a family of one-sided p-values
  newcombe()                Newcombe hybrid-score CI for p1 − p2 (method 10)

Stdlib only, Python 3.9-safe, deterministic: every random draw is seeded or hash-derived.
"""

import hashlib
import math
import random

Z975 = 1.959964
Z80 = 0.841621
ZPOW = Z975 + Z80  # 80% power, two-sided 5%: the 2.80 every MDE in the plan uses
HP_INTERIM = 3.0
HP_FINAL = Z975
AA_BAND = (0.02, 0.08)


# ── normal / chi-square / Poisson ──────────────────────────────────────────────────────────────
def norm_cdf(x):
    return 0.5 * math.erfc(-x / math.sqrt(2.0))


def norm_sf(x):
    return 0.5 * math.erfc(x / math.sqrt(2.0))


def norm_ppf(p):
    """Inverse normal CDF by bisection (exact to 1e-10; called a handful of times per run)."""
    if not 0.0 < p < 1.0:
        raise ValueError("p must be in (0, 1)")
    lo, hi = -40.0, 40.0
    for _ in range(200):
        mid = (lo + hi) / 2
        if norm_cdf(mid) < p:
            lo = mid
        else:
            hi = mid
    return (lo + hi) / 2


def _gammainc_upper_reg(a, x):
    """Q(a, x), the regularized upper incomplete gamma (series below a+1, continued fraction above)."""
    if x <= 0:
        return 1.0
    gln = math.lgamma(a)
    if x < a + 1.0:
        ap, s, d = a, 1.0 / a, 1.0 / a
        for _ in range(1000):
            ap += 1.0
            d *= x / ap
            s += d
            if abs(d) < abs(s) * 1e-15:
                break
        return max(0.0, 1.0 - s * math.exp(-x + a * math.log(x) - gln))
    b = x + 1.0 - a
    c = 1.0 / 1e-300
    d = 1.0 / b
    h = d
    for i in range(1, 1000):
        an = -i * (i - a)
        b += 2.0
        d = an * d + b
        d = 1e-300 if abs(d) < 1e-300 else d
        c = b + an / c
        c = 1e-300 if abs(c) < 1e-300 else c
        d = 1.0 / d
        de = d * c
        h *= de
        if abs(de - 1.0) < 1e-15:
            break
    return min(1.0, math.exp(-x + a * math.log(x) - gln) * h)


def chi2_sf(x, df):
    return _gammainc_upper_reg(df / 2.0, x / 2.0)


def poisson_sf(k, lam):
    """P(X >= k) for X ~ Poisson(lam) (stage_mde.py pois_ge)."""
    return 1 - sum(math.exp(-lam) * lam**i / math.factorial(i) for i in range(k))


# ── MDE arithmetic (ports) ─────────────────────────────────────────────────────────────────────
def mde(sd, per_week, weeks, p=0.5, r2=0.0, extra=1.0, z=ZPOW):
    """Fleet pp/wk MDE of an event-level metric (stage_mde.py): z·sd·√(1−R²)·√((1/p+1/(1−p))/N)·n_w,
    N = n_w·weeks. p is the treated share; extra multiplies (√2 for a round's half arms)."""
    n = per_week * weeks
    return (
        z
        * sd
        * math.sqrt(1 - r2)
        * math.sqrt((1 / p + 1 / (1 - p)) / n)
        * per_week
        * extra
    )


def hp_mde_factor():
    """Interim-look MDE inflation under Haybittle-Peto (§2: ×1.37, est. (3.0+0.84)/(1.96+0.84))."""
    return (HP_INTERIM + Z80) / (HP_FINAL + Z80)


def mean_sd(xs):
    n = len(xs)
    m = sum(xs) / n
    return m, (math.sqrt(sum((x - m) ** 2 for x in xs) / (n - 1)) if n > 1 else 0.0)


def event_mde(xs, weeks_observed):
    """eventmde.py summ(): an event-randomized 50/50 week. → dict(n, per_week, mean, sd, p50, p90,
    cv, mde_per_event, mde_pp_wk)."""
    n = len(xs)
    m, sd = mean_sd(xs)
    nw = n / float(weeks_observed)
    mde_ev = ZPOW * math.sqrt(2 * sd * sd / (nw / 2))
    srt = sorted(xs)
    return {
        "n": n,
        "per_week": nw,
        "mean": m,
        "sd": sd,
        "p50": srt[n // 2],
        "p90": srt[int(0.9 * n)],
        "cv": sd / m if m else None,
        "mde_per_event": mde_ev,
        "mde_pp_wk": mde_ev * nw,
    }


def ols_resid_var(X, y):
    """cuped.py: normal-equation OLS with intercept → (var(y), residual variance at n−k dof)."""
    n, k = len(y), len(X[0]) + 1
    A = [[0.0] * k for _ in range(k)]
    b = [0.0] * k
    for xi, yi in zip(X, y):
        r = [1.0] + list(xi)
        for i in range(k):
            b[i] += r[i] * yi
            for j in range(k):
                A[i][j] += r[i] * r[j]
    M = [A[i] + [b[i]] for i in range(k)]
    for c in range(k):
        p = max(range(c, k), key=lambda r: abs(M[r][c]))
        M[c], M[p] = M[p], M[c]
        pv = M[c][c]
        if abs(pv) < 1e-18:
            continue
        M[c] = [x / pv for x in M[c]]
        for r in range(k):
            if r != c:
                f = M[r][c]
                M[r] = [x - f * y_ for x, y_ in zip(M[r], M[c])]
    beta = [M[i][k] for i in range(k)]
    res = [
        yi - (beta[0] + sum(bj * xj for bj, xj in zip(beta[1:], xi)))
        for xi, yi in zip(X, y)
    ]
    m = sum(y) / n
    vy = sum((yi - m) ** 2 for yi in y) / (n - 1)
    vr = sum(r * r for r in res) / (n - k)
    return vy, vr


def cuped_mde_rows(X, y, weeks_observed, weeks=(1, 2, 4)):
    """cuped.py rep(): raw and adjusted pp/wk MDE at each horizon, plus R²."""
    vy, vr = ols_resid_var(X, y)
    nw = len(y) / float(weeks_observed)
    out = []
    for wk in weeks:
        n = nw * wk
        out.append(
            {
                "weeks": wk,
                "raw": ZPOW * math.sqrt(2 * vy / (n / 2)) * nw,
                "adj": ZPOW * math.sqrt(2 * vr / (n / 2)) * nw,
                "r2": 1 - vr / vy,
            }
        )
    return out


def ratio(n, d, sc=1.0):
    return (n / (d / sc)) if d > 0 else None


def cv(xs):
    xs = [x for x in xs if x is not None]
    if len(xs) < 2:
        return None
    m, sd = mean_sd(xs)
    return sd / m if m else None


def week_mdes(num_days, den_days, sc=1.0):
    """stats.py's before/after MDEs over daily series: (b1) 2.80·√2·CV_week of the whole weeks,
    (b2) 2.80 × RMS of consecutive 7-day-window relative differences."""
    nweeks = len(num_days) // 7
    weekly = [
        ratio(
            sum(num_days[w * 7 : (w + 1) * 7]), sum(den_days[w * 7 : (w + 1) * 7]), sc
        )
        for w in range(nweeks)
    ]
    roll = []
    for s0 in range(0, len(num_days) - 13):
        r1 = ratio(sum(num_days[s0 : s0 + 7]), sum(den_days[s0 : s0 + 7]), sc)
        r2 = ratio(sum(num_days[s0 + 7 : s0 + 14]), sum(den_days[s0 + 7 : s0 + 14]), sc)
        if r1 and r2:
            roll.append(r2 / r1 - 1)
    cvw = cv(weekly)
    return {
        "weekly": weekly,
        "cv_week": cvw,
        "mde_b1_week_rel": ZPOW * math.sqrt(2) * cvw if cvw is not None else None,
        "mde_b2_roll_rel": ZPOW * math.sqrt(sum(x * x for x in roll) / len(roll))
        if len(roll) > 1
        else None,
    }


def aa_ratio_mde(units, num_key, den_key, sc=1.0, reps=1000, seed=20261024):
    """stats.py aa(): units (dicts) split 50/50 at random `reps` times; MDE_rel = 2.80 × SD of the
    arm-ratio relative difference. One population (stats.py runs it per week and RMSes the SDs)."""
    rng = random.Random(seed)
    rels = []
    for _ in range(reps):
        nA = dA = nB = dB = 0.0
        for s in units:
            if rng.random() < 0.5:
                nA += s.get(num_key, 0.0)
                dA += s.get(den_key, 0.0)
            else:
                nB += s.get(num_key, 0.0)
                dB += s.get(den_key, 0.0)
        rA, rB = ratio(nA, dA, sc), ratio(nB, dB, sc)
        if rA and rB:
            rels.append(rA / rB - 1)
    if len(rels) <= reps // 2:
        return None
    return ZPOW * mean_sd(rels)[1]


def meter_consumption(readings):
    """meter.py: one account's weekly-meter readings [(t, weekly_pct, window_id)] → (pp consumed,
    negative steps). Consumption = positive steps inside one weekly window + the first reading of a
    newer window (pct accrued since its reset); a stale older window id reappearing is skipped."""
    pp, neg, prev = 0.0, 0, None
    for t, wp, wr in sorted(readings):
        if prev is not None:
            pt, pwp, pwr = prev
            if wr == pwr:
                d = wp - pwp
                if d > 0:
                    pp += d
                elif d < 0:
                    neg += 1
            elif wr > pwr:
                pp += wp
        prev = (t, wp, wr)
    return pp, neg


# ── proportions ────────────────────────────────────────────────────────────────────────────────
def wilson(x, n, z=Z975):
    """Wilson score interval → (lo, hi); (0, 1) at n = 0."""
    if n <= 0:
        return 0.0, 1.0
    ph = x / float(n)
    d = 1 + z * z / n
    c = ph + z * z / (2 * n)
    r = z * math.sqrt(ph * (1 - ph) / n + z * z / (4 * n * n))
    return max(0.0, (c - r) / d), min(1.0, (c + r) / d)


def wilson_n_min(bar, observed, z=Z975, n_max=5000):
    """Smallest n whose Wilson lower bound clears `bar` at an observed rate (stage_mde.py)."""
    return next(
        (n for n in range(1, n_max) if wilson(round(observed * n), n, z)[0] >= bar),
        None,
    )


def newcombe(x1, n1, x2, n2, z=Z975):
    """Newcombe's hybrid score CI for p1 − p2 (method 10) → (d, lo, hi)."""
    p1, p2 = x1 / float(n1), x2 / float(n2)
    l1, u1 = wilson(x1, n1, z)
    l2, u2 = wilson(x2, n2, z)
    d = p1 - p2
    lo = d - math.sqrt((p1 - l1) ** 2 + (u2 - p2) ** 2)
    hi = d + math.sqrt((u1 - p1) ** 2 + (p2 - l2) ** 2)
    return d, lo, hi


# ── tests ──────────────────────────────────────────────────────────────────────────────────────
def srm_p(n_treat, n_total, share):
    """Sample-ratio mismatch: χ² (1 dof) of treated count vs the design share. A design share of 0
    or 1 has no variance: any count off it is p 0, on it p 1."""
    if n_total <= 0:
        return None
    if share <= 0 or share >= 1:
        exp_t = n_total * (1 if share >= 1 else 0)
        return 1.0 if n_treat == exp_t else 0.0
    et, ec = n_total * share, n_total * (1 - share)
    x = (n_treat - et) ** 2 / et + ((n_total - n_treat) - ec) ** 2 / ec
    return chi2_sf(x, 1)


def contingency_p(table):
    """χ² test of independence on an r×c table of counts (rows/cols with zero margins dropped)."""
    rows = [r for r in table if sum(r) > 0]
    if len(rows) < 2:
        return None
    cols = [j for j in range(len(rows[0])) if sum(r[j] for r in rows) > 0]
    if len(cols) < 2:
        return None
    t = [[r[j] for j in cols] for r in rows]
    n = float(sum(sum(r) for r in t))
    rs = [sum(r) for r in t]
    cs = [sum(t[i][j] for i in range(len(t))) for j in range(len(cols))]
    x = sum(
        (t[i][j] - rs[i] * cs[j] / n) ** 2 / (rs[i] * cs[j] / n)
        for i in range(len(t))
        for j in range(len(cols))
    )
    return chi2_sf(x, (len(t) - 1) * (len(cols) - 1))


def _kolmogorov_sf(lam):
    if lam < 1e-3:
        return 1.0
    s = sum((-1) ** (j - 1) * math.exp(-2 * j * j * lam * lam) for j in range(1, 101))
    return max(0.0, min(1.0, 2 * s))


def ks_2samp(a, b):
    """Two-sample KS → (D, asymptotic p with Stephens' small-sample correction)."""
    a, b = sorted(a), sorted(b)
    n, m = len(a), len(b)
    if not n or not m:
        return None, None
    i = j = 0
    d = 0.0
    while i < n and j < m:
        x = min(a[i], b[j])
        while i < n and a[i] <= x:
            i += 1
        while j < m and b[j] <= x:
            j += 1
        d = max(d, abs(i / float(n) - j / float(m)))
    en = math.sqrt(n * m / float(n + m))
    return d, _kolmogorov_sf((en + 0.12 + 0.11 / en) * d)


def smd(a, b):
    """Standardized mean difference (pooled SD); 0 when both are constant and equal."""
    if len(a) < 2 or len(b) < 2:
        return None
    ma, sa = mean_sd(a)
    mb, sb = mean_sd(b)
    s = math.sqrt((sa * sa + sb * sb) / 2)
    return (ma - mb) / s if s > 0 else (0.0 if ma == mb else float("inf"))


def covariate_ok(a, b, ks_min=0.05, smd_max=0.1):
    """§2: a covariate is usable iff KS p >= 0.05 and |SMD| < 0.1. → (ok, ks_p, smd)."""
    _, p = ks_2samp(a, b)
    s = smd(a, b)
    if p is None or s is None:
        return False, p, s
    return (p >= ks_min and abs(s) < smd_max), p, s


def hp_bound(look, n_looks):
    """Haybittle-Peto: |z| >= 3.0 at every interim look, 1.96 at the final one."""
    return HP_FINAL if look >= n_looks else HP_INTERIM


def holm(pvals, alpha):
    """Holm step-down. pvals {name: p or None} → {name: rejected?}; None never rejects."""
    named = sorted(((p, k) for k, p in pvals.items() if p is not None))
    m = len(named)
    out = {k: False for k in pvals}
    for i, (p, k) in enumerate(named):
        if p <= alpha / (m - i):
            out[k] = True
        else:
            break
    return out


# ── the estimate: savings per event, clustered by session, stratified by account ──────────────
def _clusters(rows):
    """rows (stratum, cluster, arm, value) with arm 'treat' or 'ctrl' →
    {stratum: [[sum_c, n_c, sum_t, n_t], ...]} in a stable order."""
    acc = {}
    for s, c, arm, v in rows:
        cl = acc.setdefault(s, {}).setdefault(c, [0.0, 0, 0.0, 0])
        if arm == "treat":
            cl[2] += v
            cl[3] += 1
        else:
            cl[0] += v
            cl[1] += 1
    return {s: [cs[c] for c in sorted(cs)] for s, cs in sorted(acc.items())}


def _diff(st):
    sc = nc = stt = nt = 0.0
    for cs in st.values():
        for c in cs:
            sc += c[0]
            nc += c[1]
            stt += c[2]
            nt += c[3]
    if not nc or not nt:
        return None
    return sc / nc - stt / nt


def cluster_robust_diff(rows):
    """Savings per event d = mean(ctrl) − mean(treat) with a stratified CR1 variance: each cluster's
    linearized contribution e_c = (Σy_c − m_c·n_c)/N_c − (Σy_t − m_t·n_t)/N_t, centred and summed
    within stratum with k/(k−1). → (d, se, n_ctrl, n_treat) or None with one arm empty."""
    st = _clusters(rows)
    N_c = sum(c[1] for cs in st.values() for c in cs)
    N_t = sum(c[3] for cs in st.values() for c in cs)
    if not N_c or not N_t:
        return None
    m_c = sum(c[0] for cs in st.values() for c in cs) / N_c
    m_t = sum(c[2] for cs in st.values() for c in cs) / N_t
    var = 0.0
    for cs in st.values():
        k = len(cs)
        if k < 2:
            continue
        e = [(c[0] - m_c * c[1]) / N_c - (c[2] - m_t * c[3]) / N_t for c in cs]
        me = sum(e) / k
        var += k / (k - 1.0) * sum((x - me) ** 2 for x in e)
    return m_c - m_t, math.sqrt(var), N_c, N_t


def cluster_bootstrap_diff(rows, reps=2000, seed=0):
    """Savings per event with sessions resampled whole, with replacement, inside their account
    stratum. → (point, sd, n_ctrl, n_treat) or None with one arm empty. The CI at a look is
    point ± bound·sd: percentiles cannot resolve the 3.0 bound's tail at 2000 reps."""
    st = _clusters(rows)
    point = _diff(st)
    if point is None:
        return None
    rng = random.Random(seed)
    keys = list(st)
    draws = []
    for _ in range(reps):
        sc = nc = stt = nt = 0.0
        for s in keys:
            cs = st[s]
            k = len(cs)
            for _j in range(k):
                c = cs[rng.randrange(k)]
                sc += c[0]
                nc += c[1]
                stt += c[2]
                nt += c[3]
        if nc and nt:
            draws.append(sc / nc - stt / nt)
    sd = mean_sd(draws)[1] if len(draws) > 1 else 0.0
    n_c = sum(c[1] for cs in st.values() for c in cs)
    n_t = sum(c[3] for cs in st.values() for c in cs)
    return point, sd, n_c, n_t


def unit_hash(salt, unit):
    return int(
        hashlib.sha256(("%s:%s" % (salt, unit)).encode("utf-8")).hexdigest()[:13], 16
    )


def pseudo_salt_aa(units, reps=200, salt="aa", z=Z975):
    """Pseudo-salt A/A over the REAL randomization unit: units (stratum, cluster, unit, value) are
    re-split 50/50 by unit_hash("salt:i", unit) parity in each of `reps` runs and tested with
    cluster_robust_diff. → dict(fpr, sd, hits, runs, band_ok) — sd is the A/A distribution's SD of
    the estimate, which the bootstrap SD must sit within 20% of (§2 Plumbing gate)."""
    hits, runs, ests = 0, 0, []
    for i in range(reps):
        rows = []
        for s, c, u, v in units:
            arm = "treat" if unit_hash("%s:%d" % (salt, i), u) & 1 else "ctrl"
            rows.append((s, c, arm, v))
        r = cluster_robust_diff(rows)
        if r is None or r[1] <= 0:
            continue
        runs += 1
        ests.append(r[0])
        if abs(r[0] / r[1]) >= z:
            hits += 1
    fpr = hits / float(runs) if runs else None
    return {
        "fpr": fpr,
        "sd": mean_sd(ests)[1] if len(ests) > 1 else None,
        "hits": hits,
        "runs": runs,
        "band_ok": fpr is not None and AA_BAND[0] <= fpr <= AA_BAND[1],
    }


def ratio_diff_z(rows, baseline=None):
    """One-sided test that a ratio is HIGHER in treatment (guards): rows (stratum, cluster, arm,
    num, den) per session → dict(r_t, r_c, z, p, basis) with a stratified CR1 delta-method SE.
    No treated denominator → None (nothing treated to harm). No control denominator → against the
    pre-registered `baseline` when given (basis "baseline", the treated arm's SE alone), else None."""
    st = {}
    for s, c, arm, y, x in rows:
        a = st.setdefault(s, {}).setdefault(c, [0.0, 0.0, 0.0, 0.0])
        if arm == "treat":
            a[2] += y
            a[3] += x
        else:
            a[0] += y
            a[1] += x
    X_c = sum(a[1] for cs in st.values() for a in cs.values())
    X_t = sum(a[3] for cs in st.values() for a in cs.values())
    if X_t <= 0 or (X_c <= 0 and baseline is None):
        return None
    basis = "arms" if X_c > 0 else "baseline"
    r_c = (
        sum(a[0] for cs in st.values() for a in cs.values()) / X_c
        if X_c > 0
        else float(baseline)
    )
    r_t = sum(a[2] for cs in st.values() for a in cs.values()) / X_t
    var = 0.0
    for cs in st.values():
        k = len(cs)
        if k < 2:
            continue
        e = [
            (a[2] - r_t * a[3]) / X_t - ((a[0] - r_c * a[1]) / X_c if X_c > 0 else 0.0)
            for a in cs.values()
        ]
        me = sum(e) / k
        var += k / (k - 1.0) * sum((x - me) ** 2 for x in e)
    se = math.sqrt(var)
    if (
        se <= 0
    ):  # no spread: the sign alone decides (z stays null: JSON has no infinity)
        return {
            "r_t": r_t,
            "r_c": r_c,
            "z": None,
            "p": 0.0 if r_t > r_c else (0.5 if r_t == r_c else 1.0),
            "basis": basis,
        }
    zz = (r_t - r_c) / se
    return {"r_t": r_t, "r_c": r_c, "z": zz, "p": norm_sf(zz), "basis": basis}


def cuped(y, x):
    """CUPED: y_adj = y − θ(x − x̄), θ = cov(x, y)/var(x), pooled over both arms so the adjustment
    cannot carry the effect. → (theta, r2, y_adj); theta 0 when x is constant."""
    n = len(y)
    mx, my = sum(x) / n, sum(y) / n
    vx = sum((a - mx) ** 2 for a in x)
    vy = sum((b - my) ** 2 for b in y)
    cxy = sum((a - mx) * (b - my) for a, b in zip(x, y))
    theta = cxy / vx if vx > 0 else 0.0
    r2 = (cxy * cxy / (vx * vy)) if vx > 0 and vy > 0 else 0.0
    return theta, r2, [b - theta * (a - mx) for a, b in zip(x, y)]
