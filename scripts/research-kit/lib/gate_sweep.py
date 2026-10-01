"""gate_sweep.py — the program's decision packets and their due dates (REPORT.md §3.5, §5.4, §5.6;
§10 items 4 and 9). Run by hand in the pilot, by launchd in wave 2.

  gate.sh file-packet --program P --decision D --class B|C --what … --option l::o … --conviction N
                      --receipt R [--default … --deadline ISO] [--due ISO]
      cc-decide open with the program's --project always, and --default-effect no-change on class B,
      so the live autonomy sweep never dispatches a fired program default as backlog work.
  gate.sh sweep --program P
      1. a class-B packet cc-decide has expired-actioned applies its default to the decision record,
         unless the operator SIGNED a veto for that decision (cc-signoff research:<P>/veto/<D>);
         a cc-decide veto with no valid signature is UNSIGNED and fails the sweep (cc-decide has no
         agent guard, so only a signed veto counts);
      2. a class-C decision past its due date converts: a class-B replacement whose default is the
         reversible option is opened, the old packet is actioned, and the dependent waves are descoped;
      3. a frame-omission known row past its re-sign due date with no newer frame signature applies its
         default (descope, or class-B packets for the omitted rows) and closes, so --requires-gate
         stops refusing without a reopen;
      4. every program packet is checked for --project and (class B) --default-effect no-change.
Every action is a new appended event; nothing is edited in place. Exit 1 on any unsigned veto,
malformed packet or unconvertible decision.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import kit

DECIDE = Path(__file__).resolve().parents[3] / "bin" / "cc-decide"


def cc_decide(*args: str) -> Tuple[int, str, str]:
    exe = os.environ.get("CC_RESEARCH_CC_DECIDE") or str(DECIDE)
    p = subprocess.run(
        ["/bin/bash", exe, *args],
        stdin=subprocess.DEVNULL,
        capture_output=True,
        text=True,
    )
    return p.returncode, p.stdout.strip(), p.stderr.strip()


def packets() -> Dict[str, Dict[str, Any]]:
    rc, out, err = cc_decide("list", "--all", "--json")
    if rc != 0:
        raise kit.KitError(f"cc-decide list failed: {err}")
    return {p["id"]: p for p in json.loads(out or "[]")}


def iso_plus_hours(h: float) -> str:
    import time

    return time.strftime(
        "%Y-%m-%dT%H:%M:%SZ", time.gmtime(kit.parse_iso(kit.now_iso()) + h * 3600)
    )


def program_packets(ctx: Any, decisions: Dict[str, Dict[str, Any]]) -> Dict[str, str]:
    """packet id -> decision id, for every packet the program's decision events ever named."""
    out: Dict[str, str] = {}
    for ev in ctx.jsonl("decisions.jsonl"):
        pid = (ev.get("packet") or {}).get("id")
        if pid:
            out[pid] = ev["id"]
    return out


def packet_problems(ctx: Any) -> List[str]:
    """Program packets filed without the project, or class B without --default-effect no-change."""
    decisions = kit.fold(ctx.jsonl("decisions.jsonl"))
    refs = program_packets(ctx, decisions)
    if not refs:
        return []
    allp = packets()
    repo = ctx.frame.get("deliverable_repo")
    probs = []
    for pid, did in sorted(refs.items()):
        p = allp.get(pid)
        if p is None:
            probs.append(f"MALFORMED PACKET {pid} ({did}): not in cc-decide")
            continue
        if p.get("subject_project") != repo:
            probs.append(
                f"MALFORMED PACKET {pid} ({did}): --project is {p.get('subject_project')!r}, not {repo!r}"
            )
        if p.get("class") == "B" and p.get("default_effect") != "no-change":
            probs.append(
                f"MALFORMED PACKET {pid} ({did}): class B without --default-effect no-change"
            )
    return probs


def open_packet(
    ctx: Any,
    did: str,
    cls: str,
    what: str,
    options: List[str],
    conviction: Optional[int],
    receipt: str,
    default: Optional[str] = None,
    deadline: Optional[str] = None,
) -> str:
    repo = ctx.frame.get("deliverable_repo")
    if not repo:
        raise kit.KitError(
            "frame.json names no deliverable_repo; a program packet needs --project"
        )
    args = [
        "open",
        "--class",
        cls,
        "--what",
        what,
        "--project",
        repo,
        "--receipt",
        receipt,
    ]
    if conviction is not None:
        args += ["--conviction", str(conviction)]
    for o in options:
        args += ["--option", o]
    if cls == "B":
        args += [
            "--default",
            str(default),
            "--deadline",
            str(deadline),
            "--default-effect",
            "no-change",
        ]
    rc, out, err = cc_decide(*args)
    if rc != 0 or not out:
        raise kit.KitError(f"cc-decide open refused for {did}: {err or out}")
    return out.splitlines()[-1].strip()


def cmd_file_packet(a: argparse.Namespace) -> int:
    from gate import make_ctx

    ctx = make_ctx(a.program)
    decisions = kit.fold(ctx.jsonl("decisions.jsonl"))
    if a.decision not in decisions:
        raise kit.KitError(f"no decision {a.decision} in decisions.jsonl")
    if a.cls == "C" and not a.due:
        raise kit.KitError(
            "a class-C program packet needs --due: every operator gate carries a date (§5.6)"
        )
    if a.cls == "B" and not (a.default and a.deadline):
        raise kit.KitError("a class-B program packet needs --default and --deadline")
    pid = open_packet(
        ctx,
        a.decision,
        a.cls,
        a.what,
        a.option or [],
        a.conviction,
        a.receipt,
        a.default,
        a.deadline,
    )
    kit.append_jsonl(
        ctx.records / "decisions.jsonl",
        {
            "id": a.decision,
            "packet": {
                "id": pid,
                "class": a.cls,
                "due": a.deadline if a.cls == "B" else a.due,
            },
        },
    )
    print(
        f"filed {pid} for {a.decision} (class {a.cls}, project {ctx.frame.get('deliverable_repo')})"
    )
    return 0


def reversible_option(d: Dict[str, Any]) -> Optional[str]:
    opts = d.get("options") or []
    for o in opts:
        if o.get("label") == "do-nothing":
            return "do-nothing"
    for o in opts:
        if o.get("reversible"):
            return str(o.get("label"))
    return None


def cmd_sweep(a: argparse.Namespace) -> int:
    import operator_sign
    from gate import make_ctx

    ctx = make_ctx(a.program)
    dec_path = ctx.records / "decisions.jsonl"
    decisions = kit.fold(ctx.jsonl("decisions.jsonl"))
    allp = packets()
    now = kit.now_iso()
    bad = 0
    prem = kit.fold(ctx.jsonl("premises.jsonl"))
    probes = kit.fold(ctx.jsonl("probes.jsonl"))
    for did, d in sorted(decisions.items()):
        pk = d.get("packet") or {}
        p = allp.get(str(pk.get("id")))
        if not p:
            continue
        signed_veto = operator_sign.latest_valid(ctx.slug, "veto", did)
        conv = kit.conviction(d, prem, probes)
        if p.get("status") == "vetoed" and not signed_veto:
            print(
                f"UNSIGNED VETO {p['id']} on {did}: a cc-decide veto counts only with "
                f"`cc-signoff research:{ctx.slug}/veto/{did}` in the operator's terminal"
            )
            bad += 1
        elif (
            p.get("class") == "B"
            and p.get("status") == "expired-actioned"
            and d.get("status") != "ruled"
        ):
            if signed_veto:
                print(f"vetoed-by-operator {did}: default of {p['id']} not applied")
                if not d.get("vetoed_by_operator"):
                    kit.append_jsonl(
                        dec_path,
                        {"id": did, "vetoed_by_operator": signed_veto.get("at_iso")},
                    )
                continue
            kit.append_jsonl(
                dec_path,
                {
                    "id": did,
                    "status": "ruled",
                    "ruled_by": "packet-default",
                    "chosen": p.get("default_if_no_veto"),
                    "decided_by_default_at": conv,
                    "receipt": f"cc-decide {p['id']} expired-actioned",
                },
            )
            print(
                f"applied default of {p['id']} to {did}: {p.get('default_if_no_veto')} (decided by default at {conv}%)"
            )
        elif (
            p.get("class") == "C"
            and p.get("status") == "open"
            and pk.get("due")
            and pk["due"] < now
        ):
            rev = reversible_option(d)
            if rev is None:
                print(
                    f"CANNOT CONVERT {did}: class C past due {pk['due']} with no reversible option to default to"
                )
                bad += 1
                continue
            if conv is None:
                print(
                    f"CANNOT CONVERT {did}: a value call with no factual premise has no computed conviction"
                )
                bad += 1
                continue
            new = open_packet(
                ctx,
                did,
                "B",
                f"{d.get('question') or did} (class C past its due date "
                f"{pk['due']}; converted, default = the reversible option)",
                [
                    f"{o.get('label')}::{o.get('outcome', '')}"
                    for o in d.get("options") or []
                ],
                min(conv, 90),
                str(dec_path),
                rev,
                iso_plus_hours(kit.CAPS["class_b_default_hours"]),
            )
            cc_decide("action", p["id"], "--evidence", f"converted to class B {new}")
            kit.append_jsonl(
                dec_path,
                {
                    "id": did,
                    "packet": {
                        "id": new,
                        "class": "B",
                        "due": iso_plus_hours(kit.CAPS["class_b_default_hours"]),
                    },
                    "converted_from": p["id"],
                    "descoped_waves": d.get("blocks_waves") or [],
                },
            )
            print(
                f"converted {did}: class C {p['id']} past due -> class B {new} (default {rev}); "
                f"descoped waves {d.get('blocks_waves') or []}"
            )
    frame_sigs = [
        r
        for r in operator_sign.research_records(ctx.slug, "frame")
        if r["_verdict"] == "valid"
    ]
    from gate_rows_a import known_rows

    for kr in known_rows(ctx):
        if (
            kr.get("kind") != "frame-omission"
            or kr.get("status", "open") != "open"
            or not kr.get("resign_due")
        ):
            continue
        if kr["resign_due"] >= now or any(
            r.get("at_iso", "") > kr["resign_due"] for r in frame_sigs
        ):
            continue
        ev: Dict[str, Any] = {
            "id": kr["id"],
            "status": "closed",
            "closed_by": "default",
            "at": now,
        }
        if kr.get("default") == "class-b":
            ev["packets"] = [
                open_packet(
                    ctx,
                    kr["id"],
                    "B",
                    f"frame omission {kr['id']}: add rows "
                    f"{', '.join(kr.get('names_rows') or [])} (re-sign overdue)",
                    [
                        "descope::the dependent waves do not build",
                        "add::the rows are added",
                    ],
                    # An omitted row has no evidence tally, so its computed conviction is 0; the
                    # receipt names the frame record the omission was found against.
                    0,
                    str(ctx.records / "frame.json"),
                    "descope",
                    iso_plus_hours(kit.CAPS["class_b_default_hours"]),
                )
            ]
        else:
            ev["descoped_waves"] = kr.get("blocks_waves") or []
        kit.append_jsonl(ctx.records / "known_rows.jsonl", ev)
        print(
            f"closed known row {kr['id']} by its default ({kr.get('default', 'descope')})"
        )
    for prob in packet_problems(ctx):
        print(prob)
        bad += 1
    return 1 if bad else 0


def add_verbs(sub: Any) -> None:
    p = sub.add_parser("file-packet")
    p.add_argument("--program", required=True)
    p.add_argument("--decision", required=True)
    p.add_argument("--class", dest="cls", required=True, choices=("B", "C"))
    p.add_argument("--what", required=True)
    p.add_argument("--option", action="append")
    p.add_argument("--conviction", type=int)
    p.add_argument("--receipt", required=True)
    p.add_argument("--default")
    p.add_argument("--deadline")
    p.add_argument("--due")
    p.set_defaults(fn=cmd_file_packet)
    p = sub.add_parser("sweep")
    p.add_argument("--program", required=True)
    p.set_defaults(fn=cmd_sweep)
