#!/usr/bin/env python3
"""Map bare hook-deny reason strings (seen in tool_result error snippets) to the file that emits them.

Searches claude-infrastructure hooks/, bin/, scripts/ (read-only) for a literal stem of each message.
Prints: stem -> matching files (excluding tests). Used to name the hook in measure/tool-errors.md.
"""

import os, sys

ROOT = "/Users/chrisren/Development/claude-infrastructure"
STEMS = [
    "DUPLICATE WORKER",
    "MACHINE CAPACITY",
    "git identity write with no target",
    "curl-gate",
    "Dangerous command pattern blocked",
    "git add -f blocked",
    "Pattern kill blocked",
    "Empty-selector kill blocked",
    "is LIVE in this session",
    "Commit in the SHARED CHECKOUT",
    "DDL blocked",
    "--no-verify blocked",
    "git commit -n blocked",
    "assignment blocked",
    "Ungated advance of the SHARED",
    "Subagents should return findings",
    "one paragraph of this body",
    "was blocked by a deny rule",
    "probe-ask-from-hook",
    "teammate protocol frame",
    "Blocked: sleep",
    "not a teammate protocol",
    "capacity-admit",
    "Worktree-UNSCOPED kill",
    "all-expansion target blocked",
    "bypasses migration history",
    "Refusing to write",
]
hits = {s: [] for s in STEMS}
for sub in ("hooks", "bin", "scripts"):
    for dp, dn, fn in os.walk(os.path.join(ROOT, sub)):
        dn[:] = [
            d for d in dn if d not in ("node_modules", ".git", "tests", "fixtures")
        ]
        for f in fn:
            if f.endswith((".bats", ".md", ".jsonl", ".json", ".log")):
                continue
            p = os.path.join(dp, f)
            try:
                if os.path.getsize(p) > 3_000_000:
                    continue
                t = open(p, "r", errors="ignore").read()
            except Exception:
                continue
            for s in STEMS:
                if s in t:
                    hits[s].append(os.path.relpath(p, ROOT))
for s in STEMS:
    print(f"{s!r:45s} {len(hits[s]):3d} {', '.join(sorted(hits[s])[:4])}")
