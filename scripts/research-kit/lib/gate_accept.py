"""gate_accept.py — `gate.sh accept`: an agent accepts a phase under the operator's standing delegation
(REPORT.md §14, ruled 2026-10-16; RECORDS.md "Delegated acceptance").

  gate.sh accept --program P --action A [--target T] [--because "<why>"] [--check] [--json]

A is cert, frame, implementation, extra-round, reopen, profile/<lite|standard>, adopt/stage9 or
extend-decision/<decision id> (the target may also be passed as --target). The verb writes ONE record
to $CC_RESEARCH_HOME/<P>/delegated.jsonl, a log apart from the operator's signoff.jsonl, and only when

  1. a delegation the operator signed (`cc-signoff research:<P|*>/delegate`) is in force for P now; and
  2. every machine criterion of A holds (the names are operator_sign.DELEGATED_CRITERIA):

  cert            state certified or a Stage 9 state · the newest CERT-v<n> exists · it carries rows,
                  each PASS or FILED · no reopen is signed or accepted after it. Pins it.
  frame           `intake.py lint` clean · the frame's newest change is the newest frame-deltas.jsonl
                  entry (same version, and frame.json still hashes to what that apply wrote) · the
                  delta names known rows, each an open frame-omission row · no decision annotation
                  or decisions.jsonl prefix outside a delta's pin. Pins frame.json.
  implementation  state build-certified or implementation-signed · the newest BUILT-CERT-v<n> is
                  this program's · rows 20-25 present, every one PASS · its snapshot is the one
                  built/freeze.json pins. Pins it, then runs built-signed (the registry move).
  extra-round     state certifying (the only state whose rounds it changes) · none bought yet.
  reopen          state certified or a Stage 9 state · a certificate exists · none after it yet.
  profile/<name>  operator_sign.profile_switch_terms: certifying, between two certification
                  rounds, narrower, a counted round behind it and one still to run, once.
  adopt/stage9    the frame predates method 1.2 · not adopted yet.
  extend-decision/<id>  the decision is on record and not descoped · research can still raise it
                  (blockers.tag reads "research", as the menu offers it) · not extended yet.

The five without an artifact need --because, as the operator's signature does. Third reads and vetoes
are never delegable, nor is the delegation itself: each is refused, naming why. The record names the
delegation (id and sha256) and every criterion with its value; every reader of a signature honours it
exactly where it honours the operator's (operator_sign.research_records) and prints it as "accepted by
delegation (not read by the operator)". --check evaluates and prints, writing nothing.

Exit 0 accepted (or already accepted or signed) · 1 a criterion failed, nothing written · 2 usage, no
delegation in force, or an action that is not delegable.
"""

from __future__ import annotations

import argparse
import json
import time
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import kit
import operator_sign as osign

Crit = Dict[str, Any]
POST_CERT = ("certified",) + kit.STAGE9_STATES
NEEDS_BECAUSE = ("extra-round", "reopen", "profile", "adopt", "extend-decision")
TARGETED = ("profile", "adopt", "extend-decision")


def crit(name: str, ok: bool, value: Any) -> Crit:
    return {"name": name, "ok": bool(ok), "value": value}


def _state(slug: str) -> Optional[str]:
    return (kit.registry_get(slug) or {}).get("state")


def _newest(paths: List[Path]) -> Optional[Path]:
    num = lambda p: int("".join(c for c in p.stem if c.isdigit()) or 0)  # noqa: E731
    return max(paths, key=num) if paths else None


def _valid(
    slug: str, action: str, target: Optional[str] = None
) -> List[Dict[str, Any]]:
    return [
        r
        for r in osign.research_records(slug, action, target)
        if r["_verdict"] == osign.VALID
    ]


def cert_criteria(ctx: Any) -> Tuple[List[Crit], Dict[str, str]]:
    import gate

    st = _state(ctx.slug)
    newest = _newest(list(ctx.records.glob("cert/CERT-v*.json")))
    rows = ((kit.read_json(newest) or {}) if newest else {}).get("rows") or {}
    bad = sorted(
        (n for n, s in rows.items() if s not in (gate.PASS, gate.FILED)), key=int
    )
    out = [
        crit("state", st in POST_CERT, st),
        crit("newest-certificate", newest is not None, newest.stem if newest else None),
        crit(
            "rows-pass", bool(rows) and not bad, {"rows": len(rows), "not_passed": bad}
        ),
        crit(
            "no-reopen",
            not gate.reopened(ctx),
            "no reopen after it"
            if not gate.reopened(ctx)
            else "a reopen is signed or accepted after it",
        ),
    ]
    return out, ({f"cert/{newest.name}": osign.file_pin(newest)} if newest else {})


def frame_criteria(ctx: Any) -> Tuple[List[Crit], Dict[str, str]]:
    import frame_delta
    import intake

    fr_path = ctx.records / "frame.json"
    fr = kit.read_json(fr_path) or {}
    lint = intake.lint_fails(ctx.slug, ctx) if fr else ["frame.json missing or empty"]
    deltas = ctx.jsonl("frame-deltas.jsonl")
    last = deltas[-1] if deltas else {}
    pinned = (fr.get("frame_deltas") or [{}])[-1]
    now_sha = frame_delta.sha256(fr_path.read_bytes()) if fr_path.is_file() else None
    newest = (
        bool(last)
        and last.get("version") == fr.get("version")
        and pinned.get("id") == last.get("id")
        and bool(last.get("frame_sha256"))
        and last.get("frame_sha256") == now_sha
    )
    why = (
        f"{last.get('id')} wrote frame v{last.get('version')}"
        if newest
        else "no frame-deltas.jsonl entry"
        if not last
        else f"{last.get('id')} predates the frame hash in its record: the operator signs this frame"
        if not last.get("frame_sha256")
        else f"frame.json changed after {last.get('id')} (version {fr.get('version')}, "
        f"delta v{last.get('version')})"
    )
    # the base: the frame the delta applied ON must be the frame last signed or accepted (the newest
    # record that is not void), so nothing reached the frame between that and the delta unsigned
    # (a record pinning the frame as it is now is this frame's own signature or acceptance, not
    # its base)
    cur_pin = osign.file_pin(fr_path) if fr_path.is_file() else None
    held = [
        r
        for r in osign.research_records(ctx.slug, "frame")
        if r["_verdict"] != osign.VOID
        and (r.get("pins") or {}).get("frame.json") != cur_pin
    ]
    base_rec = max(held, key=lambda r: float(r.get("at") or 0)) if held else None
    base_pin = ((base_rec or {}).get("pins") or {}).get("frame.json")
    base_ok = (
        bool(last.get("base_frame_blob")) and last.get("base_frame_blob") == base_pin
    )
    base_why = (
        f"{last.get('id')} applied on frame {str(base_pin)[:12]}, the one last "
        f"{'accepted' if (base_rec or {}).get('_delegated') else 'signed'} {base_rec.get('at_iso')}"
        if base_ok and base_rec
        else "the frame was never signed or accepted: its first version is the operator's"
        if base_rec is None
        else f"{last.get('id') or 'no delta'} records no base frame: the operator signs this frame"
        if not last.get("base_frame_blob")
        else f"{last.get('id')} applied on frame {str(last.get('base_frame_blob'))[:12]}, not on "
        f"{str(base_pin)[:12]}, the one last signed or accepted: the frame changed unsigned between"
    )
    acc_path = ctx.records / "acceptance.json"
    acc_now = frame_delta.sha256(acc_path.read_bytes()) if acc_path.is_file() else None
    acc_ok = (
        "acceptance_after_sha256" in last and last["acceptance_after_sha256"] == acc_now
    )
    rows = {str(r.get("id")): r for r in kit.known_rows(ctx.slug)}
    known = [str(k) for k in last.get("known_rows") or []]
    not_open = [
        k
        for k in known
        if (rows.get(k) or {}).get("kind") != "frame-omission"
        or (rows.get(k) or {}).get("status", "open") != "open"
    ]
    loose = frame_delta.pin_fails(ctx.records, fr) if fr else ["no frame"]
    out = [
        crit("lint", not lint, lint or "clean"),
        crit("newest-change-is-delta", newest, why),
        crit("base-is-signed", base_ok, base_why),
        crit(
            "acceptance-unchanged",
            acc_ok,
            "acceptance.json is as the delta left it"
            if acc_ok
            else f"acceptance.json changed after {last.get('id') or 'no delta'}, or the delta "
            "predates its acceptance hash",
        ),
        crit(
            "known-rows-open",
            bool(known) and not not_open,
            {"known_rows": known, "not_open": not_open},
        ),
        crit("annotations-pinned", not loose, loose or "every annotation pinned"),
    ]
    # the acceptance pins the rows the frame's checks run as well as the frame, so a later edit to
    # either makes it STALE (a frame signature pins frame.json alone)
    pins = {
        rel: osign.file_pin(p)
        for rel, p in (("frame.json", fr_path), ("acceptance.json", acc_path))
        if p.is_file()
    }
    return out, pins


def implementation_criteria(ctx: Any) -> Tuple[List[Crit], Dict[str, str]]:
    from gate_rows_built import BUILT_ROWS, research_cert_fails

    research = research_cert_fails(ctx)
    st = _state(ctx.slug)
    newest = osign.newest_built_cert(ctx.slug)
    bc = (kit.read_json(newest) or {}) if newest else {}
    rows = bc.get("rows") or {}
    missing = sorted(str(n) for n in BUILT_ROWS if str(n) not in rows)
    bad = sorted((n for n, s in rows.items() if s != "PASS"), key=int)
    fz = ctx.json("built/freeze.json") or {}
    out = [
        crit("state", st in osign.IMPLEMENTATION_STATES, st),
        crit(
            "newest-built-certificate",
            bool(newest) and bc.get("program") == ctx.slug,
            newest.stem if newest else None,
        ),
        crit(
            "rows-pass",
            bool(rows) and not missing and not bad,
            {"missing": missing, "not_pass": bad},
        ),
        crit(
            "freeze-snapshot",
            bool(bc.get("snapshot_sha"))
            and bc.get("snapshot_sha") == fz.get("snapshot_sha"),
            {"certificate": bc.get("snapshot_sha"), "freeze": fz.get("snapshot_sha")},
        ),
        # row 20's own check, re-read now: the research certificate signed or accepted, every
        # row passed, no reopen after it
        crit(
            "research-certificate",
            not research,
            research or "signed, passed, not reopened",
        ),
    ]
    return out, ({f"built/{newest.name}": osign.file_pin(newest)} if newest else {})


def purchase_criteria(
    ctx: Any, action: str, target: Optional[str]
) -> Tuple[List[Crit], Dict[str, Any]]:
    """The five actions with no artifact: the kit's own checks before the operator signs each, and
    its once-per-program (once-per-decision) caps. Returns (criteria, terms for the record)."""
    import gate

    slug, st, terms = ctx.slug, _state(ctx.slug), {}
    if action == "extra-round":
        n = len(_valid(slug, "extra-round"))
        return [
            crit("state", st == "certifying", st),
            crit("once-per-program", n < kit.CAPS["extra_round_sets"], f"{n} bought"),
        ], terms
    if action == "reopen":
        certs = list(ctx.records.glob("cert/CERT-v*.json"))
        return [
            crit("state", st in POST_CERT, st),
            crit("certificate", bool(certs), _newest(certs).stem if certs else None),
            crit(
                "not-reopened",
                not gate.reopened(ctx),
                "none after the newest certificate"
                if not gate.reopened(ctx)
                else "a reopen already follows the newest certificate",
            ),
        ], terms
    if action == "profile":
        try:
            terms = osign.profile_switch_terms(slug, target)
            return [crit("switch-terms", True, terms)], terms
        except osign.Refused as e:
            return [crit("switch-terms", False, str(e).replace("REFUSED — ", ""))], {}
    if action == "adopt":
        fr = ctx.frame
        n = len(_valid(slug, "adopt", target))
        return [
            crit(
                "frame-predates-1.2",
                bool(fr) and not kit.is_v12(fr),
                fr.get("method_version") if fr else "no frame.json",
            ),
            crit("once-per-program", n == 0, f"{n} adopted"),
        ], terms
    import blockers  # extend-decision

    d = kit.fold(ctx.jsonl("decisions.jsonl")).get(str(target))
    on_record = d is not None and d.get("status") != "descoped"
    tag = blockers.tag(ctx, d) if on_record else {}
    n = blockers.extensions(slug, str(target))
    return [
        # the menu offers an extension only under a method 1.2 frame (cli_core.extension_items)
        crit("frame-1.2", kit.is_v12(ctx.frame), ctx.frame.get("method_version")),
        crit(
            "decision-on-record", on_record, (d or {}).get("status") or "not on record"
        ),
        crit(
            "research-can-raise-it",
            tag.get("tag") == "research",
            {"tag": tag.get("tag"), "conviction": tag.get("conviction")},
        ),
        crit("once-per-decision", n < kit.CAPS["decision_extensions"], f"{n} bought"),
    ], terms


def criteria(
    ctx: Any, action: str, target: Optional[str]
) -> Tuple[List[Crit], Dict[str, str], Dict[str, Any]]:
    """(criteria, pins, terms) for one action; criteria named exactly as DELEGATED_CRITERIA."""
    if action == "cert":
        c, pins = cert_criteria(ctx)
        terms: Dict[str, Any] = {}
    elif action == "frame":
        c, pins = frame_criteria(ctx)
        terms = {}
    elif action == "implementation":
        c, pins = implementation_criteria(ctx)
        terms = {}
    else:
        c, terms = purchase_criteria(ctx, action, target)
        pins = {}
    names = tuple(x["name"] for x in c)
    # the writer/reader contract, checked at the write
    if names != osign.DELEGATED_CRITERIA[action]:
        raise kit.KitError(
            f"accept: {action} computed criteria {names}, the readers require "
            f"{osign.DELEGATED_CRITERIA[action]}"
        )
    return c, pins, terms


def parse_action(a: argparse.Namespace) -> Tuple[str, Optional[str]]:
    action, _, slash = str(a.action).partition("/")
    target = a.target or (slash or None)
    if a.target and slash and a.target != slash:
        raise kit.KitError(
            f"--action {a.action} and --target {a.target} name two targets"
        )
    if action in osign.NOT_DELEGABLE:
        raise kit.KitError(
            f"accept refused: {action} is never delegable — {osign.NOT_DELEGABLE[action]}. The "
            f"operator signs it in his own terminal (cc-signoff research:{a.program}/{action}"
            + (f"/{target}" if target else "")
            + ")"
        )
    if action not in osign.DELEGABLE:
        raise kit.KitError(
            f"accept refused: {action!r} is not an action; delegable: {', '.join(osign.DELEGABLE)}"
        )
    if (action in TARGETED) != (target is not None):
        raise kit.KitError(
            f"accept refused: {action} "
            + (
                "names its target (profile/<lite|standard>, adopt/stage9, extend-decision/<id>)"
                if action in TARGETED
                else "takes no target"
            )
        )
    if action == "adopt" and target not in osign.ADOPT_TARGETS:
        raise kit.KitError(
            f"accept refused: adopt/{target} is not adoptable; one of "
            f"{', '.join(osign.ADOPT_TARGETS)}"
        )
    if action in NEEDS_BECAUSE and not (a.because or "").strip():
        raise kit.KitError(
            f'accept refused: {action} needs --because "<why>", as the operator\'s '
            "signature does; it is logged and priced"
        )
    return action, target


def already(
    slug: str, action: str, target: Optional[str], pins: Dict[str, str]
) -> Optional[Dict[str, Any]]:
    """A VALID record (a signature or an acceptance) already pinning these exact bytes."""
    if not pins:
        return None
    for r in _valid(slug, action, target):
        if all((r.get("pins") or {}).get(p) == sha for p, sha in pins.items()):
            return r
    return None


def note_on_md(md: Path, line: str) -> None:
    """Append the acceptance to the certificate's issue-time .md, which no signature pins."""
    if md.is_file():
        with md.open("a") as fh:
            fh.write(line + "\n")


def cmd_accept(a: argparse.Namespace) -> int:
    import gate

    slug = kit.check_slug(a.program)
    # a non-delegable action is refused before anything is read
    action, target = parse_action(a)
    if kit.registry_get(slug) is None:
        raise kit.KitError(f"program {slug!r} is not registered")
    d = osign.delegation_for(slug)
    if d is None:
        raise kit.KitError(
            f"accept refused: no delegation is in force for {slug}. The operator gives one once, in "
            f'his own terminal: cc-signoff research:{slug}/delegate --because "<words>" (or '
            "'research:*/delegate', quoted, for every program)"
        )
    ctx = gate.make_ctx(slug)
    crits, pins, terms = criteria(ctx, action, target)
    ok = all(c["ok"] for c in crits)
    row = f"research:{slug}/{action}" + (f"/{target}" if target else "")
    prior = already(slug, action, target, pins) if ok else None
    rec: Optional[Dict[str, Any]] = None
    if ok and not prior and not a.check:
        now = time.time()
        chain = [c["comm"] for c in osign.ancestry()]
        rec = {
            **terms,
            "kind": osign.DELEGATED,
            "row": row,
            "program": slug,
            "action": action,
            "target": target,
            "at": now,
            "at_iso": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now)),
            "because": a.because,
            "pins": pins,
            "delegation": {
                k: d.get(k) for k in ("id", "sha256", "program", "at_iso", "because")
            },
            "criteria": crits,
            "words": osign.DELEGATED_WORDS,
            "by": kit.lease_owner(),
            "provenance": {
                "chain": chain,
                "claude_ancestor": osign.claude_ancestor(chain) is not None,
            },
        }
        kit.sealed_dir(slug, create=True)
        with osign.acceptance_log(slug).open("a") as fh:
            fh.write(json.dumps(rec, sort_keys=True) + "\n")
        # a revoke can land between delegation_for above and this write: read the record back as
        # every reader will, and claim nothing a void record does not carry
        back = next(
            (
                r
                for r in osign.research_records(slug, action, target)
                if r.get("_delegated") and r.get("at") == now
            ),
            None,
        )
        if back is None or back["_verdict"] != osign.VALID:
            why = (back or {}).get("_why") or "it cannot be read back"
            print(
                f"VOID {row}: written, but every reader reads it void ({why}); nothing follows"
            )
            return 1
    if a.json:
        print(
            json.dumps(
                {
                    "program": slug,
                    "row": row,
                    "delegation": d.get("id"),
                    "verdict": "already"
                    if prior
                    else ("accepted" if rec else ("would-accept" if ok else "refused")),
                    "criteria": crits,
                    "pins": pins,
                },
                sort_keys=True,
            )
        )
    else:
        head = (
            f"ALREADY {row}: {osign.signed_words(prior)}; nothing written"
            if prior
            else f"ACCEPTED {row} under delegation {d.get('id')}: {osign.DELEGATED_WORDS}"
            if rec
            else f"WOULD ACCEPT {row} under delegation {d.get('id')} (--check: nothing "
            "written)"
            if ok
            else f"NOT ACCEPTED {row}: a criterion does not hold; nothing written"
        )
        print(head)
        for c in crits:
            print(
                f"  {'ok  ' if c['ok'] else 'FAIL'} {c['name']}: {json.dumps(c['value'])}"
            )
        for p, sha in sorted(pins.items()):
            print(f"  pinned {p} = {sha} — one changed byte makes the acceptance STALE")
    if not ok:
        return 1
    if rec is not None:
        after(ctx, action, pins, rec)
    elif (
        prior
        and action == "implementation"
        and not a.check
        and _state(slug) != kit.IMPL_SIGNED
    ):
        import gate_built  # accepted or signed already, the registry not yet moved: move it

        gate_built.cmd_built_signed(argparse.Namespace(program=slug))
    return 0


def after(ctx: Any, action: str, pins: Dict[str, str], rec: Dict[str, Any]) -> None:
    """What follows an acceptance: the certificate's .md says so; an implementation moves the
    registry (built-signed, as cc-signoff does after the operator's signature); the rest name the
    next verb."""
    line = (
        f"Accepted by delegation (not read by the operator) {rec['at_iso']}: delegation "
        f"{rec['delegation']['id']} ({rec['delegation']['program']}, given "
        f"{rec['delegation']['at_iso']}); criteria "
        + ", ".join(c["name"] for c in rec["criteria"])
        + " held."
    )
    for p in pins:
        if p.startswith(("cert/", "built/")):
            note_on_md((ctx.records / p).with_suffix(".md"), line)
    if action == "implementation":
        import gate_built

        gate_built.cmd_built_signed(argparse.Namespace(program=ctx.slug))
    elif action == "reopen":
        print(
            f"Next: gate.sh run --program {ctx.slug} re-runs the gate over the records "
            "(registry -> registered)"
        )
    elif action == "frame":
        print(
            f"Next: the next passing gate.sh run --program {ctx.slug} closes the held rows this "
            "frame carries"
        )


def add_verbs(sub: Any) -> None:
    p = sub.add_parser(
        "accept",
        help="accept a phase under the operator's standing delegation (REPORT.md §14)",
        description="Write a delegated acceptance of ACTION for the program when a delegation the "
        "operator signed (cc-signoff research:<P|*>/delegate) is in force and every machine "
        "criterion of ACTION holds. Every reader honours it where it honours the operator's "
        "signature and prints it as 'accepted by delegation (not read by the operator)'. Third "
        "reads and vetoes are never delegable. Exit 0 accepted, 1 a criterion failed, 2 refused.",
    )
    p.add_argument("--program", required=True)
    p.add_argument(
        "--action",
        required=True,
        help="cert | frame | implementation | extra-round | reopen | profile/<lite|standard> | "
        "adopt/stage9 | extend-decision/<decision id>",
    )
    p.add_argument(
        "--target", help="the action's target, if not given as ACTION/TARGET"
    )
    p.add_argument(
        "--because", help="why (extra-round, reopen, profile, adopt, extend-decision)"
    )
    p.add_argument(
        "--check", action="store_true", help="evaluate and print; write nothing"
    )
    p.add_argument("--json", action="store_true")
    p.set_defaults(fn=cmd_accept)
