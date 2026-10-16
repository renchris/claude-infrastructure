#!/usr/bin/env python3
"""m_movement.py — is the TrueMemory 2.0 program still moving? Yield per week, per round, per stage.

Reads (read-only): tm2-plan git history (plan critique round records), program/rounds/*/matrix.json
and panels, and this report's own data files (o_records.json, k_attrib.json, t_time.json — run
o_records.py, k_census.py, k_attrib.py and t_time.py first), plus data/m_estimate_forecast.txt
(`python3 -I scripts/research-kit/estimate.py forecast --program truememory-2-0`, read-only).

Usage (from the repo root):
  python3 -I docs/research/tm2-cost-vs-outcome-2026-10-16/scripts/m_movement.py
Writes data/m_movement.json; prints the tables.
"""

import collections, glob, json, os, re, subprocess
from datetime import datetime, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(os.path.dirname(HERE), "data")
TM2 = os.path.expanduser("~/Development/.worktrees/tm2-plan")
PROG = "docs/research/truememory-2.0-2026-09-28"
ESCAPE_DAYS = 3.0  # CONTRACT.md "Your escape cost": 3 research days per decision-changing hole after build


def ep(s):
    return datetime.fromisoformat(str(s).replace("Z", "+00:00")).timestamp()


WEEKS = [
    ("Wk1", ep("2026-09-28T05:00:00Z")),
    ("Wk2", ep("2026-10-05T05:00:00Z")),
    ("Wk3", ep("2026-10-12T05:00:00Z")),
]
WEEK_DAYS = {
    "Wk1": 7.0,
    "Wk2": 7.0,
    "Wk3": (ep("2026-10-16T14:00:00Z") - ep("2026-10-12T05:00:00Z")) / 86400,
}


def week_of(t):
    w = "pre"
    for n, a in WEEKS:
        if t >= a:
            w = n
    return w


def git(*a):
    return subprocess.run(["git", "-C", TM2, *a], capture_output=True, text=True).stdout


def load(name):
    return json.load(open(os.path.join(DATA, name)))


def main():
    out = {}
    # ── 1. plan critique rounds (pre-program and replan), from their record commits ──────────
    rx = re.compile(r"critique round (\d+) record(?: update)? \((\d+) verified")
    crit = {}
    for ln in git(
        "log",
        "--reverse",
        "--format=%h|%cI|%s",
        "--",
        "docs/plans/TRUEMEMORY_2_0.md",
        PROG,
    ).splitlines():
        sha, ci, s = ln.split("|", 2)
        m = rx.search(s)
        if m and int(m.group(1)) not in crit:
            crit[int(m.group(1))] = {
                "round": int(m.group(1)),
                "at": ci,
                "verified": int(m.group(2)),
                "sha": sha,  # subjects stay on the private branch: this file is published
            }
    out["plan_critique_rounds"] = [crit[k] for k in sorted(crit)]
    # ── 2. certification rounds ─────────────────────────────────────────────────────────────
    rounds = []
    for k in ["fc1", "fc2", "1", "2", "3", "4", "5", "6"]:
        d = json.load(open(os.path.join(TM2, PROG, "program/rounds", k, "matrix.json")))
        fam = collections.Counter()
        for p in glob.glob(
            os.path.join(TM2, PROG, "program/rounds", k, "panels", "*.json")
        ):
            try:
                pj = json.load(open(p))
            except ValueError:
                continue
            fam[
                str(
                    pj.get("vendor")
                    or pj.get("family")
                    or (pj.get("raised_by") or {}).get("family")
                    or "?"
                )
            ] += 1
        rounds.append(
            {
                "round": k,
                "kind": d.get("kind"),
                "at": d.get("at"),
                "new_material": d.get("new_material"),
                "seeds_caught": d.get("seeds_caught"),
                "seeds_planted": len(d.get("seeds") or [])
                if isinstance(d.get("seeds"), list)
                else d.get("seeds"),
                "kappa": (d.get("kappa") or {}).get("materiality"),
                "reclosed": len(d.get("reclosed") or []),
                "slots": len(d.get("slots") or []),
                "panels_by_vendor": dict(fam),
                "quiet": d.get("quiet"),
            }
        )
    out["rounds"] = rounds
    # ── 3. weekly yield ─────────────────────────────────────────────────────────────────────
    o = load("o_records.json")
    ka = load("k_attrib.json")
    tt = load("t_time.json")
    A = {tuple(a["key"]): a for a in ka["agg"]}
    P = {tuple(p["key"]): p for p in ka["pp"]}
    pr = ka["fit_price"]
    ppm1 = lambda a: (
        pr["output"] * a["output"]
        + pr["cache_creation"] * a["cache_creation"]
        + pr["input"] * a["input"]
    )
    core = ("program", "kit", "kit-method")
    weekly = []
    crit_by_week = collections.Counter()
    for r in out["plan_critique_rounds"]:
        if (
            r["round"] < 24
        ):  # rounds 24-29 are also holes.jsonl rows (round "24".."29"): count them once
            crit_by_week[week_of(ep(r["at"]))] += r["verified"]
    sess_hours = collections.Counter()
    for b in core:
        for h, n in ka["hours"].get(b, {}).items():
            sess_hours[week_of(int(h))] += n
    for w, _ in WEEKS:
        pp = sum(ppm1(A[("week", b, w)]) for b in core if ("week", b, w) in A)
        hc = tt["hour_causes_by_week"].get(w, {})
        row = {
            "week": w,
            "days": round(WEEK_DAYS[w], 2),
            "core_pp_M1": round(pp, 1),
            "working_hours": hc.get("working", 0),
            "operator_wait_hours": hc.get("waiting: operator", 0),
            "session_hours": sess_hours[w],
            "plan_critique_verified_findings": crit_by_week[w],
            "real_new_material_holes": o["holes"]["real_new_material_by_week"].get(
                w, 0
            ),
            "of_which_name_a_decision": o["holes"][
                "real_new_material_naming_decision_by_week"
            ].get(w, 0),
            "decisions_first_ruled": o["decisions"]["first_ruled_by_week"].get(w, 0),
            "premises_reaching_required_level": o["premises"][
                "first_reached_required_level_by_week"
            ].get(w, 0),
            "probes_run": o["probes"]["by_week"].get(w, 0),
        }
        f = row["real_new_material_holes"] + row["plan_critique_verified_findings"]
        row["findings_per_day"] = round(f / row["days"], 1)
        row["findings_per_10pp"] = round(10 * f / pp, 1) if pp else None
        row["findings_per_100_session_hours"] = (
            round(100 * f / row["session_hours"], 1) if row["session_hours"] else None
        )
        weekly.append(row)
    out["weekly"] = weekly
    # ── 4. per stage: cost, finds, escape-cost test ─────────────────────────────────────────
    stage_holes = collections.Counter()
    stage_dec = collections.Counter()
    hr = [json.loads(l) for l in open(os.path.join(TM2, PROG, "program/holes.jsonl"))]
    stage_win = [(s["stage"], ep(s["start"]), ep(s["end"])) for s in tt["stages"]]
    # use o_records' definition: confirmed, MATERIAL, not seed/artifact/held re-find; first ts of the id
    import sys

    sys.path.insert(
        0,
        os.path.join(
            os.path.dirname(HERE), "..", "..", "..", "scripts", "research-kit", "lib"
        ),
    )
    import kit  # noqa: E402

    H = kit.fold(hr)
    first = {}
    for r in hr:
        if r.get("id") and r.get("ts") and r["id"] not in first:
            first[r["id"]] = ep(r["ts"])
    held = {
        str(r["hole"])
        for r in kit.fold(
            [
                json.loads(l)
                for l in open(os.path.join(TM2, PROG, "program/known_rows.jsonl"))
            ]
        ).values()
        if r.get("kind") == "frame-omission"
        and r.get("status", "open") == "open"
        and r.get("hole")
    }
    for i, h in H.items():
        if (
            (h.get("verification") or {}).get("status") == "CONFIRMED"
            and (h.get("materiality") or {}).get("level") == "MATERIAL"
            and not kit.not_new_material(h, held)
        ):
            t = first.get(i)
            st = next((n for n, a, b in stage_win if a <= t < b), "after")
            stage_holes[st] += 1
            if any(re.match(r"DR-\d", str(n)) for n in (h.get("names") or [])):
                stage_dec[st] += 1
    for r in out["plan_critique_rounds"]:
        if r["round"] < 24:
            t = ep(r["at"])
            st = next((n for n, a, b in stage_win if a <= t < b), "after")
            stage_holes[st + " (plan critique, verified findings)"] += r["verified"]
    stages = []
    for s in tt["stages"]:
        n = s["stage"]
        a = A.get(("stage", "program", n))
        pp = sum(ppm1(A[("stage", b, n)]) for b in core if ("stage", b, n) in A)
        dec = stage_dec.get(n, 0)
        stages.append(
            {
                "stage": n,
                "wall_days": s["wall_days"],
                "core_pp_M1": round(pp, 1),
                "material_holes": stage_holes.get(n, 0),
                "decision_naming": dec,
                "plan_critique_findings": stage_holes.get(
                    n + " (plan critique, verified findings)", 0
                ),
                "days_per_decision_naming_hole": round(s["wall_days"] / dec, 2)
                if dec
                else None,
                "pays_vs_escape_price": (s["wall_days"] / dec < ESCAPE_DAYS)
                if dec
                else None,
            }
        )
    out["stages"] = stages
    # ── 5. forecast, then and now ───────────────────────────────────────────────────────────
    now_f = json.loads(
        open(os.path.join(DATA, "m_estimate_forecast.txt"))
        .read()
        .strip()
        .splitlines()[-1]
    )
    out["forecast_now"] = {
        k: now_f.get(k)
        for k in (
            "found",
            "n_hat",
            "desk_mean",
            "desk_n95",
            "invisible_mean",
            "invisible_bound95",
            "p_any",
            "stop",
            "rounds_counted",
            "quiet_streak",
        )
    }
    cp = open(os.path.join(TM2, PROG, "program/CONTRACT.md")).read()
    m = re.search(
        r"(\d+) material holes found so far, estimated holes at freeze (\d+) \(at most (\d+)",
        cp,
    )
    out["forecast_contract_page_after_round_1"] = (
        {"found": int(m.group(1)), "n_hat": int(m.group(2)), "n95": int(m.group(3))}
        if m
        else None
    )
    # ── 6. the marginal week: what Wk3's program commits were ───────────────────────────────
    cats = [
        (
            "finding or fix of a finding",
            r"fix cycle|integrat|holes? (verified|recorded)|round \d+ (closed|work)|material|refind|re-find",
        ),
        (
            "certification round mechanics",
            r"round \d|settle|repass|re-pass|rating|kappa|cap round|seed",
        ),
        (
            "re-dating, re-filing, re-ruling, affirming",
            r"re-dat|re-fil|re-rul|affirm|re-carr|not-yet-true|filed|re-sign",
        ),
        ("freshness and re-checks", r"freshness|re-check|recheck|lapsed"),
        ("rehearsal and relay trials", r"rehears|relay|trial"),
        (
            "gate rows and trace bookkeeping",
            r"gate|row \d|trace|reconcil|/tmp|operator items|packets|records",
        ),
    ]
    wk3 = collections.Counter()
    fix = 0
    lines = git(
        "log",
        "--since=2026-10-12T05:00:00Z",
        "--format=%s",
        "--",
        PROG,
        "docs/plans/TRUEMEMORY_2_0.md",
    ).splitlines()
    for s in lines:
        if s.startswith("fixup!"):
            fix += 1
        for c, rr in cats:
            if re.search(rr, s, re.I):
                wk3[c] += 1
                break
        else:
            wk3["other"] += 1
    out["wk3_commit_categories"] = {
        "commits": len(lines),
        "fixups": fix,
        "by_category_first_match": dict(wk3),
    }
    s8 = git(
        "log",
        "--since=2026-10-13T04:15:43Z",
        "--format=%s",
        "--",
        PROG,
        "docs/plans/TRUEMEMORY_2_0.md",
    ).splitlines()
    out["s8_commits"] = len(s8)
    s8c = collections.Counter()
    for s in s8:
        for c, rr in cats:
            if re.search(rr, s, re.I):
                s8c[c] += 1
                break
        else:
            s8c["other"] += 1
    out["s8_commit_categories"] = dict(s8c)
    # counts only: the subjects themselves live on the private tm2-plan branch (one names an
    # unfiled advisory) and this file is published with the public repo
    out["s8_load_fix_commits"] = sum(
        1 for s in s8 if "load" in s and s.startswith("fix(")
    )
    out["s8_freshness_commits"] = sum(1 for s in s8 if "freshness" in s)
    with open(os.path.join(DATA, "m_movement.json"), "w") as fh:
        json.dump(out, fh, indent=1)
    print(json.dumps(out, indent=1)[:14000])


if __name__ == "__main__":
    main()
