#!/usr/bin/env python3
"""Join each surviving triaged item to its master's condition group.

WHY LINK AND NOT CLOSE. The six masters each drove their own DoD; none of them did
260 items of work. Closing an item because a thematically-related master landed would
be exactly the laundering the worktree brief forbade ("do NOT mark an item done to
reap a directory"). `link` asserts something weaker and TRUE: these items share one
condition, so cc-backlog's CONDITION LEASE admits at most one live claim across the
group. That is what stops N dispatch slots going to N siblings of one root cause —
the operator's original complaint — without lying about completion.

Dry by default; --run to execute.
"""

import json
import os
import subprocess
import sys

D = os.path.dirname(os.path.abspath(__file__))
RUN = "--run" in sys.argv

# triage slice -> the master whose condition owns that root cause
SLICE_TO_CONDITION = {
    "landgate": "master-convergence-deadlock",
    "testcorpus": "master-convergence-deadlock",
    "dispatch": "master-fire-gate",
    "panes": "master-fleet-footprint",
    "session": "master-stranded-work",
    "memhooks": "master-enforcing-store",
    "accounts": "master-account-facts",
    # deliberately unmapped: 'tail' is a mixed bag (misc/machine/docs/other-projects),
    # 'reso' and 'docclf' belong to OTHER repos and have their own masters. Forcing a
    # condition on them would assert a shared root cause that the triage never found.
}

verdicts = json.load(open(os.path.join(D, "verdicts.json")))
live = json.loads(
    subprocess.run(
        ["cc-backlog", "list", "--open", "--json"], capture_output=True, text=True
    ).stdout
    or "[]"
)
open_ids = {i["id"] for i in live if i.get("status") == "open"}
already = {i["id"] for i in live if i.get("condition")}

plan = []
for iid, (slc, verdict) in verdicts.items():
    if verdict not in ("KEEP", "UPDATE"):
        continue  # PRUNE/MERGE were closed in the prune pass
    if iid not in open_ids:
        continue  # already resolved since triage
    if iid in already:
        continue  # carries a condition already — never re-key
    cond = SLICE_TO_CONDITION.get(slc)
    if cond:
        plan.append((iid, cond))

from collections import Counter

print(f"{len(plan)} item(s) to link")
for c, n in sorted(Counter(c for _, c in plan).items()):
    print(f"  {n:4d} -> {c}")
if not RUN:
    print("  … dry run; pass --run to execute")
    sys.exit(0)

ok = fail = 0
log = open(os.path.join(D, "link-log.txt"), "w")
for iid, cond in plan:
    p = subprocess.run(
        ["cc-backlog", "link", iid, "--condition", cond], capture_output=True, text=True
    )
    if p.returncode == 0:
        ok += 1
    else:
        fail += 1
        log.write(f"FAIL rc={p.returncode} {iid} {cond}: {p.stderr.strip()[:160]}\n")
    log.write(f"{'OK  ' if p.returncode == 0 else 'FAIL'} {iid} -> {cond}\n")
log.close()
print(f"linked={ok} failed={fail}  (detail: link-log.txt)")
