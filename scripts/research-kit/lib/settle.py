"""settle.py — settling a certification round's holes honestly before any plan edit (REPORT.md §3.9,
§6.5; RECORDS.md "Settling a round"). Verbs on round.sh, each under the program lease:

  round.sh artifact --program P --hole H --reason T --evidence F…
      An untagged CONFIRMED MATERIAL hole the lead proved is damage the seeded copy did, not a
      defect of the real plan: no seed_match, no catch credit. Seed match skips it, round close and
      estimate.counted_holes leave it out of every count, and close lists it in m["artifacts"].
      An evidence file must name the real plan's git blob, so the checks ran on the real plan.
  round.sh split --program P --hole H --findings FID… --path F --lines L --quote Q --claim C
                 --reason T --evidence F…
      A seed-tagged CONFIRMED MATERIAL hole that merged a seed catch with a defect the REAL plan
      also holds. The catch stays; a new hole is opened from the named raise events (the findings
      a blind adjudicator assigned to the real defect), its locus in the real plan's numbering
      (the quote must sit on the cited lines of the real plan).
  round.sh verify-split --program P --hole NEW --status CONFIRMED|REFUTED|CONTACT --read-plan F
                 --by WHO --evidence F…
      The split hole's verification, refused unless F (the plan the verifier read) is the real
      plan, byte for byte: never the seeded bundle. Until it runs, round close refuses the round.
  round.sh repass --program P --round K --ratings F --reason T
      The round's ONE rating re-pass (§6.5), only while rater 1 and rater 2 agree below
      kit.KAPPA_REPASS_BELOW. Each line of F, {id, raters, level, clause?}, supersedes that hole's
      earlier ratings in the fold; the round is then re-closed, and a kappa still low prints
      "Adjudication unstable", which the certificate carries.

Records are append-only events on holes.jsonl; the fold makes the newest win. Python 3.9-safe.
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path
from typing import Any, Dict, List, Set

import kit
rounds: Any = None  # the round.py module that hosts these verbs (add_verbs)

STATUSES = ("CONFIRMED", "REFUTED", "CONTACT")
LEVELS = ("MATERIAL", "MATERIAL-DISPUTED", "REFINEMENT", "COSMETIC", "GENERIC")


def holes_path(slug: str) -> Path:
    return kit.records_dir(slug) / "holes.jsonl"


def folded(slug: str) -> Dict[str, Dict[str, Any]]:
    return kit.fold(kit.read_jsonl(holes_path(slug)))


def real_plan(slug: str) -> Path:
    fr = rounds.frame(slug)
    if not fr.get("plan"):
        raise rounds.Refused(
            "frame.json names no plan: there is no real plan to settle against"
        )
    return kit.records_dir(slug) / fr["plan"]


def blob_of(path: Path) -> str:
    import operator_sign

    return operator_sign.blob_sha(Path(path).read_bytes())


def evidence(slug: str, paths: List[str]) -> List[str]:
    """Each file, relative to the records dir, that exists inside it (gate row 8 fails a record
    citing a scratch path such as /tmp)."""
    rec = kit.records_dir(slug).resolve()
    out = []
    for p in paths:
        f = Path(p) if Path(p).is_absolute() else rec / p
        f = f.resolve()
        if not f.is_file():
            raise rounds.Refused(f"evidence {p}: no such file")
        try:
            out.append(str(f.relative_to(rec)))
        except ValueError:
            raise rounds.Refused(
                f"evidence {p}: outside the records dir; copy it under {rec}/evidence"
            ) from None
    if not out:
        raise rounds.Refused("--evidence names no file")
    return out


def hole(slug: str, hid: str) -> Dict[str, Any]:
    h = folded(slug).get(hid)
    if not h:
        raise rounds.Refused(f"no such hole: {hid}")
    return h


def confirmed_material(h: Dict[str, Any], what: str) -> None:
    ver = (h.get("verification") or {}).get("status")
    lvl = (h.get("materiality") or {}).get("level")
    if ver != "CONFIRMED" or lvl != "MATERIAL":
        raise rounds.Refused(
            f"{h['id']}: {ver} {lvl}; only a CONFIRMED MATERIAL hole can be {what}"
        )
    if h.get("artifact") or h.get("split_from"):
        raise rounds.Refused(
            f"{h['id']}: already settled ({'artifact' if h.get('artifact') else 'split-off'})"
        )


def reason(text: str) -> str:
    if not (text or "").strip():
        raise rounds.Refused("--reason is required")
    return text.strip()


def audit(a: argparse.Namespace, slug: str, **extra: Any) -> Dict[str, Any]:
    return dict(
        at=kit.now_iso(),
        by=kit.lease_owner(),
        reason=reason(a.reason),
        evidence=evidence(slug, a.evidence),
        **extra,
    )


def cmd_artifact(a: argparse.Namespace) -> int:
    h = hole(a.program, a.hole)
    confirmed_material(h, "an artifact")
    if h.get("seed_match"):
        raise rounds.Refused(
            f"{a.hole}: seed-tagged; an artifact record is for an UNTAGGED hole (a tagged one that "
            "also holds a real defect is split instead)"
        )
    plan = real_plan(a.program)
    b = blob_of(plan)
    rec = audit(a, a.program, plan_blob=b)
    texts = [
        (kit.records_dir(a.program) / e).read_text(errors="replace")
        for e in rec["evidence"]
    ]
    if not any(b[:7] in t for t in texts):
        raise rounds.Refused(
            f"no evidence file names the real plan's blob {b[:12]} (git hash-object {plan.name}): "
            "the checks must be shown to have run on the real plan, not the seeded copy"
        )
    kit.append_jsonl(
        holes_path(a.program), {"id": a.hole, "event": "artifact", "artifact": rec}
    )
    print(
        f"{a.hole}: artifact of the seeded copy; no catch credit. Re-close round {h.get('round')} "
        "to recount (round.sh close --reclose)"
    )
    return 0


def raise_findings(slug: str, hid: str) -> List[str]:
    return [
        str(r["finding"])
        for r in kit.read_jsonl(holes_path(slug))
        if r.get("id") == hid and r.get("event") == "raise" and r.get("finding")
    ]


def line_ranges(lines: str, n: int) -> List[range]:
    out = []
    for part in re.split(r"[;,]", lines or ""):
        m = re.match(r"^\s*(\d+)\s*(?:[-–]\s*(\d+))?\s*$", part)
        if not m:
            raise rounds.Refused(f"--lines {lines!r}: each part must read N or N-M")
        lo, hi = sorted((int(m.group(1)), int(m.group(2) or m.group(1))))
        if lo < 1 or hi > n:
            raise rounds.Refused(f"--lines {lines!r}: the real plan has {n} lines")
        out.append(range(lo, hi + 1))
    if not out:
        raise rounds.Refused("--lines is empty")
    return out


def norm(text: str) -> str:
    return " ".join(text.split())


def cmd_split(a: argparse.Namespace) -> int:
    h = hole(a.program, a.hole)
    confirmed_material(h, "split")
    if not h.get("seed_match"):
        raise rounds.Refused(
            f"{a.hole}: not seed-tagged; a split keeps a seed catch, so it needs one"
        )
    own = raise_findings(a.program, a.hole)
    if not own:
        raise rounds.Refused(
            f"{a.hole}: no raise event names a finding; nothing to split from"
        )
    bad = [f for f in a.findings if f not in own]
    if bad:
        raise rounds.Refused(f"finding(s) {', '.join(bad)} are not raise events of {a.hole}")
    taken: Set[str] = set()
    for o in folded(a.program).values():
        if o.get("split_from") == a.hole:
            taken |= set(o.get("findings") or [])
    if taken & set(a.findings):
        raise rounds.Refused(
            f"finding(s) {', '.join(sorted(taken & set(a.findings)))} already split off"
        )
    if set(a.findings) == set(own) - taken:
        raise rounds.Refused(
            f"every finding of {a.hole} would leave it: the seed catch must keep one"
        )
    plan = real_plan(a.program)
    if Path(a.path).name != plan.name:
        raise rounds.Refused(f"--path {a.path}: the real plan is {plan.name}")
    text = plan.read_text().splitlines()
    cited = norm(
        " ".join(text[i - 1] for r in line_ranges(a.lines, len(text)) for i in r)
    )
    if not norm(a.quote) or norm(a.quote) not in cited:
        raise rounds.Refused(f"--quote is not on lines {a.lines} of the real plan {plan.name}")
    if not (a.claim or "").strip():
        raise rounds.Refused(
            "--claim is required: the real defect, written from the real plan"
        )
    rec = audit(a, a.program, plan_blob=blob_of(plan))
    m = re.match(r"^(.*)-(\d+)$", a.hole)
    if not m:
        raise rounds.Refused(f"{a.hole}: not a <prefix>-<n> id")
    n = int(kit.mint_id(holes_path(a.program), m.group(1)).rsplit("-", 1)[1])
    new = f"{m.group(1)}-{n:0{len(m.group(2))}d}"
    kit.append_jsonl(
        holes_path(a.program),
        {
            "id": new,
            "event": "raise",
            "round": h.get("round"),
            "source": h.get("source") or "panel",
            "split_from": a.hole,
            "findings": list(a.findings),
            "claim": a.claim.strip(),
            "locus": {
                "path": a.path,
                "lines": a.lines,
                "quote": a.quote,
                "numbering": "real",
            },
            "plan_blob": rec["plan_blob"],
            "split": rec,
        },
    )
    kit.append_jsonl(
        holes_path(a.program),
        {
            "id": a.hole,
            "event": "split",
            "split_to": list(h.get("split_to") or []) + [new],
            "split": dict(rec, to=new),
        },
    )
    print(
        f"{a.hole} keeps its seed catch; {new} opened from {len(a.findings)} finding(s). Verify it "
        f"against the real plan (round.sh verify-split), rate it, then re-close round {h.get('round')}"
    )
    return 0


def cmd_verify_split(a: argparse.Namespace) -> int:
    h = hole(a.program, a.hole)
    if not h.get("split_from"):
        raise rounds.Refused(f"{a.hole}: not a split-off hole")
    if (h.get("verification") or {}).get("against") == "real":
        raise rounds.Refused(f"{a.hole}: already verified against the real plan")
    plan = real_plan(a.program)
    want = str(h.get("plan_blob"))
    if blob_of(plan) != want:
        raise rounds.Refused(
            f"the real plan changed since {a.hole} was split: its line numbers are stale"
        )
    if blob_of(Path(a.read_plan)) != want:
        raise rounds.Refused(
            f"--read-plan {a.read_plan} is not the real plan the split cites (blob {want[:12]}): a "
            "split hole is verified on the real plan, never the seeded bundle"
        )
    if not (a.by or "").strip():
        raise rounds.Refused("--by is required: the verifier")
    kit.append_jsonl(
        holes_path(a.program),
        {
            "id": a.hole,
            "event": "verify",
            "verification": {
                "status": a.status,
                "against": "real",
                "plan_blob": want,
                "by": a.by.strip(),
                "evidence": evidence(a.program, a.evidence),
                "at": kit.now_iso(),
            },
        },
    )
    print(f"{a.hole}: {a.status} against the real plan")
    return 0


def cmd_repass(a: argparse.Namespace) -> int:
    why = reason(a.reason)
    rd = rounds.rounds_dir(a.program) / a.round
    m = kit.read_json(rd / "matrix.json")
    if not m or not m.get("closed"):
        raise rounds.Refused(f"round {a.round} is not closed; the re-pass re-closes it")
    later = rounds.later_rounds(a.program, m)
    if later:
        raise rounds.Refused(
            f"round {a.round}: later round(s) {', '.join(later)} already opened"
        )
    ids = (a.round, str(m.get("seq")))
    rounds.refuse_pending_splits(a.program, ids)
    mine = {k: h for k, h in folded(a.program).items() if str(h.get("round")) in ids}
    done = [
        r
        for r in kit.read_jsonl(holes_path(a.program))
        if r.get("event") == "repass" and r.get("id") in mine
    ]
    if done:
        raise rounds.Refused(f"round {a.round}'s one rating re-pass already ran (§6.5)")
    before, n = kit.materiality_kappa(mine.values())
    if before is None:
        raise rounds.Refused(f"round {a.round}: no hole carries both rater 1 and rater 2")
    if before >= kit.KAPPA_REPASS_BELOW:
        raise rounds.Refused(
            f"round {a.round}: rater kappa {before} is not below {kit.KAPPA_REPASS_BELOW}; no re-pass"
        )
    rows = kit.read_jsonl(Path(a.ratings))
    errs: List[str] = []
    seen: Set[str] = set()
    for r in rows:
        hid = str(r.get("id"))
        calls = [kit.rater_call({"materiality": r}, k) for k in (1, 2, 3)]
        lvl = r.get("level")
        if hid not in mine:
            errs.append(f"{hid}: not a hole of round {a.round}")
        elif hid in seen:
            errs.append(f"{hid}: rated twice")
        elif not (calls[0] and calls[1]):
            errs.append(f"{hid}: the re-pass needs rater 1 and rater 2")
        elif lvl not in LEVELS:
            errs.append(f"{hid}: level {lvl!r} is not one of {', '.join(LEVELS)}")
        elif (calls.count("M") >= 2) != (lvl in ("MATERIAL", "MATERIAL-DISPUTED")):
            errs.append(
                f"{hid}: level {lvl} disagrees with {calls.count('M')} rater(s) calling M (2 of 3)"
            )
        seen.add(hid)
    sample = {
        k for k, h in mine.items() if kit.rater_call(h, 1) and kit.rater_call(h, 2)
    }
    if sample - seen:
        errs.append(
            f"the re-pass must re-rate every rated hole; missing {', '.join(sorted(sample - seen))}"
        )
    if errs:
        raise rounds.Refused("; ".join(errs))
    at, by = kit.now_iso(), kit.lease_owner()
    for r in rows:
        kit.append_jsonl(
            holes_path(a.program),
            {
                "id": r["id"],
                "event": "repass",
                "round": mine[str(r["id"])].get("round"),
                "materiality": {
                    "level": r["level"],
                    "clause": r.get("clause"),
                    "raters": r["raters"],
                    "repass": {
                        "at": at,
                        "by": by,
                        "reason": why,
                        "kappa_before": before,
                    },
                },
            },
        )
    rounds.cmd_reclose(
        argparse.Namespace(
            program=a.program,
            round=a.round,
            reason=f"rating re-pass (kappa {before} over {n}): {why}",
        )
    )
    after = (kit.read_json(rd / "matrix.json") or {}).get("kappa") or {}
    print(
        f"rater kappa {before} -> {after.get('materiality')}"
        + (" · Adjudication unstable" if after.get("unstable") else "")
    )
    return 0


def add_verbs(sub: Any, host: Any) -> None:
    """Add the verbs to round.sh. `host` is round.py as it runs (its __main__), so a refusal here
    is its Refused and prints as one."""
    global rounds
    rounds = host
    p = sub.add_parser(
        "artifact", help="an untagged hole proved an artifact of the seeded copy"
    )
    p.add_argument("--program", required=True)
    p.add_argument("--hole", required=True)
    p.add_argument("--reason", required=True)
    p.add_argument("--evidence", nargs="+", required=True)
    p.set_defaults(fn=cmd_artifact)
    p = sub.add_parser(
        "split", help="open the real defect a seed-tagged hole also holds"
    )
    p.add_argument("--program", required=True)
    p.add_argument("--hole", required=True)
    p.add_argument("--findings", nargs="+", required=True)
    p.add_argument("--path", required=True)
    p.add_argument("--lines", required=True)
    p.add_argument("--quote", required=True)
    p.add_argument("--claim", required=True)
    p.add_argument("--reason", required=True)
    p.add_argument("--evidence", nargs="+", required=True)
    p.set_defaults(fn=cmd_split)
    p = sub.add_parser(
        "verify-split", help="a split hole's verdict, read on the real plan"
    )
    p.add_argument("--program", required=True)
    p.add_argument("--hole", required=True)
    p.add_argument("--status", required=True, choices=STATUSES)
    p.add_argument("--read-plan", required=True)
    p.add_argument("--by", required=True)
    p.add_argument("--evidence", nargs="+", required=True)
    p.set_defaults(fn=cmd_verify_split)
    p = sub.add_parser(
        "repass", help="the round's one rating re-pass when rater agreement is low"
    )
    p.add_argument("--program", required=True)
    p.add_argument("--round", required=True)
    p.add_argument("--ratings", required=True)
    p.add_argument("--reason", required=True)
    p.set_defaults(fn=cmd_repass)
