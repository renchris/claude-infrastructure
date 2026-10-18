#!/usr/bin/env python3
"""a8_account_load.py — axis A8: dispatcher duration by CONFIG-DIR CLASS x LOAD BAND.

Tests the attribution "config-mirror-assert's memory-mirror walk (lib/config-mirror.zsh:293-302,
O(~18k project slugs), only on accounts whose _CC_ISOLATE list contains `projects`) is what drives
dispatcher runs past the 9 s child bound", against the alternative "those accounts just started
during high load".

Account class from the transcript path: ~/.claude/projects is shared by ~/.claude and
~/.claude-next (whose projects/ is a symlink to it) => SHARED (memory mirror returns early);
~/.claude-{secondary,tertiary,quaternary}/projects => ISOLATED (walks every slug).
READ-ONLY. Usage: python3 -I a8_account_load.py [file_list] [capacity_jsonl]
"""

import json, sys, os, bisect, collections
from datetime import datetime


def ts(s):
    try:
        return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
    except Exception:
        return None


def pct(xs, p):
    xs = sorted(xs)
    return (
        xs[max(0, min(len(xs) - 1, int(round(p / 100 * (len(xs) - 1)))))]
        if xs
        else None
    )


def main():
    flist = sys.argv[1] if len(sys.argv) > 1 else "/tmp/startup-hooks-census-files.txt"
    cap = (
        sys.argv[2]
        if len(sys.argv) > 2
        else os.path.expanduser("~/.claude/logs/capacity-alarm.jsonl")
    )
    lt, lv = [], []
    for line in open(cap, errors="replace"):
        if '"load_1m"' not in line:
            continue
        try:
            r = json.loads(line)
        except Exception:
            continue
        t = ts(r.get("ts", ""))
        if t is not None and isinstance(r.get("load_1m"), (int, float)):
            lt.append(t)
            lv.append(float(r["load_1m"]))
    o = sorted(range(len(lt)), key=lambda i: lt[i])
    lt = [lt[i] for i in o]
    lv = [lv[i] for i in o]
    cell = collections.defaultdict(list)
    home = os.path.expanduser("~")
    for path in open(flist).read().split():
        cls = (
            "SHARED(.claude/.claude-next)"
            if path.startswith(home + "/.claude/projects/")
            else "ISOLATED(sec/ter/quat)"
        )
        try:
            fh = open(path, errors="replace")
        except OSError:
            continue
        with fh:
            for line in fh:
                if "session-start-dispatch" not in line:
                    continue
                try:
                    r = json.loads(line)
                except Exception:
                    continue
                a = r.get("attachment") or {}
                if a.get("type") not in (
                    "hook_success",
                    "hook_cancelled",
                ) or "session-start-dispatch" not in str(a.get("command", "")):
                    continue
                ms = a.get("durationMs")
                t = ts(r.get("timestamp", ""))
                if ms is None or t is None:
                    continue
                st = t - ms / 1000.0
                i = bisect.bisect_left(lt, st)
                j = min(
                    (k for k in (i - 1, i) if 0 <= k < len(lt)),
                    key=lambda k: abs(lt[k] - st),
                    default=None,
                )
                if j is None or abs(lt[j] - st) > 120:
                    continue
                band = "load<100" if lv[j] < 100 else "load>=100"
                cell[(cls, band)].append(int(ms))
    for k in sorted(cell):
        xs = cell[k]
        ge9 = sum(1 for x in xs if x >= 9000)
        print(
            f"{k[0]:30s} {k[1]:10s} n={len(xs):4d} p50={pct(xs, 50):6d} p90={pct(xs, 90):6d} >=9s={ge9:4d} ({100 * ge9 / len(xs):.0f}%)"
        )


if __name__ == "__main__":
    main()
