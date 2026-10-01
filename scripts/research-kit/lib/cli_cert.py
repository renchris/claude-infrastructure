"""cli_cert.py — the certification verbs of bin/cc-research (REPORT.md §3.8, §8 item 11).

  slots       --program P --kind K --round N [--escape H] [--json]   round.plan_slots as [{pid, vendor, strategy, role}]
  open-round  --program P --kind K --round N --plan F [--escape H]   writes rounds/<rid>/plan.json, builds the bundle
  slot        --program P --round RID --pid PID --brief F            runs ONE planned slot through the courier
  raters      --program P --round RID [--json]                       the rater assignment (§3.8 step 2)
  check-round --program P --round RID [--json]                       voids pin, rater and integrity breaches
  round | frame-critique --program P --round N --plan F --brief F    round.py run with the kind fixed
  rehearse frames --program P [--json] | rehearse record --program P --frames-typed F.. --trials FILE [--retest]

The Workflows in ../workflows/ only call these. What is enforced HERE, in code: the slot plan and its
caps (round.py), the vendor/strategy/role of every slot (an agent names a pid, never a vendor), the
re-run cap per slot (CAPS["slot_reruns"]), the rater assignment, the responding-model check against
frame.json reviewer_pins, and the relay test of gate row 14. A Workflow round writes rounds/<rid>/
matrix.json through check-round (round.py's shape), so `round.sh close` and gate row 13 read it as
they read a round.py round. Exit codes are the kit's: 0 ok · 1 check failed · 2 refusal · 3 dead lane
· 4 void slot.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
from pathlib import Path
from typing import Any, Dict, List, Optional

import kit
import courier
import round as rnd

RELAY_TRIALS = 20  # §3.8 rehearsal: the relay test is 20 trials


def rdir(slug: str, rid: str) -> Path:
    return rnd.rounds_dir(slug) / str(rid)


def plan_rows(rid: str, slots: List[Any]) -> List[Dict[str, Any]]:
    return [
        {
            "pid": f"r{rid}p{i}",
            "vendor": v,
            "strategy": s,
            "role": "reviewer",
            "round": rid,
        }
        for i, (v, s) in enumerate(slots, 1)
    ]


def raters(slug: str, rid: str) -> Optional[List[Dict[str, Any]]]:
    """§3.8 step 2. None when fewer than two families are live or none of them is non-Anthropic."""
    fr = rnd.frame(slug)
    fams: Dict[str, str] = {}
    for v in rnd.live_lanes(fr):
        fams.setdefault(kit.VENDOR_FAMILY[v], v)
    order = [f for f in ("openai", "google", "anthropic") if f in fams]
    non = [f for f in order if f != "anthropic"]
    if len(order) < 2 or not non:
        return None
    picks = [non[0]] + [f for f in order if f != non[0]][:2]
    out = [
        {
            "pid": f"r{rid}rater{k}",
            "slot": k,
            "vendor": fams[f],
            "family": f,
            "fresh_process": False,
            "role": "rater",
        }
        for k, f in enumerate(picks, 1)
    ]
    if (
        len(out) == 2
    ):  # the two-vendor default: rater 3 is a fresh process from rater 1's vendor
        out.append(dict(out[0], pid=f"r{rid}rater3", slot=3, fresh_process=True))
    return out


def attempts(slug: str, rid: str) -> Dict[str, int]:
    n: Dict[str, int] = {}
    for e in kit.read_jsonl(rdir(slug, rid) / "attempts.jsonl"):
        n[e["pid"]] = max(n.get(e["pid"], 0), int(e["attempt"]))
    return n


def emit(a: argparse.Namespace, obj: Any, lines: List[str]) -> None:
    print(json.dumps(obj, indent=2) if getattr(a, "json", False) else "\n".join(lines))


# ── verbs ───────────────────────────────────────────────────────────────────────────────────────


def cmd_slots(a: argparse.Namespace) -> int:
    rid, slots, _, _ = rnd.plan_slots(a.program, a.kind, a.round, a.escape)
    rows = plan_rows(rid, slots)
    emit(a, rows, [f"{r['pid']} {r['vendor']} {r['strategy']}" for r in rows])
    return 0


def cmd_open(a: argparse.Namespace) -> int:
    rid, slots, vonly, rmax = rnd.plan_slots(a.program, a.kind, a.round, a.escape)
    rd = rdir(a.program, rid)
    if (rd / "plan.json").exists() or (rd / "matrix.json").exists():
        raise kit.KitError(f"round {rid} is already open")
    rat = raters(a.program, rid)
    if rat is None:
        print(
            "cc-research: no rater assignment: fewer than two live families or none non-Anthropic"
        )
        return 3
    p = subprocess.run(
        [
            rnd.courier(),
            "bundle",
            "--program",
            a.program,
            "--round",
            rid,
            "--plan",
            a.plan,
        ],
        stdin=subprocess.DEVNULL,
        capture_output=True,
        text=True,
    )
    if p.returncode != 0:
        raise kit.KitError(f"courier bundle failed: {p.stderr.strip()}")
    kit.write_json_atomic(
        rd / "plan.json",
        {
            "round": rid,
            "seq": a.round,
            "kind": a.kind,
            "escape": a.escape,
            "verification_only": vonly,
            "r_max": rmax,
            "slots": plan_rows(rid, slots),
            "raters": rat,
            "at": kit.now_iso(),
        },
    )
    print(rid)
    return 0


def cmd_slot(a: argparse.Namespace) -> int:
    rd = rdir(a.program, a.round)
    plan = kit.read_json(rd / "plan.json")
    if not plan:
        raise kit.KitError(f"round {a.round} is not open (cc-research open-round)")
    sl = next(
        (
            s
            for s in plan["slots"] + (raters(a.program, a.round) or [])
            if s["pid"] == a.pid
        ),
        None,
    )
    if sl is None:
        raise kit.KitError(f"{a.pid} is not a slot or rater of round {a.round}")
    n = attempts(a.program, a.round).get(a.pid, 0)
    if n >= 1 + kit.CAPS["slot_reruns"]:
        raise kit.KitError(
            f"{a.pid} has run {n} times; a slot is re-run at most {kit.CAPS['slot_reruns']} times"
        )
    kit.append_jsonl(rd / "attempts.jsonl", {"pid": a.pid, "attempt": n + 1})
    strategy = sl.get("strategy") or "rater"
    bf = rd / "briefs" / f"{strategy}.txt"
    if not bf.exists():
        bf.parent.mkdir(parents=True, exist_ok=True)
        text = Path(a.brief).read_text()
        bf.write_text(
            text
            if sl["role"] == "rater"
            else f"{text}\n\nContext strategy for this slot: {strategy}.\n"
        )
    return subprocess.run(
        [
            rnd.courier(),
            "run",
            "--program",
            a.program,
            "--round",
            a.round,
            "--pid",
            a.pid,
            "--vendor",
            sl["vendor"],
            "--strategy",
            strategy,
            "--role",
            sl["role"],
            "--brief",
            str(bf),
        ],
        stdin=subprocess.DEVNULL,
    ).returncode


def cmd_raters(a: argparse.Namespace) -> int:
    rat = raters(a.program, a.round)
    if rat is None:
        print(
            "cc-research: no rater assignment: fewer than two live families or none non-Anthropic"
        )
        return 3
    emit(
        a,
        rat,
        [
            f"rater {r['slot']} {r['vendor']}{' (fresh process)' if r['fresh_process'] else ''}"
            for r in rat
        ],
    )
    return 0


def panel_breaches(
    slug: str,
    p: Dict[str, Any],
    raw: Path,
    pins: Dict[str, str],
    assign: Dict[int, Dict[str, Any]],
    needles: List[str],
) -> List[str]:
    why: List[str] = []
    want = pins.get(str(p.get("vendor")))
    if not want:
        why.append(f"no reviewer pin for {p.get('vendor')}")
    elif p.get("responding_model") != want:
        why.append(f"responding model {p.get('responding_model')}, pinned {want}")
    if p.get("role") == "rater":
        m = re.search(r"rater(\d+)$", str(p.get("pid")))
        slot = assign.get(int(m.group(1))) if m else None
        if slot is None:
            why.append("not a rater slot of the assignment")
        elif slot["vendor"] != p.get("vendor"):
            why.append(
                f"rater slot {slot['slot']} is {slot['vendor']}, ran on {p.get('vendor')}"
            )
    text = raw.read_text(errors="replace") if raw.exists() else ""
    hits = sorted(
        set((p.get("integrity") or {}).get("hits") or [])
        | {n for n in needles if n in text}
    )
    if hits:
        p.setdefault("integrity", {})["hits"] = hits
        why.append("integrity hit: " + ", ".join(hits))
    if p.get("status") == "void" and not why:
        why.append("voided by the courier")
    return why


def cmd_check(a: argparse.Namespace) -> int:
    rd = rdir(a.program, a.round)
    fr = rnd.frame(a.program)
    pins = fr.get("reviewer_pins") or {}
    assign = {r["slot"]: r for r in raters(a.program, a.round) or []}
    needles = courier.integrity_needles(a.program)
    tries = attempts(a.program, a.round)
    seen = {
        (e.get("pid"), e.get("attempt")) for e in kit.read_jsonl(rd / "check.jsonl")
    }
    voided, status = [], {}
    for pj in sorted((rd / "panels").glob("*.json")):
        p = kit.read_json(pj) or {}
        pid = str(p.get("pid") or pj.stem)
        status[pid] = p.get("status")
        if p.get("status") == "dead":
            continue
        why = panel_breaches(
            a.program, p, pj.with_suffix(".raw"), pins, assign, needles
        )
        if not why:
            continue
        p["status"] = status[pid] = "void"
        kit.write_json_atomic(pj, p)
        n = tries.get(pid, 1)
        if (pid, n) not in seen:
            kit.append_jsonl(
                rd / "check.jsonl",
                {
                    "event": "void",
                    "pid": pid,
                    "vendor": p.get("vendor"),
                    "role": p.get("role"),
                    "reason": "; ".join(why),
                    "attempt": n,
                },
            )
        voided.append(
            {
                "pid": pid,
                "reason": "; ".join(why),
                "reruns_left": max(0, 1 + kit.CAPS["slot_reruns"] - n),
            }
        )
    write_matrix(a.program, rd, status, tries)
    emit(
        a,
        {"round": a.round, "voided": voided, "exit": 4 if voided else 0},
        [f"void {v['pid']}: {v['reason']}" for v in voided]
        or [f"round {a.round}: no slot voided"],
    )
    return 4 if voided else 0


def write_matrix(
    slug: str, rd: Path, status: Dict[str, Any], tries: Dict[str, int]
) -> None:
    """A Workflow round's matrix.json, in round.py cmd_run's shape; never over a closed round."""
    plan = kit.read_json(rd / "plan.json")
    old = kit.read_json(rd / "matrix.json") or {}
    if not plan or old.get("closed"):
        return
    res = [
        {
            "pid": s["pid"],
            "vendor": s["vendor"],
            "strategy": s["strategy"],
            "status": status.get(s["pid"]) or "dead",
            "reruns": max(0, tries.get(s["pid"], 1) - 1),
        }
        for s in plan["slots"]
    ]
    lanes = {
        v: "live"
        if any(s["status"] in ("complete", "partial") for s in res if s["vendor"] == v)
        else "dead"
        for v in sorted({s["vendor"] for s in res})
    }
    freeze = kit.read_json(kit.records_dir(slug) / "freeze.json", {}) or {}
    kit.write_json_atomic(
        rd / "matrix.json",
        {
            "round": plan["round"],
            "seq": plan["seq"],
            "kind": plan["kind"],
            "escape": plan["escape"],
            "snapshot_sha": freeze.get("snapshot_sha"),
            "verification_only": plan["verification_only"],
            "r_max": plan["r_max"],
            "slots": res,
            "lanes": lanes,
            "counted": all(s == "live" for s in lanes.values()),
            "closed": False,
            "at": kit.now_iso(),
        },
    )


def cmd_round(a: argparse.Namespace) -> int:
    return rnd.cmd_run(
        argparse.Namespace(
            program=a.program,
            kind=a.kind,
            round=a.round,
            plan=a.plan,
            brief=a.brief,
            escape=None,
        )
    )


def relay_fails(slug: str, trials: List[Dict[str, Any]]) -> List[str]:
    import router

    cert, err = router.render_cert(slug)
    if err:
        raise kit.KitError(err)
    roots = [
        os.path.realpath(r)
        for r in (kit.registry_get(slug) or {}).get("cwd_roots") or []
    ]
    if not roots:
        raise kit.KitError(
            f"program {slug!r} has no registered cwd_roots; the outside-the-root trial cannot be judged"
        )
    fails = (
        []
        if len(trials) >= RELAY_TRIALS
        else [f"{len(trials)} trials; the relay test is {RELAY_TRIALS}"]
    )
    outside = False
    for i, t in enumerate(trials, 1):
        reply = str(t.get("reply") or "")
        label = (
            t.get("label")
            if t.get("label") in ("completeness", "pushback")
            else "completeness"
        )
        v = router.relay_violations(reply, cert, label)
        if any(
            router.norm(ln) not in router.norm(reply)
            for ln in cert.splitlines()
            if ln.strip()
        ):
            v.append("it does not relay the certificate lines unchanged")
        bad = [
            str(c) for c in t.get("tools") or [] if not router.cert_read(str(c), slug)
        ]
        if bad:
            v.append(
                "it called "
                + ", ".join(bad)
                + " (only the certificate read is allowed)"
            )
        fails += [f"trial {t.get('trial', i)}: {x}" for x in v]
        cwd = os.path.realpath(str(t.get("cwd") or ""))
        if t.get("cwd") and not any(
            cwd == r or cwd.startswith(r + os.sep) for r in roots
        ):
            outside = True
    if not outside:
        fails.append("no trial was asked from outside the program's cwd_roots")
    return fails


def cmd_rehearse(a: argparse.Namespace) -> int:
    rec = kit.records_dir(a.program)
    if a.sub == "frames":
        frames = [
            m["frame"]
            for m in rnd.frame(a.program).get("reask_map") or []
            if m.get("axis")
        ]
        emit(a, frames, frames)
        return 0
    hist = kit.read_jsonl(rec / "rehearsal.jsonl")
    if len(hist) >= 2:
        raise kit.KitError(
            "the relay test allows one repair and one re-test; a third record is refused"
        )
    if hist and not a.retest:
        raise kit.KitError(
            "a rehearsal is already recorded; after one repair, record again with --retest"
        )
    if not hist and a.retest:
        raise kit.KitError("nothing to re-test: no rehearsal is recorded")
    if hist and hist[-1].get("passed"):
        raise kit.KitError("the relay test already passed; there is nothing to re-test")
    if not a.trials:
        raise kit.KitError("rehearse record needs --trials FILE")
    trials = kit.read_jsonl(Path(a.trials))
    fails = relay_fails(a.program, trials)
    passed, n = not fails, len(trials)
    kit.append_jsonl(
        rec / "rehearsal.jsonl",
        {
            "event": "retest" if hist else "record",
            "trials": n,
            "passed": passed,
            "fails": fails,
            "frames_typed": a.frames_typed,
        },
    )
    kit.write_json_atomic(
        rec / "rehearsal.json",
        {
            "frames_typed": a.frames_typed,
            "at": kit.now_iso(),
            "relay": {
                "trials": n,
                "passed": passed,
                "unstable": bool(hist) and not passed,
            },
        },
    )
    print("\n".join(fails) or f"relay test passed: {n} trials")
    return 0 if passed else 1


def add_verbs(sub: Any) -> None:
    """slots open-round slot raters check-round round frame-critique rehearse."""

    def P(name: str, fn: Any) -> argparse.ArgumentParser:
        p = sub.add_parser(name)
        p.add_argument("--program", required=True, type=kit.check_slug)
        p.set_defaults(fn=fn)
        return p

    for name, fn in (("slots", cmd_slots), ("open-round", cmd_open)):
        p = P(name, fn)
        p.add_argument(
            "--kind",
            required=True,
            choices=("frame-critique", "certification", "delta"),
        )
        p.add_argument("--round", type=int, required=True)
        p.add_argument("--escape")
        if name == "slots":
            p.add_argument("--json", action="store_true")
        else:
            p.add_argument("--plan", required=True)
    p = P("slot", cmd_slot)
    p.add_argument("--round", required=True)
    p.add_argument("--pid", required=True)
    p.add_argument("--brief", required=True)
    for name, fn in (("raters", cmd_raters), ("check-round", cmd_check)):
        p = P(name, fn)
        p.add_argument("--round", required=True)
        p.add_argument("--json", action="store_true")
    for name, kind in (
        ("round", "certification"),
        ("frame-critique", "frame-critique"),
    ):
        p = P(name, cmd_round)
        p.set_defaults(kind=kind)
        p.add_argument("--round", type=int, required=True)
        p.add_argument("--plan", required=True)
        p.add_argument("--brief", required=True)
    p = P("rehearse", cmd_rehearse)
    p.add_argument("sub", choices=("frames", "record"))
    p.add_argument("--frames-typed", nargs="*", default=[])
    p.add_argument("--trials")
    p.add_argument("--retest", action="store_true")
    p.add_argument("--json", action="store_true")
