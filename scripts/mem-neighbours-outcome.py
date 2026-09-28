#!/usr/bin/env python3
"""mem-neighbours-outcome.py — what happened after each new-topic neighbour advisory (nightly).

hooks/backup-before-write.sh logs a `fired` row to ~/.claude/state/mem-neighbours.jsonl each time
it shows a new memory topic or lesson its two nearest existing files (truememory-2026-09-27.md
§3.10, acceptance criterion 4). The advice reaches the model AFTER the write, and deleting the new
file needs an rm that is not auto-allowed, so nothing at write time observes whether a duplicate was
actually resolved. This does, from `stat` and the rows alone. For every fired row older than 24 h,
with X the new file and A its top neighbour:

  superseded     X or A carries `superseded_by` in its frontmatter
  merged         X is gone and A was modified after the fire
  unresolved     X still exists, A is unmodified since the fire, and the pair scored at least
                 CC_MEM_NEIGH_DUP_SCORE — a likely duplicate left behind
  kept_distinct  everything else

The unresolved pairs go to ~/.claude/state/mem-neighbours-unresolved.txt, which compact-memory
reads in its orphan sweep. The last line is `OUTCOME-VERDICT ok|unresolved-high|unknown`:
unresolved-high when more than half of at least 4 classified rows are unresolved (the trigger for
the deny-once treatment arm in §3.10), unknown below 4. Exit 0 on every verdict: this is a report
for compact-memory, not a page.
"""

from __future__ import annotations

import json
import math
import os
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Any

DAY = 86400
HEAD_BYTES = 1536


def _home_state(name: str) -> Path:
    return Path(os.environ.get("HOME", "~")).expanduser() / ".claude" / "state" / name


def _epoch(ts: str) -> float | None:
    try:
        return datetime.fromisoformat(ts.replace("Z", "+00:00")).timestamp()
    except (AttributeError, ValueError):
        return None


def _mtime(p: str) -> float | None:
    try:
        return os.stat(p).st_mtime
    except OSError:
        return None


def superseded(p: str) -> bool:
    try:
        with open(p, "rb") as fh:
            head = fh.read(HEAD_BYTES).decode("utf-8", "replace")
    except OSError:
        return False
    if not head.startswith("---"):
        return False
    end = head.find("\n---", 3)
    front = head[3:end] if end != -1 else head[3:]
    return any(line.strip().startswith("superseded_by:") for line in front.splitlines())


def load_fired(log: Path) -> list[dict[str, Any]]:
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
        top = r.get("top") if isinstance(r, dict) else None
        if r.get("disposition") == "fired" and isinstance(top, list) and top:
            rows.append(r)
    return rows


def top1(row: dict[str, Any]) -> tuple[str, float]:
    first = row["top"][0] if isinstance(row["top"][0], dict) else {}
    try:
        return str(first.get("path", "")), float(first.get("score", 0.0))
    except (TypeError, ValueError):
        return str(first.get("path", "")), 0.0


def top_quartile(scores: list[float]) -> float:
    s = sorted(scores)
    return s[max(0, math.ceil(0.75 * len(s)) - 1)] if s else 1.0


def classify(row: dict[str, Any], fired_at: float, dup: float) -> str:
    x = str(row.get("path", ""))
    a, score = top1(row)
    if superseded(x) or superseded(a):
        return "superseded"
    x_exists = os.path.exists(x)
    a_m = _mtime(a)
    if not x_exists and a_m is not None and a_m > fired_at:
        return "merged"
    if x_exists and a_m is not None and a_m <= fired_at and score >= dup:
        return "unresolved"
    return "kept_distinct"


def main() -> int:
    log = Path(
        os.environ.get("CC_MEM_NEIGH_LOG", str(_home_state("mem-neighbours.jsonl")))
    )
    out = Path(
        os.environ.get(
            "CC_MEM_NEIGH_UNRESOLVED", str(_home_state("mem-neighbours-unresolved.txt"))
        )
    )
    now = float(os.environ.get("CC_MEM_NEIGH_NOW", str(time.time())))
    fired = load_fired(log)
    # ESTIMATED default: the top-quartile top-1 score of every fired row. No measured duplicate
    # threshold exists (§3.10 deliberately ships none), so "a likely duplicate" is relative to what
    # this store's own advisories have scored; set CC_MEM_NEIGH_DUP_SCORE once one is measured.
    env_dup = os.environ.get("CC_MEM_NEIGH_DUP_SCORE", "")
    try:
        dup = float(env_dup) if env_dup else top_quartile([top1(r)[1] for r in fired])
    except ValueError:
        dup = 1.0
    latest: dict[str, tuple[float, dict[str, Any]]] = {}
    for r in fired:
        at = _epoch(str(r.get("ts", "")))
        if at is None or now - at < DAY:
            continue
        key = str(r.get("path", ""))
        if key not in latest or at > latest[key][0]:
            latest[key] = (at, r)
    counts = {"kept_distinct": 0, "merged": 0, "superseded": 0, "unresolved": 0}
    pairs: list[str] = []
    for at, r in latest.values():
        c = classify(r, at, dup)
        counts[c] += 1
        if c == "unresolved":
            a, score = top1(r)
            pairs.append(f"{r.get('path')}\t{a}\t{score}\t{r.get('ts')}")
    try:
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text("".join(p + "\n" for p in sorted(pairs)), encoding="utf-8")
    except OSError as e:
        print(f"mem-neighbours-outcome: could not write {out}: {e}", file=sys.stderr)
    n = sum(counts.values())
    verdict = (
        "unknown"
        if n < 4
        else ("unresolved-high" if counts["unresolved"] / n > 0.5 else "ok")
    )
    print(
        f"mem-neighbours-outcome: classified={n} "
        + " ".join(f"{k}={v}" for k, v in counts.items())
        + f" dup_score={dup:.3f}{'' if env_dup else ' (ESTIMATED top quartile)'} unresolved_file={out}"
    )
    print(f"OUTCOME-VERDICT {verdict}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
