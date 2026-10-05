"""cli_yield.py — cc-research yield show|find, the yield stop of stages 3 and 5 (REPORT.md §12.1).

  yield show --program P --stage N [--json]   the verdict and its numbers; exit 0 on stop or
                                              ceiling, 1 on continue
  yield find --program P --probe P-.. --ref ID  tie a probe to the record it produced, so it
                                              counts as a find (yield.jsonl, append-only)
"""

from __future__ import annotations

import argparse
import json
from typing import Any, Optional

import kit
import yield_stop


def ctx_for(slug: str) -> Any:
    import gate

    return gate.make_ctx(slug)


def cmd_show(a: argparse.Namespace) -> int:
    v = yield_stop.evaluate(ctx_for(a.program), a.stage)
    print(json.dumps(v, indent=2) if a.json else yield_stop.describe(v))
    return 1 if v["verdict"] == "continue" else 0


def ref_kind(ctx: Any, ref: str) -> Optional[str]:
    """Where the ref lives, or None. A premise only counts once it reads refuted."""
    prem = kit.fold(ctx.jsonl("premises.jsonl")).get(ref)
    if prem is not None:
        if prem.get("verdict") != "refuted":
            raise kit.KitError(
                f"premise {ref} reads {prem.get('verdict')!r}, not 'refuted': a probe that "
                "confirmed a premise is quiet, not a find"
            )
        return "premise"
    for rel, kind in (("holes.jsonl", "hole"), ("changes.jsonl", "change"),
                      ("residual.jsonl", "residual")):
        if ref in kit.fold(ctx.jsonl(rel)):
            return kind
    if any(r.get("id") == ref for r in ctx.frame.get("known_rows") or []):
        return "frame-row"
    return None


def probe_stage(ctx: Any, at: str) -> Optional[int]:
    """The yield stage whose window holds this time."""
    stages = (ctx.json("budget.json") or {}).get("stages") or {}
    t = kit.parse_iso(at)
    for n in kit.YIELD_STAGES:
        st = stages.get(str(n)) or {}
        if not st.get("started"):
            continue
        end = kit.parse_iso(st["ended"]) if st.get("ended") else kit.parse_iso(kit.now_iso())
        if kit.parse_iso(st["started"]) <= t <= end:
            return n
    return None


def cmd_find(a: argparse.Namespace) -> int:
    ctx = ctx_for(a.program)
    probe = kit.fold(ctx.jsonl("probes.jsonl")).get(a.probe)
    if not probe:
        raise kit.KitError(f"no probe {a.probe} in probes.jsonl")
    kind = ref_kind(ctx, a.ref)
    if kind is None:
        raise kit.KitError(
            f"{a.ref} is not a premise, hole, change, residual or frame row of {a.program}: "
            "a find names the record the probe produced"
        )
    stage = probe_stage(ctx, str(probe.get("at")))
    if stage is None:
        raise kit.KitError(
            f"probe {a.probe} ran outside stages "
            f"{' and '.join(str(s) for s in kit.YIELD_STAGES)}: only those stop on yield"
        )
    if any(r.get("probe") == a.probe and r.get("ref") == a.ref for r in ctx.jsonl("yield.jsonl")):
        raise kit.KitError(f"{a.probe} is already tied to {a.ref}")
    kit.append_jsonl(ctx.path("yield.jsonl"), {
        "probe": a.probe, "ref": a.ref, "ref_kind": kind, "stage": stage, "at": kit.now_iso()})
    print(f"{a.probe} is a find: {kind} {a.ref} (stage {stage})")
    return 0


def add_verbs(sub: Any) -> None:
    y = sub.add_parser("yield", help="the yield stop of stages 3 and 5 (method v1.2)")
    ys = y.add_subparsers(dest="yield_verb", required=True)
    p = ys.add_parser("show")
    p.add_argument("--program", required=True)
    p.add_argument("--stage", type=int, required=True)
    p.add_argument("--json", action="store_true")
    p.set_defaults(fn=cmd_show)
    p = ys.add_parser("find")
    p.add_argument("--program", required=True)
    p.add_argument("--probe", required=True)
    p.add_argument("--ref", required=True)
    p.set_defaults(fn=cmd_find)
