"""libproc_probe.py -- the ctypes layer lockwatch needs, split by who may call what.

Run nothing here directly; it is imported by lockprobe.py (the core), procscan.py and fdscan.py.

Two groups, and the split is the point (DESIGN §2 I3):

  CORE-SAFE (lockprobe's core may call these; none touches /dev, KERN_PROC_* or proc_pidinfo):
    sysctl_int / sysctl_str / sysctl_loadavg   sysctlbyname scalars
    boot_uuid()                                 kern.bootsessionuuid (unprivileged)
    mach_abs_s / mach_cont_s                    mach_absolute_time / mach_continuous_time in seconds
    cpu_ticks()                                 host_processor_info, summed over CPUs
    set_qos_user_interactive / band_read        pthread QoS for this thread and its read-back

  PROBE-ONLY (procscan / fdscan children; never the core):
    kinfo_all / kinfo_pid / parse_kinfo         sysctl KERN_PROC_ALL / KERN_PROC_PID
    task_all / fd_list / threads                proc_pidinfo

The kinfo_proc offsets are arm64, 648 bytes per record, VERIFIED 2026-10-25 on 24.6.0 against
`ps -o ppid,pgid,tdev,lstart` and os.getsid(): p_starttime@0 (tv_sec q, tv_usec i), p_flag@32,
p_stat@36, p_pid@40, p_comm@243[17], cr_uid@420, e_ppid@560, e_pgid@564, e_tdev@572, e_tpgid@576,
e_flag@612 (EPROC_SLEADER 0x2). OFFSETS is a dict so the self-test can be seam-injected
(CC_LOCKWATCH_TEST_BAD_OFFSET=<field>) and must then read `blind`, never a quiet zero.
"""

import ctypes
import os
import struct

_LIBC = ctypes.CDLL("/usr/lib/libSystem.B.dylib", use_errno=True)

KINFO_SIZE = 648
OFFSETS = {
    "start_sec": 0,
    "p_flag": 32,
    "p_stat": 36,
    "pid": 40,
    "comm": 243,
    "uid": 420,
    "ppid": 560,
    "pgid": 564,
    "tdev": 572,
    "tpgid": 576,
    "e_flag": 612,
}
_bad = os.environ.get("CC_LOCKWATCH_TEST_BAD_OFFSET", "")
if _bad in OFFSETS:
    OFFSETS[_bad] += 4

NODEV = 0xFFFFFFFF
P_WEXIT = 0x00002000
EPROC_SLEADER = 0x2
PTY_MAJOR = 16
PSTAT = {1: "I", 2: "R", 3: "S", 4: "T", 5: "Z"}


# ---------------------------------------------------------------- CORE-SAFE ----------------
def sysctl_int(name):
    """Integer sysctl by name (4 or 8 bytes); None when unreadable."""
    buf = ctypes.create_string_buffer(8)
    sz = ctypes.c_size_t(8)
    if _LIBC.sysctlbyname(
        name.encode(), buf, ctypes.byref(sz), None, ctypes.c_size_t(0)
    ):
        return None
    if sz.value == 4:
        return struct.unpack_from("<i", buf.raw, 0)[0]
    if sz.value == 8:
        return struct.unpack_from("<q", buf.raw, 0)[0]
    return None


def sysctl_str(name, cap=256):
    buf = ctypes.create_string_buffer(cap)
    sz = ctypes.c_size_t(cap)
    if _LIBC.sysctlbyname(
        name.encode(), buf, ctypes.byref(sz), None, ctypes.c_size_t(0)
    ):
        return None
    return buf.raw[: sz.value].split(b"\0", 1)[0].decode("utf-8", "replace")


def sysctl_loadavg():
    """vm.loadavg -> (l1, l5, l15); struct loadavg {fixpt_t ldavg[3]; long fscale}."""
    buf = ctypes.create_string_buffer(24)
    sz = ctypes.c_size_t(24)
    if _LIBC.sysctlbyname(
        b"vm.loadavg", buf, ctypes.byref(sz), None, ctypes.c_size_t(0)
    ):
        return None
    a, b, c = struct.unpack_from("<III", buf.raw, 0)
    (scale,) = struct.unpack_from("<q", buf.raw, 16)
    scale = scale or 2048
    return (a / scale, b / scale, c / scale)


def boottime():
    """kern.boottime tv_sec (struct timeval, 16 bytes); None when unreadable."""
    buf = ctypes.create_string_buffer(16)
    sz = ctypes.c_size_t(16)
    if _LIBC.sysctlbyname(b"kern.boottime", buf, ctypes.byref(sz), None, ctypes.c_size_t(0)):
        return None
    return struct.unpack_from("<q", buf.raw, 0)[0]


def boot_uuid():
    return sysctl_str("kern.bootsessionuuid") or "unknown-boot"


class _TB(ctypes.Structure):
    _fields_ = [("numer", ctypes.c_uint32), ("denom", ctypes.c_uint32)]


_tb = _TB()
_LIBC.mach_timebase_info(ctypes.byref(_tb))
_TICK_NS = _tb.numer / float(_tb.denom or 1)
TICK_NS = _TICK_NS
_LIBC.mach_absolute_time.restype = ctypes.c_uint64
_LIBC.mach_continuous_time.restype = ctypes.c_uint64


def mach_abs_s():
    """Monotonic seconds that STOP across sleep (mach_absolute_time)."""
    return _LIBC.mach_absolute_time() * _TICK_NS / 1e9


def mach_cont_s():
    """Monotonic seconds that INCLUDE sleep (mach_continuous_time). cont - abs grows only while
    the machine sleeps, which is how I8 excludes lid-close from every streak."""
    return _LIBC.mach_continuous_time() * _TICK_NS / 1e9


_LIBC.mach_host_self.restype = ctypes.c_uint32
_LIBC.mach_task_self.restype = ctypes.c_uint32
_LIBC.mach_thread_self.restype = ctypes.c_uint32
PROCESSOR_CPU_LOAD_INFO = 2


def cpu_ticks():
    """(user, system, idle, nice) ticks summed over CPUs via host_processor_info; None on error."""
    ncpu = ctypes.c_uint32(0)
    info = ctypes.POINTER(ctypes.c_int32)()
    cnt = ctypes.c_uint32(0)
    host = _LIBC.mach_host_self()
    kr = _LIBC.host_processor_info(
        host,
        PROCESSOR_CPU_LOAD_INFO,
        ctypes.byref(ncpu),
        ctypes.byref(info),
        ctypes.byref(cnt),
    )
    if kr != 0:
        return None
    try:
        u = s = i = n = 0
        for c in range(ncpu.value):
            u += info[c * 4 + 0] & 0xFFFFFFFF
            s += info[c * 4 + 1] & 0xFFFFFFFF
            i += info[c * 4 + 2] & 0xFFFFFFFF
            n += info[c * 4 + 3] & 0xFFFFFFFF
        return (u, s, i, n)
    finally:
        _LIBC.vm_deallocate(
            _LIBC.mach_task_self(),
            ctypes.cast(info, ctypes.c_void_p),
            ctypes.c_size_t(cnt.value * 4),
        )


QOS_CLASS_USER_INTERACTIVE = 0x21
THREAD_SCHED_TIMESHARE_INFO = 10


def set_qos_user_interactive():
    """Promote the calling thread to QOS_CLASS_USER_INTERACTIVE; True on success."""
    try:
        return _LIBC.pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0) == 0
    except AttributeError:
        return False


def band_read():
    """(base_priority, cur_priority) of the calling thread via thread_info on its own port;
    None when unreadable. THREAD_SCHED_TIMESHARE_INFO = {max, base, cur, depressed, depress_pri}."""
    out = (ctypes.c_int32 * 5)()
    cnt = ctypes.c_uint32(5)
    port = _LIBC.mach_thread_self()
    try:
        kr = _LIBC.thread_info(
            port, THREAD_SCHED_TIMESHARE_INFO, out, ctypes.byref(cnt)
        )
    finally:
        _LIBC.mach_port_deallocate(_LIBC.mach_task_self(), port)
    if kr != 0:
        return None
    return (int(out[1]), int(out[2]))


# ---------------------------------------------------------------- PROBE-ONLY ---------------
def parse_kinfo(raw):
    """Parse a KERN_PROC buffer into dicts. Pure: no syscalls."""
    o = OFFSETS
    rows = []
    for off in range(0, len(raw) - KINFO_SIZE + 1, KINFO_SIZE):
        kp = raw[off : off + KINFO_SIZE]
        (start,) = struct.unpack_from("<q", kp, o["start_sec"])
        (p_flag,) = struct.unpack_from("<i", kp, o["p_flag"])
        (pid,) = struct.unpack_from("<i", kp, o["pid"])
        (uid,) = struct.unpack_from("<I", kp, o["uid"])
        (ppid,) = struct.unpack_from("<i", kp, o["ppid"])
        (pgid,) = struct.unpack_from("<i", kp, o["pgid"])
        (tdev,) = struct.unpack_from("<I", kp, o["tdev"])
        (tpgid,) = struct.unpack_from("<i", kp, o["tpgid"])
        (e_flag,) = struct.unpack_from("<i", kp, o["e_flag"])
        comm = (
            kp[o["comm"] : o["comm"] + 17].split(b"\0", 1)[0].decode("utf-8", "replace")
        )
        rows.append(
            {
                "pid": pid,
                "ppid": ppid,
                "pgid": pgid,
                "uid": uid,
                "stat": PSTAT.get(kp[o["p_stat"]], "?"),
                "exiting": bool(p_flag & P_WEXIT),
                "sleader": bool(e_flag & EPROC_SLEADER),
                "tdev": tdev,
                "tpgid": tpgid,
                "lstart": start,
                "comm": comm,
            }
        )
    return rows


def _sysctl_kern_proc(mib_tail, hint):
    mib = (ctypes.c_int * (2 + len(mib_tail)))(1, 14, *mib_tail)
    for _ in range(5):
        sz = ctypes.c_size_t(0)
        if _LIBC.sysctl(mib, len(mib), None, ctypes.byref(sz), None, 0) != 0:
            raise OSError(ctypes.get_errno(), "sysctl size")
        sz.value += hint * KINFO_SIZE
        buf = ctypes.create_string_buffer(sz.value)
        if _LIBC.sysctl(mib, len(mib), buf, ctypes.byref(sz), None, 0) == 0:
            return buf.raw[: sz.value]
    raise OSError(ctypes.get_errno(), "sysctl kern.proc")


def kinfo_all():
    """KERN_PROC_ALL. NOT core-safe: 20 ps slept inside this handler at 03:40 (DESIGN R7)."""
    return parse_kinfo(_sysctl_kern_proc((0,), 64))


def kinfo_pid(pid):
    rows = parse_kinfo(_sysctl_kern_proc((1, int(pid)), 0))
    return rows[0] if rows else None


def tty_name(tdev):
    """Controlling-tty NAME computed arithmetically (major 16 minor N -> ttysNNN), never looked up."""
    if tdev is None or tdev == NODEV or tdev < 0:
        return None
    major, minor = (tdev >> 24) & 0xFF, tdev & 0xFFFFFF
    if major == PTY_MAJOR:
        return "ttys%03d" % minor
    return "%d/%d" % (major, minor)


def is_pty(tdev):
    return tdev is not None and tdev != NODEV and ((tdev >> 24) & 0xFF) == PTY_MAJOR


class BSDShortInfo(ctypes.Structure):
    _fields_ = [
        ("pbsi_pid", ctypes.c_uint32),
        ("pbsi_ppid", ctypes.c_uint32),
        ("pbsi_pgid", ctypes.c_uint32),
        ("pbsi_status", ctypes.c_uint32),
        ("pbsi_comm", ctypes.c_char * 16),
        ("pbsi_flags", ctypes.c_uint32),
        ("pbsi_uid", ctypes.c_uint32),
        ("pbsi_gid", ctypes.c_uint32),
        ("pbsi_ruid", ctypes.c_uint32),
        ("pbsi_rgid", ctypes.c_uint32),
        ("pbsi_svuid", ctypes.c_uint32),
        ("pbsi_svgid", ctypes.c_uint32),
        ("pbsi_rfu", ctypes.c_uint32),
    ]


class TaskInfo(ctypes.Structure):
    _fields_ = [
        (n, ctypes.c_uint64)
        for n in ("virt", "rss", "tot_user", "tot_sys", "thr_user", "thr_sys")
    ] + [
        (n, ctypes.c_int32)
        for n in (
            "policy",
            "faults",
            "pageins",
            "cow",
            "msg_sent",
            "msg_recv",
            "sc_mach",
            "sc_unix",
            "csw",
            "threadnum",
            "numrunning",
            "priority",
        )
    ]


class ThreadInfo(ctypes.Structure):
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


_LIBC.proc_pidinfo.argtypes = [
    ctypes.c_int,
    ctypes.c_int,
    ctypes.c_uint64,
    ctypes.c_void_p,
    ctypes.c_int,
]
PROC_PIDLISTFDS, PROC_PIDTASKINFO, PROC_PIDTHREADINFO, PROC_PIDLISTTHREADS = 1, 4, 5, 6
PROC_PIDT_SHORTBSDINFO = 13
PROC_PIDFDVNODEPATHINFO = 2
RUN = {1: "R", 2: "T", 3: "S", 4: "U", 5: "H"}
FDT = {
    1: "vnode",
    2: "socket",
    3: "pshm",
    4: "psem",
    5: "kqueue",
    6: "pipe",
    7: "fsevents",
}


def short_comm(pid):
    """p_comm via PROC_PIDT_SHORTBSDINFO: an independent source for the struct self-test."""
    bi = BSDShortInfo()
    n = _LIBC.proc_pidinfo(
        int(pid), PROC_PIDT_SHORTBSDINFO, 0, ctypes.byref(bi), ctypes.sizeof(bi)
    )
    if n != ctypes.sizeof(bi):
        return None
    return bi.pbsi_comm.split(b"\0", 1)[0].decode("utf-8", "replace")


def task_info(pid):
    ti = TaskInfo()
    n = _LIBC.proc_pidinfo(
        int(pid), PROC_PIDTASKINFO, 0, ctypes.byref(ti), ctypes.sizeof(ti)
    )
    return ti if n == ctypes.sizeof(ti) else None


def fd_list(pid):
    """[(fd, type_name)] via PROC_PIDLISTFDS (no vnode lookup); None when unreadable."""
    n = _LIBC.proc_pidinfo(int(pid), PROC_PIDLISTFDS, 0, None, 0)
    if n <= 0:
        return None
    buf = ctypes.create_string_buffer(n + 64 * 8)
    n = _LIBC.proc_pidinfo(int(pid), PROC_PIDLISTFDS, 0, buf, len(buf))
    if n <= 0:
        return None
    out = []
    for i in range(0, n, 8):
        fd, t = struct.unpack_from("<iI", buf.raw, i)
        out.append((fd, FDT.get(t, str(t))))
    return out


def threads(pid, hint=256):
    """Per-thread dicts via PROC_PIDLISTTHREADS + PROC_PIDTHREADINFO (handles go in as c_uint64)."""
    cap = max(int(hint), 1) + 64
    handles = (ctypes.c_uint64 * cap)()
    n = _LIBC.proc_pidinfo(
        int(pid), PROC_PIDLISTTHREADS, 0, handles, ctypes.sizeof(handles)
    )
    res = []
    for i in range(max(0, min(cap, n // 8))):
        th = ThreadInfo()
        if _LIBC.proc_pidinfo(
            int(pid),
            PROC_PIDTHREADINFO,
            ctypes.c_uint64(handles[i]),
            ctypes.byref(th),
            ctypes.sizeof(th),
        ) == ctypes.sizeof(th):
            res.append(
                {
                    "st": RUN.get(th.run_state, str(th.run_state)),
                    "pri": th.curpri,
                    "base": th.priority,
                    "cpu_ns": int((th.user + th.system)),
                    "name": th.name.split(b"\0", 1)[0].decode("utf-8", "replace"),
                }
            )
    return res


class _VnodeInfoPath(ctypes.Structure):
    # struct vnode_fdinfowithpath = proc_fileinfo (24) + vnode_info_path (152 + MAXPATHLEN 1024)
    _fields_ = [("raw", ctypes.c_char * (24 + 152 + 1024))]


def fd_vnode_path(pid, fd):
    """(path, rdev) of a vnode fd. PROBE-ONLY and fdscan-ONLY: vn_stat on a devfs vnode takes
    DEVFS_LOCK (proc_info.c fill_vnodeinfo -> vn_stat; devfs_getattr), so this may block on a
    wedged node, which is why only the disposable fdscan child calls it."""
    vi = _VnodeInfoPath()
    n = _LIBC.proc_pidfdinfo(
        int(pid), int(fd), PROC_PIDFDVNODEPATHINFO, ctypes.byref(vi), ctypes.sizeof(vi)
    )
    if n != ctypes.sizeof(vi):
        return None
    raw = ctypes.string_at(ctypes.addressof(vi), ctypes.sizeof(vi))
    # vnode_info_path @24: vinfo_stat (136 bytes; vst_rdev u32 @116), vi_type @136, vi_pad @140,
    # vi_fsid 8 @144 = 152; then vip_path[1024] @152.
    (rdev,) = struct.unpack_from("<I", raw, 24 + 116)
    path = raw[24 + 152 :].split(b"\0", 1)[0].decode("utf-8", "replace")
    return (path, rdev & 0xFFFFFFFF)
