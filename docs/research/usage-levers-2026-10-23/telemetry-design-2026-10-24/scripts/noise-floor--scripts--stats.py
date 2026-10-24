#!/usr/bin/env python3
# Noise floor of candidate online metrics. usage: python3 -I stats.py <data_dir> <out_json>
# For each metric (ratio of sums) per account and fleet:
#   pooled mean over 28 days; day-to-day CV (SD/mean of daily ratios); week-to-week CV (4 weeks);
#   MDE (a) session-randomized 50/50 over 7 days, from an A/A permutation of real weeks' sessions
#           (2.80 x SD of the arm-ratio relative difference; alpha 0.05 two-sided, power 0.80);
#   MDE (b) before/after week: (b1) 2.80*sqrt(2)*CV_week; (b2) 2.80 x SD of consecutive 7-day
#           window relative differences over the 28 days (15 overlapping pairs, empirical).
import json
import math
import random
import sys
from collections import defaultdict

D, OUT = sys.argv[1], sys.argv[2]
B = json.load(open(D + "/built.json"))
DAYS = B["days"]
ACCTS = ["next", "next2", "next3", "next4"]
Z = 1.959964 + 0.841621
random.seed(20261024)


def g(a, d, k):
    if a == "fleet":
        return sum(
            B["day"].get("%s|%s" % (x, d), {}).get(k, 0.0)
            for x in ACCTS
            + (["?"] if k in ("land_ok", "land_fail", "commits", "land_red") else [])
        )
    return B["day"].get("%s|%s" % (a, d), {}).get(k, 0.0)


# metric: (numerator key, denominator key, scale)
METRICS = {
    "m1_meter_pp_per_Mout": ("meter_pp", "out", 1e6),
    "m1w_wpp_per_Mout": ("wpp", "out", 1e6),
    "m2_wpp_per_active_h": ("wpp", "active_s", 3600.0),
    "m2m_meter_pp_per_active_h": ("meter_pp", "active_s", 3600.0),
    "m3_meter_pp_per_commit": ("meter_pp", "commits", 1.0),
    "m3w_wpp_per_commit": ("wpp", "commits", 1.0),
    "m4a_tool_err_per_100req": ("tool_err", "req", 100.0),
    "m4a2_tool_err_nohook_per_100req": ("tool_err_nohook", "req", 100.0),
    "m4b_ptl_main_deaths_per_100sess": ("ptl_main_death", "sessions", 100.0),
    "m4c_failed_land_per_land": ("land_fail", "land_ok", 1.0),
    "m4c2_red_land_per_land": ("land_red", "land_ok", 1.0),
}


def ratio(n, d, sc):
    return (n / (d / sc)) if d > 0 else None


def cv(xs):
    xs = [x for x in xs if x is not None]
    if len(xs) < 2:
        return None
    m = sum(xs) / len(xs)
    if m == 0:
        return None
    sd = math.sqrt(sum((x - m) ** 2 for x in xs) / (len(xs) - 1))
    return sd / m


res = {}
for a in ACCTS + ["fleet"]:
    res[a] = {}
    for mk, (nk, dk, sc) in METRICS.items():
        N = [g(a, d, nk) for d in DAYS]
        Dn = [g(a, d, dk) for d in DAYS]
        pooled = ratio(sum(N), sum(Dn), sc)
        daily = [ratio(n, d, sc) for n, d in zip(N, Dn)]
        weekly = [
            ratio(sum(N[w * 7 : (w + 1) * 7]), sum(Dn[w * 7 : (w + 1) * 7]), sc)
            for w in range(4)
        ]
        roll = []
        for s0 in range(0, 15):
            r1 = ratio(sum(N[s0 : s0 + 7]), sum(Dn[s0 : s0 + 7]), sc)
            r2 = ratio(sum(N[s0 + 7 : s0 + 14]), sum(Dn[s0 + 7 : s0 + 14]), sc)
            if r1 and r2:
                roll.append(r2 / r1 - 1)
        sd_roll = (
            math.sqrt(sum(x * x for x in roll) / len(roll)) if len(roll) > 1 else None
        )
        cvd, cvw = cv(daily), cv(weekly)
        res[a][mk] = {
            "pooled": pooled,
            "num_28d": sum(N),
            "den_28d": sum(Dn) / sc,
            "days_with_den": sum(1 for d in Dn if d > 0),
            "cv_day": cvd,
            "cv_week": cvw,
            "weekly": weekly,
            "mde_b1_week_rel": Z * math.sqrt(2) * cvw if cvw is not None else None,
            "mde_b2_roll_rel": Z * sd_roll if sd_roll is not None else None,
        }
    # m1 on unsaturated days only (meter censored while pinned at 100%)
    if a != "fleet":
        keep = [d for d in DAYS if g(a, d, "sat_min") == 0]
        N = [g(a, d, "meter_pp") for d in keep]
        Dn = [g(a, d, "out") for d in keep]
        res[a]["m1_unsat"] = {
            "pooled": ratio(sum(N), sum(Dn), 1e6),
            "cv_day": cv([ratio(n, d, 1e6) for n, d in zip(N, Dn)]),
            "days": len(keep),
        }

# calibration: meter pp vs weighted-token pp per account-week
cal = {}
for a in ACCTS + ["fleet"]:
    cal[a] = [
        (
            sum(g(a, d, "meter_pp") for d in DAYS[w * 7 : (w + 1) * 7]),
            sum(g(a, d, "wpp") for d in DAYS[w * 7 : (w + 1) * 7]),
        )
        for w in range(4)
    ]
res["calibration_meter_vs_wpp_by_week"] = cal

# ---- session-level A/A permutation, 7-day weeks, 50/50
S0 = 1790398800
sess = [s for s in B["sess"] if not s.get("orphan_sub")]
for s in sess:
    s["week"] = int((s["first"] - S0) // (7 * 86400))
    s["sessions"] = 1
SESS_METRICS = {
    "m1w_wpp_per_Mout": ("wpp", "out", 1e6),
    "m2_wpp_per_active_h": ("wpp", "active_s", 3600.0),
    "m3w_wpp_per_commit": ("wpp", "commits", 1.0),
    "m4a_tool_err_per_100req": ("tool_err", "req", 100.0),
    "m4a2_tool_err_nohook_per_100req": ("tool_err_nohook", "req", 100.0),
    "m4b_ptl_main_deaths_per_100sess": ("ptl_death", "sessions", 100.0),
    "m4c_failed_land_per_land": ("land_fail", "land_ok", 1.0),
}
TRIG = {
    "all": lambda s: True,
    "D1_idle15_at200k": lambda s: s.get("d1_points", 0) > 0,
    "D2_has_workflow": lambda s: s.get("workflow_calls", 0) > 0,
    "D3_gap_ge_55min": lambda s: s.get("d3_gaps", 0) > 0,
    "D4_sub_poll_loop": lambda s: s.get("poll_loops", 0) > 0,
}
REPS = 1000


def aa(pop, nk, dk, sc):
    sds = []
    for w in range(4):
        P = [s for s in pop if s["week"] == w]
        if len(P) < 10:
            continue
        rels = []
        for _ in range(REPS):
            nA = dA = nB = dB = 0.0
            for s in P:
                if random.random() < 0.5:
                    nA += s.get(nk, 0.0)
                    dA += s.get(dk, 0.0)
                else:
                    nB += s.get(nk, 0.0)
                    dB += s.get(dk, 0.0)
            rA, rB = ratio(nA, dA, sc), ratio(nB, dB, sc)
            if rA and rB:
                rels.append(rA / rB - 1)
        if len(rels) > REPS // 2:
            m = sum(rels) / len(rels)
            sds.append(math.sqrt(sum((x - m) ** 2 for x in rels) / (len(rels) - 1)))
    if not sds:
        return None
    return Z * math.sqrt(sum(x * x for x in sds) / len(sds))


sres = {}
for a in ACCTS + ["fleet"]:
    pa = sess if a == "fleet" else [s for s in sess if s["acct"] == a]
    sres[a] = {}
    for tk, tf in TRIG.items():
        if a != "fleet" and tk != "all":
            continue
        pop = [s for s in pa if tf(s)]
        row = {
            "n_sessions_28d": len(pop),
            "wpp_per_week": sum(s.get("wpp", 0) for s in pop) / 4,
        }
        for mk, (nk, dk, sc) in SESS_METRICS.items():
            if tk != "all" and mk not in ("m1w_wpp_per_Mout", "m2_wpp_per_active_h"):
                continue
            row[mk] = aa(pop, nk, dk, sc)
        sres[a][tk] = row
res["session_aa_mde_rel"] = sres
res["n_sessions"] = len(sess)
json.dump(res, open(OUT, "w"), indent=1, default=lambda x: None)
print("ok")
