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
  round.sh reproduce --program P --hole NEW --status CONFIRMED|REFUTED --read-plan F --by WHO
                 --reason T --evidence F…
      The ONE reproduction (§6.5 "Disputed finding") of a split hole whose verdict was CONTACT,
      read on the real plan before any plan edit; round close and the estimate honour its verdict.
  round.sh hold-g --program P --hole H --known-row KR-N --names-rows ROW… --resign-due ISO
                 --reason T --evidence F…
      Hold a clause-(g) frame-omission hole for the post-certificate frame-delta cycle (§5.4): an
      open known row in known_rows.jsonl that names the hole.
  round.sh refind --program P --hole NEW --of H --reason T --evidence F…
      A later round's hole that re-finds held hole H: not new material while H's row is open.
  round.sh repass --program P --round K --ratings F --reason T
      The round's ONE rating re-pass (§6.5), only while rater 1 and rater 2 agree below
      kit.KAPPA_REPASS_BELOW. Each line of F, {id, raters, level, clause?}, supersedes that hole's
      earlier ratings in the fold; the round is then re-closed, and a kappa still low prints
      "Adjudication unstable", which the certificate carries.
  round.sh name-cap --program P --hole H --known-row KR-N --wave W --reason T --evidence F…
      Name a CONFIRMED MATERIAL non-(g) find of the closed verification-only cap round (§3.8) as an
      open `cap-round` known row applied in build wave W; it blocks no wave. Gate row 9 passes it.

hold-g, refind and name-cap end by re-reading what the last certification round still owes
(round.py settle_owed), and the last settle step closes the certification-round activity.

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


def cmd_reproduce(a: argparse.Namespace) -> int:
    """§6.5 "Disputed finding — 1 reproduction probe": the one second verdict a split hole can get,
    and only when its first one was CONTACT. Round close and the estimate read `verification.status`,
    so CONFIRMED starts counting it (rate it, then re-close) and REFUTED joins the false share."""
    h = hole(a.program, a.hole)
    ver = h.get("verification") or {}
    if not h.get("split_from") or ver.get("against") != "real":
        raise rounds.Refused(
            f"{a.hole}: not a split-off hole verified against the real plan (round.sh verify-split first)"
        )
    if h.get("reproduction"):
        raise rounds.Refused(
            f"{a.hole}: already reproduced ({ver.get('status')}); a disputed finding gets one "
            "reproduction probe (§6.5)"
        )
    if ver.get("status") != "CONTACT":
        raise rounds.Refused(
            f"{a.hole}: its verdict is {ver.get('status')}; only a CONTACT verdict is reproduced"
        )
    plan = real_plan(a.program)
    want = str(h.get("plan_blob"))
    if blob_of(plan) != want:
        raise rounds.Refused(
            f"the real plan changed since {a.hole} was split: reproduce before any plan edit"
        )
    if blob_of(Path(a.read_plan)) != want:
        raise rounds.Refused(
            f"--read-plan {a.read_plan} is not the real plan the split cites (blob {want[:12]}): a "
            "reproduction reads the real plan, never the seeded bundle"
        )
    if not (a.by or "").strip():
        raise rounds.Refused("--by is required: who ran the reproduction")
    rec = audit(a, a.program, plan_blob=want)
    texts = [
        (kit.records_dir(a.program) / e).read_text(errors="replace")
        for e in rec["evidence"]
    ]
    if not any(want[:7] in t for t in texts):
        raise rounds.Refused(
            f"no evidence file names the real plan's blob {want[:12]} (git hash-object {plan.name}): "
            "the reproduction must be shown to have read the real plan"
        )
    kit.append_jsonl(
        holes_path(a.program),
        {
            "id": a.hole,
            "event": "reproduce",
            "verification": {
                "status": a.status,
                "against": "real",
                "plan_blob": want,
                "by": a.by.strip(),
                "evidence": rec["evidence"],
                "at": rec["at"],
            },
            "reproduction": dict(rec, status=a.status, first=ver),
        },
    )
    print(
        f"{a.hole}: CONTACT -> {a.status} by its one reproduction. "
        + (
            f"Rate it, then re-close round {h.get('round')} (round.sh close --reclose)"
            if a.status == "CONFIRMED"
            else f"Re-close round {h.get('round')} to recount (round.sh close --reclose)"
        )
    )
    return 0


def known_rows_path(slug: str) -> Path:
    return kit.records_dir(slug) / "known_rows.jsonl"


def cmd_hold_g(a: argparse.Namespace) -> int:
    """Hold a clause-(g) frame-omission hole for the post-certificate frame-delta cycle (§5.4): an
    open `frame-omission` known row that names the hole. The hole still counts in its own round;
    a later round's re-find of it (round.sh refind) does not count as new material while the row
    is open."""
    h = hole(a.program, a.hole)
    confirmed_material(h, "held for the frame-delta cycle")
    clause = str((h.get("materiality") or {}).get("clause") or "")
    if clause and "g" not in re.findall(r"[a-z]", clause.lower()):
        raise rounds.Refused(
            f"{a.hole}: rated under clause {clause}; only a clause-(g) frame omission is held"
        )
    if not re.match(r"^KR-\d+$", a.known_row):
        raise rounds.Refused(f"--known-row {a.known_row!r}: must read KR-<n>")
    fr = rounds.frame(a.program)
    taken = {str(r.get("id")) for r in fr.get("known_rows") or []} | {
        str(r.get("id")) for r in kit.read_jsonl(known_rows_path(a.program))
    }
    if a.known_row in taken:
        raise rounds.Refused(f"{a.known_row}: a known row with this id already exists")
    if a.hole in kit.held_frame_omissions(a.program):
        raise rounds.Refused(f"{a.hole}: already held by an open known row")
    # The hourly sweep closes an open row by its default once resign_due has passed (gate_sweep),
    # so a past date would un-hold the hole within the hour.
    if not re.match(r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$", a.resign_due):
        raise rounds.Refused(
            f"--resign-due {a.resign_due!r}: must read YYYY-MM-DDTHH:MM:SSZ"
        )
    if a.resign_due <= kit.now_iso():
        raise rounds.Refused(
            f"--resign-due {a.resign_due} is not in the future: the sweep would close the row by "
            "its default at once"
        )
    kit.append_jsonl(
        known_rows_path(a.program),
        {
            "id": a.known_row,
            "kind": "frame-omission",
            "hole": a.hole,
            "names_rows": list(a.names_rows),
            "blocks_waves": list(a.blocks_waves or []),
            "resign_due": a.resign_due,
            "default": a.default,
            "status": "open",
            "held": audit(a, a.program),
        },
    )
    print(
        f"{a.hole}: held for the frame-delta cycle as {a.known_row} (re-sign due {a.resign_due}); "
        "a later round's re-find of it is attached with round.sh refind"
    )
    settle_tail(a.program, h)
    return 0


def cmd_refind(a: argparse.Namespace) -> int:
    """Attach a later round's hole to the held hole it re-finds. The LEAD runs this after dedup (the
    adjudicator stays blind to round history). A re-find of a hole that is not held, a fixed one
    included, is new material and gets no record."""
    h = hole(a.program, a.hole)
    of = hole(a.program, a.of)
    if a.of not in kit.held_frame_omissions(a.program):
        raise rounds.Refused(
            f"{a.of}: not held by an open frame-omission known row (round.sh hold-g); a re-find of "
            "any other hole is new material"
        )
    if h.get("refind_of"):
        raise rounds.Refused(
            f"{a.hole}: already recorded as a re-find of {h['refind_of']}"
        )
    if h.get("seed_match") or h.get("artifact") or h.get("split_from"):
        raise rounds.Refused(
            f"{a.hole}: seed-tagged or already settled; it is not counted as new material anyway"
        )
    rh, ro = str(h.get("round") or ""), str(of.get("round") or "")
    if not (rh.isdigit() and ro.isdigit() and int(rh) > int(ro)):
        raise rounds.Refused(
            f"{a.hole} (round {rh or '?'}) is not from a later certification round than {a.of} "
            f"(round {ro or '?'})"
        )
    kit.append_jsonl(
        holes_path(a.program),
        {
            "id": a.hole,
            "event": "refind",
            "refind_of": a.of,
            "refind": audit(a, a.program),
        },
    )
    print(
        f"{a.hole}: a re-find of held {a.of}; not new material while its known row is open. "
        f"Re-close round {rh} if it is already closed (round.sh close --reclose)"
    )
    settle_tail(a.program, h)
    return 0


def settle_tail(slug: str, h: Dict[str, Any]) -> None:
    """After a settle verb on a certification round's hole: close the certification-round activity
    if that was the last settle step owed, or name what is still owed (round.py activity_tail)."""
    if str(h.get("round") or "").isdigit():
        rounds.activity_tail(slug, {"kind": "certification"})


WAVE_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")


def cmd_name_cap(a: argparse.Namespace) -> int:
    """Name a find of the verification-only cap round as a known row (REPORT.md §3.8: "Its finds are
    listed on the certificate as named known rows applied in build wave 1, and the plan is not
    edited"): an open `cap-round` row in known_rows.jsonl naming the hole and the build wave that
    applies it. It blocks no wave (gate_requires reads `blocks_waves`, and it is empty): the fix is
    the applying wave's own work, so blocking that wave would deadlock it, and the plan it builds
    from is not wrong the way a frame omission's frame is. A clause-(g) find is hold-g's."""
    h = hole(a.program, a.hole)
    rnd = str(h.get("round") or "")
    cap = [
        m
        for m in rounds.all_matrices(a.program, "certification")
        if m.get("verification_only") and rnd in (str(m.get("round")), str(m.get("seq")))
    ]
    if not cap:
        raise rounds.Refused(
            f"{a.hole} (round {rnd or '?'}) is not a find of the verification-only cap round; only a "
            "cap-round find is named this way (REPORT.md §3.8)"
        )
    if not cap[0].get("closed"):
        raise rounds.Refused(
            f"round {rnd} is not closed; name its finds after round.sh close (seed match runs there)"
        )
    confirmed_material(h, "named as a cap-round known row")
    if h.get("seed_match"):
        raise rounds.Refused(
            f"{a.hole}: seed-tagged ({h['seed_match']}); a caught seed is no defect of the real plan"
        )
    if kit.held_refind(h, kit.held_frame_omissions(a.program)):
        raise rounds.Refused(
            f"{a.hole}: a re-find of held {h['refind_of']}; it is not new material while that row is open"
        )
    if kit.clause_g(h):
        raise rounds.Refused(
            f"{a.hole}: rated under clause {(h.get('materiality') or {}).get('clause')}, a clause-(g) "
            "frame omission: hold it for the frame-delta cycle (round.sh hold-g)"
        )
    if not re.match(r"^KR-\d+$", a.known_row):
        raise rounds.Refused(f"--known-row {a.known_row!r}: must read KR-<n>")
    if not WAVE_RE.match(a.wave or ""):
        raise rounds.Refused(f"--wave {a.wave!r}: not a wave id")
    rows = kit.known_rows(a.program)
    by = [str(r.get("id")) for r in rows if str(r.get("hole")) == a.hole]
    if by:
        raise rounds.Refused(f"{a.hole}: already named by {', '.join(by)}")
    if a.known_row in {str(r.get("id")) for r in rows}:
        raise rounds.Refused(f"{a.known_row}: a known row with this id already exists")
    kit.append_jsonl(
        known_rows_path(a.program),
        {
            "id": a.known_row,
            "kind": "cap-round",
            "hole": a.hole,
            "round": rnd,
            "applied_in_wave": a.wave,
            "blocks_waves": [],
            "status": "open",
            "named": audit(a, a.program),
        },
    )
    print(
        f"{a.hole}: named as {a.known_row}, a cap-round known row applied in build wave {a.wave}; "
        "the plan is not edited and the row blocks no wave"
    )
    settle_tail(a.program, h)
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
        "reproduce",
        help="the one reproduction of a split hole whose verdict was CONTACT",
    )
    p.add_argument("--program", required=True)
    p.add_argument("--hole", required=True)
    p.add_argument("--status", required=True, choices=("CONFIRMED", "REFUTED"))
    p.add_argument("--read-plan", required=True)
    p.add_argument("--by", required=True)
    p.add_argument("--reason", required=True)
    p.add_argument("--evidence", nargs="+", required=True)
    p.set_defaults(fn=cmd_reproduce)
    p = sub.add_parser(
        "hold-g", help="hold a clause-(g) frame omission for the frame-delta cycle"
    )
    p.add_argument("--program", required=True)
    p.add_argument("--hole", required=True)
    p.add_argument("--known-row", required=True)
    p.add_argument("--names-rows", nargs="+", required=True)
    p.add_argument("--blocks-waves", nargs="*", default=[])
    p.add_argument("--resign-due", required=True)
    p.add_argument("--default", choices=("class-b", "descope"), default="class-b")
    p.add_argument("--reason", required=True)
    p.add_argument("--evidence", nargs="+", required=True)
    p.set_defaults(fn=cmd_hold_g)
    p = sub.add_parser(
        "refind", help="attach a later round's hole to the held hole it re-finds"
    )
    p.add_argument("--program", required=True)
    p.add_argument("--hole", required=True)
    p.add_argument("--of", required=True)
    p.add_argument("--reason", required=True)
    p.add_argument("--evidence", nargs="+", required=True)
    p.set_defaults(fn=cmd_refind)
    p = sub.add_parser(
        "repass", help="the round's one rating re-pass when rater agreement is low"
    )
    p.add_argument("--program", required=True)
    p.add_argument("--round", required=True)
    p.add_argument("--ratings", required=True)
    p.add_argument("--reason", required=True)
    p.set_defaults(fn=cmd_repass)
    p = sub.add_parser(
        "name-cap",
        help="name a non-(g) find of the verification-only cap round as a known row",
    )
    p.add_argument("--program", required=True)
    p.add_argument("--hole", required=True)
    p.add_argument("--known-row", required=True)
    p.add_argument("--wave", required=True, help="the build wave that applies it (W1)")
    p.add_argument("--reason", required=True)
    p.add_argument("--evidence", nargs="+", required=True)
    p.set_defaults(fn=cmd_name_cap)
