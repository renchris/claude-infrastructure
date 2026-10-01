"""calib_sim.py - REPORT §3.12's profile model re-run at the A3 calibration study's measured inputs.

`program()` is evidence/final/profile_sim.py's program() with three additions and no change to its logic:
  - it also returns the TYPICAL-CASE forecast the certificate prints (the posterior median of the desk
    residual, `med`) and the typical invisible forecast (n_hat * u_assumed / (1 - u_assumed)), so the
    rate at which the point forecast is exceeded can be reported beside the 95%-bound rate (§10 item 5);
  - the detection-model parameters (alpha, sd_f, rho for the frontier slots) can be overridden, so the
    model can be run at the values the replay measured;
  - extra compositions: the two-vendor composition (§3.8 dead-lane default) the replay itself ran.

Control: `python3 calib_sim.py --control` re-runs profile_sim's own base rows and must print the same
numbers as evidence/final/profile_sim.out (same seed, same draw order). The study refuses to report a
measured row until the control matches.

Run from the repo root:
  PYTHONPATH=docs/research/upfront-research-exhaustion-2026-09-30/evidence/design \
    python3 docs/research/research-calibration/calib_sim.py [--control|--table]
stdlib only.
"""

import json
import math
import random
import sys

import cert_sim as m

LITE8 = dict(
    panels=[
        ("A", 0),
        ("A", 1),
        ("B", 0),
        ("B", 1),
        ("C", 0),
        ("C", 1),
        ("D", 0),
        ("D", 1),
    ],
    corr={"D": ("A", 1.0)},
)
STD16 = dict(panels=[(f, s) for f in "ABCD" for s in range(4)], corr={"D": ("A", 1.0)})
FULL24 = dict(panels=[(f, s) for f in "ABCD" for s in range(6)], corr={"D": ("A", 1.0)})
PROFILES = {
    "lite": dict(comp=LITE8, T=8, K=2, R_abs=6, s=40),
    "standard": dict(comp=STD16, T=16, K=3, R_abs=10, s=60),
    "full": dict(comp=FULL24, T=24, K=3, R_abs=14, s=100),
}


def with_rho(prof, rho):
    """the profile with the frontier set (D) correlated rho with Opus (A) instead of 1.0"""
    comp = dict(panels=prof["comp"]["panels"], corr={"D": ("A", rho)})
    return dict(prof, comp=comp)


def two_vendor(prof):
    """§3.8 dead-lane default: the Google set (C) is dropped and not handed to the others"""
    panels = [p for p in prof["comp"]["panels"] if p[0] != "C"]
    return dict(
        prof, comp=dict(panels=panels, corr=prof["comp"]["corr"]), T=len(panels)
    )


def poisson_q95(lam):
    if lam <= 0:
        return 0
    k, p, c = 0, math.exp(-lam), math.exp(-lam)
    while c < 0.95:
        k += 1
        p *= lam / k
        c += p
    return k


def program(
    rng,
    prof,
    N0,
    u,
    fpp,
    q,
    omit,
    b=0.1,
    u_hi=0.2,
    surf_det=1.0,
    surf_blind=0.5,
    cfg_kw=None,
):
    cfg = m.Cfg(
        N0=N0, K=prof["K"], comp=prof["comp"], s=prof["s"], b=b, u=u, **(cfg_kw or {})
    )
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
    F = 0
    deferred = 0
    named_at_cap = 0
    dry = 0
    k = 0
    fixes = fixborn = 0
    while True:
        k += 1
        last = k >= R_abs
        found = 0
        keep = []
        for it in live:
            if m.detect(rng, it, cfg.sd_e):
                if rng.random() < q:
                    deferred += 1
                else:
                    found += 1
            else:
                keep.append(it)
        live = keep

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
            named_at_cap += found + nfp
            F += found + nfp
            stop = "cap" if dry + (0 if (found + nfp) else 1) < K else "dry"
            break
        F += found + nfp
        if found + nfp:
            dry = 0
            for _ in range(found + nfp):
                fixes += 1
                for _ in range(m.poisson(rng, b)):
                    live.append(item())
                    fixborn += 1
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
    d_s = (
        m.predictive_draws(rng, 0, len(shadow) + len(triaged_out_sh), s_sh, 600)
        if s_sh
        else [0] * 600
    )
    draws = [a + c for a, c in zip(d_o, d_s)]
    npred = m.quantile(draws, 0.95)
    med = m.quantile(draws, 0.5)
    n_hat = F + med
    inv_bound = poisson_q95(n_hat * u_hi / (1 - u_hi))
    inv_point = n_hat * u / (1 - u)
    det_left = sum(1 for it in live if not it["blind"])
    blind_left = sum(1 for it in live if it["blind"])
    desk_esc = sum(1 for _ in range(det_left + deferred) if rng.random() < surf_det)
    inv_esc = sum(1 for _ in range(blind_left) if rng.random() < surf_blind)
    return dict(
        k=k,
        stop=stop,
        npred=npred,
        med=med,
        inv_bound=inv_bound,
        inv_point=inv_point,
        det_left=det_left,
        deferred=deferred,
        blind=blind_left,
        named=named_at_cap,
        desk_esc=desk_esc,
        inv_esc=inv_esc,
        fixes=fixes,
        fixborn=fixborn,
        tb=(desk_esc > npred) or (inv_esc > inv_bound),
        any=(desk_esc + inv_esc) > 0,
        pt_desk=desk_esc > med,
        pt_total=(desk_esc + inv_esc) > med + round(inv_point),
        panel_runs=k * T,
    )


def summarize(R):
    ks = [r["k"] for r in R]
    return dict(
        rounds_p50=m.pct(ks, 0.5),
        rounds_p90=m.pct(ks, 0.9),
        cap_share=m.mean([r["stop"] == "cap" for r in R]),
        named_at_cap=m.mean([r["named"] for r in R]),
        desk_left=m.mean([r["det_left"] + r["deferred"] for r in R]),
        p_desk_ge1=m.mean([(r["det_left"] + r["deferred"]) > 0 for r in R]),
        npred95_med=m.pct([r["npred"] for r in R], 0.5),
        point_med=m.pct([r["med"] for r in R], 0.5),
        invisible=m.mean([r["blind"] for r in R]),
        inv_bound_med=m.pct([r["inv_bound"] for r in R], 0.5),
        p_any=m.mean([r["any"] for r in R]),
        p_takeback=m.mean([r["tb"] for r in R]),
        p_point_desk=m.mean([r["pt_desk"] for r in R]),
        p_point_total=m.mean([r["pt_total"] for r in R]),
        fixborn_mean=m.mean([r["fixborn"] for r in R]),
        panel_runs_mean=m.mean([r["panel_runs"] for r in R]),
    )


def run(name, reps=500, seed=7, **kw):
    rng = random.Random(seed)
    R = [program(rng, **kw) for _ in range(reps)]
    s = summarize(R)
    s["row"] = name
    return s


def fmt(s):
    return (
        "%-44s rounds %2d/%-2d cap %4.1f%% | desk-left %.2f npred95 %d point %d | invisible %.2f | "
        "P(any) %.2f | 95%%-bound exceeded %4.1f%% | point exceeded desk %4.1f%% total %4.1f%% | fix-born %.1f"
        % (
            s["row"],
            s["rounds_p50"],
            s["rounds_p90"],
            100 * s["cap_share"],
            s["desk_left"],
            s["npred95_med"],
            s["point_med"],
            s["invisible"],
            s["p_any"],
            100 * s["p_takeback"],
            100 * s["p_point_desk"],
            100 * s["p_point_total"],
            s["fixborn_mean"],
        )
    )


def control():
    """must reproduce evidence/final/profile_sim.out's base rows exactly"""
    for N0 in (10, 20, 60):
        for pname in ("lite", "standard", "full"):
            s = run(
                "%s base N0=%d" % (pname, N0),
                prof=PROFILES[pname],
                N0=N0,
                u=0.05,
                fpp=0.01,
                q=0.05,
                omit=0.3,
                surf_blind=0.5,
            )
            print(
                "%-24s rounds %2d/%-2d cap %4.1f%% desk-left %.2f invisible %.2f P(any) %.2f P(take-back) %4.1f%%"
                % (
                    s["row"],
                    s["rounds_p50"],
                    s["rounds_p90"],
                    100 * s["cap_share"],
                    s["desk_left"],
                    s["invisible"],
                    s["p_any"],
                    100 * s["p_takeback"],
                )
            )


def table(params_path):
    """the §3.12 table at measured inputs, plus b sensitivity; params from the calibration summary"""
    P = json.load(open(params_path))
    base = dict(
        u=P["u"],
        fpp=P["fpp"],
        q=P["q"],
        omit=P["omit"],
        surf_blind=P.get("surf_blind", 0.5),
    )
    cfg_kw = P.get("cfg_kw") or {}
    out = []
    rows = []
    for N0 in P["N0_list"]:
        for pname in ("lite", "standard", "full"):
            for b in P["b_list"]:
                for comp_name in P["comps"]:
                    prof = PROFILES[pname]
                    if comp_name == "two_vendor":
                        prof = two_vendor(prof)
                    if "rho" in P:
                        prof = with_rho(prof, P["rho"])
                    rows.append((N0, pname, b, comp_name, prof))
    for N0, pname, b, comp_name, prof in rows:
        s = run(
            "%s N0=%d b=%.2f %s" % (pname, N0, b, comp_name),
            prof=prof,
            N0=N0,
            b=b,
            cfg_kw=cfg_kw,
            **base,
        )
        s.update(N0=N0, profile=pname, b=b, comp=comp_name)
        out.append(s)
        print(fmt(s), flush=True)
    return out


if __name__ == "__main__":
    if "--control" in sys.argv:
        control()
    elif "--table" in sys.argv:
        i = sys.argv.index("--table")
        res = table(sys.argv[i + 1])
        if len(sys.argv) > i + 2:
            json.dump(res, open(sys.argv[i + 2], "w"), indent=1)
