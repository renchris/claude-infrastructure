"""gate_rows_a.py — gate rows 1-8 of REPORT.md §3.10 (frame, censuses, sources, premises, decisions,
instruments, contact, trace and persistence).

Each predicate RE-EXECUTES what it names in this run (census methods, acceptance checks against their
known-bad and known-good fixtures, private-receipt hashes), and UNKNOWN FAILS: a missing or unreadable
record is a FAIL with its reason, never a pass. Conviction is recomputed by kit.conviction (§3.5),
never read from what an agent typed.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import time
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Set, Tuple

import kit
from gate import FAIL, FILED, PASS, Ctx, Row

SUPERLATIVE = re.compile(
    r"\b(perfect|100th|maximal|best|exhaustive|absolute|flawless)\b", re.I
)
FAC_IDS = [f"FAC-{i:02d}" for i in range(1, 34)]
# Method v1.3 (REPORT.md §13.6): five rows that front-load every wait (accrual, third party, one-shot
# spend, elapsed-time or scheduled check, event-keyed due), required of a frame stamped 1.3 or later.
FAC_V13_IDS = [f"FAC-{i:02d}" for i in range(34, 39)]
# The command bound for every command a gate row re-runs (row 2's census methods, row 6's acceptance
# fixtures, rows 20-21's artifact checks): TIMEOUT s scaled by the 1-min load per CPU, capped at
# TIMEOUT_CAP. A bound sized on an idle machine convicts a healthy check in the background band
# (2026-10-16, load1 ~330 on 10 CPUs: census methods that exit 0 in 39 s and 54 s, and an acceptance
# check that exits 0 in 131 s, all hit the old fixed 60 s and failed rows 2 and 6). So a timeout is
# never the check's exit: run_cmd retries once at the cap and, if that expires too, returns rc
# None with a "gave no verdict" message, which every caller turns into a FAIL that says so.
# CC_RESEARCH_GATE_TIMEOUT and CC_RESEARCH_GATE_TIMEOUT_CAP override the two figures.
TIMEOUT = 60
TIMEOUT_CAP = 900


def row(n: int, name: str) -> Callable[[Callable[[Ctx], Row]], Callable[[Ctx], Row]]:
    def deco(fn: Callable[[Ctx], Row]) -> Callable[[Ctx], Row]:
        fn.row = (n, name)  # type: ignore[attr-defined]
        return fn

    return deco


def verdict(
    n: int, name: str, fails: List[str], filed: List[str], notes: List[str]
) -> Row:
    status = FAIL if fails else (FILED if filed else PASS)
    return Row(n, name, status, fails + [f"FILED {f}" for f in filed] + notes)


def bound_s(name: str, default: float) -> float:
    try:
        v = float(os.environ.get(name) or default)
    except ValueError:
        raise kit.KitError(f"{name} must be a number of seconds")
    if v <= 0:
        raise kit.KitError(f"{name} must be a positive number of seconds")
    return v


def load_bound(base: float, cap: float) -> Tuple[float, float]:
    """(bound, load1): `base` scaled by the 1-min load per CPU, never below base, never above cap."""
    load = os.getloadavg()[0]
    return min(cap, base * max(1.0, load / (os.cpu_count() or 1))), load


def run_cmd(
    cmd: str, cwd: Path, env: Optional[Dict[str, str]] = None
) -> Tuple[Optional[int], str]:
    """(exit, stdout) of `cmd`, or (None, a "gave no verdict" message) when it outlives the bound
    (TIMEOUT above): an attempt at the load-scaled bound and, if that expires short of the cap, one
    retry at the cap. The whole process group is killed on expiry, so a grandchild holding the
    output pipe cannot outlive the bound."""
    base = bound_s("CC_RESEARCH_GATE_TIMEOUT", TIMEOUT)
    cap = max(base, bound_s("CC_RESEARCH_GATE_TIMEOUT_CAP", TIMEOUT_CAP))
    bound, load = load_bound(base, cap)
    while True:
        try:
            p = subprocess.Popen(
                ["/bin/bash", "-c", cmd],
                cwd=str(cwd),
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
                env=dict(os.environ, **(env or {})),
                start_new_session=True,
            )
        except OSError as e:
            return 127, str(e)
        try:
            out, _ = p.communicate(timeout=bound)
            return p.returncode, out
        except subprocess.TimeoutExpired:
            try:
                os.killpg(p.pid, 9)
            except OSError:
                pass
            p.communicate()
        if bound >= cap:
            short = cmd if len(cmd) <= 80 else cmd[:77] + "..."
            return None, (
                f"`{short}` gave no verdict: timed out after {bound:g} s at load1 {load:.1f}"
            )
        bound, load = cap, os.getloadavg()[0]


def ran(rc: Optional[int], out: str) -> str:
    """How a run_cmd call ended, for a FAIL line: its exit, or the no-verdict message."""
    return out if rc is None else f"exited {rc}"


def active_methods(census: Dict[str, Any]) -> List[Dict[str, Any]]:
    """A census's methods minus the superseded ones (`census repin`), which stay recorded only."""
    return [m for m in census.get("methods") or [] if not m.get("superseded_by")]


def numberless_superlative(text: str) -> bool:
    return any(
        SUPERLATIVE.search(s) and not re.search(r"\d", s)
        for s in re.split(r"(?<=[.;!?])\s+", text or "")
    )


def folded(ctx: Ctx, rel: str) -> Dict[str, Dict[str, Any]]:
    return kit.fold(ctx.jsonl(rel))


def known_rows(ctx: Ctx) -> List[Dict[str, Any]]:
    rows = {r["id"]: dict(r) for r in ctx.frame.get("known_rows") or [] if r.get("id")}
    for ev in ctx.jsonl("known_rows.jsonl"):
        rows.setdefault(ev["id"], {}).update(ev)
    return list(rows.values())


def held_at(ctx: Ctx) -> Dict[str, str]:
    """Per known row, when it was held: its `held.at`, else the ts of the FIRST event naming it. The
    folded ts is the newest event's, so a later event (a `rekey-wave`, a packet resolution) would move
    the hold and change which frame signatures count as after it (gate_sweep step 3, gate.py
    close_delta_rows). A row only frame.json carries has no hold time."""
    out: Dict[str, str] = {}
    for ev in ctx.jsonl("known_rows.jsonl"):
        kid = ev.get("id")
        if kid and kid not in out:
            at = (ev.get("held") or {}).get("at") or ev.get("ts")
            if at:
                out[str(kid)] = str(at)
    return out


def probes(ctx: Ctx) -> Dict[str, Dict[str, Any]]:
    return folded(ctx, "probes.jsonl")


# ── row 1 ───────────────────────────────────────────────────────────────────────────────────────


@row(1, "Frame")
def row1(ctx: Ctx) -> Row:
    import operator_sign

    fails: List[str] = []
    notes: List[str] = []
    fr = ctx.frame
    if not fr:
        return Row(1, "Frame", FAIL, ["frame.json missing or empty"])
    sigs = operator_sign.research_records(ctx.slug, "frame")
    if not sigs:
        fails.append(
            "the frame has never been signed (cc-signoff research:<slug>/frame, operator only)"
        )
    else:
        # a delegated acceptance (REPORT.md §14) counts exactly as a signature does, and says so;
        # every line keeps "signature" or "frame pin", which `intake.py lint` reads past
        newest = max(sigs, key=lambda r: r.get("at", 0))
        if newest["_verdict"] == operator_sign.VOID and newest.get("_delegated"):
            fails.append(
                f"the newest frame signature is VOID: delegated acceptance ({newest.get('_why')})"
            )
        elif newest["_verdict"] == operator_sign.VOID:
            fails.append("the newest frame signature is VOID: agent-written signature")
        elif newest["_verdict"] == operator_sign.STALE:
            fails.append(
                "the newest frame signature is STALE: frame.json changed since it was signed"
                + (" (a delegated acceptance)" if newest.get("_delegated") else "")
            )
        else:
            notes.append(
                f"frame pin {newest['pins'].get('frame.json', '?')[:12]} "
                + (
                    operator_sign.signed_words(newest)
                    if newest.get("_delegated")
                    else f"signed {newest.get('at_iso', '')}"
                )
            )
    acc = (ctx.json("acceptance.json", {}) or {}).get("rows") or []
    for r in acc:
        if numberless_superlative(str(r.get("predicate"))):
            fails.append(f"{r.get('id')}: numberless superlative in its predicate")
        miss = [
            k for k in ("check_cmd", "threshold", "negative_branch") if not r.get(k)
        ]
        if miss:
            fails.append(f"{r.get('id')}: missing {', '.join(miss)}")
    if numberless_superlative(str(fr.get("deliverable", ""))):
        fails.append("the deliverable sentence carries a numberless superlative")
    fac = {m.get("fac"): m for m in fr.get("fac_map") or []}
    unmapped = [
        f
        for f in FAC_IDS + (FAC_V13_IDS if kit.is_v13(fr) else [])
        if not (fac.get(f, {}).get("row") or fac.get(f, {}).get("na_reason"))
    ]
    if unmapped:
        fails.append(f"checklist rows unmapped: {', '.join(unmapped)}")
    for m in fr.get("reask_map") or []:
        if not (m.get("axis") or m.get("excluded_quote")):
            fails.append(
                f"historical question frame {m.get('frame')!r} neither mapped nor excluded in your words"
            )
    open_changes = [
        c["id"]
        for c in folded(ctx, "changes.jsonl").values()
        if c.get("status") == "open"
        and c.get("version", fr.get("version")) == fr.get("version")
    ]
    if open_changes:
        fails.append(f"open changes to this version: {', '.join(open_changes)}")
    import frame_delta

    fails += frame_delta.pin_fails(ctx.records, fr)
    rulings = fr.get("rulings") or {}
    for k in ("definition_of_complete", "exemption"):
        if not (rulings.get(k) or {}).get("at"):
            fails.append(f"§3.1 ruling not recorded: {k}")
    opened = [r["id"] for r in known_rows(ctx) if r.get("status", "open") == "open"]
    if opened:
        notes.append(
            f"open known rows (gate dependent build waves, not this row): {', '.join(opened)}"
        )
    return verdict(1, "Frame", fails, [], notes)


# ── row 2 ───────────────────────────────────────────────────────────────────────────────────────


@row(2, "Censuses")
def row2(ctx: Ctx) -> Row:
    fails: List[str] = []
    cwd = Path(ctx.frame.get("deliverable_repo") or ctx.records)
    if not cwd.is_dir():
        cwd = ctx.records
    for pop in ctx.frame.get("populations") or []:
        c = ctx.json(f"census/{pop}.json")
        if not c:
            fails.append(f"{pop}: no census file")
            continue
        # A superseded method is history, not evidence: it is neither re-run nor counted, and a
        # retired member (census repin) is no longer expected in any re-run.
        methods = active_methods(c)
        if len(methods) < 2:
            sup = len(c.get("methods") or []) - len(methods)
            fails.append(
                f"{pop}: {len(methods)} method(s)"
                + (f" active ({sup} superseded)" if sup else "")
                + "; 2 independent methods are required"
            )
        stored: Set[str] = {str(m.get("id")) for m in c.get("members") or []}
        for m in methods:
            rc, out = run_cmd(str(m.get("cmd") or "false"), cwd)
            got = {ln.strip() for ln in out.splitlines() if ln.strip()}
            if rc != 0:
                fails.append(
                    f"{pop}: method {m.get('agent', '?')} {ran(rc, out)} on re-run"
                )
            elif not stored <= got or (got - stored and not c.get("as_of")):
                fails.append(
                    f"{pop}: method {m.get('agent', '?')} re-run does not reproduce the member set "
                    f"(missing {sorted(stored - got)[:3]}, extra {sorted(got - stored)[:3]})"
                )
        grid = c.get("grid") or {}
        empty = [
            f"{x.get('row')}/{x.get('col')}"
            for x in grid.get("cells") or []
            if not (x.get("probe") or x.get("na_reason"))
        ]
        if empty:
            fails.append(f"{pop}: empty grid cells {', '.join(empty[:4])}")
        critic = c.get("critic") or {}
        if not critic.get("ran") or (
            critic.get("unlisted_verified") and not critic.get("integrated")
        ):
            fails.append(
                f"{pop}: census reviewer not run, or its verified members not integrated"
            )
    for d in folded(ctx, "decisions.jsonl").values():
        labels = {o.get("label") for o in d.get("options") or []}
        if not {"do-nothing", "use-what-exists"} <= labels:
            fails.append(f"{d.get('id')}: options lack do-nothing or use-what-exists")
    return verdict(2, "Censuses", fails, [], [])


# ── row 3 ───────────────────────────────────────────────────────────────────────────────────────


@row(3, "Sources")
def row3(ctx: Ctx) -> Row:
    fails: List[str] = []
    src = folded(ctx, "sources.jsonl")
    for sid in ctx.frame.get("sources_required") or []:
        s = src.get(sid)
        if not s:
            fails.append(f"{sid}: never consulted or excluded")
        elif s.get("status") == "consulted":
            ev = s.get("evidence") or []
            missing = [e for e in ev if not (ctx.records / e).exists()]
            if not ev or missing:
                fails.append(
                    f"{sid}: consulted, but evidence {'missing' if not ev else missing[:2]}"
                )
        elif s.get("status") == "excluded":
            if not (s.get("exclusion_quote") or "").strip():
                fails.append(f"{sid}: excluded without your quote")
        else:
            fails.append(f"{sid}: status {s.get('status')!r}")
    return verdict(3, "Sources", fails, [], [])


# ── row 4 ───────────────────────────────────────────────────────────────────────────────────────


def refuted_at(events: List[Dict[str, Any]]) -> Dict[str, str]:
    """Per premise id, the ts of the event that set verdict=refuted (the move into it; an event that
    re-asserts refuted moves nothing). A later event with no verdict (a freshness re-check appending
    its probe, a `premise revise` of the command) is not a refutation, so it never asks a dependent
    decision to be revised again — keying on the folded ts did exactly that."""
    out: Dict[str, str] = {}
    cur: Dict[str, Any] = {}
    for e in events:
        pid = e.get("id")
        if pid is None or "verdict" not in e:
            continue
        if e["verdict"] == "refuted" and cur.get(pid) != "refuted":
            out[pid] = str(e.get("ts", ""))
        cur[pid] = e["verdict"]
    return out


def unrevised_dependents(
    p: Dict[str, Any], events: List[Dict[str, Any]], since: Dict[str, str]
) -> List[str]:
    """A refuted premise's DR dependents with no ruled, reopened, carried or descoped event at or after
    the event that refuted it (refuted_at)."""
    at = since.get(p["id"], str(p.get("ts", "")))
    return [
        dep
        for dep in p.get("load_bearing_for") or []
        if dep.startswith("DR")
        and not any(
            e.get("id") == dep
            and str(e.get("ts", "")) >= at
            and e.get("status") in ("ruled", "reopened", "carried", "descoped")
            for e in events
        )
    ]


def descoped_waves(ctx: Ctx, decisions: Dict[str, Dict[str, Any]]) -> Set[str]:
    """Every wave a decision or known row descoped (the same reading as gate_requires)."""
    out: Set[str] = set()
    for x in list(decisions.values()) + known_rows(ctx):
        out |= {w for w in x.get("descoped_waves") or [] if isinstance(w, str)}
    return out


def not_yet_problems(
    p: Dict[str, Any],
    row: Dict[str, Any],
    decisions: Dict[str, Dict[str, Any]],
    descoped: Set[str],
    now: float,
    records: Optional[Path] = None,
) -> List[str]:
    """Why a not-yet-true filing does not carry its below-level premise, or [] when it does (decision
    55e7da1e7311). One implementation for gate row 4 and `cc-research premise file`. `records` is
    the program's records dir, which a due keyed to an event (method v1.3) resolves against."""
    import cli_jobs

    out: List[str] = []
    truth, awaits = p.get("truth_lives_in"), row.get("awaits")
    if p.get("verdict") not in ("partial", "holds"):
        out.append(
            f"verdict {p.get('verdict')!r}; only a partial or holding premise is filed"
        )
    if awaits not in kit.NOT_YET_AWAITS:
        out.append(f"awaits {awaits!r} is not one of {', '.join(kit.NOT_YET_AWAITS)}")
    elif truth not in kit.NOT_YET_AWAITS[awaits]:
        out.append(
            f"a {truth} premise is not raised by {awaits} "
            f"({awaits} raises {', '.join(kit.NOT_YET_AWAITS[awaits])})"
        )
    miss = [
        k for k in ("owner_wave", "owner", "due", "closing_probe") if not row.get(k)
    ]
    if miss:
        out.append(f"the filing is missing {', '.join(miss)}")
    kind, due = kit.resolve_due(row.get("due"), records)
    if row.get("due") and (kind == "bad" or (kind == "date" and due <= now)):
        out.append(f"due {row.get('due')!r} is unparseable or already past")
    elif kind == "event" and due is not None and due <= now:
        ev_, at_ = kit.due_event(row.get("due")), None
        if ev_ is not None:
            at_ = (
                kit.cert_issued(records)
                if ev_[0] == kit.CERT_EVENT
                else kit.wave_starts(records).get(ev_[0])
            )
        what = (
            "cert issued"
            if ev_ and ev_[0] == kit.CERT_EVENT
            else f"{ev_[0] if ev_ else '?'} started"
        )
        out.append(
            f"due {row.get('due')!r} ({what} {at_}) resolved to "
            f"{time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(due))}, already past"
        )
    ev = kit.due_event(row.get("due"))
    if ev and ev[0] != kit.CERT_EVENT:
        named = {row.get("owner_wave")} | set(kit.not_yet_waves(row, p, decisions))
        if ev[0] not in named:
            out.append(
                f"due {row.get('due')!r} is keyed to {ev[0]}, a wave this filing does not name; "
                "key it to its owner wave, a wave resting on it, or cert"
            )
    rc = str(p.get("recheck_cmd") or "")
    if not rc.strip() or cli_jobs.PROSE_RE.match(rc):
        out.append("its recheck_cmd is missing or a prose note, not a command")
    deps = p.get("load_bearing_for") or []
    for dep in deps:
        d = decisions.get(dep)
        if not dep.startswith("DR") or d is None:
            out.append(f"dependent {dep} is not a recorded decision")
            continue
        st, by = d.get("status"), d.get("ruled_by")
        carried = st == "carried" and (
            kit.carried_set_ok(d.get("set"))
            or (d.get("packet") or {}).get("class") == "C"
        )
        if not (carried or (st == "ruled" and by in ("operator", "packet-default"))):
            out.append(
                f"dependent {dep} is {st} by {by or '-'}; a filed premise needs dependents "
                "carried, or ruled by the operator or a packet default"
            )
    # skeptic correction: the closing event must have a live wave, so read the dependents' narrowing
    # and blocked waves, not only the filed owner wave
    waves = {"owner wave": [row.get("owner_wave")]}
    for dep in deps:
        d = decisions.get(dep) or {}
        npb = (d.get("set") or {}).get("narrowing_probe") or {}
        waves[f"{dep} narrowing wave"] = [npb.get("wave")]
        waves[f"{dep} blocks_waves"] = list(d.get("blocks_waves") or [])
    for what, ws in waves.items():
        gone = sorted(w for w in ws if w in descoped)
        if gone:
            out.append(f"{what} {', '.join(gone)} is descoped, so it never runs")
    if not kit.not_yet_waves(row, p, decisions):
        out.append(
            "no wave depends on it (the filing names no --blocks-wave and no dependent blocks "
            "one), so nothing re-checks it at build time"
        )
    return out


def not_yet_line(
    p: Dict[str, Any], row: Dict[str, Any], need: Any, records: Optional[Path] = None
) -> str:
    return (
        f"{p['id']}: at E{need[0]}, needs E{need[1]}; not yet true until {row.get('owner_wave')} "
        f"({row.get('awaits')}), owner {row.get('owner')}, due {kit.due_note(row.get('due'), records)}, "
        f"closing probe {row.get('closing_probe')}"
    )


@row(4, "Premises")
def row4(ctx: Ctx) -> Row:
    fails: List[str] = []
    filed: List[str] = []
    prem_events = ctx.jsonl("premises.jsonl")
    prem = kit.fold(prem_events)
    since = refuted_at(prem_events)
    pr = probes(ctx)
    events = ctx.jsonl("decisions.jsonl")
    decisions = kit.fold(events)
    nyt = kit.not_yet_rows(ctx.jsonl("residual.jsonl"))
    descoped = descoped_waves(ctx, decisions)
    now = kit.parse_iso(kit.now_iso())
    refuted = 0
    for p in prem.values():
        if p.get("verdict") == "unknown":
            fails.append(f"{p['id']}: verdict unknown")
        if (
            p.get("load_bearing_for")
            and p.get("verdict") != "refuted"
            and not kit.premise_at_level(p, pr)
        ):
            need = (
                kit.premise_level(p, pr),
                kit.REQUIRED_LEVEL.get(p.get("truth_lives_in", ""), "?"),
            )
            row_ = nyt.get(p["id"])
            why = (
                not_yet_problems(p, row_, decisions, descoped, now, ctx.records)
                if row_
                else ["not filed"]
            )
            if not why:
                filed.append(not_yet_line(p, row_, need, ctx.records))
            else:
                if row_:
                    fails += [f"{p['id']}: filed not-yet-true, but {w}" for w in why]
                fails.append(
                    f"{p['id']}: at E{need[0]}, needs E{need[1]} ({p.get('truth_lives_in')})"
                )
        if p.get("verdict") == "refuted":
            refuted += 1
            fails += [
                f"{p['id']} refuted but dependent {dep} was never revised"
                for dep in unrevised_dependents(p, events, since)
            ]
    rate = f"refutation rate {refuted}/{len(prem)}" if prem else "no premises recorded"
    notes = [rate] + ([f"{len(filed)} premise(s) filed not-yet-true"] if filed else [])
    return verdict(4, "Premises", fails, filed, notes)


# ── row 5 ───────────────────────────────────────────────────────────────────────────────────────


@row(5, "Decisions")
def row5(ctx: Ctx) -> Row:
    fails: List[str] = []
    filed: List[str] = []
    notes: List[str] = []
    prem = folded(ctx, "premises.jsonl")
    pr = probes(ctx)
    for d in folded(ctx, "decisions.jsonl").values():
        f, fi, n = decision_findings(d, prem, pr)
        fails += f
        filed += fi
        notes += n
    return verdict(5, "Decisions", fails, filed, notes)


def decision_findings(
    d: Dict[str, Any], prem: Dict[str, Dict[str, Any]], pr: Dict[str, Dict[str, Any]]
) -> Tuple[List[str], List[str], List[str]]:
    """Row 5's (fails, filed, notes) for one folded decision. `decision annotate` compares it before
    and after its event, so an annotation can never move this row."""
    fails: List[str] = []
    filed: List[str] = []
    notes: List[str] = []
    did = d.get("id")
    c = kit.conviction(d, prem, pr)
    if "conviction" in d and d["conviction"] is not None and d["conviction"] != c:
        fails.append(
            f"{did}: conviction typed, not computed ({d['conviction']} stored, {c} by the §3.5 rule)"
        )
    st, by = d.get("status"), d.get("ruled_by")
    pk = d.get("packet") or {}
    if d.get("reversibility") == "irreversible" and pk.get("class") == "B":
        fails.append(f"{did}: a class-B default sits on an irreversible decision")
    if d.get("reversibility") == "reversible" and st == "ruled":
        if int(d.get("runs_used") or 0) > kit.CAPS["reversible_runs"] or not d.get(
            "revisit_trigger"
        ):
            fails.append(
                f"{did}: reversible row used {d.get('runs_used')} runs or has no revisit trigger"
            )
    if st == "open":
        fails.append(f"{did}: open")
    elif st == "descoped":
        notes.append(f"{did}: descoped ({', '.join(d.get('descoped_waves') or [])})")
    elif st == "carried":
        s = d.get("set") or {}
        members = s.get("members") or []
        npb = s.get("narrowing_probe") or {}
        if pk.get("class") == "C" and pk.get("due"):
            filed.append(
                f"{did}: class C, due {pk['due']}, blocks {d.get('blocks_waves') or []}"
            )
        elif kit.carried_set_ok(s):
            filed.append(
                f"{did}: carried set of {len(members)}, narrows in {npb['wave']} by {npb['due']}"
            )
        else:
            fails.append(
                f"{did}: carried without a well-formed set or a dated class-C packet"
            )
    elif st == "ruled":
        if c is None and by != "operator":
            fails.append(
                f"{did}: rests on no factual premise, so it is a value call the operator rules"
            )
        elif by == "agent" and (c is None or c < 90):
            fails.append(f"{did}: agent-ruled at {c}%; the §3.5 rule needs 90")
        elif by in ("operator", "ladder") and not d.get("receipt"):
            fails.append(f"{did}: ruled by {by} with no receipt")
        elif by == "packet-default":
            notes.append(
                f"{did}: decided by default at {d.get('decided_by_default_at', c)}%"
            )
        elif by not in ("agent", "operator", "ladder", "packet-default"):
            fails.append(f"{did}: ruled_by {by!r}")
    else:
        fails.append(f"{did}: status {st!r}")
    return fails, filed, notes


# ── row 6 ───────────────────────────────────────────────────────────────────────────────────────


@row(6, "Instruments")
def row6(ctx: Ctx) -> Row:
    fails: List[str] = []
    notes: List[str] = []
    acc = (ctx.json("acceptance.json", {}) or {}).get("rows")
    if acc is None:
        return Row(6, "Instruments", FAIL, ["acceptance.json missing"])
    for r in acc:
        rid = r.get("id")
        if r.get("residual_label") == "build-validated residual":
            notes.append(f"{rid}: build-validated residual (stub-validated)")
            continue
        ctl = r.get("control") or {}
        if not ctl.get("known_bad") or not ctl.get("known_good"):
            fails.append(f"{rid}: no known-bad and known-good fixtures")
            continue
        bad, bad_out = run_cmd(
            r["check_cmd"],
            ctx.records,
            {"FIXTURE": str(ctx.records / ctl["known_bad"])},
        )
        good, good_out = run_cmd(
            r["check_cmd"],
            ctx.records,
            {"FIXTURE": str(ctx.records / ctl["known_good"])},
        )
        # A timeout is no verdict on either side: a known-bad run that never finished has not
        # shown the check can fail.
        if bad is None:
            fails.append(f"{rid}: on its known-bad fixture, {bad_out}")
        elif bad == 0:
            fails.append(f"{rid}: passes on its known-bad fixture, so it cannot fail")
        if good is None:
            fails.append(f"{rid}: on its known-good fixture, {good_out}")
        elif good != 0:
            fails.append(f"{rid}: fails on its known-good fixture (exit {good})")
        if r.get("timing") and (int(r.get("n") or 0) < 5 or not r.get("load_control")):
            fails.append(f"{rid}: timing row with n<5 or no load control")
    return verdict(6, "Instruments", fails, [], notes)


# ── row 7 ───────────────────────────────────────────────────────────────────────────────────────


@row(7, "Contact")
def row7(ctx: Ctx) -> Row:
    fails: List[str] = []
    pr = probes(ctx)
    doctors = [p for k, p in pr.items() if k.startswith("P-doctor-")]
    if not doctors:
        return Row(
            7, "Contact", FAIL, ["no environment doctor run (probe-run.sh doctor)"]
        )
    envs = max(doctors, key=lambda p: str(p.get("at"))).get("envs") or []
    crossed = {
        (p.get("env") or {}).get("id")
        for k, p in pr.items()
        if not k.startswith("P-doctor-")
    }
    for e in envs:
        if e not in crossed:
            fails.append(f"environment {e} never crossed by a probe")
    for comp in ctx.frame.get("components") or []:
        if isinstance(comp, dict) and comp.get("scheduled"):
            if not any(
                p.get("kind") == "skeleton"
                and (p.get("env") or {}).get("id") == "launchd-bash32"
                and p.get("exit") == 0
                for p in pr.values()
            ):
                fails.append(
                    f"{comp.get('name')}: scheduled, but no scheduler-started launchd run"
                )
    for k, p in pr.items():
        if p.get("kind") == "handed-cmd" and p.get("stdin") != "/dev/null":
            fails.append(f"{k}: handed command ran with keyboard input available")
        nc = p.get("negative_control") or {}
        if p.get("kind") == "measure" and not (
            nc.get("ran") or nc.get("reason_if_not_run")
        ):
            fails.append(f"{k}: measurement without a negative control or a reason")
    cm = ctx.json("contact_matrix.json")
    if cm is None:
        fails.append("contact_matrix.json missing")
    for r in (cm or {}).get("rows") or []:
        for cell, v in (r.get("cells") or {}).items():
            if not v.get("applies"):
                if not v.get("na_reason"):
                    fails.append(
                        f"{r.get('component')}/{cell}: not applicable without a reason"
                    )
                continue
            if not (v.get("probes") or v.get("decision") or v.get("residual")):
                fails.append(
                    f"{r.get('component')}/{cell}: applicable cell with no probe, set or residual"
                )
            props = v.get("properties")
            if props is not None and not any(
                re.search(r"liveness|eventually", str(x), re.I) for x in props
            ):
                fails.append(
                    f"{r.get('component')}/{cell}: property list has no liveness property"
                )
    return verdict(
        7, "Contact", fails, [], [f"{len(envs)} environment(s) from the doctor"]
    )


# ── row 8 ───────────────────────────────────────────────────────────────────────────────────────


def heading_slug(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")


def text_files(root: Path) -> List[Path]:
    out = []
    for p in root.rglob("*"):
        if (
            p.is_file()
            and p.suffix in (".md", ".json", ".jsonl", ".txt", ".sh", ".py")
            and "rounds" not in p.parts
        ):
            out.append(p)
    return out


# holes.jsonl is append-only and records what vendor reviewers, verifiers and raters wrote verbatim, so
# a scratch path a verifier SUGGESTED (truememory-2-0 H-3-008: a probe run on a copy under /tmp) could
# never be cleaned out. These fields are vendor text, not paths the program cites; the /tmp scan skips
# them and still reads every lead-written field (evidence lists, a split-off hole's claim, reasons).
HOLE_VENDOR_TEXT = {
    "verification": ("probe", "consequence", "read"),  # the courier verifier's verdict
    "materiality": ("note",),  # a rater's note
}
# a blind panel reviewer's or rehearsal session's raise (raised_by.blind): its claim, title, read
# receipt and locus.quote
HOLE_BLIND_RAISE_TEXT = ("claim", "title", "receipt")


def hole_lead_text(line: str) -> str:
    """One holes.jsonl line less its vendor-authored text (an unparseable line is scanned whole)."""
    try:
        d = json.loads(line)
    except ValueError:
        return line
    if not isinstance(d, dict):
        return line
    for k, fields in HOLE_VENDOR_TEXT.items():
        if isinstance(d.get(k), dict):
            d[k] = {f: v for f, v in d[k].items() if f not in fields}
    rb = d.get("raised_by")
    if d.get("event") == "raise" and isinstance(rb, dict) and rb.get("blind") is True:
        for f in HOLE_BLIND_RAISE_TEXT:
            d.pop(f, None)
        if isinstance(d.get("locus"), dict):
            d["locus"] = {f: v for f, v in d["locus"].items() if f != "quote"}
    return json.dumps(d)


# a relay trial row (evidence/rehearsal/trials-<n>.jsonl, practice.jsonl) records what the observed
# session said and ran, and `rehearse record` quotes it in rehearsal.jsonl's "trial <n>: ..." fails
# (truememory-2-0 trial 20: the session ran `ls -t /tmp/*handoff*` on its own). That is behavior under
# test, not a path the program cites; the prompt, cwd, transcript and every other field are still read.
TRIAL_OBSERVED_TEXT = ("reply", "replies", "tools")
TRIAL_FILE = re.compile(r"^(trials-\d+|practice)\.jsonl$")


def rehearsal_lead_text(ctx: Ctx, f: Path, line: str) -> str:
    """One relay-trial or rehearsal.jsonl line less the observed session's text (else the line whole)."""
    trial = f.parent == ctx.records / "evidence" / "rehearsal" and TRIAL_FILE.match(
        f.name
    )
    if not trial and f != ctx.path("rehearsal.jsonl"):
        return line
    try:
        d = json.loads(line)
    except ValueError:
        return line
    if not isinstance(d, dict):
        return line
    if trial:
        for k in TRIAL_OBSERVED_TEXT:
            d.pop(k, None)
    elif isinstance(d.get("fails"), list):
        d["fails"] = [x for x in d["fails"] if not re.match(r"^trial \S+: ", str(x))]
    return json.dumps(d)


@row(8, "Trace and persistence")
def row8(ctx: Ctx) -> Row:
    fails: List[str] = []
    trace = ctx.jsonl("trace.jsonl")
    ok_from = {
        t.get("from")
        for t in trace
        if t.get("to") or (t.get("type") == "rejects" and t.get("reason"))
    }
    for h in folded(ctx, "holes.jsonl"):
        if h not in ok_from:
            fails.append(f"finding {h} maps to no plan anchor or recorded rejection")
    for md in sorted(ctx.records.glob("*.md")):
        if md.name in ("FRAME.md", ctx.frame.get("plan")):
            continue
        for ln in md.read_text(errors="replace").splitlines():
            m = re.match(r"^#{1,6}\s+(.*)$", ln)
            if m and not any(
                str(f).endswith(f"{md.name}#{heading_slug(m.group(1))}")
                for f in ok_from
            ):
                fails.append(
                    f"{md.name}#{heading_slug(m.group(1))}: research heading never traced"
                )
    for f in text_files(ctx.records):
        text = f.read_text(errors="replace")
        if f == ctx.path("holes.jsonl"):
            text = "\n".join(hole_lead_text(ln) for ln in text.splitlines())
        else:
            text = "\n".join(
                rehearsal_lead_text(ctx, f, ln) for ln in text.splitlines()
            )
        if re.search(r"(?<![\w.])/(private/)?tmp/", text):
            fails.append(
                f"{f.relative_to(ctx.records)}: cites a path under /tmp (wiped on reboot)"
            )
    for k, p in probes(ctx).items():
        if p.get("raw") and not (ctx.records / p["raw"]).exists():
            fails.append(f"{k}: evidence path {p['raw']} missing")
    for rc in ctx.frame.get("private_receipts") or []:
        path = Path(os.path.expanduser(str(rc.get("path", ""))))
        m = re.match(r"^(\d+)-(\d+)$", str(rc.get("span", "")))
        if not path.is_file() or not m:
            fails.append(f"private receipt {rc.get('path')}: unreadable or no span")
            continue
        lines = path.read_text(errors="replace").splitlines()[
            int(m.group(1)) - 1 : int(m.group(2))
        ]
        if hashlib.sha256("\n".join(lines).encode()).hexdigest() != rc.get("sha256"):
            fails.append(
                f"private receipt {rc.get('path')}:{rc.get('span')}: the cited span changed"
            )
    if not (ctx.frame.get("topic_owner") or "").strip():
        fails.append("topic owner not confirmed")
    return verdict(8, "Trace and persistence", fails, [], [])


ROWS = [row1, row2, row3, row4, row5, row6, row7, row8]
