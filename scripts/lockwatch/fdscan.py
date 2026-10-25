"""fdscan.py -- vnode-fd census of pty masters and slave holders (a 300 s lockwatch probe).

Run as:  $PY -I fdscan.py --out FILE        (never via #!: DESIGN I1)

Output (atomic rename): {v, ts_epoch, boot, masters:{minor:[pid]}, slaves:{minor:[pid]},
orphan_slaves:[minor], ptys, procs_scanned, elapsed_ms}. An orphan slave is a pty minor that some
process still holds open while NO readable process holds its master: the precondition of the
2026-10-25 wedge (ptmx-holders.txt: minor 63 held by nobody at 13:11 while 96296 slept opening it).

This is the ONLY lockwatch code that makes per-fd vnode calls (PROC_PIDFDVNODEPATHINFO -> vn_stat
-> devfs_getattr -> DEVFS_LOCK). On a wedged node it can block, which is why it runs only as a
disposable child; lockprobe reads `stuck:fdscan` as corroboration of a devfs wedge (DESIGN P11).
It never opens, stats or lists anything under /dev itself.
"""

import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
import libproc_probe as lp  # noqa: E402


def scan():
    t0 = time.time()
    me = os.getuid()
    masters, slaves = {}, {}
    n = 0
    for p in lp.kinfo_all():
        if p["uid"] != me or p["stat"] == "Z":
            continue
        fds = lp.fd_list(p["pid"])
        if not fds:
            continue
        n += 1
        for fd, kind in fds:
            if kind != "vnode":
                continue
            res = lp.fd_vnode_path(p["pid"], fd)
            if not res:
                continue
            path, rdev = res
            minor = rdev & 0xFFFFFF
            if path == "/dev/ptmx" or path.startswith("/dev/ptmx"):
                masters.setdefault(str(minor), []).append(p["pid"])
            elif path.startswith("/dev/ttys"):
                slaves.setdefault(str(minor), []).append(p["pid"])
    orphans = sorted(int(m) for m in slaves if m not in masters)
    return {
        "v": 1,
        "ts_epoch": int(time.time()),
        "boot": lp.boot_uuid(),
        "masters": {k: sorted(set(v)) for k, v in masters.items()},
        "slaves": {k: sorted(set(v)) for k, v in slaves.items()},
        "orphan_slaves": orphans,
        "ptys": len(masters),
        "procs_scanned": n,
        "elapsed_ms": round((time.time() - t0) * 1000, 1),
    }


def main(argv):
    if len(argv) != 2 or argv[0] != "--out":
        sys.stderr.write("usage: fdscan.py --out FILE\n")
        return 2
    sys.stdout.write("started %.3f\n" % time.time())
    sys.stdout.flush()
    doc = scan()
    tmp = argv[1] + ".tmp.%d" % os.getpid()
    with open(tmp, "w") as fh:
        fh.write(json.dumps(doc, separators=(",", ":")) + "\n")
    os.rename(tmp, argv[1])
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
