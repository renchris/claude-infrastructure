#!/usr/bin/env python3
"""Completeness check for a triage wave: every row in a slice carries one verdict.

Format-tolerant on purpose — each agent wrote its verdict lines slightly differently
(backticked id, bare id, padded verb). The contract is the SET of ids and their
verdicts, not the punctuation, so parse for that and nothing else.

── WHY THIS FILE IS TRACKED NOW (2026-08-12, W2 of BACKLOG_SELF_DRAINING) ──────────
Promoted with its siblings. It is the gate that makes prune.py safe to run: prune
closes whatever the reports adjudicated, so the question "did every row a slice was
handed actually GET a verdict" has to be answerable BEFORE the closer runs. A missing
verdict is silent otherwise — the row simply is not in the table, and a closer that
only reads the table cannot tell "kept" from "never looked at".

It also WRITES verdicts.json, which is link.py's legacy replay input, so the order
within a triage wave is: verify.py (completeness + emit verdicts.json) → prune.py
(close PRUNE/MERGE) → link.py --dir (join the survivors). The slice map lives here
because it describes one wave's decomposition; a future wave passes its own via
--slices rather than editing this table.

rc 0 = every delivered slice is complete · rc 1 = a gap (missing or extra ids).
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from collections import Counter

# Kept BYTE-FOR-BYTE in step with prune.py's LINE (including the optional leading pipe added
# 2026-08-12): this file is the completeness gate for that closer, so a row this parser can see and
# that one cannot — or the reverse — makes the gate certify a population the closer never reads
# (memory: sibling-auditors-must-share-the-state-model).
VERDICT = re.compile(
    r"^\s*\|?\s*\**`?([0-9a-f]{12})`?\**\s*\|\s*\**(PRUNE|UPDATE|KEEP|MERGE)\**", re.M
)

# The 2026-08-09 wave's decomposition: slice → the cluster files it was handed.
SLICES: dict[str, list[str]] = {
    "landgate": ["C-landgate"],
    "dispatch": ["C-dispatch"],
    "panes": ["C-panes"],
    "testcorpus": ["C-testcorpus"],
    "session": ["C-session", "C-worktree"],
    "reso": ["P-reso"],
    "docclf": ["P-docclf"],
    "accounts": ["C-accounts"],
    "memhooks": ["C-memory", "C-hooks", "C-comms"],
    "tail": ["C-misc", "C-machine", "C-docs", "P-other"],
}


def main() -> int:
    ap = argparse.ArgumentParser(add_help=True, description=__doc__)
    ap.add_argument(
        "--dir", required=True, help="triage directory (OUT-*.md + cluster-*.json)"
    )
    ap.add_argument("--slices", default=None, help="JSON file overriding the slice map")
    ap.add_argument(
        "--emit",
        default="verdicts.json",
        help="filename (inside --dir) for the id → [slice, verdict] map",
    )
    args = ap.parse_args()

    if not os.path.isdir(args.dir):
        print(f"verify.py: no such triage directory: {args.dir}", file=sys.stderr)
        return 2
    slices = SLICES
    if args.slices:
        with open(args.slices) as fh:
            slices = json.load(fh)

    grand: Counter[str] = Counter()
    all_ok = True
    seen_all: dict[str, list[str]] = {}
    total_expected = 0

    for name, clusters in slices.items():
        out = os.path.join(args.dir, f"OUT-{name}.md")
        expected: set[str] = set()
        for c in clusters:
            cpath = os.path.join(args.dir, f"cluster-{c}.json")
            if not os.path.exists(cpath):
                continue
            with open(cpath) as fh:
                expected |= {i["id"] for i in json.load(fh)}
        total_expected += len(expected)
        if not os.path.exists(out):
            print(f"{name:11s} … not delivered yet ({len(expected)} rows)")
            all_ok = False
            continue
        with open(out) as fh:
            found = dict(VERDICT.findall(fh.read()))
        missing = expected - set(found)
        extra = set(found) - expected
        counts = Counter(found[i] for i in expected & set(found))
        grand.update(counts)
        for i, v in found.items():
            seen_all[i] = [name, v]
        if missing or extra:
            all_ok = False
        print(
            f"{name:11s} {'OK ' if not (missing or extra) else 'GAP'} "
            f"{len(expected):3d} rows | "
            + " ".join(f"{k}={counts[k]}" for k in ("PRUNE", "UPDATE", "KEEP", "MERGE"))
            + (f"  MISSING={sorted(missing)}" if missing else "")
            + (f"  EXTRA={sorted(extra)}" if extra else "")
        )

    print(
        f"\nTOTAL adjudicated: {sum(grand.values())} / {total_expected} — "
        + " ".join(f"{k}={grand[k]}" for k in ("PRUNE", "UPDATE", "KEEP", "MERGE"))
    )
    with open(os.path.join(args.dir, args.emit), "w") as fh:
        json.dump(seen_all, fh, indent=1)
    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main())
