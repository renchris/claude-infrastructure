"""build_heldout.py - the frame-axis checklist and the escape library, rebuilt WITHOUT one held-out plan's holes.

REPORT §6.6 / Appendix B break 13: a calibration replay is in-sample unless the checklist and the escape
library are rebuilt without the held-out plan's own holes first.

Inputs (repo-relative):
  - evidence/taxonomy_holes.py: the 200-hole ledger. The escape library is its desk-findable rows (findable D).
  - evidence/design/SYNTHESIS.md §3.5: the 32-row Frame Axis Checklist (FAC v0), each row citing ledger ids.
  - a history file per plan (history/<id>.json) whose holes carry `ledger_ids`, plus the plan's ledger project
    names (PROJECTS below), so rows are held out by project as well as by id.

Rule: a ledger row is held out if its id is cited by the plan's history or its project is one of the plan's
projects. A FAC row is dropped if every ledger id it cites is held out (rows citing outside sources, such as
the AWS paper or a plan line, are kept). Output: heldout/<id>.json with the kept FAC rows and escape ids.
"""

import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
EV = os.path.join(ROOT, "..", "upfront-research-exhaustion-2026-09-30", "evidence")

# ledger project names per held-out plan (exact strings from taxonomy_holes.py)
PROJECTS = {
    "tm2": ["TrueMemory 2.0", "TrueMemory", "TrueMemory upstream"],
    "limit-recover-100p": [
        "infra LIMIT_RECOVER_100P",
        "limit-recover",
        "infra limit-recover",
    ],
    "limit-detect-100p": ["infra LIMIT_DETECT", "infra limit-detect"],
    "hook-surface-100p": ["infra hook surface"],
    "reso-latency-100p": ["reso nav latency"],
    "reso-security-100p": ["reso security audit", "reso key rotation"],
    "land-pipeline-v2": [],
    "machine-capacity-v2": [],
    "limit-recover-fleet-v2": [],
    "tenant-provisioning-100p": [],
    "land-ship-v2": ["reso land/deploy"],
    "device-enrollment-build": [],
    "voiceink-latency": ["VoiceInk latency", "voiceink", "voiceink-transcripts"],
    "sevenrooms-laptop-independence": ["sevenrooms"],
    "agent-context-sync": ["agent-context-sync"],
    "research-report-v1": [],
}


def ledger():
    ns = {}
    exec(open(os.path.join(EV, "taxonomy_holes.py")).read(), ns)
    return ns["H"]


def fac_rows():
    txt = open(os.path.join(EV, "design", "SYNTHESIS.md")).read()
    sec = txt.split("### 3.5 Frame Axis Checklist", 1)[1].split("\n### ", 1)[0]
    rows = []
    for line in sec.splitlines():
        mm = re.match(r"\|\s*(\d\d)\s*\|\s*(.+?)\s*\|\s*(.+?)\s*\|\s*$", line)
        if not mm:
            continue
        cites = mm.group(3)
        ids, external = [], False
        for seg in cites.split(";"):
            seg = seg.strip()
            if re.fullmatch(r"[\d,\s]+", seg):
                ids += [int(x) for x in re.findall(r"\d+", seg)]
            elif seg:
                external = True
        rows.append(
            dict(
                fac="FAC-" + mm.group(1),
                axis=mm.group(2),
                ledger_ids=ids,
                external=external,
                cites=cites,
            )
        )
    return rows


def build(plan_id, hist):
    H = ledger()
    projects = set(PROJECTS.get(plan_id, []))
    cited = set()
    for h in hist.get("holes", []):
        for x in h.get("ledger_ids") or []:
            try:
                cited.add(int(x))
            except (TypeError, ValueError):
                pass
    held = {r[0] for r in H if r[2] in projects} | cited
    escapes = [r[0] for r in H if r[6] == "D" and r[0] not in held]
    kept, dropped = [], []
    for row in fac_rows():
        live_ids = [i for i in row["ledger_ids"] if i not in held]
        if row["ledger_ids"] and not live_ids and not row["external"]:
            dropped.append(row["fac"])
        else:
            kept.append(dict(row, ledger_ids=live_ids))
    return dict(
        id=plan_id,
        held_out_ledger_ids=sorted(held),
        escape_ids=escapes,
        fac_kept=kept,
        fac_dropped=dropped,
        n_escapes=len(escapes),
        n_fac=len(kept),
    )


if __name__ == "__main__":
    hist_dir, out_dir = sys.argv[1], sys.argv[2]
    os.makedirs(out_dir, exist_ok=True)
    for fn in sorted(os.listdir(hist_dir)):
        if not fn.endswith(".json"):
            continue
        pid = fn[:-5]
        hist = json.load(open(os.path.join(hist_dir, fn)))
        res = build(pid, hist)
        json.dump(res, open(os.path.join(out_dir, fn), "w"), indent=1)
        print(
            "%-32s held-out ledger rows %3d  escapes kept %3d  FAC kept %2d dropped %s"
            % (
                pid,
                len(res["held_out_ledger_ids"]),
                res["n_escapes"],
                res["n_fac"],
                res["fac_dropped"],
            )
        )
