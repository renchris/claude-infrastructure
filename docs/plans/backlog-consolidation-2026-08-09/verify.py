#!/usr/bin/env python3
"""Completeness check: every item in a slice must carry exactly one verdict.

Format-tolerant on purpose — each agent wrote its verdict lines slightly
differently (backticked id, bare id, padded verb). The contract is the SET of
ids and their verdicts, not the punctuation, so parse for that and nothing else.
"""

import glob
import json
import os
import re
import sys
from collections import Counter

SP = os.path.dirname(os.path.abspath(__file__))

SLICES = {
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

VERDICT = re.compile(
    r"^\**`?([0-9a-f]{12})`?\**\s*\|\s*\**(PRUNE|UPDATE|KEEP|MERGE)\**", re.M
)

grand = Counter()
all_ok = True
seen_all = {}

for name, clusters in SLICES.items():
    out = os.path.join(SP, f"OUT-{name}.md")
    if not os.path.exists(out):
        print(f"{name:11s} … not delivered yet")
        all_ok = False
        continue
    expected = set()
    for c in clusters:
        expected |= {
            i["id"] for i in json.load(open(os.path.join(SP, f"cluster-{c}.json")))
        }
    found = dict(VERDICT.findall(open(out).read()))
    missing = expected - set(found)
    extra = set(found) - expected
    counts = Counter(found[i] for i in expected & set(found))
    grand.update(counts)
    for i, v in found.items():
        seen_all[i] = (name, v)
    flag = "OK " if not missing and not extra else "GAP"
    if missing or extra:
        all_ok = False
    print(
        f"{name:11s} {flag} {len(expected):3d} items | "
        + " ".join(f"{k}={counts[k]}" for k in ("PRUNE", "UPDATE", "KEEP", "MERGE"))
        + (f"  MISSING={sorted(missing)}" if missing else "")
        + (f"  EXTRA={sorted(extra)}" if extra else "")
    )

print(
    f"\nTOTAL adjudicated: {sum(grand.values())} / 460 — "
    + " ".join(f"{k}={grand[k]}" for k in ("PRUNE", "UPDATE", "KEEP", "MERGE"))
)
json.dump(seen_all, open(os.path.join(SP, "verdicts.json"), "w"), indent=1)
sys.exit(0 if all_ok else 1)
