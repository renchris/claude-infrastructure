"""gate_cert.py — freeze, the certificate and its state lines (REPORT.md §3.7 step 6, §3.10, §4.3).

gate.sh freeze --program P
    lint must show 0 errors; records the snapshot (the deliverable repo's HEAD, with the program's
    records clean) and the plan's blob; sets the registry to CERTIFYING (§10 item 1), so the
    research block and the Stop check are already on when the rehearsal's 20 relay trials run.
    Re-runnable while certifying, because each fix cycle between rounds yields a new snapshot.
gate.sh render --program P        (also `gate.sh --render --program P`)
    the certificate's state lines, the ONE read a completeness or pushback turn may make (§4.2).
    A pure read: it writes nothing and runs nothing, so it is fast and repeatable.
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
from gate import FILED, PASS, Ctx, Row, make_ctx


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
    }
    path = ctx.records / "cert" / f"CERT-v{n}.json"
    kit.write_json_atomic(path, cert)
    (ctx.records / "cert" / f"CERT-v{n}.md").write_text(
        "\n".join(lines_for(ctx.slug, cert, "certified")) + "\n"
    )
    return str(path)


def lines_for(slug: str, cert: Optional[Dict[str, Any]], state: str) -> List[str]:
    if not cert:
        return [f"Research: {slug} — {state}; not certified."]
    s, fc = cert["state"], cert["forecast"]
    when = time.strftime("%b %d", time.gmtime(kit.parse_iso(cert["issued"])))
    why = (
        f"stopped after {cert['quiet_streak']} quiet rounds"
        if cert["stop"] == "dry"
        else f"stopped at the round cap ({cert['rounds']} rounds)"
    )
    head = f"Research: {slug} version {cert['version']}. {state.upper()} {when} ({cert['profile']} profile; {why})"
    if cert.get("degraded") == "two vendors":
        head = "degraded: two vendors · " + head
    total = fc["desk_mean"] + fc["invisible_mean"]
    out = [
        head,
        f"Signed frame: 100.00% closed. {s['decisions']}/{s['decisions']} decisions · {s['populations']}/"
        f"{s['populations']} populations enumerated two ways · {s['checks']}/{s['checks']} checks shown to fail "
        f"first · {s['premises_at_level']}/{s['premises']} premises at required level · {s['sources']}/"
        f"{s['sources']} sources",
        f"After signoff: forecast about {total:.1f} material change(s); at most "
        f"{fc['desk_n95'] + fc['invisible_bound95']} at 95%, of which about {fc['invisible_mean']:.1f} is invisible "
        f"to any reviewer (share assumed) · take-backs 0",
        f"Decisions: {s['ruled_90']} ruled at 90%+ · {s['operator_ruled']} ruled by you · "
        f"{len(s['by_default'])} decided by default{' (' + '; '.join(s['by_default']) + ')' if s['by_default'] else ''}"
        f" · {len(s['carried'])} carried",
        f"Next version: {s['parked']} ideas parked · Frame defects {s['frame_defects']} · "
        f"Unasked intent {s['unasked_intent']}",
    ]
    if cert.get("known_rows"):
        out.append(
            "Known rows: "
            + " · ".join(
                f"{r['id']} (blocks {', '.join(r.get('blocks_waves') or []) or '-'})"
                for r in cert["known_rows"]
            )
        )
    fp = cert["fingerprint"]
    out += [
        "Calibration: no programs observed yet (uncalibrated)",
        f"Fingerprint: certified under {fp['model']}, rules {fp['rules']}, memory {fp['memory']} · "
        f"this answer unchanged since {cert['issued']}",
    ]
    return out


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
    if state != "certified" or not certs:
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
    print("\n".join(lines_for(a.program, kit.read_json(certs[-1]), state)))
    return 0


def add_verbs(sub: Any) -> None:
    p = sub.add_parser("freeze")
    p.add_argument("--program", required=True)
    p.set_defaults(fn=cmd_freeze)
    p = sub.add_parser("render")
    p.add_argument("--program", required=True)
    p.set_defaults(fn=cmd_render)
