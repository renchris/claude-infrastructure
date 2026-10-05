#!/usr/bin/env python3
"""estimate.py — the stop rule and the certificate's forecast (REPORT.md §3.8, §3.12, §8 item 7).

A port of the corrected model, evidence/final/profile_sim.py over evidence/design/cert_sim.py
(docs/research/upfront-research-exhaustion-2026-09-30/): false alarms scale with the reviewer count;
the frontier slots are Opus at rho = 1.0, so a family means a vendor; raters downgrade real holes and
SEEDS PASS THROUGH THE SAME RATERS; a share of holes and seeds are omissions; the cap round is
verification-only; the invisible part is priced separately, its bound at the MEASURED upper bracket
(u_hi 0.234, research-calibration REPORT §4.4).

Method v1.2 (ruling 1bf69e5c1775, 2026-10-04): the inputs are the MEASURED set by default, read from
docs/research/research-calibration/evidence/params-measured.json (MEASURED_FIELDS names the field
behind each input; CC_RESEARCH_PARAMS or --params points at another file). The pre-calibration
assumptions stay as a labeled contrast, --base; a missing or incomplete file is a refusal, never a
silent return to them.

  estimate.py simulate --profile lite|standard|full --n0 N [--base|--stress] [--params FILE]
                       [--reps 500] [--seed 7] [--published]
      one profile_sim.out row as JSON, at the measured inputs unless --base (assumed, pre-calibration)
      or --stress (assumed). --published runs the port as published (base inputs, u_hi 0.2), which is
      random-call-for-random-call faithful, so the same seed reproduces the published table exactly.
  estimate.py forecast --program P [--base] [--params FILE]
      from the program's counted rounds (rounds/<k>/matrix.json): the stop state, the round-1
      forecast and R_max, the desk-detectable residual and its 95% bound, the invisible part, and
      P(any material change after signoff).
  estimate.py calibration [--file research-calibration.jsonl]
      skill of the forecast over replayed plans: coverage (the 95% bound held), median bound
      sharpness (bound ÷ realized desk misses; realized-0 rows counted apart, the ratio is undefined)
      and the Spearman rank correlation between the point forecast and the realized misses.
"""

from __future__ import annotations

import argparse
import json
import math
import os
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
# The false share among calls that survived verification and rating as MATERIAL, MEASURED: 89 of 237
# over 16 held-out plans (research-calibration REPORT §4.1; research-calibration.jsonl sums of
# `false_alarms` over `material`). Used only when the program's own holes carry no verified material call.
FALSE_MATERIAL_SHARE = 89 / 237
ASSUMED = [
    "fix-born rate 0.1 per applied fix",
    "invisible share 0.05 at the mean (share assumed)",
    "false alarms 1 per 100 reviewer-reads",
    "rater downgrade 5%",
    "omission share 30%",
]
MEASURED = [
    "invisible share up to 0.234 (pooled u_hi, research-calibration REPORT §4.4)",
    "false material share 0.376 when the program has no verified record (research-calibration REPORT §4.1)",
]
# The measured input set (research-calibration REPORT §3, its "Field" column): each model input and the
# field of params-measured.json it is read from. surf_blind has no measurement and stays assumed.
MEASURED_FILE = (
    Path(__file__).resolve().parents[2]
    / "docs/research/research-calibration/evidence/params-measured.json"
)
MEASURED_FIELDS = dict(
    u="u_plan_mean",
    fpp="fpp",
    q="q",
    omit="omit_plan_mean",
    b="fixborn_plan_median",
    u_hi="u_hi",
)


def measured_params(path: Optional[Path] = None) -> Dict[str, float]:
    """The measured inputs as program() keywords. Refuses a file that cannot supply every one of them."""
    src = Path(path or os.environ.get("CC_RESEARCH_PARAMS") or MEASURED_FILE)
    try:
        P = json.loads(src.read_text())
    except (OSError, ValueError) as e:
        raise kit.KitError(
            f"measured inputs unreadable at {src}: {e}; --base runs the assumed set"
        )
    miss = [
        f
        for f in MEASURED_FIELDS.values()
        if isinstance(P.get(f), bool) or not isinstance(P.get(f), (int, float))
    ]
    if miss:
        raise kit.KitError(
            f"{src}: no numeric {', '.join(miss)}; --base runs the assumed set"
        )
    out = {k: float(P[f]) for k, f in MEASURED_FIELDS.items()}
    out["surf_blind"] = BASE["surf_blind"]
    return out


def inputs_for(
    base: bool = False, path: Optional[Path] = None
) -> Tuple[str, Dict[str, float]]:
    """(label, program() keywords): the measured set, or the pre-calibration contrast."""
    if base:
        return "base", dict(BASE, b=FIX_BORN, u_hi=U_HI)
    return "measured", measured_params(path)


def provenance(label: str, P: Dict[str, float]) -> Tuple[List[str], List[str]]:
    """The certificate's (assumed, measured) lines for one input set."""
    if label != "measured":
        return ASSUMED, MEASURED
    return (
        ["blind holes surface with probability 0.5 (surf_blind, no measurement)"],
        [
            f"invisible share {P['u']:g} at the mean, up to {P['u_hi']:g} (u_plan_mean, pooled u_hi; "
            "research-calibration REPORT §3, §4.4)",
            f"false material calls {P['fpp']:g} per reviewer-read (fpp)",
            f"rater downgrade {P['q']:g} (q)",
            f"omission share {P['omit']:g} (omit_plan_mean)",
            f"fix-born rate {P['b']:g} per applied fix (fixborn_plan_median)",
            MEASURED[1],
        ],
    )


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
    rng: random.Random, found: float, k_left: int, s: int, n: int
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
    u_hi: float = U_HI,
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
    found_total = found_fb = deferred = named = dry = k = 0
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
                    found_fb += 1 if it.get("fix_born") else 0
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
                    fb = item()
                    fb["fix_born"] = True
                    live.append(fb)
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
    # each stratum draws from its own found count; the published model gave the shadow stratum 0
    found_sh = 0 if published else found_fb
    d_o = predictive_draws(
        rng, found_total - found_sh, len(seeds) + len(tri_out), s, 600
    )
    d_s = (
        predictive_draws(rng, found_sh, len(shadow) + len(tri_out_sh), s_sh, 600)
        if s_sh
        else [0] * 600
    )
    draws = [x + y for x, y in zip(d_o, d_s)]
    npred = quantile(draws, 0.95)
    n_hat = found_total + quantile(draws, 0.5)
    u_hi = U_HI_PUBLISHED if published else u_hi
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
    base: bool = False,
    params_file: Optional[Path] = None,
) -> Dict[str, Any]:
    rng = random.Random(seed)
    if stress:
        regime, params = "stress", dict(STRESS)
    else:
        regime, params = inputs_for(base or published, params_file)
    R = [
        program(rng, sim_profile(name), n0, **params, published=published)
        for _ in range(reps)
    ]
    ks = [float(r["k"]) for r in R]
    out = {
        "profile": name,
        "n0": n0,
        "regime": regime,
        "reps": reps,
        "rounds_p50": int(quantile(ks, 0.5)),
        "rounds_p90": int(quantile(ks, 0.9)),
        "cap_pct": round(100 * mean([r["stop"] == "cap" for r in R]), 1),
        "desk_left": round(mean([r["det_left"] + r["deferred"] for r in R]), 2),
        "invisible_left": round(mean([r["blind"] for r in R]), 2),
        "p_any": round(mean([r["any"] for r in R]), 2),
        "take_back_pct": round(100 * mean([r["tb"] for r in R]), 1),
    }
    if (
        not published
    ):  # the published row is reproduced byte for byte, so it carries no extra key
        out["inputs"] = params
    return out


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


def counted_holes(slug: str, mats: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """The counted rounds' MATERIAL, non-seed holes, folded; round.py close selects from the same log."""
    rounds = {str(m.get(k)) for m in mats for k in ("round", "seq")}
    holes = kit.fold(kit.read_jsonl(kit.records_dir(slug) / "holes.jsonl")).values()
    return [
        h
        for h in holes
        if str(h.get("round")) in rounds
        and (h.get("materiality") or {}).get("level") == "MATERIAL"
        and not h.get("seed_match")
    ]


def forecast(
    slug: str,
    reps: int = 300,
    seed: int = 11,
    base: bool = False,
    params_file: Optional[Path] = None,
) -> Dict[str, Any]:
    label, P = inputs_for(base, params_file)
    assumed, measured = provenance(label, P)
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
    found_raw = sum(int(m.get("new_material") or 0) for m in mats)
    holes = counted_holes(slug, mats)
    # every false material call would widen the bound, so found is deflated by the false share:
    # the program's own verifier REFUTED share among its material calls, else the calibration's
    verdicts = [
        (h.get("verification") or {}).get("status")
        for h in holes
        if (h.get("verification") or {}).get("status") in ("CONFIRMED", "REFUTED")
    ]
    if verdicts:
        false_share = verdicts.count("REFUTED") / len(verdicts)
        false_source = "program"
    else:
        false_share, false_source = FALSE_MATERIAL_SHARE, "calibration"
    keep = 1.0 - false_share
    found = found_raw * keep
    # the shadow stratum's own found count: confirmed fix-born holes (`born_in_edit`)
    found_sh = min(
        found_raw,
        sum(
            1
            for h in holes
            if h.get("born_in_edit")
            and (h.get("verification") or {}).get("status") == "CONFIRMED"
        ),
    )
    seeds = mats[-1].get("seeds") or {}
    orig = seeds.get("original") or {}
    shadow = seeds.get("shadow") or {}
    draws_o = predictive_draws(
        rng,
        (found_raw - found_sh) * keep,
        int(orig.get("k_left", 0)),
        int(orig.get("s_eff", 0)),
        2000,
    )
    draws_s = predictive_draws(
        rng,
        found_sh * keep,
        int(shadow.get("k_left", 0)),
        int(shadow.get("s_eff", 0)),
        2000,
    )
    draws = [a + c for a, c in zip(draws_o, draws_s)]
    n_hat = found + quantile(draws, 0.5)
    inv_lam = n_hat * P["u_hi"] / (1 - P["u_hi"])
    inv_mean = n_hat * P["u"] / (1 - P["u"])
    p_any = mean([1.0 if d + poisson(rng, inv_mean) > 0 else 0.0 for d in draws])
    # the round-1 forecast fixes R_max: simulate programs that START at the holes round 1 implies
    first = mats[0]
    if first.get("forecast"):
        p50, p90 = first["forecast"]["p50"], first["forecast"]["p90"]
    else:
        n0 = int(first.get("new_material") or 0) + int(quantile(draws_o, 0.5))
        ks = [
            float(program(rng, sim_profile(frame["profile"]), n0, **P)["k"])
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
        "found_raw": found_raw,
        "found": round(found, 2),
        "found_shadow": found_sh,
        "false_material_share": round(false_share, 3),
        "false_material_source": false_source,
        "desk_mean": round(mean([float(d) for d in draws]), 2),
        "desk_n95": int(quantile(draws, 0.95)),
        "desk_shadow_mean": round(mean([float(d) for d in draws_s]), 2),
        "n_hat": round(n_hat, 2),
        "invisible_mean": round(inv_mean, 2),
        "invisible_bound95": poisson_q95(inv_lam),
        "p_any": round(p_any, 2),
        "quiet_streak": streak,
        "stop": stop,
        "inputs": label,
        "assumed": assumed,
        "measured": measured,
        "calibrated": False,
    }


# ── skill over a replay: coverage alone rewards a wide bound ───────────────────────────────────

CALIBRATION_FILE = (
    Path(__file__).resolve().parents[2] / "docs/research/research-calibration.jsonl"
)


def ranks(xs: List[float]) -> List[float]:
    """1-based ranks, ties sharing their average rank."""
    order = sorted(range(len(xs)), key=lambda i: xs[i])
    out = [0.0] * len(xs)
    i = 0
    while i < len(order):
        j = i
        while j + 1 < len(order) and xs[order[j + 1]] == xs[order[i]]:
            j += 1
        for t in range(i, j + 1):
            out[order[t]] = (i + j) / 2 + 1
        i = j + 1
    return out


def spearman(xs: List[float], ys: List[float]) -> Optional[float]:
    """Pearson over average ranks; None when either side has no spread."""
    rx, ry = ranks(xs), ranks(ys)
    mx, my = mean(rx), mean(ry)
    sxy = sum((a - mx) * (b - my) for a, b in zip(rx, ry))
    sxx = sum((a - mx) ** 2 for a in rx)
    syy = sum((b - my) ** 2 for b in ry)
    return None if not sxx or not syy else sxy / math.sqrt(sxx * syy)


def median(xs: List[float]) -> Optional[float]:
    ys = sorted(xs)
    n = len(ys)
    if not n:
        return None
    return ys[n // 2] if n % 2 else (ys[n // 2 - 1] + ys[n // 2]) / 2


def calibration(path: Path) -> Dict[str, Any]:
    rows = kit.read_jsonl(path)
    need = ("forecast_point", "forecast_95", "realized_desk_missed")
    for n, r in enumerate(rows, 1):
        miss = [k for k in need if not isinstance(r.get(k), (int, float))]
        if miss:
            raise kit.KitError(f"{path}: row {n} has no numeric {', '.join(miss)}")
    if not rows:
        raise kit.KitError(f"{path}: no rows")
    point = [float(r["forecast_point"]) for r in rows]
    bound = [float(r["forecast_95"]) for r in rows]
    real = [float(r["realized_desk_missed"]) for r in rows]
    held = sum(1 for b, x in zip(bound, real) if x <= b)
    ratios = [b / x for b, x in zip(bound, real) if x > 0]
    sharp, rho = median(ratios), spearman(point, real)
    mb, mr = median(bound), median(real)
    return {
        "rows": len(rows),
        "held": held,
        "coverage": round(held / len(rows), 3),
        "sharpness_median": None if sharp is None else round(sharp, 3),
        "realized_zero": len(rows) - len(ratios),
        "bound_median": mb,
        "realized_median": mr,
        "spearman": None if rho is None else round(rho, 3),
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
    p.add_argument(
        "--base",
        action="store_true",
        help="the pre-calibration assumed inputs, as a contrast",
    )
    p.add_argument(
        "--params",
        type=Path,
        help="measured inputs file (default params-measured.json)",
    )
    p = sub.add_parser("forecast")
    p.add_argument("--program", required=True)
    p.add_argument(
        "--base",
        action="store_true",
        help="the pre-calibration assumed inputs, as a contrast",
    )
    p.add_argument(
        "--params",
        type=Path,
        help="measured inputs file (default params-measured.json)",
    )
    p = sub.add_parser("calibration")
    p.add_argument("--file", type=Path, default=CALIBRATION_FILE)
    a = ap.parse_args(argv)
    try:
        if a.verb == "simulate":
            out = simulate(
                a.profile, a.n0, a.stress, a.reps, a.seed, a.published, a.base, a.params
            )
        elif a.verb == "calibration":
            out = calibration(a.file)
        else:
            kit.check_slug(a.program)
            out = forecast(a.program, base=a.base, params_file=a.params)
    except kit.KitError as e:
        print(f"estimate.py: {e}", file=sys.stderr)
        return 2
    print(json.dumps(out, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
