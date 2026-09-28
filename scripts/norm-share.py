#!/usr/bin/env python3
"""norm-share.py — share of recently indexed context_text rows that still carry machinery (nightly).

The session index's context_text is meant to hold what the operator typed. Before the transcript
normaliser (hooks/lib/transcript_norm.py) 64% of it (78 of 122 sampled messages) was Stop-hook
feedback, skill bodies and peer messages (docs/research/truememory-2026-09-27.md §3.14, gap item 3).
This is the output metric that watches the fix: of the sessions rows indexed in the last --hours
with a non-empty context_text, how many contain a non-operator marker.

MARKERS is the normaliser's prefix list plus the XML envelopes it drops, kept as a separate copy on
purpose: a meter that imported the list it measures would stop counting whatever the lib stops
dropping. Matching is by substring, because context_text joins many turns.

Output: `NORM-SHARE contaminated=<k> total=<n> pct=<p>` (p rounded UP, so the verdict never rests on
a rounded-down number), then one verdict line:
  verdict=ok                             p <= --threshold
  verdict=regressed                      p > --threshold and n >= --min-rows   (exit 1, the page)
  verdict=abstain reason=too-few-rows    n < --min-rows
  verdict=abstain reason=no-db|unreadable
Exit 0 on everything except regressed. The DB is opened read-only; this never writes.
"""

from __future__ import annotations

import argparse
import os
import sqlite3
import sys
from datetime import datetime, timedelta, timezone

MARKERS = (
    "Stop hook feedback",
    "<teammate-message",
    "<system-reminder",
    "<task-notification",
    "<bash-input>",
    "Base directory for this skill",
    "Another Claude session sent a message",
    "A session-scoped Stop hook",
    "This session is being continued from a previous conversation",
    "Caveat:",
    "[Request interrupted",
    "[Image:",
    "[desk-sweep]",
    "API Error:",
)
# indexed_at is written as UTC `YYYY-MM-DDTHH:MM:SSZ` (every live row, measured 2026-09-28), so a
# cutoff in the same format compares correctly as text.
STAMP = "%Y-%m-%dT%H:%M:%SZ"


def positive_hours(raw: str) -> float:
    try:
        hours = float(raw)
    except ValueError:
        raise argparse.ArgumentTypeError(f"not a number of hours: {raw!r}") from None
    if not hours > 0:
        raise argparse.ArgumentTypeError(f"hours must be > 0: {raw!r}")
    return hours


def main(argv: list[str]) -> int:
    default_db = os.environ.get("SESSION_INDEX_DB") or os.path.join(
        os.path.expanduser("~"), ".claude", "session-index.db"
    )
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--db", default=default_db)
    ap.add_argument("--hours", type=positive_hours, default=24.0)
    ap.add_argument("--threshold", type=int, default=10)
    ap.add_argument("--min-rows", type=int, default=10)
    args = ap.parse_args(argv)

    if not os.path.isfile(args.db):
        print("verdict=abstain reason=no-db")
        return 0
    cutoff = (datetime.now(timezone.utc) - timedelta(hours=args.hours)).strftime(STAMP)
    try:
        conn = sqlite3.connect(f"file:{args.db}?mode=ro", uri=True, timeout=5)
        try:
            rows = conn.execute(
                "SELECT context_text FROM sessions WHERE indexed_at >= ? AND context_text != ''",
                (cutoff,),
            ).fetchall()
        finally:
            conn.close()
    except sqlite3.Error as exc:
        print(f"verdict=abstain reason=unreadable ({type(exc).__name__})")
        return 0

    total = len(rows)
    dirty = sum(1 for (text,) in rows if any(m in text for m in MARKERS))
    pct = (100 * dirty + total - 1) // total if total else 0
    print(f"NORM-SHARE contaminated={dirty} total={total} pct={pct}")
    if total < args.min_rows:
        print("verdict=abstain reason=too-few-rows")
        return 0
    if pct > args.threshold:
        print("verdict=regressed")
        return 1
    print("verdict=ok")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
