"""yield_stop.py — stages 3 and 5 end on yield, not on the stage clock (REPORT.md §12.1, v1.2).

`evaluate` is the one implementation behind `cc-research yield show`, the `budget end` refusal
(cli_core.cmd_budget) and gate row 18 (gate_rows_yield.py). Every figure comes from kit.CAPS and
the profile; nothing here is typed by hand. Python 3.9-safe, standard library only.
"""

from __future__ import annotations

import math
from typing import Any, Dict, List, Optional, Tuple

import kit

DAY = 86400.0
MIN_SPAN_S = 3600.0  # the yield window's span is floored at one hour


def escape_cost(frame: Dict[str, Any]) -> float:
    """frame.json escape_cost_days as a finite positive number (§9 decision 5), else a refusal."""
    raw = frame.get("escape_cost_days")
    try:
        cost = float(raw)
    except (TypeError, ValueError):
        cost = float("nan")
    if not math.isfinite(cost) or cost <= 0:
        raise kit.KitError(
            f"frame.json escape_cost_days is {raw!r}: the yield rule needs a finite positive "
            "number of research days (§12.1)"
        )
    return cost


def stage_record(ctx: Any, stage: int) -> Dict[str, Any]:
    if stage not in kit.YIELD_STAGES:
        raise kit.KitError(
            f"stage {stage} does not stop on yield: only stages "
            f"{', '.join(str(s) for s in kit.YIELD_STAGES)} do (§12.1)"
        )
    st = ((ctx.json("budget.json") or {}).get("stages") or {}).get(str(stage)) or {}
    if not st.get("started"):
        raise kit.KitError(f"stage {stage} never started; there is no yield to read")
    return st


def counted_probes(ctx: Any, start: float, end: float) -> List[Tuple[float, str, bool]]:
    """(at, probe id, is a find) for every counted probe in the window, oldest first.

    Counted: it failed, or it passed and showed it could fail (kit.probe_level > 0). A find: the
    tool tied it to a record (yield.jsonl), or it failed and nobody has explained it yet.
    """
    named = {str(r.get("probe")) for r in ctx.jsonl("yield.jsonl")}
    out: List[Tuple[float, str, bool]] = []
    for p in kit.fold(ctx.jsonl("probes.jsonl")).values():
        if not p.get("at"):
            continue
        at = kit.parse_iso(str(p["at"]))
        if not start <= at <= end:
            continue
        failed = p.get("exit") != 0
        if not failed and kit.probe_level(p) == 0:
            continue  # it could not fail, so it teaches nothing
        out.append((at, str(p.get("id")), failed or str(p.get("id")) in named))
    return sorted(out)


def evaluate(ctx: Any, stage: int, as_of: Optional[str] = None) -> Dict[str, Any]:
    """The §12.1 verdict for one stage: continue, stop (quiet) or ceiling."""
    st = stage_record(ctx, stage)
    prof = kit.profile(ctx.frame.get("profile") or "")
    cost = escape_cost(ctx.frame)
    start = kit.parse_iso(str(st["started"]))
    at = as_of or st.get("ended") or kit.now_iso()
    end = kit.parse_iso(str(at))
    probes = counted_probes(ctx, start, end)
    k = int(prof["quiet_probes_to_stop"])
    streak = 0
    for _, _, find in reversed(probes):
        if find:
            break
        streak += 1
    window = probes[-kit.CAPS["yield_window_factor"] * k:]
    finds = sum(1 for _, _, find in window if find)
    span = max(window[-1][0] - window[0][0], MIN_SPAN_S) / DAY if window else 0.0
    rate = finds / span if finds else 0.0
    voi = rate * cost
    days = (end - start) / DAY
    cap_days = kit.CAPS["yield_ceiling_factor"] * prof["stage_days"][stage]
    ceiling: Optional[str] = None
    if days >= cap_days:
        ceiling = "days"
    elif len(probes) >= kit.CAPS["yield_probe_ceiling"]:
        ceiling = "probes"
    if ceiling:
        verdict = "ceiling"
    elif streak < k or voi > 1:
        verdict = "continue"
    else:
        verdict = "stop"
    return {
        "stage": stage,
        "verdict": verdict,
        "reason": {"stop": "quiet", "ceiling": "ceiling"}.get(verdict),
        "ceiling": ceiling,
        "k": k,
        "streak": streak,
        "counted": len(probes),
        "finds": finds,
        "yield_per_day": round(rate, 3),
        "escape_cost_days": cost,
        "voi": round(voi, 3),
        "days": round(days, 3),
        "ceiling_days": cap_days,
        "at": at,
    }


def describe(v: Dict[str, Any]) -> str:
    """One line a person can read: the verdict and the numbers behind it."""
    head = {
        "continue": "keep probing",
        "stop": "stop: the stage is quiet",
        "ceiling": f"stop: the hard ceiling was reached ({v['ceiling']})",
    }[v["verdict"]]
    return (
        f"stage {v['stage']}: {head} · {v['streak']} quiet in a row of {v['k']} needed · "
        f"{v['finds']} finds in the last {kit.CAPS['yield_window_factor'] * v['k']} probes, "
        f"{v['yield_per_day']:g} per day × escape cost {v['escape_cost_days']:g} d = "
        f"{v['voi']:g} (keep going above 1) · {v['counted']} probes, {v['days']:g} d of a "
        f"{v['ceiling_days']:g} d ceiling"
    )


def stop_record(v: Dict[str, Any]) -> Dict[str, Any]:
    """The budget.json stages.<n>.stop shape (RECORDS.md)."""
    keys = ("reason", "ceiling", "k", "streak", "counted", "finds", "yield_per_day",
            "escape_cost_days", "voi", "at")
    return {key: v[key] for key in keys}
