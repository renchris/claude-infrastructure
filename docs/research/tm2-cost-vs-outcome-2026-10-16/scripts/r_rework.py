#!/usr/bin/env python3
"""r_rework.py — count every named instance of rework or goal-post moving, from the records.

Each instance carries the store and the count, so the report can name it and a reader can check it.
Reads (read-only): tm2-plan git history, the program records, this report's data files
(p_kit.json, m_movement.json, o_records.json, t_time.json, k_attrib.json), and the bundle backups
in ~/Development/claude-private/tm2-plan.

Usage (from the repo root):
  python3 -I docs/research/tm2-cost-vs-outcome-2026-10-16/scripts/r_rework.py
Writes data/r_rework.json; prints it.
"""

import glob, json, os, re, subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(os.path.dirname(HERE), "data")
REPO = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))
TM2 = os.path.expanduser("~/Development/.worktrees/tm2-plan")
PROG = "docs/research/truememory-2.0-2026-09-28"
PRIV = os.path.expanduser("~/Development/claude-private/tm2-plan")


def git(repo, *a):
    return subprocess.run(
        ["git", "-C", repo, *a], capture_output=True, text=True
    ).stdout


def load(n):
    return json.load(open(os.path.join(DATA, n)))


def main():
    o, m, k, t = (
        load("o_records.json"),
        load("m_movement.json"),
        load("p_kit.json"),
        load("t_time.json"),
    )
    subj = git(
        TM2, "log", "--format=%h|%cI|%s", "--", PROG, "docs/plans/TRUEMEMORY_2_0.md"
    ).splitlines()
    prog_commits = len(subj)
    since_intake = [s for s in subj if s.split("|")[1] >= "2026-10-01T22:11"]
    fixups = sum(1 for s in subj if s.split("|", 2)[2].startswith("fixup!"))
    resign = [
        s.split("|")[0]
        for s in subj
        if re.search(
            r"re-sign|frame signed|frame re-signed|signature now stale", s, re.I
        )
    ]
    kitrows = list(csv_rows(os.path.join(DATA, "p_kit_commits.csv")))
    v12 = [
        r
        for r in kitrows
        if re.search(r"v1\.2|Stage 9|built|yield stop|soak", r["subject"], re.I)
    ]
    router = [
        r
        for r in kitrows
        if re.search(
            r"router|held-out|heldout|classifier|row 15|relay", r["subject"], re.I
        )
    ]
    bundles = glob.glob(os.path.join(PRIV, "*.bundle"))
    gate_now = o["gate_outputs"][-1] if o["gate_outputs"] else {}
    out = {
        "program_commits_total": prog_commits,
        "program_commits_since_intake": len(since_intake),
        "program_fixup_commits": fixups,
        "frame_sign_or_resign_commits": resign,
        "contract_page_renders": len(o["contract_page_renders"]),
        "freezes": len(o["freezes"]),
        "plan_lines_first_freeze_to_last": [
            o["freezes"][0]["plan_lines"],
            o["freezes"][-1]["plan_lines"],
        ],
        "round_recloses": sum(r["reclosed"] for r in m["rounds"]),
        "round_kappa": [
            r["kappa"] for r in m["rounds"] if r["kind"] == "certification"
        ],
        "profile_switch": "standard -> lite after counted round 1 (operator signature 2026-10-12T16:19:54Z, CONTRACT.md)",
        "review_regimes_over_one_plan": {
            "plan critique rounds": len(m["plan_critique_rounds"]),
            "frame critique rounds": 2,
            "certification rounds": 6,
        },
        "decisions_ruled_more_than_once": o["decisions"]["ruled_more_than_once"],
        "decision_rule_events": o["decisions"]["rule_events_total"],
        "decisions": o["decisions"]["distinct"],
        "premises_refuted": o["premises"]["refuted"],
        "challenges_total": o["challenges"]["distinct"],
        "challenges_void": o["challenges"]["void"],
        "kit_defect_fix_commits": k["by_class"].get("D", {}).get("commits"),
        "kit_commits": k["kit_commits"],
        "kit_v12_stage9_commits": len(v12),
        "kit_v12_stage9_lines_added": sum(int(r["added"]) for r in v12),
        "kit_router_commits": len(router),
        "kit_router_lines_added": sum(int(r["added"]) for r in router),
        "router_gate_row_now": "row 15 Router FAIL: 'router not built (wave B1): CC_RESEARCH_ROUTER is unset' (tm2-cert.log)",
        "gate_now": gate_now,
        "abandoned_fires": t["fires"]["abandoned"],
        "kit_fires": t["fires"]["kit_fires"],
        "fires": t["fires"]["count"],
        "bundle_backups": len(bundles),
        "bundle_gb": round(sum(os.path.getsize(b) for b in bundles) / 1e9, 2),
        "same_morning_refile": "a9e1c97a9 (07:43 local) filed six premises not-yet-true due 2026-10-31; 0c3a5504e (08:09 local) re-dated them to 2026-12-31/2027-01-31/2027-03-31; kit 40158a730 built --refile for it",
        "s8_load_fix_commits": m["s8_load_fix_commits"],
        "s8_freshness_commits": m["s8_freshness_commits"],
    }
    with open(os.path.join(DATA, "r_rework.json"), "w") as fh:
        json.dump(out, fh, indent=1)
    print(json.dumps(out, indent=1))


def csv_rows(p):
    import csv

    with open(p) as fh:
        yield from csv.DictReader(fh)


if __name__ == "__main__":
    main()
