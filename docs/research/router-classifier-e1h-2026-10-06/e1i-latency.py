#!/usr/bin/env python3
"""Wave E1i's warm latency check (RULE 1's latency clause, carried into E1i): the first 100 rows of the
E1h fresh tuning file (`tuning-v4.jsonl`, file order, fixed before any call) through the router's
`classify` verb exactly as `heldout.py evaluate` calls it (the command on stdin, a 9 s limit), with
the resident classifier at CC_RESEARCH_WARM_SOCK. PASS: fallback <= 0.03 and p90 wall <= 7.5 s.

  e1i-latency.py ROUTER_CMD OUT.json [--n N]

Wave E1j: --n sets how many rows (default 100, E1i's), and each call records its start time `t`, so a
call can be joined to the router's own trace rows (CC_RESEARCH_CLASSIFY_TRACE, set in ROUTER_CMD).

Wave E1k: --hedge-ab alternates the router's cold hedge by row (even rows CC_RESEARCH_HEDGE=1, odd rows
=0), so both arms see the same load (RULE E1k in docs/plans/RESEARCH_PROGRAM_BUILD.md); each call records
its arm (`hedge`) and the 1-min load at its start (`load0`) as well as at its end (`load`).

Reads tuning data only (never a sealed set, never tuning-v2.jsonl); writes per-call wall time, label
and load to OUT.json and prints a summary; never a prompt.
"""

import json
import os
import subprocess
import sys
import time
from pathlib import Path

H = Path.home() / ".claude/autonomy/research/router-heldout"
N, LIMIT_S, MAX_FALLBACK, MAX_P90 = 100, 9, 0.03, 7.5
ROUTES = (
    "completeness",
    "pushback",
    "concern",
    "new-idea",
    "research-order",
    "work-order",
    "other",
)


def main() -> int:
    router, out = sys.argv[1], Path(sys.argv[2])
    n_rows = int(sys.argv[sys.argv.index("--n") + 1]) if "--n" in sys.argv else N
    ab = "--hedge-ab" in sys.argv
    rows = [json.loads(line) for line in open(H / "tuning-v4.jsonl")][:n_rows]
    calls = []
    for n, r in enumerate(rows):
        env = dict(os.environ)
        if ab:
            env["CC_RESEARCH_HEDGE"] = "1" if n % 2 == 0 else "0"
        load0 = round(os.getloadavg()[0], 1)
        t0 = time.time()
        try:
            p = subprocess.run(
                ["/bin/bash", "-c", router],
                input=r["prompt"],
                capture_output=True,
                text=True,
                timeout=LIMIT_S,
                env=env,
            )
            labels = p.stdout.replace(",", " ").split()
            ok = p.returncode == 0 and len(labels) == 1 and labels[0] in ROUTES
            label = labels[0] if ok else None
        except subprocess.TimeoutExpired:
            label = None
        calls.append(
            {
                "n": n,
                "t": round(t0, 2),
                "stratum": r["stratum"],
                "label": label,
                "wall_s": round(time.time() - t0, 2),
                "load": round(os.getloadavg()[0], 1),
                **({"hedge": n % 2 == 0, "load0": load0} if ab else {}),
            }
        )
    out.write_text(json.dumps({"calls": calls}, indent=1) + "\n")
    walls = sorted(c["wall_s"] for c in calls)
    fell = sum(c["label"] is None for c in calls)
    p90 = walls[int(len(walls) * 0.9)]
    med = walls[len(walls) // 2]
    loads = sorted(c["load"] for c in calls)
    verdict = "PASS" if fell / len(calls) <= MAX_FALLBACK and p90 <= MAX_P90 else "FAIL"
    if ab:  # RULE E1k's verdict is per arm and load band: e1k-ab-report.py gives it
        verdict = "none (two arms; read e1k-ab-report.py)"
    print(
        f"latency: {len(calls)} rows, fallback {fell}/{len(calls)} = {fell / len(calls):.2f} (<= {MAX_FALLBACK}), "
        f"median {med:.2f} s, p90 {p90:.2f} s (<= {MAX_P90}), max {walls[-1]:.2f} s; "
        f"1-min load {loads[0]}-{loads[-1]}, median {loads[len(loads) // 2]}; verdict={verdict}"
    )
    return 0 if ab or verdict == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
