#!/usr/bin/env python3
"""episodic-cue-outcome.py — was each episodic cue followed by a claude-search? (nightly, read-only)

hooks/lib/episodic_cue.sh appends one row to ~/.claude/state/episodic-cue.jsonl each time the memory
nudge carries an EPISODIC CUE (truememory-2026-09-27.md §3.18, item #18). The cue is PROVISIONAL:
research §5.17 (#35) found no gain for push consumers, so it stays only if the cue is acted on. This
measures that. For every fire older than 24 h it finds the session's transcript under every account
root (<root>/projects/*/<sid>.jsonl and <root>/projects/*/<sid>/subagents/*.jsonl) and classes it:

  used            a Bash tool call whose command contains `claude-search`, timestamped after the fire
  unused          a transcript exists and holds no such call
  no-transcript   no transcript for the session id was found (reported as unresolved)

The last line is `EPISODIC-VERDICT fires=N used=U unused=X unresolved=Z`. Exit 0 on every verdict:
this is the adoption log's reader, not a page. It writes nothing.

Seams: CC_EPISODIC_LOG (the fire log), CC_EPISODIC_ROOTS (colon-separated account roots; default
every ~/.claude* dir holding projects/), CC_EPISODIC_NOW (epoch seconds).
"""

from __future__ import annotations

import json
import os
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Any

DAY = 86400


def _epoch(ts: object) -> float | None:
    if not isinstance(ts, str):
        return None
    try:
        return datetime.fromisoformat(ts.replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None


def load_fires(log: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    try:
        lines = log.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return rows
    for line in lines:
        try:
            r = json.loads(line)
        except ValueError:
            continue
        if isinstance(r, dict) and isinstance(r.get("sid"), str) and r.get("sid"):
            rows.append(r)
    return rows


def account_roots() -> list[Path]:
    env = os.environ.get("CC_EPISODIC_ROOTS", "")
    if env:
        return [Path(p) for p in env.split(":") if p]
    home = Path(os.environ.get("HOME", "~")).expanduser()
    return sorted(p for p in home.glob(".claude*") if (p / "projects").is_dir())


def transcripts(sid: str, roots: list[Path]) -> list[Path]:
    found: list[Path] = []
    for root in roots:
        proj = root / "projects"
        found.extend(proj.glob(f"*/{sid}.jsonl"))
        found.extend(proj.glob(f"*/{sid}/subagents/*.jsonl"))
    return found


def _searched_after(path: Path, fired_at: float) -> bool:
    try:
        fh = path.open(encoding="utf-8", errors="replace")
    except OSError:
        return False
    with fh:
        for line in fh:
            if "claude-search" not in line:
                continue
            try:
                rec = json.loads(line)
            except ValueError:
                continue
            if not isinstance(rec, dict):
                continue
            at = _epoch(rec.get("timestamp"))
            if at is None or at < fired_at:
                continue
            msg = rec.get("message")
            content = msg.get("content") if isinstance(msg, dict) else None
            if not isinstance(content, list):
                continue
            for block in content:
                if not isinstance(block, dict) or block.get("type") != "tool_use":
                    continue
                if block.get("name") != "Bash":
                    continue
                inp = block.get("input")
                cmd = inp.get("command") if isinstance(inp, dict) else None
                if isinstance(cmd, str) and "claude-search" in cmd:
                    return True
    return False


def classify(row: dict[str, Any], fired_at: float, roots: list[Path]) -> str:
    paths = transcripts(str(row["sid"]), roots)
    if not paths:
        return "no-transcript"
    return "used" if any(_searched_after(p, fired_at) for p in paths) else "unused"


def main() -> int:
    home = Path(os.environ.get("HOME", "~")).expanduser()
    log = Path(
        os.environ.get(
            "CC_EPISODIC_LOG", str(home / ".claude" / "state" / "episodic-cue.jsonl")
        )
    )
    try:
        now = float(os.environ.get("CC_EPISODIC_NOW", "") or time.time())
    except ValueError:
        now = time.time()
    roots = account_roots()
    counts = {"used": 0, "unused": 0, "no-transcript": 0}
    fires = 0
    for r in load_fires(log):
        at = _epoch(r.get("ts"))
        if at is None or now - at < DAY:
            continue
        fires += 1
        counts[classify(r, at, roots)] += 1
    print(
        f"episodic-cue-outcome: log={log} roots={len(roots)} "
        + " ".join(f"{k}={v}" for k, v in counts.items())
    )
    print(
        f"EPISODIC-VERDICT fires={fires} used={counts['used']} "
        f"unused={counts['unused']} unresolved={counts['no-transcript']}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
