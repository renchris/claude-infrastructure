"""gate_rows_a.py — gate rows 1-8 of REPORT.md §3.10 (frame, censuses, sources, premises, decisions,
instruments, contact, trace and persistence).

Each predicate RE-EXECUTES what it names in this run (census methods, acceptance checks against their
known-bad and known-good fixtures, private-receipt hashes), and UNKNOWN FAILS: a missing or unreadable
record is a FAIL with its reason, never a pass. Conviction is recomputed by kit.conviction (§3.5),
never read from what an agent typed.
"""

from __future__ import annotations

import hashlib
import os
import re
import subprocess
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Set, Tuple

import kit
from gate import FAIL, FILED, PASS, Ctx, Row

SUPERLATIVE = re.compile(
    r"\b(perfect|100th|maximal|best|exhaustive|absolute|flawless)\b", re.I
)
FAC_IDS = [f"FAC-{i:02d}" for i in range(1, 34)]
TIMEOUT = 60


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


def run_cmd(
    cmd: str, cwd: Path, env: Optional[Dict[str, str]] = None
) -> Tuple[int, str]:
    try:
        p = subprocess.run(
            ["/bin/bash", "-c", cmd],
            cwd=str(cwd),
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
            timeout=TIMEOUT,
            env=dict(os.environ, **(env or {})),
        )
        return p.returncode, p.stdout
    except subprocess.TimeoutExpired:
        return 124, ""
    except OSError as e:
        return 127, str(e)


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
        newest = max(sigs, key=lambda r: r.get("at", 0))
        if newest["_verdict"] == operator_sign.VOID:
            fails.append("the newest frame signature is VOID: agent-written signature")
        elif newest["_verdict"] == operator_sign.STALE:
            fails.append(
                "the newest frame signature is STALE: frame.json changed since it was signed"
            )
        else:
            notes.append(
                f"frame pin {newest['pins'].get('frame.json', '?')[:12]} signed {newest.get('at_iso', '')}"
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
        for f in FAC_IDS
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
                    f"{pop}: method {m.get('agent', '?')} exited {rc} on re-run"
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


@row(4, "Premises")
def row4(ctx: Ctx) -> Row:
    fails: List[str] = []
    prem = folded(ctx, "premises.jsonl")
    pr = probes(ctx)
    events = ctx.jsonl("decisions.jsonl")
    refuted = 0
    for p in prem.values():
        if p.get("verdict") == "unknown":
            fails.append(f"{p['id']}: verdict unknown")
        if (
            p.get("load_bearing_for")
            and p.get("verdict") != "refuted"
            and not kit.premise_at_level(p, pr)
        ):
            fails.append(
                f"{p['id']}: at E{kit.premise_level(p, pr)}, needs "
                f"E{kit.REQUIRED_LEVEL.get(p.get('truth_lives_in', ''), '?')} ({p.get('truth_lives_in')})"
            )
        if p.get("verdict") == "refuted":
            refuted += 1
            for dep in p.get("load_bearing_for") or []:
                if not dep.startswith("DR"):
                    continue
                later = [
                    e
                    for e in events
                    if e.get("id") == dep
                    and str(e.get("ts", "")) >= str(p.get("ts", ""))
                    and e.get("status") in ("ruled", "reopened", "carried", "descoped")
                ]
                if not later:
                    fails.append(
                        f"{p['id']} refuted but dependent {dep} was never revised"
                    )
    rate = f"refutation rate {refuted}/{len(prem)}" if prem else "no premises recorded"
    return verdict(4, "Premises", fails, [], [rate])


# ── row 5 ───────────────────────────────────────────────────────────────────────────────────────


@row(5, "Decisions")
def row5(ctx: Ctx) -> Row:
    fails: List[str] = []
    filed: List[str] = []
    notes: List[str] = []
    prem = folded(ctx, "premises.jsonl")
    pr = probes(ctx)
    for d in folded(ctx, "decisions.jsonl").values():
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
            notes.append(
                f"{did}: descoped ({', '.join(d.get('descoped_waves') or [])})"
            )
        elif st == "carried":
            s = d.get("set") or {}
            members = s.get("members") or []
            npb = s.get("narrowing_probe") or {}
            if pk.get("class") == "C" and pk.get("due"):
                filed.append(
                    f"{did}: class C, due {pk['due']}, blocks {d.get('blocks_waves') or []}"
                )
            elif (
                2 <= len(members) <= 4
                and all(m.get("feasibility_probe") for m in members)
                and all(npb.get(k) for k in ("wave", "owner", "due"))
                and s.get("revision_budget_h")
            ):
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
    return verdict(5, "Decisions", fails, filed, notes)


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
        bad, _ = run_cmd(
            r["check_cmd"],
            ctx.records,
            {"FIXTURE": str(ctx.records / ctl["known_bad"])},
        )
        good, _ = run_cmd(
            r["check_cmd"],
            ctx.records,
            {"FIXTURE": str(ctx.records / ctl["known_good"])},
        )
        if bad == 0:
            fails.append(f"{rid}: passes on its known-bad fixture, so it cannot fail")
        if good != 0:
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
        if re.search(r"(?<![\w.])/(private/)?tmp/", f.read_text(errors="replace")):
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
