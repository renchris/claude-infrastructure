"""gate_delta.py — the post-certificate frame-delta cycle's activity (REPORT.md §5.4).

gate.sh delta-activity --program P
    print (opening if none) the program's frame-delta activity id, so the delta's Stages 2-5 (census
    methods and critic, its delta rounds) run past the research block once the operator has re-signed
    a frame carrying a held omission's delta. Refused (exit 2, nothing written) unless:
      - the registry reads certified, or certifying with that re-sign newer than the newest
        certificate (a reopen re-froze the program after the cycle's re-sign);
      - a certificate exists (the cycle runs after one);
      - at least one OPEN frame-omission known row has a VALID frame signature dated after its hold
        whose pinned frame lists it in `known_rows_applied` (gate.delta_signature, the same evidence
        `gate.sh run` closes the row on), so the cycle is genuinely pending;
      - no other frame-delta activity is open (triage's, say): its tag already carries the cycle.
    A second call while this verb's row is open prints the same id.

gate.sh run closes the row (close_cycle) once every known row it was opened for is closed: the
re-issued certificate closing them is the cycle's step 4. The row records `opened_by`, `opened_at`,
`known_rows`, `signed_at` (the newest re-sign carrying them) and `after_cert` (the certificate the
cycle follows).

What its tag lets through the research block (router.py research_clause, FRAME_DELTA): courier.sh
and the delta's round.sh verbs (`run --kind delta`, any verb on a `delta-…` round) for THIS program,
and [activity:<id>] Agent/Task/Workflow calls. The census verbs (`cc-research census add|repin|critic`)
and probe-run.sh are not research verbs and run untagged. Nothing else: no other program, no vendor
CLI, no `claude -p`, no buying verb, no certification round, no handoff-fire.sh fire.
"""

from __future__ import annotations

import re
import sys
from typing import Any, Dict, List, Optional, Tuple

import kit
from gate import Ctx, delta_signature, make_ctx

KIND = "frame-delta"
OPENED_BY = "gate.sh delta-activity"


def newest_cert(ctx: Ctx) -> Optional[Dict[str, Any]]:
    """The newest certificate's record (by its version number), or None."""

    def num(p: Any) -> int:
        m = re.match(r"CERT-v(\d+)\.json$", p.name)
        return int(m.group(1)) if m else -1

    certs = [p for p in (ctx.records / "cert").glob("CERT-v*.json") if num(p) >= 0]
    if not certs:
        return None
    best = max(certs, key=num)
    rec = kit.read_json(best, {}) or {}
    return dict(rec, cert=rec.get("cert") or best.stem)


def pending(ctx: Ctx) -> Tuple[List[str], List[str], str]:
    """(open frame-omission rows whose delta a VALID re-sign carries, the other open frame-omission
    rows, the newest such re-sign's at_iso)."""
    from gate_rows_a import held_at, known_rows

    held = held_at(ctx)
    carried: List[str] = []
    rest: List[str] = []
    signed = ""
    for kr in known_rows(ctx):
        if kr.get("kind") != "frame-omission" or kr.get("status", "open") != "open":
            continue
        kid = str(kr.get("id"))
        sig = delta_signature(ctx, kid, held.get(kid, ""))
        if sig:
            carried.append(kid)
            signed = max(signed, str(sig.get("at_iso") or ""))
        else:
            rest.append(kid)
    return carried, rest, signed


def _ours(a: Dict[str, Any]) -> bool:
    return a.get("opened_by") == OPENED_BY


def cmd_delta_activity(a: Any) -> int:
    import activities

    slug = a.program
    ctx = make_ctx(slug)
    state = (kit.registry_get(slug) or {}).get("state")
    if state not in ("certified", "certifying"):
        raise kit.KitError(
            f"delta-activity refused: {slug} is {state!r}; the frame-delta cycle runs after the "
            "certificate (REPORT.md §5.4), so the registry must read certified, or certifying after a "
            "reopen"
        )
    cert = newest_cert(ctx)
    if not cert:
        raise kit.KitError(
            f"delta-activity refused: {slug} has no certificate; the frame-delta cycle runs after one "
            "(REPORT.md §5.4)"
        )
    opened = [
        x
        for x in activities.load()["activities"]
        if isinstance(x, dict)
        and x.get("program") == slug
        and x.get("kind") == KIND
        and x.get("state") == "open"
    ]
    other = [x for x in opened if not _ours(x)]
    if other:
        raise kit.KitError(
            f"delta-activity refused: frame-delta activity {other[0].get('id')} is already open "
            "(opened by triage); tag the cycle's calls with it"
        )
    carried, rest, signed = pending(ctx)
    if not carried:
        raise kit.KitError(
            "delta-activity refused: no frame-delta cycle is pending: no open frame-omission known row "
            "is listed in known_rows_applied of a frame the operator re-signed after its hold"
            + (f" (open frame-omission rows: {', '.join(rest)})" if rest else "")
            + "; apply the delta (intake.py delta-apply) and have the operator re-sign the frame "
            f"(cc-signoff research:{slug}/frame) first"
        )
    if state == "certifying" and not signed > str(cert.get("issued") or ""):
        raise kit.KitError(
            f"delta-activity refused: {slug} is certifying and the newest re-sign carrying a delta "
            f"({signed}) is not newer than {cert['cert']} ({cert.get('issued')}); the certification "
            "under way is not a post-certificate cycle"
        )
    if opened:
        aid = str(opened[0]["id"])
    else:
        aid = str(
            activities.ensure_open(
                slug,
                KIND,
                fields={
                    "opened_by": OPENED_BY,
                    "opened_at": kit.now_iso(),
                    "known_rows": carried,
                    "signed_at": signed,
                    "after_cert": cert["cert"],
                },
            )
        )
    print(
        f"frame-delta activity for {', '.join(carried)}: tag CC_RESEARCH_ACTIVITY={aid} (courier.sh, "
        "round.sh run --kind delta, round.sh … --round delta-…, all on --program "
        f"{slug}) and [activity:{aid}] (Agent and Workflow inputs); the census verbs and probe-run.sh "
        "run untagged. gate.sh run closes it when the re-issued certificate closes those rows.",
        file=sys.stderr,
    )
    print(aid)
    return 0


def close_cycle(ctx: Ctx, cert: str) -> List[str]:
    """Close every open frame-delta row this verb opened whose known rows are all closed now (§5.4
    step 4: the re-issued certificate closes them). A row still naming an open known row stays open."""
    import activities
    from gate_rows_a import known_rows

    status = {str(k.get("id")): k.get("status", "open") for k in known_rows(ctx)}
    out: List[str] = []
    for x in activities.load()["activities"]:
        if not (
            isinstance(x, dict)
            and x.get("program") == ctx.slug
            and x.get("kind") == KIND
            and x.get("state") == "open"
            and _ours(x)
        ):
            continue
        rows = [str(r) for r in x.get("known_rows") or []]
        if rows and all(status.get(r) == "closed" for r in rows):
            activities.close_activity(str(x["id"]))
            out.append(
                f"closed frame-delta activity {x['id']} ({cert} closed {', '.join(rows)})"
            )
    return out


def add_verbs(sub: Any) -> None:
    p = sub.add_parser(
        "delta-activity",
        help="open (or name) the frame-delta activity of a pending post-certificate cycle (§5.4)",
        description="Print the id of the program's frame-delta activity, opening one if none is "
        "open. Refused unless the registry reads certified (or certifying with the re-sign newer "
        "than the newest certificate), a certificate exists, at least one open frame-omission known "
        "row is listed in known_rows_applied of a frame the operator re-signed after its hold, and "
        "no other frame-delta activity is open. Tag the delta's calls with CC_RESEARCH_ACTIVITY=<id> "
        "(courier.sh, round.sh run --kind delta, round.sh on a delta-… round, all for this program) "
        "and [activity:<id>] (Agent and Workflow inputs). gate.sh run closes it once the re-issued "
        "certificate closes those rows.",
    )
    p.add_argument("--program", required=True)
    p.set_defaults(fn=cmd_delta_activity)
