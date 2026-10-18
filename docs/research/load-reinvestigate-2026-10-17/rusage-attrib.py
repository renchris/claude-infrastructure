#!/usr/bin/env python3
"""Interval CPU attribution incl. reaped children (proc_pid_rusage flavor 2).
Usage: lr2-rusage.py SECONDS"""

import ctypes, ctypes.util, subprocess, sys, time, re, collections

lib = ctypes.CDLL(ctypes.util.find_library("c"))


class RU(ctypes.Structure):
    _fields_ = [("uuid", ctypes.c_uint8 * 16)] + [
        (n, ctypes.c_uint64)
        for n in (
            "user",
            "sys",
            "piw",
            "iw",
            "pageins",
            "wired",
            "resident",
            "foot",
            "start",
            "exit",
            "cuser",
            "csys",
            "cpiw",
            "ciw",
            "cpageins",
            "celapsed",
            "rd",
            "wr",
        )
    ]


class TB(ctypes.Structure):
    _fields_ = [("numer", ctypes.c_uint32), ("denom", ctypes.c_uint32)]


tb = TB()
lib.mach_timebase_info(ctypes.byref(tb))
NS = tb.numer / tb.denom


def snap():
    out = subprocess.run(
        ["ps", "-axww", "-o", "pid=,ppid=,args="],
        capture_output=True,
        text=True,
        timeout=90,
    ).stdout
    pp, args, ru = {}, {}, {}
    for l in out.splitlines():
        m = re.match(r"\s*(\d+)\s+(\d+)\s?(.*)", l)
        if not m:
            continue
        p = int(m.group(1))
        pp[p] = int(m.group(2))
        args[p] = m.group(3)
        r = RU()
        if lib.proc_pid_rusage(p, 2, ctypes.byref(r)) == 0:
            ru[p] = (
                (r.user + r.sys) * NS / 1e9,
                (r.cuser + r.csys) * NS / 1e9,
                r.start,
            )
    return pp, args, ru


RULES = [
    (
        "TrueMemory tm2 team (tm-upstream-wt / tm2-*)",
        ("tm-upstream-wt", "tm2-", "truememory", "session-ad2417e7"),
    ),
    ("agent-context-sync gates (b13/r14)", ("/b13/", "agent-context-sync")),
    ("agent-browser + headless Chrome", ("agent-browser",)),
    ("reso session", ("reso-management-app",)),
    ("research-kit classifier (haiku -p)", ("research-kit",)),
    ("claude-infrastructure sessions", ("claude-infrastructure",)),
    ("personal sessions", ("Development-personal",)),
    ("kitty", ("kitty.app",)),
    ("Dia browser", ("Dia.app",)),
    ("Hammerspoon", ("Hammerspoon",)),
]


def is_claude(a):
    return (
        bool(re.search(r"(/claude(\.exe)?)( |$)", a.split(" --")[0]))
        or "claude-code/bin/claude.exe" in a
    )


def group(p, pp, args):
    chain = []
    q = p
    for _ in range(25):
        if q not in args:
            break
        chain.append(args[q])
        q = pp.get(q)
        if not q or q <= 1:
            break
    joined = "\n".join(chain)
    for name, keys in RULES:
        if any(k in joined for k in keys):
            return name
    return "other: " + (
        args.get(p, "?").split()[0].split("/")[-1][:40] if args.get(p) else "?"
    )


secs = float(sys.argv[1]) if len(sys.argv) > 1 else 30
pp1, a1, r1 = snap()
t1 = time.time()
time.sleep(secs)
pp2, a2, r2 = snap()
t2 = time.time()
dt = t2 - t1
agg = collections.Counter()
selfc = collections.Counter()
childc = collections.Counter()
for p, (s2, c2, st2) in r2.items():
    s1, c1, st1 = r1.get(p, (0.0, 0.0, None))
    if st1 is not None and st1 != st2:
        s1, c1 = 0.0, 0.0  # pid reuse
    g = group(p, pp2, a2)
    claude_self = is_claude(a2.get(p, ""))
    ds, dc = max(0, s2 - s1), max(0, c2 - c1)
    key_self = (g + " [claude binary self]") if claude_self else g
    agg[key_self] += ds
    agg[g + (" [reaped tool children]" if claude_self else "")] += dc
tot = sum(agg.values())
print(
    f"interval {dt:.1f}s  attributed {tot / dt * 100:.0f}% CPU (=cores x100), uid-501 only, incl. reaped children"
)
for k, v in agg.most_common(40):
    if v / dt * 100 < 1:
        continue
    print(f"{v / dt * 100:7.1f}%  {v / tot * 100:5.1f}%  {k}")
