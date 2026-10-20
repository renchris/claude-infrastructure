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
from typing import Callable, Optional

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
    global _LIBPROC
    try:
        if _LIBPROC is None:
            _LIBPROC = ctypes.CDLL("/usr/lib/libproc.dylib", use_errno=True)
        ti = _TaskInfo()
        n = _LIBPROC.proc_pidinfo(
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
