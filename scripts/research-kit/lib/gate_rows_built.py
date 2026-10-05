"""gate_rows_built.py — the built gate, rows 20-25 (REPORT.md §11, method v1.2).

Run only by `gate.sh built-run` (gate_built.py), never by the research gate. Each row function takes
a Ctx and returns a Row; a row that cannot be evaluated is FAIL ("Unknown fails", §3.10).
"""

from __future__ import annotations

from typing import Callable, List

from gate import FAIL, Ctx, Row

BUILT_ROWS = {20: "Built snapshot", 21: "Repro", 22: "Harness mutation", 23: "As-built contact",
              24: "Soak", 25: "Built rounds"}
ROWS: List[Callable[[Ctx], Row]] = []


def run_built_rows(ctx: Ctx) -> List[Row]:
    """Every row 20-25, in order. A missing or crashing row is a FAIL, never a pass."""
    out: List[Row] = []
    for fn in ROWS:
        try:
            out.append(fn(ctx))
        except Exception as e:
            num, name = getattr(fn, "row", (0, fn.__name__))
            out.append(Row(num, name, FAIL, [f"row raised {type(e).__name__}: {e}"]))
    have = {r.num for r in out}
    for n, name in BUILT_ROWS.items():
        if n not in have:
            out.append(Row(n, name, FAIL, ["row not implemented — unknown fails (§3.10)"]))
    return sorted(out, key=lambda r: r.num)
