#!/usr/bin/env python3
"""norm-share.py — share of recently indexed context_text rows that still carry machinery (nightly).

The session index's context_text is meant to hold what the operator typed. Before the transcript
normaliser (hooks/lib/transcript_norm.py) 64% of it (78 of 122 sampled messages) was Stop-hook
feedback, skill bodies and peer messages (docs/research/truememory-2026-09-27.md §3.14, gap item 3).
This is the output metric that watches the fix: of the sessions rows indexed in the last --hours
with a non-empty context_text, how many contain a non-operator marker.

The window also starts no earlier than the first `session-index:norm` IDL row with norm=lib, i.e.
the first time the lib actually filtered a live extraction. Rows indexed before that were written
by the old filter, so counting them would page every night after a deploy on data the fix never
touched; an alarm that fires on known-stale rows says nothing. The IDL is written by the helpers,
never by this meter. No such row yet ⇒ `verdict=abstain reason=lib-not-live`.

MARKERS is the normaliser's prefix list plus the XML envelopes it drops, kept as a separate copy on
purpose: a meter that imported the list it measures would stop counting whatever the lib stops
dropping. Matching is by substring, because context_text joins many turns.

Output: `NORM-SHARE contaminated=<k> total=<n> pct=<p>` (p rounded UP, so the verdict never rests on
a rounded-down number), then one verdict line:
  verdict=ok                             p <= --threshold
  verdict=regressed                      p > --threshold and n >= --min-rows   (exit 1, the page)
  verdict=abstain reason=too-few-rows    n < --min-rows
  verdict=abstain reason=no-db|unreadable|lib-not-live
Exit 0 on everything except regressed. The DB is opened read-only; this never writes.
"""

from __future__ import annotations

import argparse
import json
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


def first_lib_stamp(idl: str) -> str | None:
    """Earliest ts of a session-index:norm row whose norm is `lib`, or None (missing file included)."""
    first: str | None = None
    try:
        with open(idl, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                if "session-index:norm" not in line:
                    continue
                try:
                    rec = json.loads(line)
                except ValueError:
                    continue
                if not isinstance(rec, dict) or rec.get("hook") != "session-index:norm":
                    continue
                ts = rec.get("ts")
                if (
                    rec.get("norm") == "lib"
                    and isinstance(ts, str)
                    and (first is None or ts < first)
                ):
                    first = ts
    except OSError:
        return None
    return first


def main(argv: list[str]) -> int:
    default_db = os.environ.get("SESSION_INDEX_DB") or os.path.join(
        os.path.expanduser("~"), ".claude", "session-index.db"
    )
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    default_idl = os.environ.get("CC_IDL") or os.path.join(
        os.path.expanduser("~"), ".claude", "autonomy", "idl.jsonl"
    )
    ap.add_argument("--db", default=default_db)
    ap.add_argument("--idl", default=default_idl)
    ap.add_argument("--hours", type=positive_hours, default=24.0)
    ap.add_argument("--threshold", type=int, default=10)
    ap.add_argument("--min-rows", type=int, default=10)
    args = ap.parse_args(argv)

    if not os.path.isfile(args.db):
        print("verdict=abstain reason=no-db")
        return 0
    live_since = first_lib_stamp(args.idl)
    if live_since is None:
        print("verdict=abstain reason=lib-not-live")
        return 0
    cutoff = (datetime.now(timezone.utc) - timedelta(hours=args.hours)).strftime(STAMP)
    cutoff = max(
        cutoff, live_since
    )  # same UTC stamp format on both sides, so text order is time order
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
