#!/usr/bin/env python3
"""Which process class CARRIES a (cred, kalloc.48, data.kalloc.1024) triple, and is it returned at exit?

The co-growth sampler found data.kalloc.1024 deltas moving ~1:1 with the `cred` and `kalloc.48`
zones in every window, up and down. This holds N processes of one class alive at once, reads the
zones while they live (the per-process carry) and again after they exit (the residue), against a
plain `sleep` control class. Rounds interleave so fleet drift hits every class alike.

Usage: carry_ab.py [--n 300] [--hold 12] [--rounds 3] [--classes plain,sandbox_same,sandbox_unique]
"""

import argparse
import json
import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from probe import all_zones  # noqa: E402

TRACK = ["data.kalloc.1024", "cred", "kalloc.48", "MAC.Labels", "proc_ro"]


def argv_for(cls, i, hold):
    if cls == "plain":
        return ["/bin/sleep", str(hold)]
    if cls == "sandbox_same":
        return [
            "/usr/bin/sandbox-exec",
            "-p",
            "(version 1)(allow default)",
            "/bin/sleep",
            str(hold),
        ]
    if cls == "sandbox_unique":
        prof = (
            '(version 1)(allow default)(deny file-write* (subpath "/private/tmp/kcarry-%d-%d"))'
            % (os.getpid(), i)
        )
        return ["/usr/bin/sandbox-exec", "-p", prof, "/bin/sleep", str(hold)]
    raise SystemExit("unknown class " + cls)


def snap():
    z = all_zones()
    return {k: z.get(k, 0) for k in TRACK}


def diff(a, b):
    return {k: b[k] - a[k] for k in TRACK}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=300)
    ap.add_argument("--hold", type=int, default=12)
    ap.add_argument("--rounds", type=int, default=3)
    ap.add_argument("--classes", default="plain,sandbox_same,sandbox_unique")
    a = ap.parse_args()
    for r in range(a.rounds):
        for cls in a.classes.split(","):
            s0 = snap()
            procs = [subprocess.Popen(argv_for(cls, i, a.hold)) for i in range(a.n)]
            time.sleep(min(4, a.hold / 2))
            s1 = snap()  # all N alive
            for p in procs:
                p.wait()
            time.sleep(2)
            s2 = snap()  # all N gone
            print(
                json.dumps(
                    {
                        "round": r,
                        "class": cls,
                        "n": a.n,
                        "alive": diff(s0, s1),
                        "after_exit": diff(s0, s2),
                    }
                ),
                flush=True,
            )


if __name__ == "__main__":
    main()
