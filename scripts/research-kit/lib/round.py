"""round.py — one frame-critique, certification or delta round (REPORT.md §3.2 step 6, §3.8, §5.3, §6.5).

  round.sh run   --program P --kind frame-critique|certification|delta --round N --plan SEEDED --brief F
                 [--escape H-id]
  round.sh close --program P --round ID

The caps live HERE, in code (§10 item 17), and every refusal names its cap (exit 2):
  - frame critique: exactly 2 rounds of 6 reviewers across at least 3 vendor families;
  - certification: rounds in order, none skipped, each opened only after the last one closed; the
    frame critique must have run both rounds first; no round past
    R_max = min(round-1 forecast p90 + 4, profile hard cap), +1 only for a VALID operator-signed extra
    round set (one per program); the round equal to R_max is verification-only; no round after the
    stop rule has fired (K quiet rounds at r >= K + 1);
  - delta: at most 2 per escape, the second verification-only.
Slots run in parallel through courier.sh. A dead or voided slot is re-run at most twice; a lane whose
every slot is still dead or void is DEAD, and a round with a dead lane is not counted. A dead lane's
slots are never handed to another vendor (§3.8). Only after the operator's class-B default
"continue on two vendors" has fired (frame.json `degraded: "two vendors"`, `dead_lanes: [..]`) do
rounds run without that lane, and then only with two families, one of them non-Anthropic.

Round directories: certification `rounds/<n>/`, frame critique `rounds/fc<n>/`, delta
`rounds/delta-<hole>-<n>/`. Test override for the courier: CC_RESEARCH_COURIER.
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "lib"))
import kit  # noqa: E402

HERE = Path(__file__).resolve().parent
# Frame critique (§3.2 step 6): two frontier derivation slots, then one per remaining lane, 6 in all.
FC_DEFAULT = [
    ("frontier", "frame-rows-only"),
    ("frontier", "frame-rows-only"),
    ("anthropic", "frame-rows-only"),
    ("openai", "frame-rows-only"),
    ("openai", "frame-rows-only"),
    ("google", "frame-rows-only"),
]


class Refused(kit.KitError):
    pass


def courier() -> str:
    return os.environ.get("CC_RESEARCH_COURIER") or str(HERE.parent / "courier.sh")


def rounds_dir(slug: str) -> Path:
    return kit.records_dir(slug) / "rounds"


def matrix(slug: str, rid: str) -> Optional[Dict[str, Any]]:
    return kit.read_json(rounds_dir(slug) / rid / "matrix.json")


def all_matrices(slug: str, kind: str) -> List[Dict[str, Any]]:
    out = [kit.read_json(p) for p in rounds_dir(slug).glob("*/matrix.json")]
    return sorted(
        [m for m in out if m and m.get("kind") == kind],
        key=lambda m: int(m.get("seq") or 0),
    )


def frame(slug: str) -> Dict[str, Any]:
    f = kit.read_json(kit.records_dir(slug) / "frame.json")
    if not f or not f.get("profile"):
        raise Refused("frame.json is missing or names no profile")
    return f


def extra_round_granted(slug: str) -> bool:
    import operator_sign

    return operator_sign.latest_valid(slug, "extra-round") is not None


def live_lanes(fr: Dict[str, Any]) -> List[str]:
    dead = (
        set(fr.get("dead_lanes") or [])
        if fr.get("degraded") == "two vendors"
        else set()
    )
    return [v for v in kit.VENDORS if v not in dead]


def check_families(slots: List[Tuple[str, str]], fr: Dict[str, Any], need: int) -> None:
    fams = {kit.VENDOR_FAMILY[v] for v, _ in slots}
    if fr.get("degraded") == "two vendors":
        if len(fams) < 2 or fams == {"anthropic"}:
            raise Refused(
                "two-vendor default needs two families, one of them non-Anthropic (§3.8)"
            )
    elif len(fams) < need:
        raise Refused(
            f"slots span {len(fams)} vendor families; at least {need} are required (§3.8)"
        )


def plan_slots(
    slug: str, kind: str, n: int, escape: Optional[str]
) -> Tuple[str, List[Tuple[str, str]], bool, int]:
    """(round id, [(vendor, strategy)], verification_only, r_max) or Refused."""
    fr = frame(slug)
    prof = kit.profile(fr["profile"])
    lanes = live_lanes(fr)
    if kind == "frame-critique":
        done = all_matrices(slug, "frame-critique")
        if n != len(done) + 1:
            raise Refused(
                f"frame-critique round {n} out of order; next is {len(done) + 1}"
            )
        if n > kit.CAPS["frame_critique_rounds"]:
            raise Refused(
                f"the frame critique is exactly {kit.CAPS['frame_critique_rounds']} rounds (§6.5); no third"
            )
        slots = [
            (v, s)
            for v, s in (fr.get("frame_critique_slots") or FC_DEFAULT)
            if v in lanes
        ]
        if (
            len(slots) != kit.CAPS["frame_critique_reviewers"]
            and fr.get("degraded") != "two vendors"
        ):
            raise Refused(
                f"a frame-critique round is {kit.CAPS['frame_critique_reviewers']} reviewers, not {len(slots)}"
            )
        check_families(slots, fr, kit.CAPS["frame_critique_min_vendors"])
        return f"fc{n}", slots, False, kit.CAPS["frame_critique_rounds"]
    if kind == "delta":
        if not escape:
            raise Refused("a delta round needs --escape <hole id>")
        mine = [m for m in all_matrices(slug, "delta") if m.get("escape") == escape]
        if n != len(mine) + 1 or n > 2:
            raise Refused(
                f"delta rounds per escape are capped at 2 (§5.3 step 3); {escape} has {len(mine)}"
            )
        slots = [(v, s) for v in lanes for s in prof["strategies"]]
        return f"delta-{escape}-{n}", slots, n == 2, 2
    if kind != "certification":
        raise Refused(f"unknown round kind {kind!r}")
    fc = all_matrices(slug, "frame-critique")
    if len(fc) < kit.CAPS["frame_critique_rounds"] or not all(
        m.get("closed") for m in fc
    ):
        raise Refused(
            "certification starts only after both frame-critique rounds have run and closed"
        )
    done = sorted(all_matrices(slug, "certification"), key=lambda m: int(m["round"]))
    if n != len(done) + 1:
        raise Refused(
            f"certification round {n} out of order; next is {len(done) + 1} (no skipping)"
        )
    if done and not done[-1].get("closed"):
        raise Refused(f"round {done[-1]['round']} is not closed yet (round.sh close)")
    p90 = (done[0].get("forecast") or {}).get("p90") if done else None
    rmax = kit.r_max(fr["profile"], p90, extra_round_granted(slug))
    if n > rmax:
        raise Refused(
            f"round {n} is past R_max = {rmax} (min(round-1 p90 + {kit.CAPS['rp90_slack_rounds']}, "
            f"hard cap {prof['hard_cap']}){', +1 extra set' if extra_round_granted(slug) else ''})"
        )
    counted = [m for m in done if m.get("counted")]
    k = prof["quiet_to_stop"]
    if (
        len(done) >= k + 1
        and len(counted) >= k
        and all(m.get("quiet") for m in counted[-k:])
    ):
        raise Refused(
            f"the stop rule has fired: the last {k} counted rounds were quiet; certify, do not review again"
        )
    slots = [(v, s) for v in lanes for s in prof["strategies"]]
    if (
        fr.get("degraded") != "two vendors"
        and len(slots) != prof["reviewers_per_round"]
    ):
        raise Refused(
            f"a {fr['profile']} round is {prof['reviewers_per_round']} reviewers, not {len(slots)}"
        )
    check_families(slots, fr, 3)
    return str(n), slots, n == rmax, rmax


def run_slots(
    slug: str, rid: str, slots: List[Tuple[str, str]], brief: Path
) -> List[Dict[str, Any]]:
    """Every slot in parallel; dead/void slots re-run up to CAPS['slot_reruns'] times."""
    bdir = rounds_dir(slug) / rid / "briefs"
    bdir.mkdir(parents=True, exist_ok=True)
    text = brief.read_text()
    state = []
    for i, (v, s) in enumerate(slots, 1):
        bf = bdir / f"{s}.txt"
        if not bf.exists():
            bf.write_text(f"{text}\n\nContext strategy for this slot: {s}.\n")
        state.append(
            {
                "pid": f"r{rid}p{i}",
                "vendor": v,
                "strategy": s,
                "status": None,
                "reruns": -1,
                "brief": str(bf),
            }
        )
    pending = list(state)
    while pending:
        procs = []
        for sl in pending:
            sl["reruns"] += 1
            procs.append(
                (
                    sl,
                    subprocess.Popen(
                        [
                            courier(),
                            "run",
                            "--program",
                            slug,
                            "--round",
                            rid,
                            "--pid",
                            sl["pid"],
                            "--vendor",
                            sl["vendor"],
                            "--strategy",
                            sl["strategy"],
                            "--role",
                            "reviewer",
                            "--brief",
                            sl["brief"],
                        ],
                        stdin=subprocess.DEVNULL,
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL,
                    ),
                )
            )
        for sl, p in procs:
            rc = p.wait()
            sl["status"] = {0: "complete", 3: "dead", 4: "void"}.get(rc, "dead")
            pj = (
                kit.read_json(rounds_dir(slug) / rid / "panels" / f"{sl['pid']}.json")
                or {}
            )
            if rc == 0 and pj.get("status") in ("complete", "partial"):
                sl["status"] = pj["status"]
        pending = [
            sl
            for sl in state
            if sl["status"] in ("dead", "void")
            and sl["reruns"] < kit.CAPS["slot_reruns"]
        ]
    for sl in state:
        sl.pop("brief", None)
    return state


def cmd_run(a: argparse.Namespace) -> int:
    rid, slots, vonly, rmax = plan_slots(a.program, a.kind, a.round, a.escape)
    rd = rounds_dir(a.program) / rid
    if (rd / "matrix.json").exists():
        raise Refused(f"round {rid} already ran")
    p = subprocess.run(
        [courier(), "bundle", "--program", a.program, "--round", rid, "--plan", a.plan],
        stdin=subprocess.DEVNULL,
        capture_output=True,
        text=True,
    )
    if p.returncode != 0:
        raise Refused(f"courier bundle failed: {p.stderr.strip()}")
    res = run_slots(a.program, rid, slots, Path(a.brief))
    subprocess.run(
        [courier(), "integrity", "--program", a.program, "--round", rid],
        stdin=subprocess.DEVNULL,
        capture_output=True,
    )
    for (
        sl
    ) in res:  # the integrity pass may have voided a slot after it reported complete
        pj = kit.read_json(rd / "panels" / f"{sl['pid']}.json") or {}
        if pj.get("status") == "void":
            sl["status"] = "void"
    lanes = {}
    for v in sorted({sl["vendor"] for sl in res}):
        lanes[v] = (
            "live"
            if any(
                sl["status"] in ("complete", "partial")
                for sl in res
                if sl["vendor"] == v
            )
            else "dead"
        )
    freeze = kit.read_json(kit.records_dir(a.program) / "freeze.json", {}) or {}
    m = {
        "round": rid,
        "seq": a.round,
        "kind": a.kind,
        "escape": a.escape,
        "snapshot_sha": freeze.get("snapshot_sha"),
        "verification_only": vonly,
        "r_max": rmax,
        "slots": res,
        "lanes": lanes,
        "counted": all(s == "live" for s in lanes.values()),
        "closed": False,
        "at": kit.now_iso(),
    }
    kit.write_json_atomic(rd / "matrix.json", m)
    dead = [v for v, s in lanes.items() if s == "dead"]
    print(
        f"round {rid}: {len(res)} slots, lanes {lanes}, counted={m['counted']}"
        f"{', VERIFICATION-ONLY' if vonly else ''}"
    )
    if dead:
        print(
            f"DEAD LANE {', '.join(dead)}: this round does not count; restore the lane or let the class-B "
            f"default 'continue on two vendors' fire (48 h)",
            file=sys.stderr,
        )
        return 3
    return 0


def cmd_close(a: argparse.Namespace) -> int:
    rd = rounds_dir(a.program) / a.round
    m = kit.read_json(rd / "matrix.json")
    if not m:
        raise Refused(f"round {a.round} has not run")
    if m.get("closed"):
        raise Refused(f"round {a.round} is already closed")
    # A counted round is a full read: a dead, void, partial or missing slot closed as quiet would
    # feed the stop rule a read that never happened (gate row 13 refuses it, but only at the gate).
    lost = [
        f"{s.get('pid')} ({s.get('status') or 'missing'})"
        for s in m.get("slots") or []
        if s.get("status") != "complete"
    ]
    if m.get("counted") and lost:
        raise Refused(
            f"round {a.round} is counted but planned slot(s) {', '.join(lost)} did not complete; "
            f"re-run them before closing"
        )
    # Match seeds FIRST: seed.py match writes seed_match onto each hole that restates a seed, and
    # only then can a caught seed be told apart from a real finding.
    fr = frame(a.program)
    vault = kit.sealed_dir(a.program) / "vault" / "seeds.enc"
    if vault.exists() and fr.get("plan"):
        p = subprocess.run(
            [
                str(HERE.parent / "seed.py"),
                "match",
                "--program",
                a.program,
                "--round",
                str(m.get("seq")),
                "--plan",
                str(kit.records_dir(a.program) / fr["plan"]),
            ],
            capture_output=True,
            text=True,
        )
        if p.returncode != 0:
            raise Refused(f"seed.py match failed: {p.stderr.strip()}")
        import json

        cohorts = json.loads(p.stdout)
        m["seeds"] = {
            "original": cohorts.get("original", {}),
            "shadow": {
                k: sum(
                    c.get(k, 0) for n, c in cohorts.items() if n.startswith("shadow")
                )
                for k in ("s_eff", "caught", "k_left", "orphaned")
            },
        }
    holes = kit.fold(
        kit.read_jsonl(kit.records_dir(a.program) / "holes.jsonl")
    ).values()
    mine = [h for h in holes if str(h.get("round")) in (a.round, str(m.get("seq")))]
    real = [
        h
        for h in mine
        if (h.get("verification") or {}).get("status") == "CONFIRMED"
        and (h.get("materiality") or {}).get("level") == "MATERIAL"
        and not h.get("seed_match")
    ]
    m["new_material"] = len(real)
    m["seeds_caught"] = sum(
        1 for h in mine if h.get("seed_match")
    )  # never resets the quiet count (§3.9)
    m["quiet"] = bool(m.get("counted")) and not real
    m["closed"] = True
    kit.write_json_atomic(rd / "matrix.json", m)
    if m["kind"] == "certification" and m.get("seq") == 1 and m.get("counted"):
        sys.path.insert(0, str(HERE.parent))
        import estimate

        f = estimate.forecast(a.program)
        m["forecast"] = {"p50": f["p50"], "p90": f["p90"]}
        m["r_max"] = f["r_max"]
        kit.write_json_atomic(rd / "matrix.json", m)
    print(
        f"round {a.round} closed: new material {m['new_material']}, seeds caught {m['seeds_caught']}, "
        f"quiet={m['quiet']}{', R_max ' + str(m['r_max']) if m.get('forecast') else ''}"
    )
    return 0


def main(argv: Optional[List[str]] = None) -> int:
    ap = argparse.ArgumentParser(prog="round.sh")
    sub = ap.add_subparsers(dest="verb", required=True)
    p = sub.add_parser("run")
    p.add_argument("--program", required=True)
    p.add_argument(
        "--kind", required=True, choices=("frame-critique", "certification", "delta")
    )
    p.add_argument("--round", type=int, required=True)
    p.add_argument("--plan", required=True)
    p.add_argument("--brief", required=True)
    p.add_argument("--escape")
    p.set_defaults(fn=cmd_run)
    p = sub.add_parser("close")
    p.add_argument("--program", required=True)
    p.add_argument("--round", required=True)
    p.set_defaults(fn=cmd_close)
    a = ap.parse_args(argv)
    try:
        kit.check_slug(a.program)
        return int(a.fn(a))
    except kit.KitError as e:
        print(
            f"round.sh: refused: {e}" if isinstance(e, Refused) else f"round.sh: {e}",
            file=sys.stderr,
        )
        return 2


if __name__ == "__main__":
    sys.exit(main())
