"""boot_classify.py -- after a boot, preserve the last boot's evidence, then classify how it ended.

Run as:  $PY -I boot_classify.py run [--boot-epoch N] [--force]     (never via #!: DESIGN I1)
The sentinel spawns it detached after freeze_scan. Idempotent: a boot already classified exits 0
without rewriting. Exit 0 always, except 2 on usage. Kill switch CC_SENTINEL_BOOT_CLASSIFY=off.

Output: ~/.claude/autonomy/lockwatch/boot-<epoch>.json, <epoch> = THIS boot's kern.boottime sec:
  {v, class, confidence, first_signal_ts, evidence[], summary, boot_epoch, boot, prev_boot,
   window, preserved_dir, samplers, shutdown_reason}
  class: LOCKUP_DEVFS | LOCKUP_KITTY_RC | LOCKUP_UNKNOWN | STORM_COMPRESSOR | CLEAN, or null with
  deferred_to:"panic_scan" on a panic boot (the sentinel's rule: one death is recorded once).
  With no evidence the class is LOCKUP_UNKNOWN only when kern.shutdownreason says force_off, else
  CLEAN. It never fabricates a class.

Step 0 PRESERVES before it classifies (DESIGN C7, critique 2.4), into
~/Library/Logs/cc-forensics/<bootuuid>-postboot/ (a name capture.sh's retention never matches):
  * DiagnosticReports files in the window (shutdown_stall, .hang, .panic, ResetCounter .diag),
  * the last boot's lockwatch series: levels.jsonl, metrics-*.jsonl, ttymap.json, pty.json, state.json,
  * a bounded `log collect --start <last good metrics row - 30 min> --end <shutdown> --size 1024m`
    (300 s deadline, disposable setsid child with file stdio, abandoned at the deadline).
It then classifies FROM THE COPIES: macOS rotates the source reports away.

Stall reports are Spindump binary; they are converted with `spindump -i <f> -o <txt>` in a bounded
child (60 s, root-free). Signatures are counted on USER frames, which are stable across builds
(kernel frames are unsymbolicated without a KDK): an `lstat` leaf in ps/login/zsh/tty/ls or under
ttyname/devname_r; an `__open` leaf (the carrier-wait opener); a zombie bash whose parent is launchd.

Test seams: CC_LOCKWATCH_DIR, CC_FX_ROOT, CC_BC_REPORT_DIRS (colon list), CC_BC_LOGS_DIR,
CC_BC_SHUTDOWN_REASON, CC_BC_BOOT (uuid), CC_BC_NO_LOG=1, CC_BC_SPINDUMP, CC_FX_TRANSCRIPT_ROOTS.
"""

import calendar
import json
import os
import re
import shutil
import sys
import time

HERE = os.path.dirname(os.path.realpath(__file__))
sys.path.insert(0, HERE)
import diagnose  # noqa: E402
import libproc_probe as lp  # noqa: E402

HOME = os.path.expanduser("~")
LWDIR = os.environ.get("CC_LOCKWATCH_DIR") or os.path.join(
    HOME, ".claude", "autonomy", "lockwatch"
)
FXROOT = os.environ.get("CC_FX_ROOT") or os.path.join(
    HOME, "Library", "Logs", "cc-forensics"
)
LOGS = os.environ.get("CC_BC_LOGS_DIR") or os.path.join(HOME, ".claude", "logs")
REPORT_DIRS = [
    d
    for d in (
        os.environ.get("CC_BC_REPORT_DIRS")
        or "/Library/Logs/DiagnosticReports:%s/Library/Logs/DiagnosticReports" % HOME
    ).split(":")
    if d
]
SPINDUMP = os.environ.get("CC_BC_SPINDUMP") or "/usr/sbin/spindump"
REPORT_RE = re.compile(
    r"(shutdown_stall_.*|.*\.hang|.*\.panic|ResetCounter-.*\.diag|.*\.shutdownStall)$"
)
DEVFS_COMMS = ("ps", "login", "zsh", "tty", "ls")
SAMPLERS = (
    "capacity-alarm.jsonl",
    "compressor-sentinel.jsonl",
    "attrib.jsonl",
    "qos-census.jsonl",
)


def iso(t):
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(t)) if t else None


def read_json(p):
    try:
        with open(p) as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return None


def jsonl_rows(p):
    try:
        with open(p, errors="replace") as fh:
            for line in fh:
                try:
                    yield json.loads(line)
                except ValueError:
                    continue
    except OSError:
        return


def ts_of(row):
    t = row.get("ts")
    if isinstance(t, (int, float)):
        return float(t)
    if isinstance(t, str):
        try:
            return calendar.timegm(time.strptime(t[:19], "%Y-%m-%dT%H:%M:%S"))
        except ValueError:
            return None
    return None


def bounded(argv, out, deadline_s):
    """posix_spawn a setsid child with regular-file stdio; poll until it exits or the deadline.
    Returns rc, or None if abandoned (never killed: it may be in an uninterruptible wait)."""
    empty = out + ".in"
    open(empty, "w").close()
    fa = [
        (os.POSIX_SPAWN_OPEN, 0, empty, os.O_RDONLY, 0),
        (os.POSIX_SPAWN_OPEN, 1, out, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600),
        (
            os.POSIX_SPAWN_OPEN,
            2,
            out + ".err",
            os.O_WRONLY | os.O_CREAT | os.O_TRUNC,
            0o600,
        ),
    ]
    try:
        pid = os.posix_spawn(
            argv[0], argv, dict(os.environ), file_actions=fa, setsid=True
        )
    except OSError:
        return -1
    end = time.time() + deadline_s
    while time.time() < end:
        p, st = os.waitpid(pid, os.WNOHANG)
        if p == pid:
            return (
                os.waitstatus_to_exitcode(st)
                if hasattr(os, "waitstatus_to_exitcode")
                else st >> 8
            )
        time.sleep(0.5)
    return None


# ---------------------------------------------------------------- stall report parsing -----
def to_text(path, workdir):
    """A stall/hang report as text: as-is when already text, else via `spindump -i` (bounded)."""
    try:
        with open(path, "rb") as fh:
            head = fh.read(4096)
    except OSError:
        return None
    if b"Spindump binary format" not in head:
        try:
            with open(path, errors="replace") as fh:
                return fh.read()
        except OSError:
            return None
    out = os.path.join(workdir, os.path.basename(path) + ".txt")
    if not os.path.exists(out):
        rc = bounded([SPINDUMP, "-i", path, "-o", out], out + ".log", 60)
        if rc != 0 or not os.path.exists(out):
            return None
    try:
        with open(out, errors="replace") as fh:
            return fh.read()
    except OSError:
        return None


def parse_report(text):
    """Process blocks -> [{name, pid, zombie, parent, since_fork_s, leaves[], user_frames[]}] plus
    the report's Date/Time epoch."""
    t_report = None
    m = re.search(
        r"^Date/Time:\s+(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)(?:\.\d+)?\s+([+-]\d{4})",
        text,
        re.M,
    )
    if m:
        off = (
            int(m.group(2)[:3]) * 3600
            + (1 if m.group(2)[0] == "+" else -1) * int(m.group(2)[3:]) * 60
        )
        t_report = calendar.timegm(time.strptime(m.group(1), "%Y-%m-%d %H:%M:%S")) - off
    procs = []
    for blk in re.split(r"\n(?=Process:\s)", text):
        mh = re.match(r"Process:\s+(.+?) \[(\d+)\]([^\n]*)", blk)
        if not mh:
            continue
        p = {
            "name": mh.group(1).strip(),
            "pid": int(mh.group(2)),
            "zombie": "zombie" in mh.group(3),
            "parent": None,
            "parent_pid": None,
            "since_fork_s": None,
            "leaves": [],
            "user_frames": [],
        }
        mp = re.search(r"^Parent:\s+(.+?) \[(\d+)\]", blk, re.M)
        if mp:
            p["parent"], p["parent_pid"] = mp.group(1).strip(), int(mp.group(2))
        mf = re.search(r"^Time Since Fork:\s+(\d+)s", blk, re.M)
        if mf:
            p["since_fork_s"] = int(mf.group(1))
        for th in re.split(r"\n(?=\s+Thread 0x)", blk)[1:]:
            last_user = None
            for line in th.splitlines()[1:]:
                mm = re.match(r"\s+(\*?)(\d+)\s+(\S+)", line)
                if not mm:
                    if line.strip().startswith("Binary Images"):
                        break
                    continue
                if mm.group(1) == "*":
                    break  # kernel frames start: the last user frame was the leaf
                sym = mm.group(3)
                if sym != "???":
                    p["user_frames"].append(sym)
                last_user = sym if sym != "???" else (last_user or "???")
            if last_user:
                p["leaves"].append(last_user)
        procs.append(p)
    return procs, t_report


def report_signatures(procs, t_report):
    devfs, opens, zleaders = [], [], []
    for p in procs:
        frames = set(p["user_frames"])
        tty_path = bool(frames & {"ttyname", "ttyname_r", "devname", "devname_r"})
        if "lstat" in p["leaves"] and (p["name"] in DEVFS_COMMS or tty_path):
            devfs.append(p)
        elif "__open" in p["leaves"]:
            opens.append(p)
        if p["zombie"] and p["parent_pid"] == 1 and p["name"] in ("bash", "zsh", "sh"):
            zleaders.append(p)
    first = None
    if t_report:
        starts = [
            t_report - p["since_fork_s"] for p in devfs if p["since_fork_s"] is not None
        ]
        first = min(starts) if starts else None
    return {"devfs": devfs, "opens": opens, "zleaders": zleaders, "first": first}


# ---------------------------------------------------------------- classification ----------
def prev_boot_of(cur):
    runs = os.path.join(LWDIR, "run")
    best = None
    try:
        for n in os.listdir(runs):
            if n == cur:
                continue
            mt = os.stat(os.path.join(runs, n)).st_mtime
            if best is None or mt > best[1]:
                best = (n, mt)
    except OSError:
        pass
    return best[0] if best else None


def last_row_ts(path, before):
    """ts of the last row at or before `before`, reading only the file's tail."""
    try:
        sz = os.path.getsize(path)
        with open(path, "rb") as fh:
            fh.seek(max(0, sz - 262144))
            tail = fh.read().decode("utf-8", "replace").splitlines()
    except OSError:
        return None
    for line in reversed(tail):
        try:
            t = ts_of(json.loads(line))
        except ValueError:
            continue
        if t is not None and t <= before:
            return t
    return None


def last_reboot_before(epoch, workdir):
    """Start of the PREVIOUS boot from wtmp (`last reboot`, run bounded into a file; it prints the
    stored ut_line and never resolves a tty). Minute resolution, no year: the newest entry at least
    2 min before this boot, year inferred. None when unavailable."""
    os.makedirs(workdir, exist_ok=True)
    out = os.path.join(workdir, "last-reboot.txt")
    if bounded([os.environ.get("CC_BC_LAST", "/usr/bin/last"), "reboot"], out, 20) != 0:
        return None
    year = time.gmtime(epoch).tm_year
    best = None
    try:
        with open(out, errors="replace") as fh:
            for line in fh:
                m = re.search(r"reboot\s+time\s+\w{3}\s+(\w{3})\s+(\d+)\s+(\d\d):(\d\d)", line)
                if not m:
                    continue
                for y in (year, year - 1):
                    try:
                        t = time.mktime(time.strptime("%d %s %s %s:%s" % ((y,) + m.groups()), "%Y %b %d %H:%M"))
                    except ValueError:
                        continue
                    if t <= epoch - 120:
                        best = max(best or 0, t)
                        break
    except OSError:
        return None
    return best


def preserve(dest, cur_epoch, prev, w0):
    """Copy the evidence, once. Returns the manifest dict."""
    marker = os.path.join(dest, ".preserved")
    if os.path.exists(marker):
        return read_json(marker) or {}
    os.makedirs(os.path.join(dest, "DiagnosticReports"), exist_ok=True)
    copied = []
    for d in REPORT_DIRS:
        try:
            names = os.listdir(d)
        except OSError:
            continue
        for n in names:
            src = os.path.join(d, n)
            if not REPORT_RE.match(n) or n.startswith("."):
                continue
            try:
                mt = os.stat(src).st_mtime
            except OSError:
                continue
            if w0 - 60 <= mt <= cur_epoch + 1800:
                try:
                    shutil.copy2(src, os.path.join(dest, "DiagnosticReports", n))
                    copied.append(n)
                except OSError:
                    pass
    series = os.path.join(dest, "lockwatch")
    os.makedirs(series, exist_ok=True)
    for n in ("levels.jsonl", "state.json", "pty.json", "shadow-audit.json"):
        try:
            shutil.copy2(os.path.join(LWDIR, n), os.path.join(series, n))
        except OSError:
            pass
    try:
        for n in os.listdir(LWDIR):
            if n.startswith("metrics-") and n.endswith(".jsonl"):
                try:
                    shutil.copy2(os.path.join(LWDIR, n), os.path.join(series, n))
                except OSError:
                    pass
    except OSError:
        pass
    if prev:
        for n in ("ttymap.json",):
            try:
                shutil.copy2(
                    os.path.join(LWDIR, "run", prev, n), os.path.join(series, n)
                )
            except OSError:
                pass
    log = {"skipped": True}
    if os.environ.get("CC_BC_NO_LOG") != "1":
        last_good = None
        for n in sorted(os.listdir(series)):
            if n.startswith("metrics-"):
                t = last_row_ts(os.path.join(series, n), cur_epoch)
                last_good = max(last_good or 0, t or 0) or last_good
        start = (last_good or cur_epoch - 3600) - 1800
        argv = [
            "/usr/bin/log",
            "collect",
            "--start",
            time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(start)),
            "--end",
            time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(cur_epoch)),
            "--size",
            "1024m",
            "--output",
            os.path.join(dest, "logs.logarchive"),
        ]
        rc = bounded(argv, os.path.join(dest, "log-collect.out"), 300)
        log = {
            "rc": rc,
            "start": iso(start),
            "end": iso(cur_epoch),
            "abandoned": rc is None,
        }
    man = {"ts": iso(time.time()), "reports": sorted(copied), "log_collect": log}
    with open(marker, "w") as fh:
        json.dump(man, fh)
    return man


def kitty_peer_count(dest):
    la = os.path.join(dest, "logs.logarchive")
    if not os.path.isdir(la):
        return None
    out = os.path.join(dest, "kitty-peers.txt")
    rc = bounded(
        [
            "/usr/bin/log",
            "show",
            "--archive",
            la,
            "--style",
            "compact",
            "--predicate",
            'eventMessage CONTAINS "Too many peers"',
        ],
        out,
        120,
    )
    if rc != 0:
        return None
    n = 0
    try:
        with open(out, errors="replace") as fh:
            for line in fh:
                if "Too many peers" in line:
                    n += 1
    except OSError:
        return None
    return n


def compressor_trips(w1):
    n = 0
    p = os.path.join(LOGS, "compressor-sentinel-snap.log")
    try:
        with open(p, errors="replace") as fh:
            for line in fh:
                m = re.search(r"TRIP (\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ)", line)
                if m:
                    t = calendar.timegm(time.strptime(m.group(1), "%Y-%m-%dT%H:%M:%SZ"))
                    if w1 - 1800 <= t <= w1:
                        n += 1
    except OSError:
        pass
    return n


def classify(dest, cur_epoch, prev, w0, shutdown_reason):
    ev = []
    first = []
    rep_dir = os.path.join(dest, "DiagnosticReports")
    work = os.path.join(dest, "converted")
    os.makedirs(work, exist_ok=True)
    reports = sorted(os.listdir(rep_dir)) if os.path.isdir(rep_dir) else []
    if any(n.endswith(".panic") for n in reports):
        return {
            "class": None,
            "deferred_to": "panic_scan",
            "confidence": "n/a",
            "evidence": [
                {
                    "source": "DiagnosticReports",
                    "file": n,
                    "detail": "panic report: left to panic_scan",
                }
                for n in reports
                if n.endswith(".panic")
            ],
            "first_signal_ts": None,
            "summary": "panic boot: classification deferred to the sentinel's panic_scan",
        }
    sig_devfs = 0
    sig = None
    for n in reports:
        if not (
            n.startswith("shutdown_stall")
            or n.endswith(".hang")
            or n.endswith(".shutdownStall")
        ):
            continue
        text = to_text(os.path.join(rep_dir, n), work)
        if not text:
            ev.append(
                {
                    "source": "DiagnosticReports",
                    "file": n,
                    "detail": "unreadable/unconverted",
                }
            )
            continue
        procs, t_rep = parse_report(text)
        s = report_signatures(procs, t_rep)
        ev.append(
            {
                "source": "DiagnosticReports",
                "file": n,
                "detail": "procs=%d devfs_sleepers=%d open_sleepers=%d zombie_leaders=%s"
                % (
                    len(procs),
                    len(s["devfs"]),
                    len(s["opens"]),
                    [p["pid"] for p in s["zleaders"]],
                ),
            }
        )
        if len(s["devfs"]) > sig_devfs:
            sig_devfs, sig = len(s["devfs"]), s
        if s["first"]:
            first.append(s["first"])
    lv = []
    for row in diagnose_rows(os.path.join(dest, "lockwatch", "levels.jsonl")):
        if prev and row.get("boot") not in (prev, None):
            continue
        lv.append(row)
    lv_max = max([r.get("to") or 0 for r in lv] or [0])
    lv_verdicts = set(r.get("verdict") for r in lv if r.get("verdict"))
    if lv:
        ev.append(
            {
                "source": "levels.jsonl",
                "file": "lockwatch/levels.jsonl",
                "detail": "max level L%d, verdicts %s" % (lv_max, sorted(lv_verdicts)),
            }
        )
        t1 = [ts_of(r) for r in lv if (r.get("to") or 0) >= 1]
        if t1 and t1[0]:
            first.append(t1[0])
    bundles = []
    try:
        for n in sorted(os.listdir(FXROOT)):
            dj = read_json(os.path.join(FXROOT, n, "diagnosis.json"))
            if dj and w0 <= os.stat(os.path.join(FXROOT, n)).st_mtime <= cur_epoch:
                bundles.append((n, dj))
    except OSError:
        pass
    for n, dj in bundles:
        if dj.get("verdict") not in (None, "none"):
            ev.append(
                {
                    "source": "bundle",
                    "file": n,
                    "detail": dj.get("summary") or dj.get("verdict"),
                }
            )
    b_verdicts = set(dj.get("verdict") for _n, dj in bundles)
    peers = kitty_peer_count(dest)
    if peers is not None:
        ev.append(
            {
                "source": "log show",
                "file": "logs.logarchive",
                "detail": "kitty 'Too many peers' x%d" % peers,
            }
        )
    trips = compressor_trips(cur_epoch)
    if trips:
        ev.append(
            {
                "source": "compressor-sentinel-snap.log",
                "file": "",
                "detail": "%d TRIP(s) in the last 30 min" % trips,
            }
        )
    devfs_lw = bool(
        lv_verdicts & {"devfs_lookup_stall"}
        or any(str(v).startswith("devfs_poison") for v in lv_verdicts)
        or b_verdicts & {"devfs_poison", "devfs_lookup_stall"}
    )
    out = {"first_signal_ts": iso(min(first)) if first else None, "evidence": ev}
    if sig_devfs >= 5 or devfs_lw:
        strong = (
            sig is not None and sig_devfs >= 5 and (sig["opens"] or sig["zleaders"])
        )
        out.update(
            {
                "class": "LOCKUP_DEVFS",
                "confidence": "high"
                if (strong or (devfs_lw and sig_devfs >= 5))
                else "medium",
            }
        )
        pids = []
        if sig:
            pids = (
                [p["pid"] for p in sig["zleaders"]]
                + [p["pid"] for p in sig["opens"]]
                + [
                    p["parent_pid"]
                    for p in sig["opens"]
                    if p["parent_pid"] and p["parent_pid"] != 1
                ]
            )
        if pids and os.environ.get("CC_BC_NO_CAUSE") != "1":
            since = min(first) if first else None
            hits, stats = diagnose.cause_scan(
                sorted(set(pids)),
                since,
                None,
                kill_guard=os.path.join(LWDIR, "kill-guard.jsonl"),
            )
            for h in hits[:5]:
                ev.append(
                    {
                        "source": "cause",
                        "file": h["file"],
                        "detail": "%s session %s cwd %s: %s"
                        % (h["ts"], h["session"], h["cwd"], h["command"]),
                    }
                )
            out["cause_scan"] = stats
            out["cause"] = hits[:5]
        out["summary"] = (
            "LOCKUP_DEVFS: %d processes asleep in the /dev lookup path%s%s"
            % (
                sig_devfs,
                (", zombie session leader(s) %s" % [p["pid"] for p in sig["zleaders"]])
                if sig and sig["zleaders"]
                else "",
                (", cause: %s" % out["cause"][0]["command"])
                if out.get("cause")
                else "",
            )
        )
        return out
    if (peers or 0) >= 1 or "kitty_rc_deaf" in lv_verdicts | b_verdicts:
        out.update(
            {
                "class": "LOCKUP_KITTY_RC",
                "confidence": "medium",
                "summary": "LOCKUP_KITTY_RC: kitty remote control saturated (%s peer refusals)"
                % peers,
            }
        )
        return out
    if trips:
        out.update(
            {
                "class": "STORM_COMPRESSOR",
                "confidence": "medium",
                "summary": "STORM_COMPRESSOR: %d compressor-sentinel trip(s) in the last 30 min"
                % trips,
            }
        )
        return out
    if lv_max >= 1 or [b for b in b_verdicts if b not in (None, "none")]:
        out.update(
            {
                "class": "LOCKUP_UNKNOWN",
                "confidence": "low",
                "summary": "LOCKUP_UNKNOWN: lockwatch reached L%d, no class signature matched"
                % lv_max,
            }
        )
        return out
    if not reports and "force_off" in (shutdown_reason or ""):
        out.update(
            {
                "class": "LOCKUP_UNKNOWN",
                "confidence": "low",
                "summary": "LOCKUP_UNKNOWN: no evidence, and kern.shutdownreason=%r"
                % shutdown_reason,
            }
        )
        return out
    out.update(
        {
            "class": "CLEAN",
            "confidence": "medium" if reports else "low",
            "summary": "CLEAN: no lockup signature in %d report(s)" % len(reports),
        }
    )
    return out


def diagnose_rows(p):
    return list(jsonl_rows(p))


def samplers(cur_epoch):
    out = {}
    for n in SAMPLERS:
        t = last_row_ts(os.path.join(LOGS, n), cur_epoch)
        out[n] = {
            "last_ts": iso(t),
            "dark_minutes": round((cur_epoch - t) / 60.0, 1) if t else None,
        }
    return out


def run(argv):
    if os.environ.get("CC_SENTINEL_BOOT_CLASSIFY", "on") == "off":
        return 0
    epoch = None
    if "--boot-epoch" in argv:
        epoch = int(argv[argv.index("--boot-epoch") + 1])
    if epoch is None:
        epoch = int(lp.boottime() or time.time())
    os.makedirs(LWDIR, exist_ok=True)
    out_path = os.path.join(LWDIR, "boot-%d.json" % epoch)
    if (
        os.path.exists(out_path)
        and "--force" not in argv
        and (read_json(out_path) or {}).get("v")
    ):
        return 0
    cur = os.environ.get("CC_BC_BOOT") or lp.boot_uuid()
    prev = prev_boot_of(cur)
    w0 = epoch - 86400 * 7
    if prev:
        lvp = [
            ts_of(r)
            for r in jsonl_rows(os.path.join(LWDIR, "levels.jsonl"))
            if r.get("boot") == prev
        ]
        cands = [t for t in lvp if t]
        tm = read_json(os.path.join(LWDIR, "run", prev, "ttymap.json")) or {}
        cands += [e.get("first_seen") for e in tm.values() if isinstance(e, dict) and e.get("first_seen")]
        if cands:
            w0 = max(w0, min(cands))
    lr = last_reboot_before(epoch, os.path.join(FXROOT, ".bc-work-%d" % epoch))
    if lr:
        w0 = lr  # wtmp knows the previous boot's start exactly: reports before it are another boot's
    # the window always covers at least the last hour before this boot (shutdown stalls land there)
    w0 = min(w0, epoch - 3600)
    dest = os.path.join(FXROOT, "%s-postboot" % cur)
    man = preserve(dest, epoch, prev, w0)
    reason = os.environ.get("CC_BC_SHUTDOWN_REASON")
    if reason is None:
        reason = lp.sysctl_str("kern.shutdownreason") or ""
    res = classify(dest, epoch, prev, w0, reason)
    doc = {
        "v": 1,
        "class": res.get("class"),
        "confidence": res.get("confidence"),
        "first_signal_ts": res.get("first_signal_ts"),
        "evidence": res.get("evidence", []),
        "summary": res.get("summary"),
        "boot_epoch": epoch,
        "boot": cur,
        "prev_boot": prev,
        "window": {"start": iso(w0), "end": iso(epoch)},
        "preserved_dir": dest,
        "preserved": man,
        "samplers": samplers(epoch),
        "shutdown_reason": reason,
        "ts": iso(time.time()),
    }
    for k in ("deferred_to", "cause", "cause_scan"):
        if k in res:
            doc[k] = res[k]
    tmp = out_path + ".tmp.%d" % os.getpid()
    with open(tmp, "w") as fh:
        json.dump(doc, fh, indent=1)
    os.rename(tmp, out_path)
    print("boot_classify: %s -> %s" % (doc["class"], out_path))
    return 0


def main(argv):
    if not argv or argv[0] != "run":
        sys.stderr.write("usage: boot_classify.py run [--boot-epoch N] [--force]\n")
        return 2
    return run(argv[1:])


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
