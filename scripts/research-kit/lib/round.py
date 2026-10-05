"""round.py — one frame-critique, certification, delta or built round (REPORT.md §3.2 step 6, §3.8,
§5.3, §6.5, and §11 for the built kind).

  round.sh run   --program P --kind frame-critique|certification|delta|built --round N --plan SEEDED --brief F
                 [--escape H-id]
  round.sh close --program P --round ID

The caps live HERE, in code (§10 item 17), and every refusal names its cap (exit 2):
  - frame critique: exactly 2 rounds of 6 reviewers across at least 3 vendor families;
  - certification: rounds in order, none skipped, each opened only after the last one closed; the
    frame critique must have run both rounds first; no counted round past
    R_max = min(round-1 forecast p90 + 4, profile hard cap), +1 only for a VALID operator-signed extra
    round set (one per program); the counted round equal to R_max is verification-only; rounds lost
    to a dead lane spend no R_max but stop at UNCOUNTED_ROUNDS_MAX; none opens without a fresh
    all-live vendor preflight (exit 3); no round after the stop rule has fired (K quiet rounds at
    r >= K + 1);
  - delta: at most 2 per escape, the second verification-only.
  - built (method v1.2, Stage 9): only while the registry reads build-certifying with a
    built/freeze.json; in order, none skipped; at most the profile's built_hard_cap rounds, the cap
    round verification-only, and no extra-round signature raises it; none after K quiet counted
    built rounds; at least 2 vendor families; the same fresh all-live preflight. Its bundle carries
    the built snapshot's tracked files (courier `--extra`), and its matrix pins that snapshot.
Slots run in parallel through courier.sh. A dead, voided or partial slot is re-run at most twice; a lane
with any slot still not complete is DEAD, and a round with a dead lane is not counted. A dead lane's
slots are never handed to another vendor (§3.8). Only after the operator's class-B default
"continue on two vendors" has fired (frame.json `degraded: "two vendors"`, `dead_lanes: [..]`) do
rounds run without that lane, and then only with two families, one of them non-Anthropic.

Round directories: certification `rounds/<n>/`, frame critique `rounds/fc<n>/`, delta
`rounds/delta-<hole>-<n>/`, built `rounds/b<n>/`. Test override for the courier: CC_RESEARCH_COURIER.
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple

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
# Certification rounds lost to a dead lane (uncounted) that the program tolerates. They do not spend
# R_max, so without their own cap a vendor walled for good would loop rounds forever. 2 covers the
# audit's ChatGPT Plus wall case (rounds 5-6 lost, upfront-method-audit-2026-10-04) and no more.
UNCOUNTED_ROUNDS_MAX = 2


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


def built_freeze(slug: str) -> Dict[str, Any]:
    """built/freeze.json of a program in Stage 9 (REPORT.md §11), or Refused."""
    state = (kit.registry_get(slug) or {}).get("state")
    fz = kit.read_json(kit.records_dir(slug) / "built" / "freeze.json") or {}
    if state != "build-certifying" or not fz.get("snapshot_sha"):
        raise Refused(
            f"a built round reviews a frozen built snapshot: {slug} is {state!r} with "
            f"{'a' if fz.get('snapshot_sha') else 'no'} built/freeze.json (run gate.sh built-freeze "
            "after the last build wave)"
        )
    return fz


def plan_built(
    slug: str, fr: Dict[str, Any], prof: Dict[str, Any], lanes: List[str], n: int
) -> Tuple[str, List[Tuple[str, str]], bool, int]:
    """A Stage 9 round over the built artifact (§11): in order, none skipped, capped by the
    profile's built_hard_cap (the extra-round signature never raises it), none after K quiet."""
    built_freeze(slug)
    done = all_matrices(slug, "built")
    if n != len(done) + 1:
        raise Refused(f"built round {n} out of order; next is {len(done) + 1} (no skipping)")
    if done and not done[-1].get("closed"):
        raise Refused(f"round {done[-1]['round']} is not closed yet (round.sh close)")
    cap = int(prof["built_hard_cap"])
    if n > cap:
        raise Refused(
            f"built round {n} is past the {fr['profile']} cap of {cap} built rounds (§11); "
            "certify with named known rows"
        )
    counted = [m for m in done if m.get("counted")]
    k = prof["quiet_to_stop"]
    if len(counted) >= k and all(m.get("quiet") for m in counted[-k:]):
        raise Refused(
            f"the stop rule has fired: the last {k} counted built rounds were quiet; run the "
            "built gate, do not review again"
        )
    slots = [(v, s) for v in lanes for s in prof["strategies"]]
    if fr.get("degraded") != "two vendors" and len(slots) != prof["reviewers_per_round"]:
        raise Refused(
            f"a {fr['profile']} round is {prof['reviewers_per_round']} reviewers, not {len(slots)}"
        )
    check_families(slots, fr, kit.CAPS["built_min_families"])
    return f"b{n}", slots, n == cap, cap


def export_artifact(slug: str, dest: Path) -> Path:
    """The built snapshot's tracked files, exported at its pinned commit into dest/artifact."""
    fz = built_freeze(slug)
    out = dest / "artifact"
    out.mkdir(parents=True)
    ar = subprocess.run(
        ["git", "-C", str(fz["artifact_root"]), "archive", str(fz["snapshot_sha"])],
        capture_output=True,
    )
    if ar.returncode != 0:
        raise Refused(
            f"cannot export the built snapshot {fz['snapshot_sha']} from {fz['artifact_root']}: "
            f"{ar.stderr.decode(errors='replace').strip()}"
        )
    tar = subprocess.run(["/usr/bin/tar", "-x", "-C", str(out)], input=ar.stdout, capture_output=True)
    if tar.returncode != 0:
        raise Refused(f"cannot unpack the built snapshot: {tar.stderr.decode(errors='replace').strip()}")
    return out


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
    if kind == "built":
        return plan_built(slug, fr, prof, lanes, n)
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
    counted = [m for m in done if m.get("counted")]
    # R_max bounds COUNTED rounds: a round lost to a dead lane read nothing, so it spends no review
    # budget. UNCOUNTED_ROUNDS_MAX bounds those instead, so a permanently walled vendor cannot loop.
    lost = len(done) - len(counted)
    if lost > UNCOUNTED_ROUNDS_MAX:
        raise Refused(
            f"{lost} certification rounds were lost to a dead lane, past the cap of "
            f"{UNCOUNTED_ROUNDS_MAX} uncounted rounds; the lane must be restored before review continues"
        )
    if len(counted) + 1 > rmax:
        raise Refused(
            f"round {n} would be counted round {len(counted) + 1}, past R_max = {rmax} "
            f"(min(round-1 p90 + {kit.CAPS['rp90_slack_rounds']}, "
            f"hard cap {prof['hard_cap']}){', +1 extra set' if extra_round_granted(slug) else ''})"
        )
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
    return str(n), slots, len(counted) + 1 == rmax, rmax


def run_slots(
    slug: str,
    rid: str,
    slots: List[Tuple[str, str]],
    brief: Path,
    done: Optional[Set[str]] = None,
) -> List[Dict[str, Any]]:
    """Every slot in parallel; dead/void slots re-run up to CAPS['slot_reruns'] times.

    A pid in `done` already has a complete panel (a resumed round) and is not run again.
    """
    bdir = rounds_dir(slug) / rid / "briefs"
    bdir.mkdir(parents=True, exist_ok=True)
    text = brief.read_text()
    state = []
    for i, (v, s) in enumerate(slots, 1):
        bf = bdir / f"{s}.txt"
        if not bf.exists():
            bf.write_text(f"{text}\n\nContext strategy for this slot: {s}.\n")
        pid = f"r{rid}p{i}"
        state.append(
            {
                "pid": pid,
                "vendor": v,
                "strategy": s,
                "status": "complete" if pid in (done or set()) else None,
                "reruns": 0 if pid in (done or set()) else -1,
                "brief": str(bf),
            }
        )
    pending = [sl for sl in state if sl["status"] is None]
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
            if sl["status"] in ("dead", "void", "partial")  # a partial read is a lost read too
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
    if a.kind in ("certification", "built"):
        import cli_cert  # here, not at the top: cli_cert imports this module

        why = cli_cert.lane_refusal(a.program, {v for v, _ in slots})
        if why:  # before anything is written: a refused round mints no round dir
            print(f"round.sh: refused: {why}", file=sys.stderr)
            return 3
    # A bundle with no matrix.json is a round whose process died mid-run. courier.sh refuses a second
    # bundle, so re-running it from scratch is impossible: resume it on the bundle and plan it already
    # has, re-running only the planned slots with no complete panel.
    resumed = (kit.sealed_dir(a.program) / "rounds" / rid / "bundle").exists()
    if not resumed:
        import tempfile

        with tempfile.TemporaryDirectory(prefix="cc-built-bundle.") as tmp:
            # A built round's reviewers read the built snapshot itself, beside the plan (§11).
            extra = (
                ["--extra", str(export_artifact(a.program, Path(tmp)))]
                if a.kind == "built"
                else []
            )
            p = subprocess.run(
                [
                    courier(),
                    "bundle",
                    "--program",
                    a.program,
                    "--round",
                    rid,
                    "--plan",
                    a.plan,
                ]
                + extra,
                stdin=subprocess.DEVNULL,
                capture_output=True,
                text=True,
            )
        if p.returncode != 0:
            raise Refused(f"courier bundle failed: {p.stderr.strip()}")
    plan = kit.read_json(rd / "plan.json")
    if plan:
        slots = [(s["vendor"], s["strategy"]) for s in plan["slots"]]
        vonly, rmax = plan["verification_only"], plan["r_max"]
    else:
        kit.write_json_atomic(
            rd / "plan.json",
            {
                "round": rid,
                "seq": a.round,
                "kind": a.kind,
                "escape": a.escape,
                "verification_only": vonly,
                "r_max": rmax,
                "slots": [
                    {
                        "pid": f"r{rid}p{i}",
                        "vendor": v,
                        "strategy": s,
                        "role": "reviewer",
                        "round": rid,
                    }
                    for i, (v, s) in enumerate(slots, 1)
                ],
                "at": kit.now_iso(),
            },
        )
    done: Set[str] = set()
    if resumed:
        done = {
            f"r{rid}p{i}"
            for i in range(1, len(slots) + 1)
            if (kit.read_json(rd / "panels" / f"r{rid}p{i}.json") or {}).get("status")
            == "complete"
        }
        rerun = [
            f"r{rid}p{i}" for i in range(1, len(slots) + 1) if f"r{rid}p{i}" not in done
        ]
        print(
            f"round {rid}: resumed an interrupted run; re-running {', '.join(rerun) or 'no slot'}"
        )
    res = run_slots(a.program, rid, slots, Path(a.brief), done)
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
            if all(  # as cli_cert.write_matrix: live only when every planned slot completed
                sl["status"] == "complete" for sl in res if sl["vendor"] == v
            )
            else "dead"
        )
    freeze = kit.read_json(kit.records_dir(a.program) / "freeze.json", {}) or {}
    if a.kind == "built":  # a built round is pinned to the built snapshot, not the plan freeze
        freeze = built_freeze(a.program)
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
    built = m.get("kind") == "built"  # its seeds are the harness mutants (§11), not the plan vault
    if vault.exists() and fr.get("plan") and not built:
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
    # a built round is "b<n>": matching its seq would claim certification round n's holes
    ids = (a.round,) if built else (a.round, str(m.get("seq")))
    mine = [h for h in holes if str(h.get("round")) in ids]
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
        "--kind",
        required=True,
        choices=("frame-critique", "certification", "delta", "built"),
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
        kit.lease_check(a.program)  # run and close both write the program's rounds
        return int(a.fn(a))
    except kit.KitError as e:
        print(
            f"round.sh: refused: {e}" if isinstance(e, Refused) else f"round.sh: {e}",
            file=sys.stderr,
        )
        return 2


if __name__ == "__main__":
    sys.exit(main())
