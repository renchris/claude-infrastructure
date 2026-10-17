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
import re
import subprocess
import sys
import time
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import kit
from gate import FILED, Ctx, Row, make_ctx

REPO = Path(__file__).resolve().parents[3]
# The causes triage writes for §5.2's counted buckets (cli_records.CAUSE). A parked row is a
# next-version idea, not a change to the certified answer, so it is not a material change.
COUNTED_CAUSES = ("escape", "frame_defect", "operator_unelicited", "reality_moved")
SCHEDULED_RESIDUAL = ("production-traffic", "elapsed-time", "not-yet-true")
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
    import activities
    import round as rnd

    # The re-freeze ends every front-end return: its edits are in the snapshot now pinned.
    for aid in activities.close_kind(a.program, activities.FRONT_END_RETURN):
        print(f"front-end return closed by the re-freeze: {aid}")
    if rnd.certification_due(a.program) is None:
        aid = activities.ensure_open(a.program, "certification-round")
        print(f"certification activity open: {aid} (tag CC_RESEARCH_ACTIVITY={aid})")
    return 0


# REPORT.md §6.1 says "well above the design point"; §10 row 16 (the 2026-10-04 audit) proposes 1.5x,
# which the calibration run measures. Assumed until then.
FER_FACTOR = 1.5
# REPORT.md §6.1 ceiling: "one front-end return per area (lite 1 x 1 day; standard and full 3 x 1.5 days)".
FER_AREAS = {"lite": 1, "standard": 3, "full": 3}
AREA_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")


def cmd_return_activity(a: Any) -> int:
    """Open (or name) one area's front-end-return activity (REPORT.md §6.1, §6.5). Refused unless the
    program is certifying and frozen, its newest certification round is closed and the next has not
    started, a counted round's n_hat is above FER_FACTOR x the design point, and the profile's area
    cap is not used up. The window check comes first, so a second call for an open area still
    prints its id only inside the window."""
    import activities
    import estimate
    import round as rnd

    slug = a.program
    state = (kit.registry_get(slug) or {}).get("state")
    if state != "certifying":
        raise kit.KitError(
            f"return-activity refused: {slug} is {state!r}, not certifying"
        )
    if not (kit.records_dir(slug) / "freeze.json").is_file():
        raise kit.KitError(f"return-activity refused: {slug} has no freeze.json")
    if not AREA_RE.match(a.area or ""):
        raise kit.KitError(f"return-activity refused: bad area name {a.area!r}")
    if not (a.because or "").strip():
        raise kit.KitError(
            "return-activity refused: --because names the recorded course and areas decisions"
        )
    done = rnd.all_matrices(slug, "certification")
    nxt = len(done) + 1
    if (
        not done
        or not done[-1].get("closed")
        or not any(m.get("counted") for m in done)
        or (rnd.rounds_dir(slug) / str(nxt)).exists()
    ):
        raise kit.KitError(
            "return-activity refused: a front-end return opens after a counted certification round "
            f"has closed and before the next one runs (§6.1); certification rounds: {len(done)}"
            + (
                f", round {nxt} already started"
                if done and done[-1].get("closed")
                else ""
            )
        )
    frame = make_ctx(slug).frame
    design = kit.profile(str(frame.get("profile") or ""))["design_holes"]
    n_hat = float(estimate.forecast(slug)["n_hat"])
    if n_hat <= FER_FACTOR * design:
        raise kit.KitError(
            f"return-activity refused: the estimate n_hat {n_hat:g} is not above {FER_FACTOR:g} x "
            f"the {frame.get('profile')} design point {design}"
        )
    aid, shut, _ = activities.open_return(
        slug,
        a.area,
        FER_AREAS[kit.round_profile(slug, frame)],
        {
            "n_hat": n_hat,
            "design_holes": design,
            "after_round": len(done),
            "opened_at": kit.now_iso(),
            "because": a.because,
        },
    )
    for x in shut:
        print(
            f"certification activity closed for the return: {x} (gate.sh freeze re-opens one)",
            file=sys.stderr,
        )
    print(aid)
    return 0


def cmd_cert_activity(a: Any) -> int:
    """Open, or name, the certification-round activity of a certifying, frozen program with a
    certification round due. Idempotent: a second call prints the same id. With no round due (the
    stop rule or R_max) but the last round still owing a settle step (round.py settle_owed), the
    activity opens settle-only instead: its tag runs that round's settle steps and no round."""
    import activities
    import round as rnd

    state = (kit.registry_get(a.program) or {}).get("state")
    if state != "certifying":
        raise kit.KitError(
            f"cert-activity refused: {a.program} is {state!r}, not certifying"
        )
    if not (kit.records_dir(a.program) / "freeze.json").is_file():
        raise kit.KitError(f"cert-activity refused: {a.program} has no freeze.json")
    why = rnd.certification_due(a.program)
    if why:
        # a front-end return edits the plan the last round reviewed: nothing settles under it
        rid, owed = (
            (None, [])
            if activities.open_ids(a.program, activities.FRONT_END_RETURN)
            else rnd.settle_owed(a.program)
        )
        if not owed:
            raise kit.KitError(
                f"cert-activity refused: no certification round is due: {why}"
                + (f"; round {rid} owes no settle step" if rid else "")
            )
        aid = activities.ensure_open(a.program, "certification-round", settle_round=rid)
        print(f"settle-only: round {rid} owes {', '.join(owed)}", file=sys.stderr)
        print(aid)
        return 0
    aid = activities.ensure_open(a.program, "certification-round")
    print(aid)
    return 0


def cmd_rehearsal_activity(a: Any) -> int:
    """Open, or name, the program's rehearsal activity (REPORT.md §3.8: "once, after the stop, before
    issue"). Refused unless the registry reads certifying, freeze.json exists, a certification round
    has run and closed, no certification round is due (the stop rule or R_max), that last round owes
    no settle step, no front-end return is open, and the relay test has neither passed nor used its
    one re-test. Idempotent: a second call prints the same id."""
    import activities
    import round as rnd

    slug = a.program
    state = (kit.registry_get(slug) or {}).get("state")
    if state != "certifying":
        raise kit.KitError(
            f"rehearsal-activity refused: {slug} is {state!r}, not certifying"
        )
    rec = kit.records_dir(slug)
    if not (rec / "freeze.json").is_file():
        raise kit.KitError(f"rehearsal-activity refused: {slug} has no freeze.json")
    done = rnd.all_matrices(slug, "certification")
    if not done or not done[-1].get("closed"):
        raise kit.KitError(
            "rehearsal-activity refused: the rehearsal runs after the stop, and "
            + (
                f"certification round {done[-1].get('round')} is not closed"
                if done
                else "no certification round has run"
            )
        )
    if rnd.certification_due(slug) is None:
        raise kit.KitError(
            f"rehearsal-activity refused: certification round {len(done) + 1} is still due; the "
            "rehearsal runs after the stop (the stop rule fired or R_max is spent)"
        )
    rid, owed = rnd.settle_owed(slug)
    if owed:
        raise kit.KitError(
            f"rehearsal-activity refused: round {rid} still owes {', '.join(owed)} "
            f"(gate.sh cert-activity --program {slug} opens its settle-only activity)"
        )
    if activities.open_ids(slug, activities.FRONT_END_RETURN):
        raise kit.KitError(
            "rehearsal-activity refused: a front-end return is open; the rehearsal reads the plan "
            "certification froze"
        )
    hist = kit.read_jsonl(rec / "rehearsal.jsonl")
    if any(h.get("passed") for h in hist):
        raise kit.KitError("rehearsal-activity refused: the relay test already passed")
    if len(hist) >= 2:
        raise kit.KitError(
            "rehearsal-activity refused: the relay test used its one repair and one re-test"
        )
    aid = activities.ensure_open(
        slug,
        activities.REHEARSAL,
        fields={"opened_at": kit.now_iso(), "attempt": len(hist) + 1},
    )
    print(
        f"rehearsal activity: tag CC_RESEARCH_ACTIVITY={aid} (cc-research rehearse, round.sh "
        f"rehearsal-*) and [activity:{aid}] (Agent and Workflow inputs)",
        file=sys.stderr,
    )
    print(aid)
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
    from gate_rows_b import lost_rounds, unstable_rounds

    certs = sorted((ctx.records / "cert").glob("CERT-v*.json"))
    n = len(certs) + 1
    f = estimate.forecast(ctx.slug)
    fz = ctx.json("freeze.json", {}) or {}
    issued = kit.now_iso()
    cert = {
        "cert": f"CERT-v{n}",
        "program": ctx.slug,
        "version": n,
        "profile": kit.round_profile(ctx.slug, ctx.frame),
        # a signed switch (cc-signoff research:<slug>/profile/<name>): {"to","from","after_round",…}
        "profile_switch": kit.profile_switch(ctx.slug),
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
        # §6.5: rounds whose rater agreement stayed low after their one re-pass
        "adjudication_unstable": unstable_rounds(ctx),
        "known_rows": [r for r in known_rows(ctx) if r.get("status", "open") == "open"],
        "state": summary(ctx, rows),
        "fingerprint": dict(
            fingerprint(), memory=memory_hash(ctx.frame.get("deliverable_repo"))
        ),
        # the change ids already on record, so a change after signoff is known even if undated
        "changes_at_issue": sorted(folded_changes(ctx.records)),
    }
    if kit.stage9_applies(
        ctx.slug, ctx.frame
    ):  # v1.3 §13.3: an adopted Stage 9 splits it too
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
            + [
                f"Row 15, stated condition: {c}"
                for c in (cert.get("conditions") or {}).values()
            ]
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
    gone = kit.superseded_residuals(
        res
    )  # a refiled filing is history, never a scheduled check
    res = [r for r in res if r.get("id") not in gone]
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
    # Method v1.3 (REPORT.md §13.2): a keyed due sorts by what it resolved to; one whose event has
    # not happened is pending and is counted, never compared as text with a date.
    # Method v1.3 (REPORT.md §13.6): a wait filed after the freeze is one the intake did not
    # front-load; the count is the front-loading's own measure.
    frozen = str((kit.read_json(rec / "freeze.json", {}) or {}).get("at") or "")
    import scheduled_read

    late = 0
    if frozen:
        late = sum(
            1
            for r in res
            if r.get("why_unreachable") == kit.NOT_YET
            and str(r.get("ts") or "") > frozen
        ) + sum(
            1
            for e in scheduled_read.events(rec)
            if e.get("event") == "filed" and str(e.get("ts") or "") > frozen
        )
    # (when, as printed): a date as filed, an event resolved
    due_at: List[Tuple[float, str]] = []
    pending = 0
    for r in sched:
        kind, t = kit.resolve_due(r["due"], rec)
        if t is not None:
            shown = (
                str(r["due"])
                if kind == "date"
                else time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(t))
            )
            due_at.append((t, shown))
        elif kind == "pending":
            pending += 1
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
        "filed_after_freeze": late,
        "not_yet": sum(1 for r in sched if r.get("why_unreachable") == kit.NOT_YET),
        "next_due": min(due_at)[1] if due_at else None,
        "due_pending": pending,
        "fresh_at": max(fresh, default=None),
        "flipped": sum(
            1
            for c in kit.fold(kit.read_jsonl(rec / "challenges.jsonl")).values()
            if c.get("kind") == "drift"
            and c.get("raised_by") == "sweep"
            # a flip triaged refuted was never observed (e.g. raised from a crashed re-check)
            and c.get("triage") != "refuted"
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
    sw = cert.get("profile_switch") or {}
    switched = (
        f" from round {sw['after_round'] + 1}, {sw['from']} through round {sw['after_round']}"
        if sw
        else ""
    )
    head = f"Research: {slug} version {cert['version']}. {state.upper()} {when} ({cert['profile']} profile{switched}; {why})"
    if cert.get("degraded") == "two vendors":
        head = "degraded: two vendors · " + head
    unstable = cert.get("adjudication_unstable") or []
    if unstable:
        head = (
            f"Adjudication unstable ({'round' if len(unstable) == 1 else 'rounds'} "
            f"{', '.join(unstable)}: rater agreement still low after the re-pass) · "
            + head
        )
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
    if all(
        k in fc for k in SPLIT_KEYS
    ):  # a v1.2 certificate (§11); a 1.1 one prints as before
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
        k, nyt = live["scheduled"], live.get("not_yet") or 0
        kinds = [
            f"{n} {what} {'check' if n == 1 else 'checks'}"
            for n, what in (
                (k - nyt, "production or elapsed-time"),
                (nyt, "filed not-yet-true premise"),
            )
            if n
        ]
        sched.append(
            f"{' and '.join(kinds)} with "
            f"{'owner and date' if k == 1 else 'owners and dates'} ("
            + "; ".join(
                x
                for x in (
                    f"next due {live['next_due']}" if live.get("next_due") else "",
                    f"{live['due_pending']} due when the wave or certificate they wait on starts"
                    if live.get("due_pending")
                    else "",
                )
                if x
            )
            + ")"
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
    if live.get("filed_after_freeze"):
        n = live["filed_after_freeze"]
        sched.append(
            f"{n} filed after the freeze ({'a wait' if n == 1 else 'waits'} the intake did not "
            "front-load, §13.6)"
        )
    if sched:
        out.append("Scheduled checks: " + " · ".join(sched))
    import scheduled_read  # method v1.3 (REPORT.md §13.1): row 15 filed as a scheduled read

    sr = scheduled_read.render_line(kit.records_dir(cert["program"]))
    if sr:
        out.append(sr)
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
    p = sub.add_parser(
        "cert-activity",
        help="open (or name) the certification-round activity of a certifying program",
        description="Print the id of the program's open certification-round activity, opening one "
        "if none is open. Refused unless the registry reads certifying, freeze.json exists and a "
        "certification round is due, or none is due but the last round still owes a settle step (its "
        "re-pass, an unheld clause-(g) hole, an unnamed cap-round find): then the activity is "
        "settle-only. Tag the round's calls with CC_RESEARCH_ACTIVITY=<id> "
        "(round.sh, courier.sh, read-only codex exec) and [activity:<id>] (Agent descriptions).",
    )
    p.add_argument("--program", required=True)
    p.set_defaults(fn=cmd_cert_activity)
    p = sub.add_parser(
        "return-activity",
        help="open (or name) one area's front-end-return activity (REPORT.md §6.1)",
        description="Print the id of the area's open front-end-return activity, opening one if "
        "none is open and closing the certification-round activity. Refused unless the registry "
        "reads certifying, freeze.json exists, the newest certification round is closed and the "
        "next has not started, the estimate is above 1.5 x the design point, the area has not "
        "already had its return and the profile's area cap (lite 1, standard and full 3) is not "
        "used up. gate.sh freeze closes it. Tag the area's calls with [activity:<id>] (Agent and "
        "Workflow inputs) and CC_RESEARCH_ACTIVITY=<id> (read-only codex exec); the lead fires the "
        "area's workers itself, because handoff-fire.sh stays denied under every activity tag.",
    )
    p.add_argument("--program", required=True)
    p.add_argument("--area", required=True)
    p.add_argument(
        "--because",
        required=True,
        help="the recorded course and areas decisions this return follows",
    )
    p.set_defaults(fn=cmd_return_activity)
    p = sub.add_parser(
        "rehearsal-activity",
        help="open (or name) the rehearsal activity once the stop has fired (REPORT.md §3.8)",
        description="Print the id of the program's open rehearsal activity, opening one if none is "
        "open. Refused unless the registry reads certifying, freeze.json exists, the last "
        "certification round is closed and none is due, it owes no settle step, no front-end return "
        "is open, and the relay test has neither passed nor used its re-test. Tag the rehearsal's "
        "calls with CC_RESEARCH_ACTIVITY=<id> (cc-research rehearse frames|trial|record, round.sh "
        "rehearsal-*, courier.sh --round rehearsal) and [activity:<id>] (the lens sessions' Agent "
        "and Workflow inputs). handoff-fire.sh stays denied: `rehearse trial` launches the trial "
        "panes. `rehearse record` closes it on a pass or a failed re-test.",
    )
    p.add_argument("--program", required=True)
    p.set_defaults(fn=cmd_rehearsal_activity)
    p = sub.add_parser("render")
    p.add_argument("--program", required=True)
    p.set_defaults(fn=cmd_render)
    import gate_delta

    gate_delta.add_verbs(sub)  # delta-activity (REPORT.md §5.4)
