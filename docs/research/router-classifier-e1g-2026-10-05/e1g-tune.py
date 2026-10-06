#!/usr/bin/env python3
"""Measure the fast-plus-careful classifier on the v1 TUNING set (never a sealed set), for wave E1g's
pre-registered pass rule (docs/plans/RESEARCH_PROGRAM_BUILD.md, wave E1g).

  e1g-tune.py REPS OUT.json

One call per tuning row and repeat, one after another, each made the way `heldout.py evaluate` makes
it: `/bin/bash -c "python3 <this branch>/scripts/research-kit/router.py classify"` with the prompt
on stdin, stopped at 9 s of THIS clock (heldout.ROUTER_TIMEOUT_S), so a label that arrives late is a
fallback here exactly as it is on a sealed read. The router's own trace (CC_RESEARCH_CLASSIFY_TRACE)
says which call and which path answered. Set CC_RESEARCH_WARM_SOCK to the in-session daemon's socket
before running. Results are keyed by tuning row index; no prompt text is written.
"""

import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
ROUTER = REPO / "scripts/research-kit/router.py"
H = Path.home() / ".claude/autonomy/research/router-heldout"
ROUTES = (
    "completeness",
    "pushback",
    "concern",
    "new-idea",
    "research-order",
    "work-order",
    "other",
)
LIMIT_S = 9  # heldout.ROUTER_TIMEOUT_S


def call(prompt: str) -> dict:
    fd, trace = tempfile.mkstemp(prefix="e1g-trace-")
    os.close(fd)
    load = os.getloadavg()[0]
    t0 = time.time()
    try:
        p = subprocess.run(
            ["/bin/bash", "-c", f"python3 {ROUTER} classify"],
            input=prompt,
            capture_output=True,
            text=True,
            timeout=LIMIT_S,
            env=dict(os.environ, CC_RESEARCH_CLASSIFY_TRACE=trace),
        )
        words = p.stdout.replace(",", " ").split()
        ok = p.returncode == 0 and len(words) == 1 and words[0] in ROUTES
        lab = words[0] if ok else "INVALID"
    except subprocess.TimeoutExpired:
        lab = "TIMEOUT"
    wall = round(time.time() - t0, 2)
    why = ""
    try:
        rows = [json.loads(line) for line in open(trace)]
        why = rows[-1]["why"] if rows else ""
    except (OSError, ValueError):
        pass
    os.unlink(trace)
    return {"label": lab, "wall_s": wall, "load": round(load, 1), "why": why}


def main() -> None:
    reps, out = int(sys.argv[1]), Path(sys.argv[2])
    rows = [json.loads(line) for line in open(H / "tuning.jsonl")]
    res: dict = {}
    for rep in range(reps):
        for k, row in enumerate(rows):
            r = call(row["prompt"])
            res.setdefault(str(k), []).append(r)
            print(rep, k, r["label"], r["wall_s"], r["load"], r["why"][:70], flush=True)
        out.write_text(
            json.dumps(
                {"reps_done": rep + 1, "rows": len(rows), "arms": {"union": res}},
                sort_keys=True,
            )
        )
    print(f"{reps} repeat(s) x {len(rows)} tuning row(s) -> {out}")


if __name__ == "__main__":
    main()
