#!/usr/bin/env python3
"""z_headlines.py — every headline number in REPORT.md, derived from the data files, one per line.

Run the measurement scripts first (README order: k_census, k_attrib, o_records, p_kit, t_time,
estimate.py forecast > data/m_estimate_forecast.txt, m_movement, r_rework). This script only
reads data/*.json and prints `key = value`, so any number in the report is
  python3 -I docs/research/tm2-cost-vs-outcome-2026-10-16/scripts/z_headlines.py | grep '^<key> '
"""

import json, os, re
from datetime import datetime, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(os.path.dirname(HERE), "data")
CORE = ("program", "kit", "kit-method")


def load(n):
    return json.load(open(os.path.join(DATA, n)))


def slug(s):
    return re.sub(r"[^A-Za-z0-9]+", "_", s).strip("_")


def main():
    ka, t, o, m, k, r = (
        load(n)
        for n in (
            "k_attrib.json",
            "t_time.json",
            "o_records.json",
            "m_movement.json",
            "p_kit.json",
            "r_rework.json",
        )
    )
    A = {tuple(a["key"]): a for a in ka["agg"]}
    P = {tuple(p["key"]): p for p in ka["pp"]}
    pr = ka["fit_price"]
    m1 = lambda a: (
        pr["output"] * a["output"]
        + pr["cache_creation"] * a["cache_creation"]
        + pr["input"] * a["input"]
    )
    H = []
    add = lambda key, v: H.append((key, v))

    # ── time
    for kk, v in t["span_days"].items():
        add("span_days_since_" + kk.split(" (")[0].replace(" ", "_").lower(), v)
    add("hours_since_first_activity", t["hours_total"])
    for c, v in t["hour_causes"].items():
        add("hours_" + slug(c.split(" (")[0]), v)
    add(
        "pct_hours_working",
        round(100 * t["hour_causes"]["working"] / t["hours_total"], 1),
    )
    add(
        "pct_hours_operator_wait",
        round(100 * t["hour_causes"].get("waiting: operator", 0) / t["hours_total"], 1),
    )
    add("session_hours", t["sessions_per_working_hour"]["session_hours"])
    add(
        "mean_concurrent_sessions_per_working_hour",
        t["sessions_per_working_hour"]["mean"],
    )
    for s in t["stages"]:
        add(f"wall_days_{slug(s['stage'])}", s["wall_days"])
    add("kit_agent_days_stages_1_6", t["stages_1_6_agent_days"])
    add("kit_budget_days_stages_1_6", t["stages_1_6_budget"])
    add(
        "wall_days_stages_7_8",
        round(
            sum(s["wall_days"] for s in t["stages"] if s["stage"] in ("S7", "S8")), 2
        ),
    )
    add("operator_packets", t["operator_packets"]["count"])
    add("operator_packets_class_C", t["operator_packets"]["by_class"].get("C"))
    add(
        "operator_class_C_median_open_hours",
        round(t["operator_packets"]["class_C_median_open_hours"], 1),
    )
    add("fires", t["fires"]["count"])
    add("fires_kit", t["fires"]["kit_fires"])
    add("fires_hours", t["fires"]["hours_total"])
    for w, n in sorted(t["fires"]["by_week"].items()):
        add(f"fires_{w}", n)
    # ── tokens and quota
    core = {
        x: sum(A[("all", b)][x] for b in CORE if ("all", b) in A)
        for x in ("n", "input", "output", "cache_creation", "cache_read")
    }
    fleet = A[("fleet", "all")]
    for x in ("n", "input", "output", "cache_creation", "cache_read"):
        add(f"core_{x}", core[x])
        add(f"fleet_{x}", fleet[x])
        add(f"core_share_{x}_pct", round(100 * core[x] / fleet[x], 1))
    for b in CORE + ("mixed", "suspect", "adoption", "measurement"):
        a = A.get(("all", b))
        if a:
            add(f"pp_M1_{b}", round(m1(a), 1))
            add(f"pp_M2_{b}", round(P[("all", b)]["M2"], 1))
            add(f"output_{b}", a["output"])
            add(f"cache_creation_{b}", a["cache_creation"])
    add("pp_M1_core", round(sum(m1(A[("all", b)]) for b in CORE), 1))
    add("pp_M2_core", round(sum(P[("all", b)]["M2"] for b in CORE), 1))
    add("pp_fleet_moved", P[("fleet", "all")]["moved"])
    add(
        "pp_core_share_of_fleet_moved_pct",
        round(
            100 * sum(P[("all", b)]["M2"] for b in CORE) / P[("fleet", "all")]["moved"],
            1,
        ),
    )
    add(
        "pp_core_upper_with_mixed_and_suspect",
        round(sum(P[("all", b)]["M2"] for b in CORE + ("mixed", "suspect")), 1),
    )
    add("fit_r2", round(load("k_ccqp_fit21d.json")["fit"]["r2"], 3))
    for w in ("Wk0", "Wk1", "Wk2", "Wk3"):
        add(
            f"pp_M1_core_{w}",
            round(sum(m1(A[("week", b, w)]) for b in CORE if ("week", b, w) in A), 1),
        )
        add(
            f"pp_M2_core_{w}",
            round(sum(P.get(("week", b, w), {}).get("M2", 0) for b in CORE), 1),
        )
        add(f"pp_fleet_moved_{w}", P.get(("fleet", "week", w), {}).get("moved", 0))
    for s in t["stages"]:
        n = s["stage"]
        add(
            f"pp_M1_core_{slug(n)}",
            round(sum(m1(A[("stage", b, n)]) for b in CORE if ("stage", b, n) in A), 1),
        )
        add(
            f"pp_M1_program_{slug(n)}",
            round(m1(A[("stage", "program", n)]), 1)
            if ("stage", "program", n) in A
            else 0,
        )
    for kk, a in A.items():
        if kk[0] == "sub" and kk[1] == "program":
            add(
                "pp_M1_program_sub_" + kk[2].split(" (")[0].replace(" ", "_"),
                round(m1(a), 1),
            )
    for kk, a in A.items():
        if kk[0] == "model" and kk[1] in CORE and "fable" in kk[2]:
            add(f"output_fable_{kk[1]}", a["output"])
    # ── outcome
    hf = o["holes"]["by_family"]
    add("holes_distinct", o["holes"]["distinct"])
    add(
        "material_real_new_total",
        sum(v.get("real new material", 0) for v in hf.values()),
    )
    add(
        "material_real_new_certification_rounds_1_6",
        sum(
            v.get("real new material", 0)
            for kk, v in hf.items()
            if kk.startswith("certification round")
        ),
    )
    add(
        "material_real_new_frame_critique",
        sum(
            v.get("real new material", 0)
            for kk, v in hf.items()
            if kk.startswith("frame critique")
        ),
    )
    add(
        "material_real_new_replan_rounds_24_29",
        sum(
            v.get("real new material", 0)
            for kk, v in hf.items()
            if kk.startswith("plan critique")
        ),
    )
    add(
        "material_naming_a_decision_total",
        sum(v.get("real new material naming a decision", 0) for v in hf.values()),
    )
    add(
        "seed_catches_total",
        sum(v.get("seed catches (planted)", 0) for v in hf.values()),
    )
    add(
        "plan_critique_rounds_1_23_verified_findings",
        sum(x["verified"] for x in m["plan_critique_rounds"] if x["round"] < 24),
    )
    add("plan_critique_rounds", len(m["plan_critique_rounds"]))
    add("decisions", o["decisions"]["distinct"])
    for kk, v in o["decisions"]["status"].items():
        add(f"decisions_{kk}", v)
    for kk, v in o["decisions"]["ruled_by"].items():
        add(f"decisions_ruled_by_{kk}", v)
    add("premises", o["premises"]["distinct"])
    add("premises_at_required_level_now", o["premises"]["at_required_level_now"])
    add("premises_below_required_now", o["premises"]["below_required_now"])
    add("premises_refuted", o["premises"]["refuted"])
    for kk, v in o["premises"]["achieved_level_now"].items():
        add(f"premises_level_{kk}", v)
    add("probes", o["probes"]["total"])
    add("probes_live_read", o["probes"]["by_kind"].get("live-read"))
    add("known_rows", o["known_rows"]["distinct"])
    add("known_rows_open", o["known_rows"]["status"].get("open"))
    add("apply_at_build_rows", o["apply_at_build"]["distinct"])
    add("apply_at_build_open", o["apply_at_build"]["status"].get("open"))
    add("residual_rows", o["residual"]["distinct"])
    add("plan_lines_first_commit", list(o["plan_size_by_day"].values())[0]["lines"])
    add("plan_lines_now", list(o["plan_size_by_day"].values())[-1]["lines"])
    add("plan_commits", o["plan_commits"])
    g = o["gate_outputs"][-1]
    add("gate_rows_now", g["rows"])
    add("gate_pass_now", g["pass"])
    add("gate_filed_now", g["filed"])
    add("gate_failing_now", ",".join(str(x) for x in g["failing"]))
    add("kit_commits", k["kit_commits"])
    for kk, v in k["by_class"].items():
        add(f"kit_commits_{kk}", v["commits"])
        add(f"kit_lines_added_{kk}", v["added"])
    add("kit_share_of_trunk_commits_pct", round(100 * k["kit_share_of_trunk"], 1))
    add("kit_router_commits", r["kit_router_commits"])
    add("kit_v12_stage9_commits", r["kit_v12_stage9_commits"])
    up_pr = json.load(open(os.path.join(DATA, "p_upstream_prs.json")))
    up_is = json.load(open(os.path.join(DATA, "p_upstream_issues.json")))
    add("upstream_prs_opened_by_us", len(up_pr))
    add("upstream_prs_merged", sum(1 for p in up_pr if p.get("mergedAt")))
    add("upstream_issues_opened_by_us", len(up_is))
    # ── movement
    for w in m["weekly"]:
        for kk in (
            "plan_critique_verified_findings",
            "real_new_material_holes",
            "of_which_name_a_decision",
            "decisions_first_ruled",
            "premises_reaching_required_level",
            "findings_per_day",
            "findings_per_10pp",
            "findings_per_100_session_hours",
            "session_hours",
        ):
            add(f"{kk}_{w['week']}", w[kk])
    for x in m["rounds"]:
        if x["kind"] == "certification":
            add(f"round_{x['round']}_new_material", x["new_material"])
            add(f"round_{x['round']}_kappa", x["kappa"])
    for s in m["stages"]:
        if s["decision_naming"]:
            add(
                f"days_per_decision_naming_hole_{slug(s['stage'])}",
                s["days_per_decision_naming_hole"],
            )
    for kk, v in m["forecast_now"].items():
        add(f"forecast_now_{kk}", v)
    for kk, v in (m["forecast_contract_page_after_round_1"] or {}).items():
        add(f"forecast_round1_{kk}", v)
    add("s8_commits", m["s8_commits"])
    for kk, v in r.items():
        if isinstance(v, (int, float)) and not isinstance(v, bool):
            add(f"rework_{kk}", v)
    # ── stages that found or decided things vs stages that did not (program bucket and days)
    FIND = ("P0 pre-program", "S1", "S3", "S4", "S7")
    stg = {s["stage"]: s for s in t["stages"]}
    pp_prog = lambda n: (
        m1(A[("stage", "program", n)]) if ("stage", "program", n) in A else 0.0
    )
    find_days = sum(stg[n]["wall_days"] for n in FIND if n != "P0 pre-program")
    other = [n for n in stg if n not in FIND]
    other_days = sum(stg[n]["wall_days"] for n in other)
    add("finding_stages_days_since_intake", round(find_days, 2))
    add("other_stages_days_since_intake", round(other_days, 2))
    add(
        "finding_stages_share_of_days_since_intake_pct",
        round(100 * find_days / (find_days + other_days), 1),
    )
    add("pp_M1_program_finding_stages", round(sum(pp_prog(n) for n in FIND), 1))
    add("pp_M1_program_other_stages", round(sum(pp_prog(n) for n in other), 1))
    add(
        "pp_M1_program_finding_stages_share_pct",
        round(100 * sum(pp_prog(n) for n in FIND) / sum(pp_prog(n) for n in stg), 1),
    )
    kd = k["by_class"]
    add(
        "kit_defect_share_commits_pct",
        round(100 * kd["D"]["commits"] / k["kit_commits"], 1),
    )
    add(
        "kit_defect_share_lines_pct",
        round(100 * kd["D"]["added"] / sum(v["added"] for v in kd.values()), 1),
    )
    add(
        "days_intake_to_2026_11_15",
        round(
            (
                datetime(2026, 11, 15, tzinfo=timezone.utc).timestamp()
                - datetime(2026, 10, 2, 3, 11, 20, tzinfo=timezone.utc).timestamp()
            )
            / 86400,
            1,
        ),
    )
    for key, v in H:
        print(f"{key} = {v}")


if __name__ == "__main__":
    main()
