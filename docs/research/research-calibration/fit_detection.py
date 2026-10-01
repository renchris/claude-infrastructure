"""fit_detection.py - fit cert_sim's detection parameters to what one replay round measured.

Measured (per plan, over the known at-freeze holes that history says a DESK reader found, with the evidence in
the plan or the repo at the freeze, i.e. the holes the bundle could show): a hole x slot matrix, 1 when that
reviewer slot's findings include an item the scorer matched to the hole. From it:
  r_full, r_plan   mean per-read recall, full-context and plan-only slots
  phi_AD           same strategy, Opus vs Opus (the frontier slots filled by Opus): the model's rho
  phi_AB           same strategy, Opus vs OpenAI (cross-vendor): the model's sd_f
The fit searches alpha (base logit), a plan-only strategy shift, rho and sd_f so that one simulated round of the
same six-slot composition reproduces those four numbers (least squares on the four moments). sd_d, sd_s, sd_e
keep cert_sim's defaults. stdlib only.

usage: python3 fit_detection.py <cache_dir> <out.json>
"""

import itertools
import json
import math
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(
    0,
    os.path.join(
        HERE, "..", "upfront-research-exhaustion-2026-09-30", "evidence", "design"
    ),
)
import cert_sim as m  # noqa: E402

from analyze import phi  # noqa: E402

DESK_EV = {"in_plan", "in_repo_at_freeze"}


def measure(C):
    mats = []  # (plan, slots, rows)
    for fn in sorted(os.listdir(os.path.join(C, "replay", "triage"))):
        d = json.load(open(os.path.join(C, "replay", "triage", fn)))
        plan = d["plan"]
        hist = json.load(open(os.path.join(C, "history", plan + ".json")))
        slots = [
            s["slot"].split("__")[1]
            for s in json.load(open(os.path.join(C, "replay", "slots.json")))
            if s["plan"] == plan and not s["void"]
        ]
        member = {
            it["iid"]: {f.split("#")[0].split("__")[1] for f in it["members"]}
            for it in d["items"]
        }
        det = {h["hole_id"]: h["detected_by_iids"] for h in d["score"]["holes"]}
        rows = []
        for h in hist["holes"]:
            if (
                h.get("fix_born")
                or h.get("found_by") != "desk_review"
                or h.get("evidence_at_freeze") not in DESK_EV
            ):
                continue
            got = (
                set().union(*[member.get(i, set()) for i in det.get(h["id"], [])])
                if det.get(h["id"])
                else set()
            )
            rows.append({s: s in got for s in slots})
        mats.append((plan, slots, rows))
    rec = {"full": [0, 0], "plan": [0, 0]}
    ph = {"AD": [], "AB": []}
    for plan, slots, rows in mats:
        for s in slots:
            k = s.split("_")[1]
            rec[k][0] += sum(r[s] for r in rows)
            rec[k][1] += len(rows)
        for a, b in itertools.combinations(slots, 2):
            fa, sa = a.split("_")
            fb, sb = b.split("_")
            if sa != sb:
                continue
            key = (
                "AD"
                if {fa, fb} == {"A", "D"}
                else "AB"
                if {fa, fb} in ({"A", "B"}, {"D", "B"})
                else None
            )
            if key:
                f = phi([r[a] for r in rows], [r[b] for r in rows])
                if f is not None:
                    ph[key].append(f)
    return dict(
        r_full=rec["full"][0] / rec["full"][1],
        r_plan=rec["plan"][0] / rec["plan"][1],
        n_holes=sum(len(r) for _, _, r in mats),
        n_full_reads=rec["full"][1],
        phi_AD=sum(ph["AD"]) / len(ph["AD"]),
        n_AD=len(ph["AD"]),
        phi_AB=sum(ph["AB"]) / len(ph["AB"]),
        n_AB=len(ph["AB"]),
    )


def simulate(alpha, shift_plan, rho, sd_f, sd_d=1.2, u=0.0, n=3000, seed=11):
    rng = random.Random(seed)
    comp = dict(
        panels=[("A", 0), ("A", 1), ("D", 0), ("D", 1), ("B", 0), ("B", 1)],
        corr={"D": ("A", rho)},
    )
    cfg = m.Cfg(comp=comp, alpha=alpha, sd_f=sd_f, sd_d=sd_d, u=u)
    X = []
    for _ in range(n):
        it = m.new_item(rng, cfg)
        if it["blind"]:
            X.append([False] * 6)
            continue
        z = [
            zz + (shift_plan if p[1] == 1 else 0.0)
            for zz, p in zip(it["z"], comp["panels"])
        ]
        X.append([rng.random() < m.logistic(zj + rng.gauss(0, cfg.sd_e)) for zj in z])
    col = lambda j: [x[j] for x in X]  # noqa: E731
    r_full = sum(sum(col(j)) for j in (0, 2, 4)) / (3 * n)
    r_plan = sum(sum(col(j)) for j in (1, 3, 5)) / (3 * n)
    pAD = (phi(col(0), col(2)) + phi(col(1), col(3))) / 2
    pAB = (
        phi(col(0), col(4))
        + phi(col(2), col(4))
        + phi(col(1), col(5))
        + phi(col(3), col(5))
    ) / 4
    return dict(r_full=r_full, r_plan=r_plan, phi_AD=pAD, phi_AB=pAB)


def fit(meas):
    """coarse grid, then a local refinement around the best cell"""
    def err(s):
        return ((s["r_full"] - meas["r_full"]) / 0.03) ** 2 + ((s["r_plan"] - meas["r_plan"]) / 0.03) ** 2 \
            + ((s["phi_AD"] - meas["phi_AD"]) / 0.08) ** 2 + ((s["phi_AB"] - meas["phi_AB"]) / 0.12) ** 2
    best = None
    for alpha in (-3.0, -2.0, -1.0, 0.0, 1.0):
        for shift in (0.0, -0.75, -1.5):
            for rho in (0.25, 0.5, 0.75, 1.0):
                for sd_f in (0.0, 0.75, 1.5):
                    for sd_d in (1.2, 2.5, 4.0):
                        for u in (0.0, 0.3, 0.6):
                            par = dict(alpha=alpha, shift_plan=shift, rho=rho, sd_f=sd_f, sd_d=sd_d, u=u)
                            e = err(simulate(n=800, **par))
                            if best is None or e < best[0]:
                                best = (e, par)
    par = best[1]
    for _ in range(2):
        for k, step in (("alpha", 0.5), ("shift_plan", 0.25), ("rho", 0.125), ("sd_f", 0.375), ("sd_d", 0.75), ("u", 0.1)):
            for d in (-step, step):
                cand = dict(par, **{k: par[k] + d})
                if cand["rho"] > 1 or cand["rho"] < 0 or cand["u"] < 0 or cand["sd_f"] < 0 or cand["sd_d"] < 0:
                    continue
                if err(simulate(n=2000, **cand)) < err(simulate(n=2000, **par)):
                    par = cand
    return dict(params=par, fitted_moments=simulate(n=4000, **par), sse=round(err(simulate(n=4000, **par)), 3))


if __name__ == "__main__":
    C = sys.argv[1]
    meas = measure(C)
    res = dict(
        measured=meas,
        fit=fit(meas),
        model_default=dict(
            alpha=-1.2,
            sd_f=1.0,
            rho_frontier=1.0,
            moments=simulate(-1.2, 0.0, 1.0, 1.0, u=0.05),
        ),
    )
    json.dump(res, open(sys.argv[2], "w"), indent=1)
    print(json.dumps(res, indent=1))
