"""gate_rows_blockers.py — research-gate row 19, decision blockers (REPORT.md §12.2, method v1.2).

The tag itself is computed in blockers.py; this row recomputes it from the records.
"""

from __future__ import annotations

import kit
from gate import FAIL, PASS, Ctx, Row
from gate_rows_a import row


@row(19, "Decision blockers")
def row19(ctx: Ctx) -> Row:
    if not kit.is_v12(ctx.frame):
        return Row(19, "Decision blockers", PASS, ["not applicable: frame signed under method 1.1"])
    return Row(19, "Decision blockers", FAIL, ["row not implemented — unknown fails (§3.10)"])


ROWS = [row19]
