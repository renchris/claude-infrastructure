"""procscan.py -- devfs-free, TTY-free process census for lockwatch and hang forensics.

Run as:  $PY -I procscan.py [--threads | --threads-for comm,comm] [--out FILE]   (one JSON doc)
         $PY -I procscan.py --selftest PID PPID PGID [--out FILE]
Never via #! exec on this box (each #! exec leaks ~1.1 KiB kalloc; DESIGN I1).

It is a PROBE: lockprobe runs it as a disposable setsid child with regular-file stdio, and treats
an unreturned run as `stuck:procscan` (R7: 20 ps slept inside the kern_proc handler at 03:40).

What it touches: sysctl KERN_PROC_ALL (every pid: ppid, pgid, uid, stat, P_WEXIT, EPROC_SLEADER,
e_tdev, lstart, comm); proc_pidinfo TASKINFO / LISTFDS / LISTTHREADS / THREADINFO and proc_pidpath
for own-uid processes. NEVER: open/stat/readdir under /dev, ttyname, devname, or any per-fd vnode
call (PROC_PIDFDVNODE*: vn_stat takes DEVFS_LOCK on a devfs vnode). The tty NAME is arithmetic.

Selftest (lockprobe startup, DESIGN C1): parse KERN_PROC_PID for the caller and compare ppid/pgid
with what the caller passed and comm with PROC_PIDT_SHORTBSDINFO, an independent source. Exit 3 and
`"selftest":"mismatch"` on any difference: a parse failure must read `blind`, never 0.
"""

import ctypes
import json
import os
import sys
import time

sys.path.insert(
    0, os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "lockwatch")
)
import libproc_probe as lp  # noqa: E402

_LIBPROC = ctypes.CDLL("/usr/lib/libproc.dylib", use_errno=True)


def pidpath(pid):
    buf = ctypes.create_string_buffer(4096)
    n = _LIBPROC.proc_pidpath(int(pid), buf, ctypes.c_uint32(4096))
    return buf.raw[:n].decode("utf-8", "replace") if n > 0 else None


def _write(doc, out):
    data = json.dumps(doc, separators=(",", ":")) + "\n"
    if out:
        tmp = out + ".tmp.%d" % os.getpid()
        with open(tmp, "w") as fh:
            fh.write(data)
        os.rename(tmp, out)
    else:
        sys.stdout.write(data)


def selftest(pid, ppid, pgid):
    row = lp.kinfo_pid(pid)
    if row is None:
        return {"selftest": "mismatch", "why": "kinfo_pid returned nothing", "pid": pid}
    sc = lp.short_comm(pid)
    bad = []
    if row["pid"] != pid:
        bad.append("pid %s != %s" % (row["pid"], pid))
    if row["ppid"] != ppid:
        bad.append("ppid %s != %s" % (row["ppid"], ppid))
    if row["pgid"] != pgid:
        bad.append("pgid %s != %s" % (row["pgid"], pgid))
    if not row["comm"] or (sc is not None and row["comm"][:15] != sc[:15]):
        bad.append("comm %r != %r" % (row["comm"], sc))
    if not (0 < row["lstart"] <= time.time() + 5):
        bad.append("lstart %s implausible" % row["lstart"])
    return {
        "selftest": "mismatch" if bad else "ok",
        "bad": bad,
        "row": row,
        "short_comm": sc,
    }


def phase(name, on):
    """Phase lines on stdout (a regular file under lockprobe) so a stuck run names its step, and the
    `started` line timestamps scheduler/exec latency (lockprobe's child-starvation gauge)."""
    if on:
        sys.stdout.write("%s %.3f\n" % (name, time.time()))
        sys.stdout.flush()


def scan(want_threads, threads_for=(), phases=False):
    t0 = time.time()
    me = os.getuid()
    phase("kinfo_all", phases)
    procs = lp.kinfo_all()
    phase("tasks", phases)
    totals = {
        "procs": len(procs),
        "zombies": 0,
        "exiting": 0,
        "threads_seen": 0,
        "U": 0,
    }
    kitty = []
    for p in procs:
        p["tty"] = lp.tty_name(p["tdev"])
        try:
            p["sid"] = os.getsid(p["pid"])  # the R3 join needs sid: members of a revoking session read NODEV
        except OSError:
            p["sid"] = None
        if p["stat"] == "Z":
            totals["zombies"] += 1
        if p["exiting"]:
            totals["exiting"] += 1
        if p["uid"] != me or p["stat"] == "Z":
            continue
        ti = lp.task_info(p["pid"])
        if ti is not None:
            p["threads"] = ti.threadnum
            p["rss_mb"] = round(ti.rss / 1048576.0, 1)
            # pti_total_* are mach ticks on arm64 (24 MHz), measured by the 2026-10-25 kit
            p["cpu_s"] = round((ti.tot_user + ti.tot_sys) * lp.TICK_NS / 1e9, 3)
            p["pri"] = ti.priority
        path = pidpath(p["pid"])
        if path:
            p["path"] = path
        is_kitty = p["comm"] == "kitty"
        if want_threads or is_kitty or p["comm"] in threads_for:
            th = lp.threads(p["pid"], p.get("threads", 64))
            if th:
                st = {}
                for t in th:
                    st[t["st"]] = st.get(t["st"], 0) + 1
                totals["threads_seen"] += len(th)
                totals["U"] += st.get("U", 0)
                p["tstates"] = st
                if st.get("U"):
                    p["U_threads"] = [t for t in th if t["st"] == "U"][:8]
                if is_kitty:
                    p["t0_cpu_ns"] = th[0]["cpu_ns"]
                    p["t0_state"] = th[0]["st"]
        if is_kitty:
            fds = lp.fd_list(p["pid"]) or []
            p["sockets"] = sum(1 for _fd, t in fds if t == "socket")
            p["fds"] = len(fds)
            kitty.append(p["pid"])
    return {
        "v": 1,
        "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "ts_epoch": int(time.time()),
        "boot": lp.boot_uuid(),
        "elapsed_ms": round((time.time() - t0) * 1000, 1),
        "totals": totals,
        "kitty": kitty,
        "procs": procs,
    }


def main(argv):
    if "--out" in argv:
        phase("started", True)
    out = None
    if "--out" in argv:
        i = argv.index("--out")
        out = argv[i + 1]
        del argv[i : i + 2]
    if argv[:1] == ["--selftest"]:
        if len(argv) != 4:
            sys.stderr.write(
                "usage: procscan.py --selftest PID PPID PGID [--out FILE]\n"
            )
            return 2
        res = selftest(int(argv[1]), int(argv[2]), int(argv[3]))
        _write(res, out)
        return 0 if res["selftest"] == "ok" else 3
    tf = ()
    if "--threads-for" in argv:
        i = argv.index("--threads-for")
        tf = tuple(x for x in argv[i + 1].split(",") if x)
        del argv[i : i + 2]
    _write(scan("--threads" in argv, tf, phases=bool(out)), out)
    phase("done", bool(out))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
