"""scheduled_read.py — gate row 15 as a scheduled read (method v1.3, REPORT.md §13.1).

Row 15 measures the shared re-ask router on sealed held-out sets. When a stratum of the instrument
awaits a fresh set (`heldout.py instrument --await`, ruling 915d7fb98b7f), no route in grasp makes
that data exist sooner, so the read cannot happen now. Method v1.3 ("exhaust, then proceed",
the operator's ruling of 2026-10-16) lets the program proceed: the lead files the read, the row
prints FILED and decrypts nothing, the certificate issues with the row carried, and the read is
spent later by its own verb. Nothing about the read is weakened (REPORT.md §13.1 lists each guard):

  cc-research read file --program P --row 15 --awaits "<what accrues>" --owner WHO --due DUE
                        --falsifier "<cmd>" [--blocks-wave W ...] --why "<why>" [--refile]
      files the scheduled read in scheduled-reads.jsonl. Refused while every stratum is pinned (the
      read is in grasp: run it), and while a live filing exists unless --refile. DUE is a date or
      an event due (`cert+<N>d`, `<wave>+<N>d`).
  gate.sh read --program P --row 15 --consent-sealed-read
      spends the read: only while the registry is certified (or a Stage 9 state), the newest
      certificate carries no FAIL row and row 15 FILED, no reopen is signed after it, and a live
      filing has no recorded read. The read is heldout.evaluate, the call row 15 makes, with every
      one of its own refusals (router, consent, pins, the two-read cap, real-load figures, the load
      bound); a refusal spends nothing. The verdict is appended to scheduled-reads.jsonl; a FAIL is
      final for the items read. Exit 0 PASS · 1 FAIL · 2 refused.
  gate.sh read --program P --row 15 --practice
      the uncounted practice run (REPORT.md §13.5): every precondition of the read as it stands now,
      and the router once per canned prompt under the read's own call and time limit. Decrypts
      nothing, logs no read, writes nothing. Exit 0 ready · 1 not ready.

`gate.sh requires` refuses the filing's --blocks-wave waves until a PASS is recorded, and keeps
them refused after a FAIL. Python 3.9-safe, standard library only.
"""

from __future__ import annotations

import argparse
import os
import re
import sys
import time
from pathlib import Path
from typing import Any, Dict, List, Optional

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))  # heldout.py
import kit  # noqa: E402

READS = "scheduled-reads.jsonl"
ROWS = (15,)
WAVE_ID = r"^[A-Za-z0-9][A-Za-z0-9._-]*$"
# Canned prompts for the practice run: they prove the router answers, under the read's call and time
# limit, with a label it may give. They are not held-out items and score nothing.
PRACTICE_PROMPTS = (
    "are we 100% done with this?",
    "add a CSV export to the weekly report",
    "what does this error mean?",
)


def closing_cmd(slug: str) -> str:
    return f"gate.sh read --program {slug} --row 15 --consent-sealed-read"


def events(records: Path) -> List[Dict[str, Any]]:
    return kit.read_jsonl(Path(records) / READS)


def live_filing(records: Path, row: int = 15) -> Optional[Dict[str, Any]]:
    """The newest filing for `row` that no later filing superseded, with its read folded in
    (`read`: the read event, or None)."""
    evs = events(records)
    filings = [e for e in evs if e.get("event") == "filed" and e.get("row") == row]
    gone = {str(e.get("supersedes")) for e in filings if e.get("supersedes")}
    live = [f for f in filings if str(f.get("id")) not in gone]
    if not live:
        return None
    f = dict(live[-1])
    reads = [e for e in evs if e.get("event") == "read" and e.get("id") == f["id"]]
    f["read"] = reads[-1] if reads else None
    return f


def awaiting() -> List[str]:
    """The strata of the pinned instrument that await a fresh set; [] when none is pinned."""
    import heldout

    plan = heldout.instrument()
    return [s for s in heldout.STRATA if plan is not None and plan[s] is None]


def filing_line(f: Dict[str, Any], records: Path) -> str:
    waves = ", ".join(f.get("blocks_waves") or []) or "none"
    return (
        f"scheduled read {f['id']}: awaits {f.get('awaits')} (strata {', '.join(f.get('strata') or [])}), "
        f"owner {f.get('owner')}, due {kit.due_note(f.get('due'), records)}, closing probe "
        f"`{f.get('closing_probe')}`, falsifier `{f.get('falsifier')}`, blocks waves {waves}"
    )


def past_due(f: Dict[str, Any], records: Path) -> Optional[str]:
    kind, t = kit.resolve_due(f.get("due"), records)
    if kind == "bad":
        return f"its due {f.get('due')!r} is unparseable"
    if t is not None and t <= kit.parse_iso(kit.now_iso()):
        return f"its due {kit.due_note(f.get('due'), records)} has passed with no read recorded"
    return None


def row15_filed(ctx: Any) -> Optional[Any]:
    """Row 15's v1.3 verdict when a scheduled read is filed, else None (the row reads as before).

    FILED: strata await a fresh set and a live, unread filing covers them, due not past.
    FAIL:  a live unread filing is past due, or its recorded read FAILed (final for those items).
    None:  no filing, or nothing awaits (the read is in grasp: row 15 reads under its own rules)."""
    from gate import FAIL, FILED, Row

    f = live_filing(ctx.records)
    if f is None:
        return None
    if f.get("read"):
        if f["read"].get("verdict") == "FAIL":
            return Row(
                15,
                "Router",
                FAIL,
                [
                    f"{f['id']}: the scheduled read FAILED at {f['read'].get('at')}; final for the items read"
                ]
                + list(f["read"].get("fails") or []),
            )
        return None  # read and passed: a later gate run reads under row 15's own rules
    wait = awaiting()
    if not wait:
        return None
    uncovered = [s for s in wait if s not in (f.get("strata") or [])]
    if uncovered:
        return Row(
            15,
            "Router",
            FAIL,
            [
                f"{f['id']} does not cover stratum {', '.join(uncovered)}; refile it (--refile)"
            ],
        )
    late = past_due(f, ctx.records)
    if late:
        return Row(15, "Router", FAIL, [f"{f['id']}: {late}"])
    return Row(
        15,
        "Router",
        FILED,
        [f"FILED {filing_line(f, ctx.records)}", "nothing decrypted, no read logged"],
    )


def blocks(records: Path, wave: Optional[str]) -> List[str]:
    """`gate.sh requires` reasons: the live filing's waves wait for a passing read."""
    f = live_filing(records)
    if f is None:
        return []
    ws = [w for w in f.get("blocks_waves") or [] if isinstance(w, str) and w]
    if not ws or (wave is not None and wave not in ws):
        return []
    r = f.get("read")
    if r and r.get("verdict") == "PASS":
        return []
    if r:
        return [
            f"row 15: scheduled read {f['id']} FAILED at {r.get('at')} (final for the items read), "
            f"so {', '.join(ws)} wait for a fresh set and a passing read"
        ]
    return [
        f"row 15: scheduled read {f['id']} has not run ({f.get('awaits')}; due "
        f"{kit.due_note(f.get('due'), records)}), so {', '.join(ws)} wait for "
        f"`{f.get('closing_probe')}` to pass"
    ]


def render_line(records: Path) -> Optional[str]:
    f = live_filing(records)
    if f is None:
        return None
    r = f.get("read")
    if r:
        return f"Router read {f['id']}: {r.get('verdict')} at {r.get('at')}"
    late = past_due(f, records)
    state = f"OVERDUE, {late}" if late else f"due {kit.due_note(f.get('due'), records)}"
    return f"Router read {f['id']}: scheduled, awaits {f.get('awaits')}; {state}"


# ── cc-research read file ───────────────────────────────────────────────────────────────────────


def cmd_file(a: argparse.Namespace) -> int:
    import cli_jobs
    import gate

    ctx = gate.make_ctx(a.program)
    for flag, v in (("--awaits", a.awaits), ("--owner", a.owner), ("--why", a.why)):
        if not (v or "").strip():
            raise kit.KitError(f"{flag} is required and may not be empty")
    fals = (a.falsifier or "").strip()
    if not fals or cli_jobs.PROSE_RE.match(fals):
        raise kit.KitError(
            "--falsifier must be a command whose exit 0 makes the filing moot, not prose"
        )
    for w in a.blocks_wave or []:
        if not re.match(WAVE_ID, w):
            raise kit.KitError(f"bad wave id {w!r}")
    kind, t = kit.resolve_due(a.due, ctx.records)
    if kind == "bad":
        raise kit.KitError(
            f"--due {a.due!r} is not ISO-8601 UTC or YYYY-MM-DD, nor an event due "
            "<wave>+<N>d or cert+<N>d (method v1.3)"
        )
    if t is not None and t <= kit.parse_iso(kit.now_iso()):
        raise kit.KitError(f"--due {a.due!r} is already past")
    ev = kit.due_event(a.due)
    if ev and ev[0] != kit.CERT_EVENT and ev[0] not in (a.blocks_wave or []):
        raise kit.KitError(
            f"--due {a.due!r} is keyed to {ev[0]}, a wave this filing does not block; key it to "
            "cert or a --blocks-wave"
        )
    wait = awaiting()
    if not wait:
        raise kit.KitError(
            "every stratum of the router's instrument is pinned, so the read is in grasp: spend it "
            f"(gate.sh run --program {a.program} --consent-sealed-read), do not schedule it"
        )
    old = live_filing(ctx.records)
    if old is not None and not old.get("read") and not a.refile:
        raise kit.KitError(
            f"{old['id']} is already filed and unread; --refile supersedes it"
        )
    if a.refile and (old is None or old.get("read")):
        raise kit.KitError("no unread filing to refile; file it without --refile")
    n = 1 + sum(
        1
        for e in events(ctx.records)
        if e.get("event") == "filed" and e.get("row") == 15
    )
    rec: Dict[str, Any] = {
        "id": f"SR-15-{n}",
        "event": "filed",
        "row": 15,
        "awaits": a.awaits.strip(),
        "strata": wait,
        "owner": a.owner.strip(),
        "due": a.due,
        "closing_probe": closing_cmd(a.program),
        "falsifier": fals,
        "blocks_waves": sorted(set(a.blocks_wave or [])),
        "why": a.why.strip(),
    }
    if a.refile and old is not None:
        rec["supersedes"] = old["id"]
    kit.append_jsonl(ctx.records / READS, rec)
    print(
        f"{rec['id']}: filed row 15 as a scheduled read; "
        + filing_line(rec, ctx.records)
        + (f"; supersedes {old['id']}" if a.refile and old else "")
    )
    return 0


def add_verbs(sub: Any) -> None:
    p = sub.add_parser(
        "read", help="row 15 as a scheduled read (method v1.3, REPORT.md §13.1)"
    )
    rs = p.add_subparsers(dest="read_verb", required=True)
    q = rs.add_parser("file")
    q.add_argument("--program", required=True)
    q.add_argument("--row", type=int, choices=ROWS, required=True)
    q.add_argument(
        "--awaits", required=True, help="what must accrue before the read can run"
    )
    q.add_argument("--owner", required=True)
    q.add_argument(
        "--due", required=True, help="a date, or an event due: cert+<N>d or <wave>+<N>d"
    )
    q.add_argument(
        "--falsifier",
        required=True,
        help="a command whose exit 0 makes the filing moot",
    )
    q.add_argument(
        "--blocks-wave", action="append", help="a build wave that rests on the router"
    )
    q.add_argument("--why", required=True)
    q.add_argument("--refile", action="store_true")
    q.set_defaults(fn=cmd_file)


# ── gate.sh read ────────────────────────────────────────────────────────────────────────────────


def practice(slug: str) -> int:
    """Every precondition of the read as it stands now, plus the router under the read's call."""
    import gate
    import heldout

    ctx = gate.make_ctx(slug)
    lines, short = [], []
    router = os.environ.get("CC_RESEARCH_ROUTER")
    ref = heldout.router_refusal(router)
    (short if ref else lines).append(ref or f"router command resolves: {router}")
    try:
        wait = awaiting()
        if wait:
            short.append(
                f"stratum {', '.join(wait)} awaits a fresh set: the read would refuse now"
            )
        else:
            lines.append("every stratum has a set pinned")
    except kit.KitError as e:
        short.append(str(e))
    try:
        heldout.real_load()
        lines.append("RULE E1k's real-load figures are on record and pass")
    except kit.KitError as e:
        short.append(str(e))
    now = heldout.load1()
    (lines if now <= heldout.LOAD_BOUND else short).append(
        f"1-min load {now:.1f} against the bound {heldout.LOAD_BOUND:g}"
    )
    f = live_filing(ctx.records)
    if f is None:
        lines.append(
            "no scheduled read is filed (a plain gate run reads row 15 itself)"
        )
    elif f.get("read"):
        short.append(f"{f['id']} was already read ({f['read'].get('verdict')})")
    else:
        lines.append(filing_line(f, ctx.records))
    if not ref:
        for prompt in PRACTICE_PROMPTS:
            t0 = time.monotonic()
            got = heldout.route(str(router), prompt)
            took = time.monotonic() - t0
            msg = f"router answered {got or 'nothing (a fallback)'} in {took:.1f} s to a canned prompt"
            (lines if got else short).append(msg)
    for x in lines:
        print(f"  ok   {x}")
    for x in short:
        print(f"  NOT  {x}")
    print(
        ("PRACTICE READY" if not short else f"PRACTICE NOT READY ({len(short)})")
        + f": {slug} row 15; nothing decrypted, no read logged, nothing written"
    )
    return 0 if not short else 1


def cmd_read(a: argparse.Namespace) -> int:
    import gate
    import heldout

    if a.practice:
        return practice(a.program)
    if not a.consent_sealed_read:
        raise kit.KitError(
            "no read consent: a sealed read is spent only on purpose (--consent-sealed-read); "
            "--practice runs every precondition without spending it"
        )
    ctx = gate.make_ctx(a.program)
    state = (kit.registry_get(a.program) or {}).get("state")
    if state not in ("certified",) + kit.STAGE9_STATES:
        raise kit.KitError(
            f"{a.program} is {state or 'not registered'}: a scheduled read runs after the certificate "
            "issues (before it, gate.sh run reads row 15 itself)"
        )
    certs = sorted(
        ctx.records.glob("cert/CERT-v*.json"),
        key=lambda p: int(re.sub(r"\D", "", p.stem) or 0),
    )
    cert = kit.read_json(certs[-1], {}) if certs else {}
    rows = (cert or {}).get("rows") or {}
    failed = sorted((k for k, v in rows.items() if v == gate.FAIL), key=int)
    if not certs or failed or rows.get("15") != gate.FILED:
        raise kit.KitError(
            "the newest certificate must carry no FAIL row and row 15 FILED"
            + (f" (FAIL rows {', '.join(failed)})" if failed else "")
            + (
                f" (row 15 {rows.get('15')})"
                if certs and rows.get("15") != gate.FILED
                else ""
            )
            + "; nothing read"
        )
    if gate.reopened(ctx):
        raise kit.KitError(
            "an operator reopen is signed after the newest certificate; nothing read"
        )
    f = live_filing(ctx.records)
    if f is None:
        raise kit.KitError(
            "no scheduled read is filed (cc-research read file); nothing read"
        )
    if f.get("read"):
        raise kit.KitError(
            f"{f['id']} was already read ({f['read'].get('verdict')} at {f['read'].get('at')}): a "
            "sealed set is never re-read for the same verdict"
        )
    res = heldout.evaluate(
        os.environ.get("CC_RESEARCH_ROUTER"), consent=True, program=a.program
    )
    verdict = gate.PASS if not res["fails"] else gate.FAIL
    kit.append_jsonl(
        ctx.records / READS,
        {
            "id": f["id"],
            "event": "read",
            "row": 15,
            "verdict": verdict,
            "at": kit.now_iso(),
            "fails": res["fails"],
            "notes": res["notes"],
        },
    )
    print(f"{f['id']}: row 15 scheduled read {verdict}")
    for x in res["fails"] + res["notes"]:
        print(f"      {x}")
    return 0 if verdict == gate.PASS else 1


def add_gate_verbs(sub: Any) -> None:
    p = sub.add_parser("read")
    p.add_argument("--program", required=True)
    p.add_argument("--row", type=int, choices=ROWS, required=True)
    g = p.add_mutually_exclusive_group()
    g.add_argument("--consent-sealed-read", action="store_true")
    g.add_argument("--practice", action="store_true")
    p.set_defaults(fn=cmd_read)
