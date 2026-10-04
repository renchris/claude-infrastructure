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


def procargs(pid):
    """-> (argv list, env-tag or None), via KERN_PROCARGS2. Same uid only; no sudo."""
    global _ARGMAX
    if _ARGMAX is None:
        v = ctypes.c_int(0)
        sz = ctypes.c_size_t(ctypes.sizeof(v))
        mib = (ctypes.c_int * 2)(CTL_KERN, KERN_ARGMAX)
        libc.sysctl(mib, 2, ctypes.byref(v), ctypes.byref(sz), None, 0)
        _ARGMAX = v.value or 1048576
    buf = ctypes.create_string_buffer(_ARGMAX)
    sz = ctypes.c_size_t(_ARGMAX)
    mib = (ctypes.c_int * 3)(CTL_KERN, KERN_PROCARGS2, pid)
    if libc.sysctl(mib, 3, buf, ctypes.byref(sz), None, 0) != 0:
        return None, None
    raw = buf.raw[: sz.value]
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


def main():
    t_start = time.time()
    write = "--no-write" not in sys.argv
    top_n = 3
    if "--top" in sys.argv:
        top_n = int(sys.argv[sys.argv.index("--top") + 1])

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
    for mb, pid, name in cands[:top_n]:
        sys.stdout.write(
            "%d %.0f %s\n" % (pid, mb, name.replace('"', "").replace("\\", ""))
        )
    sys.stdout.flush()

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
        # reap correction: nearest ancestor alive at BOTH ticks absorbs -cum_A(gone), per counter
        prev_by_pid = {int(k.split("@")[0]): k for k in pa}
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
                    du[ak] -= a[1] + a[3]
                    ds[ak] -= a[2] + a[4]
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
                dp += 99999 - 100  # pids wrap at 99,999 back to ~100
            row["forks_per_s"] = round(dp / el, 1)
        if exec_hook is not None and prev.get("exec_hook") is not None:
            row["exec_hook_dt"] = (
                exec_hook - prev["exec_hook"]
            )  # tracks execs; ratio unconfirmed (B1)
        row["attrib_s"] = round(attrib, 1)
        row["uid501_s"] = round(uid501, 1)
        row["other_uid_s"] = round(other_s, 1)
        row["unseen_s"] = round(busy - attrib, 1)
        row["neg_s"] = round(neg, 2)
        row["accounting"] = "overflow" if busy > 0 and attrib > busy * 1.05 else "ok"
        top = sorted(buckets.items(), key=lambda kv: -kv[1])
        bk = {k: round(v, 2) for k, v in top[:MAX_BUCKETS] if round(v, 2) != 0}
        rest = sum(v for _, v in top[MAX_BUCKETS:])
        if rest:
            bk["rest"] = round(rest, 2)
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
    row["self_cpu_s"] = round(rs.ru_utime + rs.ru_stime + rc.ru_utime + rc.ru_stime, 3)
    row["self_wall_s"] = round(time.time() - t_start, 3)

    if not write:
        return
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


if __name__ == "__main__":
    try:
        main()
    except Exception:
        sys.exit(0)
