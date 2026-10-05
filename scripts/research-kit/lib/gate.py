"""gate.py — the §3.10 gate of the hand-run kit, and the only writer of the program registry.

Invoked through scripts/research-kit/gate.sh. Verbs:

  register  --program P --root <abs dir> [--root ...] [--alias A ...]
                                                            registry state -> registered; keeps any
                                                            roots already registered for P
  add-root  --program P --root <abs dir>                    append an existing dir to P's cwd_roots
                                                            (idempotent); state and aliases untouched
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
  close     --program P                                     state -> closed; refused for a
                                                            build-certified program until the
                                                            operator signs the implementation (§11)
  requires  --program P [--wave W] [--json]                 may build wave W fire? exit 0 clear,
                                                            1 refused (handoff-fire --requires-gate)
  built-freeze --program P --artifact <abs dir>             pin the built snapshot; state ->
                                                            build-certifying (REPORT.md §11)
  built-run --program P [--json]                            rows 20-25; all pass -> built
                                                            certificate, state -> build-certified
  built-signed --program P                                  a VALID operator signature on the built
                                                            certificate -> implementation-signed

Rows 1-8 live in gate_rows_a.py; rows 9-17 and the plan lint in gate_rows_b.py; the sweep and
file-packet verbs in gate_sweep.py; requires in gate_requires.py; freeze, render and the certificate in gate_cert.py. Each row function takes a Ctx and returns a Row. A row that cannot
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
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))  # heldout.py, estimate.py
import kit  # noqa: E402

PASS, FAIL, FILED = "PASS", "FAIL", "FILED"
ROW_COUNT = 19  # §3.10 rows 1-15, plus row 16: rounds and stage time against their caps (§10 item 17),
# row 17: an honest stop, dry or the cap reached by counted rounds (audit 2026-10-04, item 5d),
# and method v1.2's row 18 (yield stop) and row 19 (decision blockers), REPORT.md §12.
# The built gate's rows 20-25 (REPORT.md §11) run only under `built-run` (gate_built.py).


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
    import gate_rows_blockers
    import gate_rows_yield

    fns: List[Callable[[Ctx], Row]] = (
        list(gate_rows_a.ROWS)
        + list(gate_rows_b.ROWS)
        + list(gate_rows_yield.ROWS)
        + list(gate_rows_blockers.ROWS)
    )
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
            out.append(
                Row(n, "missing", FAIL, ["row not implemented — unknown fails (§3.10)"])
            )
    return sorted(out, key=lambda r: r.num)


def print_rows(rows: List[Row], as_json: bool) -> None:
    if as_json:
        print(json.dumps([r.__dict__ for r in rows], indent=2))
        return
    for r in rows:
        print(f"{r.num:>2}. {r.name:<24} {r.status}")
        for e in r.evidence:
            print(f"      {e}")


def merged_roots(prior: List[str], new: List[str]) -> List[str]:
    """prior + new, each absolute and normalized (realpath, no trailing slash), duplicates dropped.

    A program covers its build worktrees and sibling worktrees too (audit 2026-10-04 row 4e), so
    neither a re-register nor an add-root may drop a root already registered.
    """
    out: List[str] = []
    for r in list(prior) + list(new):
        if not os.path.isabs(r):
            raise kit.KitError(f"cwd_root {r!r} is not absolute")
        n = os.path.realpath(r)
        if n not in out:
            out.append(n)
    return out


def cmd_register(a: argparse.Namespace) -> int:
    prior = kit.registry_get(a.program)
    roots = merged_roots((prior or {}).get("cwd_roots") or [], a.root)
    # Like the roots, a re-register adds aliases and never drops the ones already stored.
    aliases = list(dict.fromkeys(list((prior or {}).get("aliases") or []) + (a.alias or [])))
    e = kit.registry_set(a.program, "registered", aliases=aliases, cwd_roots=roots)
    print(f"registered {e['slug']} roots={e['cwd_roots']} aliases={e['aliases']}")
    return 0


def cmd_add_root(a: argparse.Namespace) -> int:
    prior = kit.registry_get(a.program)
    if prior is None:
        raise kit.KitError(
            f"program {a.program!r} is not registered; register it first"
        )
    if not os.path.isabs(a.root):
        raise kit.KitError(f"cwd_root {a.root!r} is not absolute")
    if not os.path.isdir(a.root):
        raise kit.KitError(f"cwd_root {a.root!r} is not an existing directory")
    roots = merged_roots(prior.get("cwd_roots") or [], [a.root])
    e = kit.registry_set(a.program, prior["state"], cwd_roots=roots)
    print(f"added root to {e['slug']}: roots={e['cwd_roots']} state={e['state']}")
    return 0


def cmd_close(a: argparse.Namespace) -> int:
    # §11: a built certificate is not "done"; the operator's implementation signature is
    state = (kit.registry_get(a.program) or {}).get("state")
    if state in ("build-certified", kit.IMPL_SIGNED):
        import gate_built

        ok, why = gate_built.implementation_gate(a.program)
        if not ok:
            raise kit.KitError(f"close refused: {a.program} is {state} and {why}")
    kit.registry_set(a.program, "closed")
    print(f"closed {a.program}")
    return 0


def reopened(ctx: Ctx) -> bool:
    """A VALID operator reopen signed after the newest certificate (§5.1)."""
    import operator_sign

    rec = operator_sign.latest_valid(ctx.slug, "reopen")
    certs = sorted(
        ctx.records.glob("cert/CERT-v*.json"), key=lambda p: p.stat().st_mtime
    )
    return bool(rec) and (not certs or rec["at"] > certs[-1].stat().st_mtime)


def cmd_run(a: argparse.Namespace) -> int:
    import gate_cert

    ctx = make_ctx(a.program)
    if reopened(ctx):
        kit.registry_set(a.program, "registered")
        print(f"REOPENED {a.program} by operator signature; registry -> registered")
    rows = run_rows(ctx)
    print_rows(rows, a.json)
    if any(r.status not in (PASS, FILED) for r in rows):
        return 1
    cert = gate_cert.write_certificate(ctx, rows)
    kit.registry_set(a.program, "certified")
    if not a.json:
        print(f"CERTIFIED {a.program}: {cert}")
    return 0


def main(argv: Optional[List[str]] = None) -> int:
    ap = argparse.ArgumentParser(prog="gate.sh")
    sub = ap.add_subparsers(dest="verb", required=True)
    p = sub.add_parser("register")
    p.add_argument("--program", required=True)
    p.add_argument("--root", required=True, action="append")
    p.add_argument("--alias", action="append")
    p.set_defaults(fn=cmd_register)
    p = sub.add_parser("add-root")
    p.add_argument("--program", required=True)
    p.add_argument("--root", required=True)
    p.set_defaults(fn=cmd_add_root)
    p = sub.add_parser("close")
    p.add_argument("--program", required=True)
    p.set_defaults(fn=cmd_close)
    p = sub.add_parser("run")
    p.add_argument("--program", required=True)
    p.add_argument("--json", action="store_true")
    p.set_defaults(fn=cmd_run)

    import gate_built
    import gate_cert
    import gate_requires
    import gate_sweep

    gate_cert.add_verbs(sub)  # freeze, render
    gate_sweep.add_verbs(sub)  # sweep, file-packet
    gate_requires.add_verbs(sub)  # requires
    gate_built.add_verbs(sub)  # built-freeze, built-run (REPORT.md §11)

    a = ap.parse_args(argv)
    try:
        if a.verb not in ("render", "requires"):  # every other gate verb writes
            kit.lease_check(kit.check_slug(a.program))
        return int(a.fn(a))
    except kit.KitError as e:
        print(f"gate.sh: {e}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
