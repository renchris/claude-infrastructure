#!/usr/bin/env python3
"""export-f1.py — write eval/gate/f1/runs.jsonl (one line per scheduled cell) from the run dirs.

Each line: task, rep, arm, account, block, attempts, plus the run's metrics.json (usage, cost, turns,
tool errors, hook blocks, push attempts/refusals, fail class, session id). Transcript paths are kept as
pointers only; no transcript content is copied.
"""

import json, os

H = os.path.dirname(os.path.abspath(__file__))
G = os.environ.get("GATE_ROOT", "/tmp/tokeff-gate")
GATE = os.environ.get("GATE_DIR", os.path.join(os.path.dirname(H), "gate"))
FLAG = os.environ.get("GATE_FLAG", "f1")  # f3/f4 export the same way into their own dir
os.makedirs(f"{GATE}/{FLAG}", exist_ok=True)
sched = json.load(open(f"{G}/schedule.json"))
n = 0
with open(f"{GATE}/{FLAG}/runs.jsonl", "w") as out:
    for c in sorted(sched, key=lambda c: (c["task"], c["rep"])):
        p = f"{G}/runs/{c['task']}/r{c['rep']}/out/metrics.json"
        m = json.load(open(p)) if os.path.exists(p) else {"fail_class": "missing"}
        row = {k: c[k] for k in ("task", "rep", "arm", "block", "attempts", "state")}
        row["account"] = c["account"]
        row.update(
            {k: v for k, v in m.items() if k not in ("task", "run", "arm", "account")}
        )
        out.write(json.dumps(row) + "\n")
        n += 1
print(f"wrote {n} rows to {GATE}/{FLAG}/runs.jsonl")
