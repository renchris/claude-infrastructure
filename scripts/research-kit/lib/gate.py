"""gate.py — the §3.10 gate of the hand-run kit, and the only writer of the program registry.

Invoked through scripts/research-kit/gate.sh. Verbs:

  register  --program P --root <abs dir> [--alias A ...]   registry state -> registered
  freeze    --program P                                     freeze checks; state -> certifying
                                                            (§10 item 1: the relay test then runs
                                                            with the research block on)
  run       --program P [--json]                            every row PASS/FAIL/FILED with
                                                            evidence; all pass -> certificate
                                                            written, state -> certified
  render    --program P                                     the certificate's state lines (§4.3),
                                                            the only read a completeness turn may make
  sweep     --program P                                     class-B/class-C due-date sweep (§10 item 4)
  file-packet --program P --decision D ...                  cc-decide open with the program's
                                                            --project and --default-effect no-change
  close     --program P                                     state -> closed

Rows 1-8 and the freeze/render/certificate verbs live in gate_rows_a.py; rows 9-16, the sweep and
file-packet in gate_rows_b.py. Each row function takes a Ctx and returns a Row. A row that cannot
be evaluated is FAIL ("Unknown fails", §3.10); a row function that raises is FAIL with the error.
Exit codes: 0 all rows PASS/FILED (or verb succeeded) · 1 a row FAILed · 2 usage or refusal.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "lib"))
import kit  # noqa: E402

PASS, FAIL, FILED = "PASS", "FAIL", "FILED"
ROW_COUNT = 16   # §3.10 rows 1-15, plus row 16: rounds and stage time against their caps (§10 item 17)


@dataclass
class Row:
    num: int
    name: str
    status: str  # PASS | FAIL | FILED
    evidence: List[str] = field(default_factory=list)


@dataclass
class Ctx:
    slug: str
    records: Path  # tracked records dir, docs/research/<slug>/
    sealed: Path  # sealed dir, $CC_RESEARCH_HOME/<slug>/

    def path(self, rel: str) -> Path:
        return self.records / rel

    def jsonl(self, rel: str) -> List[Dict[str, Any]]:
        return kit.read_jsonl(self.records / rel)

    def json(self, rel: str, default: Any = None) -> Any:
        return kit.read_json(self.records / rel, default)

    @property
    def frame(self) -> Dict[str, Any]:
        return self.json("frame.json", {}) or {}


def make_ctx(slug: str) -> Ctx:
    kit.check_slug(slug)
    return Ctx(slug=slug, records=kit.records_dir(slug), sealed=kit.sealed_dir(slug))


def run_rows(ctx: Ctx) -> List[Row]:
    import gate_rows_a
    import gate_rows_b

    fns: List[Callable[[Ctx], Row]] = list(gate_rows_a.ROWS) + list(gate_rows_b.ROWS)
    out = []
    for fn in fns:
        try:
            out.append(fn(ctx))
        except (
            Exception
        ) as e:  # a row that crashes is a FAIL with its error, never a pass
            num, name = getattr(fn, "row", (0, fn.__name__))
            out.append(Row(num, name, FAIL, [f"row raised {type(e).__name__}: {e}"]))
    # Every row 1..ROW_COUNT must be present: a gate that silently lost a row would certify more
    # easily, which is the one direction a gate may never fail in.
    have = {r.num for r in out}
    for n in range(1, ROW_COUNT + 1):
        if n not in have:
            out.append(Row(n, "missing", FAIL, ["row not implemented — unknown fails (§3.10)"]))
    return sorted(out, key=lambda r: r.num)


def print_rows(rows: List[Row], as_json: bool) -> None:
    if as_json:
        print(json.dumps([r.__dict__ for r in rows], indent=2))
        return
    for r in rows:
        print(f"{r.num:>2}. {r.name:<24} {r.status}")
        for e in r.evidence:
            print(f"      {e}")


def cmd_register(a: argparse.Namespace) -> int:
    e = kit.registry_set(
        a.program, "registered", aliases=a.alias or [], cwd_roots=[a.root]
    )
    print(f"registered {e['slug']} roots={e['cwd_roots']} aliases={e['aliases']}")
    return 0


def cmd_close(a: argparse.Namespace) -> int:
    kit.registry_set(a.program, "closed")
    print(f"closed {a.program}")
    return 0


def cmd_run(a: argparse.Namespace) -> int:
    import gate_rows_a

    ctx = make_ctx(a.program)
    rows = run_rows(ctx)
    print_rows(rows, a.json)
    if any(r.status not in (PASS, FILED) for r in rows):
        return 1
    cert = gate_rows_a.write_certificate(ctx, rows)
    kit.registry_set(a.program, "certified")
    if not a.json:
        print(f"CERTIFIED {a.program}: {cert}")
    return 0


def main(argv: Optional[List[str]] = None) -> int:
    ap = argparse.ArgumentParser(prog="gate.sh")
    sub = ap.add_subparsers(dest="verb", required=True)
    p = sub.add_parser("register")
    p.add_argument("--program", required=True)
    p.add_argument("--root", required=True)
    p.add_argument("--alias", action="append")
    p.set_defaults(fn=cmd_register)
    p = sub.add_parser("close")
    p.add_argument("--program", required=True)
    p.set_defaults(fn=cmd_close)
    p = sub.add_parser("run")
    p.add_argument("--program", required=True)
    p.add_argument("--json", action="store_true")
    p.set_defaults(fn=cmd_run)

    import gate_rows_a
    import gate_rows_b

    gate_rows_a.add_verbs(sub)  # freeze, render
    gate_rows_b.add_verbs(sub)  # sweep, file-packet

    a = ap.parse_args(argv)
    try:
        return int(a.fn(a))
    except kit.KitError as e:
        print(f"gate.sh: {e}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
