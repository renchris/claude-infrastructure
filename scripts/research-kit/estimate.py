#!/usr/bin/env python3
"""estimate.py — the stop rule and the certificate's forecast (REPORT.md §3.8, §3.12, §8 item 7).

A port of the corrected model, evidence/final/profile_sim.py over evidence/design/cert_sim.py
(docs/research/upfront-research-exhaustion-2026-09-30/): false alarms scale with the reviewer count;
the frontier slots are Opus at rho = 1.0, so a family means a vendor; raters downgrade real holes and
SEEDS PASS THROUGH THE SAME RATERS; a share of holes and seeds are omissions; the cap round is
verification-only; the invisible part is priced separately, its bound at the MEASURED upper bracket
(u_hi 0.234, research-calibration REPORT §4.4). The other inputs are still model assumptions until
the operator re-signs the measured set (§6.6).

  estimate.py simulate --profile lite|standard|full --n0 N [--stress] [--reps 500] [--seed 7] [--published]
      one profile_sim.out row as JSON. --published runs the port as published (u_hi 0.2), which is
      random-call-for-random-call faithful, so the same seed reproduces the published table exactly.
  estimate.py forecast --program P
      from the program's counted rounds (rounds/<k>/matrix.json): the stop state, the round-1
      forecast and R_max, the desk-detectable residual and its 95% bound, the invisible part, and
      P(any material change after signoff).
"""

from __future__ import annotations

import argparse
import json
import math
import random
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
import kit  # noqa: E402

# ── the cert_sim model (cert_sim.py:33-198, ported verbatim in behaviour) ──────────────────────

ALPHA, SD_D, SD_F, SD_S, SD_E = -1.2, 1.2, 1.0, 0.5, 0.3
BASE = dict(u=0.05, fpp=0.01, q=0.05, omit=0.3, surf_blind=0.5)
STRESS = dict(u=0.10, fpp=0.02, q=0.10, omit=0.5, surf_blind=1.0)
FIX_BORN = 0.1
# The invisible share's upper bracket, MEASURED: pooled u_hi 0.234 over 16 held-out plans (per-plan
# mean 0.343), docs/research/research-calibration/REPORT.md §4.4, evidence/params-measured.json `u_hi`.
# The published model priced it at an assumed 0.2 (U_HI_PUBLISHED), below that bracket.
U_HI, U_HI_PUBLISHED = 0.234, 0.2
ASSUMED = [
    "fix-born rate 0.1 per applied fix",
    "invisible share 0.05 at the mean (share assumed)",
    "false alarms 1 per 100 reviewer-reads",
    "rater downgrade 5%",
    "omission share 30%",
]
MEASURED = [
    "invisible share up to 0.234 (pooled u_hi, research-calibration REPORT §4.4)",
]


def logistic(x: float) -> float:
    return 0.0 if x < -35 else 1.0 / (1.0 + math.exp(-x))


def composition(per_slot_set: int) -> Dict[str, Any]:
    """Four slot sets A-D (Opus, OpenAI, Google, frontier); D is Opus at rho 1.0 (profile_sim.py:30-33)."""
    return {
        "panels": [(f, s) for f in "ABCD" for s in range(per_slot_set)],
        "corr": {"D": ("A", 1.0)},
    }


def families(comp: Dict[str, Any]) -> List[str]:
    fams: List[str] = []
    for f, _ in comp["panels"]:
        if f not in fams:
            fams.append(f)
    return sorted(fams, key=lambda f: 1 if f in comp["corr"] else 0)


def new_item(
    rng: random.Random, comp: Dict[str, Any], u: float, blind_ok: bool = True
) -> Dict[str, Any]:
    blind = blind_ok and (rng.random() < u)
    d = rng.gauss(0.0, SD_D)
    g: Dict[str, float] = {}
    for f in families(comp):
        if f in comp["corr"]:
            base, rho = comp["corr"][f]
            g[f] = rho * g[base] + math.sqrt(1 - rho * rho) * rng.gauss(0.0, SD_F)
        else:
            g[f] = rng.gauss(0.0, SD_F)
    h: Dict[Tuple[str, int], float] = {}
    z = []
    for f, s in comp["panels"]:
        if (f, s) not in h:
            h[(f, s)] = rng.gauss(0.0, SD_S)
        z.append(ALPHA + d + g[f] + h[(f, s)])
    return {"blind": blind, "d": d, "z": z}


def detect(rng: random.Random, item: Dict[str, Any]) -> int:
    if item["blind"]:
        return 0
    return sum(
        1 for zj in item["z"] if rng.random() < logistic(zj + rng.gauss(0.0, SD_E))
    )


def poisson(rng: random.Random, lam: float) -> int:
    if lam <= 0:
        return 0
    if lam < 40:
        lim, k, p = math.exp(-lam), 0, 1.0
        while True:
            p *= rng.random()
            if p <= lim:
                return k
            k += 1
    return max(0, int(round(rng.gauss(lam, math.sqrt(lam)))))


def predictive_draws(
    rng: random.Random, found: int, k_left: int, s: int, n: int
) -> List[int]:
    """Posterior-predictive residual: pi ~ Beta(k+.5, s-k+.5); R | pi ~ NegBin(F+1, 1-pi)."""
    if s <= 0:
        return [0] * n
    out = []
    r = found + 1
    for _ in range(n):
        pi = rng.betavariate(k_left + 0.5, s - k_left + 0.5)
        if r <= 0 or pi <= 0:
            out.append(0)
            continue
        lam = rng.gammavariate(r, pi / (1 - pi)) if pi < 1 else 1e9
        out.append(poisson(rng, lam))
    return out


def quantile(xs: List[float], q: float) -> float:
    ys = sorted(xs)
    return ys[min(len(ys) - 1, max(0, int(math.ceil(q * len(ys))) - 1))]


def poisson_q95(lam: float) -> int:
    if lam <= 0:
        return 0
    k, p, c = 0, math.exp(-lam), math.exp(-lam)
    while c < 0.95:
        k += 1
        p *= lam / k
        c += p
    return k


def mean(xs: List[float]) -> float:
    return sum(xs) / len(xs) if xs else float("nan")


# ── one simulated program (profile_sim.py:52-135) ──────────────────────────────────────────────


def program(
    rng: random.Random,
    prof: Dict[str, Any],
    n0: int,
    u: float,
    fpp: float,
    q: float,
    omit: float,
    surf_blind: float,
    b: float = FIX_BORN,
    surf_det: float = 1.0,
    published: bool = False,
) -> Dict[str, Any]:
    comp, T, K, R_abs, s = prof["comp"], prof["T"], prof["K"], prof["R_abs"], prof["s"]

    def item(blind_ok: bool = True) -> Dict[str, Any]:
        it = new_item(rng, comp, u, blind_ok=blind_ok)
        if rng.random() < omit:
            it["z"] = [z - 2.0 for z in it["z"]]
        return it

    live = [item() for _ in range(n0)]
    seeds = [item(blind_ok=False) for _ in range(s)]
    shadow: List[Dict[str, Any]] = []
    s_sh = 0
    tri_out: List[Any] = []
    tri_out_sh: List[Any] = []
    found_total = deferred = named = dry = k = 0
    stop = "running"

    def sweep(pool: List[Dict[str, Any]], out_pool: List[Any]) -> List[Dict[str, Any]]:
        keep = []
        for sd in pool:
            if detect(rng, sd):
                if rng.random() < q:
                    out_pool.append(sd)
            else:
                keep.append(sd)
        return keep

    while True:
        k += 1
        last = k >= R_abs
        found = 0
        keep = []
        for it in live:
            if detect(rng, it):
                if rng.random() < q:
                    deferred += 1
                else:
                    found += 1
            else:
                keep.append(it)
        live = keep
        seeds = sweep(seeds, tri_out)
        shadow = sweep(shadow, tri_out_sh)
        nfp = poisson(rng, fpp * T)
        if last and (found + nfp):
            named += found + nfp
            found_total += found + nfp
            stop = "cap" if dry + (0 if (found + nfp) else 1) < K else "dry"
            break
        found_total += found + nfp
        if found + nfp:
            dry = 0
            for _ in range(found + nfp):
                for _ in range(poisson(rng, b)):
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
    d_o = predictive_draws(rng, found_total, len(seeds) + len(tri_out), s, 600)
    d_s = (
        predictive_draws(rng, 0, len(shadow) + len(tri_out_sh), s_sh, 600)
        if s_sh
        else [0] * 600
    )
    draws = [x + y for x, y in zip(d_o, d_s)]
    npred = quantile(draws, 0.95)
    n_hat = found_total + quantile(draws, 0.5)
    u_hi = U_HI_PUBLISHED if published else U_HI
    inv_bound = poisson_q95(n_hat * u_hi / (1 - u_hi))
    det_left = sum(1 for it in live if not it["blind"])
    blind_left = sum(1 for it in live if it["blind"])
    desk_esc = sum(1 for _ in range(det_left + deferred) if rng.random() < surf_det)
    inv_esc = sum(1 for _ in range(blind_left) if rng.random() < surf_blind)
    return dict(
        k=k,
        stop=stop,
        npred=npred,
        inv_bound=inv_bound,
        det_left=det_left,
        deferred=deferred,
        blind=blind_left,
        named=named,
        tb=(desk_esc > npred) or (inv_esc > inv_bound),
        any=(desk_esc + inv_esc) > 0,
    )


def sim_profile(name: str) -> Dict[str, Any]:
    p = kit.profile(name)
    return {
        "comp": composition(p["per_slot_set"]),
        "T": p["reviewers_per_round"],
        "K": p["quiet_to_stop"],
        "R_abs": p["hard_cap"],
        "s": p["seeds_original"],
    }


def simulate(
    name: str,
    n0: int,
    stress: bool = False,
    reps: int = 500,
    seed: int = 7,
    published: bool = False,
) -> Dict[str, Any]:
    rng = random.Random(seed)
    params = STRESS if stress else BASE
    R = [
        program(rng, sim_profile(name), n0, **params, published=published)
        for _ in range(reps)
    ]
    ks = [float(r["k"]) for r in R]
    return {
        "profile": name,
        "n0": n0,
        "regime": "stress" if stress else "base",
        "reps": reps,
        "rounds_p50": int(quantile(ks, 0.5)),
        "rounds_p90": int(quantile(ks, 0.9)),
        "cap_pct": round(100 * mean([r["stop"] == "cap" for r in R]), 1),
        "desk_left": round(mean([r["det_left"] + r["deferred"] for r in R]), 2),
        "invisible_left": round(mean([r["blind"] for r in R]), 2),
        "p_any": round(mean([r["any"] for r in R]), 2),
        "take_back_pct": round(100 * mean([r["tb"] for r in R]), 1),
    }


# ── forecast from a program's own rounds ───────────────────────────────────────────────────────


def counted_rounds(slug: str) -> List[Dict[str, Any]]:
    rd = kit.records_dir(slug) / "rounds"
    mats = []
    for d in sorted(
        rd.glob("*/matrix.json"),
        key=lambda p: int(p.parent.name) if p.parent.name.isdigit() else 0,
    ):
        m = kit.read_json(d)
        if m.get("kind", "certification") == "certification" and m.get("counted"):
            mats.append(m)
    return mats


def forecast(slug: str, reps: int = 300, seed: int = 11) -> Dict[str, Any]:
    frame = kit.read_json(kit.records_dir(slug) / "frame.json", {}) or {}
    if not frame.get("profile"):
        raise kit.KitError("frame.json has no profile")
    prof = kit.profile(frame["profile"])
    mats = counted_rounds(slug)
    if not mats:
        raise kit.KitError(
            "no counted certification round yet: nothing to forecast from"
        )
    rng = random.Random(seed)
    found = sum(int(m.get("new_material") or 0) for m in mats)
    seeds = mats[-1].get("seeds") or {}
    orig = seeds.get("original") or {}
    shadow = seeds.get("shadow") or {}
    draws_o = predictive_draws(
        rng, found, int(orig.get("k_left", 0)), int(orig.get("s_eff", 0)), 2000
    )
    draws_s = predictive_draws(
        rng, 0, int(shadow.get("k_left", 0)), int(shadow.get("s_eff", 0)), 2000
    )
    draws = [a + c for a, c in zip(draws_o, draws_s)]
    n_hat = found + quantile(draws, 0.5)
    inv_lam = n_hat * U_HI / (1 - U_HI)
    inv_mean = n_hat * BASE["u"] / (1 - BASE["u"])
    p_any = mean([1.0 if d + poisson(rng, inv_mean) > 0 else 0.0 for d in draws])
    # the round-1 forecast fixes R_max: simulate programs that START at the holes round 1 implies
    first = mats[0]
    if first.get("forecast"):
        p50, p90 = first["forecast"]["p50"], first["forecast"]["p90"]
    else:
        n0 = int(first.get("new_material") or 0) + int(quantile(draws_o, 0.5))
        ks = [
            float(program(rng, sim_profile(frame["profile"]), n0, **BASE)["k"])
            for _ in range(reps)
        ]
        p50, p90 = int(quantile(ks, 0.5)), int(quantile(ks, 0.9))
    import operator_sign  # noqa: E402  (scripts/lib, on the path through kit's caller)

    extra = operator_sign.latest_valid(slug, "extra-round") is not None
    rmax = kit.r_max(frame["profile"], p90, extra)
    streak = 0
    for m in reversed(mats):
        if not m.get("quiet"):
            break
        streak += 1
    r = int(mats[-1]["round"])
    K = prof["quiet_to_stop"]
    stop = (
        "dry" if (r >= K + 1 and streak >= K) else ("cap" if r >= rmax else "running")
    )
    return {
        "p50": p50,
        "p90": p90,
        "r_max": rmax,
        "rounds_counted": len(mats),
        "found": found,
        "desk_mean": round(mean([float(d) for d in draws]), 2),
        "desk_n95": int(quantile(draws, 0.95)),
        "n_hat": round(n_hat, 2),
        "invisible_mean": round(inv_mean, 2),
        "invisible_bound95": poisson_q95(inv_lam),
        "p_any": round(p_any, 2),
        "quiet_streak": streak,
        "stop": stop,
        "assumed": ASSUMED,
        "measured": MEASURED,
        "calibrated": False,
    }


def main(argv: Optional[List[str]] = None) -> int:
    sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lib"))
    ap = argparse.ArgumentParser(prog="estimate.py")
    sub = ap.add_subparsers(dest="verb", required=True)
    p = sub.add_parser("simulate")
    p.add_argument("--profile", required=True, choices=sorted(kit.PROFILES))
    p.add_argument("--n0", type=int, required=True)
    p.add_argument("--stress", action="store_true")
    p.add_argument("--reps", type=int, default=500)
    p.add_argument("--seed", type=int, default=7)
    p.add_argument("--published", action="store_true")
    p = sub.add_parser("forecast")
    p.add_argument("--program", required=True)
    a = ap.parse_args(argv)
    try:
        if a.verb == "simulate":
            out = simulate(a.profile, a.n0, a.stress, a.reps, a.seed, a.published)
        else:
            kit.check_slug(a.program)
            out = forecast(a.program)
    except kit.KitError as e:
        print(f"estimate.py: {e}", file=sys.stderr)
        return 2
    print(json.dumps(out, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
