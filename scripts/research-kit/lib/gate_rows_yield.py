"""gate_rows_yield.py — research-gate row 18, the yield stop (REPORT.md §12.1, method v1.2).

The rule itself lives in yield_stop.py; this row recomputes it from the records.
"""

from __future__ import annotations

from typing import List

import kit
import yield_stop
from gate import PASS, Ctx, Row
from gate_rows_a import row, verdict


@row(18, "Yield stop")
def row18(ctx: Ctx) -> Row:
    if not kit.is_v12(ctx.frame):
        return Row(18, "Yield stop", PASS, ["not applicable: frame signed under method 1.1"])
    fails: List[str] = []
    notes: List[str] = []
    stages = (ctx.json("budget.json") or {}).get("stages") or {}
    for n in kit.YIELD_STAGES:
        ended = (stages.get(str(n)) or {}).get("ended")
        if not ended:
            fails.append(f"stage {n} has not ended: the yield rule has not stopped it")
            continue
        try:
            v = yield_stop.evaluate(ctx, n, as_of=ended)
        except kit.KitError as e:
            fails.append(f"stage {n}: {e}")
            continue
        line = yield_stop.describe(v)
        if v["verdict"] == "continue":
            fails.append(f"stage {n} was ended while the yield rule said continue — {line}")
        elif v["verdict"] == "ceiling":
            notes.append(f"stage {n} stopped at the ceiling ({v['ceiling']}) — {line}")
        else:
            notes.append(line)
    return verdict(18, "Yield stop", fails, [], notes)


ROWS = [row18]
