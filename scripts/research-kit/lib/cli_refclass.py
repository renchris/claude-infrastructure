"""cli_refclass.py — `cc-research reference-class record | show | check` (REPORT.md §8 item 15, §6.3).

The store is append-only JSON lines: env CC_RESEARCH_REFCLASS, else
<claude-infrastructure>/docs/research/research-reference-class.jsonl. One row per measured program
or studied case:

  {program|case, project_type, research_days, active_days|null, source, recorded_at}
  (+ cert_version on a recorded program; + note on a seeded case)

research_days is calendar time from first research to the first usable result. The seed rows are
the cases of evidence/internal/greenfield-cases.md:29-36; `record` adds a finished program, its
research days the span of budget.json stages 1-6.

  record --program P              frame.json project_type (refused when absent); idempotent per
                                  (program, certificate version)
  show [--type T] [--json]        per type: n, median and max research days
  check --type T --typical-days D exit 1 when D > 3 x the type's median research days, printing
                                  both figures (the contract page shows both and needs an override);
                                  no rows for T is "uncalibrated" and exits 0
"""

from __future__ import annotations

import argparse
import json
import os
import re
import statistics
from pathlib import Path
from typing import Any, Dict, List

import kit

REPO = Path(__file__).resolve().parents[3]
CHECK_FACTOR = 3  # §6.3: typical total over 3 x the type's measured research time
RESEARCH_STAGES = ("1", "2", "3", "4", "5", "6")
CERT_RE = re.compile(r"^CERT-v(\d+)\.json$")


def store() -> Path:
    env = os.environ.get("CC_RESEARCH_REFCLASS")
    return (
        Path(env)
        if env
        else REPO / "docs" / "research" / "research-reference-class.jsonl"
    )


def append(rec: Dict[str, Any]) -> None:
    p = store()
    p.parent.mkdir(parents=True, exist_ok=True)
    with p.open("a") as fh:
        fh.write(json.dumps(rec) + "\n")


def num(x: float) -> Any:
    """2.0 → 2 and 1.5 → 1.5, so figures print the way they were measured."""
    return int(x) if float(x).is_integer() else round(x, 2)


def by_type(rows: List[Dict[str, Any]]) -> Dict[str, List[float]]:
    out: Dict[str, List[float]] = {}
    for r in rows:
        if r.get("project_type") and r.get("research_days") is not None:
            out.setdefault(str(r["project_type"]), []).append(float(r["research_days"]))
    return out


def summary(t: str, days: List[float]) -> Dict[str, Any]:
    return {
        "project_type": t,
        "n": len(days),
        "median_days": num(statistics.median(days)),
        "max_days": num(max(days)),
    }


# ── record ──────────────────────────────────────────────────────────────────────────────────────


def cert_version(records: Path) -> int:
    vs = [
        int(m.group(1))
        for f in (records / "cert").glob("CERT-v*.json")
        for m in [CERT_RE.match(f.name)]
        if m
    ]
    if not vs:
        raise kit.KitError(
            f"no certificate under {records / 'cert'}: record runs once a program certifies"
        )
    return max(vs)


def research_days(records: Path) -> float:
    stages = (kit.read_json(records / "budget.json") or {}).get("stages") or {}
    starts: List[float] = []
    ends: List[float] = []
    for s in RESEARCH_STAGES:
        st = stages.get(s) or {}
        if not st.get("started"):
            continue
        if not st.get("ended"):
            raise kit.KitError(
                f"budget.json stage {s} has no `ended`: research is still running"
            )
        starts.append(kit.parse_iso(st["started"]))
        ends.append(kit.parse_iso(st["ended"]))
    if not starts:
        raise kit.KitError(
            f"budget.json under {records} records no started stage among 1-6"
        )
    return round((max(ends) - min(starts)) / 86400.0, 2)


def cmd_record(a: argparse.Namespace) -> int:
    slug = kit.check_slug(a.program)
    records = kit.records_dir(slug)
    frame = kit.read_json(records / "frame.json") or {}
    ptype = frame.get("project_type")
    if not ptype:
        raise kit.KitError(
            f"frame.json of {slug} names no project_type, so there is no reference class to add it to"
        )
    version = cert_version(records)
    rows = kit.read_jsonl(store())
    if any(r.get("program") == slug and r.get("cert_version") == version for r in rows):
        print(f"{slug} certificate v{version} already recorded in {store()}")
        return 0
    rec = {
        "program": slug,
        "project_type": ptype,
        "research_days": research_days(records),
        "active_days": None,
        "source": str(records / "budget.json"),
        "cert_version": version,
        "recorded_at": kit.now_iso(),
    }
    append(rec)
    print(
        f"recorded {slug} v{version}: {ptype}, {num(rec['research_days'])} research days"
    )
    return 0


# ── show / check ────────────────────────────────────────────────────────────────────────────────


def cmd_show(a: argparse.Namespace) -> int:
    types = by_type(kit.read_jsonl(store()))
    if a.type:
        types = {k: v for k, v in types.items() if k == a.type}
    out = [summary(t, d) for t, d in sorted(types.items())]
    if a.json:
        print(json.dumps({"store": str(store()), "types": out}, indent=1))
        return 0
    if not out:
        print(f"no reference rows{' for ' + a.type if a.type else ''} in {store()}")
    for s in out:
        print(
            f"{s['project_type']:<16} n={s['n']} median={s['median_days']} max={s['max_days']} research days"
        )
    return 0


def cmd_check(a: argparse.Namespace) -> int:
    if a.typical_days < 0:
        raise kit.KitError("--typical-days must be 0 or more")
    days = by_type(kit.read_jsonl(store())).get(a.type)
    res: Dict[str, Any] = {
        "project_type": a.type,
        "typical_days": num(a.typical_days),
        "uncalibrated": not days,
    }
    if not days:
        res.update(n=0, median_days=None, limit_days=None, over=False)
        line = f"uncalibrated: no reference class for {a.type}"
    else:
        s = summary(a.type, days)
        limit = CHECK_FACTOR * statistics.median(days)
        over = a.typical_days > limit
        res.update(
            n=s["n"], median_days=s["median_days"], limit_days=num(limit), over=over
        )
        both = (
            f"typical total {num(a.typical_days)} days; {a.type} research median "
            f"{s['median_days']} days over n={s['n']} (limit {CHECK_FACTOR} x = {num(limit)})"
        )
        line = (
            f"OVER: {both}. The contract page shows both figures and needs your signed override"
            if over
            else f"ok: {both}"
        )
    print(json.dumps(res, indent=1) if a.json else line)
    return 1 if res["over"] else 0


def add_verbs(sub: Any) -> None:
    """reference-class record | show | check."""
    p = sub.add_parser("reference-class", help="research time per project type (§6.3)")
    rs = p.add_subparsers(dest="refclass_verb", required=True)
    q = rs.add_parser("record")
    q.add_argument("--program", required=True)
    q.set_defaults(fn=cmd_record)
    q = rs.add_parser("show")
    q.add_argument("--type")
    q.add_argument("--json", action="store_true")
    q.set_defaults(fn=cmd_show)
    q = rs.add_parser("check")
    q.add_argument("--type", required=True)
    q.add_argument("--typical-days", type=float, required=True)
    q.add_argument("--json", action="store_true")
    q.set_defaults(fn=cmd_check)
