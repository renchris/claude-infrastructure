#!/usr/bin/env python3
"""Read-only process probes for the load-harness sampler (LR_SUSTAINED_LOAD W4).

  runq.py census        runnable threads by BASE priority over every readable process
  runq.py base PID      the process's base priority
  runq.py threads PID   its threads counted as {"base,run_state": n}
  runq.py ident PID     its start time "<tvsec>.<tvusec>" (the identity verified_kill checks)
  runq.py argv PID      its argv joined with spaces ("" when unreadable)
  runq.py desc PID      every pid whose ppid chain reaches PID
  runq.py fds PID       its open-descriptor count
  runq.py cpu PID       its user+system CPU seconds

Each prints one JSON value on stdout; rc 0, rc 1 when the value is None. Every read is an
in-process libproc/sysctl call through ctypes: this file never forks, because a fork from a loaded
box is the cost the harness measures. Pure stdlib, python 3.9 (runs as /usr/bin/python3 -I).
"""

from __future__ import annotations

import ctypes
import json
import os
import sys
import time
from typing import Any, Dict, List, Optional

_LRDIR = os.environ.get("LR_RUNQ_LRDIR") or os.path.join(
    os.path.dirname(os.path.realpath(__file__)), "..", "..", "scripts", "limit-recover"
)
sys.path.insert(0, os.path.realpath(_LRDIR))
from lr_recon import band  # noqa: E402

PROC_PIDLISTFDS, PROC_PIDTBSDINFO, RUSAGE_INFO_V2 = 1, 3, 2
CTL_KERN, KERN_ARGMAX, KERN_PROCARGS2 = 1, 8, 49
FDINFO_SIZE = 8  # struct proc_fdinfo: int32 fd, uint32 type


class _BsdInfo(ctypes.Structure):
    """``struct proc_bsdinfo`` (<sys/proc_info.h>), 136 bytes."""

    _fields_ = (
        [
            (n, ctypes.c_uint32)
            for n in (
                "flags",
                "status",
                "xstatus",
                "pid",
                "ppid",
                "uid",
                "gid",
                "ruid",
                "rgid",
                "svuid",
                "svgid",
                "rfu_1",
            )
        ]
        + [("comm", ctypes.c_char * 16), ("name", ctypes.c_char * 32)]
        + [
            (n, ctypes.c_uint32)
            for n in ("nfiles", "pgid", "pjobc", "e_tdev", "e_tpgid")
        ]
        + [
            ("nice", ctypes.c_int32),
            ("start_tvsec", ctypes.c_uint64),
            ("start_tvusec", ctypes.c_uint64),
        ]
    )


class _RusageV2(ctypes.Structure):
    """``struct rusage_info_v2``: uuid[16] then 18 uint64 (times in mach-absolute units)."""

    _fields_ = [("uuid", ctypes.c_uint8 * 16)] + [
        (n, ctypes.c_uint64)
        for n in (
            "user_time",
            "system_time",
            "pkg_idle_wkups",
            "interrupt_wkups",
            "pageins",
            "wired_size",
            "resident_size",
            "phys_footprint",
            "proc_start_abstime",
            "proc_exit_abstime",
            "child_user_time",
            "child_system_time",
            "child_pkg_idle_wkups",
            "child_interrupt_wkups",
            "child_pageins",
            "child_elapsed_abstime",
            "diskio_bytesread",
            "diskio_byteswritten",
        )
    ]


class _Timebase(ctypes.Structure):
    _fields_ = [("numer", ctypes.c_uint32), ("denom", ctypes.c_uint32)]


_LIBC: Optional[ctypes.CDLL] = None
_NS_PER_TICK: Optional[float] = None


def _libc() -> ctypes.CDLL:
    global _LIBC
    if _LIBC is None:
        _LIBC = ctypes.CDLL("/usr/lib/libSystem.B.dylib", use_errno=True)
    return _LIBC


def _bsd(pid: int) -> Optional[_BsdInfo]:
    try:
        bi = _BsdInfo()
        n = band._lib().proc_pidinfo(
            int(pid),
            PROC_PIDTBSDINFO,
            ctypes.c_uint64(0),
            ctypes.byref(bi),
            ctypes.sizeof(bi),
        )
    except (OSError, AttributeError, ValueError):
        return None
    return bi if n == ctypes.sizeof(bi) else None


def census(deadline_s: float = 5.0) -> Dict[str, Any]:
    t0 = time.monotonic()
    try:
        c = band.runnable_by_base(deadline_s=deadline_s)
    except (OSError, AttributeError, ValueError):
        c = None
    if not c:
        return {}
    return {
        "runq": c["run"],
        "procs": c["procs"],
        "of": c["of"],
        "partial": c["partial"],
        "dur_s": round(time.monotonic() - t0, 4),
    }


def base_of(pid: int) -> Optional[int]:
    return band.base_priority(pid)


def threads_of(pid: int) -> Dict[str, int]:
    out: Dict[str, int] = {}
    for t in band._threads(pid):
        k = "%d,%d" % (int(t.priority), int(t.run_state))
        out[k] = out.get(k, 0) + 1
    return out


def ident(pid: int) -> Optional[str]:
    bi = _bsd(pid)
    return None if bi is None else "%d.%06d" % (bi.start_tvsec, bi.start_tvusec)


def ppid(pid: int) -> Optional[int]:
    bi = _bsd(pid)
    return None if bi is None else int(bi.ppid)


def comm(pid: int) -> Optional[str]:
    bi = _bsd(pid)
    return None if bi is None else bi.comm.decode("utf-8", "replace")


def argv(pid: int) -> str:
    try:
        sc = _libc().sysctl
        mib = (ctypes.c_int * 3)(CTL_KERN, KERN_ARGMAX, 0)
        amax = ctypes.c_int(0)
        sz = ctypes.c_size_t(ctypes.sizeof(amax))
        if (
            sc(mib, 2, ctypes.byref(amax), ctypes.byref(sz), None, 0) != 0
            or amax.value <= 0
        ):
            return ""
        buf = ctypes.create_string_buffer(amax.value)
        sz = ctypes.c_size_t(amax.value)
        mib = (ctypes.c_int * 3)(CTL_KERN, KERN_PROCARGS2, int(pid))
        if sc(mib, 3, buf, ctypes.byref(sz), None, 0) != 0 or sz.value < 4:
            return ""
    except (OSError, AttributeError, ValueError):
        return ""
    raw = buf.raw[: sz.value]
    argc = int.from_bytes(raw[:4], sys.byteorder)
    rest = raw[4:]
    end = rest.find(b"\0")  # skip the exec path, then its NUL padding
    if end < 0:
        return ""
    i = end
    while i < len(rest) and rest[i] == 0:
        i += 1
    args = rest[i:].split(b"\0")[:argc]
    return " ".join(a.decode("utf-8", "replace") for a in args)


def descendants(root: int) -> List[int]:
    parent: Dict[int, int] = {}
    for p in band._all_pids(8192):
        pp = ppid(p)
        if pp is not None and p != root:
            parent[p] = pp
    out: List[int] = []
    for p in parent:
        seen, cur = 0, parent.get(p)
        while cur is not None and cur > 0 and seen < 64:
            if cur == root:
                out.append(p)
                break
            cur, seen = parent.get(cur), seen + 1
    return sorted(out)


def fd_count(pid: int) -> Optional[int]:
    try:
        lib = band._lib()
        need = lib.proc_pidinfo(int(pid), PROC_PIDLISTFDS, ctypes.c_uint64(0), None, 0)
        if need <= 0:
            return None
        cap = need + 32 * FDINFO_SIZE  # room for fds opened between the two calls
        buf = ctypes.create_string_buffer(cap)
        n = lib.proc_pidinfo(int(pid), PROC_PIDLISTFDS, ctypes.c_uint64(0), buf, cap)
    except (OSError, AttributeError, ValueError):
        return None
    return n // FDINFO_SIZE if n > 0 else None


def _ns_per_tick() -> float:
    global _NS_PER_TICK
    if _NS_PER_TICK is None:
        tb = _Timebase()
        _libc().mach_timebase_info(ctypes.byref(tb))
        _NS_PER_TICK = tb.numer / tb.denom if tb.denom else 1.0
    return _NS_PER_TICK


def cpu_s(pid: int, children: bool = False) -> Optional[float]:
    try:
        ru = _RusageV2()
        if band._lib().proc_pid_rusage(int(pid), RUSAGE_INFO_V2, ctypes.byref(ru)) != 0:
            return None
        ticks = (
            ru.child_user_time + ru.child_system_time
            if children
            else ru.user_time + ru.system_time
        )
        return round(ticks * _ns_per_tick() / 1e9, 6)
    except (OSError, AttributeError, ValueError):
        return None


def verified_kill(pid: int, ident_str: str, sig: int) -> bool:
    """Signal ``pid`` only if its start time still reads ``ident_str`` (a reused pid differs)."""
    if not ident_str or ident(pid) != ident_str:
        return False
    try:
        os.kill(int(pid), sig)
    except OSError:
        return False
    return True


def main(argv_: List[str]) -> int:
    if not argv_:
        print(__doc__, file=sys.stderr)
        return 2
    cmd = argv_[0]
    if cmd == "census":
        val: Any = census()
    else:
        probes = {
            "base": base_of,
            "threads": threads_of,
            "ident": ident,
            "argv": argv,
            "desc": descendants,
            "fds": fd_count,
            "cpu": cpu_s,
        }
        if cmd not in probes or len(argv_) < 2 or not argv_[1].isdigit():
            print(__doc__, file=sys.stderr)
            return 2
        val = probes[cmd](int(argv_[1]))  # type: ignore[operator]
    print(json.dumps(val, sort_keys=True))
    return 1 if val is None else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
