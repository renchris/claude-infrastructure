"""Tier G (B1 load harness §9.11): the REAL decision code on a VIRTUAL clock, no real child started.

``run_pass`` (and the ``_dispatch`` / ``_admission_period`` it calls) runs unmodified. A ``Sim`` stands
in for every child the pass waits on and charges it its virtual cost, the 31-band p90 at 40/core:
census 3 s, ``--place`` 15 s, the admission probe 4 s, a kitty composer read 0.1 s per record. An
actuator is a fake process in the Sim's own table that, ``T_att`` after its spawn, exits NOTMOVED
(``HELD:unreachable``, TRANSIENT; its verdict appended to the actlog ``act.spawn`` opened, its code
in ``act.EXIT_CODES``, as ``test_rollback`` replays), which frees its boot slot and drives retries.

What it proves (REPORT.md §5, Invariant G): the decision code never reads load; our own timeout is
never a verdict; first and retry attempts are bounded. ``P_sim`` is the longest pass the Sim can
charge for ``n`` records (sleep + census + place + n × (probe + kitty)); every observed pass is
checked against it, so the bounds below are stated in a term the Sim cannot quietly exceed.

F3 TRIPWIRE: ``subprocess.Popen``/``run`` (and ``Popen._execute_child``, which a ``popen=subprocess
.Popen`` default captured at def time still reaches), every lr_recon module's ``run_bounded``,
``_run_snap`` and ``_provenance`` record the call and raise, so a real child fails the case even
where production swallows the exception (``observe.composer_state`` does). ``store.proc_lstart``
answers from the Sim's process table. F2: no lr_recon function may hold ``os.getloadavg`` as a
default except the allow set the Sim injects past (``Clock.__init__``, ``observe.ps_bound``).

MUTANT → RED (each applied in ``MutantsDie``, which asserts its checker raises AssertionError):
  * S1  ``Admission.pace_ok`` also requires load1/ncpu < 20      → traces differ at load ≥ 250
  * S1  ``Admission.pace_ok`` also requires load1/ncpu < 2.0     → traces differ at load ≥ 150
  * S2  ``BootSlots.START = 1``                                   → the first-spawn bound breaks
  * S2  ``ctx.boots.on_wave([60 s])`` every pass (AIMD wired)    → ``boots.limit`` leaves 6
  * S2b ``admit.DRIP_EVERY_S × 100``                              → the drip bound breaks
  * S3  ``classify.BACKOFF_CAP_S = 900``                          → a backoff of 480 s > 300
  * S4  ``plan.keep_waits`` ends every mover IMPOSSIBLE on rc 124 → a record closes on our timeout
  * S5a the restart forgets live actuators (procs dropped on load, no argv adoption) → a 2nd spawn
  * S5b ``_restamp`` stamps the claim to the new daemon (the pre-W2 shape) → the claim leaves the
        live actuator. S5b is hard: W2 (A6) landed before W1, so W1 flipped its expectedFailure.
  * F2  a planted function with ``os.getloadavg`` as a default    → the defaults scan fails
  * F3  the composer read reaches the real ``composer_state``     → the tripwire records a child
"""

import collections
import contextlib
import importlib
import math
import os
import pkgutil
import shutil
import subprocess
import tempfile
import time
import types
import unittest
from typing import Any, Callable, Dict, Iterator, List, Optional, Tuple
from unittest import mock

import lr_recon
from lr_recon import __main__ as M
from lr_recon import act, admit, classify, observe, plan, report, store
from lr_recon import clock as C
from lr_recon import types as T
from lr_recon.admit import Admission, BootSlots
from lr_recon.tests import test_rollback as TR

T0 = 1792314000.0
L = "Tue Sep 29 11:19:17 2026"
NCPU = 10
LOADS = (5.0, 150.0, 250.0, 400.0, 1000.0)  # 0.5 to 100 per core (F1)
CENSUS_S, PLACE_S, PROBE_S, KITTY_S = 3.0, 15.0, 4.0, 0.1
SLEEP_S = M.ACTIVE_FAST_S  # the daemon's wait between passes while a record is moving
# The guarantee's own terms (REPORT.md:431-441), literals: a checker that read them from the code
# under test would move with a mutant instead of catching it.
D = 6  # BootSlots width
B_MAX = 300.0
BACKOFFS = (10.0, 30.0, 60.0, 120.0, 240.0, 300.0, 300.0)
DRIP_AFTER, DRIP_EVERY_S = 3, 30.0
SRC, TARGETS = "next3", ("next", "next2", "next4")
NOTMOVED_RC = 6
RESETS = T0 + 9 * 3600  # a weekly reset well past the stay window: every member moves
ALLOW_LOAD_DEFAULTS = {"lr_recon.clock.Clock.__init__", "lr_recon.observe.ps_bound"}
REAL_COMPOSER = observe.composer_state


class Tripwire(AssertionError):
    """A real child was about to start."""


def p_sim(n: int) -> float:
    return SLEEP_S + CENSUS_S + PLACE_S + n * (PROBE_S + KITTY_S)


class Proc:
    def __init__(
        self, sid: str, pid: int, args: str, log: str, born: float, dies: float
    ):
        self.sid, self.pid, self.args, self.log = sid, pid, args, log
        self.lstart = "SIM act %d" % pid
        self.born, self.dies = born, dies


class Sim:
    """The virtual world one case runs in: clock, load, sessions, fake actuators, fake children."""

    def __init__(
        self,
        tmp: str,
        n: int,
        t_att: float,
        load1: float = 250.0,
        reveal: Optional[Callable[[int], int]] = None,
        busy: int = 0,
        busy_from: int = 0,
        place_rc: Callable[[int], int] = lambda pass_no: 0,
        probe_rc: Callable[[int], int] = lambda pass_no: 0,
    ) -> None:
        self.tmp, self.n, self.t_att, self.load1 = tmp, n, t_att, load1
        self.reveal = reveal or (lambda i: 0)
        self.busy, self.busy_from = busy, busy_from
        self.place_rc, self.probe_rc = place_rc, probe_rc
        self.home = os.path.join(tmp, "home")
        os.makedirs(os.path.join(self.home, ".claude"))
        self.cfg = {
            a: os.path.join(self.home, ".claude-" + a) for a in (SRC,) + TARGETS
        }
        with open(os.path.join(self.home, ".claude", "accounts.json"), "w") as fh:
            fh.write(
                store.dumps(
                    {
                        "accounts": [
                            {"name": a, "config_dir": c} for a, c in self.cfg.items()
                        ]
                    }
                )
            )
        self.env = {"HOME": self.home, "LR_STATE_DIR": os.path.join(tmp, "lr")}
        self.paths = T.Paths.from_env(
            env=self.env, root=os.path.join(tmp, "lr", "recon")
        )
        store.ensure_dirs(self.paths)
        for f in (
            self.paths.recon_on,
            self.paths.autorecover_on,
            self.paths.recon_autorecover_on,
        ):
            open(f, "w").close()
        with open(self.paths.mode_file, "w") as fh:
            fh.write("act\n")
        self.t = self.pass_now = T0
        self.pass_no = 0
        self.daemon_lstart = "SIM daemon 1"
        self.next_pid = 40000
        self.procs: Dict[int, Proc] = {}
        self.spawns: List[
            Tuple[float, str, str, int, int]
        ] = []  # t, sid, actuator, attempt, pid
        self.exits: List[Tuple[float, str, int]] = []
        self.trace: List[Tuple[Any, ...]] = []
        self.violations: List[str] = []
        self.doubles: List[str] = []
        self.boot_limits: List[int] = []
        self.pass_lens: List[float] = []
        self.pages: List[str] = []
        self._spawning: Tuple[str, str, int] = ("", "", 0)

    # ── identities ────────────────────────────────────────────────────────────────────────────────
    def sid(self, i: int) -> str:
        # unique in the first 8: record ids and actlog names key on sid[:8]
        return "5a%06d-0000-0000-0000-%012d" % (i, i)

    def wall(self) -> float:
        return self.t

    def loadavg(self) -> Tuple[float, float, float]:
        return (self.load1, self.load1, self.load1)

    def sysctl(self, name: str) -> str:
        at = {"kern.waketime": T0 - 86400, "kern.boottime": T0 - 2 * 86400}.get(name)
        return "{ sec = %d, usec = 0 } x" % at if at else ""

    def proc_lstart(self, pid: int, run: Any = None) -> str:
        if pid == os.getpid():
            return self.daemon_lstart
        if pid in self.procs:
            return self.procs[pid].lstart
        return L if 1000 <= pid < 1000 + self.n + self.busy else ""

    def live(self, sid: str) -> List[Proc]:
        return [p for p in self.procs.values() if p.sid == sid]

    # ── the children the pass waits on ────────────────────────────────────────────────────────────
    def observe(self, paths: T.Paths, home: str, **_kw: Any) -> T.Snapshot:
        for pid, p in sorted(self.procs.items()):
            if (
                p.dies <= self.t
            ):  # the actuator exited NOTMOVED at p.dies; this pass reaps it
                with open(p.log, "a") as fh:
                    fh.write(TR.ROLLED_BACK)
                act.EXIT_CODES[pid] = NOTMOVED_RC
                self.exits.append((p.dies, p.sid, pid))
                del self.procs[pid]
        self.t += CENSUS_S
        sessions, panes, procs = {}, {}, {}
        cwd = os.path.join(self.tmp, "cwd")
        os.makedirs(cwd, exist_ok=True)
        rows = [(i, True) for i in range(self.n) if self.reveal(i) <= self.pass_no]
        if self.pass_no >= self.busy_from:
            rows += [(self.n + j, False) for j in range(self.busy)]
        for i, limited in rows:
            sid, pid, pane = self.sid(i), 1000 + i, (5, 100 + i)
            tx = os.path.join(cwd, "t%d.jsonl" % i)
            open(tx, "a").close()
            last = {
                "limit": True,
                "kind": "limit",
                "cap": "seven_day",
                "resets_at": RESETS,
            }
            sessions[sid] = T.SessionObs(
                sid=sid,
                acct=SRC,
                cfg=self.cfg[SRC],
                pid=pid,
                lstart=L,
                cwd=cwd,
                pane=pane,
                registry_name="p%d" % i,
                holders=[
                    T.HolderObs(
                        pid=pid, lstart=L, cfg=self.cfg[SRC], src="registry", pane=pane
                    )
                ],
                transcript=T.TranscriptObs(
                    path=tx, at_rest=limited, last=last if limited else {}
                ),
            )
            panes["5:%d" % pane[1]] = T.PaneObs(
                kitty_pid=5,
                window_id=pane[1],
                sock="unix:/tmp/kitty-5",
                root_pid=2000 + i,
                root_lstart=L,
                root_shape="shell",
                state="claude",
            )
            procs[pid] = T.ProcRow(pid, 1, "S+", L, "/x/claude.exe")
        for p in self.procs.values():
            procs[p.pid] = T.ProcRow(p.pid, 1, "S", p.lstart, p.args)
        return T.Snapshot(
            wall=self.t, uptime_raw=0.0, procs=procs, panes=panes, sessions=sessions
        )

    def place(
        self, lane: str, mvs: Any, facts_dir: str, kw: Any, timeout: float = 30.0
    ) -> Any:
        rc = self.place_rc(self.pass_no)
        if rc == 124:
            self.t += timeout  # our own bound fired: the Sim charges exactly that bound
            return {
                m.sid: T.Placement(acct=None, reason="wait-data", weight=m.w)
                for m in mvs
            }, 124
        self.t += PLACE_S
        return {
            m.sid: T.Placement(acct=TARGETS[int(m.sid[-4:]) % len(TARGETS)], weight=m.w)
            for m in mvs
        }, 0

    def runner(self, argv: List[str]) -> Tuple[int, str]:
        self.t += PROBE_S
        return self.probe_rc(self.pass_no), ""

    def composer(self, sock: str, window_id: int, *_a: Any, **_kw: Any) -> str:
        self.t += KITTY_S
        return "empty"

    def popen(self, argv: List[str], stdout: Any = None, **_kw: Any) -> Any:
        sid, actuator, attempt = self._spawning
        if self.live(sid):
            self.doubles.append(
                "%s spawned %s while pid %d lives"
                % (sid[-4:], actuator, self.live(sid)[0].pid)
            )
        pid, self.next_pid = self.next_pid, self.next_pid + 1
        self.procs[pid] = Proc(
            sid, pid, " ".join(argv), stdout.name, self.t, self.t + self.t_att
        )
        self.spawns.append((self.t, sid, actuator, attempt, pid))
        self.trace.append((round(self.t - T0, 3), "spawn", sid, actuator, attempt))
        return types.SimpleNamespace(pid=pid)

    def spawn(
        self,
        paths: T.Paths,
        rec: T.Record,
        actuator: str,
        argv: List[str],
        env: Dict[str, str],
        now: float,
    ) -> int:
        self._spawning = (rec.sid, actuator, rec.attempt)
        return REAL_SPAWN(
            paths,
            rec,
            actuator,
            argv,
            env,
            now,
            popen=self.popen,
            lstart_of=self.proc_lstart,
        )

    def tripwire(self, name: str) -> Callable[..., Any]:
        def trip(*a: Any, **_kw: Any) -> Any:
            self.violations.append("%s %s" % (name, repr(a[:2])[:120]))
            raise Tripwire("a real child from %s" % name)

        return trip

    # ── wiring ────────────────────────────────────────────────────────────────────────────────────
    @contextlib.contextmanager
    def patched(self) -> Iterator["Sim"]:
        with contextlib.ExitStack() as es:
            pat = es.enter_context
            pat(
                mock.patch.dict(
                    os.environ,
                    {"LR_STATE_DIR": os.path.join(self.tmp, "lr"), "HOME": self.home},
                )
            )
            pat(mock.patch.object(time, "time", self.wall))
            pat(mock.patch("os.getloadavg", self.loadavg))
            pat(mock.patch("os.cpu_count", lambda: NCPU))
            pat(
                mock.patch.object(
                    subprocess, "Popen", self.tripwire("subprocess.Popen")
                )
            )
            pat(mock.patch.object(subprocess, "run", self.tripwire("subprocess.run")))
            pat(
                mock.patch.object(
                    REAL_POPEN, "_execute_child", self.tripwire("Popen._execute_child")
                )
            )
            for mod in lr_modules():
                if hasattr(mod, "run_bounded"):
                    pat(
                        mock.patch.object(
                            mod,
                            "run_bounded",
                            self.tripwire(mod.__name__ + ".run_bounded"),
                        )
                    )
            pat(mock.patch.object(M, "_run_snap", self.tripwire("_run_snap")))
            pat(mock.patch.object(M, "_provenance", self.tripwire("_provenance")))
            pat(mock.patch.object(store, "proc_lstart", self.proc_lstart))
            pat(mock.patch.object(observe, "observe", self.observe))
            pat(mock.patch.object(observe, "composer_state", self.composer))
            pat(mock.patch.object(plan, "place", self.place))
            pat(mock.patch.object(plan, "assign_many", lambda rows, run=None: 0))
            pat(mock.patch.object(plan, "unassign", lambda assign_id, run=None: 0))
            pat(mock.patch.object(act, "spawn", self.spawn))
            pat(
                mock.patch.object(
                    Admission, "mint_token", lambda adm, sid, owes_prompt=True: None
                )
            )
            pat(mock.patch.dict(act.EXIT_CODES, clear=True))
            pat(mock.patch.object(act, "_SELF_LSTART", (0, "")))
            orig_admit = M._admit

            def admit_spy(
                ctx: M.Ctx, rec: T.Record, which: str, snap: T.Snapshot, now: float
            ) -> Tuple[bool, str]:
                ok, why = orig_admit(ctx, rec, which, snap, now)
                self.trace.append(
                    (round(self.t - T0, 3), "admit", rec.sid, which, ok, why)
                )
                return ok, why

            pat(mock.patch.object(M, "_admit", admit_spy))
            yield self

    def make_ctx(self) -> M.Ctx:
        ctx = M.Ctx(self.paths, None, self.home)
        ctx.clock = C.Clock(
            wall=self.wall,
            uptime=lambda: 0.0,
            sysctl=self.sysctl,
            getloadavg=self.loadavg,
            cpu_count=lambda: NCPU,
            env={},
        )
        ctx.admission = Admission(runner=self.runner, env={}, wall=self.wall)
        ctx.reporter = report.Reporter(
            self.paths, "act", page=self.pages.append, mail=lambda p, t: None
        )
        return ctx

    def restart(self) -> M.Ctx:
        """A new daemon process: new lstart, a Ctx rebuilt from disk, `_startup` as daemon() runs it."""
        self.daemon_lstart = "SIM daemon 2"
        act._SELF_LSTART = (0, "")
        ctx = self.make_ctx()
        M._startup(ctx)
        return ctx

    def run(
        self,
        ctx: M.Ctx,
        passes: int = 0,
        each: Optional[Callable[[M.Ctx], None]] = None,
        span: float = 0.0,
    ) -> None:
        """`passes` passes, or as many as fill `span` virtual seconds (a waiting pass is short)."""
        end = self.t + span
        for _ in range(passes or 5000):
            if span and self.t >= end:
                break
            # run_pass reads its `now` before the first charge
            start = self.pass_now = self.t
            M.run_pass(ctx)
            if self.violations:
                raise Tripwire("real children: %s" % self.violations[:3])
            self.boot_limits.append(ctx.boots.limit)
            if each is not None:
                each(ctx)
            self.t += SLEEP_S
            self.pass_lens.append(self.t - start)
            self.pass_no += 1

    def first_spawn(self) -> Dict[str, float]:
        out: Dict[str, float] = {}
        for t, sid, _a, _n, _p in self.spawns:
            out.setdefault(sid, t)
        return out


REAL_SPAWN = act.spawn
REAL_POPEN = subprocess.Popen


def lr_modules() -> List[types.ModuleType]:
    out = []
    for info in pkgutil.iter_modules(lr_recon.__path__):
        if info.name != "tests":
            out.append(importlib.import_module("lr_recon." + info.name))
    return out


def load_defaults() -> List[str]:
    """Every lr_recon function or method whose defaults hold os.getloadavg (F2)."""
    seen, hits = set(), []

    def fns(obj: Any) -> Iterator[Any]:
        if isinstance(obj, (staticmethod, classmethod)):
            obj = obj.__func__
        if isinstance(obj, property):
            obj = obj.fget
        if isinstance(obj, types.FunctionType):
            yield obj
        elif isinstance(obj, type) and obj.__module__.startswith("lr_recon"):
            for v in vars(obj).values():
                yield from fns(v)

    for mod in lr_modules():
        for v in list(vars(mod).values()):
            for fn in fns(v):
                if id(fn) in seen:
                    continue
                seen.add(id(fn))
                vals = list(fn.__defaults__ or ()) + list(
                    (fn.__kwdefaults__ or {}).values()
                )
                if any(d is os.getloadavg for d in vals):
                    hits.append("%s.%s" % (fn.__module__, fn.__qualname__))
    return hits


class SimCase(unittest.TestCase):
    """The checkers. Each builds its own Sim under a fresh temp root and raises AssertionError."""

    def setUp(self) -> None:
        self.tmp = tempfile.mkdtemp(prefix="lr-gsim.")
        self.addCleanup(shutil.rmtree, self.tmp, True)
        env = mock.patch.dict(
            os.environ, {"LR_STATE_DIR": os.path.join(self.tmp, "lr"), "HOME": self.tmp}
        )
        env.start()
        self.addCleanup(env.stop)
        self.k = 0

    def sim(self, **kw: Any) -> Sim:
        self.k += 1
        return Sim(os.path.join(self.tmp, "s%d" % self.k), **kw)

    def assert_passes_fit(self, s: Sim) -> None:
        self.assertLessEqual(
            max(s.pass_lens), p_sim(s.n) + 1e-6, "the Sim charged a pass past P_sim"
        )

    # S1: full run_pass — the pass is where load could enter (plan, admission, dispatch)
    def check_s1(self) -> None:
        traces = {}
        for load1 in LOADS:
            s = self.sim(n=8, t_att=60.0, load1=load1)
            with s.patched():
                s.run(s.make_ctx(), 24)
            traces[load1] = s.trace
        base = traces[LOADS[0]]
        self.assertGreaterEqual(
            sum(1 for e in base if e[1] == "spawn"), 8, "no trace to compare"
        )
        self.assertTrue(
            any(e[1] == "admit" and not e[4] for e in base), "no refusal in the trace"
        )
        for load1 in LOADS[1:]:
            self.assertEqual(
                traces[load1], base, "the decision trace moved with load1=%s" % load1
            )

    # S1 with telemetry (W6): the writer is write-only, so the trace is identical with it on and
    # off at the top of the load range, and the "on" arm really wrote rows
    def check_s1_telemetry(self) -> None:
        from lr_recon import telemetry

        traces = []
        for on in (False, True):
            s = self.sim(n=8, t_att=60.0, load1=LOADS[-1])
            with s.patched():
                ctx = s.make_ctx()
                if on:
                    ctx.telem = telemetry.Telemetry(
                        s.paths,
                        env={},
                        wall=s.wall,
                        read_pri=lambda pid=None: 31,
                        census=lambda: None,
                        thermal=lambda: 1,
                        pressure=lambda: 1,
                        kitty_glob=os.path.join(self.tmp, "no-kitty-*"),
                    )
                    ctx.telem.start(None, [])
                s.run(ctx, 24)
            traces.append(s.trace)
        self.assertTrue(
            os.path.exists(s.paths.p(telemetry.FILE)), "telemetry wrote nothing"
        )
        self.assertGreaterEqual(sum(1 for e in traces[0] if e[1] == "spawn"), 8)
        self.assertEqual(
            traces[1], traces[0], "the decision trace moved with telemetry on"
        )

    # S2: full run_pass — the first attempt's latency is a property of the whole pass
    def check_s2(self) -> None:
        s = self.sim(n=8, t_att=600.0, reveal=lambda i: i)
        with s.patched():
            ctx = s.make_ctx()
            s.run(ctx, span=3 * s.t_att)
        self.assert_passes_fit(s)
        # never attempted inside the run = an unbounded wait
        first = collections.defaultdict(lambda: math.inf, s.first_spawn())
        recs = ctx.records
        self.assertEqual(len(recs), s.n)
        bad, k_rs = [], []
        for sid, r in recs.items():
            t_det = r.timeline.detected
            # k_r (REPORT.md:441, C17): records detected EARLIER than r, none held here, still owed
            # a lane at t_detect(r): not yet attempted, or their attempt's actuator still live.
            # Not every earlier member: one whose attempt had ended holds no lane.
            k_r = sum(
                1
                for q, rq in recs.items()
                if rq.timeline.detected < t_det
                and (
                    first[q] > t_det
                    or any(
                        p[0] <= t_det < p[0] + s.t_att for p in s.spawns if p[1] == q
                    )
                )
            )
            k_rs.append(k_r)
            bound = 2 * p_sim(s.n) + math.ceil(k_r / D) * s.t_att
            if first[sid] - t_det > bound:
                bad.append(
                    "%s k_r=%d waited %.0f > %.0f"
                    % (sid[-4:], k_r, first[sid] - t_det, bound)
                )
        self.assertGreaterEqual(max(k_rs), D, "the cohort never filled the boot slots")
        limits = sorted(set(s.boot_limits))
        msg = []
        if bad:
            msg.append("first-spawn bound: " + "; ".join(bad))
        if limits != [D]:
            msg.append("boots.limit %s, not %d on every pass" % (limits, D))
        if msg:
            raise AssertionError(" | ".join(msg))

    # S2b: full run_pass — the restore budget binds inside _admit; the drip is its bound
    def check_s2b(self) -> None:
        s = self.sim(
            n=6, t_att=900.0, reveal=lambda i: 0 if i == 0 else 2, busy=12, busy_from=1
        )
        with s.patched():
            ctx = s.make_ctx()
            s.run(ctx, span=600.0)
        self.assertTrue(
            any(e[1] == "admit" and e[5] == "restore-r" for e in s.trace),
            "R never bound",
        )
        first = collections.defaultdict(lambda: math.inf, s.first_spawn())
        # queue position: _dispatch's own order, detection then record insertion (a stable sort)
        queue = sorted(
            (r for r in ctx.records.values() if r.sid != s.sid(0)),
            key=lambda r: r.timeline.detected,
        )
        self.assertEqual(len(queue), s.n - 1)
        for q, r in enumerate(queue):
            bound = (DRIP_AFTER + 2) * p_sim(s.n) + q * (DRIP_EVERY_S + p_sim(s.n))
            self.assertLessEqual(
                first[r.sid] - r.timeline.detected,
                bound,
                "drip bound, queue position %d" % q,
            )
        self.assertTrue(
            any(e[1] == "admit" and e[5] == "admit:drip" for e in s.trace),
            "no member came in through the drip",
        )

    # S3: full run_pass — a failed attempt is settled, backed off, re-placed and re-admitted there
    def check_s3(self) -> None:
        s = self.sim(n=1, t_att=30.0)
        backoffs: List[float] = []

        def note(ctx: M.Ctx) -> None:
            # the backoff as set: next_eligible_at minus the settling pass's own `now`
            r = ctx.records[s.sid(0)]
            if r.attempts_by_class.get("TRANSIENT", 0) > len(backoffs):
                backoffs.append(round(r.next_eligible_at - s.pass_now, 3))

        with s.patched():
            s.run(s.make_ctx(), each=note, span=2500.0)
        self.assert_passes_fit(s)
        self.assertGreaterEqual(
            len(backoffs), 7, "fewer than 7 consecutive TRANSIENT failures"
        )
        self.assertLessEqual(
            max(backoffs), B_MAX, "a backoff past the 300 s cap: %s" % backoffs
        )
        self.assertEqual(tuple(backoffs[:7]), BACKOFFS)
        spawns = [t for t, *_ in s.spawns]
        for n, (t_exit, _sid, _pid) in enumerate(s.exits[:7]):
            nxt = min(t for t in spawns if t > t_exit)
            self.assertLessEqual(
                nxt - t_exit, BACKOFFS[n] + 2 * p_sim(s.n), "retry %d late" % (n + 1)
            )

    # S4: full run_pass — placement and admission both sit inside the pass
    def check_s4(self) -> None:
        answer = 6  # place rc 124 on passes 0-5, past KEEP_MAX_MISSES; the probe times out on pass 6
        s = self.sim(
            n=3,
            t_att=60.0,
            place_rc=lambda p: 124 if p < answer else 0,
            probe_rc=lambda p: admit.RC_TIMEOUT if p == answer else 0,
        )
        subs: List[str] = []
        with s.patched():
            ctx = s.make_ctx()
            s.run(
                ctx,
                answer + 3,
                lambda c: subs.extend(r.substate or "" for r in c.records.values()),
            )
        self.assertEqual(len(ctx.records), s.n)
        for r in ctx.records.values():
            self.assertTrue(
                r.open, "%s closed on our own timeout: %s" % (r.sid[-4:], r.terminal)
            )
            self.assertFalse(r.escalated)
        self.assertFalse({"HELD:load", "HOLD-LOAD"} & set(subs))
        self.assertTrue(
            any(e[1] == "admit" and e[5] == "probe-timeout" for e in s.trace),
            "no probe timeout",
        )
        first = s.first_spawn()
        self.assertEqual(
            sorted(first),
            sorted(ctx.records),
            "a record not spawned once place answered",
        )

    # S5a: full run_pass across a rebuilt Ctx — restart is a property of the daemon, not of a stage
    def run_restart(self) -> Tuple[Sim, Dict[str, float], M.Ctx]:
        s = self.sim(n=4, t_att=900.0)
        with s.patched():
            ctx = s.make_ctx()
            s.run(ctx, 4)
            detected = {sid: r.timeline.detected for sid, r in ctx.records.items()}
            ctx = s.restart()
            s.run(ctx, 6)
        return s, detected, ctx

    def check_s5a(self) -> None:
        s, detected, ctx = self.run_restart()
        self.assertEqual(len(detected), s.n)
        self.assertEqual(
            {sid: r.timeline.detected for sid, r in ctx.records.items()}, detected
        )
        self.assertEqual(
            s.doubles, [], "a second spawn for an attempt whose actuator lives"
        )
        self.assertEqual(len(s.spawns), s.n)

    def check_s5b(self) -> None:
        # C16 / REPORT A6 (ii): on restart an in-flight claim is re-stamped to the adopted live
        # actuator, never to the new daemon. W2 (1eb5548ac, A6) made it hold.
        s, _detected, ctx = self.run_restart()
        for sid in ctx.records:
            [p] = s.live(sid)
            claim = store.read_claim(s.paths, sid)
            self.assertIsNotNone(claim)
            self.assertEqual(
                (claim.pid, claim.lstart),
                (p.pid, p.lstart),
                "claim re-stamped away from the live actuator",
            )

    def check_f2(self) -> None:
        self.assertEqual(sorted(set(load_defaults()) - ALLOW_LOAD_DEFAULTS), [])

    def check_f3(self) -> None:
        s = self.sim(n=2, t_att=60.0)
        with s.patched():
            s.run(s.make_ctx(), 3)
        self.assertEqual(s.violations, [])
        self.assertEqual(len(s.spawns), 2)


class GuaranteeSim(SimCase):
    def test_f2_no_load_default_outside_the_allow_set(self) -> None:
        self.check_f2()

    def test_f3_no_real_child(self) -> None:
        self.check_f3()

    def test_s1_load_invariance(self) -> None:
        self.check_s1()

    def test_s1_identical_with_telemetry_on(self) -> None:
        self.check_s1_telemetry()

    def test_s2_first_spawn_bound(self) -> None:
        self.check_s2()

    def test_s2b_restore_budget_drip_bound(self) -> None:
        self.check_s2b()

    def test_s3_retry_bound(self) -> None:
        self.check_s3()

    def test_s4_our_timeout_is_not_a_verdict(self) -> None:
        self.check_s4()

    def test_s5a_restart_neutrality(self) -> None:
        self.check_s5a()

    # Hard since W2 (A6 restart safety) landed first: Phase 0 shared-file rule 4 flips the
    # expectedFailure in the commit that makes it pass. A comment, not a docstring: unittest -v
    # would split the line the bats case greps.
    def test_s5b_claim_stays_with_the_live_actuator(self) -> None:
        self.check_s5b()


class MutantsDie(SimCase):
    def dies(self, check: Callable[[], None], *patches: Any, why: str = "") -> None:
        with contextlib.ExitStack() as es:
            for p in patches:
                es.enter_context(p)
            with self.assertRaises(AssertionError) as cm:
                check()
        self.assertIn(why, str(cm.exception))

    def test_s1_telemetry_that_decides(self) -> None:
        """W6: a writer that touches a decision field (here: every record backed off) moves the trace."""
        from lr_recon import telemetry

        orig = telemetry.Telemetry.note_states

        def deciding(tel, records, active_of):
            records = list(records)
            for r in records:
                r.next_eligible_at = 4e9
            return orig(tel, records, active_of)

        self.dies(
            self.check_s1_telemetry,
            mock.patch.object(telemetry.Telemetry, "note_states", deciding),
            why="telemetry on",
        )

    def test_s1_pace_requires_load_below_20_per_core(self) -> None:
        orig = Admission.pace_ok
        gated = lambda adm, wall: (
            orig(adm, wall) and os.getloadavg()[0] / (os.cpu_count() or 1) < 20
        )
        self.dies(
            self.check_s1,
            mock.patch.object(Admission, "pace_ok", gated),
            why="load1=250",
        )

    def test_s1_pace_requires_load_below_2_per_core(self) -> None:
        orig = Admission.pace_ok
        gated = lambda adm, wall: (
            orig(adm, wall) and os.getloadavg()[0] / (os.cpu_count() or 1) < 2.0
        )
        self.dies(
            self.check_s1,
            mock.patch.object(Admission, "pace_ok", gated),
            why="load1=150",
        )

    def test_s2_one_boot_slot(self) -> None:
        self.dies(
            self.check_s2,
            mock.patch.object(BootSlots, "START", 1),
            why="first-spawn bound",
        )

    def test_s2_aimd_wired_to_slow_boots(self) -> None:
        orig = M._admission_period

        def wired(ctx: M.Ctx, snap: T.Snapshot, now: float) -> None:
            ctx.boots.on_wave([60.0])
            orig(ctx, snap, now)

        self.dies(
            self.check_s2,
            mock.patch.object(M, "_admission_period", wired),
            why="boots.limit",
        )

    def test_s2b_drip_100x_slower(self) -> None:
        self.dies(
            self.check_s2b,
            mock.patch.object(admit, "DRIP_EVERY_S", admit.DRIP_EVERY_S * 100),
            why="drip bound",
        )

    def test_s3_backoff_cap_900(self) -> None:
        self.dies(
            self.check_s3,
            mock.patch.object(classify, "BACKOFF_CAP_S", 900),
            why="300 s cap",
        )

    def test_s4_place_timeout_is_a_verdict(self) -> None:
        orig = plan.keep_waits
        box: Dict[str, Any] = {}

        def verdict(got: Any, pre: Any, rc: int, misses: int) -> Any:
            if rc == 124:
                for sid in got:
                    box["recs"][sid].terminal = T.Terminal(
                        outcome="IMPOSSIBLE", proof="place rc 124", at=time.time()
                    )
            return orig(got, pre, rc, misses)

        orig_plan = M._plan

        def plan_spy(ctx: M.Ctx, *a: Any) -> int:
            box["recs"] = ctx.records
            return orig_plan(ctx, *a)

        self.dies(
            self.check_s4,
            mock.patch.object(plan, "keep_waits", verdict),
            mock.patch.object(M, "_plan", plan_spy),
            why="closed on our own timeout",
        )

    def test_s5b_restamp_to_the_new_daemon(self) -> None:
        # the pre-W2 shape: _startup re-stamped every in-flight claim to os.getpid()
        def to_daemon(paths: T.Paths, rec: T.Record, pid: int, lstart: str) -> None:
            store.claim_restamp(paths, rec.sid, rec.record_id, os.getpid(), "daemon")

        self.dies(
            self.check_s5b,
            mock.patch.object(M, "_restamp", to_daemon),
            why="claim re-stamped away from the live actuator",
        )

    def test_s5a_restart_forgets_the_live_actuator(self) -> None:
        orig = store.load_all

        def forget(paths: T.Paths, on_bad: Any) -> Dict[str, T.Record]:
            recs = orig(paths, on_bad)
            for r in recs.values():
                r.procs, r.intent = [], None
            return recs

        self.dies(
            self.check_s5a,
            mock.patch.object(store, "load_all", forget),
            mock.patch.object(act, "adopt", lambda rec, snap: []),
            why="second spawn",
        )

    def test_f2_planted_load_default(self) -> None:
        def gate(
            load_fn: Callable[[], Tuple[float, float, float]] = os.getloadavg,
        ) -> bool:
            return load_fn()[0] < 20

        self.dies(
            self.check_f2,
            mock.patch.object(admit, "planted_gate", gate, create=True),
            why="<locals>.gate",
        )

    def test_f3_composer_read_reaches_kitty(self) -> None:
        self.dies(
            self.check_f3,
            mock.patch.object(Sim, "composer", staticmethod(REAL_COMPOSER)),
            why="real children",
        )


if __name__ == "__main__":
    unittest.main()
