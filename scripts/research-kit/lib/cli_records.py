"""cli_records.py — the record verbs of bin/cc-research (REPORT.md §8 item 9) and concern triage
(§5.1, §5.2, §10 item 8); see cli.py for the verb table.

  census add|repin|critic · premise add · source add · decision add|tally|rule|show
  concern add|list · park · triage

Every record here is append-only (kit.append_jsonl); a census is one JSON file per population,
rewritten atomically, whose methods are superseded (census repin), never overwritten. Conviction
is never typed: the lead writes a tally and kit.conviction derives the number (§3.5), so there is
no --conviction flag.
Triage asks a blind rater for ONE §5.2 bucket per pending challenge; the rater's prompt names every
bucket with its test and never says which ones count. Python 3.9-safe, standard library only.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import tempfile
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Set, Tuple

import activities
import kit

RAISERS = ("operator", "agent", "sweep", "build", "rehearsal")
PACKET_ROUTE = "cc-research gate file-packet"
# §5.2, in table order: (bucket, its test). Deliberately silent on which buckets count.
BUCKETS: Tuple[Tuple[str, str], ...] = (
    ("generic", "No location, or no frame row it could apply to."),
    ("refuted", "Cannot be reproduced from the primary source."),
    (
        "already-recorded",
        "Matches an existing hole, residual, backlog or reconciliation row; re-raising "
        "it needs evidence dated after that row's disposition.",
    ),
    (
        "immaterial",
        "Fails the materiality rubric: true, but changes no decision, check or plan line.",
    ),
    ("frame-defect", "No checklist row covers the axis at all."),
    (
        "new-requirement",
        "An intake question asked about it and the operator answered, and the new item "
        "contradicts or extends that answer.",
    ),
    ("intent-never-asked", "Operator intent that no intake question covered."),
    ("residual-realized", "Matches a declared residual row."),
    ("contact-hole", "A hole only reality shows, with no residual row."),
    ("set-narrowing", "A carried decision set's dated probe ran."),
    ("drift", "A scheduled re-check changed after validation."),
    ("new-detector", "Found by a model or vendor not in the certifying set."),
    (
        "escape",
        "An in-frame, reproduced, material miss on an axis a checklist row covers (a census "
        "exists for that population, or the intake question was asked).",
    ),
)
BUCKET_NAMES = tuple(b for b, _ in BUCKETS)
CAUSE = {
    "frame-defect": "frame_defect",
    "intent-never-asked": "operator_unelicited",
    "new-requirement": "operator_new",
    "drift": "reality_moved",
    "escape": "escape",
}
ACTIVITY = {
    "escape": "escape",
    "frame-defect": "frame-delta",
    "intent-never-asked": "frame-delta",
}
BRIEF = """You are sorting one concern raised about a research program into exactly ONE bucket.
The buckets, each with its test:

{buckets}

Answer with the bucket name alone on one line, nothing else.

CONCERN:
{concern}

THE PROGRAM'S RECORDS (for the tests above):
{context}
"""


# ── helpers ─────────────────────────────────────────────────────────────────────────────────────


def recs(a: argparse.Namespace) -> Path:
    return kit.records_dir(kit.check_slug(a.program))


def folded(r: Path, name: str) -> Dict[str, Dict[str, Any]]:
    return kit.fold(kit.read_jsonl(r / name))


def next_id(r: Path, name: str, prefix: str) -> str:
    """Reserved under the kit's mint lock, so two concurrent writers never get the same id."""
    return kit.mint_id(r / name, prefix)


def add_new(r: Path, name: str, row: Dict[str, Any]) -> int:
    if row["id"] in folded(r, name):
        raise kit.KitError(
            f"{row['id']} already in {name}; records are append-only, and a later "
            "event goes through its own verb"
        )
    kit.append_jsonl(r / name, {k: v for k, v in row.items() if v is not None})
    print(f"{row['id']}: appended to {name}")
    return 0


def frame(r: Path) -> Dict[str, Any]:
    return kit.read_json(r / "frame.json", {}) or {}


# ── census ──────────────────────────────────────────────────────────────────────────────────────


def census_file(r: Path, pop: str) -> Path:
    if pop not in (frame(r).get("populations") or []):
        raise kit.KitError(f"population {pop!r} is not in frame.json populations")
    return r / "census" / f"{pop}.json"


def census_add(a: argparse.Namespace) -> int:
    r = recs(a)
    f = census_file(r, a.pop)
    c = kit.read_json(f) or {
        "population": a.pop,
        "form": "list",
        "methods": [],
        "members": [],
    }
    if any(m.get("agent") == a.method for m in c.get("methods") or []):
        raise kit.KitError(
            f"{a.pop}: method {a.method!r} already recorded; a method is never overwritten"
        )
    items = method_items(r, a)
    c.setdefault("methods", []).append(
        {"agent": a.method, "cmd": a.cmd, "count": a.count, "at": kit.now_iso()}
    )
    have = {str(m.get("id")) for m in c.get("members") or []}
    c.setdefault("members", []).extend({"id": i} for i in items if i not in have)
    kit.write_json_atomic(f, c)
    print(
        f"census/{a.pop}.json: method {a.method} ({a.count}), {len(c['methods'])} method(s)"
    )
    return 0


def census_cwd(r: Path) -> Path:
    cwd = Path(frame(r).get("deliverable_repo") or r)
    return cwd if cwd.is_dir() else r


def method_items(r: Path, a: argparse.Namespace) -> List[str]:
    """Run --cmd as gate row 2 will, and return the member ids --count is checked against."""
    from gate_rows_a import run_cmd  # the same invocation gate row 2 re-runs

    rc, out = run_cmd(a.cmd, census_cwd(r))
    if rc != 0:
        raise kit.KitError(
            f"{a.pop}: --cmd exited {rc}; gate row 2 re-runs it and needs exit 0"
        )
    src = Path(a.items_file).read_text() if a.items_file else out
    items = sorted({ln.strip() for ln in src.splitlines() if ln.strip()})
    if len(items) != a.count:
        raise kit.KitError(
            f"{a.pop}: --count {a.count}, but method {a.method!r} lists {len(items)}"
        )
    return items


def census_repin(a: argparse.Namespace) -> int:
    """Supersede one method with a re-pinned one and re-baseline the members to what every
    active method now lists. Nothing is deleted: OLD stays in `methods` marked superseded, and a
    member no active method lists moves to `retired_members`. All-or-nothing: any refusal
    leaves the census file untouched."""
    from gate_rows_a import active_methods, run_cmd

    r = recs(a)
    f = census_file(r, a.pop)
    c = kit.read_json(f)
    if not c:
        raise kit.KitError(f"{a.pop}: no census yet; `census add` first")
    if not a.why.strip():
        raise kit.KitError(f"{a.pop}: --why is empty; a re-pin records its reason")
    methods = c.get("methods") or []
    old = next((m for m in methods if m.get("agent") == a.supersedes), None)
    if old is None:
        raise kit.KitError(f"{a.pop}: no method {a.supersedes!r} to supersede")
    if old.get("superseded_by"):
        raise kit.KitError(
            f"{a.pop}: method {a.supersedes!r} is already superseded by "
            f"{old['superseded_by']!r}"
        )
    if any(m.get("agent") == a.method for m in methods):
        raise kit.KitError(
            f"{a.pop}: method {a.method!r} already recorded; a method is never overwritten"
        )
    items = method_items(r, a)
    at = kit.now_iso()
    old.update(superseded_by=a.method, superseded_at=at, superseded_why=a.why)
    new = {"agent": a.method, "cmd": a.cmd, "count": a.count, "at": at}
    methods.append(new)
    lists: Dict[str, Set[str]] = {}
    for m in active_methods(c):
        if m is new:
            lists[a.method] = set(items)
            continue
        rc, out = run_cmd(str(m.get("cmd") or "false"), census_cwd(r))
        if rc != 0:
            raise kit.KitError(
                f"{a.pop}: active method {m.get('agent')!r} exited {rc} on re-run"
            )
        lists[str(m.get("agent"))] = {
            ln.strip() for ln in out.splitlines() if ln.strip()
        }
    union: Set[str] = set().union(*lists.values())
    differ = [
        f"{n} lacks {sorted(union - s)}" for n, s in sorted(lists.items()) if s != union
    ]
    if differ:
        raise kit.KitError(
            f"{a.pop}: the active methods disagree, so the re-pin is refused: "
            + "; ".join(differ)
        )
    kept = [m for m in c.get("members") or [] if str(m.get("id")) in union]
    gone = [m for m in c.get("members") or [] if str(m.get("id")) not in union]
    have = {str(m.get("id")) for m in kept}
    added = sorted(union - have)
    c["members"] = kept + [{"id": i} for i in added]
    retired = [x for x in c.get("retired_members") or [] if x.get("id") not in union]
    retired += [{"id": str(m.get("id")), "at": at, "why": a.why} for m in gone]
    if retired or "retired_members" in c:
        c["retired_members"] = retired
    kit.write_json_atomic(f, c)
    print(
        f"census/{a.pop}.json: method {a.method} supersedes {a.supersedes}; "
        f"{len(c['members'])} member(s), +{len(added)} added, {len(gone)} retired"
    )
    return 0


def census_critic(a: argparse.Namespace) -> int:
    f = census_file(recs(a), a.pop)
    c = kit.read_json(f)
    if not c:
        raise kit.KitError(f"{a.pop}: no census yet; `census add` first")
    if (c.get("critic") or {}).get("ran"):
        raise kit.KitError(
            f"{a.pop}: the census critic already ran; it is checked once"
        )
    c["critic"] = {
        "family": a.family,
        "ran": True,
        "unlisted_verified": a.unlisted_verified,
        "integrated": a.integrated,
        "at": kit.now_iso(),
    }
    kit.write_json_atomic(f, c)
    print(
        f"census/{a.pop}.json: critic {a.family}, {a.unlisted_verified} unlisted verified"
    )
    return 0


# ── premises, sources ───────────────────────────────────────────────────────────────────────────


def premise_add(a: argparse.Namespace) -> int:
    if a.expires:
        try:
            kit.parse_iso(a.expires)
        except ValueError:
            raise kit.KitError(
                f"--expires {a.expires!r} is not ISO-8601 UTC (YYYY-MM-DDTHH:MM:SSZ)"
            )
    return add_new(
        recs(a),
        "premises.jsonl",
        {
            "id": a.id,
            "kind": a.kind,
            "claim": a.claim,
            "truth_lives_in": a.truth_lives_in,
            "verdict": a.verdict,
            "load_bearing_for": a.load_bearing_for or [],
            "probes": a.probe or [],
            "origin": {"source": a.origin_source or "", "tier": a.origin_tier},
            "recheck_cmd": a.recheck_cmd,
            "expires": a.expires,
            "ttl_h": a.ttl_h,
        },
    )


def source_add(a: argparse.Namespace) -> int:
    if a.status == "consulted" and not a.evidence:
        raise kit.KitError(f"{a.id}: consulted needs --evidence (gate row 3)")
    if a.status == "excluded" and not (a.exclusion_quote or "").strip():
        raise kit.KitError(
            f"{a.id}: excluded needs --exclusion-quote, the operator's words (row 3)"
        )
    return add_new(
        recs(a),
        "sources.jsonl",
        {
            "id": a.id,
            "source": a.source,
            "kind": a.kind,
            "access_cmd": a.access_cmd,
            "status": a.status,
            "evidence": a.evidence or [],
            "exclusion_quote": a.exclusion_quote,
            "consulted_at": kit.now_iso() if a.status == "consulted" else None,
        },
    )


# ── decisions ───────────────────────────────────────────────────────────────────────────────────


def decision_get(r: Path, did: str) -> Dict[str, Any]:
    d = folded(r, "decisions.jsonl").get(did)
    if not d:
        raise kit.KitError(f"no decision {did}; `decision add` first")
    return d


def derived(r: Path, d: Dict[str, Any]) -> Optional[int]:
    return kit.conviction(d, folded(r, "premises.jsonl"), folded(r, "probes.jsonl"))


def timebox_fields(r: Path, a: argparse.Namespace) -> Dict[str, Any]:
    """§12.2 (method v1.2): the decision's intake timebox and when its research started, which
    its research ceiling is measured from. Required under a 1.2 frame."""
    if a.timebox_days is None:
        if kit.is_v12(frame(r)):
            raise kit.KitError(
                f"{a.id}: a method 1.2 program needs --timebox-days (the decision's intake "
                "timebox; its research ceiling is twice that, §12.2)"
            )
        return {}
    if a.timebox_days <= 0:
        raise kit.KitError(f"{a.id}: --timebox-days must be above 0")
    return {"timebox_days": a.timebox_days, "research_started": kit.now_iso()}


def decision_add(a: argparse.Namespace) -> int:
    missing = {"do-nothing", "use-what-exists"} - set(a.option)
    if missing:
        raise kit.KitError(
            f"{a.id}: options lack {', '.join(sorted(missing))} (gate row 2)"
        )
    return add_new(
        recs(a),
        "decisions.jsonl",
        {
            "id": a.id,
            "question": a.question,
            "type": a.type,
            "options": [{"label": o} for o in a.option],
            "premises": a.premise or [],
            "reversibility": a.reversibility,
            "runs_used": 0,
            "status": "open",
            **timebox_fields(recs(a), a),
        },
    )


def decision_tally(a: argparse.Namespace) -> int:
    r = recs(a)
    decision_get(r, a.id)
    kit.append_jsonl(
        r / "decisions.jsonl",
        {
            "id": a.id,
            "tally": {
                "premises": a.premise,
                "flip_probe": a.flip_probe,
                "flip_result": None if a.flip_result == "null" else a.flip_result,
            },
        },
    )
    print(
        f"{a.id}: tally recorded; derived conviction {derived(r, decision_get(r, a.id))}"
    )
    return 0


def decision_rule(a: argparse.Namespace) -> int:
    r = recs(a)
    d = decision_get(r, a.id)
    if d.get("status") not in ("open", "reopened"):
        raise kit.KitError(f"{a.id}: status {d.get('status')!r}, not open")
    if a.chosen not in {o.get("label") for o in d.get("options") or []}:
        raise kit.KitError(f"{a.id}: {a.chosen!r} is not one of its options")
    c = derived(r, d)
    if c is None or c < 90:
        raise kit.KitError(
            f"{a.id}: derived conviction {c}%; an agent rules only at 90 (§3.5). "
            f"File it to the operator instead: {PACKET_ROUTE}"
        )
    if d.get("reversibility") == "reversible" and not a.revisit_trigger:
        raise kit.KitError(
            f"{a.id}: a reversible ruling needs --revisit-trigger (gate row 5)"
        )
    row = {
        "id": a.id,
        "status": "ruled",
        "ruled_by": "agent",
        "chosen": a.chosen,
        "receipt": a.receipt,
        "revisit_trigger": a.revisit_trigger,
    }
    kit.append_jsonl(
        r / "decisions.jsonl", {k: v for k, v in row.items() if v is not None}
    )
    print(f"{a.id}: ruled {a.chosen} by agent at a derived {c}%")
    return 0


def decision_show(a: argparse.Namespace) -> int:
    r = recs(a)
    d = decision_get(r, a.id)
    out = dict(d, conviction=derived(r, d))
    print(
        json.dumps(out, indent=1, sort_keys=True)
        if a.json
        else f"{a.id} [{out.get('status')}] {out.get('question', '')}\n"
        f"  conviction {out['conviction']}% (derived) · chosen {out.get('chosen') or '-'}"
    )
    return 0


# ── concerns, parking ───────────────────────────────────────────────────────────────────────────


def concern_add(a: argparse.Namespace) -> int:
    r = recs(a)
    return add_new(
        r,
        "challenges.jsonl",
        {
            "id": next_id(r, "challenges.jsonl", "CH"),
            "ts": kit.now_iso(),
            "raised_by": a.raised_by,
            "text": a.text,
            "triage": "pending",
        },
    )


def concern_list(a: argparse.Namespace) -> int:
    rows = [
        c
        for c in folded(recs(a), "challenges.jsonl").values()
        if not a.pending or c.get("triage") == "pending"
    ]
    if a.json:
        print(json.dumps(rows, sort_keys=True))
    for c in [] if a.json else rows:
        print(
            f"{c['id']} [{c.get('triage')}] {c.get('raised_by')}: {c.get('text', '')}"
        )
    return 0


def park(a: argparse.Namespace) -> int:
    r = recs(a)
    return add_new(
        r,
        "changes.jsonl",
        {
            "id": next_id(r, "changes.jsonl", "CR"),
            "cause": "operator_new",
            "status": "parked",
            "justification": a.idea,
            "raised_by": a.raised_by,
            "ts": kit.now_iso(),
        },
    )


# ── triage ──────────────────────────────────────────────────────────────────────────────────────


def triage_prompt(r: Path, c: Dict[str, Any]) -> str:
    fr = frame(r)
    ctx = {
        "populations_with_census": fr.get("populations") or [],
        "sources_required": fr.get("sources_required") or [],
        "intake_questions": [m.get("frame") for m in fr.get("reask_map") or []],
        "residual_rows": [
            {"id": x.get("id"), "property": x.get("property")}
            for x in kit.read_jsonl(r / "residual.jsonl")
        ],
        "holes": sorted(folded(r, "holes.jsonl")),
        "carried_decisions": [
            d["id"]
            for d in folded(r, "decisions.jsonl").values()
            if d.get("status") == "carried"
        ],
    }
    concern = {
        k: c.get(k)
        for k in ("text", "raised_by", "locus", "names", "evidence_date")
        if c.get(k)
    }
    return BRIEF.format(
        buckets="\n".join(f"- {b}: {t}" for b, t in BUCKETS),
        concern=json.dumps(concern, indent=1),
        context=json.dumps(ctx, indent=1),
    )


Rater = Callable[[str], Tuple[Optional[str], Dict[str, Any], str]]


def make_rater(a: argparse.Namespace) -> Rater:
    """(prompt) -> (bucket or None, {vendor, model}, why not). Env command first, else courier."""
    cmd = os.environ.get("CC_RESEARCH_TRIAGE_RATER")
    resolved: Dict[str, Any] = {}

    def ask(prompt: str) -> Tuple[Optional[str], Dict[str, Any], str]:
        if cmd:
            who: Dict[str, Any] = {
                "vendor": "command",
                "model": os.path.basename(cmd.split()[0]),
            }
            try:
                p = subprocess.run(
                    ["/bin/bash", "-c", cmd],
                    input=prompt,
                    capture_output=True,
                    text=True,
                    timeout=a.timeout,
                )
            except subprocess.TimeoutExpired:
                return None, who, f"timed out at {a.timeout} s"
            except OSError as e:
                return None, who, f"did not start: {e}"
            if p.returncode != 0:
                return None, who, f"rater exited {p.returncode}"
            reply = p.stdout
        else:
            import courier

            if "bin" not in resolved:
                resolved["bin"], resolved["how"] = courier.resolve(a.vendor)
            model = a.model or courier.pins(a.program).get(a.vendor)
            who = {"vendor": a.vendor, "model": model}
            if not resolved["bin"]:
                return None, who, f"no {a.vendor} CLI ({resolved['how']})"
            work = Path(tempfile.mkdtemp(prefix="cc-research-triage-"))
            try:
                res = courier.call(
                    a.program, a.vendor, resolved["bin"], prompt, model, work, a.timeout
                )
            finally:
                shutil.rmtree(work, ignore_errors=True)
            who["model"] = (res["model_ids"] or [model or "unknown"])[0]
            if res["error"]:
                return None, who, res["error"]
            reply = res["reply"] or ""
        words = reply.strip().strip("`'\".").lower().split()
        if len(words) != 1 or words[0] not in BUCKET_NAMES:
            return None, who, f"answered {reply.strip()[:60]!r}, not one bucket"
        return words[0], who, ""

    return ask


def triage(a: argparse.Namespace) -> int:
    r = recs(a)
    pending = [
        c
        for c in folded(r, "challenges.jsonl").values()
        if c.get("triage") == "pending"
    ]
    if not pending:
        print("[]" if a.json else "no pending concerns")
        return 0
    ask, results = make_rater(a), []
    batch = activities.open_activity(a.program, "triage-batch")
    prev = os.environ.get("CC_RESEARCH_ACTIVITY")
    os.environ["CC_RESEARCH_ACTIVITY"] = (
        batch  # the research block lets the tagged batch through
    )
    try:
        for c in pending:
            bucket, who, why = ask(triage_prompt(r, c))
            res: Dict[str, Any] = {"id": c["id"], "triage": bucket or "pending"}
            if bucket is None:
                res["why"] = why
                results.append(res)
                continue
            ev: Dict[str, Any] = {
                "id": c["id"],
                "triage": bucket,
                "rater": who,
                "ts": kit.now_iso(),
            }
            if bucket in ACTIVITY:
                ev["activity"] = res["activity"] = activities.open_activity(
                    a.program, ACTIVITY[bucket]
                )
            kit.append_jsonl(r / "challenges.jsonl", ev)
            if bucket in CAUSE:
                cr = {
                    "id": next_id(r, "changes.jsonl", "CR"),
                    "cause": CAUSE[bucket],
                    "challenge": c["id"],
                    "justification": c.get("text", ""),
                    "ts": kit.now_iso(),
                }
                if bucket == "new-requirement":
                    cr["status"] = (
                        "parked"  # §5.1: a new idea parks in the next version
                    )
                kit.append_jsonl(r / "changes.jsonl", cr)
                res["change"] = cr["id"]
            results.append(res)
    finally:
        if prev is None:
            os.environ.pop("CC_RESEARCH_ACTIVITY", None)
        else:
            os.environ["CC_RESEARCH_ACTIVITY"] = prev
        activities.close_activity(batch)
    if a.json:
        print(json.dumps(results, sort_keys=True))
    for x in [] if a.json else results:
        tail = (
            f" ({x['why']})"
            if "why" in x
            else "".join(f" {x[k]}" for k in ("change", "activity") if k in x)
        )
        print(f"{x['id']}: {x['triage']}{tail}")
    return 3 if any(x["triage"] == "pending" for x in results) else 0


# ── the verb table ──────────────────────────────────────────────────────────────────────────────


def add_verbs(sub: Any) -> None:
    """census premise source decision concern park triage."""

    def verb(
        parent: Any, name: str, fn: Callable[[argparse.Namespace], int], hlp: str
    ) -> Any:
        p = parent.add_parser(name, help=hlp)
        p.add_argument("--program", required=True)
        p.set_defaults(fn=fn)
        return p

    def group(name: str, hlp: str) -> Any:
        return sub.add_parser(name, help=hlp).add_subparsers(
            dest=f"{name}_verb", required=True
        )

    g = group("census", "census/<pop>.json: methods and the critic")
    p = verb(
        g, "add", census_add, "add one independent method to a population's census"
    )
    p.add_argument("--pop", required=True)
    p.add_argument("--method", required=True, help="the agent that ran this method")
    p.add_argument("--count", required=True, type=int)
    p.add_argument(
        "--cmd", required=True, help="the generating command gate row 2 re-runs"
    )
    p.add_argument(
        "--items-file",
        help="the member ids, one per line (default: the command's output)",
    )
    p = verb(
        g,
        "repin",
        census_repin,
        "supersede a stale method with a re-pinned one; members no active method lists retire",
    )
    p.add_argument("--pop", required=True)
    p.add_argument("--method", required=True, help="the new method's agent name")
    p.add_argument(
        "--supersedes", required=True, help="the active method this one replaces"
    )
    p.add_argument("--count", required=True, type=int)
    p.add_argument(
        "--cmd", required=True, help="the generating command gate row 2 re-runs"
    )
    p.add_argument(
        "--why", required=True, help="why the old method is stale (recorded on it)"
    )
    p.add_argument(
        "--items-file",
        help="the member ids, one per line (default: the command's output)",
    )
    p = verb(
        g, "critic", census_critic, "record the blind non-Anthropic census critic, once"
    )
    p.add_argument("--pop", required=True)
    p.add_argument("--family", required=True, choices=("openai", "google"))
    p.add_argument("--unlisted-verified", required=True, type=int)
    p.add_argument("--integrated", action="store_true")

    p = verb(
        group("premise", "premises.jsonl"), "add", premise_add, "append one premise"
    )
    p.add_argument("--id", required=True)
    p.add_argument("--claim", required=True)
    p.add_argument(
        "--truth-lives-in", required=True, choices=sorted(kit.REQUIRED_LEVEL)
    )
    p.add_argument("--kind", default="claim", choices=("claim", "external-fact"))
    p.add_argument(
        "--verdict",
        default="unknown",
        choices=("holds", "refuted", "partial", "unknown"),
    )
    p.add_argument("--load-bearing-for", action="append")
    p.add_argument("--probe", action="append")
    p.add_argument("--origin-source")
    p.add_argument("--origin-tier", default="E0", choices=[f"E{i}" for i in range(7)])
    p.add_argument("--recheck-cmd")
    p.add_argument(
        "--expires", help="ISO-8601 UTC, when the premise must be re-checked"
    )
    p.add_argument("--ttl-h", type=float)

    p = verb(group("source", "sources.jsonl"), "add", source_add, "append one source")
    p.add_argument("--id", required=True)
    p.add_argument("--source", required=True)
    p.add_argument(
        "--kind",
        required=True,
        choices=("ours", "external", "operator-owned", "production"),
    )
    p.add_argument("--status", required=True, choices=("consulted", "excluded"))
    p.add_argument("--access-cmd")
    p.add_argument("--evidence", action="append")
    p.add_argument("--exclusion-quote")

    g = group(
        "decision", "decisions.jsonl: the lead writes a tally, never a conviction"
    )
    p = verb(g, "add", decision_add, "append one open decision")
    p.add_argument("--id", required=True)
    p.add_argument("--question", required=True)
    p.add_argument("--option", required=True, action="append")
    p.add_argument("--premise", action="append")
    p.add_argument("--type", default="design", choices=("fact", "design", "taste"))
    p.add_argument(
        "--reversibility",
        default="reversible",
        choices=("reversible", "costly", "irreversible"),
    )
    p.add_argument("--timebox-days", type=float)
    p = verb(g, "tally", decision_tally, "record the premises and the flip probe")
    p.add_argument("--id", required=True)
    p.add_argument("--premise", required=True, action="append")
    p.add_argument("--flip-probe")
    p.add_argument(
        "--flip-result", default="null", choices=("negative", "positive", "null")
    )
    p = verb(g, "rule", decision_rule, "rule as agent, only at a derived 90")
    p.add_argument("--id", required=True)
    p.add_argument("--chosen", required=True)
    p.add_argument("--receipt")
    p.add_argument("--revisit-trigger")
    p = verb(g, "show", decision_show, "print a decision with its derived conviction")
    p.add_argument("--id", required=True)
    p.add_argument("--json", action="store_true")

    g = group("concern", "challenges.jsonl")
    p = verb(g, "add", concern_add, "append one pending concern")
    p.add_argument("--text", required=True)
    p.add_argument("--raised-by", default="operator", choices=RAISERS)
    p = verb(g, "list", concern_list, "list concerns")
    p.add_argument("--pending", action="store_true")
    p.add_argument("--json", action="store_true")

    p = verb(sub, "park", park, "park a new idea in the next version (§5.1)")
    p.add_argument("--idea", required=True)
    p.add_argument("--raised-by", default="operator", choices=RAISERS)

    p = verb(
        sub, "triage", triage, "bucket pending concerns through a blind rater (§5.2)"
    )
    p.add_argument(
        "--vendor",
        default="openai",
        choices=("openai", "google"),
        help="non-Anthropic rater when CC_RESEARCH_TRIAGE_RATER is unset",
    )
    p.add_argument("--model")
    p.add_argument("--timeout", type=int, default=600)
    p.add_argument("--json", action="store_true")
