#!/usr/bin/env python3
"""postland-table.py <run-log>... — one markdown row per trial cell, joined to its close order.

Reads run.sh's own logs (`kitty <pid> up`, the `rep=… pwA=<n> … fs=<f>` line that opens a trial and
the `crashed=<c> … guard_rc=<g>` line that closes it), asks the unified log for each throwaway pid's
AppKit Window category, classifies it with close-order.py, and joins every trial's A window
(pwA, decimal) to its close row (windowNumber, hex). A trial whose A never closed (a refusal) reads
`not closed`; that is the guard holding, not a missing row.
"""

import collections
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
trials = []
for path in sys.argv[1:]:
    kpid, cur, start = None, None, None
    for line in open(path, errors="replace"):
        m = re.match(r"(\d+\.\d+) kitty (\d+) up", line)
        if m:
            kpid = m.group(2)
            start = start or float(m.group(1)) - 5
            continue
        m = re.match(
            r"(\d+\.\d+) rep=(\d+) (\S+) .*display=(\d+) .*pwA=(\d+) .*fs=(\S+) ", line
        )
        if m:
            start = start or float(m.group(1)) - 60
            cur = {
                "rep": m.group(2),
                "cell": m.group(3),
                "display": m.group(4),
                "pwA": int(m.group(5)),
                "fs": m.group(6),
                "kpid": kpid,
            }
            continue
        m = re.match(r"\d+\.\d+ crashed=(\d+) rc=(\S+) ips=(\S*) guard_rc=(\S+)", line)
        if m and cur:
            cur.update(crashed=m.group(1), guard_rc=m.group(4))
            trials.append(cur)
            cur = None
    if start is None:
        continue
    for t in trials:
        t.setdefault("start", start)

orders = {}
for kpid in sorted({t["kpid"] for t in trials if t.get("kpid")}):
    st = min(t["start"] for t in trials if t["kpid"] == kpid)
    stamp = subprocess.run(
        ["date", "-r", str(int(st)), "+%Y-%m-%d %H:%M:%S"],
        capture_output=True,
        text=True,
    ).stdout.strip()
    log = subprocess.run(
        [
            "/usr/bin/log",
            "show",
            "--start",
            stamp,
            "--style",
            "compact",
            "--predicate",
            f'processID == {kpid} AND category == "Window"',
        ],
        capture_output=True,
        text=True,
    ).stdout
    co = subprocess.run(
        [sys.executable, os.path.join(HERE, "close-order.py")],
        input=log,
        capture_output=True,
        text=True,
    ).stdout
    for row in co.splitlines():
        _ts, num, verdict, delta = row.split("\t")
        orders[(kpid, int(num, 16))] = (verdict, delta)

cells = collections.OrderedDict()
for t in trials:
    key = (t["cell"], t["display"])
    v = orders.get((t["kpid"], t["pwA"]), ("not closed", "-"))
    cells.setdefault(key, []).append((t, v))

print(
    "| Cell (action/ctx/delay/post/panes) | Display | Trials | Crashed | A fullscreen before | Guard rc | Close order of A |"
)
print("|---|---|---|---|---|---|---|")
for (cell, disp), rows in cells.items():
    crashed = sum(int(t.get("crashed", 0)) for t, _ in rows)
    fs = ",".join(t["fs"] for t, _ in rows)
    grc = ",".join(t.get("guard_rc", "-") for t, _ in rows)
    order = "; ".join(f"{v[0]} {v[1]}" if v[1] != "-" else v[0] for _, v in rows)
    print(f"| {cell} | {disp} | {len(rows)} | {crashed} | {fs} | {grc} | {order} |")
