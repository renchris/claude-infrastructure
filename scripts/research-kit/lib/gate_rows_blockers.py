"""gate_rows_blockers.py — research-gate row 19, decision blockers (REPORT.md §12.2, method v1.2).

The tag itself is computed in blockers.py; this row recomputes it from the records.
"""

from __future__ import annotations

from typing import List

import blockers
import kit
from gate import PASS, Ctx, Row
from gate_rows_a import folded, row, verdict


@row(19, "Decision blockers")
def row19(ctx: Ctx) -> Row:
    if not kit.is_v12(ctx.frame):
        return Row(19, "Decision blockers", PASS, ["not applicable: frame signed under method 1.1"])
    fails: List[str] = []
    notes: List[str] = []
    cap = kit.CAPS["decision_extensions"]
    for d in folded(ctx, "decisions.jsonl").values():
        did = d.get("id")
        t = blockers.tag(ctx, d)
        if t["extensions"] > cap:
            fails.append(f"{did}: {t['extensions']} research extensions signed; the cap is {cap} per decision")
        if t["tag"] is None:
            continue
        if not (d.get("ruled_by") == "packet-default" or d.get("status") == "carried"):
            continue  # ruled by the operator or the ladder, or still open (row 5's business)
        how = "decided by default" if d.get("ruled_by") == "packet-default" else "carried"
        if t["tag"] != "research":
            notes.append(f"{did}: {how} at {t['conviction']}%, blocked by {t['tag']}")
        elif t["at_ceiling"] is None:
            fails.append(
                f"{did}: {how} while blocked by research, and its timebox_days or "
                "research_started is not on record — unknown fails"
            )
        elif t["at_ceiling"]:
            notes.append(
                f"{did} defaulted at the research ceiling ({t['conviction']}%; still below "
                f"level: {', '.join(t['gaps'])})"
            )
        else:
            fails.append(
                f"{did}: {how} at {t['conviction']}% while research can still close "
                f"{', '.join(t['gaps'])} (up to {t['reachable_max']}%) and its research ceiling "
                "is not reached"
            )
    return verdict(19, "Decision blockers", fails, [], notes)


ROWS = [row19]
