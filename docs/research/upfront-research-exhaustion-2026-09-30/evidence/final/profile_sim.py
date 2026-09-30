"""profile_sim.py - the final protocol's certification profiles under the red-team corrections.

Reuses /tmp/rescomp/design/cert_sim.py (the synthesis's model) and changes exactly what the red team said
the synthesis got wrong:
  - false-MATERIAL findings scale with width: Poisson(fpp * T) per round (attack_sim.py term C);
  - Opus-alternate slots are modelled at rho = 1.0 with Opus (corr_check.out), so 'family' means vendor;
  - raters downgrade a real hole w.p. q, and SEEDS NOW PASS THROUGH THE SAME RATERS, so the seed recall
    pi measures detection x triage and the stated bound widens instead of silently shrinking;
  - a fraction omit of real holes are omissions (-2 logits) and the SAME fraction of seeds are omission
    seeds (the new 'remove a member and every reference to it' operator);
  - the cap round is verification-only: its finds are named on the certificate and applied in build
    wave 1 (no edit, so no fix-born hole and no post-freeze text), and they are KNOWN, never escapes;
  - the invisible mass is priced separately: inv_bound = Poisson 95% quantile of N_hat * u_hi/(1-u_hi),
    where N_hat = real holes found + the posterior-median desk residual and u_hi is the prior's upper value;
  - a post-signoff find counts against the DESK bound only if the certifying composition would catch it
    on a blind replay (blind holes never are); otherwise it counts against the INVISIBLE bound;
  - a take-back = desk escapes > n_pred95 OR invisible realized > inv_bound (either stratum, total).
Downgraded real holes (q) that later surface are escapes against the desk bound (never a relabel).
stdlib only; uncalibrated like its parent: every number is a model output until the backtest measures
the parameters.
"""
import math
import random
import sys

sys.path.insert(0, "/tmp/rescomp/design")
import cert_sim as m  # noqa: E402

# vendor-honest compositions: family D (Opus-alternate / Fable) is Opus at rho = 1.0
LITE8 = dict(panels=[("A", 0), ("A", 1), ("B", 0), ("B", 1), ("C", 0), ("C", 1), ("D", 0), ("D", 1)],
             corr={"D": ("A", 1.0)})
STD16 = dict(panels=[(f, s) for f in "ABCD" for s in range(4)], corr={"D": ("A", 1.0)})
FULL24 = dict(panels=[(f, s) for f in "ABCD" for s in range(6)], corr={"D": ("A", 1.0)})
PROFILES = {
    "lite": dict(comp=LITE8, T=8, K=2, R_abs=6, s=40),
    "standard": dict(comp=STD16, T=16, K=3, R_abs=10, s=60),
    "full": dict(comp=FULL24, T=24, K=3, R_abs=14, s=100),
}


def poisson_q95(lam):
    if lam <= 0:
        return 0
    k, p, c = 0, math.exp(-lam), math.exp(-lam)
    while c < 0.95:
        k += 1
        p *= lam / k
        c += p
    return k


def program(rng, prof, N0, u, fpp, q, omit, b=0.1, u_hi=0.2, surf_det=1.0, surf_blind=0.5):
    cfg = m.Cfg(N0=N0, K=prof["K"], comp=prof["comp"], s=prof["s"], b=b, u=u)
    T, K, R_abs, s = prof["T"], prof["K"], prof["R_abs"], prof["s"]

    def item(blind_ok=True):
        it = m.new_item(rng, cfg, blind_ok=blind_ok)
        if rng.random() < omit:
            it["z"] = [z - 2.0 for z in it["z"]]
        return it

    live = [item() for _ in range(N0)]
    seeds = [item(blind_ok=False) for _ in range(s)]
    shadow, s_sh = [], 0
    triaged_out, triaged_out_sh = [], []
    F = F_sh = 0
    deferred = 0
    named_at_cap = 0
    dry = 0
    k = 0
    while True:
        k += 1
        last = k >= R_abs
        found = 0
        keep = []
        for it in live:
            if m.detect(rng, it, cfg.sd_e):
                if rng.random() < q:
                    deferred += 1          # real, rated below MATERIAL, applied at build; surfaces later
                else:
                    found += 1
            else:
                keep.append(it)
        live = keep
        # seeds pass through the same raters: caught only if detected AND rated MATERIAL. A seed that is
        # detected but rated below MATERIAL is triaged out exactly like a real hole: it is never re-raised
        # and it stays in the uncaught count, so pi measures detection x triage (symmetric with 'deferred').
        def sweep(pool, out_pool):
            keep = []
            for sd in pool:
                if m.detect(rng, sd, cfg.sd_e):
                    if rng.random() < q:
                        out_pool.append(sd)
                else:
                    keep.append(sd)
            return keep
        seeds = sweep(seeds, triaged_out)
        shadow = sweep(shadow, triaged_out_sh)
        nfp = m.poisson(rng, fpp * T)
        if last and (found + nfp):
            named_at_cap += found + nfp    # verification-only round: named, not edited
            F += found + nfp
            stop = "cap" if dry + (0 if (found + nfp) else 1) < K else "dry"
            break
        F += found + nfp
        if found + nfp:
            dry = 0
            for _ in range(found + nfp):
                for _ in range(m.poisson(rng, b)):
                    live.append(item())
                shadow.append(item(blind_ok=False))
                s_sh += 1
        else:
            dry += 1
        if dry >= K:
            stop = "dry"
            break
        if last:
            stop = "cap"
            break
    d_o = m.predictive_draws(rng, F, len(seeds) + len(triaged_out), s, 600)
    d_s = m.predictive_draws(rng, 0, len(shadow) + len(triaged_out_sh), s_sh, 600) if s_sh else [0] * 600
    draws = [a + c for a, c in zip(d_o, d_s)]
    npred = m.quantile(draws, 0.95)
    med = m.quantile(draws, 0.5)
    n_hat = F + med
    inv_bound = poisson_q95(n_hat * u_hi / (1 - u_hi))
    det_left = sum(1 for it in live if not it["blind"])
    blind_left = sum(1 for it in live if it["blind"])
    desk_esc = sum(1 for _ in range(det_left + deferred) if rng.random() < surf_det)
    inv_esc = sum(1 for _ in range(blind_left) if rng.random() < surf_blind)
    return dict(k=k, stop=stop, npred=npred, inv_bound=inv_bound, det_left=det_left, deferred=deferred,
                blind=blind_left, named=named_at_cap, desk_esc=desk_esc, inv_esc=inv_esc,
                tb=(desk_esc > npred) or (inv_esc > inv_bound), any=(desk_esc + inv_esc) > 0,
                panel_runs=k * T)


def row(name, reps=500, seed=7, **kw):
    rng = random.Random(seed)
    R = [program(rng, **kw) for _ in range(reps)]
    ks = [r["k"] for r in R]
    print("%-46s rounds %2d/%-2d cap %4.1f%% named-at-cap %.2f | desk-left %.2f P(>=1) %.2f npred95 med %d"
          " | invisible %.2f bound med %d | P(any post-gate material) %.2f P(take-back) %4.1f%%" % (
              name, m.pct(ks, .5), m.pct(ks, .9), 100 * m.mean([r["stop"] == "cap" for r in R]),
              m.mean([r["named"] for r in R]),
              m.mean([r["det_left"] + r["deferred"] for r in R]),
              m.mean([(r["det_left"] + r["deferred"]) > 0 for r in R]),
              m.pct([r["npred"] for r in R], .5), m.mean([r["blind"] for r in R]),
              m.pct([r["inv_bound"] for r in R], .5), m.mean([r["any"] for r in R]),
              100 * m.mean([r["tb"] for r in R])))


if __name__ == "__main__":
    print("# profile_sim.out  (cert_sim.py model + red-team corrections; b=0.1; u_hi=0.2; surf_det=1.0; REPS=500)")
    print("# base = fpp 0.01/panel, q 0.05, omit 0.3, u 0.05, invisible surfacing 0.5")
    print("# stress = fpp 0.02/panel, q 0.10, omit 0.5, u 0.10, invisible surfacing 1.0")
    for N0 in (10, 20, 60):
        print("\n## N0=%d material holes at the first freeze" % N0)
        for pname in ("lite", "standard", "full"):
            prof = PROFILES[pname]
            row("%-8s base" % pname, prof=prof, N0=N0, u=0.05, fpp=0.01, q=0.05, omit=0.3, surf_blind=0.5)
            row("%-8s stress" % pname, prof=prof, N0=N0, u=0.10, fpp=0.02, q=0.10, omit=0.5, surf_blind=1.0)
    print("\n## the old accounting on the same stress runs, for contrast: no omission seeds, seeds bypass raters,")
    print("## invisible mass unpriced (it would be booked against the desk bound). See attack_sim.out rows D-F.")
