"""rehearsal.py — a rehearsal find (REPORT.md §3.8 "Rehearsal": "A verified material find becomes a named
known row"; RECORDS.md "Rehearsal finds"). Verbs on round.sh, each under the program lease:

  round.sh rehearsal-raise  --program P --frame F --path PLAN --lines L --quote Q --claim C [--names ROW…]
                            [--receipt T]
      A blind frame session's find opens hole H-RH-<n> in the reserved round `rehearsal`, source
      "rehearsal". Only after the stop (no certification round due, the last one closed), only on a
      reask_map frame with an axis, only on the plan the freeze pinned, its quote on the cited lines.
  round.sh rehearsal-verify --program P --hole H-RH-<n> --vendor V
      ONE verifier on the frozen briefs/verifier.md, through `courier.sh run --round rehearsal --role
      verifier` over a bundle of the real plan; its verdict lands on the hole.
  round.sh rehearsal-rate   --program P --hole H-RH-<n>
      The three raters of the certification round's assignment (cli_cert.raters: rater 1 non-Anthropic,
      rater 2 another family, rater 3 the third) on the frozen briefs/rater.md (RUBRIC.md), through
      `courier.sh run --round rehearsal --role rater`; only a CONFIRMED hole. The level is the median of
      the three calls, so MATERIAL is 2 of 3 M; a lost rater records nothing, and the re-run runs only it.
      Once a lost rater is past its re-run cap it never runs again: if the other two agree, no call of it
      moves the median, so their level is recorded with materiality.lost {slot, vendor, why}; else refused.
  round.sh rehearsal-name   --program P --hole H-RH-<n> --known-row KR-<n> --wave W --reason T --evidence F…
      Name a CONFIRMED MATERIAL non-(g) rehearsal find as an open `rehearsal` known row applied in build
      wave W, blocking none (like name-cap's cap-round row). A clause-(g) find is hold-g's. Gate row 9
      passes it.

Why a reserved round of the round machinery and not a path of its own: the rehearsal's finds then use
the hole ledger, the courier, the rater assignment, the panel checks (cli_cert.panel_breaches: pins,
effort, rater vendor, integrity) and known_rows.jsonl exactly as a certification round's, and every
reader that counts rounds skips them for free: `rounds/rehearsal/` never holds a matrix.json, and
`round` "rehearsal" matches no certification, built or delta id. The rehearsal never edits the plan, so
nothing here opens a fix cycle or a freeze. None of these verbs is in router.py ROUND_SETTLE: no
certification-round tag runs them. The rehearsal activity's tag does (gate.sh rehearsal-activity,
router.py REHEARSAL_ROUND), and so does any allow-all turn outside the program root.

Python 3.9-safe.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Tuple

import kit
import settle

rounds: Any = None  # the round.py module that hosts these verbs (add_verbs)

ROUND = "rehearsal"
PREFIX = "H-RH"
BRIEFS = Path(__file__).resolve().parents[3] / "skills" / "research-program" / "briefs"
CALLS = {"M": "MATERIAL", "R": "REFINEMENT", "C": "COSMETIC", "G": "GENERIC"}
RANK = {"M": 3, "R": 2, "C": 1, "G": 0}
FID = "f1"  # the briefs carry a neutral fid: a hole id would tell the reader where the find came from
DEAD, VOID = 3, 4


def is_rehearsal(h: Dict[str, Any]) -> bool:
    return h.get("source") == "rehearsal" and str(h.get("round")) == ROUND


def rehearsal_hole(slug: str, hid: str) -> Dict[str, Any]:
    h = settle.hole(slug, hid)
    if not is_rehearsal(h):
        raise rounds.Refused(
            f"{hid} (round {h.get('round')}): not a rehearsal find; a certification round's find is "
            "named by round.sh name-cap, and a clause-(g) one held by round.sh hold-g"
        )
    return h


def after_stop(slug: str) -> None:
    """The rehearsal runs once, after the stop and before issue (§3.8): never between two rounds."""
    done = rounds.all_matrices(slug, "certification")
    if not done:
        raise rounds.Refused(
            "no certification round has run: the rehearsal runs after the stop (REPORT.md §3.8)"
        )
    if not done[-1].get("closed"):
        raise rounds.Refused(
            f"certification round {done[-1].get('round')} is not closed: the rehearsal runs after the stop"
        )
    if rounds.certification_due(slug) is None:
        raise rounds.Refused(
            f"certification round {len(done) + 1} is still due: the rehearsal runs after the stop "
            "(the stop rule fired or R_max is spent)"
        )


def certified_plan(slug: str) -> Tuple[Path, str]:
    """The real plan and its blob, refused unless it is the plan the freeze pinned."""
    plan = settle.real_plan(slug)
    fz = kit.read_json(kit.records_dir(slug) / "freeze.json", {}) or {}
    if not fz.get("snapshot_sha"):
        raise rounds.Refused(
            "not frozen (gate.sh freeze): the rehearsal reads the plan certification froze"
        )
    b = settle.blob_of(plan)
    if fz.get("plan_blob") and b != fz["plan_blob"]:
        raise rounds.Refused(
            f"{plan.name} changed after the freeze: the rehearsal never edits the plan, and reads "
            "the one certification froze"
        )
    return plan, b


def same_plan(h: Dict[str, Any], b: str) -> None:
    if str(h.get("plan_blob")) != b:
        raise rounds.Refused(
            f"{h['id']}: the plan changed since it was raised; its locus is stale"
        )


def rdir(slug: str) -> Path:
    return rounds.rounds_dir(slug) / ROUND


def cmd_raise(a: argparse.Namespace) -> int:
    after_stop(a.program)
    fr = rounds.frame(a.program)
    frames = {str(r.get("frame")) for r in fr.get("reask_map") or [] if r.get("axis")}
    if a.frame not in frames:
        raise rounds.Refused(
            f"--frame {a.frame!r}: not a reask_map frame with an axis ({len(frames)} in frame.json); "
            "an unmapped frame is excluded from the rehearsal"
        )
    plan, b = certified_plan(a.program)
    if Path(a.path).name != plan.name:
        raise rounds.Refused(f"--path {a.path}: the real plan is {plan.name}")
    text = plan.read_text().splitlines()
    cited = settle.norm(
        " ".join(text[i - 1] for r in settle.line_ranges(a.lines, len(text)) for i in r)
    )
    if not settle.norm(a.quote) or settle.norm(a.quote) not in cited:
        raise rounds.Refused(
            f"--quote is not on lines {a.lines} of the real plan {plan.name}"
        )
    if not (a.claim or "").strip():
        raise rounds.Refused("--claim is required: the find, as the session wrote it")
    hid = kit.mint_id(settle.holes_path(a.program), PREFIX)
    rec: Dict[str, Any] = {
        "id": hid,
        "event": "raise",
        "round": ROUND,
        "source": "rehearsal",
        "raised_by": {
            "frame": a.frame,
            "blind": True,
            "by": kit.lease_owner(),
            "at": kit.now_iso(),
        },
        "claim": a.claim.strip(),
        "names": list(a.names or []),
        "locus": {
            "path": a.path,
            "lines": a.lines,
            "quote": a.quote,
            "numbering": "real",
        },
        "plan_blob": b,
    }
    if (a.receipt or "").strip():
        rec["receipt"] = a.receipt.strip()
    kit.append_jsonl(settle.holes_path(a.program), rec)
    print(
        f"{hid}: a rehearsal find on frame {a.frame!r}. Verify it (round.sh rehearsal-verify --program "
        f"{a.program} --hole {hid} --vendor V), then rate it (round.sh rehearsal-rate)"
    )
    return 0


# ── the courier ─────────────────────────────────────────────────────────────────────────────────


def ensure_bundle(slug: str, plan: Path) -> None:
    """One bundle for the reserved round, of the REAL plan (the rehearsal reads the certified plan,
    never a seeded copy); courier.sh refuses a second one, so later finds reuse it."""
    import courier

    if (courier.bundle_dir(slug, ROUND) / "manifest.json").is_file():
        return
    p = subprocess.run(
        [
            rounds.courier(),
            "bundle",
            "--program",
            slug,
            "--round",
            ROUND,
            "--plan",
            str(plan),
        ],
        stdin=subprocess.DEVNULL,
        capture_output=True,
        text=True,
    )
    if p.returncode != 0:
        raise rounds.Refused(f"courier bundle failed: {p.stderr.strip()}")


def brief(slug: str, name: str, role: str, item: Dict[str, Any]) -> Path:
    """The frozen brief verbatim, then the one item it is about."""
    what = "The finding" if role == "verifier" else "The verified finding to rate"
    text = (BRIEFS / f"{role}.md").read_text()
    bf = rdir(slug) / "briefs" / f"{name}.txt"
    bf.parent.mkdir(parents=True, exist_ok=True)
    bf.write_text(f"{text}\n\n{what}:\n\n```json\n{json.dumps(item, indent=2)}\n```\n")
    return bf


def item(h: Dict[str, Any], plan: Path) -> Dict[str, Any]:
    """The find as the briefs carry it. Its path is the plan's in the bundle (courier.sh bundle copies
    the plan to the bundle's root under its file name, as a certification round's items cite it), never
    the path the raise recorded: that is the operator's absolute path, which a sandboxed rater (agy) is
    denied, and then it replies empty. The raise record keeps it, as provenance."""
    loc = h.get("locus") or {}
    return {
        "fid": FID,
        "locus": {
            "path": plan.name,
            "lines": loc.get("lines"),
            "quote": loc.get("quote"),
        },
        "claim": h.get("claim"),
        "names": h.get("names") or [],
    }


def run_courier(slug: str, jobs: List[Tuple[str, str, str, Path]]) -> None:
    """Each (pid, vendor, role, brief) through `courier.sh run`, in parallel, within the per-slot
    re-run cap a certification slot has (cli_cert.cmd_slot)."""
    import cli_cert

    tries = cli_cert.attempts(slug, ROUND)
    cap = 1 + kit.CAPS["slot_reruns"]
    over = [pid for pid, _, _, _ in jobs if tries.get(pid, 0) >= cap]
    if over:
        raise rounds.Refused(
            f"{', '.join(over)} ran {cap} times; a slot is re-run at most {kit.CAPS['slot_reruns']} times"
        )
    procs = []
    for pid, vendor, role, bf in jobs:
        kit.append_jsonl(
            rdir(slug) / "attempts.jsonl",
            {"pid": pid, "attempt": tries.get(pid, 0) + 1},
        )
        procs.append(
            subprocess.Popen(
                [
                    rounds.courier(),
                    "run",
                    "--program",
                    slug,
                    "--round",
                    ROUND,
                    "--pid",
                    pid,
                    "--vendor",
                    vendor,
                    "--strategy",
                    role,
                    "--role",
                    role,
                    "--brief",
                    str(bf),
                ],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        )
    for p in procs:
        p.wait()


def lost(slug: str, pid: str, assign: Dict[int, Dict[str, Any]]) -> Optional[str]:
    """Why a panel is no read (missing, dead, void, or a breach of the round's checks), else None.
    A verifier's or rater's reply is not a reviewer panel, so the courier marks it partial: that is
    its normal state here, and its reply is read from the raw output."""
    import cli_cert
    import courier

    pj = rdir(slug) / "panels" / f"{pid}.json"
    p = kit.read_json(pj)
    if not p:
        return "missing: no panel file"
    if p.get("status") in ("dead", "void"):
        return f"{p['status']}{': ' + str(p['error']) if p.get('error') else ''}"
    fr = rounds.frame(slug)
    why = cli_cert.panel_breaches(
        slug,
        p,
        pj.with_suffix(".raw"),
        fr.get("reviewer_pins") or {},
        assign,
        courier.integrity_needles(slug),
        fr.get("reviewer_effort") or {},
    )
    if why:
        p["status"] = "void"
        kit.write_json_atomic(pj, p)
        return "void: " + "; ".join(why)
    return None


def reply_object(
    slug: str, pid: str, vendor: str, want: Callable[[Dict[str, Any]], bool]
) -> Optional[Dict[str, Any]]:
    """The first JSON object in the vendor's reply that `want` accepts, bare, fenced or in prose."""
    import courier

    raw = rdir(slug) / "panels" / f"{pid}.raw"
    try:
        reply, _ = courier.parse(vendor, raw.read_text(errors="replace"))
    except (OSError, ValueError, KeyError, TypeError):
        return None
    dec = json.JSONDecoder()
    for m in re.finditer(r"\{", reply or ""):
        try:
            d, _ = dec.raw_decode(reply, m.start())
        except ValueError:
            continue
        if isinstance(d, dict) and want(d):
            return d
    return None


def cmd_verify(a: argparse.Namespace) -> int:
    h = rehearsal_hole(a.program, a.hole)
    if h.get("verification"):
        raise rounds.Refused(
            f"{a.hole}: already verified ({h['verification'].get('status')}); a find gets one verifier"
        )
    plan, b = certified_plan(a.program)
    same_plan(h, b)
    if a.vendor not in rounds.live_lanes(rounds.frame(a.program)):
        raise rounds.Refused(f"--vendor {a.vendor}: not a live lane of this program")
    ensure_bundle(a.program, plan)
    pid = f"{a.hole}-verifier"
    run_courier(
        a.program,
        [(pid, a.vendor, "verifier", brief(a.program, pid, "verifier", item(h, plan)))],
    )
    why = lost(a.program, pid, {})
    v = (
        None
        if why
        else reply_object(
            a.program, pid, a.vendor, lambda d: d.get("status") in settle.STATUSES
        )
    )
    if v is None:
        print(
            f"{pid}: {why or 'no verdict in the reply'}; nothing recorded, re-run round.sh rehearsal-verify"
        )
        return DEAD if (why or "").startswith("dead") else VOID
    kit.append_jsonl(
        settle.holes_path(a.program),
        {
            "id": a.hole,
            "event": "verify",
            "verification": {
                "status": v["status"],
                "against": "real",
                "plan_blob": b,
                "by": a.vendor,
                "vendor": a.vendor,
                "panel": pid,
                "read": v.get("read"),
                "consequence": v.get("consequence"),
                "probe": v.get("probe"),
                "at": kit.now_iso(),
            },
        },
    )
    print(
        f"{a.hole}: {v['status']} by its verifier ({a.vendor})"
        + (". Rate it: round.sh rehearsal-rate" if v["status"] == "CONFIRMED" else "")
    )
    return 0


def rating_of(slug: str, pid: str, vendor: str) -> Optional[Dict[str, Any]]:
    """A rater's one call on the item: {rating, clause} from its {"ratings": [...]}, or None."""

    def ok(d: Dict[str, Any]) -> bool:
        return isinstance(d.get("ratings"), list)

    d = reply_object(slug, pid, vendor, ok)
    rows = [r for r in (d or {}).get("ratings") or [] if isinstance(r, dict)]
    mine = [r for r in rows if r.get("fid") == FID] or (rows if len(rows) == 1 else [])
    if len(mine) != 1:
        return None
    call = str(mine[0].get("rating") or "")
    clause = mine[0].get("clause")
    if call not in CALLS or (call == "M" and not str(clause or "").strip()):
        return None
    return {"rating": call, "clause": str(clause).strip() if call == "M" else None}


def level_of(calls: List[Dict[str, Any]]) -> Tuple[str, Optional[str]]:
    """The median of the three calls (M > R > C > G), so MATERIAL is 2 of 3 M, as the re-pass checks;
    the clause the most material calls gave, the earlier rater on a tie."""
    ranked = sorted((c["rating"] for c in calls), key=lambda c: -RANK[c])
    lvl = ranked[len(ranked) // 2]
    if lvl != "M":
        return CALLS[lvl], None
    ms = [c["clause"] for c in calls if c["rating"] == "M"]
    return CALLS[lvl], max(ms, key=lambda c: (ms.count(c), -ms.index(c)))


def fixed_level(calls: List[Dict[str, Any]]) -> Optional[Tuple[str, Optional[str]]]:
    """The level (and clause) these two calls give whatever the lost third rater would have said, or
    None when one of its calls moves the median. The clause comes from the calls actually made."""
    lvls = {
        level_of(calls + [{"rating": r, "clause": "?" if r == "M" else None}])[0]
        for r in CALLS
    }
    if len(calls) != 2 or len(lvls) != 1:
        return None
    lvl = lvls.pop()
    if lvl != CALLS["M"]:
        return lvl, None
    ms = [c["clause"] for c in calls if c["rating"] == "M"]
    return lvl, max(ms, key=lambda c: (ms.count(c), -ms.index(c)))


def cmd_rate(a: argparse.Namespace) -> int:
    import cli_cert

    h = rehearsal_hole(a.program, a.hole)
    ver = h.get("verification") or {}
    if ver.get("status") != "CONFIRMED":
        raise rounds.Refused(
            f"{a.hole}: verification {ver.get('status') or 'none'}; only a CONFIRMED hole is rated "
            "(round.sh rehearsal-verify first)"
        )
    if h.get("materiality"):
        raise rounds.Refused(f"{a.hole}: already rated {h['materiality'].get('level')}")
    plan, b = certified_plan(a.program)
    same_plan(h, b)
    assign = cli_cert.raters(a.program, ROUND)
    if assign is None:
        print(
            "round.sh: no rater assignment: fewer than two live families or none non-Anthropic"
        )
        return DEAD
    by_slot = {int(r["slot"]): r for r in assign}
    pids = {k: f"{a.hole}-rater{k}" for k in by_slot}

    def read(k: int) -> Tuple[Optional[str], Optional[Dict[str, Any]]]:
        if not (rdir(a.program) / "panels" / f"{pids[k]}.json").exists():
            return "missing: no panel file", None
        why = lost(a.program, pids[k], by_slot)
        if why:
            return why, None
        c = rating_of(a.program, pids[k], by_slot[k]["vendor"])
        return (None, c) if c else ("no rating in the reply", None)

    ensure_bundle(a.program, plan)
    tries = cli_cert.attempts(a.program, ROUND)
    cap = 1 + kit.CAPS["slot_reruns"]
    spent = {k for k in by_slot if tries.get(pids[k], 0) >= cap}
    todo = [k for k in sorted(by_slot) if read(k)[1] is None and k not in spent]
    if todo:
        it = dict(
            item(h, plan),
            verification={
                "read": ver.get("read"),
                "consequence": ver.get("consequence"),
            },
        )
        bf = brief(a.program, f"{a.hole}-rater", "rater", it)
        run_courier(
            a.program, [(pids[k], by_slot[k]["vendor"], "rater", bf) for k in todo]
        )
    got = {k: read(k) for k in sorted(by_slot)}
    bad = {k: why for k, (why, c) in got.items() if c is None}
    gone: Optional[Dict[str, Any]] = None
    fixed: Optional[Tuple[str, Optional[str]]] = None
    if bad and set(bad) <= spent:
        # Every lost slot is past its re-run cap, so it can never be read: the hole is rated only if
        # no call it could have made moves the median (one lost slot, the other two agreeing).
        if len(bad) == 1:
            fixed = fixed_level([c for _, c in got.values() if c])
        if fixed is None:
            raise rounds.Refused(
                f"{', '.join(pids[j] for j in sorted(bad))} ran {cap} times; a slot is re-run at most "
                f"{kit.CAPS['slot_reruns']} times, and a call of the lost slot could change the level; "
                "nothing recorded"
            )
        k = next(iter(bad))
        gone = {"slot": k, "vendor": by_slot[k]["vendor"], "why": bad[k]}
        got = {j: v for j, v in got.items() if j != k}
    elif bad:
        print(
            "; ".join(
                f"{pids[k]} ({by_slot[k]['vendor']}): {why}" for k, why in bad.items()
            )
            + "; nothing recorded, re-run round.sh rehearsal-rate (it re-runs only these)"
        )
        return DEAD if any(str(w).startswith("dead") for w in bad.values()) else VOID
    calls = [
        dict(got[k][1], vendor=by_slot[k]["vendor"], panel=pids[k]) for k in sorted(got)
    ]
    lvl, clause = fixed or level_of(calls)
    kit.append_jsonl(
        settle.holes_path(a.program),
        {
            "id": a.hole,
            "event": "rate",
            "materiality": dict(
                {
                    "level": lvl,
                    "clause": clause,
                    "raters": {str(k): c for k, c in zip(sorted(got), calls)},
                    "at": kit.now_iso(),
                },
                **({"lost": gone} if gone else {}),
            ),
        },
    )
    print(
        f"{a.hole}: {lvl}{' (clause ' + clause + ')' if clause else ''} from "
        + ", ".join(f"{c['vendor']} {c['rating']}" for c in calls)
        + (
            f"; rater{gone['slot']} ({gone['vendor']}) lost past its re-run cap ({gone['why']}), "
            "and no call of it changes the level"
            if gone
            else ""
        )
        + (
            ". Name it: round.sh rehearsal-name (clause g: round.sh hold-g)"
            if lvl == "MATERIAL"
            else ""
        )
    )
    return 0


def cmd_name(a: argparse.Namespace) -> int:
    h = rehearsal_hole(a.program, a.hole)
    settle.confirmed_material(h, "named as a rehearsal known row")
    if kit.clause_g(h):
        raise rounds.Refused(
            f"{a.hole}: rated under clause {(h.get('materiality') or {}).get('clause')}, a clause-(g) "
            "frame omission: hold it for the frame-delta cycle (round.sh hold-g)"
        )
    if not re.match(r"^KR-\d+$", a.known_row):
        raise rounds.Refused(f"--known-row {a.known_row!r}: must read KR-<n>")
    if not settle.WAVE_RE.match(a.wave or ""):
        raise rounds.Refused(f"--wave {a.wave!r}: not a wave id")
    rows = kit.known_rows(a.program)
    by = [str(r.get("id")) for r in rows if str(r.get("hole")) == a.hole]
    if by:
        raise rounds.Refused(f"{a.hole}: already named by {', '.join(by)}")
    if a.known_row in {str(r.get("id")) for r in rows}:
        raise rounds.Refused(f"{a.known_row}: a known row with this id already exists")
    kit.append_jsonl(
        settle.known_rows_path(a.program),
        {
            "id": a.known_row,
            "kind": "rehearsal",
            "hole": a.hole,
            "round": ROUND,
            "frame": (h.get("raised_by") or {}).get("frame"),
            "applied_in_wave": a.wave,
            "blocks_waves": [],
            "status": "open",
            "named": settle.audit(a, a.program),
        },
    )
    print(
        f"{a.hole}: named as {a.known_row}, a rehearsal known row applied in build wave {a.wave}; "
        "the plan is not edited and the row blocks no wave"
    )
    return 0


def add_verbs(sub: Any, host: Any) -> None:
    """Add the verbs to round.sh. `host` is round.py as it runs (its __main__); settle.add_verbs runs
    first, so settle's helpers raise the same Refused."""
    global rounds
    rounds = host
    p = sub.add_parser(
        "rehearsal-raise", help="open a rehearsal session's find as hole H-RH-<n>"
    )
    p.add_argument("--program", required=True)
    p.add_argument(
        "--frame", required=True, help="the reask_map frame the session took"
    )
    p.add_argument("--path", required=True)
    p.add_argument("--lines", required=True)
    p.add_argument("--quote", required=True)
    p.add_argument("--claim", required=True)
    p.add_argument("--names", nargs="*", default=[], help="the frame rows it names")
    p.add_argument("--receipt", help="the session's read receipt")
    p.set_defaults(fn=cmd_raise)
    p = sub.add_parser(
        "rehearsal-verify", help="one verifier on a rehearsal find, through the courier"
    )
    p.add_argument("--program", required=True)
    p.add_argument("--hole", required=True)
    p.add_argument("--vendor", required=True, choices=kit.VENDORS)
    p.set_defaults(fn=cmd_verify)
    p = sub.add_parser(
        "rehearsal-rate", help="the three raters on a CONFIRMED rehearsal find"
    )
    p.add_argument("--program", required=True)
    p.add_argument("--hole", required=True)
    p.set_defaults(fn=cmd_rate)
    p = sub.add_parser(
        "rehearsal-name",
        help="name a CONFIRMED MATERIAL non-(g) rehearsal find as a known row",
    )
    p.add_argument("--program", required=True)
    p.add_argument("--hole", required=True)
    p.add_argument("--known-row", required=True)
    p.add_argument("--wave", required=True, help="the build wave that applies it (W1)")
    p.add_argument("--reason", required=True)
    p.add_argument("--evidence", nargs="+", required=True)
    p.set_defaults(fn=cmd_name)
