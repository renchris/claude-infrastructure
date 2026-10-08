"""gate_cert.py — freeze, the certificate and its state lines (REPORT.md §3.7 step 6, §3.10, §4.3).

gate.sh freeze --program P
    lint must show 0 errors; records the snapshot (the deliverable repo's HEAD, with the program's
    records clean) and the plan's blob; sets the registry to CERTIFYING (§10 item 1), so the
    research block and the Stop check are already on when the rehearsal's 20 relay trials run.
    Re-runnable while certifying, because each fix cycle between rounds yields a new snapshot.
gate.sh render --program P        (also `gate.sh --render --program P`)
    the certificate's state lines, the ONE read a completeness or pushback turn may make (§4.2).
    A pure read: it writes nothing and runs nothing, so it is fast and repeatable. In a Stage 9
    build state (§11) it prints the same lines plus one "Built:" line read from built/.
(gate.sh run calls write_certificate once every row passes.)
"""

from __future__ import annotations

import hashlib
import os
import subprocess
import sys
import time
from pathlib import Path
from typing import Any, Dict, List, Optional

import kit
from gate import FILED, Ctx, Row, make_ctx

REPO = Path(__file__).resolve().parents[3]
# The causes triage writes for §5.2's counted buckets (cli_records.CAUSE). A parked row is a
# next-version idea, not a change to the certified answer, so it is not a material change.
COUNTED_CAUSES = ("escape", "frame_defect", "operator_unelicited", "reality_moved")
SCHEDULED_RESIDUAL = ("production-traffic", "elapsed-time")
# The §11 forecast split a v1.2 certificate carries (RECORDS.md "Stage 9 records", last bullet).
SPLIT_KEYS = (
    "build_findable_share",
    "before_impl_mean",
    "after_impl_mean",
    "after_impl_bound95",
)


def git(repo: str, *args: str) -> Optional[str]:
    p = subprocess.run(["git", "-C", repo, *args], capture_output=True, text=True)
    return p.stdout.strip() if p.returncode == 0 else None


def cmd_freeze(a: Any) -> int:
    import gate_rows_b
    import operator_sign

    ctx = make_ctx(a.program)
    prog = kit.registry_get(a.program) or {}
    if prog.get("state") not in ("registered", "certifying"):
        raise kit.KitError(f"cannot freeze a program in state {prog.get('state')!r}")
    errs = gate_rows_b.lint(ctx)
    if errs:
        for e in errs:
            print(f"lint: {e}", file=sys.stderr)
        raise kit.KitError(f"freeze refused: lint shows {len(errs)} error(s)")
    repo = ctx.frame.get("deliverable_repo")
    sha = git(repo, "rev-parse", "HEAD") if repo else None
    if not sha:
        raise kit.KitError(f"cannot read the snapshot sha of deliverable_repo {repo!r}")
    dirty = git(repo, "status", "--porcelain", "--", str(ctx.records))
    if dirty is None or dirty:
        raise kit.KitError(
            "the program's records are not committed; freeze pins a recorded sha"
        )
    plan = gate_rows_b.plan_text(ctx)
    rec = {
        "snapshot_sha": sha,
        "plan_blob": operator_sign.blob_sha(plan.encode()),
        "at": kit.now_iso(),
        "plan_lines": len(plan.splitlines()),
    }
    kit.write_json_atomic(ctx.records / "freeze.json", rec)
    kit.append_jsonl(ctx.records / "freezes.jsonl", dict(rec))
    kit.registry_set(a.program, "certifying")
    print(
        f"FROZEN {a.program} at {sha[:12]}; registry -> certifying (the research block is on from here)"
    )
    return 0


def fingerprint() -> Dict[str, str]:
    home = Path.home() / ".claude"
    h = hashlib.sha256()
    for f in [home / "CLAUDE.md"] + sorted((home / "rules").glob("*.md")):
        if f.is_file():
            h.update(f.read_bytes())
    return {
        "model": os.environ.get("CC_RESEARCH_MODEL") or "unrecorded",
        "rules": h.hexdigest()[:12],
    }


def memory_hash(repo: Optional[str]) -> str:
    if not repo:
        return "none"
    mangled = str(Path(repo).resolve()).replace("/", "-").replace(".", "-")
    for cfg in sorted(Path.home().glob(".claude*")):
        idx = cfg / "projects" / mangled / "memory" / "MEMORY.md"
        if idx.is_file():
            return hashlib.sha256(idx.read_bytes()).hexdigest()[:12]
    return "none"


def summary(ctx: Ctx, rows: List[Row]) -> Dict[str, Any]:
    from gate_rows_a import folded

    prem = folded(ctx, "premises.jsonl")
    pr = folded(ctx, "probes.jsonl")
    dec = folded(ctx, "decisions.jsonl")
    acc = (ctx.json("acceptance.json", {}) or {}).get("rows") or []
    ruled90 = [
        d
        for d in dec.values()
        if d.get("status") == "ruled" and d.get("ruled_by") == "agent"
    ]
    defaults = [
        f"{d['id']} at {d.get('decided_by_default_at')}%"
        for d in dec.values()
        if d.get("ruled_by") == "packet-default"
    ]
    carried = [d["id"] for d in dec.values() if d.get("status") == "carried"]
    lb = [p for p in prem.values() if p.get("load_bearing_for")]
    changes = list(folded(ctx, "changes.jsonl").values())
    return {
        "decisions": len(dec),
        "ruled_90": len(ruled90),
        "by_default": defaults,
        "carried": carried,
        "operator_ruled": sum(
            1 for d in dec.values() if d.get("ruled_by") in ("operator", "ladder")
        ),
        "populations": len(ctx.frame.get("populations") or []),
        "checks": len(acc),
        "premises": len(lb),
        "premises_at_level": sum(1 for p in lb if kit.premise_at_level(p, pr)),
        "sources": len(ctx.frame.get("sources_required") or []),
        "parked": sum(1 for c in changes if c.get("status") == "parked"),
        "frame_defects": sum(1 for c in changes if c.get("cause") == "frame_defect"),
        "unasked_intent": sum(
            1 for c in changes if c.get("cause") == "operator_unelicited"
        ),
        "filed_rows": [
            e
            for r in rows
            if r.status == FILED
            for e in r.evidence
            if e.startswith("FILED")
        ],
    }


def write_certificate(ctx: Ctx, rows: List[Row]) -> str:
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    import estimate
    from gate_rows_a import known_rows
    from gate_rows_b import lost_rounds

    certs = sorted((ctx.records / "cert").glob("CERT-v*.json"))
    n = len(certs) + 1
    f = estimate.forecast(ctx.slug)
    fz = ctx.json("freeze.json", {}) or {}
    issued = kit.now_iso()
    cert = {
        "cert": f"CERT-v{n}",
        "program": ctx.slug,
        "version": n,
        "profile": ctx.frame.get("profile"),
        "snapshot_sha": fz.get("snapshot_sha"),
        "issued": issued,
        "stop": f["stop"],
        "rounds": f["rounds_counted"],
        "r_max": f["r_max"],
        "quiet_streak": f["quiet_streak"],
        "lost_rounds": lost_rounds(
            ctx
        ),  # stated apart from the counted rounds (gate row 17)
        "rows": {str(r.num): r.status for r in rows},
        "forecast": {
            k: f[k]
            for k in (
                "desk_mean",
                "desk_n95",
                "invisible_mean",
                "invisible_bound95",
                "p_any",
            )
        },
        "assumed": f["assumed"],
        "calibrated": False,
        "degraded": ctx.frame.get("degraded"),
        "known_rows": [r for r in known_rows(ctx) if r.get("status", "open") == "open"],
        "state": summary(ctx, rows),
        "fingerprint": dict(
            fingerprint(), memory=memory_hash(ctx.frame.get("deliverable_repo"))
        ),
        # the change ids already on record, so a change after signoff is known even if undated
        "changes_at_issue": sorted(folded_changes(ctx.records)),
    }
    if kit.is_v12(ctx.frame):
        cert["forecast"].update(impl_split(cert["forecast"]))
    # Wave E1l (ruling 17aff7158fa6 item 4): row 15 was measured under the load bound, a stated
    # condition of the certificate, with RULE E1k's real-load figures beside it.
    cond = [
        e
        for r in rows
        if r.num == 15
        for e in r.evidence
        if e.startswith("load bound (ruling 17aff7158fa6)")
    ]
    if cond:
        cert["conditions"] = {"15": cond[0]}
    path = ctx.records / "cert" / f"CERT-v{n}.json"
    kit.write_json_atomic(path, cert)
    # the .md keeps the issue-time snapshot; `gate.sh render` re-reads the records every time
    (ctx.records / "cert" / f"CERT-v{n}.md").write_text(
        "\n".join(
            lines_for(ctx.slug, cert, "certified", live_state(ctx.records, cert))
            + [f"Row 15, stated condition: {c}" for c in (cert.get("conditions") or {}).values()]
        )
        + "\n"
    )
    return str(path)


def impl_split(fc: Dict[str, Any]) -> Dict[str, Any]:
    """§11: the §3.12 mean split by the assumed build-findable share. The 95% bound is NOT split,
    because an assumed share may not tighten a bound."""
    share = kit.BUILD_FINDABLE_SHARE
    total = fc["desk_mean"] + fc["invisible_mean"]
    return {
        "build_findable_share": share,
        "before_impl_mean": round(share * total, 4),
        "after_impl_mean": round((1 - share) * total, 4),
        "after_impl_bound95": fc["desk_n95"] + fc["invisible_bound95"],
    }


def folded_changes(rec: Path) -> Dict[str, Dict[str, Any]]:
    return kit.fold(kit.read_jsonl(rec / "changes.jsonl"))


def calibration_store() -> Path:
    env = os.environ.get("CC_RESEARCH_CALIBRATION")
    return (
        Path(env) if env else REPO / "docs" / "research" / "research-calibration.jsonl"
    )


def live_state(rec: Path, cert: Dict[str, Any]) -> Dict[str, Any]:
    """What the records say now (§4.3, §4.4): changes after signoff, residuals, scheduled checks,
    calibration. Read at every render, so an escape triaged after the issue moves the answer."""
    issued = kit.parse_iso(cert["issued"])
    at_issue = cert.get("changes_at_issue")

    def after(c: Dict[str, Any]) -> bool:
        if at_issue is not None:
            return c.get("id") not in at_issue
        return bool(c.get("ts")) and kit.parse_iso(c["ts"]) > issued

    changes = [
        c
        for c in folded_changes(rec).values()
        if c.get("cause") in COUNTED_CAUSES and c.get("status") != "parked" and after(c)
    ]
    res = list(kit.fold(kit.read_jsonl(rec / "residual.jsonl")).values())
    classes: Dict[str, int] = {}
    for r in res:
        why = str(r.get("why_unreachable"))
        classes[why] = classes.get(why, 0) + 1
    sched = [
        r
        for r in res
        if r.get("why_unreachable") in SCHEDULED_RESIDUAL
        and (r.get("owner") or r.get("owner_wave"))
        and r.get("due")
    ]
    fresh = [
        str(p["at"])
        for p in kit.fold(kit.read_jsonl(rec / "probes.jsonl")).values()
        if str(p.get("id", "")).startswith("P-fresh-") and p.get("at")
    ]
    cal = calibration_store()
    return {
        "after": len(changes),
        "escapes": sum(1 for c in changes if c.get("cause") == "escape"),
        "last_change": max(
            (str(c["ts"]) for c in changes if c.get("ts")), default=None
        ),
        "residual": classes,
        "scheduled": len(sched),
        "next_due": min((str(r["due"]) for r in sched), default=None),
        "fresh_at": max(fresh, default=None),
        "flipped": sum(
            1
            for c in kit.fold(kit.read_jsonl(rec / "challenges.jsonl")).values()
            if c.get("kind") == "drift" and c.get("raised_by") == "sweep"
        ),
        "calibration": len(kit.read_jsonl(cal)) if cal.is_file() else 0,
    }


def plural(n: int, word: str) -> str:
    return f"{n} {word}{'' if n == 1 else 's'}"


def lines_for(
    slug: str, cert: Optional[Dict[str, Any]], state: str, live: Dict[str, Any]
) -> List[str]:
    if not cert:
        return [f"Research: {slug} — {state}; not certified."]
    s, fc = cert["state"], cert["forecast"]
    when = time.strftime("%b %d", time.gmtime(kit.parse_iso(cert["issued"])))
    why = (
        f"stopped after {cert['quiet_streak']} quiet rounds"
        if cert["stop"] == "dry"
        else f"stopped at the round cap ({cert['rounds']} rounds)"
    )
    lost = cert.get("lost_rounds") or []
    if lost:
        why += (
            f"; {plural(len(lost), 'round')} lost to a dead lane and not counted "
            f"({'round' if len(lost) == 1 else 'rounds'} {', '.join(lost)})"
        )
    head = f"Research: {slug} version {cert['version']}. {state.upper()} {when} ({cert['profile']} profile; {why})"
    if cert.get("degraded") == "two vendors":
        head = "degraded: two vendors · " + head
    total = fc["desk_mean"] + fc["invisible_mean"]
    bound = fc["desk_n95"] + fc["invisible_bound95"]
    n = live["after"]
    # §5.3 step 5: past the summed 95% bounds at least one stratum is past its own, a take-back for
    # certain; below it the desk/invisible split needs the blind replay, so no take-back count prints.
    over = (
        f" · {n} exceed the 95% bound of {bound}: a take-back (§5.3)"
        if n > bound
        else ""
    )
    out = [
        head,
        f"Signed frame: 100.00% closed. {s['decisions']}/{s['decisions']} decisions · {s['populations']}/"
        f"{s['populations']} populations enumerated two ways · {s['checks']}/{s['checks']} checks shown to fail "
        f"first · {s['premises_at_level']}/{s['premises']} premises at required level · {s['sources']}/"
        f"{s['sources']} sources",
        f"After signoff: {plural(n, 'material change')} ({plural(live['escapes'], 'escape')}; forecast about "
        f"{total:.1f}; at most {bound} at 95%, of which about {fc['invisible_mean']:.1f} is invisible to any "
        f"reviewer, share assumed){over}",
        f"Decisions: {s['ruled_90']} ruled at 90%+ · {s['operator_ruled']} ruled by you · "
        f"{len(s['by_default'])} decided by default{' (' + '; '.join(s['by_default']) + ')' if s['by_default'] else ''}"
        f" · {len(s['carried'])} carried",
        f"Next version: {s['parked']} ideas parked · Frame defects {s['frame_defects']} · "
        f"Unasked intent {s['unasked_intent']}",
    ]
    if all(k in fc for k in SPLIT_KEYS):  # a v1.2 certificate (§11); a 1.1 one prints as before
        out.insert(
            3,
            f"Split: before implementation signoff about {fc['before_impl_mean']:.1f} · after "
            f"implementation signoff about {fc['after_impl_mean']:.1f} (at most "
            f"{fc['after_impl_bound95']} at 95%); build-findable share {fc['build_findable_share']}, "
            "share assumed",
        )
    if cert.get("known_rows"):
        out.append(
            "Known rows: "
            + " · ".join(
                f"{r['id']} (blocks {', '.join(r.get('blocks_waves') or []) or '-'})"
                for r in cert["known_rows"]
            )
        )
    if live["residual"]:
        out.append(
            f"Residuals: {sum(live['residual'].values())} declared ("
            + ", ".join(f"{k} {v}" for k, v in sorted(live["residual"].items()))
            + ")"
        )
    sched: List[str] = []
    if live["scheduled"]:
        k = live["scheduled"]
        sched.append(
            f"{k} production or elapsed-time {'check' if k == 1 else 'checks'} with "
            f"{'owner and date' if k == 1 else 'owners and dates'} (next due {live['next_due']})"
        )
    if live["fresh_at"]:
        when = time.strftime(
            "%b %d %H:%M", time.gmtime(kit.parse_iso(live["fresh_at"]))
        )
        f = live["flipped"]
        sched.append(
            f"last freshness run {when}, "
            + ("no verdict changed" if not f else f"{plural(f, 'verdict')} changed")
        )
    if sched:
        out.append("Scheduled checks: " + " · ".join(sched))
    cal = live["calibration"]
    fp = cert["fingerprint"]
    out += [
        # no record of build or live state exists in the kit: unknown, never 0
        "Built – · Live – · Calibration: "
        + (
            f"{plural(cal, 'plan')} measured" if cal else "none measured (uncalibrated)"
        ),
        f"Fingerprint: certified under {fp['model']}, rules {fp['rules']}, memory {fp['memory']} · "
        + (
            f"this answer unchanged since {cert['issued']}"
            if not n
            else f"changed after signoff, last {live['last_change'] or 'undated'}"
        ),
    ]
    return out


def built_line(slug: str, rec: Path, state: str) -> str:
    """§11: the built stage's one state line, read from built/ at every render."""
    certs = sorted(
        (rec / "built").glob("BUILT-CERT-v*.json"),
        key=lambda p: int("".join(c for c in p.stem if c.isdigit()) or 0),
    )
    bc = (kit.read_json(certs[-1], {}) or {}) if certs else {}
    if state in ("build-certified", kit.IMPL_SIGNED) and bc:
        import operator_sign

        # the signature is read from the sealed log at every render, never from the registry state
        return (
            f"Built: certified {bc.get('issued')} (BUILT-CERT-v{bc.get('version')})"
            f" · implementation {operator_sign.implementation_words(slug)}"
        )
    fz = kit.read_json(rec / "built" / "freeze.json", {}) or {}
    return f"Built: frozen {fz.get('frozen_at') or 'at an unrecorded time'}, not yet certified"


def cmd_render(a: Any) -> int:
    kit.check_slug(a.program)
    prog = kit.registry_get(a.program)
    state = (prog or {}).get("state", "unregistered")
    rec = (
        kit.records_dir(a.program)
        if prog or os.environ.get("CC_RESEARCH_RECORDS")
        else None
    )
    certs = (
        sorted(
            (rec / "cert").glob("CERT-v*.json"),
            key=lambda p: int("".join(c for c in p.stem if c.isdigit()) or 0),
        )
        if rec
        else []
    )
    if state not in ("certified",) + kit.STAGE9_STATES or not certs:
        mats = (
            [kit.read_json(p) for p in (rec / "rounds").glob("*/matrix.json")]
            if rec
            else []
        )
        counted = [
            m
            for m in mats
            if m and m.get("kind") == "certification" and m.get("counted")
        ]
        quiet = 0
        for m in sorted(counted, key=lambda m: int(m.get("seq") or 0), reverse=True):
            if not m.get("quiet"):
                break
            quiet += 1
        print(
            f"Research: {a.program} — {state}; not certified. Certification rounds counted: {len(counted)}; "
            f"trailing quiet rounds: {quiet}."
        )
        return 0
    cert = kit.read_json(certs[-1])
    out = lines_for(a.program, cert, "certified", live_state(rec, cert))
    if state in kit.STAGE9_STATES:
        # the research lines' "Built –" means "no build record"; in Stage 9 there is one, below
        out = [ln.replace("Built – · Live – · ", "Live – · ", 1) for ln in out]
        out.append(built_line(a.program, rec, state))
    print("\n".join(out))
    return 0


def add_verbs(sub: Any) -> None:
    p = sub.add_parser("freeze")
    p.add_argument("--program", required=True)
    p.set_defaults(fn=cmd_freeze)
    p = sub.add_parser("render")
    p.add_argument("--program", required=True)
    p.set_defaults(fn=cmd_render)
