#!/usr/bin/env python3
"""Self-demoting load generator for the load harness (LR_SUSTAINED_LOAD W4).

  loadgen.py run --bg N --ut N --df N [--df-duty 600/400] [--storm R] --parent PID
                 --parent-ident ID --max-s S --ctl FILE [--off /tmp/lr-harness/OFF]
  loadgen.py kill --ctl FILE        SIGKILL FILE.pid's pid only if its start time still matches;
                                    prints {"killed": bool}
  loadgen.py stop-test --bg N [--hold S] [--off PATH]   Tier-L preflight: run at the cap, then
                                    prove the OFF path stops it within 10 s

One process, started at the caller's band, whose worker threads demote THEMSELVES: bg threads set
PRIO_DARWIN_BG on their own thread, ut threads set QOS_CLASS_UTILITY, df threads stay at the
default band and duty-cycle. Work is sha256 over a shared 1 MiB buffer, which releases the GIL, so
the threads run truly in parallel. The main thread polls once a second and os._exit(0)s when the
parent is gone, the wall budget is spent, the OFF path exists, or FILE reads "stop". It never waits
for load and never wraps itself in taskpolicy. Pure stdlib, python 3.9 (runs as /usr/bin/python3 -I).
"""

from __future__ import annotations

import argparse
import ctypes
import hashlib
import json
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time
from typing import Any, Dict, List, Optional, Tuple

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
import runq  # noqa: E402

PRIO_DARWIN_THREAD, PRIO_DARWIN_BG = 3, 0x1000
QOS_CLASS_UTILITY = 0x11
CAPS = {"bg": 200, "ut": 64, "df": 16, "storm": 400}
DEFAULT_OFF = "/tmp/lr-harness/OFF"
BUF = os.urandom(1 << 20)

_LIBC = ctypes.CDLL("/usr/lib/libSystem.B.dylib", use_errno=True)


def _write_json(path: str, obj: Dict[str, Any]) -> None:
    tmp = "%s.tmp.%d" % (path, os.getpid())
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(obj, fh)
    os.replace(tmp, path)


def _read_json(path: str) -> Dict[str, Any]:
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return {}


def _spin() -> None:
    while True:
        hashlib.sha256(BUF).digest()


def _bg_worker() -> None:
    _LIBC.setpriority(PRIO_DARWIN_THREAD, 0, PRIO_DARWIN_BG)
    _spin()


def _ut_worker() -> None:
    _LIBC.pthread_set_qos_class_self_np(QOS_CLASS_UTILITY, 0)
    _spin()


def _df_worker(busy_ms: int, idle_ms: int) -> None:
    while True:
        end = time.monotonic() + busy_ms / 1000.0
        while time.monotonic() < end:
            hashlib.sha256(BUF).digest()
        time.sleep(idle_ms / 1000.0)


def _storm_worker(rate: float) -> None:
    _LIBC.pthread_set_qos_class_self_np(QOS_CLASS_UTILITY, 0)
    gap = 1.0 / rate
    nxt = time.monotonic()
    while True:
        try:
            pid = os.posix_spawn("/usr/bin/true", ["true"], {})
            os.waitpid(pid, 0)
        except OSError:
            pass
        nxt += gap
        delay = nxt - time.monotonic()
        if delay > 0:
            time.sleep(delay)
        else:
            nxt = time.monotonic()  # behind: never burst to catch up


def _parse_duty(s: str) -> Optional[Tuple[int, int]]:
    try:
        busy, idle = (int(x) for x in s.split("/", 1))
    except ValueError:
        return None
    return (busy, idle) if busy > 0 and idle >= 0 else None


def _should_stop(a: argparse.Namespace, deadline: float) -> bool:
    if runq.ident(a.parent) != a.parent_ident or time.time() > deadline:
        return True
    if os.path.exists(a.off):
        return True
    try:
        with open(a.ctl, encoding="utf-8") as fh:
            return fh.read().strip() == "stop"
    except OSError:
        return False


def cmd_run(a: argparse.Namespace) -> int:
    counts = {"bg": a.bg, "ut": a.ut, "df": a.df, "storm": a.storm}
    over = [k for k, v in counts.items() if v < 0 or v > CAPS[k]]
    duty = _parse_duty(a.df_duty)
    if over or duty is None:
        print(
            json.dumps({"refused": over or ["df-duty"], "caps": CAPS}), file=sys.stderr
        )
        return 2
    started = time.time()
    me = os.getpid()
    _write_json(a.ctl + ".pid", {"pid": me, "ident": runq.ident(me)})
    _write_json(
        a.ctl + ".own",
        {"bg": a.bg, "ut": a.ut, "df": a.df, "pid": me, "started": started},
    )
    jobs: List[Tuple[Any, tuple]] = (
        [(_bg_worker, ())] * a.bg
        + [(_ut_worker, ())] * a.ut
        + [(_df_worker, duty)] * a.df
    )
    if a.storm > 0:
        jobs.append((_storm_worker, (float(a.storm),)))
    for fn, args in jobs:
        threading.Thread(target=fn, args=args, daemon=True).start()
    deadline = started + a.max_s
    while True:
        if _should_stop(a, deadline):
            os._exit(0)
        time.sleep(1.0)


def cmd_kill(a: argparse.Namespace) -> int:
    rec = _read_json(a.ctl + ".pid")
    pid, ident = rec.get("pid"), rec.get("ident")
    ok = (
        isinstance(pid, int)
        and isinstance(ident, str)
        and runq.verified_kill(pid, ident, signal.SIGKILL)
    )
    print(json.dumps({"killed": bool(ok)}))
    return 0 if ok else 1


def cmd_stop_test(a: argparse.Namespace) -> int:
    tmp = tempfile.mkdtemp(prefix="lr-loadgen-", dir="/tmp")
    ctl = os.path.join(tmp, "ctl")
    off = a.off or os.path.join(tmp, "OFF")
    me = os.getpid()
    child = subprocess.Popen(
        [
            sys.executable,
            "-I",
            os.path.realpath(__file__),
            "run",
            "--bg",
            str(a.bg),
            "--ut",
            "0",
            "--df",
            "0",
            "--parent",
            str(me),
            "--parent-ident",
            runq.ident(me) or "",
            "--max-s",
            "120",
            "--ctl",
            ctl,
            "--off",
            off,
        ],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        start_new_session=True,
    )
    time.sleep(a.hold)
    th = runq.threads_of(child.pid)
    bg4 = sum(n for k, n in th.items() if k.split(",")[0] == "4")
    off_was = os.path.exists(off)
    with open(off, "a", encoding="utf-8"):
        pass
    t0 = time.monotonic()
    gone_s: Optional[float] = None
    while time.monotonic() - t0 < 10.0:
        if child.poll() is not None:
            gone_s = round(time.monotonic() - t0, 3)
            break
        time.sleep(0.1)
    external = False
    if gone_s is None:
        rec = _read_json(ctl + ".pid")
        external = runq.verified_kill(
            int(rec.get("pid", 0)), str(rec.get("ident", "")), signal.SIGKILL
        )
        try:
            child.wait(timeout=5)
        except subprocess.TimeoutExpired:
            pass
    out = {
        "ok": gone_s is not None,
        "gone_s": gone_s,
        "bg_threads_base4": bg4,
        "external_kill": external,
        "load1": round(os.getloadavg()[0], 2),
        "band": runq.base_of(me),
    }
    print(json.dumps(out))
    if (
        not off_was and a.off is not None
    ):  # a caller's OFF left behind would stop its next run
        try:
            os.unlink(off)
        except OSError:
            pass
    shutil.rmtree(tmp, ignore_errors=True)
    return 0 if out["ok"] else 1


def main(argv: List[str]) -> int:
    p = argparse.ArgumentParser(prog="loadgen.py")
    sub = p.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("run")
    for k in ("bg", "ut", "df"):
        r.add_argument("--" + k, type=int, required=True)
    r.add_argument("--df-duty", default="600/400")
    r.add_argument("--storm", type=int, default=0)
    r.add_argument("--parent", type=int, required=True)
    r.add_argument("--parent-ident", required=True)
    r.add_argument("--max-s", type=float, required=True)
    r.add_argument("--ctl", required=True)
    r.add_argument("--off", default=DEFAULT_OFF)
    k = sub.add_parser("kill")
    k.add_argument("--ctl", required=True)
    s = sub.add_parser("stop-test")
    s.add_argument("--bg", type=int, required=True)
    s.add_argument("--hold", type=float, default=30.0)
    s.add_argument("--off", default=None)
    a = p.parse_args(argv)
    if a.cmd == "run":
        return cmd_run(a)
    if a.cmd == "kill":
        return cmd_kill(a)
    return cmd_stop_test(a)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
