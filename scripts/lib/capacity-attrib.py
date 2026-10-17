#!/usr/bin/env python3
"""capacity-attrib.py — per-session CPU attribution, one libproc pass per capacity-alarm tick.

Design: docs/research/concurrency-scale-2026-10-04/d-telemetry-gaps.md §2 (fix row 11 of that README).

WHY. A `ps`/`top` snapshot sees only processes alive at the instant it samples. On this box short-lived
tool and hook children carry 20-29% of busy CPU and exit between samples, so a snapshot census misses
~31-42% of busy CPU and cannot say which session spent it. libproc can: `proc_pid_rusage` carries
`ri_child_user_time` / `ri_child_system_time`, the CPU of every child a process has already REAPED.
Summing own + reaped-child CPU over a session's tree, as a delta between two ticks, integrates every
process that lived inside the interval, however briefly.

THE ACCOUNTING (§2.3 — the part the prototype got wrong first):
  cum(p) = own(p) + child(p), keyed on (pid, start) so a reused pid can never match.
  delta  = cum_B - cum_A for a pid alive at both ticks; cum_B for a newborn.
  REAP CORRECTION: for each pid alive at A and gone at B, walk A's ppid chain to the nearest ancestor
  alive at BOTH ticks and subtract cum_A(gone) from that ancestor's delta, per counter. Without it a
  long-lived child's whole lifetime is re-credited to its parent when it is reaped (measured: 512 cpu-s
  attributed against 300 busy). Correcting only at the direct parent still left a negative session sys
  figure; propagating to the surviving ancestor closed the budget.
  POSITIVE CONTROL on every row: attributed <= host busy x 1.05, else "accounting":"overflow".
  `unseen_s` (host busy minus everything attributed) is always reported, never hidden.

KNOWN BLIND SPOT, measured 2026-10-04: exec(2) RESETS a process's ri_child_* counters. A shell that reaps
children and then execs its last command (bash -c and zsh -c both do this implicitly) drops that reaped
CPU from its tree; the parent reaping the exec'd process receives only what came after the exec. The
loss lands in unseen_s, and the (pid, start) key does not change across exec, so the shell's delta can
read negative for that tick (summed into neg_s when it drives a session below zero).

OWNERSHIP, first match wins: ppid walk to a registered session root (sessions/<pid>.json whose
procStart matches) -> CLAUDE_CODE_SESSION_ID env tag of a live session (orphan work, credited to the
session as orphan_s) -> tag of a dead session (ghost) -> launchd label of the top ancestor ->
other-501:<comm>. Other uids (WindowServer, kernel_task, syspolicyd...) come from one setuid `ps`.

OUTPUT. Appends one row to ~/.claude/logs/attrib.jsonl (rotated by rotate-autonomy-logs.sh) and prints
the top-N processes by physical footprint as "<pid> <mb> <name>" lines on stdout: rung 4 of
capacity-alarm.sh reads those instead of running `top -l 1`, which cost 1.5-2.4 CPU-s per tick.

FAIL-OPEN, NEVER FAIL-WRONG. Any exception prints nothing and exits 0; the caller falls back. The first
tick (no state) and a state older than CC_CAP_ATTRIB_MAX_GAP_S write a row marked "baseline" with no
deltas: a delta across an unknown gap is not a measurement.

Usage: capacity-attrib.py [--no-write] [--top N]
       capacity-attrib.py --daemon [--interval 5] [--max-ticks N] [--top N]   (see "--daemon" below)
Env seams: CC_CAP_ATTRIB_LOG · CC_CAP_ATTRIB_STATE · CC_CAP_ATTRIB_MAX_GAP_S · CC_CAP_ATTRIB_ROOTS_GLOB
"""

import calendar
import ctypes
import ctypes.util
import glob
import json
import os
import resource
import subprocess
import sys
import time

HOME = os.path.expanduser("~")
LOG = os.environ.get("CC_CAP_ATTRIB_LOG", HOME + "/.claude/logs/attrib.jsonl")
STATE = os.environ.get("CC_CAP_ATTRIB_STATE", HOME + "/.claude/logs/.attrib-state.json")
MAX_GAP_S = float(os.environ.get("CC_CAP_ATTRIB_MAX_GAP_S", "900"))
ROOTS_GLOB = os.environ.get(
    "CC_CAP_ATTRIB_ROOTS_GLOB", HOME + "/.claude*/sessions/*.json"
)
MY_UID = os.getuid()
MAX_BUCKETS = 25  # keeps a row near 4-5 KB; the remainder is summed into "rest"
TAG = b"CLAUDE_CODE_SESSION_ID="
PID_SPAN = 99999 - 100  # the pid cursor wraps at 99,999 back to ~100
# The measured maximum fork rate on this box. DESIGN X5 said 1,567/s; the --daemon sampler measured
# 2,000-3,400/s sustained on 2026-10-17 (agreeing with a 20 s pid-delta probe to 0.6%), so the old
# figure let a lapped 30-63 s window through unflagged. A maximum that measurement exceeds is wrong
# by definition: raising it only marks more windows unreadable, it never fabricates a rate.
MAX_FORKS_S = 3400

libc = ctypes.CDLL(ctypes.util.find_library("c"), use_errno=True)


class TimebaseInfo(ctypes.Structure):
    _fields_ = [("numer", ctypes.c_uint32), ("denom", ctypes.c_uint32)]


class BsdInfo(ctypes.Structure):  # struct proc_bsdinfo, <sys/proc_info.h>
    _fields_ = [
        ("flags", ctypes.c_uint32),
        ("status", ctypes.c_uint32),
        ("xstatus", ctypes.c_uint32),
        ("pid", ctypes.c_uint32),
        ("ppid", ctypes.c_uint32),
        ("uid", ctypes.c_uint32),
        ("gid", ctypes.c_uint32),
        ("ruid", ctypes.c_uint32),
        ("rgid", ctypes.c_uint32),
        ("svuid", ctypes.c_uint32),
        ("svgid", ctypes.c_uint32),
        ("rfu_1", ctypes.c_uint32),
        ("comm", ctypes.c_char * 16),
        ("name", ctypes.c_char * 32),
        ("nfiles", ctypes.c_uint32),
        ("pgid", ctypes.c_uint32),
        ("pjobc", ctypes.c_uint32),
        ("e_tdev", ctypes.c_uint32),
        ("e_tpgid", ctypes.c_uint32),
        ("nice", ctypes.c_int32),
        ("start_tvsec", ctypes.c_uint64),
        ("start_tvusec", ctypes.c_uint64),
    ]


class TaskInfo(ctypes.Structure):  # struct proc_taskinfo
    _fields_ = [
        ("virtual_size", ctypes.c_uint64),
        ("resident_size", ctypes.c_uint64),
        ("total_user", ctypes.c_uint64),
        ("total_system", ctypes.c_uint64),
        ("threads_user", ctypes.c_uint64),
        ("threads_system", ctypes.c_uint64),
        ("policy", ctypes.c_int32),
        ("faults", ctypes.c_int32),
        ("pageins", ctypes.c_int32),
        ("cow_faults", ctypes.c_int32),
        ("messages_sent", ctypes.c_int32),
        ("messages_received", ctypes.c_int32),
        ("syscalls_mach", ctypes.c_int32),
        ("syscalls_unix", ctypes.c_int32),
        ("csw", ctypes.c_int32),
        ("threadnum", ctypes.c_int32),
        ("numrunning", ctypes.c_int32),
        ("priority", ctypes.c_int32),
    ]


class TaskAllInfo(ctypes.Structure):
    _fields_ = [("pbsd", BsdInfo), ("ptinfo", TaskInfo)]


_RU_FIELDS = (
    "user_time system_time pkg_idle_wkups interrupt_wkups pageins wired_size resident_size "
    "phys_footprint proc_start_abstime proc_exit_abstime child_user_time child_system_time "
    "child_pkg_idle_wkups child_interrupt_wkups child_pageins child_elapsed_abstime "
    "diskio_bytesread diskio_byteswritten cpu_time_qos_default cpu_time_qos_maintenance "
    "cpu_time_qos_background cpu_time_qos_utility cpu_time_qos_legacy "
    "cpu_time_qos_user_initiated cpu_time_qos_user_interactive billed_system_time "
    "serviced_system_time logical_writes lifetime_max_phys_footprint instructions cycles "
    "billed_energy serviced_energy interval_max_phys_footprint runnable_time flags user_ptime "
    "system_ptime pinstructions pcycles energy_nj penergy_nj secure_time_in_system "
    "secure_ptime_in_system neural_footprint lifetime_max_neural_footprint "
    "interval_max_neural_footprint"
).split()


class RusageV6(ctypes.Structure):  # struct rusage_info_v6, <sys/resource.h>
    _fields_ = (
        [("uuid", ctypes.c_uint8 * 16)]
        + [(f, ctypes.c_uint64) for f in _RU_FIELDS]
        + [("reserved", ctypes.c_uint64 * 9)]
    )


libc.proc_listallpids.argtypes = [ctypes.c_void_p, ctypes.c_int]
libc.proc_listallpids.restype = ctypes.c_int
libc.proc_pidinfo.argtypes = [
    ctypes.c_int,
    ctypes.c_int,
    ctypes.c_uint64,
    ctypes.c_void_p,
    ctypes.c_int,
]
libc.proc_pidinfo.restype = ctypes.c_int
libc.proc_pid_rusage.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_void_p]
libc.proc_pid_rusage.restype = ctypes.c_int
libc.sysctl.argtypes = [
    ctypes.POINTER(ctypes.c_int),
    ctypes.c_uint,
    ctypes.c_void_p,
    ctypes.POINTER(ctypes.c_size_t),
    ctypes.c_void_p,
    ctypes.c_size_t,
]
libc.sysctlbyname.argtypes = [
    ctypes.c_char_p,
    ctypes.c_void_p,
    ctypes.POINTER(ctypes.c_size_t),
    ctypes.c_void_p,
    ctypes.c_size_t,
]

PROC_PIDTASKALLINFO = 2
RUSAGE_INFO_V6 = 6
CTL_KERN, KERN_PROCARGS2, KERN_ARGMAX = 1, 49, 8

_tb = TimebaseInfo()
libc.mach_timebase_info(ctypes.byref(_tb))
TICK_S = (
    _tb.numer / _tb.denom
) / 1e9  # mach absolute ticks -> seconds (125/3 ns on Apple silicon)


def list_pids():
    n = libc.proc_listallpids(None, 0)
    buf = (ctypes.c_int * (n + 256))()
    got = libc.proc_listallpids(buf, ctypes.sizeof(buf))
    return [buf[i] for i in range(max(got, 0)) if buf[i] > 0]


def read_pid(pid):
    """-> dict or None (other uid, zombie, or gone)."""
    ti = TaskAllInfo()
    if (
        libc.proc_pidinfo(
            pid, PROC_PIDTASKALLINFO, 0, ctypes.byref(ti), ctypes.sizeof(ti)
        )
        <= 0
    ):
        return None
    ru = RusageV6()
    if libc.proc_pid_rusage(pid, RUSAGE_INFO_V6, ctypes.byref(ru)) != 0:
        return None
    b = ti.pbsd
    name = (b.name or b.comm).decode("utf-8", "replace")
    return {
        "ppid": b.ppid,
        "uid": b.uid,
        "start": "%d.%06d" % (b.start_tvsec, b.start_tvusec),
        "start_s": b.start_tvsec,
        "name": name,
        "ou": ru.user_time * TICK_S,
        "os": ru.system_time * TICK_S,
        "cu": ru.child_user_time * TICK_S,
        "cs": ru.child_system_time * TICK_S,
        "run": ru.runnable_time * TICK_S,
        "qu": ru.cpu_time_qos_utility * TICK_S,
        "qb": ru.cpu_time_qos_background * TICK_S,
        "fp": ru.phys_footprint,
    }


_ARGMAX = None


def argbuf():
    global _ARGMAX
    if _ARGMAX is None:
        v = ctypes.c_int(0)
        sz = ctypes.c_size_t(ctypes.sizeof(v))
        mib = (ctypes.c_int * 2)(CTL_KERN, KERN_ARGMAX)
        libc.sysctl(mib, 2, ctypes.byref(v), ctypes.byref(sz), None, 0)
        _ARGMAX = v.value or 1048576
    return ctypes.create_string_buffer(_ARGMAX)


def procargs(pid, buf=None):
    """-> (argv list, env-tag or None), via KERN_PROCARGS2. Same uid only; no sudo.
    A caller reading many pids passes one argbuf() so each read does not zero ARG_MAX bytes."""
    if buf is None:
        buf = argbuf()
    sz = ctypes.c_size_t(len(buf))
    mib = (ctypes.c_int * 3)(CTL_KERN, KERN_PROCARGS2, pid)
    if libc.sysctl(mib, 3, buf, ctypes.byref(sz), None, 0) != 0:
        return None, None
    raw = ctypes.string_at(buf, sz.value)
    argc = int.from_bytes(raw[:4], "little")
    rest = raw[4:]
    nul = rest.find(b"\0")
    rest = rest[nul:].lstrip(b"\0") if nul >= 0 else b""
    parts = rest.split(b"\0")
    argv = [p.decode("utf-8", "replace") for p in parts[:argc]]
    tag = None
    for p in parts[argc:]:
        if p.startswith(TAG):
            tag = p[len(TAG) :].decode("ascii", "replace")
            break
    return argv, tag


def eval_body(script):
    """The Bash tool runs `zsh -c 'source <snapshot> ... && eval '<cmd>' < /dev/null && pwd -P ...'`.
    Returns <cmd> with its shell quoting undone, or None. `'` inside the body is encoded '"'"'."""
    i = script.find(" && eval ")
    if i < 0:
        return None
    i += len(" && eval ")
    out = []
    n = len(script)
    while i < n and not script[i].isspace():
        q = script[i]
        if q in ("'", '"'):
            j = script.find(q, i + 1)
            if j < 0:
                return None
            out.append(script[i + 1 : j])
            i = j + 1
        else:
            out.append(q)
            i += 1
    return "".join(out) if out else None


def cmd_hash(s):
    """len:poly31 over the first 4096 code points. hooks/post-tool-batch.sh computes the SAME value in
    jq for each Bash call's tool_input.command (jq has no sha builtin), so the two join offline."""
    x = 0
    for c in s[:4096]:
        x = (x * 31 + ord(c)) % 4294967296
    return "%d:%d" % (len(s), x)


def host_ticks():
    """Sum over CPUs of (user, system, idle, nice) ticks from host_processor_info. -> tuple or None."""
    try:
        libc.mach_host_self.restype = ctypes.c_uint
        host = libc.mach_host_self()
        ncpu = ctypes.c_uint(0)
        info = ctypes.POINTER(ctypes.c_uint32)()
        cnt = ctypes.c_uint(0)
        PROCESSOR_CPU_LOAD_INFO = 2
        if (
            libc.host_processor_info(
                host,
                PROCESSOR_CPU_LOAD_INFO,
                ctypes.byref(ncpu),
                ctypes.byref(info),
                ctypes.byref(cnt),
            )
            != 0
        ):
            return None
        tot = [0, 0, 0, 0]
        for c in range(ncpu.value):
            for k in range(4):
                tot[k] += info[c * 4 + k]
        task = ctypes.c_uint.in_dll(libc, "mach_task_self_").value
        libc.vm_deallocate(task, ctypes.cast(info, ctypes.c_void_p), cnt.value * 4)
        return tuple(tot), ncpu.value
    except Exception:
        return None


def sysctl_int(name):
    v = ctypes.c_uint64(0)
    sz = ctypes.c_size_t(8)
    if (
        libc.sysctlbyname(name.encode(), ctypes.byref(v), ctypes.byref(sz), None, 0)
        != 0
    ):
        return None
    return v.value & ((1 << (8 * sz.value)) - 1) if sz.value < 8 else v.value


def parse_cputime(t):
    try:
        s = 0.0
        for part in t.split(":"):
            s = s * 60 + float(part)
        return s
    except ValueError:
        return None


def other_uids():
    """One setuid ps: every pid we cannot read with libproc. -> ({key: rec}, ps child pid)."""
    p = subprocess.Popen(
        ["/bin/ps", "-axo", "pid=,uid=,rss=,time=,utime=,lstart=,ucomm="],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
    )
    out, _ = p.communicate(timeout=15)
    recs = {}
    for line in out.splitlines():
        f = line.split()
        if len(f) < 11 or not f[0].isdigit() or not f[1].isdigit():
            continue
        if int(f[1]) == MY_UID:
            continue
        tot, usr = parse_cputime(f[3]), parse_cputime(f[4])
        if tot is None or usr is None:
            continue
        key = "%s@%s" % (f[0], "_".join(f[5:10]))
        recs[key] = {
            "pid": int(f[0]),
            "rss_kb": int(f[2]) if f[2].isdigit() else 0,
            "u": usr,
            "s": max(tot - usr, 0.0),
            "name": " ".join(f[10:]),
        }
    return recs, p.pid


def launchd_labels():
    try:
        out = subprocess.run(
            ["/bin/launchctl", "list"], capture_output=True, text=True, timeout=10
        ).stdout
    except Exception:
        return {}
    m = {}
    for line in out.splitlines()[1:]:
        f = line.split("\t")
        if len(f) == 3 and f[0].isdigit():
            m[int(f[0])] = f[2]
    return m


def session_roots():
    """pid -> {sid, start_s, kind, cwd, cfg} from every config dir's sessions/<pid>.json."""
    roots = {}
    for path in glob.glob(ROOTS_GLOB):
        try:
            with open(path) as fh:
                j = json.load(fh)
            pid = int(j["pid"])
            st = j.get("procStart")
            # Claude Code writes procStart in UTC (measured: exactly the CDT offset away from
            # libproc's start under mktime). Both readings are kept so a TZ change in the writer
            # cannot unroot every session at once; a match on either, within 1 s, is a match.
            tm = time.strptime(st, "%a %b %d %H:%M:%S %Y") if st else None
            start_s = (calendar.timegm(tm), int(time.mktime(tm))) if tm else None
            roots[pid] = {
                "sid": j.get("sessionId") or "anon:%d" % pid,
                "start_s": start_s,
                "kind": j.get("kind", "?"),
                "cwd": j.get("cwd", ""),
                "cfg": os.path.dirname(os.path.dirname(path)),
            }
        except Exception:
            continue
    return roots


def agents_live(root, now):
    """Subagent transcripts touched in the last 120 s, for a live session only (never a global glob)."""
    slug = "".join(c if c.isalnum() else "-" for c in root["cwd"])
    d = os.path.join(root["cfg"], "projects", slug, root["sid"], "subagents")
    try:
        n = 0
        for e in os.scandir(d):
            if e.name.endswith(".jsonl") and now - e.stat().st_mtime < 120:
                n += 1
        return n
    except OSError:
        return 0


def attrib_pass(write, top_n, emit, threaded=False):
    """One full attribution row (the one-shot CLI's whole job). emit(lines) receives the rung-4 feed
    as soon as it exists; returns the row. threaded: self_cpu_s counts this thread, not the process."""
    t_start = time.time()
    cpu0 = time.thread_time() if threaded else 0.0
    rc0 = resource.getrusage(resource.RUSAGE_CHILDREN) if threaded else None
    try:
        with open(STATE) as fh:
            prev = json.load(fh)
    except Exception:
        prev = None

    now = time.time()
    ht = host_ticks()
    exec_hook = sysctl_int("security.mac.asp.stats.exec_hook_count")

    snap = {}
    unreadable = 0
    for pid in list_pids():
        r = read_pid(pid)
        if r is None:
            unreadable += 1
            continue
        if r["uid"] != MY_UID:
            continue
        snap["%d@%s" % (pid, r["start"])] = dict(r, pid=pid)
    other, ps_pid = other_uids()
    by_pid = {r["pid"]: k for k, r in snap.items()}

    # ── rung-4 feed: top-N by physical footprint (uid 501 via libproc, others via ps rss) ──
    cands = [(r["fp"] / 1048576.0, r["pid"], r["name"]) for r in snap.values()]
    cands += [(r["rss_kb"] / 1024.0, r["pid"], r["name"]) for r in other.values()]
    cands.sort(reverse=True)
    emit(
        [
            "%d %.0f %s\n" % (pid, mb, name.replace('"', "").replace("\\", ""))
            for mb, pid, name in cands[:top_n]
        ]
    )

    # ── ownership ──
    roots = {
        p: v
        for p, v in session_roots().items()
        if p in by_pid
        and (
            v["start_s"] is None
            or min(abs(snap[by_pid[p]]["start_s"] - t) for t in v["start_s"]) <= 1
        )
    }
    live_sids = {v["sid"] for v in roots.values()}
    cache = (prev or {}).get("tagcache", {})
    newcache = {}
    labels = None

    def root_of(key):
        p = snap[key]["pid"]
        d = 0
        while p > 1 and d < 64:
            if p in roots:
                return p
            k = by_pid.get(p)
            if k is None:
                return None
            p = snap[k]["ppid"]
            d += 1
        return None

    def top_ancestor(key):
        p = snap[key]["pid"]
        d = 0
        while d < 64:
            k = by_pid.get(p)
            if k is None or snap[k]["ppid"] <= 1:
                return p
            p = snap[k]["ppid"]
            d += 1
        return p

    owner = {}
    tools = {}
    for key, r in snap.items():
        rp = root_of(key)
        if rp is not None:
            owner[key] = ("s", roots[rp]["sid"])
            if r["ppid"] == rp and r["name"] in ("zsh", "bash"):
                if key in cache:
                    h = cache[key].get("h")
                else:
                    argv, _ = procargs(r["pid"])
                    body = (
                        eval_body(argv[2])
                        if argv and len(argv) >= 3 and argv[1] == "-c"
                        else None
                    )
                    h = cmd_hash(body) if body is not None else None
                newcache[key] = {"h": h}
                if h:
                    tools[key] = (roots[rp]["sid"], h)
            continue
        if key in cache:
            tag = cache[key].get("t")
        else:
            _, tag = procargs(r["pid"])
        newcache[key] = {"t": tag}
        if tag and tag in live_sids:
            owner[key] = ("o", tag)
        elif tag:
            owner[key] = ("b", "ghost")
        else:
            if labels is None:
                labels = launchd_labels()
            lab = labels.get(top_ancestor(key))
            owner[key] = ("b", "launchd:" + lab if lab else "other-501:" + r["name"])

    # ── accounting ──
    baseline = (
        prev is None
        or not ht
        or not prev.get("host")
        or now - prev.get("ts", 0) > MAX_GAP_S
        or now <= prev.get("ts", 0)
    )
    row = {"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now)), "v": 1}
    sessions = {}
    for p, v in roots.items():
        k = by_pid[p]
        sessions[v["sid"]] = {
            "sid": v["sid"],
            "pid": p,
            "kind": v["kind"],
            "cpu_s": 0.0,
            "user_s": 0.0,
            "sys_s": 0.0,
            "own_s": 0.0,
            "orphan_s": 0.0,
            "runnable_wait_s": 0.0,
            "qos_util_s": 0.0,
            "qos_bg_s": 0.0,
            "fp_mb": 0.0,
            "procs": 0,
            "new_procs": 0,
            "root_cum_s": round(
                snap[k]["ou"] + snap[k]["os"] + snap[k]["cu"] + snap[k]["cs"], 2
            ),
            "agents_live": agents_live(v, now),
            "tools_live": [],
        }
    for key, (kind, who) in owner.items():
        if kind in ("s", "o") and who in sessions:
            s = sessions[who]
            s["procs"] += 1
            s["fp_mb"] += snap[key]["fp"] / 1048576.0

    if baseline:
        row["accounting"] = "baseline"
    else:
        el = now - prev["ts"]
        pa = prev["pids"]
        du, ds = {}, {}
        for key, r in snap.items():
            a = pa.get(key)
            if a:
                du[key] = (r["ou"] + r["cu"]) - (a[1] + a[3])
                ds[key] = (r["os"] + r["cs"]) - (a[2] + a[4])
            else:
                du[key] = r["ou"] + r["cu"]
                ds[key] = r["os"] + r["cs"]
        # reap correction: nearest ancestor alive at BOTH ticks absorbs -cum_A(gone), per counter.
        # Clamped at 0: an ancestor that never reaped the child (it was reparented, or an exec reset
        # the counter) cannot give back what it never received; that excess is reap_unabsorbed_s.
        prev_by_pid = {int(k.split("@")[0]): k for k in pa}
        unabsorbed = 0.0
        for gk, a in pa.items():
            if gk in snap:
                continue
            p = a[0]
            d = 0
            while p > 1 and d < 64:
                ak = prev_by_pid.get(p)
                if ak is None:
                    break
                if ak in snap:
                    for dd, x in ((du, a[1] + a[3]), (ds, a[2] + a[4])):
                        take = min(x, max(dd[ak], 0.0))
                        dd[ak] -= take
                        unabsorbed += x - take
                    break
                p = pa[ak][0]
                d += 1
        buckets = {}
        neg = 0.0
        uid501 = 0.0
        for key, r in snap.items():
            u, s_ = du[key], ds[key]
            kind, who = owner[key]
            a = pa.get(key)
            if kind in ("s", "o") and who in sessions:
                se = sessions[who]
                se["user_s"] += u
                se["sys_s"] += s_
                if kind == "o":
                    se["orphan_s"] += u + s_
                if snap[key]["pid"] == se["pid"]:
                    se["own_s"] += (r["ou"] + r["os"]) - ((a[1] + a[2]) if a else 0.0)
                if a:
                    se["runnable_wait_s"] += max(
                        (r["run"] - a[5]) - ((r["ou"] + r["os"]) - (a[1] + a[2])), 0.0
                    )
                    se["qos_util_s"] += r["qu"] - a[6]
                    se["qos_bg_s"] += r["qb"] - a[7]
                else:
                    se["new_procs"] += 1
                if key in tools:
                    se["tools_live"].append(
                        {"h": tools[key][1], "pid": r["pid"], "cpu_s": round(u + s_, 2)}
                    )
            else:
                buckets[who] = buckets.get(who, 0.0) + u + s_
            uid501 += u + s_
        for se in sessions.values():
            se["cpu_s"] = se["user_s"] + se["sys_s"]
            if se["cpu_s"] < 0:
                neg += -se["cpu_s"]
        # other uids, same (pid, start) delta rule; no reap correction is possible without their ppids
        po = prev.get("other", {})
        other_s = 0.0
        for key, r in other.items():
            a = po.get(key)
            d = (
                (r["u"] + r["s"]) - (a[0] + a[1]) if a else 0.0
            )  # a newborn root daemon: unknown start
            if d > 0:
                b = "other-uid:" + r["name"]
                buckets[b] = buckets.get(b, 0.0) + d
                other_s += d
        hp, hc = prev["host"], ht[0]
        hz = float(os.sysconf("SC_CLK_TCK") or 100)
        h_user = (hc[0] - hp[0] + hc[3] - hp[3]) / hz
        h_sys = (hc[1] - hp[1]) / hz
        h_idle = (hc[2] - hp[2]) / hz
        busy = h_user + h_sys
        attrib = uid501 + other_s
        row["el_s"] = round(el, 1)
        row["host"] = {
            "busy_s": round(busy, 1),
            "user_s": round(h_user, 1),
            "sys_s": round(h_sys, 1),
            "idle_s": round(h_idle, 1),
            "ncpu": ht[1],
        }
        fp_prev = prev.get("ps_pid")
        if fp_prev:
            dp = ps_pid - fp_prev
            if dp < 0:
                dp += PID_SPAN  # pids wrap at 99,999 back to ~100
            # past ~29 s (PID_SPAN / MAX_FORKS_S) the cursor can have lapped the pid space unseen:
            # no reading, flagged
            row["forks_alias"] = el * MAX_FORKS_S > PID_SPAN
            row["forks_per_s"] = None if row["forks_alias"] else round(dp / el, 1)
        if exec_hook is not None and prev.get("exec_hook") is not None:
            row["exec_hook_dt"] = (
                exec_hook - prev["exec_hook"]
            )  # tracks execs; ratio unconfirmed (B1)
        row["attrib_s"] = round(attrib, 1)
        row["uid501_s"] = round(uid501, 1)
        row["other_uid_s"] = round(other_s, 1)
        row["unseen_s"] = round(busy - attrib, 1)
        top = sorted(buckets.items(), key=lambda kv: -kv[1])
        bk = {k: round(v, 2) for k, v in top[:MAX_BUCKETS] if round(v, 2) != 0}
        rest = sum(v for _, v in top[MAX_BUCKETS:])
        if rest:
            bk["rest"] = round(rest, 2)
        neg += sum(
            -v for _, v in top if v < 0
        )  # negative buckets too, those folded into rest included
        row["neg_s"] = round(neg, 2)
        row["neg_session"] = neg > 0
        row["reap_unabsorbed_s"] = round(unabsorbed, 2)
        if attrib < 0 or uid501 < 0:
            row["accounting"] = "underflow"
        else:
            row["accounting"] = (
                "overflow" if busy > 0 and attrib > busy * 1.05 else "ok"
            )
        row["buckets"] = bk

    out_sessions = []
    for se in sorted(sessions.values(), key=lambda s: -s["cpu_s"]):
        for f in (
            "cpu_s",
            "user_s",
            "sys_s",
            "own_s",
            "orphan_s",
            "runnable_wait_s",
            "qos_util_s",
            "qos_bg_s",
            "fp_mb",
        ):
            se[f] = round(se[f], 2) if f != "fp_mb" else round(se[f])
        se["child_s"] = round(se["cpu_s"] - se["own_s"] - se["orphan_s"], 2)
        out_sessions.append(se)
    row["sessions"] = out_sessions
    row["n_pids"] = len(snap)
    row["n_other"] = len(other)
    row["n_unreadable"] = unreadable
    rs, rc = (
        resource.getrusage(resource.RUSAGE_SELF),
        resource.getrusage(resource.RUSAGE_CHILDREN),
    )
    if threaded:  # a long-lived daemon: this pass's thread and the children it reaped, not the process
        rs = resource.struct_rusage((time.thread_time() - cpu0, 0.0) + rs[2:])
        rc = resource.struct_rusage(
            (rc.ru_utime - rc0.ru_utime, rc.ru_stime - rc0.ru_stime) + rc[2:]
        )
    row["self_cpu_s"] = round(rs.ru_utime + rs.ru_stime + rc.ru_utime + rc.ru_stime, 3)
    row["self_wall_s"] = round(time.time() - t_start, 3)

    if not write:
        return row
    state = {
        "ts": now,
        "host": list(ht[0]) if ht else None,
        "exec_hook": exec_hook,
        "ps_pid": ps_pid,
        "pids": {
            k: [
                r["ppid"],
                r["ou"],
                r["os"],
                r["cu"],
                r["cs"],
                r["run"],
                r["qu"],
                r["qb"],
            ]
            for k, r in snap.items()
        },
        "other": {k: [r["u"], r["s"]] for k, r in other.items()},
        "tagcache": newcache,
    }
    os.makedirs(os.path.dirname(LOG), exist_ok=True)
    tmp = STATE + ".tmp.%d" % os.getpid()
    with open(tmp, "w") as fh:
        json.dump(state, fh, separators=(",", ":"))
    os.replace(tmp, STATE)
    with open(LOG, "a") as fh:
        fh.write(json.dumps(row, separators=(",", ":")) + "\n")
    return row


# ── --daemon: the fork-free 5 s sampler (docs/research/load-root-cause-2026-10-17/DESIGN.md §4.1) ──
# Every 5 s: one sysctl(KERN_PROC_ALL) for every uid (no setuid ps), argv + cwd for NEW pids only, one
# proc_pid_rusage pass over uid 501 (footprint and its lifetime max, so a transient alive at any tick is
# caught), and the kernel counters. Every 60 s: the full attribution row above, unchanged, on a thread so
# its setuid ps cannot stall the loop, plus the IOKit disk counters. Writes attrib-latest.json (atomic)
# and attrib-series.jsonl beside CC_CAP_ATTRIB_LOG; the series rotates to .1 at SERIES_MAX, so it never
# holds more than 2 x 4 MiB (~4-5 h of ticks per generation).
SERIES_MAX = 4 << 20
PASS_EVERY_S = 60.0
KERN_PROC, KERN_PROC_ALL, PROC_PIDVNODEPATHINFO = 14, 0, 9
P_, I_, U_ = ctypes.c_void_p, ctypes.c_int32, ctypes.c_uint32
RATES = (  # monotone counters, reported per second
    "vfs.vnstats.num_newvnode_calls",
    "vfs.vnstats.num_recycledvnodes",
    "security.mac.asp.stats.exec_hook_count",
    "vm.compressor_input_bytes",
    "vm.compressor_compressed_bytes",
)
GAUGES = (
    "vm.page_free_count",
    "vm.compressor_bytes_used",
    "vm.compressor_segment_pages_compressed",
)


class Timeval(ctypes.Structure):
    _fields_ = [("sec", ctypes.c_long), ("usec", I_)]


class ExternProc(ctypes.Structure):  # struct extern_proc, <sys/proc.h>
    _fields_ = [
        ("starttime", Timeval), ("vmspace", P_), ("sigacts", P_), ("flag", I_),
        ("stat", ctypes.c_uint8), ("pid", I_), ("oppid", I_), ("dupfd", I_),
        ("user_stack", P_), ("exit_thread", P_), ("debugger", I_), ("sigwait", I_),
        ("estcpu", U_), ("cpticks", I_), ("pctcpu", U_), ("wchan", P_), ("wmesg", P_),
        ("swtime", U_), ("slptime", U_), ("realtimer", Timeval * 2), ("rtime", Timeval),
        ("uticks", ctypes.c_uint64), ("sticks", ctypes.c_uint64), ("iticks", ctypes.c_uint64),
        ("traceflag", I_), ("tracep", P_), ("siglist", I_), ("textvp", P_), ("holdcnt", I_),
        ("sigmask", U_), ("sigignore", U_), ("sigcatch", U_), ("priority", ctypes.c_uint8),
        ("usrpri", ctypes.c_uint8), ("nice", ctypes.c_int8), ("comm", ctypes.c_char * 17),
        ("pgrp", P_), ("addr", P_), ("xstat", ctypes.c_uint16), ("acflag", ctypes.c_uint16),
        ("ru", P_),
    ]  # fmt: skip


class Pcred(ctypes.Structure):
    _fields_ = [("lock", ctypes.c_char * 72), ("ucred", P_), ("ruid", U_), ("svuid", U_),
                ("rgid", U_), ("svgid", U_), ("refcnt", I_)]  # fmt: skip


class Ucred(ctypes.Structure):
    _fields_ = [
        ("ref", I_),
        ("uid", U_),
        ("ngroups", ctypes.c_short),
        ("groups", U_ * 16),
    ]


class Vmspace(ctypes.Structure):
    _fields_ = [("refcnt", I_), ("shm", P_), ("seg", I_ * 5), ("taddr", P_), ("daddr", P_),
                ("maxsaddr", P_)]  # fmt: skip


class Eproc(ctypes.Structure):  # struct eproc, <sys/sysctl.h>
    _fields_ = [
        ("paddr", P_), ("sess", P_), ("pcred", Pcred), ("ucred", Ucred), ("vm", Vmspace),
        ("ppid", I_), ("pgid", I_), ("jobc", ctypes.c_short), ("tdev", I_), ("tpgid", I_),
        ("tsess", P_), ("wmesg", ctypes.c_char * 8), ("xsize", I_), ("xrssize", ctypes.c_short),
        ("xccount", ctypes.c_short), ("xswrss", ctypes.c_short), ("eflag", I_),
        ("login", ctypes.c_char * 12), ("spare", I_ * 4),
    ]  # fmt: skip


class KinfoProc(ctypes.Structure):  # 648 bytes on arm64 and x86_64
    _fields_ = [("p", ExternProc), ("e", Eproc)]


assert ctypes.sizeof(KinfoProc) == 648


def proc_all():
    """One sysctl(KERN_PROC_ALL), every uid, no fork. -> [(pid, ppid, uid, stat, comm, start)]."""
    mib = (ctypes.c_int * 3)(CTL_KERN, KERN_PROC, KERN_PROC_ALL)
    for _ in range(
        4
    ):  # the table can grow between the size probe and the read (ENOMEM)
        sz = ctypes.c_size_t(0)
        if libc.sysctl(mib, 3, None, ctypes.byref(sz), None, 0) != 0:
            break
        buf = ctypes.create_string_buffer(sz.value + 64 * ctypes.sizeof(KinfoProc))
        sz = ctypes.c_size_t(len(buf))
        if libc.sysctl(mib, 3, buf, ctypes.byref(sz), None, 0) == 0:
            n = sz.value // ctypes.sizeof(KinfoProc)
            return [
                (k.p.pid, k.e.ppid, k.e.ucred.uid, k.p.stat, k.p.comm.decode("utf-8", "replace"),
                 k.p.starttime.sec + k.p.starttime.usec / 1e6)
                for k in (KinfoProc * n).from_buffer(buf)
            ]  # fmt: skip
    raise OSError(ctypes.get_errno(), "sysctl KERN_PROC_ALL")


_VPI = ctypes.create_string_buffer(
    2 * (152 + 1024)
)  # struct proc_vnodepathinfo: cdir, then rdir


def pid_cwd(pid):
    if libc.proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, _VPI, len(_VPI)) <= 0:
        return None
    return ctypes.string_at(ctypes.addressof(_VPI) + 152).decode("utf-8", "replace")


def sysctl_words(name, n):
    v = (ctypes.c_uint64 * n)()
    sz = ctypes.c_size_t(ctypes.sizeof(v))
    if libc.sysctlbyname(name.encode(), v, ctypes.byref(sz), None, 0) != 0:
        return None
    return list(v)


def read_disk():
    """IOBlockStorageDriver Statistics summed over every driver, by IOKit, no fork (`ioreg -c
    IOBlockStorageDriver` shows the same values). -> [bytes_w, ops_w, bytes_r, ops_r] or None."""
    iokit = ctypes.CDLL(ctypes.util.find_library("IOKit"))
    cf = ctypes.CDLL(ctypes.util.find_library("CoreFoundation"))
    iokit.IOServiceMatching.restype = P_
    iokit.IOServiceMatching.argtypes = [ctypes.c_char_p]
    iokit.IOServiceGetMatchingServices.argtypes = [U_, P_, ctypes.POINTER(U_)]
    iokit.IOIteratorNext.restype = U_
    iokit.IOIteratorNext.argtypes = [U_]
    iokit.IOObjectRelease.argtypes = [U_]
    iokit.IORegistryEntryCreateCFProperty.restype = P_
    iokit.IORegistryEntryCreateCFProperty.argtypes = [U_, P_, P_, U_]
    cf.CFStringCreateWithCString.restype = P_
    cf.CFStringCreateWithCString.argtypes = [P_, ctypes.c_char_p, U_]
    cf.CFDictionaryGetValue.restype = P_
    cf.CFDictionaryGetValue.argtypes = [P_, P_]
    cf.CFNumberGetValue.argtypes = [P_, ctypes.c_int, P_]
    cf.CFRelease.argtypes = [P_]
    names = (
        "Statistics",
        "Bytes (Write)",
        "Operations (Write)",
        "Bytes (Read)",
        "Operations (Read)",
    )
    keys = [cf.CFStringCreateWithCString(None, k.encode(), 0x08000100) for k in names]
    it = U_(0)
    tot = [0, 0, 0, 0]
    try:
        # the matching dictionary's reference is consumed by IOServiceGetMatchingServices
        m = iokit.IOServiceMatching(b"IOBlockStorageDriver")
        if iokit.IOServiceGetMatchingServices(0, m, ctypes.byref(it)) != 0:
            return None
        while True:
            e = iokit.IOIteratorNext(it.value)
            if not e:
                break
            d = iokit.IORegistryEntryCreateCFProperty(e, keys[0], None, 0)
            if d:
                for i, k in enumerate(keys[1:]):
                    num, v = cf.CFDictionaryGetValue(d, k), ctypes.c_int64(0)
                    if num and cf.CFNumberGetValue(
                        num, 4, ctypes.byref(v)
                    ):  # kCFNumberSInt64Type
                        tot[i] += v.value
                cf.CFRelease(d)
            iokit.IOObjectRelease(e)
        return tot
    finally:
        if it.value:
            iokit.IOObjectRelease(it.value)
        for k in keys:
            cf.CFRelease(k)


class Sampler:
    def __init__(self):
        self.prev = None  # (ts, keys, cursor, host ticks, rates)
        self.fork_rate = None  # trailing valid reading
        self.buf = argbuf()
        self.disk = []  # (ts, [bytes_w, ops_w, bytes_r, ops_r]) over the last 24 h of passes

    def tick(self):
        cpu0 = time.thread_time()  # this thread: a pass may run beside it
        procs = proc_all()
        # stamped AFTER the read it dates: a tick starved between the two (12 s seen at load 60) would
        # otherwise credit a 17 s cursor advance to a 5 s interval (one 9,530/s reading, 2026-10-17)
        now = time.time()
        keys = {(p[0], p[5]) for p in procs}
        # the pid cursor: the pid of the most recently started process
        cursor = max(procs, key=lambda p: (p[5], p[0]))[0]
        ht = host_ticks()
        rates = {k: sysctl_int(k) for k in RATES}
        t = {
            "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now)),
            "t": round(now, 3),
        }
        t["n_procs"] = len(procs)
        la = sysctl_words("vm.loadavg", 3)
        if la:
            t["load1"] = round((la[0] & 0xFFFFFFFF) / float(la[2] or 2048), 2)
        t["gauge"] = {k.split(".")[-1]: sysctl_int(k) for k in GAUGES}
        sw = sysctl_words("vm.swapusage", 4)  # struct xsw_usage: total, avail, used
        if sw:
            t["swap_used_mb"] = round(sw[2] / 1048576.0)
        new = []
        if self.prev:
            pts, pkeys, pcur, pht, prates = self.prev
            el = now - pts
            t["el_s"] = round(el, 2)
            dp = cursor - pcur
            # A negative delta is a wrap when the cursor fell back by more than half the pid space
            # (at ~950 forks/s it laps every ~105 s, so most 5 s ticks see one sooner or later), or
            # when the trailing rate makes one plausible. A small fall-back means the newest pid
            # exited: no reading, and the cursor holds. Measured 2026-10-17: without the first arm a
            # held cursor near 99,999 read every tick after the first wrap as no reading (117/119).
            if dp < 0 and (
                -dp > PID_SPAN // 2
                or (self.fork_rate is not None and el * self.fork_rate > 50000)
            ):
                dp += PID_SPAN
            if el * MAX_FORKS_S > PID_SPAN:  # the cursor may have lapped unseen
                t["forks_per_s"] = None
            elif dp < 0:  # the newest pid exited: no reading, and the cursor holds
                t["forks_per_s"] = None
                cursor = pcur
            else:
                t["forks_per_s"] = self.fork_rate = round(dp / el, 1)
            t["rate"] = {
                k.split(".")[-1]: round((v - prates[k]) / el, 1)
                for k, v in rates.items()
                if v is not None and prates.get(k) is not None
            }
            if ht and pht:
                busy = sum(ht[0][i] - pht[i] for i in (0, 1, 3))
                idle = ht[0][2] - pht[2]
                t["cpu_busy_pct"] = round(100.0 * busy / max(busy + idle, 1), 1)
            new = [p for p in procs if (p[0], p[5]) not in pkeys and p[2] == MY_UID]
        # one proc_pid_rusage pass over uid 501: current footprint and its lifetime max
        ru = RusageV6()
        fp, tops = 0, []
        for pid, _, uid, _, comm, _ in procs:
            if (
                uid == MY_UID
                and libc.proc_pid_rusage(pid, RUSAGE_INFO_V6, ctypes.byref(ru)) == 0
            ):
                fp += ru.phys_footprint
                tops.append(
                    (ru.lifetime_max_phys_footprint, ru.phys_footprint, pid, comm)
                )
        tops.sort(reverse=True)
        t["fp_501_mb"] = round(fp / 1048576.0)
        t["top_fp"] = [
            {"pid": pid, "name": comm, "phys_footprint_mb": round(cur / 1048576.0),
             "lifetime_max_phys_footprint_mb": round(lmax / 1048576.0)}
            for lmax, cur, pid, comm in tops[:5]
        ]  # fmt: skip
        t["new"] = []
        for pid, ppid, _, _, comm, _ in new:
            argv, tag = procargs(pid, self.buf)
            t["new"].append({"pid": pid, "ppid": ppid, "comm": comm,
                             "argv": " ".join(argv or [])[:300], "cwd": pid_cwd(pid), "sid": tag})  # fmt: skip
        t["cursor"] = cursor
        self.prev = (now, keys, cursor, list(ht[0]) if ht else None, rates)
        t["self_cpu_ms"] = round((time.thread_time() - cpu0) * 1000, 1)
        return t

    def disk_rates(self):
        now, d = time.time(), read_disk()
        if d is None:
            return None
        self.disk = [x for x in self.disk if now - x[0] <= 86400] + [(now, d)]
        if len(self.disk) < 2:
            return None
        (pt, p), (t0, d0) = self.disk[-2], self.disk[0]
        el, dw, ow = now - pt, d[0] - p[0], d[1] - p[1]
        return {
            "disk_write_mb_s": round(dw / el / 1e6, 3),
            "disk_write_ops_s": round(ow / el, 1),
            "disk_kb_per_write": round(dw / 1024.0 / ow, 1) if ow > 0 else None,
            "disk_read_mb_s": round((d[2] - p[2]) / el / 1e6, 3),
            "disk_tb_written_per_day": round(
                (d[0] - d0[0]) / (now - t0) * 86400 / 1e12, 3
            ),
            "disk_window_s": round(now - t0),
        }


def write_atomic(path, obj):
    tmp = path + ".tmp.%d" % os.getpid()
    with open(tmp, "w") as fh:
        json.dump(obj, fh, separators=(",", ":"))
    os.replace(tmp, path)


class LiveDetectors:
    """D1-D9 (scripts/lib/capacity-detect.py, DESIGN §4.2) evaluated over every tick this daemon writes.

    Until this existed nothing called Detectors.step(): only `capacity-detect.py --replay` ran them, so
    no detector had ever seen a live tick and D2's 7 d record-only window, which X17's load-rung flip
    waits on, could not start. Record-only is the detectors' own contract; this only feeds them.

    Fail-open, as the sampler is: a module that will not load, or a step that throws, costs that tick's
    detector pass and is reported in attrib-latest.json, never the tick itself. The records go beside
    CC_CAP_ATTRIB_LOG (CC_CAP_DETECT_OUT overrides), so a test's scratch log keeps its detector rows too.
    The state is saved on the 60 s pass and at exit, and carries `since` and `ticks` across restarts:
    ticks x interval over the time since `since` is the evidence that the detectors ran CONTINUOUSLY,
    which the operator's activation script (52) reads before it flips the load rung."""

    def __init__(self, out_dir, interval):
        self.interval, self.det, self.err = interval, None, None
        self.out = (
            os.environ.get("CC_CAP_DETECT_OUT") or out_dir + "/capacity-detect.jsonl"
        )
        self.state_p = (
            os.environ.get("CC_CAP_DETECT_STATE")
            or out_dir + "/capacity-detect.state.json"
        )
        self.since, self.ticks = time.time(), 0
        try:
            import importlib.util

            p = os.path.join(
                os.path.dirname(os.path.realpath(__file__)), "capacity-detect.py"
            )
            spec = importlib.util.spec_from_file_location("capacity_detect", p)
            mod = importlib.util.module_from_spec(spec)
            # @dataclass resolves its annotations through sys.modules[cls.__module__], so the module
            # must be registered before it executes (an unregistered load fails on AttributeError).
            sys.modules[spec.name] = mod
            spec.loader.exec_module(mod)
            saved = {}
            try:
                with open(self.state_p) as fh:
                    saved = json.load(fh)
            except (OSError, ValueError):
                saved = {}
            if not isinstance(saved, dict):
                saved = {}
            if isinstance(saved.get("since"), (int, float)):
                self.since = float(saved["since"])
            if isinstance(saved.get("ticks"), int):
                self.ticks = saved["ticks"]
            self.det = mod.Detectors(saved.get("det"))
        except Exception as e:
            self.err = "load: " + repr(e)[:280]

    def step(self, row):
        if self.det is None:
            return
        try:
            recs = self.det.step(row, time.time())
            self.ticks += 1
            if recs:
                with open(self.out, "a") as fh:
                    fh.writelines(json.dumps(r, sort_keys=True) + "\n" for r in recs)
            self.err = None
        except Exception as e:
            self.err = "step: " + repr(e)[:280]

    def save(self):
        if self.det is None:
            return
        try:
            write_atomic(self.state_p, {"v": 1, "since": round(self.since, 3), "ticks": self.ticks,
                                        "det": self.det.state()})  # fmt: skip
        except Exception as e:
            self.err = "save: " + repr(e)[:280]

    def summary(self):
        return {"live": self.det is not None, "since": round(self.since, 3), "ticks": self.ticks,
                "interval": self.interval, "err": self.err}  # fmt: skip


def daemon(interval, max_ticks, top_n):
    import threading
    import traceback

    out_dir = os.path.dirname(LOG)
    os.makedirs(out_dir, exist_ok=True)
    latest_p, series_p = (
        out_dir + "/attrib-latest.json",
        out_dir + "/attrib-series.jsonl",
    )
    me = read_pid(os.getpid())
    # pid + start ("%d.%06d", the same key the rows use) let a reader prove the writer is still alive
    latest = {"v": 1, "pid": os.getpid(), "start": me["start"] if me else None, "interval": interval,
              "ticks": 0, "errors": 0, "err": None, "tick": None, "row": None, "row_t": None,
              "top": None, "disk": None}  # fmt: skip
    pas = {"thread": None}

    def run_pass():
        try:
            row = attrib_pass(
                True, top_n, lambda lines: latest.update(top=lines), threaded=True
            )
            latest.update(row=row, row_t=round(time.time(), 3))
        except Exception:
            sys.stderr.write(
                "%s pass: %s"
                % (time.strftime("%FT%TZ", time.gmtime()), traceback.format_exc())
            )

    sampler, last_pass, n, nxt = Sampler(), None, 0, time.time()
    dets = LiveDetectors(out_dir, interval)
    while not max_ticks or n < max_ticks:
        n += 1
        try:
            t = sampler.tick()
            if last_pass is None or time.time() - last_pass >= PASS_EVERY_S:
                last_pass = time.time()
                dets.save()
                th = pas["thread"]
                # one pass in flight at most; a slow one is skipped, not queued
                if th is None or not th.is_alive():
                    pas["thread"] = threading.Thread(target=run_pass, daemon=True)
                    pas["thread"].start()
                else:
                    t["pass_skipped"] = True
                t["disk"] = latest["disk"] = sampler.disk_rates()
            latest.update(tick=t, err=None)
            if os.path.exists(series_p) and os.path.getsize(series_p) > SERIES_MAX:
                os.replace(series_p, series_p + ".1")
            with open(series_p, "a") as fh:
                fh.write(json.dumps(t, separators=(",", ":")) + "\n")
            dets.step(
                t
            )  # over the row just written, so a --replay of the series sees the same input
        except Exception as e:
            latest["errors"] += 1
            latest["err"] = repr(e)[:300]
            sys.stderr.write(
                "%s tick %d: %s"
                % (time.strftime("%FT%TZ", time.gmtime()), n, traceback.format_exc())
            )
        latest.update(
            ticks=n,
            detectors=dets.summary(),
            hb=time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            hb_t=round(time.time(), 3),
        )
        try:
            write_atomic(latest_p, latest)
        except Exception:
            sys.stderr.write(
                "%s heartbeat: %s"
                % (time.strftime("%FT%TZ", time.gmtime()), traceback.format_exc())
            )
        if max_ticks and n >= max_ticks:
            break
        # a late tick is not made up with a burst
        nxt = max(nxt + interval, time.time())
        time.sleep(max(0.0, nxt - time.time()))
    dets.save()
    if pas["thread"] is not None:
        # a bounded run ends with its pass's row in attrib-latest.json
        pas["thread"].join(30)
        write_atomic(latest_p, latest)


def main():
    argv = sys.argv
    top_n = int(argv[argv.index("--top") + 1]) if "--top" in argv else 3
    if "--daemon" in argv:
        interval = (
            float(argv[argv.index("--interval") + 1]) if "--interval" in argv else 5.0
        )
        max_ticks = (
            int(argv[argv.index("--max-ticks") + 1]) if "--max-ticks" in argv else 0
        )
        return daemon(interval, max_ticks, top_n)

    def emit(lines):
        sys.stdout.write("".join(lines))
        sys.stdout.flush()

    attrib_pass("--no-write" not in argv, top_n, emit)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        sys.exit(0)
