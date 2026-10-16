"""cli_records.py — the record verbs of bin/cc-research (REPORT.md §8 item 9) and concern triage
(§5.1, §5.2, §10 item 8); see cli.py for the verb table.

  census add|repin|critic · premise add|revise|file · source add · decision add|tally|rule|reopen|carry|show
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
    """Supersede one or more methods with re-pinned ones and re-baseline the members to what
    every active method now lists. Each --method/--supersedes/--count/--cmd (and --items-file, if
    given) pairs by position, so a population whose methods are ALL stale is re-pinned in one
    call: re-pinning them one at a time is refused, because the agreement check below runs the
    stale method left behind. Nothing is deleted: each OLD stays in `methods` marked superseded,
    and a member no active method lists moves to `retired_members`. All-or-nothing: any refusal
    leaves the census file untouched."""
    from gate_rows_a import active_methods, run_cmd

    r = recs(a)
    f = census_file(r, a.pop)
    c = kit.read_json(f)
    if not c:
        raise kit.KitError(f"{a.pop}: no census yet; `census add` first")
    if not a.why.strip():
        raise kit.KitError(f"{a.pop}: --why is empty; a re-pin records its reason")
    n = len(a.method)
    files = a.items_file or [None] * n
    if not (len(a.supersedes) == len(a.count) == len(a.cmd) == len(files) == n):
        raise kit.KitError(
            f"{a.pop}: --method, --supersedes, --count and --cmd (and --items-file, if given) "
            "pair by position and must be given the same number of times"
        )
    if len(set(a.method)) != n or len(set(a.supersedes)) != n:
        raise kit.KitError(f"{a.pop}: a method is named twice in one re-pin")
    methods = c.get("methods") or []
    pairs = []
    for i in range(n):
        old = next((m for m in methods if m.get("agent") == a.supersedes[i]), None)
        if old is None:
            raise kit.KitError(f"{a.pop}: no method {a.supersedes[i]!r} to supersede")
        if old.get("superseded_by"):
            raise kit.KitError(
                f"{a.pop}: method {a.supersedes[i]!r} is already superseded by "
                f"{old['superseded_by']!r}"
            )
        if any(m.get("agent") == a.method[i] for m in methods):
            raise kit.KitError(
                f"{a.pop}: method {a.method[i]!r} already recorded; a method is never overwritten"
            )
        one = argparse.Namespace(
            pop=a.pop,
            method=a.method[i],
            cmd=a.cmd[i],
            count=a.count[i],
            items_file=files[i],
        )
        pairs.append((old, one, method_items(r, one)))
    at = kit.now_iso()
    news = {}
    for old, one, items in pairs:
        old.update(superseded_by=one.method, superseded_at=at, superseded_why=a.why)
        new = {"agent": one.method, "cmd": one.cmd, "count": one.count, "at": at}
        methods.append(new)
        news[id(new)] = (one.method, items)
    lists: Dict[str, Set[str]] = {}
    for m in active_methods(c):
        if id(m) in news:
            name, items = news[id(m)]
            lists[name] = set(items)
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
    swaps = ", ".join(
        f"method {one.method} supersedes {old['agent']}" for old, one, _ in pairs
    )
    print(
        f"census/{a.pop}.json: {swaps}; "
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


def premise_revise(a: argparse.Namespace) -> int:
    """Append one revision event to an existing premise: its re-check command, its verdict, what it
    bears load for, or the recorded probes that close it, each with the reason. Nothing earlier is
    rewritten; the fold reads the last."""
    import cli_jobs

    r = recs(a)
    premise = folded(r, "premises.jsonl").get(a.id)
    if premise is None:
        raise kit.KitError(
            f"{a.id} is not in premises.jsonl; `premise add` records a new one"
        )
    if not (a.why or "").strip():
        raise kit.KitError(
            "--why is required and may not be empty: a revision states its reason"
        )
    other_fields = (
        a.recheck_cmd is not None
        or a.retire_recheck
        or a.verdict is not None
        or a.load_bearing_for is not None
    )
    if not other_fields and not a.probe:
        raise kit.KitError(
            "nothing to revise: give --recheck-cmd, --retire-recheck, --verdict, "
            "--load-bearing-for or --probe"
        )
    joined = list(premise.get("probes") or [])
    new_probes: List[str] = []
    if a.probe:
        probes = folded(r, "probes.jsonl")
        for pid in a.probe:
            if pid not in probes:
                raise kit.KitError(f"--probe {pid}: no such probe in probes.jsonl")
            if a.id not in (probes[pid].get("closes") or []):
                raise kit.KitError(
                    f"--probe {pid} does not close {a.id} (its closes: "
                    f"{probes[pid].get('closes') or []}); only a probe recorded with "
                    f"--closes {a.id} joins it"
                )
            if pid not in joined and pid not in new_probes:
                new_probes.append(pid)
        if not new_probes and not other_fields:
            raise kit.KitError(
                f"nothing to revise: {', '.join(a.probe)} already joined to {a.id}"
            )
    if a.recheck_cmd is not None and a.retire_recheck:
        raise kit.KitError("--recheck-cmd and --retire-recheck contradict each other")
    if a.repointed_from and a.recheck_cmd is None:
        raise kit.KitError("--repointed-from names where a new --recheck-cmd came from")
    if a.recheck_cmd is not None and (
        not a.recheck_cmd.strip() or cli_jobs.PROSE_RE.match(a.recheck_cmd)
    ):
        raise kit.KitError(
            f"--recheck-cmd {a.recheck_cmd!r} is empty or a prose note, not a command; "
            "use --retire-recheck to drop the re-check"
        )
    if (a.verdict == "refuted") != bool(a.refuted_by):
        raise kit.KitError(
            "--refuted-by is required with --verdict refuted, and only with it"
            if a.verdict == "refuted"
            else "--refuted-by goes only with --verdict refuted"
        )
    if a.refuted_by and not any(
        a.refuted_by in folded(r, store)
        for store in ("probes.jsonl", "challenges.jsonl")
    ):
        raise kit.KitError(
            f"--refuted-by {a.refuted_by}: no such probe or challenge in the records"
        )
    event: Dict[str, Any] = {"id": a.id}
    if a.recheck_cmd is not None:
        event["recheck_cmd"] = a.recheck_cmd
        if a.repointed_from:
            event["recheck_repointed_from"] = a.repointed_from
    if a.retire_recheck:
        event["recheck_cmd"] = None
    if a.verdict is not None:
        event["verdict"] = a.verdict
        if a.refuted_by:
            event["refuted_by"] = a.refuted_by
    if a.load_bearing_for is not None:
        event["load_bearing_for"] = [x for x in a.load_bearing_for if x]
    if new_probes:
        event["probes"] = (
            joined + new_probes
        )  # the fold reads the last value: the full list
    event.update(revised=True, why=a.why.strip())
    kit.append_jsonl(r / "premises.jsonl", event)
    fields = [k for k in event if k not in ("id", "revised", "why")]
    print(f"{a.id}: revised ({', '.join(fields)}) in premises.jsonl")
    return 0


WAVE_ID = r"^[A-Za-z0-9][A-Za-z0-9._-]*$"


def premise_file(a: argparse.Namespace) -> int:
    """File a load-bearing premise below its required level as not-yet-true (decision 55e7da1e7311):
    only the build, an upstream merge or a third party's answer can raise it, so gate row 4 reports it
    FILED, and `gate.sh requires` refuses every wave resting on it until --closing-probe has run and
    joined it. Appends one residual.jsonl row R-NYT-<id> and its reconcile.jsonl line (gate row 12).
    Refuses whatever gate row 4 would fail, with the same reasons (gate_rows_a.not_yet_problems).
    --refile supersedes the live filing instead of refusing a second one: the new row R-NYT-<id>-r<n>
    carries `supersedes`, the old one is marked `superseded_by` and stays as history, and every
    reader (kit.not_yet_rows) takes the newest live filing."""
    import re

    import gate
    from gate_rows_a import descoped_waves, not_yet_problems

    r = recs(a)
    premise = folded(r, "premises.jsonl").get(a.id)
    if premise is None:
        raise kit.KitError(f"{a.id} is not in premises.jsonl")
    for flag, v in (("--why", a.why), ("--owner", a.owner)):
        if not (v or "").strip():
            raise kit.KitError(f"{flag} is required and may not be empty")
    for w in [a.owner_wave] + list(a.blocks_wave or []):
        if not re.match(WAVE_ID, w or ""):
            raise kit.KitError(f"bad wave id {w!r}")
    if not re.match(r"^P-[A-Za-z0-9._-]+$", a.closing_probe or ""):
        raise kit.KitError(
            f"--closing-probe {a.closing_probe!r} is not a probe id (P-...): the probe the "
            f"owner wave runs with --closes {a.id}"
        )
    if premise.get("verdict") == "refuted":
        raise kit.KitError(
            f"{a.id} is refuted; a refuted premise is never filed: revise its dependents (gate row 4)"
        )
    if not premise.get("load_bearing_for"):
        raise kit.KitError(f"{a.id} bears no load; gate row 4 asks nothing of it")
    pr = folded(r, "probes.jsonl")
    if kit.premise_at_level(premise, pr):
        raise kit.KitError(f"{a.id} is already at its required level; nothing to file")
    if kit.parse_due(a.due) is None and kit.due_event(a.due) is None:
        raise kit.KitError(
            f"--due {a.due!r} is not ISO-8601 UTC or YYYY-MM-DD, nor an event due "
            "<wave>+<N>d or cert+<N>d (method v1.3)"
        )
    residual = kit.read_jsonl(r / "residual.jsonl")
    old = kit.not_yet_rows(residual).get(a.id)
    if old is not None and not a.refile:
        raise kit.KitError(
            f"{a.id} is already filed not-yet-true ({old['id']}, due {old.get('due')}); "
            "--refile supersedes it"
        )
    if old is None and a.refile:
        raise kit.KitError(
            f"{a.id} has no not-yet-true filing to refile; file it without --refile"
        )
    rid = f"R-NYT-{a.id}"
    if old is not None:
        # The n-th filing of a premise is R-NYT-<id>-r<n>; the superseded rows stay as history.
        n = 1 + sum(
            1
            for x in kit.fold(residual).values()
            if x.get("why_unreachable") == kit.NOT_YET and x.get("premise") == a.id
        )
        rid = f"{rid}-r{n}"
    row: Dict[str, Any] = {
        "id": rid,
        "why_unreachable": kit.NOT_YET,
        "premise": a.id,
        "awaits": a.awaits,
        "owner_wave": a.owner_wave,
        "owner": a.owner.strip(),
        "due": a.due,
        "closing_probe": a.closing_probe,
        "blocks_waves": sorted(set(a.blocks_wave or [])),
        "why": a.why.strip(),
    }
    if old is not None:
        row["supersedes"] = old["id"]
    ctx = gate.make_ctx(a.program)
    decisions = kit.fold(ctx.jsonl("decisions.jsonl"))
    problems = not_yet_problems(
        premise,
        row,
        decisions,
        descoped_waves(ctx, decisions),
        kit.parse_iso(kit.now_iso()),
        r,
    )
    if problems:
        raise kit.KitError(
            f"{a.id} cannot be filed not-yet-true: " + "; ".join(problems)
        )
    if row["id"] in folded(r, "residual.jsonl"):
        raise kit.KitError(f"{row['id']} already in residual.jsonl")
    kit.append_jsonl(r / "residual.jsonl", row)
    if old is not None:
        kit.append_jsonl(
            r / "residual.jsonl",
            {"id": old["id"], "superseded_by": row["id"], "superseded_why": row["why"]},
        )
    kit.append_jsonl(
        r / "reconcile.jsonl",
        {"id": f"residual:{row['id']}", "disposition": "filed", "ref": row["id"]},
    )
    waves = kit.not_yet_waves(row, premise, decisions)
    verb, sup = ("refiled", f", superseding {old['id']}") if old else ("filed", "")
    print(
        f"{row['id']}: {verb} {a.id} not-yet-true until {a.owner_wave} ({a.awaits}), "
        f"due {kit.due_note(a.due, r)}"
        f"{sup}; waves {', '.join(waves)} wait for {a.closing_probe} to join it"
    )
    return 0


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


def answer_conversion(r: Path, did: str, verb: str, who: str) -> Dict[str, Any]:
    """An answer to a decision `gate.sh sweep` converted (class C past due -> class B on its
    reversible option, waves descoped) restores those waves and closes the class-B packet, whose
    default would otherwise fire over the answer at its deadline. Returns the fields the verb's event
    adds: `packet: null` while the fold still names the converted packet (gate row 5 reads the folded
    packet, and fails a class-B one on an irreversible decision), and the restored waves. Raises, so
    the verb appends nothing, when cc-decide cannot be read or refuses the action."""
    conv: Optional[Dict[str, Any]] = None
    for ev in kit.read_jsonl(r / "decisions.jsonl"):
        if ev.get("id") == did and ev.get("converted_from"):
            conv = ev
    if conv is None:
        return {}
    import gate_sweep

    d = decision_get(r, did)
    pid = str((conv.get("packet") or {}).get("id") or "")
    holds = str((d.get("packet") or {}).get("id") or "") == pid
    waves = d.get("descoped_waves") or []
    if not holds and not waves:
        return {}  # an earlier answer already took this conversion back
    try:
        p = gate_sweep.packets().get(pid)
    except (kit.KitError, OSError, ValueError) as e:
        raise kit.KitError(
            f"{did}: cannot read converted packet {pid} ({e}); nothing recorded, since its "
            "default would fire over this answer"
        )
    if p and p.get("status") == "open":
        rc, _, err = gate_sweep.cc_decide(
            "action",
            pid,
            "--evidence",
            f"answered by {verb} --by {who} {kit.now_iso()}",
        )
        if rc != 0:
            raise kit.KitError(
                f"{did}: cc-decide action {pid} refused ({err}); nothing recorded, since its "
                "default would fire over this answer"
            )
        print(f"{did}: closed converted class-B packet {pid} (answered by {verb})")
    out: Dict[str, Any] = {"packet": None} if holds else {}
    if waves:
        print(
            f"{did}: restored waves {', '.join(waves)} "
            f"(descoped when the sweep converted {conv['converted_from']})"
        )
        out.update(descoped_waves=[], restored_waves=waves)
    return out


def decision_rule(a: argparse.Namespace) -> int:
    r = recs(a)
    d = decision_get(r, a.id)
    if d.get("status") not in ("open", "reopened"):
        raise kit.KitError(f"{a.id}: status {d.get('status')!r}, not open")
    if a.chosen not in {o.get("label") for o in d.get("options") or []}:
        raise kit.KitError(f"{a.id}: {a.chosen!r} is not one of its options")
    c = derived(r, d)
    if a.by == "operator":
        return rule_by_operator(r, a, d, c)
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
    row = {k: v for k, v in row.items() if v is not None}
    row.update(
        answer_conversion(r, a.id, "decision rule", "agent")
    )  # its packet: null stays
    kit.append_jsonl(r / "decisions.jsonl", row)
    print(f"{a.id}: ruled {a.chosen} by agent at a derived {c}%")
    return 0


def rule_by_operator(
    r: Path, a: argparse.Namespace, d: Dict[str, Any], c: Optional[int]
) -> int:
    """Record the operator's re-ruling of a decision he reopened (`decision reopen`). The 90 rule is
    the agent's (§3.5); his ruling needs his words as the receipt and a revisit trigger instead."""
    if d.get("status") != "reopened" or d.get("reopened_by") != "operator":
        raise kit.KitError(
            f"{a.id}: --by operator re-rules a decision the operator reopened (`decision reopen`); "
            f"an open one goes to him as a packet: {PACKET_ROUTE}"
        )
    if not (a.receipt or "").strip() or not (a.revisit_trigger or "").strip():
        raise kit.KitError(
            f"{a.id}: an operator ruling needs --receipt (his words) and --revisit-trigger"
        )
    kit.append_jsonl(
        r / "decisions.jsonl",
        {
            "id": a.id,
            "status": "ruled",
            "ruled_by": "operator",
            "chosen": a.chosen,
            "receipt": a.receipt,
            "revisit_trigger": a.revisit_trigger,
            **answer_conversion(r, a.id, "decision rule", "operator"),
        },
    )
    print(f"{a.id}: ruled {a.chosen} by operator (derived {c}%)")
    return 0


def decision_reopen(a: argparse.Namespace) -> int:
    """Reopen a ruled or carried decision on the operator's ruling (REPORT.md §6.5: a decision is
    reopened at most CAPS["refutation_reopens"] times). It stays `reopened`, which gate row 5
    fails, until `decision rule --by operator` records his re-ruling or `decision carry` carries it
    as a set."""
    r = recs(a)
    d = decision_get(r, a.id)
    if d.get("status") not in ("ruled", "carried"):
        raise kit.KitError(
            f"{a.id}: status {d.get('status')!r}; only a ruled or carried decision is reopened"
        )
    if not a.because.strip() or not a.receipt.strip():
        raise kit.KitError(
            f"{a.id}: a reopen needs --because (what fired) and --receipt (the operator's words)"
        )
    cap = kit.CAPS["refutation_reopens"]
    used = sum(
        1
        for e in kit.read_jsonl(r / "decisions.jsonl")
        if e.get("id") == a.id and e.get("status") == "reopened"
    )
    if used >= cap:
        raise kit.KitError(
            f"{a.id}: already reopened {used} times; the cap is {cap} per decision (§6.5). It is "
            "carried as a set or filed as a packet instead"
        )
    kit.append_jsonl(
        r / "decisions.jsonl",
        {
            "id": a.id,
            "status": "reopened",
            "reopened_by": "operator",
            "reopened_because": a.because,
            "reopen_receipt": a.receipt,
            "reopened_at": kit.now_iso(),
            "reopens": used + 1,
            **answer_conversion(r, a.id, "decision reopen", "operator"),
        },
    )
    print(f"{a.id}: reopened by operator ({used + 1} of {cap})")
    return 0


def carry_set(a: argparse.Namespace, d: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """The set a carry event writes: --set FILE's, else the folded one unchanged. None only for a
    carried decision that stands on a dated class-C packet, which row 5 reads instead of a set."""
    shape = (
        "2-4 members each with a feasibility_probe, a narrowing_probe with wave, owner and due, "
        "and revision_budget_h (gate row 5)"
    )
    if a.set:
        try:
            s = json.loads(Path(a.set).read_text())
        except (OSError, ValueError) as e:
            raise kit.KitError(
                f"{a.id}: --set {a.set} is not a readable JSON file ({e})"
            )
        if not kit.carried_set_ok(s):
            raise kit.KitError(
                f"{a.id}: --set {a.set} is not a well-formed set: {shape}"
            )
        return s
    s = d.get("set")
    if kit.carried_set_ok(s):
        return s
    pk = d.get("packet") or {}
    if d.get("status") == "carried" and pk.get("class") == "C" and pk.get("due"):
        return None
    raise kit.KitError(
        f"{a.id}: no well-formed set to re-affirm; pass --set FILE holding {shape}"
    )


def decision_carry(a: argparse.Namespace) -> int:
    """Carry a decision as a set on the operator's words: re-affirm a carried set after one of its
    premises is refuted (the revision gate row 4 asks for), replace it (--set), or take a ruled or
    reopened decision into a set. It rules nothing and writes no conviction."""
    r = recs(a)
    d = decision_get(r, a.id)
    st = d.get("status")
    if st not in ("carried", "ruled", "reopened"):
        raise kit.KitError(
            f"{a.id}: status {st!r}; only a carried, ruled or reopened decision is carried. An "
            f"open one goes to the operator as a packet: {PACKET_ROUTE}"
        )
    if not a.because.strip() or not a.receipt.strip():
        raise kit.KitError(
            f"{a.id}: a carry needs --because (what changed) and --receipt (the operator's words)"
        )
    s = carry_set(a, d)
    row: Dict[str, Any] = {
        "id": a.id,
        "status": "carried",
        "carried_by": "operator",
        "carried_because": a.because,
        "carry_receipt": a.receipt,
        "carried_at": kit.now_iso(),
    }
    if s is not None:
        row["set"] = s
    if st != "carried":
        # the earlier ruling is withdrawn, so the fold must not keep reading it as the choice
        row.update(chosen=None, ruled_by=None)
    row.update(answer_conversion(r, a.id, "decision carry", "operator"))
    kit.append_jsonl(r / "decisions.jsonl", row)
    how = (
        "on its class-C packet"
        if s is None
        else f"set of {len(s['members'])} {'replaced' if a.set else 're-affirmed'}"
    )
    print(f"{a.id}: carried by operator ({how})")
    return 0


def decision_affirm(a: argparse.Namespace) -> int:
    """Keep a decision `gate.sh sweep` converted as it stands, ruled or carried, on the operator's
    words: its waves come back and its class-B packet closes without spending a reopen (§6.5 caps
    those) or re-stating the ruling. It changes no status, choice or set."""
    r = recs(a)
    d = decision_get(r, a.id)
    st = d.get("status")
    if st not in ("ruled", "carried"):
        raise kit.KitError(
            f"{a.id}: status {st!r}; affirm keeps a ruled or carried decision. An open or "
            "reopened one is answered by `decision rule` or `decision carry`"
        )
    if not a.because.strip() or not a.receipt.strip():
        raise kit.KitError(
            f"{a.id}: an affirm needs --because (why it stands) and --receipt (the operator's words)"
        )
    taken_back = answer_conversion(r, a.id, "decision affirm", "operator")
    if not taken_back:
        raise kit.KitError(
            f"{a.id}: no sweep conversion to take back (no `converted_from` still holding its "
            "class-B packet or descoped waves); affirm answers only that"
        )
    kit.append_jsonl(
        r / "decisions.jsonl",
        {
            "id": a.id,
            "affirmed_by": "operator",
            "affirmed_because": a.because,
            "affirm_receipt": a.receipt,
            "affirmed_at": kit.now_iso(),
            **taken_back,
        },
    )
    print(f"{a.id}: affirmed {st} by operator")
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
        "supersede stale methods with re-pinned ones (repeat the four flags to re-pin several "
        "at once); members no active method lists retire",
    )
    p.add_argument("--pop", required=True)
    p.add_argument(
        "--method", required=True, action="append", help="the new method's agent name"
    )
    p.add_argument(
        "--supersedes",
        required=True,
        action="append",
        help="the active method this one replaces",
    )
    p.add_argument("--count", required=True, type=int, action="append")
    p.add_argument(
        "--cmd",
        required=True,
        action="append",
        help="the generating command gate row 2 re-runs",
    )
    p.add_argument(
        "--why", required=True, help="why the old method is stale (recorded on it)"
    )
    p.add_argument(
        "--items-file",
        action="append",
        help="the member ids, one per line (default: the command's output)",
    )
    p = verb(
        g, "critic", census_critic, "record the blind non-Anthropic census critic, once"
    )
    p.add_argument("--pop", required=True)
    p.add_argument("--family", required=True, choices=("openai", "google"))
    p.add_argument("--unlisted-verified", required=True, type=int)
    p.add_argument("--integrated", action="store_true")

    g = group("premise", "premises.jsonl")
    p = verb(g, "revise", premise_revise, "append a revision event to one premise")
    p.add_argument("--id", required=True)
    p.add_argument("--why", required=True, help="the reason, recorded on the event")
    p.add_argument("--recheck-cmd", help="the new command `job freshness` re-runs")
    p.add_argument(
        "--repointed-from", help="the probe id the new --recheck-cmd was copied from"
    )
    p.add_argument(
        "--retire-recheck",
        action="store_true",
        help="drop the re-check (recheck_cmd null): no freshness pass or gate row 10",
    )
    p.add_argument("--verdict", choices=("holds", "refuted", "partial", "unknown"))
    p.add_argument(
        "--refuted-by",
        help="with --verdict refuted: the probe or challenge that refuted it",
    )
    p.add_argument(
        "--load-bearing-for",
        action="append",
        help="repeat for each dependent; replaces the list (pass '' alone to clear it)",
    )
    p.add_argument(
        "--probe",
        action="append",
        help="repeat; a recorded probe whose closes names this premise joins its probes "
        "(the level gate row 4 reads); never sets the verdict",
    )
    p = verb(
        g,
        "file",
        premise_file,
        "file a below-level premise not-yet-true: gate row 4 FILED, its waves wait for its "
        "closing probe",
    )
    p.add_argument("--id", required=True)
    p.add_argument("--awaits", required=True, choices=sorted(kit.NOT_YET_AWAITS))
    p.add_argument(
        "--owner-wave", required=True, help="the wave that runs the closing probe"
    )
    p.add_argument("--owner", required=True, help="who runs it and joins it")
    p.add_argument("--due", required=True, help="ISO-8601 UTC or YYYY-MM-DD, future")
    p.add_argument(
        "--closing-probe",
        required=True,
        help="the probe id the owner wave records with --closes <id>",
    )
    p.add_argument(
        "--blocks-wave",
        action="append",
        help="repeat; a wave that rests on the premise, beyond its dependents' blocks_waves",
    )
    p.add_argument("--why", required=True, help="why only that event can raise it")
    p.add_argument(
        "--refile",
        action="store_true",
        help="supersede the premise's live filing with this one (a new due, owner, owner wave, "
        "closing probe or blocks-waves; every guard of a first filing applies); the old row "
        "stays in residual.jsonl marked superseded_by",
    )
    p = verb(g, "add", premise_add, "append one premise")
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
    p.add_argument(
        "--by",
        default="agent",
        choices=("agent", "operator"),
        help="operator: record his re-ruling of a decision he reopened (needs --receipt, his "
        "words, and --revisit-trigger; no 90 rule)",
    )
    p = verb(
        g,
        "reopen",
        decision_reopen,
        "reopen a ruled or carried decision on the operator's ruling (at most 2 reopens per decision)",
    )
    p.add_argument("--id", required=True)
    p.add_argument("--because", required=True, help="the flip condition that fired")
    p.add_argument("--receipt", required=True, help="the operator's words")
    p = verb(
        g,
        "carry",
        decision_carry,
        "carry a carried, ruled or reopened decision as a set on the operator's words",
    )
    p.add_argument("--id", required=True)
    p.add_argument(
        "--because", required=True, help="what changed (the refuted premise)"
    )
    p.add_argument("--receipt", required=True, help="the operator's words")
    p.add_argument(
        "--set",
        metavar="FILE",
        help="JSON set replacing the carried one: {members, narrowing_probe, revision_budget_h}; "
        "omitted, the current set is re-affirmed unchanged",
    )
    p = verb(
        g,
        "affirm",
        decision_affirm,
        "keep a sweep-converted ruled or carried decision as it stands, on the operator's words",
    )
    p.add_argument("--id", required=True)
    p.add_argument("--because", required=True, help="why it stands as it is")
    p.add_argument("--receipt", required=True, help="the operator's words")
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
