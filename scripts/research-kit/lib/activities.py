"""activities.py — the writer of $CC_RESEARCH_HOME/activities.json (REPORT.md §10 item 8).

A contract-listed activity (an escape fix, a frame-delta cycle, a triage batch) is opened by
triage or the kit and lets its tagged calls through the research block: router.open_activities
lists every row of a program whose state is "open". Rows are never deleted; closing one flips its
state to "closed", so the file is the history of what was let through.

  {"activities": [{"program", "id": "ACT-<program>-<n>", "kind", "state": "open|closed"}]}

Python 3.9-safe, standard library only.
"""

from __future__ import annotations

import os
import time
from pathlib import Path
from typing import Any, Dict, List

import kit

# certification-round: opened by the kit itself (gate.sh freeze or cert-activity) while a certifying
# program has a certification round due, and closed by round.sh close once none is (the stop rule or
# R_max), so a lead-dispatched round session runs its round with every other research verb blocked.
KINDS = ("escape", "frame-delta", "triage-batch", "certification-round")


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


def _append(data: Dict[str, Any], program: str, kind: str) -> str:
    """Append one open row to data and return its id, ACT-<program>-<n>, n one past the highest."""
    prefix = f"ACT-{program}-"
    nums = [
        int(a["id"][len(prefix) :])
        for a in data["activities"]
        if str(a.get("id", "")).startswith(prefix) and a["id"][len(prefix) :].isdigit()
    ]
    aid = f"{prefix}{max(nums, default=0) + 1}"
    data["activities"].append(
        {"program": program, "id": aid, "kind": kind, "state": "open"}
    )
    return aid


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


def ensure_open(program: str, kind: str) -> str:
    """The id of the program's first open row of this kind, appending one only when none is open."""
    _check(program, kind)
    with _Lock():
        data = load()
        hit = _open_of(data, program, kind)
        if hit:
            return str(hit[0]["id"])
        aid = _append(data, program, kind)
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
