"""blockers.py — what blocks a decision below 90 (REPORT.md §12.2 and §12.3, method v1.2).

`tag` is the one implementation behind gate row 19 (gate_rows_blockers.py) and the extension
items of `cc-research menu` (cli_core.menu). The tag is computed from the decision's tally, the
premises' evidence levels and the residual rows; nothing here is typed by hand.
Python 3.9-safe, standard library only.
"""

from __future__ import annotations

from typing import Any, Dict, List, Optional, Set

import kit

DAY = 86400.0
FLIP = "flip-probe"  # the pseudo-gap: the "what would flip it" probe has not come back negative
PRODUCTION = ("production-traffic", "external-tenant-not-held", "elapsed-time")
OPERATOR = ("operator-eye",)
TAGS = ("research", "production", "operator")  # precedence: the first tag any gap carries wins


def residual_reasons(ctx: Any) -> Dict[str, Set[str]]:
    """premise id -> the why_unreachable of every residual row naming it (`premise`/`premises`)."""
    out: Dict[str, Set[str]] = {}
    for r in kit.fold(ctx.jsonl("residual.jsonl")).values():
        named = list(r.get("premises") or []) + ([r["premise"]] if r.get("premise") else [])
        for pid in named:
            out.setdefault(str(pid), set()).add(str(r.get("why_unreachable")))
    return out


def gap_tag(premise: Optional[Dict[str, Any]], reasons: Set[str]) -> str:
    """One below-level premise's tag: who or what could close it."""
    if premise is None:
        return "research"
    if premise.get("truth_lives_in") == "operator" or reasons & set(OPERATOR):
        return "operator"
    if reasons & set(PRODUCTION):
        return "production"
    return "research"


def extensions(slug: str, decision_id: str) -> int:
    """VALID operator `extend-decision` signatures for this decision (§12.3)."""
    import operator_sign

    return sum(
        1
        for r in operator_sign.research_records(slug, "extend-decision", decision_id)
        if r["_verdict"] == operator_sign.VALID
    )


def at_ceiling(decision: Dict[str, Any], extended: bool) -> Optional[bool]:
    """Has research on this decision run to its ceiling? None when the timebox is not on record."""
    try:
        box = float(decision["timebox_days"])
        started = kit.parse_iso(str(decision["research_started"]))
    except (KeyError, TypeError, ValueError):
        return None
    if box <= 0:
        return None
    factor = kit.CAPS["decision_research_ceiling_factor"] + (1 if extended else 0)
    return (kit.parse_iso(kit.now_iso()) - started) / DAY >= factor * box


def tag(ctx: Any, decision: Dict[str, Any]) -> Dict[str, Any]:
    """{tag, conviction, gaps, gap_tags, reachable_max, at_ceiling, extended, extensions}.

    `tag` is None at 90 or more. `reachable_max` is the conviction the §3.5 rule would give if
    research closed every gap research can reach.
    """
    prem = kit.fold(ctx.jsonl("premises.jsonl"))
    probes = kit.fold(ctx.jsonl("probes.jsonl"))
    conv = kit.conviction(decision, prem, probes)
    n_ext = extensions(ctx.slug, str(decision.get("id")))
    out: Dict[str, Any] = {
        "tag": None, "conviction": conv, "gaps": [], "gap_tags": {}, "reachable_max": conv,
        "extended": n_ext > 0, "extensions": n_ext,
        "at_ceiling": at_ceiling(decision, n_ext > 0),
    }
    if conv is not None and conv >= 90:
        return out
    if conv is None:  # no factual premise: a taste or value call the operator rules (§3.5)
        out["tag"] = "operator"
        return out
    tally = decision.get("tally") or {}
    ids: List[str] = list(tally.get("premises") or decision.get("premises") or [])
    reasons = residual_reasons(ctx)
    tags: Dict[str, str] = {}
    for pid in ids:
        if pid in prem and kit.premise_at_level(prem[pid], probes):
            continue
        tags[pid] = gap_tag(prem.get(pid), reasons.get(pid, set()))
    flip = tally.get("flip_probe")
    if not (flip and tally.get("flip_result") == "negative"
            and kit.probe_level(probes.get(flip, {})) > 0):
        tags[FLIP] = "research"
    beyond = sum(1 for g, t in tags.items() if g != FLIP and t != "research")
    out.update(
        tag=next(t for t in TAGS if t in tags.values()),
        gaps=list(tags),
        gap_tags=tags,
        reachable_max=90 if not beyond else (89 * (len(ids) - beyond)) // len(ids),
    )
    return out
