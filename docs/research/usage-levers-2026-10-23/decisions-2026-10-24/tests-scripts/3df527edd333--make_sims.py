#!/usr/bin/env python3
"""Write sims.jsonl: for each sampled case, the next tool call I (as that subagent, having just
received the deny text in deny_message.txt) would make. The response pattern per case was decided
by reading cases/NN.md; this script only renders the strings so quoting is exact.
  wrap     timeout 260 bash -c '<original command, inner single quotes escaped>'; echo rc=$?  tool 270000
  inner    the call already had `timeout 500 bash -c`: lower the inner bound to 260, tool 270000
  lower    not a wait loop (retry loop / harness): same command, tool timeout 270000
  seq=N    a bounded for-loop: cut its iteration count to N so it ends inside 260 s, tool 270000
Usage: python3 -I make_sims.py <sample.json> <sims.jsonl>"""

import json, re, sys

S = json.load(open(sys.argv[1]))
PLAN = {
    1: "inner",
    2: "wrap",
    3: "wrap",
    4: "lower",
    5: "lower",
    6: "wrap",
    7: "wrap",
    8: "wrap",
    9: "wrap",
    10: "wrap",
    11: "wrap",
    12: "wrap",
    13: "lower",
    14: "wrap",
    15: "seq=50",
    16: "seq=16",
    17: "wrap-loop-only",
    18: "lower",
    19: "lower",
    20: "wrap",
}


def q(s):
    return "'" + s.replace("'", "'\\''") + "'"


out = open(sys.argv[2], "w")
for n, r in enumerate(S, 1):
    c = r["cmd"]
    p = PLAN[n]
    if p == "inner":
        new = c.replace("timeout 500 bash -c", "timeout 260 bash -c", 1)
    elif p == "wrap":
        new = "timeout 260 bash -c " + q(c) + "; echo rc=$?"
    elif p == "wrap-loop-only":
        # case 17: bound only the wait; the parse runs after it whether or not the wait finished
        loop, rest = c.split("done;", 1)
        new = "timeout 260 bash -c " + q(loop + "done") + "; echo rc=$?;" + rest
    elif p == "lower":
        new = c
    elif p.startswith("seq="):
        k = p.split("=")[1]
        new = re.sub(r"\$\(seq 1 [0-9]+\)", "$(seq 1 %s)" % k, c, count=1)
    out.write(
        json.dumps(
            {
                "n": n,
                "id": r["id"],
                "plan": p,
                "call": {"command": new, "timeout": 270000},
            }
        )
        + "\n"
    )
out.close()
