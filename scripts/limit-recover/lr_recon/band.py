"""band.py: the reconciler reads its own scheduling band once per pass, and pages if it is below 31.

WHY (docs/research/lr-sustained-load-2026-10-20/REPORT.md §3.1, lever A1). launchd runs a job with
no ``ProcessType`` under its default light limits: base priority 20, the utility band. Every Claude
session runs at 31. At load ~200 the same rail work took 7-111x longer at 20 than at 31, so the
rail's own 3/10/30/120 s bounds fired and were read as facts about kitty, memory or placement. The
plist now says ``ProcessType Interactive``, but a plist edit does nothing until the job is booted
out and bootstrapped again, and a reload from a stale copy silently puts the daemon back at 20.
This check is what makes that visible: one ``band.log`` line per pass, and one page per daemon
process when the band is below FLOOR.

THE READ. ``proc_pidinfo(PROC_PIDTASKINFO).pti_priority`` is the task's BASE priority (measured
2026-10-20 on this machine: 31 from a session's tree, 20 under ``taskpolicy -c utility``). ``ps -M``
prints each thread's CURRENT priority, which agrees on an idle thread but decays while a thread
burns CPU (the same band-31 tree read 15T and 30T in ``ps -M`` mid-run), so one ``ps`` sample can
under-read the band, as one ``ps -o pri`` sample can over-read it (REPORT §4 A1). This read is
stable and forks nothing: a ``ps`` fork from band 20 at load ~200 takes seconds, which is the cost
being diagnosed.

CHILDREN. The reconciler's ``start_new_session=True`` Popen children (act.spawn, the provenance
check, plan's accounts refresh) need nothing extra: setsid changes the session and process group,
not the scheduling role, and a child inherits its parent's band. Measured 2026-10-20: a setsid
``/bin/sleep`` from a priority-31 python read ``31T`` in ``ps -M``; axes 04 R0.3 and 06 F1 read the
same for the Interactive classifier-warm job's plain Popen children; and a utility-clamped parent's
children stay at 20 (lr-reset-poller.sh --move-kick header). So the band is set at the root, here.
"""

from __future__ import annotations

import ctypes
import os
import time
from typing import Any, Callable, Dict, List, Optional, Tuple

FLOOR = 31  # the band every Claude session runs at
PROC_PIDTASKINFO = 4
LOG_MAX = 256 * 1024


class _TaskInfo(ctypes.Structure):
    """``struct proc_taskinfo`` (<sys/proc_info.h>): six uint64 then twelve int32."""

    _fields_ = [
        (n, ctypes.c_uint64)
        for n in (
            "virtual_size",
            "resident_size",
            "total_user",
            "total_system",
            "threads_user",
            "threads_system",
        )
    ] + [
        (n, ctypes.c_int32)
        for n in (
            "policy",
            "faults",
            "pageins",
            "cow_faults",
            "messages_sent",
            "messages_received",
            "syscalls_mach",
            "syscalls_unix",
            "csw",
            "threadnum",
            "numrunning",
            "priority",
        )
    ]


_LIBPROC: Optional[ctypes.CDLL] = None


def base_priority(pid: Optional[int] = None) -> Optional[int]:
    """The base scheduling priority of ``pid`` (default: this process); None when unreadable."""
    try:
        ti = _TaskInfo()
        n = _lib().proc_pidinfo(
            int(os.getpid() if pid is None else pid),
            PROC_PIDTASKINFO,
            ctypes.c_uint64(0),
            ctypes.byref(ti),
            ctypes.sizeof(ti),
        )
    except (OSError, AttributeError):
        return None
    if n != ctypes.sizeof(ti):
        return None
    return int(ti.priority)


# ── B6 reads: every thread's BASE priority, kitty's main thread, thermal and memory ──
# Same mechanism as base_priority: in-process libproc syscalls, no fork. A ps fork from a loaded box
# is the cost being diagnosed, and ps prints decayed CURRENT priority, which under-counts the
# default band 1.05-6x (axis 04 R0.2).
PROC_PIDLISTTHREADS, PROC_PIDTHREADINFO, TH_STATE_RUNNING = 6, 5, 1
CENSUS_DEADLINE_S = 2.0


class _ThreadInfo(ctypes.Structure):
    """``struct proc_threadinfo``: two uint64, eight int32, char[64] (112 bytes)."""

    _fields_ = [
        ("user", ctypes.c_uint64),
        ("system", ctypes.c_uint64),
        ("cpu_usage", ctypes.c_int32),
        ("policy", ctypes.c_int32),
        ("run_state", ctypes.c_int32),
        ("flags", ctypes.c_int32),
        ("sleep_time", ctypes.c_int32),
        ("curpri", ctypes.c_int32),
        ("priority", ctypes.c_int32),
        ("maxpriority", ctypes.c_int32),
        ("name", ctypes.c_char * 64),
    ]


def _lib() -> ctypes.CDLL:
    global _LIBPROC
    if _LIBPROC is None:
        _LIBPROC = ctypes.CDLL("/usr/lib/libproc.dylib", use_errno=True)
    return _LIBPROC


def _threads(pid: int, cap: int = 2048) -> List[_ThreadInfo]:
    """Every readable thread of ``pid``; [] when unreadable. Thread handles are 64-bit and MUST go
    in as c_uint64: passed as a plain int (ctypes' C int) the info call returns 0 (measured)."""
    try:
        lib = _lib()
        handles = (ctypes.c_uint64 * cap)()
        n = lib.proc_pidinfo(
            int(pid),
            PROC_PIDLISTTHREADS,
            ctypes.c_uint64(0),
            handles,
            ctypes.sizeof(handles),
        )
        out = []
        for i in range(max(0, min(cap, n // 8))):
            ti = _ThreadInfo()
            r = lib.proc_pidinfo(
                int(pid),
                PROC_PIDTHREADINFO,
                ctypes.c_uint64(handles[i]),
                ctypes.byref(ti),
                ctypes.sizeof(ti),
            )
            if r == ctypes.sizeof(ti):
                out.append(ti)
        return out
    except (OSError, AttributeError, ValueError):
        return []


def main_thread(pid: int) -> Optional[Tuple[int, int]]:
    """(base, current) priority of ``pid``'s first thread; None when unreadable."""
    th = _threads(pid, cap=4)
    return (int(th[0].priority), int(th[0].curpri)) if th else None


def _all_pids(max_pids: int) -> List[int]:
    try:
        buf = (ctypes.c_int * max_pids)()
        n = _lib().proc_listallpids(buf, ctypes.sizeof(buf))
    except (OSError, AttributeError):
        return []
    return [int(buf[i]) for i in range(max(0, min(n, max_pids))) if buf[i] > 0]


def runnable_by_base(
    pids: Optional[List[int]] = None,
    deadline_s: float = CENSUS_DEADLINE_S,
    max_pids: int = 8192,
    mono: Callable[[], float] = time.monotonic,
) -> Optional[Dict[str, Any]]:
    """RUNNABLE threads counted by BASE priority over every readable process. Same-user only:
    root-owned processes are unreadable, so counts are lower bounds ("procs" of "of"). A monotonic
    deadline is checked per pid: past it the counts so far come back with ``partial: true``. Meant
    to run off the loop thread (ctypes releases the GIL), since an in-process syscall cannot be
    timed out and is not a declared child."""
    end = mono() + deadline_s
    todo = _all_pids(max_pids) if pids is None else list(pids)
    if not todo:
        return None
    run: Dict[str, int] = {}
    thr = readable = 0
    partial = False
    for pid in todo:
        if mono() > end:
            partial = True
            break
        th = _threads(pid)
        if not th:
            continue
        readable += 1
        thr += len(th)
        for t in th:
            if t.run_state == TH_STATE_RUNNING:
                k = str(int(t.priority))
                run[k] = run.get(k, 0) + 1
    return {
        "run": run,
        "thr": thr,
        "procs": readable,
        "of": len(todo),
        "partial": partial,
    }


def _sysctl_int(name: str) -> Optional[int]:
    try:
        lib = ctypes.CDLL("/usr/lib/libSystem.B.dylib", use_errno=True)
        v, sz = ctypes.c_int(0), ctypes.c_size_t(4)
        if lib.sysctlbyname(
            name.encode(), ctypes.byref(v), ctypes.byref(sz), None, ctypes.c_size_t(0)
        ):
            return None
        return int(v.value)
    except (OSError, AttributeError):
        return None


def pressure_level() -> Optional[int]:
    """kern.memorystatus_vm_pressure_level: 1 normal, 2 warn, 4 critical; None when unreadable."""
    return _sysctl_int("kern.memorystatus_vm_pressure_level")


def thermal_level() -> Optional[int]:
    """The thermal pressure notify state (0 nominal … 3+ critical); None when unreadable."""
    try:
        lib = ctypes.CDLL("/usr/lib/libSystem.B.dylib", use_errno=True)
        tok, st = ctypes.c_int(0), ctypes.c_uint64(0)
        if lib.notify_register_check(
            b"com.apple.system.thermalpressurelevel", ctypes.byref(tok)
        ):
            return None
        try:
            if lib.notify_get_state(tok, ctypes.byref(st)):
                return None
        finally:
            lib.notify_cancel(tok)
        return int(st.value)
    except (OSError, AttributeError):
        return None


def below_floor(pri: Optional[int]) -> bool:
    """Only a READ below FLOOR pages: an unreadable band is logged as unknown, never as low."""
    return pri is not None and pri < FLOOR


def page_text(pri: int, pid: int) -> str:
    return (
        "The limit-recover reconciler (pid %d) runs at scheduling priority %d, below the %d every "
        "Claude session runs at, so under load its probes and placements time out and recovery "
        "stalls. Reload com.reso.lr-reconciler from the repo plist, which sets ProcessType "
        "Interactive, then read the band back with ps -M." % (pid, pri, FLOOR)
    )


def log_line(now: float, pid: int, pri: Optional[int]) -> str:
    verdict = "unknown" if pri is None else ("low" if pri < FLOOR else "ok")
    return "%.0f pid=%d pri=%s floor=%d %s" % (
        now,
        pid,
        "?" if pri is None else pri,
        FLOOR,
        verdict,
    )


def check(
    log_path: str,
    now: float,
    paged: bool,
    page: Callable[[str], None],
    append: Callable[[str, str, int], None],
    read: Optional[Callable[[], Optional[int]]] = None,
    pid: Optional[int] = None,
) -> bool:
    """One pass: append the reading to ``log_path``; page once if it is below FLOOR and ``paged``
    is False. Returns the new ``paged``. A failed log write or page never raises into the loop."""
    me = os.getpid() if pid is None else pid
    pri = (read or base_priority)()
    try:
        append(log_path, log_line(now, me, pri), LOG_MAX)
    except OSError:
        pass
    if paged or not below_floor(pri):
        return paged
    try:
        page(page_text(int(pri or 0), me))
    except Exception:  # noqa: BLE001 — a failed page must never stop the daemon
        return False
    return True


def main(argv: List[str]) -> int:
    """``python3 band.py [pid]``: print the base priority of ``pid`` (default: the caller, i.e. this
    process's parent), or ``?`` and exit 1 when unreadable. Run as a FILE, not ``-m lr_recon.band``,
    so a shell caller (bin/cc-dispatch's band self-check) loads this module and nothing else."""
    try:
        pid = int(argv[1]) if len(argv) > 1 else os.getppid()
    except ValueError:
        print("?")
        return 2
    pri = base_priority(pid)
    print("?" if pri is None else pri)
    return 0 if pri is not None else 1


if __name__ == "__main__":
    import sys

    sys.exit(main(sys.argv))
