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
from typing import Any, Dict

import kit

KINDS = ("escape", "frame-delta", "triage-batch")


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


def open_activity(program: str, kind: str) -> str:
    """Open one activity and return its id, ACT-<program>-<n>, n one past the program's highest."""
    kit.check_slug(program)
    if kind not in KINDS:
        raise kit.KitError(f"unknown activity kind {kind!r}: one of {', '.join(KINDS)}")
    with _Lock():
        data = load()
        prefix = f"ACT-{program}-"
        nums = [
            int(a["id"][len(prefix) :])
            for a in data["activities"]
            if str(a.get("id", "")).startswith(prefix)
            and a["id"][len(prefix) :].isdigit()
        ]
        aid = f"{prefix}{max(nums, default=0) + 1}"
        data["activities"].append(
            {"program": program, "id": aid, "kind": kind, "state": "open"}
        )
        kit.write_json_atomic(path(), data)
    return aid


def close_activity(aid: str) -> None:
    with _Lock():
        data = load()
        hit = [a for a in data["activities"] if a.get("id") == aid]
        if not hit:
            raise kit.KitError(f"no activity {aid!r}")
        for a in hit:
            a["state"] = "closed"
        kit.write_json_atomic(path(), data)
