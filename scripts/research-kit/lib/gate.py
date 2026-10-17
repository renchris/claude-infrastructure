"""gate.py — the §3.10 gate of the hand-run kit, and the only writer of the program registry.

Invoked through scripts/research-kit/gate.sh. Verbs:

  register  --program P --root <abs dir> [--root ...] [--alias A ...]
                                                            registry state -> registered; keeps any
                                                            roots already registered for P
  add-root  --program P --root <abs dir>                    append an existing dir to P's cwd_roots
                                                            (idempotent); state and aliases untouched
  freeze    --program P                                     freeze checks; state -> certifying
                                                            (§10 item 1: the relay test then runs
                                                            with the research block on); opens the
                                                            certification-round activity when a
                                                            certification round is due
  cert-activity --program P                                 print (opening if none) the open
                                                            certification-round activity's id;
                                                            refused unless certifying, frozen and
                                                            a certification round is due, or the
                                                            last round still owes a settle step
                                                            (then settle-only, round.py settle_owed)
  return-activity --program P --area A --because "<why>"    print (opening if none) the area's
                                                            front-end-return activity id (§6.1);
                                                            only between two certification rounds,
                                                            once per area, capped per profile;
                                                            freeze closes it
  rehearsal-activity --program P                            print (opening if none) the rehearsal
                                                            activity id (§3.8); only after the
                                                            stop, with no settle step owed and no
                                                            return open, while the relay test has
                                                            not passed or used its re-test;
                                                            rehearse record closes it
  delta-activity --program P                                print (opening if none) the frame-delta
                                                            activity id (§5.4); only while a
                                                            re-signed frame carries an open held
                                                            omission's delta (gate_delta.py); run
                                                            closes it with those rows
  run       --program P [--json]                           every row PASS/FAIL/FILED with
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
                                                            1 refused (handoff-fire --requires-gate),
                                                            2 a wave id outside the program's set
  waves     --program P [--json]                            the program's wave ids, where each is
                                                            named, twins and stray text; exit 1
                                                            while the set is not canonical
  rekey-wave --program P --row ID --from X --to Y --reason T
                                                            re-spell a known row's or decision's
                                                            wave by an appended event
  built-freeze --program P --artifact <abs dir>             pin the built snapshot; state ->
                                                            build-certifying (REPORT.md §11)
  built-run --program P [--json]                            rows 20-25; all pass -> built
                                                            certificate, state -> build-certified
  built-signed --program P                                  a VALID operator signature (or delegated
                                                            acceptance) on the built certificate ->
                                                            implementation-signed
  accept    --program P --action A [--target T] [--because W] [--check] [--json]
                                                            under the operator's standing delegation,
                                                            accept A (cert, frame, implementation,
                                                            extra-round, reopen, profile/<p>,
                                                            adopt/stage9, extend-decision/<id>) when
                                                            its machine criteria hold (gate_accept.py,
                                                            REPORT.md §14)

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
    # Wave E1l (ruling a7fd5e2ee7c8 guard 1): row 15 spends a sealed read only with the operator's
    # consent for this run (gate.sh run --consent-sealed-read), and only after every other row of the
    # same run passed; run_rows hands it those rows here.
    read_consent: bool = False
    prior: Optional[List["Row"]] = None

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

    def one(fn: Callable[[Ctx], Row]) -> Row:
        try:
            return fn(ctx)
        except (
            Exception
        ) as e:  # a row that crashes is a FAIL with its error, never a pass
            num, name = getattr(fn, "row", (0, fn.__name__))
            return Row(num, name, FAIL, [f"row raised {type(e).__name__}: {e}"])

    # A row marked runs_last (row 15, wave E1l) runs after every other row and sees their results.
    out = [one(fn) for fn in fns if not getattr(fn, "runs_last", False)]
    ctx.prior = list(out)
    out += [one(fn) for fn in fns if getattr(fn, "runs_last", False)]
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
    aliases = list(
        dict.fromkeys(list((prior or {}).get("aliases") or []) + (a.alias or []))
    )
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


def reopen_record(ctx: Ctx) -> Optional[Dict[str, Any]]:
    """The VALID reopen (the operator's, or a delegated acceptance of one) dated after the newest
    certificate was issued (§5.1), or None. The certificate's own `issued` is the clock: a file's
    mtime moves on a touch or a re-checkout and would hide a reopen; mtime is read only for a
    certificate that records no issue time."""
    import operator_sign
    from gate_requires import _cert_no

    rec = operator_sign.latest_valid(ctx.slug, "reopen")
    if not rec:
        return None
    certs = sorted(ctx.records.glob("cert/CERT-v*.json"), key=_cert_no)
    if not certs:
        return rec
    try:
        issued = kit.parse_iso(str((kit.read_json(certs[-1]) or {}).get("issued")))
    except ValueError:
        issued = certs[-1].stat().st_mtime
    return rec if float(rec.get("at") or 0) > issued else None


def reopened(ctx: Ctx) -> bool:
    """A VALID operator reopen (or delegated acceptance of one) after the newest certificate (§5.1)."""
    return reopen_record(ctx) is not None


def reopen_phrase(ctx: Ctx) -> str:
    """Who reopened, for a refusal: '<subject> is signed|recorded', said as delegated where it is."""
    import operator_sign

    rec = reopen_record(ctx) or {}
    if rec.get("_delegated"):
        return f"a reopen {operator_sign.DELEGATED_WORDS} is recorded"
    return "an operator reopen is signed"


def cmd_run(a: argparse.Namespace) -> int:
    import gate_cert

    ctx = make_ctx(a.program)
    ctx.read_consent = a.consent_sealed_read
    if reopened(ctx):
        import operator_sign

        rec = operator_sign.latest_valid(a.program, "reopen") or {}
        how = (
            f"a reopen {operator_sign.DELEGATED_WORDS}"
            if rec.get("_delegated")
            else "operator signature"
        )
        kit.registry_set(a.program, "registered")
        print(f"REOPENED {a.program} by {how}; registry -> registered")
    rows = run_rows(ctx)
    print_rows(rows, a.json)
    if any(r.status not in (PASS, FILED) for r in rows):
        return 1
    cert = gate_cert.write_certificate(ctx, rows)
    kit.registry_set(a.program, "certified")
    closed = close_delta_rows(ctx, Path(cert).stem)
    import gate_delta

    closed += gate_delta.close_cycle(ctx, Path(cert).stem)
    if not a.json:
        print(f"CERTIFIED {a.program}: {cert}")
        for line in closed:
            print(line)
    return 0


def delta_signature(ctx: Ctx, kid: str, held: str) -> Optional[Dict[str, Any]]:
    """The operator frame signature (or delegated acceptance, REPORT.md §14: research_records returns
    both) that carries known row `kid`'s delta, or None (RECORDS.md "Held
    frame omissions and re-finds", "The delta's evidence"). Positive evidence only: a VALID signature
    dated after the hold whose pinned frame.json lists `kid` in `known_rows_applied` (VALID means the
    pin is the frame as it stands, so reading the frame now reads what was signed), pinning another
    frame than the newest non-void signature at or before the hold did. A re-sign that changes
    nothing, or carries another row's delta, is no evidence for this one: reading "any valid frame
    signature newer than the hold" let truememory-2-0's 2026-10-12 re-sign, which added none of their
    rows, spare KR-06..09 and stand ready to close them. No signature at or before the hold: none."""
    import operator_sign

    if not held or kid not in (ctx.frame.get("known_rows_applied") or []):
        return None
    sigs = [
        r
        for r in operator_sign.research_records(ctx.slug, "frame")
        if r["_verdict"] != operator_sign.VOID
    ]

    def at(r: Dict[str, Any]) -> str:
        return str(r.get("at_iso") or "")

    before = [r for r in sigs if at(r) <= held]
    if not before:
        return None
    base = (max(before, key=at).get("pins") or {}).get("frame.json")
    after = [r for r in sigs if r["_verdict"] == operator_sign.VALID and at(r) > held]
    for r in sorted(after, key=at, reverse=True):
        pin = (r.get("pins") or {}).get("frame.json")
        if pin and pin != base:
            return r
    return None


def close_delta_rows(ctx: Ctx, cert: str) -> List[str]:
    """§5.4 step 4, given its actuator by method v1.3 (REPORT.md §13): a certificate issued after the
    operator re-signed a frame that carries a held row's delta (delta_signature) closes that open
    frame-omission known row, so `requires` stops holding its waves. This run passed every row, row 1
    included, so the re-signed frame is the one certified. A row with no held time is left to the
    sweep."""
    from gate_rows_a import held_at, known_rows

    held = held_at(ctx)
    out: List[str] = []
    for kr in known_rows(ctx):
        if (
            kr.get("kind") != "frame-omission"
            or kr.get("status", "open") != "open"
            or not held.get(kr["id"])
        ):
            continue
        sig = delta_signature(ctx, kr["id"], held[kr["id"]])
        if not sig:
            continue
        import operator_sign

        how = (
            operator_sign.signed_words(sig)
            if sig.get("_delegated")
            else f"re-signed {sig.get('at_iso')}"
        )
        why = (
            f"frame-delta cycle: frame {how} carries {kr['id']}, "
            f"certificate re-issued as {cert}"
        )
        kit.append_jsonl(
            ctx.records / "known_rows.jsonl",
            {"id": kr["id"], "status": "closed", "closed_by": cert, "why": why},
        )
        out.append(f"closed known row {kr['id']} ({why})")
    return out


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
    p.add_argument(
        "--consent-sealed-read",
        action="store_true",
        help="row 15 may spend a read of the sealed held-out set(s) (wave E1l); without it row 15 "
        "fails and reads nothing",
    )
    p.set_defaults(fn=cmd_run)

    import gate_accept
    import gate_built
    import gate_cert
    import gate_requires
    import gate_sweep

    gate_accept.add_verbs(sub)  # accept (REPORT.md §14)

    gate_cert.add_verbs(
        sub
    )  # freeze, cert-activity, return-activity, rehearsal-activity, render, delta-activity
    gate_sweep.add_verbs(sub)  # sweep, file-packet
    gate_requires.add_verbs(sub)  # requires
    gate_built.add_verbs(sub)  # built-freeze, built-run (REPORT.md §11)
    import scheduled_read

    scheduled_read.add_gate_verbs(sub)  # read (method v1.3, REPORT.md §13.1)

    a = ap.parse_args(argv)
    try:
        practice = (a.verb == "read" and getattr(a, "practice", False)) or (
            a.verb == "accept" and getattr(a, "check", False)
        )  # writes nothing
        if (
            a.verb not in ("render", "requires", "waves") and not practice
        ):  # every other gate verb writes
            kit.lease_check(kit.check_slug(a.program))
        return int(a.fn(a))
    except kit.KitError as e:
        print(f"gate.sh: {e}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
