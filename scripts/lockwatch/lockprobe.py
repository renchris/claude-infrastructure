"""lockprobe.py -- the lockwatch sensing core: canaries, levels, capture, diagnosis, pages.

Run as:  $PY -I lockprobe.py run [--max-ticks N]       the long-lived core (the sentinel spawns it)
         $PY -I lockprobe.py status                    print state.json and hb age (files only)
         $PY -I lockprobe.py replay FILE               feed recorded observations through rules.py
Never via #! exec (DESIGN I1). $PY is the first of: python.org 3.11, the Xcode 3.9 framework python,
the CommandLineTools 3.9 framework python, /usr/bin/python3; all Mach-O. Stdlib only, 3.9 syntax.

Shape (DESIGN §2, C1): ONE thread, a 2 s tick. Per tick the core makes only I3 calls: sysctlbyname
scalars, host_processor_info, thread_info on its own thread, mach time, kill(2), flock, a
non-blocking write to the spawner pipe, waitpid(WNOHANG), and reads / writes / renames of regular
files under the state dir. NO exec, NO /dev, NO KERN_PROC_*, NO proc_pidinfo: those run in probe
children forked by the SPAWNER, which the core forks once at start and recreates if it wedges.
Probes are disposable setsid children with regular-file stdio, one outstanding per type; one that
does not return is `stuck:<type>` -- itself a signal -- and is abandoned, never killed.

Outputs (DESIGN §5), all under $CC_LOCKWATCH_DIR (default ~/.claude/autonomy/lockwatch):
  state.json (5 s + on change) · hb (every tick) · levels.jsonl · metrics-YYYYMMDD.jsonl (10 s) ·
  pty.json · procscan.json · run/<bootuuid>/ttymap.json · shadow-audit.json · actions.jsonl ·
  lockprobe.pid ("pid lstart_epoch bootuuid") · .lease (flock: a second instance exits 0)

Switches: CC_LOCKWATCH=off (exit 0) · CC_LOCKWATCH_UNPOISON=off|observe|on (default observe: log
WOULD rows; `on` runs rescue.sh unpoison at L2 -- [RCA-DEP], operator decision) ·
CC_LOCKWATCH_SHADOW_SNAPSHOT=off (shadow rules request no precursor snapshot).
Test seams: CC_LOCKWATCH_DIR, CC_LOCKWATCH_TICK_S, CC_LOCKWATCH_PROBE_<TYPE> (argv, shlex; {out}),
CC_LOCKWATCH_EVERY_<TYPE> (seconds), CC_LOCKWATCH_ACTION_<NAME> (argv for capture|page|unpoison|
roster), CC_LOCKWATCH_STANDALONE=1 (skip the getppid()==1 exit), CC_LOCKWATCH_NO_SELFTEST=1.
"""

import errno
import fcntl
import calendar
import json
import os
import select
import shlex
import sys
import time

HERE = os.path.dirname(os.path.realpath(__file__))
sys.path.insert(0, HERE)
import libproc_probe as lp  # noqa: E402
import rules  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(HERE))
HOME = os.path.expanduser("~")
DIR = os.environ.get("CC_LOCKWATCH_DIR") or os.path.join(
    HOME, ".claude", "autonomy", "lockwatch"
)
TICK = float(os.environ.get("CC_LOCKWATCH_TICK_S") or 2.0)
PY = sys.executable or "/usr/bin/python3"
ME = os.getuid()
_floor = os.environ.get("CC_LOCKWATCH_P11_FLOOR_S")
if _floor:
    rules.THRESHOLDS["P11_floor_s"] = {
        k: float(_floor) for k in rules.THRESHOLDS["P11_floor_s"]
    }

EVERY = {
    "procscan": 10.0,
    "pty": 30.0,
    "pty_l1": 10.0,
    "walk": 30.0,
    "walk_l1": 10.0,
    "fdscan": 300.0,
}
STUCK_CAP = {"procscan": 2}
ACTION_DEADLINE = {"capture": 180.0, "page": 60.0, "unpoison": 120.0, "roster": 60.0}


def _now():
    return time.time()


def _iso(t=None):
    return time.strftime(
        "%Y-%m-%dT%H:%M:%SZ", time.gmtime(t if t is not None else _now())
    )


def _env_every(typ):
    v = os.environ.get("CC_LOCKWATCH_EVERY_%s" % typ.upper())
    try:
        return float(v) if v else EVERY[typ]
    except ValueError:
        return EVERY[typ]


def atomic_json(path, doc, fullsync=False):
    tmp = "%s.tmp.%d" % (path, os.getpid())
    data = json.dumps(doc, separators=(",", ":"), sort_keys=False) + "\n"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    try:
        os.write(fd, data.encode())
        if fullsync and hasattr(fcntl, "F_FULLFSYNC"):
            try:
                fcntl.fcntl(fd, fcntl.F_FULLFSYNC)
            except OSError:
                pass
    finally:
        os.close(fd)
    os.rename(tmp, path)


def append_jsonl(path, row, fullsync=False):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
    try:
        os.write(fd, (json.dumps(row, separators=(",", ":")) + "\n").encode())
        if fullsync and hasattr(fcntl, "F_FULLFSYNC"):
            try:
                fcntl.fcntl(fd, fcntl.F_FULLFSYNC)
            except OSError:
                pass
    finally:
        os.close(fd)


def read_json(path):
    try:
        with open(path) as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return None


# ---------------------------------------------------------------- spawner ------------------
def spawner_main(rfd, core_pid, events_path, empty, hb_path):
    """The forked spawner: posix_spawn only, never opens /dev, never waits on a child."""
    try:
        os.setsid()
    except OSError:
        pass
    ev = os.open(events_path, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
    hb = os.open(hb_path, os.O_WRONLY | os.O_CREAT, 0o600)
    buf = b""
    kids = {}
    n = 0

    def emit(row):
        row["ts"] = round(_now(), 3)
        os.write(ev, (json.dumps(row, separators=(",", ":")) + "\n").encode())

    while True:
        if os.getppid() != core_pid:
            os._exit(0)
        try:
            rl, _, _ = select.select([rfd], [], [], 0.5)
        except (OSError, ValueError):
            os._exit(0)
        if rl:
            data = os.read(rfd, 65536)
            if not data:
                os._exit(
                    0
                )  # the core closed our pipe: a replacement spawner owns the work now
            buf += data
            while b"\n" in buf:
                line, buf = buf.split(b"\n", 1)
                try:
                    req = json.loads(line.decode())
                except ValueError:
                    continue
                t0 = _now()
                fa = [
                    (os.POSIX_SPAWN_OPEN, 0, empty, os.O_RDONLY, 0),
                    (
                        os.POSIX_SPAWN_OPEN,
                        1,
                        req["stdout"],
                        os.O_WRONLY | os.O_CREAT | os.O_TRUNC,
                        0o600,
                    ),
                    (
                        os.POSIX_SPAWN_OPEN,
                        2,
                        req["stderr"],
                        os.O_WRONLY | os.O_CREAT | os.O_TRUNC,
                        0o600,
                    ),
                ]
                env = dict(os.environ)
                env.update(req.get("env") or {})
                try:
                    pid = os.posix_spawn(
                        req["argv"][0], req["argv"], env, file_actions=fa, setsid=True
                    )
                except (OSError, ValueError, TypeError) as e:
                    emit(
                        {
                            "ev": "spawn_fail",
                            "id": req["id"],
                            "type": req["type"],
                            "err": str(e),
                        }
                    )
                    continue
                kids[pid] = req["id"]
                emit(
                    {
                        "ev": "spawned",
                        "id": req["id"],
                        "type": req["type"],
                        "pid": pid,
                        "spawn_ms": round((_now() - t0) * 1000, 2),
                    }
                )
        while kids:
            try:
                pid, st = os.waitpid(-1, os.WNOHANG)
            except ChildProcessError:
                break
            if pid == 0:
                break
            rid = kids.pop(pid, None)
            rc = (
                os.waitstatus_to_exitcode(st)
                if hasattr(os, "waitstatus_to_exitcode")
                else (st >> 8)
            )
            emit({"ev": "exited", "id": rid, "pid": pid, "rc": rc})
        n += 1
        line = ("%d %.3f %d\n" % (n, _now(), len(kids))).encode()
        os.pwrite(hb, line, 0)
        os.ftruncate(hb, len(line))


# ---------------------------------------------------------------- core ---------------------
class Core:
    def __init__(self, max_ticks=None):
        self.max_ticks = max_ticks
        self.boot = lp.boot_uuid()
        self.pid = os.getpid()
        self.run = os.path.join(DIR, "run", self.boot)
        self.pdir = os.path.join(self.run, "probe")
        for d in (DIR, self.run, self.pdir):
            os.makedirs(d, exist_ok=True)
        self.empty = os.path.join(self.run, ".empty")
        if not os.path.exists(self.empty):
            open(self.empty, "w").close()
        self.seq = 0
        self.req_id = 0
        self.m = rules.new_machine()
        self.probes = {
            t: {"out": {}, "stuck": {}, "dur": [], "res": None, "seq": 0, "due": 0.0}
            for t in ("procscan", "pty", "walk", "fdscan", "selftest")
        }
        self.actions = {}  # id -> {"name", "t", "pid", "rc", "stdout", "meta"}
        self.ev_path = os.path.join(self.run, "spawner-events.jsonl")
        self.ev_off = (
            os.path.getsize(self.ev_path) if os.path.exists(self.ev_path) else 0
        )
        self.spawn_ms = None
        self.sp_pid = None
        self.sp_w = None
        self.sp_starts = []
        self.oversleep = []
        self.startlat = []  # probe request -> its own `started` line: the child-starvation gauge
        self.last_cont_minus_abs = lp.mach_cont_s() - lp.mach_abs_s()
        self.ttymap = read_json(os.path.join(self.run, "ttymap.json")) or {}
        self.orphan_since = {}
        self.stuck_cand = {}
        self.prev_procs = {}
        self.kitty = {
            "pid": None,
            "t0": None,
            "t0_changed": None,
            "socks_at_change": None,
            "sockets": None,
        }
        self.cpu_prev = lp.cpu_ticks()
        self.cpu = {"usr": None, "sys": None, "idle": None}
        self.band = None
        self.last_state_write = 0.0
        self.last_state_sig = None
        self.last_ttymap_write = 0.0
        self.last_audit = 0.0
        self.last_snapshot_req = 0.0
        self.ep = {}  # per-episode action memory
        self.res = {}
        self.reasons = []
        self.shadow = []
        self.verdict = "starting"
        self.join = None
        self.walk_last = {"last": None, "since": None, "pid": None}
        self.lstart = 0
        self.selftest = "pending"
        self.p6_done = set()
        self.last_capture_dir = None
        self.audit = read_json(os.path.join(DIR, "shadow-audit.json")) or {}
        self.m["fires"] = {k: v for k, v in (self.audit.get("fires") or {}).items()}
        self.m["noisy"] = {
            k: v
            for k, v in (self.audit.get("noisy_state") or {}).items()
            if v.get("version") == rules.RULES_VERSION
        }
        self.hb_fd = os.open(os.path.join(DIR, "hb"), os.O_WRONLY | os.O_CREAT, 0o600)
        self.phase_name = "init"
        self._restore()

    # -- liveness -------------------------------------------------------------------------
    def phase(self, name):
        """Written BEFORE each risky step (I6), so a wedge names the step it stopped in."""
        self.phase_name = name
        line = (
            "%d %s %.3f %.3f %d %s\n"
            % (
                self.seq,
                name,
                lp.mach_abs_s(),
                getattr(self, "tick_end", 0.0),
                self.pid,
                self.boot,
            )
        ).encode()
        os.pwrite(self.hb_fd, line, 0)
        os.ftruncate(self.hb_fd, len(line))

    def _restore(self):
        st = read_json(os.path.join(DIR, "state.json"))
        if (
            st
            and st.get("boot") == self.boot
            and _now() - float(st.get("ts_epoch", 0)) < 120
        ):
            self.m["level"] = int(st.get("level") or 0)
            self.m["level_since"] = st.get("level_since_epoch")
            self.m["episode"] = st.get("episode")
            self.ep = st.get("episode_actions") or {}

    def write_pidfile(self):
        tmp = os.path.join(DIR, "lockprobe.pid.tmp")
        with open(tmp, "w") as fh:
            fh.write("%d %d %s\n" % (self.pid, self.lstart, self.boot))
        os.rename(tmp, os.path.join(DIR, "lockprobe.pid"))

    # -- spawner --------------------------------------------------------------------------
    def start_spawner(self):
        now = _now()
        self.sp_starts = [t for t in self.sp_starts if now - t < 3600]
        if len(self.sp_starts) >= 6:
            return False
        if self.sp_w is not None:
            try:
                os.close(self.sp_w)
            except OSError:
                pass
        r, w = os.pipe()
        pid = os.fork()
        if pid == 0:
            try:
                os.close(w)
                spawner_main(
                    r,
                    self.pid,
                    self.ev_path,
                    self.empty,
                    os.path.join(self.run, "spawner.hb"),
                )
            finally:
                os._exit(0)
        os.close(r)
        fl = fcntl.fcntl(w, fcntl.F_GETFL)
        fcntl.fcntl(w, fcntl.F_SETFL, fl | os.O_NONBLOCK)
        self.sp_pid, self.sp_w = pid, w
        self.sp_starts.append(now)
        return True

    def spawner_alive(self):
        if self.sp_pid is None:
            return False
        try:
            pid, _ = os.waitpid(self.sp_pid, os.WNOHANG)
            if pid == self.sp_pid:
                return False
        except ChildProcessError:
            return False
        try:
            age = _now() - os.stat(os.path.join(self.run, "spawner.hb")).st_mtime
        except OSError:
            age = 0.0
        return age < 30.0

    def request(self, typ, argv, stdout, env=None):
        self.req_id += 1
        rid = "%s-%d-%d" % (typ, self.pid, self.req_id)
        line = (
            json.dumps(
                {
                    "id": rid,
                    "type": typ,
                    "argv": argv,
                    "stdout": stdout,
                    "stderr": stdout + ".err",
                    "env": env or {},
                }
            )
            + "\n"
        )
        if self.sp_w is None:
            return None
        try:
            os.write(self.sp_w, line.encode())
        except (BlockingIOError, BrokenPipeError, OSError):
            return None
        return rid

    def read_events(self):
        try:
            fd = os.open(self.ev_path, os.O_RDONLY)
        except OSError:
            return []
        try:
            size = os.fstat(fd).st_size
            if size < self.ev_off:
                self.ev_off = 0
            data = (
                os.pread(fd, size - self.ev_off, self.ev_off)
                if size > self.ev_off
                else b""
            )
        finally:
            os.close(fd)
        out = []
        cut = data.rfind(b"\n")
        if cut < 0:
            return out
        self.ev_off += cut + 1
        for line in data[: cut + 1].splitlines():
            try:
                out.append(json.loads(line.decode()))
            except ValueError:
                pass
        return out

    # -- probes ---------------------------------------------------------------------------
    def probe_argv(self, typ, out):
        ov = os.environ.get("CC_LOCKWATCH_PROBE_%s" % typ.upper())
        if ov:
            return [a.replace("{out}", out) for a in shlex.split(ov)], out
        if typ == "procscan":
            return [
                PY,
                "-I",
                os.path.join(ROOT, "scripts", "forensics", "procscan.py"),
                "--threads-for",
                ",".join(rules.STUCK_COMMS),
                "--out",
                out,
            ], out
        if typ == "pty":
            return [PY, "-I", os.path.join(HERE, "ptycanary.py"), "--out", out], out
        if typ == "walk":
            return [
                "/usr/bin/perl",
                os.path.join(ROOT, "scripts", "forensics", "devfs-canary.pl"),
                self.run,
                "5",
            ], out
        if typ == "fdscan":
            return [PY, "-I", os.path.join(HERE, "fdscan.py"), "--out", out], out
        if typ == "selftest":
            return [
                PY,
                "-I",
                os.path.join(ROOT, "scripts", "forensics", "procscan.py"),
                "--selftest",
                str(self.pid),
                str(os.getppid()),
                str(os.getpgrp()),
                "--out",
                out,
            ], out
        raise ValueError(typ)

    def launch(self, typ, now):
        p = self.probes[typ]
        out = os.path.join(self.pdir, "%s.%d.out" % (typ, self.req_id + 1))
        argv, out = self.probe_argv(typ, out)
        stdout = out if typ == "walk" else out + ".stdout"
        rid = self.request(typ, argv, stdout)
        if rid is None:
            return
        p["out"][rid] = {
            "t": now,
            "out": out,
            "stdout": stdout,
            "pid": None,
            "rc": None,
        }

    def stuck_limit(self, typ):
        dur = sorted(self.probes[typ]["dur"][-100:])
        p99 = dur[min(len(dur) - 1, int(0.99 * (len(dur) - 1)))] if dur else 0.0
        k = min(max(1.0, self.starv.get("ratio", 1.0)), rules.THRESHOLDS["starv_cap"])
        return max(
            rules.THRESHOLDS["P11_floor_s"].get(typ, 30.0),
            rules.THRESHOLDS["P11_mult"] * p99,
        ) * k, p99

    def parse_result(self, typ, o):
        if typ == "walk":
            try:
                with open(o["stdout"]) as fh:
                    line = fh.read().strip().splitlines()
            except OSError:
                return None
            if not line:
                return None
            kv = {}
            rest = line[-1]
            if 'last="' in rest:
                rest, last = rest.split('last="', 1)
                kv["last"] = last.rstrip('"')
            for tok in rest.split():
                if "=" in tok:
                    a, b = tok.split("=", 1)
                    kv[a] = b
            for f in ("scan_ms", "stuck_s", "after_s", "wall_ms", "pid"):
                if f in kv:
                    try:
                        kv[f] = float(kv[f])
                    except ValueError:
                        pass
            if kv.get("verdict") == "OK" and "worst" in kv:
                kv.setdefault("last", None)
            return kv if kv.get("verdict") else None
        d = read_json(o["out"])
        if d is None:
            return None
        if typ == "pty" and d.get("phase") != "done":
            o["pty_spawned"] = d
            return None
        return d

    def read_phase(self, o):
        """First `started <t>` line and last phase of a python probe's stdout (a regular file)."""
        if o.get("stdout") == o.get("out"):
            o["phase"] = "n/a"  # the walk canary prints one line at its end; no phases
            return
        try:
            with open(o["stdout"]) as fh:
                lines = fh.read(4096).split("\n")
        except OSError:
            return
        lines = [x for x in lines if x.strip()]
        if not lines:
            return
        if "started" not in o and lines[0].startswith("started "):
            try:
                o["started"] = float(lines[0].split()[1])
                self.startlat.append(max(0.0, o["started"] - o["t"]))
                self.startlat = self.startlat[-30:]
            except (IndexError, ValueError):
                pass
        o["phase"] = lines[-1].split()[0]

    def poll_probes(self, now):
        for ev in self.read_events():
            rid = ev.get("id")
            if ev.get("ev") == "spawned" and ev.get("spawn_ms") is not None:
                self.spawn_ms = ev["spawn_ms"]
            for p in list(self.probes.values()):
                o = p["out"].get(rid) or p["stuck"].get(rid)
                if o is not None:
                    if ev.get("ev") == "spawned":
                        o["pid"] = ev.get("pid")
                    elif ev.get("ev") in ("exited", "spawn_fail"):
                        o["rc"] = ev.get("rc", -1)
            a = self.actions.get(rid)
            if a is not None:
                if ev.get("ev") == "spawned":
                    a["pid"] = ev.get("pid")
                elif ev.get("ev") in ("exited", "spawn_fail"):
                    a["rc"] = ev.get("rc", -1)
                    a["t_end"] = now
                    if a["name"] == "capture" and a["rc"] == 0:
                        self.last_capture_dir = self.bundle_dir(a) or self.last_capture_dir
        for typ, p in self.probes.items():
            for o in list(p["out"].values()) + list(p["stuck"].values()):
                self.read_phase(o)
            for rid in list(p["stuck"]):
                o = p["stuck"][rid]
                if o.get("rc") is not None or self.parse_result(typ, o) is not None:
                    del p["stuck"][rid]
            for rid in list(p["out"]):
                o = p["out"][rid]
                res = self.parse_result(typ, o)
                if res is not None or o.get("rc") is not None:
                    del p["out"][rid]
                    p["dur"].append(now - o["t"])
                    p["dur"] = p["dur"][-200:]
                    if res is None:
                        res = {"verdict": "ERROR", "rc": o.get("rc")}
                    res["_rc"] = o.get("rc")
                    res["_t"] = now
                    p["seq"] += 1
                    p["res"] = res
                    self.on_result(typ, res, now)
                    for f in (
                        o["out"],
                        o["stdout"],
                        o["stdout"] + ".err",
                        o["out"] + ".stdout.err",
                    ):
                        if f != os.path.join(DIR, "procscan.json"):
                            try:
                                os.unlink(f)
                            except OSError:
                                pass
                    continue
                lim, _ = self.stuck_limit(typ)
                if typ != "pty" and now - o["t"] > lim:
                    cap = STUCK_CAP.get(typ, 1)
                    if len(p["stuck"]) < cap:
                        p["stuck"][rid] = o  # abandoned, never killed
                        del p["out"][rid]

    def schedule(self, now):
        lvl = self.m["level"]
        for typ in ("procscan", "pty", "walk", "fdscan"):
            p = self.probes[typ]
            every = _env_every(typ)
            if lvl >= 1 and typ in ("pty", "walk"):
                every = min(every, _env_every(typ + "_l1"))
            if p["out"]:
                continue  # one outstanding per type
            if p["stuck"] and len(p["stuck"]) >= STUCK_CAP.get(typ, 1):
                continue  # per-type stuck cap: no new victims
            if now >= p["due"]:
                p["due"] = now + every
                self.launch(typ, now)

    # -- results --------------------------------------------------------------------------
    def on_result(self, typ, res, now):
        if typ == "selftest":
            if res.get("selftest") == "ok":
                self.selftest = "ok"
                self.lstart = int((res.get("row") or {}).get("lstart") or 0)
                self.write_pidfile()
            else:
                self.selftest = "blind"
        elif typ == "procscan" and res.get("procs"):
            self.on_procscan(res, now)
        elif typ == "walk":
            last = res.get("last")
            if res.get("verdict") in ("WEDGED", "WEDGED_PREVIOUS"):
                same = (
                    last == self.walk_last["last"]
                    and res.get("pid") == self.walk_last["pid"]
                )
                if not same:
                    self.walk_last = {
                        "last": last,
                        "since": now
                        - float(res.get("stuck_s") or res.get("after_s") or 0)
                        if self.walk_last["pid"] == res.get("pid")
                        else now,
                        "pid": res.get("pid"),
                    }
                res["last_steady_s"] = now - self.walk_last["since"] if same else 0.0
                if same:
                    res["last_steady_s"] = max(
                        res["last_steady_s"], float(res.get("stuck_s") or 0)
                    )
            else:
                self.walk_last = {"last": None, "since": None, "pid": None}
        elif typ == "fdscan":
            self.fdscan = res

    def on_procscan(self, res, now):
        procs = res["procs"]
        rules.ttymap_update(self.ttymap, procs, now)
        byk = {}
        kids = {}
        for p in procs:
            byk["%d:%d" % (p["pid"], p.get("lstart", 0))] = p
            kids.setdefault(p["ppid"], []).append(p)
        # P4 stuck census: short-lived comms in uninterruptible sleep with no CPU progress, or a
        # login with no child; persistent across scans for >= P4_age_s x starvation
        k = min(max(1.0, self.starv.get("ratio", 1.0)), rules.THRESHOLDS["starv_cap"])
        cand = {}
        for key, p in byk.items():
            if p["comm"] not in rules.STUCK_COMMS or p.get("stat") == "Z":
                continue
            prev = self.prev_procs.get(key)
            if p.get("uid") == ME:
                hit = (
                    bool((p.get("tstates") or {}).get("U"))
                    and prev is not None
                    and prev.get("cpu_s") == p.get("cpu_s")
                )
            else:
                hit = (
                    p["comm"] == "login"
                    and not kids.get(p["pid"])
                    and now - p.get("lstart", now) > 60
                )
            if hit:
                cand[key] = self.stuck_cand.get(key, now)
        self.stuck_cand = cand
        stuck = [
            (key, now - t0)
            for key, t0 in cand.items()
            if now - t0 >= rules.THRESHOLDS["P4_age_s"] * k
        ]
        self.stuck = {
            "n": len(stuck),
            "oldest_s": int(max([a for _, a in stuck] or [0])),
            "pids": [
                int(key.split(":")[0])
                for key, _ in sorted(stuck, key=lambda x: -x[1])[:4]
            ],
        }
        # leaders (P5/P6) with exiting/orphan ages
        leaders = rules.pty_leaders(procs, self.ttymap)
        seen = set()
        for L in leaders:
            key = "%d:%d" % (L["pid"], L["lstart"])
            seen.add(key)
            L["exiting_s"] = (
                int(now - L["exiting_since"]) if L.get("exiting_since") else 0
            )
            if L["orphan"]:
                self.orphan_since.setdefault(key, now)
                L["orphan_s"] = int(now - self.orphan_since[key])
            else:
                self.orphan_since.pop(key, None)
                L["orphan_s"] = 0
        for key in list(self.orphan_since):
            if key not in seen:
                del self.orphan_since[key]
        self.leaders = leaders
        # kitty: thread-0 CPU progress against its RC socket count (P7/P8)
        kp = [p for p in procs if p["pid"] in (res.get("kitty") or [])]
        if kp:
            kt = kp[0]
            if (
                kt["pid"] != self.kitty["pid"]
                or kt.get("t0_cpu_ns") != self.kitty["t0"]
            ):
                self.kitty.update(
                    pid=kt["pid"],
                    t0=kt.get("t0_cpu_ns"),
                    t0_changed=now,
                    socks_at_change=kt.get("sockets"),
                )
            self.kitty["sockets"] = kt.get("sockets")
            ch = kids.get(kt["pid"], [])
            self.kitty["zombies"] = sum(1 for c in ch if c.get("stat") == "Z")
            live = [now - c.get("lstart", now) for c in ch if c.get("stat") != "Z"]
            self.kitty["newest_child_age_s"] = int(min(live)) if live else None
        else:
            self.kitty = {
                "pid": None,
                "t0": None,
                "t0_changed": None,
                "socks_at_change": None,
                "sockets": None,
            }
        # CPU rates for the top-N (snapshot suspects), from two scans
        rates = []
        for key, p in byk.items():
            prev = self.prev_procs.get(key)
            if prev and p.get("cpu_s") is not None and prev.get("cpu_s") is not None:
                dt = now - prev.get("_t", now)
                if dt > 0:
                    rates.append(
                        (
                            round((p["cpu_s"] - prev["cpu_s"]) / dt * 100, 1),
                            p["pid"],
                            p["comm"],
                        )
                    )
        rates.sort(reverse=True)
        self.top_cpu = [{"pid": pid, "comm": c, "pct": r} for r, pid, c in rates[:5]]
        for p in procs:
            p["_t"] = now
        self.prev_procs = byk
        self.procs = procs
        self.procs_total = len(procs)
        # publish the table for lane B's census and the pty view for B/D/rescue
        try:
            atomic_json(
                os.path.join(DIR, "procscan.json"),
                {
                    "v": 1,
                    "ts_epoch": int(now),
                    "boot": self.boot,
                    "procs": [
                        {
                            k2: v
                            for k2, v in p.items()
                            if not k2.startswith("_") and k2 not in ("U_threads",)
                        }
                        for p in procs
                    ],
                },
            )
        except OSError:
            pass
        self.write_pty_json(now)

    def write_pty_json(self, now):
        fd = getattr(self, "fdscan", None) or {}
        members_open = []
        if self.join and self.join.get("holder"):
            members_open.append(self.join["holder"])
        atomic_json(
            os.path.join(DIR, "pty.json"),
            {
                "v": 1,
                "ts": _iso(now),
                "ts_epoch": int(now),
                "boot": self.boot,
                "ttl_s": 90,
                "leaders": [
                    {
                        k: L.get(k)
                        for k in (
                            "pid",
                            "lstart",
                            "pgid",
                            "tdev",
                            "tty",
                            "ppid",
                            "state",
                            "exiting",
                            "orphan",
                        )
                    }
                    for L in getattr(self, "leaders", [])
                ],
                "master_holders": fd.get("masters", {}),
                "slave_holders": fd.get("slaves", {}),
                "orphan_slaves": fd.get("orphan_slaves", []),
                "members_open": members_open,
                "poison": {
                    k: (self.join or {}).get(k)
                    for k in ("tty", "leader", "lstart", "pgid", "holder", "targets", "unkillable")
                }
                if self.join
                else None,
            },
        )

    # -- observation, rules, actions ------------------------------------------------------
    def observe(self, now):
        pty = {"state": "none", "seq": self.probes["pty"]["seq"]}
        pp = self.probes["pty"]
        if pp["out"]:
            o = list(pp["out"].values())[0]
            sp = o.get("pty_spawned")
            if sp is None:
                self.parse_result("pty", o)
                sp = o.get("pty_spawned")
            t0 = float(sp["t0"]) if sp and sp.get("t0") else o["t"]
            age = now - t0
            if age >= 1.0:
                pty = {
                    "state": "outstanding",
                    "age_s": round(age, 2),
                    "seq": "o%d" % int(age / 5),
                    "zsh_pid": (sp or {}).get("zsh_pid"),
                }
        if pty["state"] == "none" and pp["res"] is not None:
            r = pp["res"]
            pty = {
                "state": "done",
                "ms": r.get("zsh_ms"),
                "seq": pp["seq"],
                "verdict": r.get("verdict"),
            }
        wr = self.probes["walk"]["res"] or {}
        walk = dict(wr, seq=self.probes["walk"]["seq"])
        ages = {}
        p99s = {}
        phases = {}
        for typ in ("procscan", "walk", "fdscan"):
            p = self.probes[typ]
            olds = sorted(
                ((now - o["t"], o.get("phase") or "")
                 for o in list(p["out"].values()) + list(p["stuck"].values())),
                key=lambda a: a[0],
            )
            if olds:
                ages[typ], phases[typ] = olds[-1]
            p99s[typ] = self.stuck_limit(typ)[1]
        kt = self.kitty
        kitty = {
            "present": kt.get("pid") is not None,
            "sockets": kt.get("sockets"),
            "t0_flat_s": (now - kt["t0_changed"]) if kt.get("t0_changed") else 0.0,
            "sockets_growth": (kt.get("sockets") or 0)
            - (kt.get("socks_at_change") or 0),
        }
        return {
            "now": now,
            "starv": self.starv,
            "pty": pty,
            "walk": walk,
            "procscan": {"seq": self.probes["procscan"]["seq"]},
            "stuck": getattr(self, "stuck", {"n": 0}),
            "leaders": getattr(self, "leaders", []),
            "kitty": kitty,
            "probe_age": ages,
            "probe_p99": p99s,
            "probe_phase": phases,
        }

    def act(self, now, prev_level):
        lvl = self.m["level"]
        ep = self.ep
        if lvl == 0:
            if prev_level != 0:
                self.ep = {}
            return
        if lvl >= 1 and not ep.get("snapshot") and prev_level == 0:
            ep["snapshot"] = now
            self.capture("snapshot", "L1-%s" % self.verdict, force=False)
        if lvl >= 2:
            if not ep.get("full_ok"):
                a = self.actions.get(ep.get("capture_id") or "")
                busy = (
                    a is not None
                    and a.get("rc") is None
                    and now - a["t"] < ACTION_DEADLINE["capture"]
                )
                if not busy:
                    if a is not None and a.get("rc") == 0:
                        d = self.bundle_dir(a)
                        if d and os.path.exists(os.path.join(d, "diagnosis.json")):
                            ep["full_ok"] = d
                            self.on_diagnosis(d)
                    if a is not None and a.get("rc") not in (None, 75):
                        ep["capture_tries"] = ep.get("capture_tries", 0) + 1
                    # rc 75 = busy or rate-limited: free to retry every tick. Anything else
                    # costs a full ~430 MB bundle, so at most 3 per episode.
                    if not ep.get("full_ok") and ep.get("capture_tries", 0) < 3:
                        ep["capture_id"] = self.capture(
                            "full", "L2-%s" % self.verdict, force=True
                        )
            ep.setdefault("l2_t", now)
            if not ep.get("paged_l2") and (ep.get("full_ok") or now - ep["l2_t"] >= 90):
                ep["paged_l2"] = now
                self.page(2)
            u = ep.get("unpoison") or {}
            if u.get("id") and u.get("done_ts") is None:
                ua = self.actions.get(u["id"])
                if ua is not None and ua.get("rc") is not None:
                    u["done_ts"] = now
                    u["rc"] = ua["rc"]
            if self.join and not ep.get("unpoison"):
                mode = os.environ.get("CC_LOCKWATCH_UNPOISON", "observe")
                if mode != "off":
                    ep["unpoison"] = {
                        "mode": mode,
                        "pgid": self.join["pgid"],
                        "leader": self.join["leader"],
                        "lstart": self.join["lstart"],
                    }
                    if mode == "on":
                        rid = self.action(
                            "unpoison",
                            [str(self.join["pgid"]), str(self.join["lstart"])],
                        )
                        ep["unpoison"]["id"] = rid
                        ep["unpoison"]["done_ts"] = None
                    else:
                        ep["unpoison"]["would_ts"] = now
                        append_jsonl(
                            os.path.join(DIR, "actions.jsonl"),
                            {
                                "ts": _iso(now),
                                "boot": self.boot,
                                "by": "lockprobe",
                                "action": "unpoison",
                                "mode": "observe",
                                "result": "WOULD",
                                "pgid": self.join["pgid"],
                                "leader": self.join["leader"],
                                "lstart": self.join["lstart"],
                                "holder": self.join.get("holder"),
                                "tty": self.join["tty"],
                                "command": "/bin/bash ~/.claude/scripts/break-glass/rescue.sh unpoison %d %d"
                                % (self.join["pgid"], self.join["lstart"]),
                            },
                        )
        if lvl >= 3:
            if not ep.get("paged_l3"):
                ep["paged_l3"] = now
                self.page(3)
                ep["roster_id"] = self.action("roster", [])
                ep["l3_capture"] = self.capture(
                    "full", "L3-%s" % self.verdict, force=True
                )

    def unpoison_failed(self):
        u = self.ep.get("unpoison") or {}
        a = self.actions.get(u.get("id") or "")
        return bool(a and a.get("rc") == 1)

    def bundle_dir(self, a):
        try:
            with open(a["stdout"]) as fh:
                lines = [x.strip() for x in fh if x.strip()]
            return lines[-1] if lines and os.path.isdir(lines[-1]) else None
        except OSError:
            return None

    def on_diagnosis(self, d):
        dj = read_json(os.path.join(d, "diagnosis.json")) or {}
        if dj.get("verdict") == "devfs_poison" and dj.get("pgid"):
            self.join = dict(
                self.join or {},
                tty=dj.get("tty"),
                leader=dj.get("leader"),
                lstart=dj.get("lstart"),
                pgid=dj.get("pgid"),
                holder=dj.get("holder"),
            )
        self.diag = dj

    def action_argv(self, name, args):
        ov = os.environ.get("CC_LOCKWATCH_ACTION_%s" % name.upper())
        if ov:
            return shlex.split(ov) + args
        if name == "capture":
            return [
                "/bin/bash",
                os.path.join(ROOT, "scripts", "forensics", "capture.sh"),
            ] + args
        if name == "page":
            return [
                "/bin/bash",
                os.path.join(ROOT, "scripts", "limit-recover", "lr-page.sh"),
            ] + args
        if name == "unpoison":
            return [
                "/bin/bash",
                os.path.join(ROOT, "scripts", "break-glass", "rescue.sh"),
                "unpoison",
            ] + args
        if name == "roster":
            return [
                "/bin/bash",
                os.path.join(ROOT, "scripts", "alarm-reboot-prep.sh"),
                "--files-only",
            ] + args
        raise ValueError(name)

    def action(self, name, args, env=None):
        stdout = os.path.join(self.run, "action-%s-%d.out" % (name, self.req_id + 1))
        rid = self.request(
            "action:" + name, self.action_argv(name, args), stdout, env=env
        )
        if rid:
            self.actions[rid] = {
                "name": name,
                "t": _now(),
                "pid": None,
                "rc": None,
                "stdout": stdout,
            }
            append_jsonl(
                os.path.join(DIR, "actions.jsonl"),
                {
                    "ts": _iso(),
                    "boot": self.boot,
                    "by": "lockprobe",
                    "action": name,
                    "args": args,
                    "id": rid,
                },
            )
        return rid

    def capture(self, tier, reason, force):
        if os.environ.get("CC_FX", "on") == "off":
            return None
        env = {"CC_FX_FORCE": "1"} if force else {}
        env["CC_LOCKWATCH_DIR"] = DIR
        return self.action("capture", [tier, reason], env=env)

    def page(self, level):
        j = self.join or {}
        cure = ""
        if j.get("pgid"):
            cure = (
                " Cure (R17): /bin/bash ~/.claude/scripts/break-glass/rescue.sh unpoison %s %s"
                " -- do NOT kill the leader by pid and do NOT kill kitty."
                % (j["pgid"], j.get("lstart"))
            )
            if j.get("targets"):
                cure += " Session tree to kill, opener first: %s." % " ".join(
                    str(x) for x in j["targets"]
                )
        b = self.ep.get("full_ok") or ""
        msg = "lockwatch L%d %s: %s.%s%s" % (
            level,
            "DIAGNOSE" if level == 2 else "ESCALATE",
            self.verdict,
            cure,
            (" Bundle: %s" % b) if b else "",
        )
        if level == 3:
            msg += " Still stuck after 10 min: files-only roster written; use Apple menu > Restart if unpoison fails."
        self.action("page", ["--title", "lockwatch L%d" % level, "--", msg])

    def shadow_actions(self, now):
        for s in self.shadow:
            if (
                s["rule"] in ("P5", "P6")
                and os.environ.get("CC_LOCKWATCH_SHADOW_SNAPSHOT", "on") != "off"
            ):
                if now - self.last_snapshot_req >= 300:
                    self.last_snapshot_req = now
                    self.capture("snapshot", "shadow-%s" % s["rule"], force=False)
            if s["rule"] == "P6":
                for L in (self.res.get("P6") or {}).get("hits", []):
                    key = "p6:%d:%d" % (L["pid"], L["lstart"])
                    if key in self.p6_done:
                        continue
                    self.p6_done.add(key)
                    append_jsonl(
                        os.path.join(DIR, "actions.jsonl"),
                        {
                            "ts": _iso(now),
                            "boot": self.boot,
                            "by": "lockprobe",
                            "action": "unpoison",
                            "mode": "shadow",
                            "result": "WOULD",
                            "rule": "P6",
                            "pgid": L["pgid"],
                            "leader": L["pid"],
                            "lstart": L["lstart"],
                            "tty": L.get("tty"),
                        },
                    )

    # -- outputs --------------------------------------------------------------------------
    def state_doc(self, now):
        pr = self.probes
        wr = pr["walk"]["res"] or {}
        prr = pr["pty"]["res"] or {}
        po = self.observe_cache.get("pty", {}) if hasattr(self, "observe_cache") else {}
        u = self.ep.get("unpoison") or {}
        cap = {
            "last_dir": self.ep.get("full_ok"),
            "last_ts": self.ep.get("snapshot"),
            "full_ok": bool(self.ep.get("full_ok")),
        }
        return {
            "v": 1,
            "seq": self.seq,
            "pid": self.pid,
            "boot": self.boot,
            "ts": _iso(now),
            "ts_epoch": int(now),
            "ttl_s": 90,
            "mode": "phase1",
            "level": self.m["level"],
            "level_since": _iso(self.m["level_since"])
            if self.m.get("level_since")
            else None,
            "level_since_epoch": self.m.get("level_since"),
            "episode": self.m.get("episode"),
            "verdict": self.verdict,
            "reasons": self.reasons[:8],
            "shadow": self.shadow[:8],
            "band_pri": self.band[1] if self.band else None,
            "kitty_rc": self.kitty_rc(),
            "selftest": self.selftest,
            "canary": {
                "zsh_ms": prr.get("zsh_ms")
                if po.get("state") != "outstanding"
                else int(po.get("age_s", 0) * 1000),
                "walk_ms": wr.get("scan_ms"),
                "stuck_s": wr.get("stuck_s") or wr.get("after_s"),
                "last_node": wr.get("last") if wr.get("verdict") != "OK" else None,
                "walk_verdict": wr.get("verdict"),
                "zsh_pid": po.get("zsh_pid"),
                "walk_pid": wr.get("pid"),
            },
            "stuck": {
                k: v for k, v in getattr(self, "stuck", {"n": 0, "oldest_s": 0}).items()
            },
            "probes_stuck": {t: len(p["stuck"]) for t, p in pr.items() if p["stuck"]},
            "exiting": [
                L["pid"] for L in getattr(self, "leaders", []) if L.get("exiting")
            ],
            "orphan_leaders": [
                L["pid"] for L in getattr(self, "leaders", []) if L.get("orphan")
            ],
            "ptys": (getattr(self, "fdscan", None) or {}).get("ptys"),
            "procs": getattr(self, "procs_total", None),
            "threads": lp.sysctl_int("kern.num_threads"),
            "spawn_ms": self.spawn_ms,
            "cpu": self.cpu,
            "starvation_ms": self.starv.get("p90_ms"),
            "unpoison": {
                "mode": os.environ.get("CC_LOCKWATCH_UNPOISON", "observe"),
                "pgid": u.get("pgid"),
                "leader": u.get("leader"),
                "lstart": u.get("lstart"),
                "would_ts": u.get("would_ts"),
                "done_ts": u.get("done_ts"),
            },
            "join": self.join,
            "capture": cap,
            "episode_actions": self.ep,
            "noisy": sorted(self.m["noisy"]),
        }

    def kitty_rc(self):
        if self.kitty.get("pid") is None or self.probes["procscan"]["res"] is None:
            return "unknown"
        r8 = self.res.get("P8") or {}
        if r8.get("x", 0) >= rules.THRESHOLDS["l2_frac"]:
            return "dead"
        return "ok"

    def metrics_row(self, now):
        day = time.strftime("%Y%m%d", time.gmtime(now))
        st = getattr(self, "stuck", {"n": 0})
        row = {
            "ts": _iso(now),
            "boot": self.boot,
            "level": self.m["level"],
            "verdict": self.verdict,
            "zsh_ms": (self.probes["pty"]["res"] or {}).get("zsh_ms"),
            "walk_ms": (self.probes["walk"]["res"] or {}).get("scan_ms"),
            "stuck_n": st.get("n"),
            "ptys": (getattr(self, "fdscan", None) or {}).get("ptys"),
            "procs": getattr(self, "procs_total", None),
            "threads": lp.sysctl_int("kern.num_threads"),
            "files": lp.sysctl_int("kern.num_files"),
            "vnodes": lp.sysctl_int("kern.num_vnodes"),
            "kitty_zombies": self.kitty.get("zombies"),
            "kitty_newest_child_s": self.kitty.get("newest_child_age_s"),
            "kitty_sockets": self.kitty.get("sockets"),
            "spawn_ms": self.spawn_ms,
            "top_cpu": getattr(self, "top_cpu", []),
            "cpu": self.cpu,
            "starv": self.starv,
            "load1": (lp.sysctl_loadavg() or [None])[0],
            "band_pri": self.band[1] if self.band else None,
            "x": {k: round(v["x"], 3) for k, v in self.res.items()},
        }
        append_jsonl(os.path.join(DIR, "metrics-%s.jsonl" % day), row)
        if day != getattr(self, "metrics_day", None):
            self.metrics_day = day
            self.prune_metrics(now)

    def prune_metrics(self, now):
        boot_t = lp.boottime() or 0
        cutoff = min(now - 14 * 86400, boot_t - 0)
        for f in os.listdir(DIR):
            if f.startswith("metrics-") and f.endswith(".jsonl"):
                try:
                    t = calendar.timegm(time.strptime(f[8:16], "%Y%m%d"))
                except ValueError:
                    continue
                if t + 86400 < cutoff:
                    try:
                        os.unlink(os.path.join(DIR, f))
                    except OSError:
                        pass

    def write_audit(self, now):
        a = self.audit
        days = a.setdefault("days", {})
        first = a.setdefault("first_ts", now)
        keep = sorted(days)[-14:]
        a["days"] = {d: days[d] for d in keep}
        last7 = sorted(a["days"])[-7:]
        awake = sum(a["days"][d].get("awake", 0) for d in last7)
        l1 = sum(a["days"][d].get("l1", 0) for d in last7)
        share = (float(l1) / awake) if awake else None
        man = read_json(
            os.path.join(self.last_capture_dir or "/nonexistent", "manifest.json")
        )
        if man and man.get("band_pri") is not None:
            a["capture_band_pri"] = man["band_pri"]
        band = self.band[1] if self.band else None
        a["band_pri"] = band
        pass_band = (
            band is not None and band >= 31 and (a.get("capture_band_pri") or 0) >= 31
        )
        ndays = (now - first) / 86400.0
        a.update(
            {
                "v": 1,
                "ts": _iso(now),
                "boot": self.boot,
                "rules_version": rules.RULES_VERSION,
                "days_of_data": round(ndays, 2),
                "awake_ticks_7d": awake,
                "l1_ticks_7d": l1,
                "v1_share_7d": round(share, 5) if share is not None else None,
                "pass_band": pass_band,
                "pass_gate": bool(
                    ndays >= 7
                    and share is not None
                    and share <= 0.02
                    and pass_band
                    and not self.m["noisy"]
                ),
                "pass_killguard": bool(
                    ndays >= 7 and pass_band and self.selftest == "ok"
                ),
                "replay": "tests/lockprobe.bats replay controls run at the land gate",
                "rules": {
                    r: {
                        "fires_24h": len(self.m["fires"].get(r, [])),
                        "noisy": bool(self.m["noisy"].get(r)),
                        "budget_24h": rules.FIRE_BUDGET_24H.get(r),
                        "shadow": r in rules.SHADOW_RULES,
                    }
                    for r in rules.ALL_RULES
                },
                "fires": self.m["fires"],
                "noisy_state": self.m["noisy"],
            }
        )
        atomic_json(os.path.join(DIR, "shadow-audit.json"), a)

    # -- main loop ------------------------------------------------------------------------
    def tick(self, now):
        self.seq += 1
        self.phase("tick")
        if os.environ.get("CC_LOCKWATCH_STANDALONE") != "1" and os.getppid() == 1:
            self.verdict = "host_dead"
            atomic_json(
                os.path.join(DIR, "state.json"), self.state_doc(now), fullsync=True
            )
            return False
        if not self.spawner_alive():
            self.phase("spawner-start")
            if not self.start_spawner():
                self.verdict = "spawner_dead"
        self.phase("poll")
        self.poll_probes(now)
        if self.selftest == "blind":
            self.verdict = "blind"
            atomic_json(
                os.path.join(DIR, "state.json"), self.state_doc(now), fullsync=True
            )
            return 3
        self.phase("schedule")
        self.schedule(now)
        self.phase("rules")
        obs = self.observe(now)
        self.observe_cache = obs
        rec = os.environ.get("CC_LOCKWATCH_RECORD_OBS")
        if rec:
            append_jsonl(rec, obs)  # replay-fixture recorder (lockprobe.py replay reads these)
        self.res = rules.evaluate(obs)
        prev = self.m["level"]
        canary_stuck = (
            obs["pty"].get("state") == "outstanding"
            and obs["pty"].get("age_s", 0) >= 15
            or (obs["walk"].get("verdict") in ("WEDGED", "WEDGED_PREVIOUS"))
        )
        ack = None
        try:
            ack = os.stat(os.path.join(DIR, "ack")).st_mtime
        except OSError:
            pass
        self.m, want, self.reasons, self.shadow = rules.step(
            self.m,
            self.res,
            now,
            ack_ts=ack,
            unpoison_failed=self.unpoison_failed(),
            canary_stuck=canary_stuck,
        )
        if self.m["level"] >= 2 and (self.res.get("P3") or {}).get("last"):
            j = rules.poison_join(
                self.res["P3"]["last"],
                getattr(self, "procs", []),
                self.ttymap,
                (getattr(self, "diag", None) or {}).get("samples"),
            )
            if j:
                if self.join and self.join.get("holder") and not j.get("holder"):
                    j["holder"] = self.join["holder"]
                self.join = j
        if self.m["level"] == 0:
            self.join = None
        self.verdict = rules.verdict_for(self.res, self.m["level"], self.join)
        if self.m["level"] != prev:
            append_jsonl(
                os.path.join(DIR, "levels.jsonl"),
                {
                    "ts": _iso(now),
                    "boot": self.boot,
                    "from": prev,
                    "to": self.m["level"],
                    "verdict": self.verdict,
                    "reasons": self.reasons,
                    "episode": self.m.get("episode"),
                    "starv": self.starv,
                },
                fullsync=True,
            )
        self.phase("act")
        self.act(now, prev)
        self.shadow_actions(now)
        day = time.strftime("%Y-%m-%d", time.gmtime(now))
        dd = self.audit.setdefault("days", {}).setdefault(day, {"awake": 0, "l1": 0})
        dd["awake"] += 1
        if self.m["level"] >= 1:
            dd["l1"] += 1
        self.phase("write")
        sig = (self.m["level"], self.verdict, tuple(self.reasons))
        if now - self.last_state_write >= 5 or sig != self.last_state_sig:
            atomic_json(
                os.path.join(DIR, "state.json"),
                self.state_doc(now),
                fullsync=sig != self.last_state_sig and self.m["level"] != prev,
            )
            self.last_state_write, self.last_state_sig = now, sig
        if (
            self.probes["procscan"]["res"] is not None
            and self.probes["procscan"]["res"].get("_t") == now
        ):
            self.metrics_row(now)
        if now - self.last_ttymap_write >= 60:
            atomic_json(os.path.join(self.run, "ttymap.json"), self.ttymap)
            self.last_ttymap_write = now
        if now - self.last_audit >= 60:
            self.write_audit(now)
            self.last_audit = now
        return True

    def measure(self, now, slept_from):
        cma = lp.mach_cont_s() - lp.mach_abs_s()
        slept = cma - self.last_cont_minus_abs > 1.0
        self.last_cont_minus_abs = cma
        if slept:
            self.m["rules"] = {}  # I8: a streak never spans a sleep
            self.oversleep = []
        elif slept_from is not None:
            self.oversleep.append(max(0.0, slept_from))
            self.oversleep = self.oversleep[-30:]
        self.starv = rules.starvation(self.oversleep, TICK, startups_s=self.startlat)
        c = lp.cpu_ticks()
        if c and self.cpu_prev and self.seq % 5 == 0:
            d = [b - a for a, b in zip(self.cpu_prev, c)]
            tot = float(sum(d)) or 1.0
            self.cpu = {
                "usr": round(100 * (d[0] + d[3]) / tot, 1),
                "sys": round(100 * d[1] / tot, 1),
                "idle": round(100 * d[2] / tot, 1),
            }
            self.cpu_prev = c
        if self.seq % 30 == 1:
            self.band = lp.band_read()

    def loop(self):
        lp.set_qos_user_interactive()
        self.band = lp.band_read()
        self.start_spawner()
        if os.environ.get("CC_LOCKWATCH_NO_SELFTEST") == "1":
            self.selftest = "skipped"
            self.write_pidfile()
        else:
            self.write_pidfile()
            self.launch("selftest", _now())
        self.starv = rules.starvation([], TICK)
        nxt = lp.mach_abs_s()
        over = None
        n = 0
        while True:
            now = _now()
            self.measure(now, over)
            r = self.tick(now)
            if r is not True:
                return 3 if r == 3 else 0
            n += 1
            if self.max_ticks is not None and n >= self.max_ticks:
                return 0
            self.tick_end = lp.mach_abs_s()
            self.phase("sleep")
            nxt += TICK
            delay = nxt - lp.mach_abs_s()
            if delay < 0:
                nxt = lp.mach_abs_s()
                delay = 0
            time.sleep(delay)
            over = lp.mach_abs_s() - nxt


def cmd_run(argv):
    if os.environ.get("CC_LOCKWATCH", "on") == "off":
        return 0
    max_ticks = None
    if "--max-ticks" in argv:
        max_ticks = int(argv[argv.index("--max-ticks") + 1])
    os.makedirs(DIR, exist_ok=True)
    lease = os.open(os.path.join(DIR, ".lease"), os.O_RDWR | os.O_CREAT, 0o600)
    try:
        fcntl.flock(lease, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError as e:
        if e.errno in (errno.EWOULDBLOCK, errno.EAGAIN):
            sys.stderr.write("lockprobe: lease held by another instance; exiting 0\n")
            return 0
        raise
    core = Core(max_ticks=max_ticks)
    rc = core.loop()
    if core.sp_w is not None:
        try:
            os.close(core.sp_w)
        except OSError:
            pass
    return rc


def cmd_status(_argv):
    st = read_json(os.path.join(DIR, "state.json"))
    try:
        hb_age = round(_now() - os.stat(os.path.join(DIR, "hb")).st_mtime, 1)
    except OSError:
        hb_age = None
    if st is None:
        print("lockprobe: no state.json in %s (hb_age=%s)" % (DIR, hb_age))
        return 1
    print(
        "lockprobe: level=L%s verdict=%s hb_age=%ss seq=%s pid=%s zsh_ms=%s walk_ms=%s band_pri=%s kitty_rc=%s "
        "selftest=%s"
        % (
            st.get("level"),
            st.get("verdict"),
            hb_age,
            st.get("seq"),
            st.get("pid"),
            (st.get("canary") or {}).get("zsh_ms"),
            (st.get("canary") or {}).get("walk_ms"),
            st.get("band_pri"),
            st.get("kitty_rc"),
            st.get("selftest"),
        )
    )
    return 0


def cmd_replay(argv):
    """Feed recorded observations (one JSON object per line, rules.evaluate's `obs` shape) through
    the level machine; print one summary line. The replay controls in tests/lockprobe.bats use it."""
    if not argv:
        sys.stderr.write("usage: lockprobe.py replay FILE\n")
        return 2
    m = rules.new_machine()
    ticks = l1 = l2 = 0
    first_l2 = None
    with open(argv[0]) as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            obs = json.loads(line)
            res = rules.evaluate(obs)
            m, _w, reasons, _s = rules.step(m, res, float(obs["now"]))
            ticks += 1
            if m["level"] >= 1:
                l1 += 1
            if m["level"] >= 2:
                l2 += 1
                first_l2 = first_l2 or (obs["now"], reasons)
    print(
        json.dumps(
            {
                "ticks": ticks,
                "l1_ticks": l1,
                "l2_ticks": l2,
                "l1_share": round(float(l1) / ticks, 5) if ticks else None,
                "first_l2": first_l2,
                "noisy": sorted(m["noisy"]),
            }
        )
    )
    return 0


def main(argv):
    if not argv:
        sys.stderr.write(
            "usage: lockprobe.py run [--max-ticks N] | status | replay FILE\n"
        )
        return 2
    cmd = argv[0]
    if cmd == "run":
        return cmd_run(argv[1:])
    if cmd == "status":
        return cmd_status(argv[1:])
    if cmd == "replay":
        return cmd_replay(argv[1:])
    sys.stderr.write("lockprobe: unknown command %s\n" % cmd)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
