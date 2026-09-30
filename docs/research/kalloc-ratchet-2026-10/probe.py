#!/usr/bin/env python3
"""No-root A/B probe for the data.kalloc.1024 ratchet (backlog a417ab59e8f5).

zprint's `cur inuse` column for data.kalloc.1024 is an exact element count and needs no root.
The fleet grows the zone continuously, so every arm is bracketed by a CONTROL window of the
same length (sleep) and the verdict is the EXCESS over the control rate:

    excess = dz_arm - rate_control * dt_arm        (elements; 1 element = 1 KiB)
    per_op = excess / N

Arms are interleaved round-robin across rounds so fleet drift hits every arm alike.

Usage:  probe.py [--rounds 3] [--arms a,b,c] [--scale 1.0] [--series SECONDS]
        --series N  : instead of arms, print a (t, pid, zone) time series every 3 s for N s.
Output: one JSON object per line on stdout.
"""

import argparse
import json
import os
import select
import socket
import subprocess
import sys
import time

ZONE = "data.kalloc.1024"


def zone_inuse():
    out = subprocess.run(
        ["/usr/bin/zprint", ZONE], capture_output=True, text=True, timeout=10
    ).stdout
    for line in out.splitlines():
        f = line.split()
        if f and f[0] == ZONE and len(f) >= 7 and f[6].isdigit():
            return int(f[6])
    raise RuntimeError("zone not found in zprint output")


def last_pid():
    return int(
        subprocess.run(
            ["/bin/sh", "-c", "echo $$"], capture_output=True, text=True
        ).stdout
    )


# ---- arms: each takes n and performs n operations -------------------------------------------
def arm_spawn_true(n):
    for _ in range(n):
        subprocess.run(["/usr/bin/true"])


def arm_spawn_true_captured(n):  # the $(...) shape: spawn with a stdout pipe
    for _ in range(n):
        subprocess.run(["/usr/bin/true"], capture_output=True)


def arm_fork_only(n):
    for _ in range(n):
        pid = os.fork()
        if pid == 0:
            os._exit(0)
        os.waitpid(pid, 0)


def arm_pty(n):
    for _ in range(n):
        a, b = os.openpty()
        os.close(a)
        os.close(b)


def arm_pipe_900(n):
    buf = b"x" * 900
    for _ in range(n):
        r, w = os.pipe()
        os.write(w, buf)
        os.read(r, 4096)
        os.close(r)
        os.close(w)


def arm_socketpair_900(n):
    buf = b"x" * 900
    for _ in range(n):
        a, b = socket.socketpair()
        a.send(buf)
        b.recv(4096)
        a.close()
        b.close()


def arm_kqueue(n):
    for _ in range(n):
        select.kqueue().close()


def arm_ps(n):
    for _ in range(n):
        subprocess.run(["/bin/ps", "-axo", "pid,ppid,command"], capture_output=True)


def arm_ps_pid_only(n):  # KERN_PROC listing only, no per-process argv read
    for _ in range(n):
        subprocess.run(["/bin/ps", "-axo", "pid"], capture_output=True)


def arm_pgrep_f(n):  # the fleet's liveness idiom: argv read of every process
    for _ in range(n):
        subprocess.run(
            ["/usr/bin/pgrep", "-f", "no-such-process-kalloc-probe"],
            capture_output=True,
        )


def _procargs_all():
    import ctypes

    libc = ctypes.CDLL("/usr/lib/libc.dylib", use_errno=True)
    pids = [
        int(p)
        for p in subprocess.run(
            ["/bin/ps", "-axo", "pid="], capture_output=True, text=True
        ).stdout.split()
    ]
    buf = ctypes.create_string_buffer(262144)
    return libc, pids, buf


def arm_procargs_inproc(n):  # KERN_PROCARGS2 via sysctl, no fork: n full sweeps
    import ctypes

    libc, pids, buf = _procargs_all()
    for _ in range(n):
        for pid in pids:
            mib = (ctypes.c_int * 3)(1, 49, pid)  # CTL_KERN, KERN_PROCARGS2
            size = ctypes.c_size_t(len(buf))
            libc.sysctl(mib, 3, buf, ctypes.byref(size), None, 0)


SANDBOX_EXEC = "/usr/bin/sandbox-exec"


def arm_sandbox_same(n):                  # one profile text, applied n times
    for _ in range(n):
        subprocess.run([SANDBOX_EXEC, "-p", "(version 1)(allow default)", "/usr/bin/true"])


def arm_sandbox_unique(n):                # a distinct profile text per call (a per-command path)
    for i in range(n):
        prof = '(version 1)(allow default)(deny file-write* (subpath "/private/tmp/kalloc-probe-%d-%d"))' % (os.getpid(), i)
        subprocess.run([SANDBOX_EXEC, "-p", prof, "/usr/bin/true"])


def arm_sh_c(n):  # exec of /bin/sh (a platform binary, like every hook)
    for _ in range(n):
        subprocess.run(["/bin/sh", "-c", ":"])


def arm_notifyutil(n):  # spawn + one mach/XPC round trip to notifyd
    for _ in range(n):
        subprocess.run(
            ["/usr/bin/notifyutil", "-g", "com.apple.system.timezone"],
            capture_output=True,
        )


def arm_git(n):
    for _ in range(n):
        subprocess.run(
            [
                "/usr/bin/git",
                "-C",
                os.path.dirname(os.path.abspath(__file__)),
                "rev-parse",
                "HEAD",
            ],
            capture_output=True,
        )


ARMS = {
    "spawn_true": (arm_spawn_true, 1500),
    "spawn_true_captured": (arm_spawn_true_captured, 1500),
    "fork_only": (arm_fork_only, 1500),
    "sh_c": (arm_sh_c, 1500),
    "pty": (arm_pty, 3000),
    "pipe_900": (arm_pipe_900, 20000),
    "socketpair_900": (arm_socketpair_900, 20000),
    "kqueue": (arm_kqueue, 20000),
    "ps": (arm_ps, 150),
    "sandbox_same": (arm_sandbox_same, 400),
    "sandbox_unique": (arm_sandbox_unique, 400),
    "ps_pid_only": (arm_ps_pid_only, 150),
    "pgrep_f": (arm_pgrep_f, 150),
    "procargs_inproc": (arm_procargs_inproc, 20),
    "notifyutil": (arm_notifyutil, 800),
    "git": (arm_git, 400),
}


TRACK = ["cred", "kalloc.48", "MAC.Labels"]   # the co-growers cogrowth.py ranked first


def measure(fn, n):
    a0, t0 = all_zones(), time.time()
    fn(n)
    a1, t1 = all_zones(), time.time()
    side = {k: a1.get(k, 0) - a0.get(k, 0) for k in TRACK}
    return a1[ZONE] - a0[ZONE], t1 - t0, side


def run_arms(names, rounds, scale):
    for r in range(rounds):
        for name in names:
            fn, n = ARMS[name]
            n = max(1, int(n * scale))
            dz, dt, side = measure(fn, n)
            cz, ct, cside = measure(lambda _n: time.sleep(dt), 0)
            rate = cz / ct if ct else 0.0
            excess = dz - rate * dt
            print(
                json.dumps(
                    {
                        "round": r,
                        "arm": name,
                        "n": n,
                        "dt": round(dt, 2),
                        "dz": dz,
                        "ctrl_dz": cz,
                        "ctrl_rate": round(rate, 2),
                        "excess": round(excess, 1),
                        "per_op": round(excess / n, 4),
                        "side": side,
                        "ctrl_side": cside,
                    }
                ),
                flush=True,
            )


def run_series(seconds):
    end = time.time() + seconds
    while time.time() < end:
        print(
            json.dumps(
                {"t": round(time.time(), 1), "pid": last_pid(), "zone": zone_inuse()}
            ),
            flush=True,
        )
        time.sleep(3)


def all_zones():
    """{zone: inuse elements} for every zone (zprint -L, no root)."""
    out = subprocess.run(
        ["/usr/bin/zprint", "-L"], capture_output=True, text=True, timeout=30
    ).stdout
    z = {}
    for line in out.splitlines():
        f = line.split()
        if len(f) >= 7 and f[1].isdigit() and f[6].isdigit():
            z[f[0]] = int(f[6])
    return z


def io_classes():
    out = subprocess.run(
        ["/usr/sbin/ioclasscount"], capture_output=True, text=True, timeout=30
    ).stdout
    c = {}
    for line in out.splitlines():
        k, _, v = line.partition(" = ")
        if v.strip().isdigit():
            c[k.strip()] = int(v)
    return c


def run_sample_all(seconds, interval, path):
    """Co-growth instrument: one row per interval with every zone and every IOKit class count."""
    end = time.time() + seconds
    with open(path, "a", buffering=1) as fh:
        while time.time() < end:
            t = time.time()
            try:
                procs = len(
                    subprocess.run(
                        ["/bin/ps", "-axo", "pid="], capture_output=True, text=True
                    ).stdout.split()
                )
                row = {
                    "t": round(t, 1),
                    "pid": last_pid(),
                    "nprocs": procs,
                    "load1": os.getloadavg()[0],
                    "zones": all_zones(),
                    "io": io_classes(),
                }
                fh.write(json.dumps(row, separators=(",", ":")) + "\n")
            except Exception as e:  # a skipped row is recorded, never silent
                fh.write(json.dumps({"t": round(t, 1), "error": repr(e)}) + "\n")
            time.sleep(max(1.0, interval - (time.time() - t)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--sample-all", type=int, default=0, help="seconds to run the co-growth sampler"
    )
    ap.add_argument("--interval", type=int, default=60)
    ap.add_argument(
        "--out",
        default=os.path.expanduser("~/.claude/logs/kalloc-ratchet-cogrowth.jsonl"),
    )
    ap.add_argument("--rounds", type=int, default=3)
    ap.add_argument("--arms", default=",".join(ARMS))
    ap.add_argument("--scale", type=float, default=1.0)
    ap.add_argument("--series", type=int, default=0)
    a = ap.parse_args()
    if a.sample_all:
        run_sample_all(a.sample_all, a.interval, a.out)
        return
    if a.series:
        run_series(a.series)
        return
    names = [x for x in a.arms.split(",") if x]
    bad = [x for x in names if x not in ARMS]
    if bad:
        sys.exit("unknown arm(s): " + ",".join(bad))
    run_arms(names, a.rounds, a.scale)


if __name__ == "__main__":
    main()
