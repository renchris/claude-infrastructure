"""gate_rows_yield.py — research-gate row 18, the yield stop (REPORT.md §12.1, method v1.2).

The rule itself lives in yield_stop.py; this row recomputes it from the records.
"""

from __future__ import annotations

import kit
from gate import FAIL, PASS, Ctx, Row
from gate_rows_a import row


@row(18, "Yield stop")
def row18(ctx: Ctx) -> Row:
    if not kit.is_v12(ctx.frame):
        return Row(18, "Yield stop", PASS, ["not applicable: frame signed under method 1.1"])
    return Row(18, "Yield stop", FAIL, ["row not implemented — unknown fails (§3.10)"])


ROWS = [row18]
