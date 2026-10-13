"""activities.py — the writer of $CC_RESEARCH_HOME/activities.json (REPORT.md §10 item 8).

A contract-listed activity (an escape fix, a frame-delta cycle, a triage batch) is opened by
triage or the kit and lets its tagged calls through the research block: router.open_activities
lists every row of a program whose state is "open". Rows are never deleted; closing one flips its
state to "closed", so the file is the history of what was let through.

  {"activities": [{"program", "id": "ACT-<program>-<n>", "kind", "state": "open|closed"}]}

A front-end-return row also carries area, n_hat, design_holes, opened_at and because.

Python 3.9-safe, standard library only.
"""

from __future__ import annotations

import os
import time
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import kit

# certification-round: opened by the kit itself (gate.sh freeze or cert-activity) while a certifying
# program has a certification round due, and closed by round.sh close once none is (the stop rule or
# R_max), so a lead-dispatched round session runs its round with every other research verb blocked.
# While the last round still owes a settle step (round.py settle_owed: its re-pass, an unheld clause-(g)
# hole, an unnamed cap-round find) the row stays open with `settle_round` set, and the research block
# lets that tag through the round's settle steps only; the last settle verb closes it.
# front-end-return: opened by the kit (gate.sh return-activity) once per area, between one
# certification round's close and the next round's run, when the estimate is well above the design
# point (REPORT.md §6.1, §6.5). Opening one closes the certification-round activity; gate.sh freeze
# closes every one and re-opens the round's. Its tag carries [activity:<id>] Agent/Workflow calls and
# read-only `codex exec` only: the lead fires the area's workers itself, and handoff-fire.sh stays
# denied under every activity tag (operator ruling 2026-10-11).
FRONT_END_RETURN = "front-end-return"
KINDS = (
    "escape",
    "frame-delta",
    "triage-batch",
    "certification-round",
    FRONT_END_RETURN,
)


def path() -> Path:
    return kit.research_home() / "activities.json"


def load() -> Dict[str, Any]:
    data = kit.read_json(path(), {"activities": []})
    if not isinstance(data, dict) or not isinstance(data.get("activities"), list):
        raise kit.KitError(
            f"{path()} does not match the contract (no activities array)"
        )
    return data


class _Lock:
    """A mkdir lock beside the file, so two writers never lose each other's row."""

    def __init__(self) -> None:
        self.dir = path().with_name(path().name + ".lock")

    def __enter__(self) -> "_Lock":
        self.dir.parent.mkdir(parents=True, exist_ok=True)
        for _ in range(100):
            try:
                os.mkdir(self.dir)
                return self
            except FileExistsError:
                time.sleep(0.05)
        raise kit.KitError(
            f"activities lock {self.dir} held for 5 s; remove it if no writer runs"
        )

    def __exit__(self, *exc: Any) -> None:
        os.rmdir(self.dir)


def _check(program: str, kind: str) -> None:
    kit.check_slug(program)
    if kind not in KINDS:
        raise kit.KitError(f"unknown activity kind {kind!r}: one of {', '.join(KINDS)}")


def _append(
    data: Dict[str, Any],
    program: str,
    kind: str,
    extra: Optional[Dict[str, Any]] = None,
) -> str:
    """Append one open row to data and return its id, ACT-<program>-<n>, n one past the highest."""
    prefix = f"ACT-{program}-"
    nums = [
        int(a["id"][len(prefix) :])
        for a in data["activities"]
        if str(a.get("id", "")).startswith(prefix) and a["id"][len(prefix) :].isdigit()
    ]
    aid = f"{prefix}{max(nums, default=0) + 1}"
    row = dict(extra or {})
    row.update({"program": program, "id": aid, "kind": kind, "state": "open"})
    data["activities"].append(row)
    return aid


def open_return(
    program: str, area: str, cap: int, fields: Dict[str, Any]
) -> Tuple[str, List[str], bool]:
    """Open one area's front-end return under one lock: (id, certification-round ids it closed,
    False); or (the open row's id, [], True) when that area's return is already open. An area whose
    return has closed is refused (once per area, §6.5), and so is a new area past `cap` (§6.1)."""
    _check(program, FRONT_END_RETURN)
    with _Lock():
        data = load()
        mine = [
            a
            for a in data["activities"]
            if isinstance(a, dict)
            and a.get("program") == program
            and a.get("kind") == FRONT_END_RETURN
        ]
        same = [a for a in mine if a.get("area") == area]
        if same and same[-1].get("state") == "open":
            return str(same[-1]["id"]), [], True
        if same:
            raise kit.KitError(
                f"area {area!r} already had its front-end return ({same[-1]['id']}): a return "
                "runs once per area (REPORT.md §6.5)"
            )
        used = sorted({str(a.get("area")) for a in mine})
        if len(used) >= cap:
            raise kit.KitError(
                f"{program} has used its {cap} front-end return area(s) ({', '.join(used)}): "
                "REPORT.md §6.1 prices no more"
            )
        # The round's tag must not carry return work: a return edits the plan a round would review.
        shut = []
        for a in _open_of(data, program, "certification-round"):
            a["state"] = "closed"
            shut.append(str(a["id"]))
        aid = _append(data, program, FRONT_END_RETURN, dict(fields, area=area))
        kit.write_json_atomic(path(), data)
    return aid, shut, False


def _open_of(data: Dict[str, Any], program: str, kind: str) -> List[Dict[str, Any]]:
    return [
        a
        for a in data["activities"]
        if isinstance(a, dict)
        and a.get("program") == program
        and a.get("kind") == kind
        and a.get("state") == "open"
    ]


def open_activity(program: str, kind: str) -> str:
    """Open one activity and return its id, ACT-<program>-<n>, n one past the program's highest."""
    _check(program, kind)
    with _Lock():
        data = load()
        aid = _append(data, program, kind)
        kit.write_json_atomic(path(), data)
    return aid


def ensure_open(
    program: str, kind: str, settle_round: Optional[str] = None, create: bool = True
) -> Optional[str]:
    """The id of the program's first open row of this kind, appending one when none is open (None,
    and nothing written, when create is False). Every open row of the kind is left carrying
    `settle_round` (a settle-only certification-round row, round.py settle_owed) or, when it is
    None, none: a plain row."""
    _check(program, kind)
    with _Lock():
        data = load()
        hit = _open_of(data, program, kind)
        if not hit and not create:
            return None
        aid = str(hit[0]["id"]) if hit else _append(data, program, kind)
        changed = not hit
        for a in _open_of(data, program, kind):
            if a.get("settle_round") != settle_round:
                changed = True
                if settle_round is None:
                    a.pop("settle_round", None)
                else:
                    a["settle_round"] = settle_round
        if changed:
            kit.write_json_atomic(path(), data)
    return aid


def open_ids(program: str, kind: str) -> List[str]:
    """The ids of the program's open rows of this kind (a read; no lock)."""
    return [str(a["id"]) for a in _open_of(load(), program, kind)]


def close_kind(program: str, kind: str) -> List[str]:
    """Close every open row of this kind for the program; returns the ids it closed."""
    _check(program, kind)
    with _Lock():
        data = load()
        hit = _open_of(data, program, kind)
        for a in hit:
            a["state"] = "closed"
        if hit:
            kit.write_json_atomic(path(), data)
    return [str(a["id"]) for a in hit]


def close_activity(aid: str) -> None:
    with _Lock():
        data = load()
        hit = [a for a in data["activities"] if a.get("id") == aid]
        if not hit:
            raise kit.KitError(f"no activity {aid!r}")
        for a in hit:
            a["state"] = "closed"
        kit.write_json_atomic(path(), data)
