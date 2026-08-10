#!/usr/bin/env python3
"""Emit (and optionally run) the close commands for PRUNE + MERGE verdicts.

Evidence is the agent's own one-line reason, prefixed so the store records WHY and
by what pass — a close with no reason is indistinguishable from a silent drop, and
`cc-backlog reopen <id> --force` is the undo.

Dry by default. Pass --run to execute.
"""

import glob
import json
import os
import re
import subprocess
import sys

SP = os.path.dirname(os.path.abspath(__file__))
RUN = "--run" in sys.argv

# id | VERDICT | reason...   (tolerant of backticks and bold, as the reports vary)
LINE = re.compile(
    r"^\**`?([0-9a-f]{12})`?\**\s*\|\s*\**(PRUNE|UPDATE|KEEP|MERGE)\**\s*\|\s*(.*)$",
    re.M,
)

# Only touch items the wave actually adjudicated, and only in these two verdicts.
CLOSE = {"PRUNE", "MERGE"}

rows = []
for path in sorted(glob.glob(os.path.join(SP, "OUT-*.md"))):
    slice_name = os.path.basename(path)[4:-3]
    for iid, verdict, reason in LINE.findall(open(path).read()):
        if verdict not in CLOSE:
            continue
        # strip markdown emphasis/backticks and collapse to one clean line
        clean = re.sub(r"[`*]", "", reason).strip()
        clean = re.sub(r"\s+", " ", clean)
        if len(clean) > 300:
            clean = clean[:297] + "..."
        rows.append((iid, verdict, slice_name, clean))

seen = set()
uniq = []
for r in rows:
    if r[0] in seen:
        continue
    seen.add(r[0])
    uniq.append(r)

print(
    f"{len(uniq)} items to close  ({sum(1 for r in uniq if r[1] == 'PRUNE')} PRUNE, "
    f"{sum(1 for r in uniq if r[1] == 'MERGE')} MERGE)"
)

if not RUN:
    for iid, verdict, sl, reason in uniq[:5]:
        print(f"  [{verdict}] {iid}  {reason[:110]}")
    print("  … dry run; pass --run to execute")
    sys.exit(0)

ok = fail = 0
log = open(os.path.join(SP, "prune-log.txt"), "w")
for iid, verdict, sl, reason in uniq:
    ev = f"backlog-consolidation 2026-08-09 [{verdict}/{sl}]: {reason}"
    p = subprocess.run(
        ["cc-backlog", "done", iid, "--evidence", ev],
        capture_output=True,
        text=True,
    )
    if p.returncode == 0:
        ok += 1
    else:
        fail += 1
        log.write(f"FAIL rc={p.returncode} {iid}: {p.stderr.strip()[:200]}\n")
    log.write(
        f"{'OK  ' if p.returncode == 0 else 'FAIL'} {iid} {verdict} {reason[:120]}\n"
    )
log.close()
print(f"closed={ok} failed={fail}  (detail: scratchpad/prune-log.txt)")
