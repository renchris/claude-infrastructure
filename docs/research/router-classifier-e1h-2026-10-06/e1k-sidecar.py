#!/usr/bin/env python3
"""Wave E1k's 1 Hz sidecar: the warm classifier daemon's children, sampled once a second for the
whole real-load A/B run, so each stall can be traced to a worker still starting or one starved
mid-call (RULE E1k in docs/plans/RESEARCH_PROGRAM_BUILD.md).

  e1k-sidecar.py OUT.jsonl STOP_FILE [--max-s SECONDS]

The daemon is found by its launchd label (com.claude.research-classifier-warm), never by a process
pattern. One row per child per second: {t, daemon, pid, kind, etime_s, cpu_s, rss_kb, pri, state};
`kind` is read from the model on the child's command line (sonnet = fast, haiku = careful), and the
command line itself is not written. Stops when STOP_FILE exists or after --max-s (default 4 h).
"""

import json
import re
import subprocess
import sys
import time
from pathlib import Path
from typing import Optional

LABEL = "com.claude.research-classifier-warm"


def daemon_pid() -> Optional[int]:
    try:
        out = subprocess.run(
            ["launchctl", "list", LABEL], capture_output=True, text=True, timeout=5
        ).stdout
    except (OSError, subprocess.TimeoutExpired):
        return None
    m = re.search(r'"PID"\s*=\s*(\d+);', out)
    return int(m.group(1)) if m else None


def secs(clock: str) -> float:
    """ps etime ([[dd-]hh:]mm:ss) or time ([hh:]mm:ss.cc) as seconds."""
    days = 0
    if "-" in clock:
        d, clock = clock.split("-", 1)
        days = int(d)
    total = 0.0
    for part in clock.split(":"):
        total = total * 60 + float(part)
    return days * 86400 + total


def kind_of(cmd: str) -> str:
    if "claude-sonnet" in cmd or " sonnet" in cmd:
        return "fast"
    if "claude-haiku" in cmd or " haiku" in cmd:
        return "careful"
    return "other"


def sample(daemon: int) -> list:
    out = subprocess.run(
        ["ps", "-axo", "pid=,ppid=,etime=,time=,rss=,pri=,state=,command="],
        capture_output=True,
        text=True,
        timeout=5,
    ).stdout
    now = round(time.time(), 2)
    rows = []
    for line in out.splitlines():
        f = line.split(None, 7)
        if len(f) < 8 or f[1] != str(daemon):
            continue
        rows.append(
            {
                "t": now,
                "daemon": daemon,
                "pid": int(f[0]),
                "kind": kind_of(f[7]),
                "etime_s": secs(f[2]),
                "cpu_s": round(secs(f[3]), 2),
                "rss_kb": int(f[4]),
                "pri": int(f[5]),
                "state": f[6],
            }
        )
    return rows


def main() -> int:
    out, stop = Path(sys.argv[1]), Path(sys.argv[2])
    max_s = (
        float(sys.argv[sys.argv.index("--max-s") + 1])
        if "--max-s" in sys.argv
        else 14400
    )
    end = time.time() + max_s
    with open(out, "a") as fh:
        while time.time() < end and not stop.exists():
            t = time.time()
            d = daemon_pid()
            try:
                rows = sample(d) if d else []
            except (OSError, subprocess.TimeoutExpired):
                rows = []
            if not rows:
                rows = [{"t": round(t, 2), "daemon": d, "pid": None}]
            for r in rows:
                fh.write(json.dumps(r, sort_keys=True) + "\n")
            fh.flush()
            time.sleep(max(0.0, 1.0 - (time.time() - t)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
