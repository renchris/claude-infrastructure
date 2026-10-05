"""cli_core.py — the state verbs of bin/cc-research (REPORT.md §8 item 9, state half; §10 item 17).

index frame estimate gate      pass-throughs to research-index.py, intake.py, estimate.py simulate
                               and lib/gate.py, each a subprocess so its own sys.path holds; the
                               exit code is preserved
forecast · freeze              estimate.forecast as JSON · gate_cert freeze
trace · reconcile · lint       exactly ONE gate check each: row 8, row 12, the plan lint
verdict [--program] P          the gate render's state lines, then the operator block: pending
                               concerns, "waiting on you since", the priced menu. A pure read:
                               it writes nothing, runs no vendor and no gate run (router cert_read)
menu                           §6.4's priced purchases; prints the operator's commands, runs none
pending --json                 every registry program not closed; one unreadable program reads
                               state "unknown" and never crashes the list
budget [start|end --stage N]   budget.json; caps enforced in code (§10 item 17) through row 16
ceiling                        §6.1 totals as printed, elapsed days, the operator's wait (§5.6)
reopen                         operator-only; with a valid reopen signature, re-runs the gate
"""

from __future__ import annotations

import argparse
import contextlib
import io
import json
import re
import subprocess
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional

import kit

LIB = Path(__file__).resolve().parent
KIT = LIB.parent
DAY = 86400.0
NO_LOWER = "no further desk review can lower this; only contact or building can"
PASS_THROUGH = {
    "index": (KIT / "research-index.py", []),
    "frame": (KIT / "intake.py", []),
    "estimate": (KIT / "estimate.py", ["simulate"]),
    "gate": (LIB / "gate.py", []),
}


def ctx_for(slug: str) -> Any:
    import gate

    return gate.make_ctx(slug)


def signoff_cmd(slug: str, action: str) -> str:
    return f"cc-signoff research:{slug}/{action}"


# ── pass-throughs, forecast, freeze ───────────────────────────────────────────────────────────────


def cmd_pass(a: argparse.Namespace) -> int:
    script, pre = PASS_THROUGH[a.verb]
    return subprocess.run(
        ["/usr/bin/env", "python3", str(script), *pre, *a.rest]
    ).returncode


def cmd_forecast(a: argparse.Namespace) -> int:
    import estimate

    kit.check_slug(a.program)
    print(json.dumps(estimate.forecast(a.program), sort_keys=True))
    return 0


def cmd_freeze(a: argparse.Namespace) -> int:
    import gate_cert

    return int(gate_cert.cmd_freeze(argparse.Namespace(program=a.program)))


# ── one gate check ────────────────────────────────────────────────────────────────────────────────


def report_check(name: str, fails: List[str], notes: List[str]) -> int:
    print(f"{'FAIL' if fails else 'PASS'} {name}")
    for e in fails + notes:
        print(f"  {e}")
    return 1 if fails else 0


def run_row(name: str, fn: Callable[[Any], Any], slug: str) -> int:
    """One gate row, judged as gate.run_rows judges it: a row that raises is a FAIL."""
    import gate

    ctx = ctx_for(slug)
    try:
        r = fn(ctx)
    except Exception as e:  # unknown fails (§3.10), never a pass
        return report_check(name, [f"row raised {type(e).__name__}: {e}"], [])
    failed = r.status not in (gate.PASS, gate.FILED)
    return report_check(
        name, r.evidence if failed else [], [] if failed else r.evidence
    )


def cmd_trace(a: argparse.Namespace) -> int:
    import gate_rows_a

    return run_row("trace", gate_rows_a.row8, a.program)


def cmd_reconcile(a: argparse.Namespace) -> int:
    import gate_rows_b

    return run_row("reconcile", gate_rows_b.row12, a.program)


def cmd_lint(a: argparse.Namespace) -> int:
    import gate_rows_b

    return report_check("lint", gate_rows_b.lint(ctx_for(a.program)), [])


# ── the operator block: concerns, the wait, the menu ──────────────────────────────────────────────


def render_lines(slug: str) -> List[str]:
    """The exact lines `gate.sh render` prints, through its own code path."""
    import gate_cert

    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        gate_cert.cmd_render(argparse.Namespace(program=slug))
    return buf.getvalue().splitlines()


def pending_concerns(ctx: Any) -> int:
    return sum(
        1
        for c in kit.fold(ctx.jsonl("challenges.jsonl")).values()
        if c.get("triage") == "pending"
    )


def waiting_since(ctx: Any) -> Optional[str]:
    """The oldest OPEN program packet's created date; None if none is open; "unknown" if
    cc-decide cannot be read (a wait is never dropped silently, §5.6)."""
    import gate_sweep

    refs = gate_sweep.program_packets(ctx, kit.fold(ctx.jsonl("decisions.jsonl")))
    if not refs:
        return None
    try:
        allp = gate_sweep.packets()
    except (kit.KitError, ValueError, KeyError, TypeError, OSError):
        return "unknown"
    opened = [
        p
        for pid, p in allp.items()
        if pid in refs and (p.get("status") or "open") == "open"
    ]
    if any(not p.get("created") for p in opened):
        return "unknown"
    return min(str(p["created"]) for p in opened) if opened else None


def seeds_all_caught(slug: str) -> bool:
    """seed.py status shows seeds planted and none left uncaught. Unreadable reads as False, so
    the menu never claims a zero it could not see."""
    import seed

    if not seed.vault_path(slug).exists():
        return False
    try:
        counts = seed.counts(seed.load_vault(slug)[0])
    except Exception:  # a vault that cannot be read proves nothing
        return False
    return (
        sum(c["s_eff"] for c in counts.values()) > 0
        and sum(c["k_left"] for c in counts.values()) == 0
    )


def extension_items(slug: str) -> List[Dict[str, str]]:
    """§12.3 (method v1.2): one priced research extension per decision below 90 that research
    can still move, while unbought. Quoted as a change to that decision's conviction."""
    import blockers

    ctx = ctx_for(slug)
    if not kit.is_v12(ctx.frame):
        return []
    items: List[Dict[str, str]] = []
    for d in kit.fold(ctx.jsonl("decisions.jsonl")).values():
        if d.get("status") == "descoped":
            continue
        t = blockers.tag(ctx, d)
        if t["tag"] != "research" or t["extended"]:
            continue
        box = d.get("timebox_days")
        items.append(
            {
                "id": f"extend-decision/{d.get('id')}",
                "label": f"one research extension on decision {d.get('id')} "
                f"({kit.CAPS['decision_extensions']} per decision)",
                "price": f"{float(box):g} research days on this decision (one more intake timebox)"
                if box
                else "one more intake timebox on this decision (its timebox is not on record)",
                "effect": f"conviction now {t['conviction']}%; still below level: "
                f"{', '.join(t['gaps'])}; research can raise it to at most {t['reachable_max']}%",
            }
        )
    return items


def menu(slug: str) -> List[Dict[str, str]]:
    """§6.4: the extra round set (once per program, quoted as its change to the printed bound,
    never as a yield) while unbought, and the reopen."""
    import gate_rows_b
    from round import extra_round_granted

    items: List[Dict[str, str]] = []
    if not extra_round_granted(slug):
        ctx = ctx_for(slug)
        prof = kit.profile(ctx.frame.get("profile") or "")
        certs = gate_rows_b.cert_rounds(ctx)
        p90 = (certs[0].get("forecast") or {}).get("p90") if certs else None
        now, after = (
            kit.r_max(prof["name"], p90, False),
            kit.r_max(prof["name"], p90, True),
        )
        items.append(
            {
                "id": "extra-round",
                "label": f"the one extra round set ({kit.CAPS['extra_round_sets']} per program)",
                "price": f"{after - now} certification round ({prof['reviewers_per_round']} reviewer reads)",
                "effect": NO_LOWER
                if seeds_all_caught(slug)
                else (
                    f"raises the round cap from {now} to {after}; the printed bound moves only by "
                    "what that round finds"
                ),
            }
        )
    items += extension_items(slug)
    items.append(
        {
            "id": "reopen",
            "label": "reopen certified scope (operator-caused)",
            "price": "a new certificate version",
            "effect": "the registry returns to registered and the gate re-runs over the records",
        }
    )
    return items


def menu_lines(slug: str, items: List[Dict[str, str]]) -> List[str]:
    out = [
        "Menu (the operator runs these in their own terminal; nothing here runs them):"
    ]
    for m in items:
        out += [
            f"  {m['id']}: {m['label']} · price {m['price']} · {m['effect']}",
            f"    {signoff_cmd(slug, m['id'])}",
        ]
    return out


def verdict_data(slug: str, with_lines: bool = True) -> Dict[str, Any]:
    import os

    kit.check_slug(slug)
    prog = kit.registry_get(slug)
    out: Dict[str, Any] = {
        "program": slug,
        "state": (prog or {}).get("state", "unregistered"),
    }
    if with_lines:
        out["lines"] = render_lines(slug)
    if prog is None and not os.environ.get("CC_RESEARCH_RECORDS"):
        out.update(pending_concerns=0, waiting_since=None, menu=[])
        return out
    ctx = ctx_for(slug)
    out["pending_concerns"] = pending_concerns(ctx)
    out["waiting_since"] = waiting_since(ctx)
    out["menu"] = menu(slug)
    return out


def cmd_verdict(a: argparse.Namespace) -> int:
    slug = a.program or a.slug
    if not slug or (a.program and a.slug and a.program != a.slug):
        raise kit.KitError(
            "verdict takes one program: cc-research verdict [--program] <slug>"
        )
    d = verdict_data(slug)
    if a.json:
        print(json.dumps(d, indent=2))
        return 0
    ws = d["waiting_since"]
    print(
        "\n".join(
            d["lines"]
            + [
                f"Pending concerns: {d['pending_concerns']}",
                f"Waiting on you since {ws}"
                if ws
                else "Waiting on you since: nothing open",
            ]
            + menu_lines(slug, d["menu"])
        )
    )
    return 0


def cmd_menu(a: argparse.Namespace) -> int:
    kit.check_slug(a.program)
    items = menu(a.program)
    print(
        json.dumps(items, indent=2)
        if a.json
        else "\n".join(menu_lines(a.program, items))
    )
    return 0


def cmd_pending(a: argparse.Namespace) -> int:
    out: List[Dict[str, Any]] = []
    for p in kit.registry_load()["programs"]:
        if p.get("state") == "closed":
            continue
        try:
            out.append(verdict_data(str(p.get("slug")), with_lines=False))
        except Exception as e:  # one unreadable program never hides the others
            out.append(
                {
                    "program": p.get("slug"),
                    "state": "unknown",
                    "pending_concerns": None,
                    "waiting_since": None,
                    "menu": [],
                    "error": f"{type(e).__name__}: {e}",
                }
            )
    if a.json:
        print(json.dumps({"programs": out}, indent=2))
    else:
        for d in out:
            print(
                f"{d['program']}: {d['state']} · pending concerns {d['pending_concerns']} · "
                f"waiting on you since {d['waiting_since'] or 'nothing open'}"
            )
    return 0


# ── budget and ceiling (§10 item 17: caps enforced in code) ──────────────────────────────────────


def load_budget(ctx: Any) -> Dict[str, Any]:
    b = ctx.json("budget.json") or {}
    b.setdefault("stages", {})
    b.setdefault("overrun_packets", {})
    return b


def unpacketed_overruns(ctx: Any) -> Dict[str, str]:
    """stage -> row 16's evidence line, for every stage over its cap with no overrun packet."""
    import gate_rows_b

    out: Dict[str, str] = {}
    for e in gate_rows_b.row16(ctx).evidence:
        m = re.match(r"^stage (\S+): .* and no overrun packet$", e)
        if m:
            out[m.group(1)] = e
    return out


def budget_report(ctx: Any) -> Dict[str, Any]:
    b = load_budget(ctx)
    prof = kit.profile(ctx.frame.get("profile") or "")
    now = kit.parse_iso(kit.now_iso())
    over = unpacketed_overruns(ctx)
    stages: Dict[str, Any] = {}
    for n in sorted({int(s) for s in b["stages"]} | set(prof["stage_days"])):
        v = b["stages"].get(str(n)) or {}
        end = kit.parse_iso(v["ended"]) if v.get("ended") else now
        days = (
            round((end - kit.parse_iso(v["started"])) / DAY, 2)
            if v.get("started")
            else 0.0
        )
        bud = prof["stage_days"].get(n, 0)
        stages[str(n)] = {
            "started": v.get("started"),
            "ended": v.get("ended"),
            "days": days,
            "budget_days": bud,
            "cap_days": bud * kit.CAPS["overrun_factor"],
            "overrun_packet": b["overrun_packets"].get(str(n)),
            "over_without_packet": str(n) in over,
        }
    return {
        "program": ctx.slug,
        "profile": prof["name"],
        "stages": stages,
        "over_without_packet": sorted(over, key=int),
    }


def yield_stop_for(ctx: Any, stage: int) -> Dict[str, Any]:
    """§12.1 (method v1.2): stages 3 and 5 end on yield. Refuses while the rule says continue;
    otherwise the {"stop": …} record to store with the end. Empty for any other stage or frame."""
    import yield_stop

    if stage not in kit.YIELD_STAGES or not kit.is_v12(ctx.frame):
        return {}
    v = yield_stop.evaluate(ctx, stage, as_of=kit.now_iso())
    if v["verdict"] == "continue":
        raise kit.KitError(
            f"stage {stage} cannot end yet — {yield_stop.describe(v)}. It ends when the last "
            f"{v['k']} probes are quiet and that product is at most 1, or at the ceiling (§12.1)"
        )
    return {"stop": yield_stop.stop_record(v)}


def cmd_budget(a: argparse.Namespace) -> int:
    ctx = ctx_for(a.program)
    if not a.action:
        rep = budget_report(ctx)
        if a.json:
            print(json.dumps(rep, indent=2))
        else:
            for st, v in rep["stages"].items():
                flag = " OVER, no overrun packet" if v["over_without_packet"] else ""
                print(
                    f"stage {st}: {v['days']:g} d used of {v['budget_days']:g} d budget "
                    f"(cap {v['cap_days']:g} d){flag}"
                )
        return 1 if rep["over_without_packet"] else 0
    prof = kit.profile(ctx.frame.get("profile") or "")
    if a.stage is None or a.stage not in prof["stage_days"]:
        raise kit.KitError(
            f"budget {a.action} needs --stage N, one of {sorted(prof['stage_days'])}"
        )
    b = load_budget(ctx)
    st = str(a.stage)
    cur = b["stages"].get(st) or {}
    if a.action == "start":
        if cur.get("started"):
            raise kit.KitError(f"stage {st} already started at {cur['started']}")
        over = unpacketed_overruns(ctx).get(str(a.stage - 1))
        if over:
            raise kit.KitError(
                f"stage {st} cannot start while {over}; the overrun needs its "
                "class-B packet recorded in budget.json overrun_packets (§6.5)"
            )
        b["stages"][st] = {"started": kit.now_iso(), "ended": None}
    else:
        if not cur.get("started"):
            raise kit.KitError(f"stage {st} never started; nothing to end")
        if cur.get("ended"):
            raise kit.KitError(f"stage {st} already ended at {cur['ended']}")
        b["stages"][st] = dict(cur, ended=kit.now_iso(), **yield_stop_for(ctx, a.stage))
    kit.write_json_atomic(ctx.records / "budget.json", b)
    print(f"stage {st} {a.action}ed at {kit.now_iso()}")
    return 0


def cmd_ceiling(a: argparse.Namespace) -> int:
    import intake

    ctx = ctx_for(a.program)
    name = kit.profile(ctx.frame.get("profile") or "")["name"]
    typical, ceiling = intake.PROFILE_DAYS[name]
    # method v1.2: the yield ceiling (§12) and the Stage 9 budget (§11), as the contract page adds them
    v12 = intake.v12_ceiling(kit.profile(name), ceiling) if kit.is_v12(ctx.frame) else None
    if v12:
        ceiling = v12["total"]
    f = intake.forecast(name)
    now = kit.parse_iso(kit.now_iso())
    starts = [
        kit.parse_iso(v["started"])
        for v in load_budget(ctx)["stages"].values()
        if v.get("started")
    ]
    ws = waiting_since(ctx)
    try:
        wait = (
            (round(max(0.0, now - kit.parse_iso(ws)) / DAY, 2) if ws else 0.0)
            if ws != "unknown"
            else None
        )
    except ValueError:
        ws, wait = "unknown", None
    d = {
        "program": a.program,
        "profile": name,
        "typical_days": typical,
        "ceiling_days": ceiling,
        "rounds_p50": f.get("rounds_p50"),
        "rounds_p90": f.get("rounds_p90"),
        "elapsed_days": round((now - min(starts)) / DAY, 2) if starts else 0.0,
        "waiting_since": ws,
        "wait_days": wait,
        "calendar_ceiling_days": None if wait is None else round(ceiling + wait, 2),
    }
    if v12:
        d.update(yield_ceiling_days=v12["yield_days"], stage9_days=v12["stage9_days"])
    if a.json:
        print(json.dumps(d, indent=2))
        return 0
    cal = "unknown" if wait is None else f"about {d['calendar_ceiling_days']:g} days"
    print(
        f"Typical total about {typical:g} days; ceiling (every loop at its cap) about "
        f"{ceiling:g} days ({name} profile, §6.1"
        + (f", plus the v1.2 yield ceiling {v12['yield_days']:g} d and Stage 9 {v12['stage9_days']:g} d"
           if v12 else "")
        + f") · elapsed {d['elapsed_days']:g} d\n"
        f"Waiting on you since {ws or 'nothing open'} · calendar ceiling with your waits {cal}"
    )
    return 0


# ── reopen (operator-only) ────────────────────────────────────────────────────────────────────────


def cmd_reopen(a: argparse.Namespace) -> int:
    import gate
    import operator_sign

    kit.check_slug(a.program)
    cmd = signoff_cmd(a.program, "reopen")
    try:
        operator_sign.refuse_if_agent(operator_sign.ancestry(), cmd)
    except operator_sign.Refused as e:
        raise kit.KitError(str(e)) from e
    if not gate.reopened(gate.make_ctx(a.program)):
        raise kit.KitError(
            f"no valid reopen signature newer than the certificate; the operator "
            f"signs one first: {cmd}"
        )
    return int(gate.cmd_run(argparse.Namespace(program=a.program, json=a.json)))


def add_verbs(sub: Any) -> None:
    """Add this module's verbs to the cc-research parser."""
    for verb in PASS_THROUGH:
        p = sub.add_parser(verb, add_help=False, prefix_chars="\x00")
        p.add_argument("rest", nargs=argparse.REMAINDER)
        p.set_defaults(fn=cmd_pass)

    def one(
        verb: str, fn: Callable[[argparse.Namespace], int], js: bool = False
    ) -> Any:
        p = sub.add_parser(verb)
        p.add_argument("--program", required=True)
        if js:
            p.add_argument("--json", action="store_true")
        p.set_defaults(fn=fn)
        return p

    for verb, fn in (
        ("forecast", cmd_forecast),
        ("freeze", cmd_freeze),
        ("trace", cmd_trace),
        ("reconcile", cmd_reconcile),
        ("lint", cmd_lint),
    ):
        one(verb, fn)
    one("menu", cmd_menu, True)
    one("ceiling", cmd_ceiling, True)
    one("reopen", cmd_reopen, True)
    p = one("budget", cmd_budget, True)
    p.add_argument("action", nargs="?", choices=["start", "end"])
    p.add_argument("--stage", type=int)
    p = sub.add_parser("verdict")
    p.add_argument("slug", nargs="?")
    p.add_argument("--program")
    p.add_argument("--json", action="store_true")
    p.set_defaults(fn=cmd_verdict)
    p = sub.add_parser("pending")
    p.add_argument("--json", action="store_true")
    p.set_defaults(fn=cmd_pending)
