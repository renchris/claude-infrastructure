"""W9 (B2 stage 1): a bounded pass, synchronous.

docs/plans/LR_SUSTAINED_LOAD_IMPL.md § W9, design docs/research/lr-sustained-load-2026-10-20/impl/
B2-bounded-pass.md §S1 and its two reviews. Every child the loop waits on is wall-bounded including
its kill-wait; reaping never steals another owner's exit; the per-record serial terms (lstart reads,
composer reads, pages, mails, draft snapshots, our own boot slot) are bounded or capped per pass, so
a pass costs at most P_cap, a sum of enforced bounds that does not grow with the record count.

Each rule has its red control or mutant beside it ("Green in both arms"). Hermetic: HOME,
LR_STATE_DIR, LR_RECON_ROOT and TMPDIR under /tmp; every child is a fake or a /bin/sleep of ours."""

import collections
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from typing import Any, Dict, List, Optional, Tuple
from unittest import mock

from lr_recon import __main__ as M
from lr_recon import act, observe, plan, report, store
from lr_recon import clock as C
from lr_recon import types as T

L = "Tue Oct 20 21:00:00 2026"
PKG = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # lr_recon/
LRD = os.path.dirname(PKG)  # scripts/limit-recover
WATCHDOG = os.path.join(LRD, "lr-recon-watchdog.sh")
GRACE = 0.3  # LR_RECON_REAP_GRACE_S in these tests
STUCK_S = 1.5  # how long a "kernel-stuck" fake child takes to die after its kill


def CP(argv: Any, rc: int = 0, out: str = "", err: str = "") -> Any:
    return subprocess.CompletedProcess(argv, rc, out, err)


class Hermetic(unittest.TestCase):
    """A sandbox root, and W9's module-level switches and registries restored after each test."""

    def setUp(self) -> None:
        self.tmp = tempfile.mkdtemp(prefix="lr-w9.", dir="/tmp")
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.home = os.path.join(self.tmp, "home")
        os.makedirs(self.home)
        env = mock.patch.dict(
            os.environ,
            {
                "HOME": self.home,
                "LR_STATE_DIR": os.path.join(self.tmp, "lr"),
                "LR_RECON_ROOT": os.path.join(self.tmp, "lr", "recon"),
                "TMPDIR": "/tmp",
                "LR_RECON_REAP_GRACE_S": str(GRACE),
            },
        )
        env.start()
        self.addCleanup(env.stop)
        self.paths = T.Paths.from_env(root=os.path.join(self.tmp, "lr", "recon"))
        store.ensure_dirs(self.paths)
        for obj, name in ((C, "BOUNDED_PASS"), (store, "INPROC_LSTART")):
            self.addCleanup(setattr, obj, name, getattr(obj, name))
        for p in (
            mock.patch.object(C, "_ORPHANS", []),
            mock.patch.object(C, "_DETACHED", []),
            mock.patch.object(C, "_INFLIGHT", set()),
            mock.patch.dict(act._CHILDREN, clear=True),
        ):
            p.start()
            self.addCleanup(p.stop)
        self.addCleanup(act.begin_pass, False)

    def events(self, ev: Optional[str] = None) -> List[Dict[str, Any]]:
        try:
            with open(self.paths.events, encoding="utf-8") as fh:
                rows = [json.loads(x) for x in fh if x.strip()]
        except OSError:
            return []
        return [r for r in rows if ev is None or r.get("ev") == ev]

    def touch(self, name: str) -> None:
        open(self.paths.p(name), "w").close()


# ── S1.a: a true wall bound for every inline child ────────────────────────────────────────────────


class StuckPopen:
    """A child stuck in the kernel past its kill (B2 §1.2): wait() blocks STUCK_S after kill()
    unless it has become reapable, and returns at once once returncode is set, like a real Popen."""

    def __init__(self, args: Any, **kw: Any) -> None:
        self.args, self.pid, self.returncode = args, 0, None
        self.stdin = self.stdout = self.stderr = None
        self.reapable = False

    def __enter__(self) -> "StuckPopen":
        return self

    def __exit__(self, *exc: Any) -> None:
        self.wait()

    def communicate(self, input: Any = None, timeout: Optional[float] = None) -> Any:
        time.sleep(timeout or 0)
        raise subprocess.TimeoutExpired(self.args, timeout or 0)

    def kill(self) -> None:
        pass

    def poll(self) -> Optional[int]:
        if self.reapable:
            self.returncode = -9
        return self.returncode

    def wait(self, timeout: Optional[float] = None) -> int:
        if self.poll() is not None:
            return int(self.returncode or 0)
        if timeout is None or timeout >= STUCK_S:
            time.sleep(STUCK_S)
            self.returncode = -9
            return -9
        time.sleep(timeout)
        raise subprocess.TimeoutExpired(self.args, timeout)


class BoundedReap(Hermetic):
    def stuck_run(self) -> Tuple[float, List[StuckPopen]]:
        made: List[StuckPopen] = []

        def popen(*a: Any, **k: Any) -> StuckPopen:
            made.append(StuckPopen(*a, **k))
            return made[-1]

        t0 = time.monotonic()
        with mock.patch.object(C.subprocess, "Popen", side_effect=popen):
            with self.assertRaises(subprocess.TimeoutExpired):
                C.run_bounded(
                    ["/bin/ps", "-axo", "pid="], capture_output=True, timeout=0.2
                )
        return time.monotonic() - t0, made

    def test_T1_stuck_child_costs_bound_plus_grace(self) -> None:
        took, made = self.stuck_run()
        self.assertLess(took, 0.2 + GRACE + 0.3)
        self.assertEqual(C._ORPHANS, made, "abandoned to the orphan registry")
        self.assertEqual(C._INFLIGHT, set())

    def test_T1_control_pre_W9_waits_for_the_corpse(self) -> None:
        # recon/bounded-pass.off is subprocess.run: its kill-wait has no bound (6.29 s measured)
        C.BOUNDED_PASS = False
        took, _made = self.stuck_run()
        self.assertGreaterEqual(took, STUCK_S)
        self.assertEqual(C._ORPHANS, [])

    def test_T2_real_child_killed_and_reaped(self) -> None:
        t0 = time.monotonic()
        with self.assertRaises(subprocess.TimeoutExpired):
            C.run_bounded(["/bin/sleep", "5"], timeout=0.3)
        self.assertLess(time.monotonic() - t0, 1.0)
        self.assertEqual(C._ORPHANS, [])
        self.assertEqual(C._INFLIGHT, set())

    def test_T2_kwargs_like_run(self) -> None:
        cp = C.run_bounded(
            ["/bin/cat"], input="hi", capture_output=True, text=True, timeout=10
        )
        self.assertEqual((cp.returncode, cp.stdout), (0, "hi"))
        with self.assertRaises(subprocess.CalledProcessError):
            C.run_bounded(["/bin/sh", "-c", "exit 3"], check=True, timeout=10)
        self.assertGreater(
            C._SPAWN_MAX[0], 0.0, "the Popen constructor is timed (spawn_s)"
        )

    def test_T3_orphan_is_reaped_later(self) -> None:
        _took, made = self.stuck_run()
        made[0].reapable = True
        act.reap_children()
        self.assertEqual(C._ORPHANS, [])

    def test_T3_mutant_without_reap_orphans_keeps_it(self) -> None:
        _took, made = self.stuck_run()
        made[0].reapable = True
        with mock.patch.object(C, "reap_orphans", return_value=0):
            act.reap_children()
        self.assertEqual(C._ORPHANS, made)

    def test_note_child_never_masks_the_result(self) -> None:
        hb = C.Heartbeat(os.path.join(self.tmp, "hb"), 1, L, C.Clock(env={}))
        C.bind_steps(hb)
        self.addCleanup(C.bind_steps, None)
        C.bind_child_hook(mock.Mock(side_effect=RuntimeError("ledger defect")))
        self.addCleanup(C.bind_child_hook, None)
        with self.assertRaises(subprocess.TimeoutExpired):
            C.run_bounded(["/bin/sleep", "5"], timeout=0.2)


# ── S1.b: registered-only reaping, and a loop that wakes on an exit ──────────────────────────────


class RegisteredReaping(Hermetic):
    def exited_nine(self) -> "subprocess.Popen[bytes]":
        p = subprocess.Popen(["/bin/sh", "-c", "exit 9"])
        time.sleep(0.3)  # exited, not yet waited: a zombie only its owner should reap
        return p

    def test_T4_an_async_owner_keeps_its_exit_status(self) -> None:
        p = self.exited_nine()
        act.reap_children()
        self.assertEqual(p.poll(), 9)

    def test_T4_control_waitpid_minus_one_steals_it(self) -> None:
        C.BOUNDED_PASS = False  # the pre-W9 reaper
        p = self.exited_nine()
        act.reap_children()
        self.assertEqual(
            p.poll(), 0, "ECHILD read as 0: a capacity refusal (9) reads as admit"
        )

    def test_T6_detached_children_are_registered_then_reaped(self) -> None:
        script = os.path.join(self.tmp, "check.sh")
        with open(script, "w") as fh:
            fh.write("exit 0\n")
        with mock.patch.object(M, "provenance_check", return_value=script):
            self.assertTrue(M._provenance(self.paths, time.time()))
        # registry membership with no Popen in between (CPython's _cleanup would reap a dropped one)
        self.assertEqual(len(C._DETACHED), 1)
        with mock.patch.dict(os.environ, {"LR_ACCOUNTS_BIN": "/usr/bin/true"}):
            self.assertTrue(
                plan.start_fresh_sweep(self.paths, time.time(), popen=C.popen_detached)
            )
        self.assertEqual(len(C._DETACHED), 2)
        procs = list(C._DETACHED)
        deadline = time.monotonic() + 10
        while C._DETACHED and time.monotonic() < deadline:
            time.sleep(0.05)
            act.reap_children()
        self.assertEqual(C._DETACHED, [])
        self.assertEqual([p.returncode for p in procs], [0, 0])

    def test_T7_wait_returns_on_an_actuator_exit(self) -> None:
        p = subprocess.Popen(["/bin/sleep", "0.3"])
        act._CHILDREN[p.pid] = (p, "n1")
        t0 = time.monotonic()
        self.assertTrue(
            M.wait_for_change(self.paths, self.home, 5.0, None, wake=act.any_exited)
        )
        self.assertLess(time.monotonic() - t0, 1.5)
        act.reap_children()
        self.assertEqual(act.EXIT_CODES.pop(p.pid, None), 0, "the code is still kept")

    def test_T7_control_no_wake_waits_out_the_timeout(self) -> None:
        p = subprocess.Popen(["/bin/sleep", "0.3"])
        act._CHILDREN[p.pid] = (p, "n1")
        t0 = time.monotonic()
        self.assertFalse(M.wait_for_change(self.paths, self.home, 2.0, None))
        self.assertGreaterEqual(time.monotonic() - t0, 1.9)
        act.reap_children()
        act.EXIT_CODES.pop(p.pid, None)

    def test_the_daemon_waits_with_the_exit_wake(self) -> None:
        with open(os.path.join(PKG, "__main__.py"), encoding="utf-8") as fh:
            src = fh.read()
        waits = re.findall(
            r"wait_for_change\(paths, ctx\.home, [A-Z_]+, hb(, act\.any_exited)?\)", src
        )
        self.assertEqual(waits, [", act.any_exited"] * 3)

    def test_unowned_zombie_is_an_event_after_two_passes(self) -> None:
        ctx = M.Ctx(self.paths, None, self.home)
        me = os.getpid()
        C._INFLIGHT.add(778)
        snap = T.Snapshot(
            wall=0.0,
            uptime_raw=0.0,
            procs={
                777: T.ProcRow(777, me, "Z", L, "/x/unregistered"),
                778: T.ProcRow(778, me, "Z", L, "/x/in-flight"),
                779: T.ProcRow(779, 1, "Z", L, "/x/not-ours"),
            },
        )
        M._unowned_zombies(ctx, snap)
        self.assertEqual(self.events("unowned-zombie"), [])
        M._unowned_zombies(ctx, snap)
        M._unowned_zombies(ctx, snap)
        rows = self.events("unowned-zombie")
        self.assertEqual(len(rows), 1)
        self.assertIn("pid 777", rows[0]["detail"])


# ── heartbeat keys against the watchdog's sed ────────────────────────────────────────────────────

# lr-recon-watchdog.sh hb_num: sed -n 's/.*"KEY":[[:space:]]*\(-\{0,1\}[0-9][0-9.]*\).*/\1/p'
SED = r'.*"%s":\s*(-?[0-9][0-9.]*).*'


def _sed(line: str, key: str) -> Optional[str]:
    m = re.match(SED % re.escape(key), line)
    return m.group(1) if m else None


def watchdog_keys() -> List[str]:
    with open(WATCHDOG, encoding="utf-8") as fh:
        return re.findall(r"hb_num ([a-z_]+)\)", fh.read())


class HeartbeatKeys(Hermetic):
    def rendered(self) -> str:
        hb = C.Heartbeat(os.path.join(self.tmp, "hb"), 4242, L, C.Clock(env={}))
        hb.declare_child(30.0)
        hb.note_pass(7, 3)
        with mock.patch.object(C, "_SPAWN_MAX", [0.0123, 1792549190.5]):
            return hb.render().strip()

    def test_T9_new_keys_leave_every_watchdog_key_intact(self) -> None:
        keys = watchdog_keys()
        self.assertGreaterEqual(
            set(keys), {"pid", "progress", "wall", "progress_wall", "step_due"}
        )
        line = self.rendered()
        obj = json.loads(line)
        for k in ("pages_queued", "orphans", "spawn_s_max", "spawn_s_max_at"):
            self.assertIn(k, obj)
        self.assertEqual((obj["pages_queued"], obj["orphans"]), (7, 3))
        for k in keys:
            self.assertEqual(float(_sed(line, k) or "nan"), float(obj[k]), k)
        m = re.match(r'.*"lstart":\s*"([^"]*)".*', line)
        self.assertEqual(m.group(1) if m else None, L)

    def test_T9_mutant_a_colliding_key_corrupts_the_read(self) -> None:
        # a nested "pid" (or any key equal to a watchdog key) is what the greedy sed would read
        obj = json.loads(self.rendered())
        bad = json.dumps(dict(obj, extra={"pid": 1}), separators=(",", ":"))
        self.assertNotEqual(_sed(bad, "pid"), str(obj["pid"]))


# ── per-record serial terms: lstart, claims, composer, assign, drafts, mints ─────────────────────


class UnknownIsAlive(Hermetic):
    def setUp(self) -> None:
        super().setUp()
        self.holder = subprocess.Popen(["/bin/sleep", "60"])
        self.addCleanup(self.holder.wait)
        self.addCleanup(self.holder.kill)
        self.lstart = store.inproc_lstart(self.holder.pid) or ""
        self.assertTrue(self.lstart)

    def ps_times_out(self) -> Any:
        store.INPROC_LSTART = False
        return mock.patch.object(
            C, "_run_reaped", side_effect=subprocess.TimeoutExpired("ps", 40)
        )

    def test_alive_on_a_ps_timeout(self) -> None:
        with self.ps_times_out():
            self.assertTrue(M._alive(self.holder.pid, self.lstart))

    def test_control_pre_W9_alive_reads_the_timeout_as_dead(self) -> None:
        with self.ps_times_out():
            self.assertFalse(
                bool(self.lstart) and store.proc_lstart(self.holder.pid) == self.lstart
            )

    def test_dead_and_reused_still_read_dead(self) -> None:
        self.assertFalse(M._alive(self.holder.pid, "Thu Jan 1 00:00:00 2026"))
        p = subprocess.Popen(["/usr/bin/true"])
        p.wait()
        self.assertFalse(M._alive(p.pid, self.lstart))

    def claim(self, sid: str, lstart: str) -> None:
        d = store.claim_dir(self.paths, sid)
        os.makedirs(d)
        holder = {"pid": self.holder.pid, "owner": "cc-lr", "record_id": "foreign"}
        if lstart:
            holder["lstart"] = lstart
        store.atomic_write_json(os.path.join(d, "holder"), holder)

    def rec(self, sid: str) -> T.Record:
        return T.Record(
            sid=sid, record_id="r-" + sid, cohort_id="c", source_acct="next3"
        )

    def test_a_foreign_claim_is_held_when_its_lstart_read_times_out(self) -> None:
        self.claim("s1", self.lstart)
        with self.ps_times_out():
            self.assertEqual(
                act.hold_claim(self.paths, self.rec("s1"), M._alive), (False, "held")
            )

    def test_an_argv_read_that_times_out_is_unknown(self) -> None:
        with mock.patch.object(
            C, "_run_reaped", side_effect=subprocess.TimeoutExpired("ps", 5)
        ):
            self.assertEqual(act._argv_of(self.holder.pid), store.UNKNOWN)
        self.claim("s3", "")
        with mock.patch.object(
            C, "_run_reaped", side_effect=subprocess.TimeoutExpired("ps", 5)
        ):
            self.assertEqual(
                act.hold_claim(self.paths, self.rec("s3"), M._alive), (False, "held")
            )

    def test_argv_cap_holds_past_six_reads(self) -> None:
        act.begin_pass(True)
        with mock.patch.object(
            C, "_run_reaped", return_value=CP(["ps"], 0, "/bin/sleep 60")
        ) as ps:
            got = [
                act._argv_of(self.holder.pid)
                for _ in range(act.ARGV_READS_PER_PASS + 1)
            ]
        self.assertEqual(ps.call_count, act.ARGV_READS_PER_PASS)
        self.assertEqual(got[-1], store.UNKNOWN)
        self.claim("s2", "")  # a legacy, lstart-less holder: only its argv can judge it
        self.assertEqual(
            act.hold_claim(self.paths, self.rec("s2"), M._alive), (False, "held")
        )
        act.begin_pass(False)
        with mock.patch.object(
            C, "_run_reaped", return_value=CP(["ps"], 0, "/bin/sleep 60")
        ) as ps:
            act._argv_of(self.holder.pid)
        self.assertEqual(ps.call_count, 1, "recon/pass-caps.off: uncapped")


class FakeMono:
    def __init__(self) -> None:
        self.t = 1000.0

    def __call__(self) -> float:
        return self.t


class ComposerGateTest(Hermetic):
    """B2 review F-D 4a: per-socket breaker, a 20 s budget, oldest-read-first rotation."""

    def setUp(self) -> None:
        super().setUp()
        self.mono = FakeMono()
        self.children: List[Tuple[str, int]] = []
        self.dur: Dict[Tuple[str, int], float] = collections.defaultdict(lambda: 4.9)

        def child(argv: List[str], **kw: Any) -> Any:
            sock, wid = argv[3], int(argv[6].split(":")[1])
            self.children.append((sock, wid))
            d = self.dur[(sock, wid)]
            self.mono.t += min(d, kw["timeout"])
            if d >= kw["timeout"]:
                self.mono.t += C.REAP_GRACE_S
                raise subprocess.TimeoutExpired(argv, kw["timeout"])
            return CP(argv, 0, "")

        p = mock.patch.object(M, "run_bounded", side_effect=child)
        p.start()
        self.addCleanup(p.stop)

    def gate(
        self, seq: int, last: Dict[str, int], prev: List[str], capped: bool = True
    ) -> M.ComposerGate:
        return M.ComposerGate(seq, last, prev, capped, mono=self.mono)

    def test_a_timed_out_socket_spawns_no_second_child(self) -> None:
        self.dur[("A", 1)] = 9.0
        g = self.gate(1, {}, [])
        self.assertEqual(g.read("s1", "A", 1), "unknown")
        self.assertEqual(g.read("s2", "A", 2), "unknown")
        g.read("s3", "B", 3)
        self.assertEqual(self.children, [("A", 1), ("B", 3)])
        self.assertEqual(g.skipped, 1)

    def test_breaker_mutant_reads_the_dead_socket_again(self) -> None:
        self.dur[("A", 1)] = self.dur[("A", 2)] = 9.0
        g = self.gate(1, {}, [], capped=False)  # pass-caps.off: no breaker
        g.read("s1", "A", 1)
        g.read("s2", "A", 2)
        self.assertEqual(self.children, [("A", 1), ("A", 2)])

    def one_pass(
        self, seq: int, sids: List[str], last: Dict[str, int], prev: List[str]
    ) -> M.ComposerGate:
        g = self.gate(seq, last, prev)
        t0 = self.mono.t
        for i, sid in enumerate(sids):
            g.read(sid, "B", i)
        g.spent_wall = self.mono.t - t0  # type: ignore[attr-defined]
        return g

    def test_budget_30_reads_at_4_9_s(self) -> None:
        sids = ["s%02d" % i for i in range(30)]
        g = self.one_pass(1, sids, {}, [])
        self.assertLessEqual(
            g.spent_wall, M.COMPOSER_BUDGET_S + M.COMPOSER_READ_S
        )  # ≤ 27 s
        self.assertEqual((g.reads, g.skipped), (5, 25))

    def rotate(self, passes: int) -> List[List[str]]:
        sids = ["s%02d" % i for i in range(30)]
        last: Dict[str, int] = {}
        prev: List[str] = []
        read: List[List[str]] = []
        for seq in range(1, passes + 1):
            before = dict(last)
            g = self.one_pass(seq, sids, last, prev)
            self.assertLessEqual(g.spent_wall, M.COMPOSER_BUDGET_S + M.COMPOSER_READ_S)
            prev = g.wanted
            read.append(
                [s for s in sids if last.get(s) == seq and before.get(s) != seq]
            )
        return read

    def test_rotation_reads_every_session_oldest_first(self) -> None:
        read = self.rotate(8)
        every = set()
        for r in read[:6]:
            self.assertTrue(r)
            self.assertFalse(
                every & set(r), "a session read again before every other one"
            )
            every |= set(r)
        self.assertEqual(len(every), 30, read)

    def test_rotation_mutant_starves_the_tail(self) -> None:
        with mock.patch.object(M.ComposerGate, "_reserved", return_value=0.0):
            read = self.rotate(8)
        self.assertLess(
            len(set().union(*read)), 30, "without reservation the head always wins"
        )

    def test_caps_off_reads_every_composer(self) -> None:
        g = self.gate(1, {}, [], capped=False)
        for i in range(30):
            g.read("s%02d" % i, "B", i)
        self.assertEqual(g.reads, 30)


class AssignMemo(Hermetic):
    def test_T20_assign_only_on_change_failure_or_refresh(self) -> None:
        ctx = M.Ctx(self.paths, None, self.home)
        rows = [{"acct": "next2", "id": "a1", "sid": "s1", "w": 1, "ttl_s": 1200}]
        wall = [1792549000.0]
        with (
            mock.patch.object(
                plan, "phantom_rows", side_effect=lambda recs: list(rows)
            ),
            mock.patch.object(plan, "assign_many", return_value=0) as am,
            mock.patch.object(M.time, "time", side_effect=lambda: wall[0]),
        ):
            for _ in range(3):
                M._own_and_charge(ctx, wall[0])
            self.assertEqual(am.call_count, 1, "red at HEAD: 3")
            rows.append(
                {"acct": "next4", "id": "a2", "sid": "s2", "w": 2, "ttl_s": 1200}
            )
            M._own_and_charge(ctx, wall[0])
            self.assertEqual(
                am.call_count, 2, "a new placement is charged in its own pass"
            )
            wall[0] += M.ASSIGN_REFRESH_S
            M._own_and_charge(ctx, wall[0])
            self.assertEqual(
                am.call_count, 3, "refreshed every 120 s against the 1200 s TTL"
            )
            am.return_value = 124
            rows.pop()
            M._own_and_charge(ctx, wall[0])  # a changed set, and the call fails
            am.return_value = 0
            M._own_and_charge(ctx, wall[0])
            self.assertEqual(am.call_count, 5, "a failed call is re-asserted next pass")
            M._own_and_charge(ctx, wall[0])
            self.assertEqual(am.call_count, 5, "and memoised again once it succeeds")
            ctx.pass_caps = False
            M._own_and_charge(ctx, wall[0])
            M._own_and_charge(ctx, wall[0])
            self.assertEqual(
                am.call_count, 7, "recon/pass-caps.off: every pass, as before"
            )


def _limited(sid: str, sub: str = "PLANNED", **kw: Any) -> T.Record:
    r = T.Record(
        sid=sid,
        record_id="r-" + sid,
        cohort_id="c1",
        source_acct="next3",
        kind="limited",
        phase="PRE-MOVE",
        substate=sub,
        pane=(5, 100),
    )
    for k, v in kw.items():
        setattr(r, k, v)
    return r


class PassCaps(Hermetic):
    def test_T17_one_draft_snapshot_a_pass_the_rest_next_pass(self) -> None:
        ctx = M.Ctx(self.paths, None, self.home)
        ctx.records = {s: _limited(s, "HOLD-DRAFT") for s in ("d1", "d2")}
        snap = T.Snapshot(wall=0.0, uptime_raw=0.0)
        with mock.patch.object(M, "_run_snap", return_value=(0, "snapfile\n")) as rs:
            self.assertEqual(M._draft_snapshots(ctx, snap), 1)
            self.assertEqual(
                rs.call_count, 2, "one snapshot is two children (snap + row)"
            )
            self.assertNotIn(
                "draft_snap_attempt", ctx.records["d2"].close, "untouched, retried"
            )
            self.assertEqual(M._draft_snapshots(ctx, snap), 1)
            self.assertEqual(M._draft_snapshots(ctx, snap), 0)
        self.assertEqual(rs.call_count, 4)

    def test_T17_caps_off_takes_both(self) -> None:
        ctx = M.Ctx(self.paths, None, self.home)
        ctx.pass_caps = False
        ctx.records = {s: _limited(s, "HOLD-DRAFT") for s in ("d1", "d2")}
        with mock.patch.object(M, "_run_snap", return_value=(0, "snapfile\n")):
            self.assertEqual(
                M._draft_snapshots(ctx, T.Snapshot(wall=0.0, uptime_raw=0.0)), 2
            )

    def test_mints_are_capped_per_pass(self) -> None:
        ctx = M.Ctx(self.paths, None, self.home)
        r = _limited("m1", target_acct="next2")
        ctx.pass_mints = M.MINTS_PER_PASS
        snap = T.Snapshot(wall=0.0, uptime_raw=0.0)
        with mock.patch.object(ctx.admission, "decide") as decide:
            self.assertEqual(M._admit(ctx, r, "A", snap, 0.0), (False, "pass-cap"))
        decide.assert_not_called()
        self.assertNotIn(
            "m1", ctx.boots.held, "the boot slot taken for it is given back"
        )
        ctx.pass_mints = M.MINTS_PER_PASS - 1
        with (
            mock.patch.object(ctx.admission, "decide", return_value=(True, "admit")),
            mock.patch.object(ctx.admission, "mint_token", return_value="/tmp/tok"),
        ):
            self.assertEqual(M._admit(ctx, r, "A", snap, 0.0), (True, "admit"))
        self.assertEqual(ctx.pass_mints, M.MINTS_PER_PASS)

    def test_ps_tries_once_while_ps_orphans_are_stuck(self) -> None:
        calls: List[List[str]] = []

        def hung(argv: List[str], **kw: Any) -> Any:
            calls.append(argv)
            raise subprocess.TimeoutExpired(argv, kw["timeout"])

        with self.assertRaises(RuntimeError):
            observe.read_ps(run=hung, bound=10.0)
        self.assertEqual(
            len(calls), 2, "the first ps call errs out of read_ps after its retry"
        )
        calls.clear()
        stuck = [StuckPopen(["/bin/ps", "-axo"]) for _ in range(C.ORPHAN_RETRY_SKIP_AT)]
        C._ORPHANS.extend(stuck)
        with self.assertRaises(RuntimeError):
            observe.read_ps(run=hung, bound=10.0)
        self.assertEqual(len(calls), 1, "one try while the kernel path is still stuck")

    def test_orphan_backlog_pages_once(self) -> None:
        ctx = M.Ctx(self.paths, None, self.home)
        pages: List[str] = []
        ctx.reporter = report.Reporter(self.paths, "act", page=pages.append)
        C._ORPHANS.extend(StuckPopen(["/bin/ps"]) for _ in range(C.ORPHAN_PAGE_AT - 1))
        M._orphan_page(ctx)
        self.assertEqual(pages, [])
        C._ORPHANS.append(StuckPopen(["/bin/ps"]))
        M._orphan_page(ctx)
        M._orphan_page(ctx)
        self.assertEqual(len(pages), 1)
        self.assertEqual(len(self.events("orphan-backlog")), 1)


# ── pages and mails: the outbox, one synchronous send a pass ─────────────────────────────────────


class Outbox(Hermetic):
    REQ = "aaaaaaaa-1111-2222-3333-%012d"

    def setUp(self) -> None:
        super().setUp()
        self.sent: List[str] = []
        self.now = [1792549000.0]

    def reporter(self, **kw: Any) -> report.Reporter:
        kw.setdefault("page", lambda t: self.sent.append("page " + t))
        kw.setdefault("mail", lambda a, t: self.sent.append("mail " + a))
        return report.Reporter(self.paths, "act", now=lambda: self.now[0], **kw)

    def files(self) -> List[str]:
        try:
            return sorted(os.listdir(self.paths.p(report.OUTBOX)))
        except OSError:
            return []

    def mail_records(self) -> List[T.Record]:
        out = []
        for i in range(5):
            r = _limited("%08d-0000-0000-0000-00000000000%d" % (i, i), "")
            r.cohort_id = "cm"
            r.terminal = T.Terminal(outcome="CLOSED", proof="p", at=self.now[0])
            r.requester_sid = self.REQ % i
            r.requester_pane = ""
            out.append(r)
        return out

    def report_pass(self, rep: report.Reporter, recs: List[T.Record]) -> List[str]:
        """_report's order: immediate pages, requester mails, then the rest (one send a pass)."""
        n = len(self.sent)
        rep.begin_pass(outbox=True, sends=report.SENDS_PER_PASS)
        rep.flush_outbox(immediate_only=True)
        rep.requester_mails(recs, {r.requester_sid for r in recs}, set())
        rep.flush_outbox()
        return self.sent[n:]

    def test_one_send_a_pass_with_5_pages_and_5_mails_queued(self) -> None:
        rep = self.reporter()
        rep.begin_pass(outbox=True, sends=0)
        for i in range(3):
            self.now[0] += 1
            rep._once("c1", "k%d" % i, "OPEN", "open %d" % i)
        for i in range(2):
            self.now[0] += 1
            rep._once("c1", "imm%d" % i, "ESCALATED", "esc %d" % i)
        self.assertEqual(self.sent, [])
        self.assertEqual(len(self.files()), 5)
        recs = self.mail_records()
        per_pass = [self.report_pass(rep, recs) for _ in range(11)]
        self.assertTrue(all(len(p) <= 1 for p in per_pass), per_pass)
        order = [p[0].split(" ", 2)[:2] for p in per_pass if p]
        self.assertEqual(len(order), 10, "every page and mail is sent, none lost")
        self.assertEqual(
            [o[1] for o in order[:2]], ["esc", "esc"], "immediate kinds first"
        )
        self.assertEqual(
            [o[0] for o in order[2:7]], ["mail"] * 5, "then the requester mails"
        )
        self.assertEqual([o[1] for o in order[7:]], ["open"] * 3)
        self.assertEqual(self.files(), [])

    def test_uncapped_sends_everything_in_one_pass(self) -> None:
        rep = self.reporter()
        rep.begin_pass(outbox=True, sends=None)
        for i in range(4):
            rep._once("c1", "k%d" % i, "OPEN", "open %d" % i)
        rep.flush_outbox()
        self.assertEqual(len(self.sent), 4)

    def test_the_outbox_file_exists_while_the_page_is_sent(self) -> None:
        seen: List[int] = []
        rep = self.reporter(page=lambda t: seen.append(len(self.files())))
        rep.begin_pass(outbox=True, sends=1)
        rep._once("c1", "k", "OPEN", "x")
        rep.flush_outbox()
        self.assertEqual((seen, self.files()), ([1], []))

    def test_a_failing_sink_is_retried_then_given_up(self) -> None:
        def boom(_t: str) -> None:
            raise report.PageFailed("down")

        rep = self.reporter(page=boom)
        rep.begin_pass(outbox=True, sends=1)
        rep._once("c1", "k", "OPEN", "x")
        for _ in range(report.OUTBOX_TRIES - 1):
            rep.begin_pass(outbox=True, sends=1)
            rep.flush_outbox()
            self.assertEqual(len(self.files()), 1, "kept for a later pass")
        rep.begin_pass(outbox=True, sends=1)
        rep.flush_outbox()
        self.assertEqual(self.files(), [])
        self.assertEqual(len(self.events("page-gave-up")), 1)
        self.assertEqual(rep.failures, report.OUTBOX_TRIES)

    def test_outbox_off_sends_inline(self) -> None:
        rep = self.reporter()
        rep.begin_pass(outbox=False, sends=1)
        rep._once("c1", "k", "OPEN", "x")
        self.assertEqual((self.sent, self.files()), (["page x"], []))

    def test_observe_mode_flushes_nothing(self) -> None:
        rep = self.reporter()
        rep.begin_pass(outbox=True, sends=None)
        rep._once("c1", "k", "OPEN", "x")
        rep.mode = "observe"
        self.assertEqual(rep.flush_outbox(), 0)
        self.assertEqual(len(self.files()), 1)

    def test_an_abstained_pass_still_sends_one_queued_page(self) -> None:
        ctx = M.Ctx(self.paths, None, self.home)
        rep = ctx.reporter = self.reporter()
        rep.begin_pass(outbox=True, sends=0)
        rep._once("c1", "k1", "ESCALATED", "esc")
        rep._once("c1", "k2", "OPEN", "open")
        snap = T.Snapshot(wall=0.0, uptime_raw=0.0, degraded=["ps"])
        M._abstain(ctx, snap, "act", self.now[0], "ps degraded")
        self.assertEqual(self.sent, ["page esc"])
        M._abstain(ctx, snap, "act", self.now[0], "ps degraded")
        self.assertEqual(self.sent, ["page esc", "page open"])

    def test_report_orders_immediate_then_mails_then_the_rest(self) -> None:
        ctx = M.Ctx(self.paths, None, self.home)
        rep = ctx.reporter = self.reporter()
        calls: List[str] = []
        snap = T.Snapshot(wall=0.0, uptime_raw=0.0)
        with (
            mock.patch.object(
                rep,
                "flush_outbox",
                side_effect=lambda immediate_only=False, **k: calls.append(
                    "imm" if immediate_only else "rest"
                ),
            ),
            mock.patch.object(
                rep, "requester_mails", side_effect=lambda *a: calls.append("mails")
            ),
        ):
            M._report(ctx, "act", self.now[0], snap)
        self.assertEqual(calls, ["imm", "mails", "rest"])
        self.assertEqual((rep.outbox, rep.sends_left), (True, report.SENDS_PER_PASS))
        self.touch(M.PASS_CAPS_OFF)
        self.touch(M.PAGE_OUTBOX_OFF)
        M._w9_switches(ctx)
        M._report(ctx, "act", self.now[0], None)
        self.assertEqual((rep.outbox, rep.sends_left), (False, None))


DAEMON_CHILD = r"""
import os, sys, time
sys.path.insert(0, sys.argv[1])
from lr_recon import __main__ as M, report, store, types as T
root, mode = sys.argv[2], sys.argv[3]
paths = T.Paths.from_env(root=root)
log = os.path.join(os.path.dirname(root), "sent.log")
def sink(text):
    if mode == "fail":
        raise report.PageFailed("down")
    with open(log, "a") as fh:
        fh.write(text + "\n")
ctx = M.Ctx(paths, None, os.environ["HOME"])
def fake_pass(ctx, force_observe=False):
    rep = ctx.reporter = report.Reporter(ctx.paths, "act", page=sink)
    if mode == "replay":
        rep.begin_pass(outbox=True, sends=None)
        rep.flush_outbox()
        raise SystemExit(0)
    rep.begin_pass(outbox=True, sends=0)
    for i in range(3):
        rep._once("c1", "k%d" % i, "OPEN", "page %d" % i)
    for r in ctx.records.values():
        r.substate = "MUTATED-MID-PASS"
    open(os.path.join(os.path.dirname(root), "ready"), "w").close()
    time.sleep(60)
M.run_pass = fake_pass
sys.exit(M.daemon(ctx))
"""


class SigtermOutbox(Hermetic):
    """Review C5: no SIGTERM handler meant kickstart -k and the watchdog's TERM skipped daemon()'s
    finally, so latched pages were lost. Now the finally flushes the outbox and saves no record."""

    def run_daemon(self, mode: str) -> int:
        env = dict(
            os.environ,
            LR_RECON_TELEMETRY="off",
            LR_RECON_BAND_CHECK="off",
            LR_RECON_PROVENANCE="off",
            PYTHONDONTWRITEBYTECODE="1",
        )
        ready = os.path.join(self.tmp, "lr", "ready")
        p = subprocess.Popen(
            ["/usr/bin/python3", "-c", DAEMON_CHILD, LRD, self.paths.root, mode],
            env=env,
        )
        try:
            if mode != "replay":
                deadline = time.monotonic() + 120
                while not os.path.exists(ready) and time.monotonic() < deadline:
                    if p.poll() is not None:
                        break
                    time.sleep(0.05)
                self.assertTrue(os.path.exists(ready), "the child reached mid-pass")
                p.send_signal(signal.SIGTERM)
            return p.wait(timeout=120)
        finally:
            if p.poll() is None:
                p.kill()
                p.wait()

    def record(self) -> str:
        r = _limited("aaaaaaaa-0000-0000-0000-000000000001", "WAIT_SLOT")
        store.save_record(self.paths, r, 1792549000.0)
        with open(store.record_path(self.paths, r.sid), "rb") as fh:
            return fh.read().decode()

    def sent(self) -> List[str]:
        try:
            with open(os.path.join(self.tmp, "lr", "sent.log")) as fh:
                return fh.read().split("\n")[:-1]
        except OSError:
            return []

    def test_sigterm_mid_pass_flushes_the_outbox_and_saves_no_record(self) -> None:
        before = self.record()
        rc = self.run_daemon("ok")
        self.assertEqual(rc, 128 + signal.SIGTERM)
        self.assertEqual(self.sent(), ["page 0", "page 1", "page 2"])
        self.assertEqual(os.listdir(self.paths.p(report.OUTBOX)), [])
        with open(
            store.record_path(self.paths, "aaaaaaaa-0000-0000-0000-000000000001")
        ) as fh:
            self.assertEqual(fh.read(), before, "the finally writes no record")

    def test_pages_a_dead_sink_left_are_sent_by_the_next_daemon(self) -> None:
        self.record()
        self.assertEqual(self.run_daemon("fail"), 128 + signal.SIGTERM)
        self.assertEqual(
            len(os.listdir(self.paths.p(report.OUTBOX))), 3, "survives the kill"
        )
        self.assertEqual(self.run_daemon("replay"), 0)
        self.assertEqual(self.sent(), ["page 0", "page 1", "page 2"])
        self.assertEqual(len(self.events("outbox-replay")), 1)


class PassExceptionGuard(Hermetic):
    def test_three_raising_passes_exit_1_and_page_once(self) -> None:
        ctx = M.Ctx(self.paths, None, self.home)
        pages: List[str] = []
        ctx.reporter = report.Reporter(self.paths, "act", page=pages.append)
        self.assertFalse(M._pass_exception(ctx, ValueError("one")))
        self.assertFalse(M._pass_exception(ctx, ValueError("two")))
        self.assertTrue(M._pass_exception(ctx, ValueError("three")))
        self.assertEqual(len(self.events("pass-exception")), 3)
        self.assertEqual(len(pages), 1, "latched hourly")

    def test_daemon_survives_two_then_exits_on_the_third_in_a_row(self) -> None:
        ctx = M.Ctx(self.paths, None, self.home)
        script = iter(
            [
                ValueError("a"),
                ValueError("b"),
                None,
                ValueError("c"),
                ValueError("d"),
                ValueError("e"),
            ]
        )
        passes: List[int] = []

        def fake_pass(ctx: Any, force_observe: bool = False) -> Dict[str, Any]:
            passes.append(1)
            e = next(script)
            if e is not None:
                raise e
            return {"open": 0}

        env = {
            "LR_RECON_TELEMETRY": "off",
            "LR_RECON_BAND_CHECK": "off",
            "LR_RECON_PROVENANCE": "off",
        }
        with (
            mock.patch.dict(os.environ, env),
            mock.patch.object(M, "run_pass", side_effect=fake_pass),
            mock.patch.object(M, "wait_for_change", return_value=False),
        ):
            self.assertEqual(M.daemon(ctx), 1)
        self.assertEqual(len(passes), 6, "a clean pass resets the streak")
        self.assertIs(
            signal.getsignal(signal.SIGTERM), signal.SIG_DFL, "the handler is restored"
        )


# ── T22: the incident shape, n = 20, P ≤ P_cap ───────────────────────────────────────────────────

# P_cap (estimated, sum of enforced bounds; plan § W9): ps 92 · kitty 7 · composer 20 + 7 ·
# place 2 × 122 · assign 32 · probe (W11) 32 · mints 6 × 32 · claim argv ps 6 × 7 · one page or
# mail 55 · one draft snapshot 44 · unassign 32 — independent of n.
P_CAP = 92 + 7 + 27 + 2 * 122 + 32 + 32 + 6 * 32 + 6 * 7 + 55 + 44 + 32
N = 20
DRAFT_WIDS = {101, 103}


class IncidentShape(Hermetic):
    """A fake-wall replay of a cohort pass: 20 limited sessions whose composers read at and just
    under their bound (two sockets, one stalled), a live foreign driver's claim on every record,
    5 requester mails, 2 HOLD-DRAFT records, --place at its bound. The wall is the sum of what each
    child charges; the control arm turns every W9 switch off and must exceed P_cap."""

    def setUp(self) -> None:
        super().setUp()
        self.holder = subprocess.Popen(["/bin/sleep", "120"])
        self.addCleanup(self.holder.wait)
        self.addCleanup(self.holder.kill)
        self.holder_lstart = store.inproc_lstart(self.holder.pid) or ""
        fake = os.path.join(self.tmp, "fake")
        os.makedirs(fake)
        env = mock.patch.dict(
            os.environ,
            {
                "LR_NOTIFY_BIN": os.path.join(fake, "cc-notify"),
                "LR_PAGE_BIN": os.path.join(fake, "lr-page.sh"),
                "LR_ACCOUNTS_BIN": os.path.join(fake, "claude-accounts"),
                "LR_COMPOSER_SNAP_BIN": os.path.join(fake, "lr-composer-snapshot.sh"),
                "LR_RECON_PROVENANCE": "off",
            },
        )
        env.start()
        self.addCleanup(env.stop)
        with open(self.paths.mode_file, "w") as fh:
            fh.write("act\n")
        open(self.paths.recon_on, "w").close()
        # zero-human (D1.9), so census records are acted on, and the accounts the placer names
        for marker in (self.paths.autorecover_on, self.paths.recon_autorecover_on):
            os.makedirs(os.path.dirname(marker), exist_ok=True)
            open(marker, "w").close()
        os.makedirs(os.path.join(self.home, ".claude"))
        with open(os.path.join(self.home, ".claude", "accounts.json"), "w") as fh:
            json.dump(
                {
                    "accounts": [
                        {"name": a, "config_dir": os.path.join(self.tmp, "cfg-" + a)}
                        for a in ("next2", "next3", "next4")
                    ]
                },
                fh,
            )
        self.charged: Dict[str, float] = collections.defaultdict(float)
        self.n: Dict[str, int] = collections.defaultdict(int)
        self.now = time.time()
        self.cwd = os.path.join(self.tmp, "repo")
        os.makedirs(self.cwd)

    def charge(self, what: str, s: float) -> None:
        self.charged[what] += s
        self.n[what] += 1

    def child(self, *a: Any, **kw: Any) -> Any:
        argv = [str(x) for x in (a[0] if a else kw["args"])]
        lab, t = C.child_label(argv), float(kw["timeout"])
        if lab == "kitten":
            wid = int(argv[6].split(":")[1])
            if (
                wid == 100
            ):  # socket A's first read: stalled at its bound, kill-wait included
                self.charge("composer", t + C.REAP_GRACE_S)
                raise subprocess.TimeoutExpired(argv, t)
            self.charge("composer", 4.9)
            return CP(argv, 0, "")
        if lab == "ps:pid":
            self.charge("lstart-ps", t + C.REAP_GRACE_S)  # answered, at its bound
            ok = argv[-1] == str(self.holder.pid)
            return CP(argv, 0 if ok else 1, self.holder_lstart if ok else "")
        if lab.startswith("cc-notify"):
            self.charge("send", 10)
            return CP(argv, 1 if "--role" in argv else 0)
        if lab == "lr-page.sh":
            self.charge("send", 45)
            return CP(argv, 0)
        if lab == "lr-composer-snapshot.sh":
            self.charge("draft", t + C.REAP_GRACE_S)
            return CP(argv, 0, "snapfile\n")
        if lab.startswith("claude-accounts"):
            self.charge(lab, t + C.REAP_GRACE_S)
            return CP(argv, 0)
        if lab == "sysctl":  # the wake guard's kern.waketime (and boottime, read once)
            self.charge("sysctl", t + C.REAP_GRACE_S)
            return CP(argv, 1)
        self.charge("other:" + lab, t + C.REAP_GRACE_S)
        return CP(argv, 1)

    def composer(self, sock: str, wid: int, run: Any = None, **_kw: Any) -> str:
        try:
            run(  # type: ignore[misc]
                ["kitten", "@", "--to", sock, "get-text", "--match", "id:%d" % wid],
                capture_output=True,
                text=True,
                timeout=5.0,
            )
        except Exception:  # noqa: BLE001 — composer_state's own rule: a failed read is unknown
            return "unknown"
        return "draft" if wid in DRAFT_WIDS else "empty"

    def observe_fake(self, *a: Any, **kw: Any) -> T.Snapshot:
        self.charge(
            "ps+kitty", 92 + 7
        )  # the census ps at its budget, one kitty socket at its bound
        sessions, panes, procs = {}, {}, {}
        for i in range(N + 5):
            sid = "abcdef01-0000-0000-0000-%012d" % i
            limited = i < N
            tx = os.path.join(self.cwd, "t%d.jsonl" % i)
            open(tx, "a").close()
            last = (
                {
                    "limit": True,
                    "kind": "limit",
                    "cap": "seven_day",
                    "resets_at": self.now + 7200,
                }
                if limited
                else {"kind": "assistant"}
            )
            sessions[sid] = T.SessionObs(
                sid=sid,
                acct="next4",
                cfg="/nonexistent-cfg",
                pid=1000 + i,
                lstart=L,
                cwd=self.cwd,
                pane=(5, 100 + i),
                registry_name="p%d" % i,
                holders=[
                    T.HolderObs(
                        pid=1000 + i,
                        lstart=L,
                        cfg="/nonexistent-cfg",
                        src="registry",
                        pane=(5, 100 + i),
                    )
                ],
                transcript=T.TranscriptObs(path=tx, at_rest=True, last=last),
            )
            panes["5:%d" % (100 + i)] = T.PaneObs(
                kitty_pid=5,
                window_id=100 + i,
                sock="unix:/tmp/kitty-%s" % ("A" if i % 2 == 0 else "B"),
                root_pid=2000 + i,
                root_lstart=L,
                root_shape="shell",
                state="claude",
            )
            procs[3000 + i] = T.ProcRow(3000 + i, 1, "S+", L, "/x/claude.exe")
        return T.Snapshot(
            wall=self.now, uptime_raw=0.0, procs=procs, panes=panes, sessions=sessions
        )

    def place(
        self,
        lane: str,
        mvs: Any,
        facts_dir: str,
        kw: Any,
        run: Any = None,
        timeout: float = 30.0,
    ) -> Any:
        self.charge("place", 120 + C.REAP_GRACE_S)
        return {m.sid: T.Placement(acct="next2", reason="ok", weight=1) for m in mvs}, 0

    def setup_world(self) -> M.Ctx:
        for i in range(N):
            sid = "abcdef01-0000-0000-0000-%012d" % i
            d = store.claim_dir(self.paths, sid)
            os.makedirs(d)
            store.atomic_write_json(
                os.path.join(d, "holder"),
                {
                    "pid": self.holder.pid,
                    "lstart": self.holder_lstart,
                    "owner": "cc-lr",
                    "record_id": "foreign-%d" % i,
                },
            )
        ctx = M.Ctx(self.paths, None, self.home)
        for i in range(5):
            r = _limited("bbbbbbbb-0000-0000-0000-%012d" % i, "")
            r.cohort_id = "cm"
            r.terminal = T.Terminal(outcome="CLOSED", proof="p", at=self.now - 60)
            r.requester_sid = "abcdef01-0000-0000-0000-%012d" % (N + i)
            r.requester_pane = ""
            ctx.records[r.sid] = r
        return ctx

    def one_pass(self) -> float:
        ctx = self.setup_world()
        spawned: List[str] = []
        with (
            mock.patch.object(C, "_run_reaped", side_effect=self.child),
            mock.patch.object(C.subprocess, "run", side_effect=self.child),
            mock.patch.object(observe, "observe", side_effect=self.observe_fake),
            mock.patch.object(observe, "composer_state", side_effect=self.composer),
            mock.patch.object(plan, "place", side_effect=self.place),
            mock.patch.object(
                act, "spawn", side_effect=lambda *a, **k: spawned.append(a[2]) or 99999
            ),
            mock.patch.object(  # the fake wall is the clock the per-pass budgets read
                time,
                "monotonic",
                side_effect=lambda: 1000.0 + sum(self.charged.values()),
            ),
        ):
            M.run_pass(ctx)
        self.spawned = spawned
        self.ctx = ctx
        return sum(self.charged.values())

    def test_T22_cohort_pass_is_bounded_by_P_cap(self) -> None:
        p = self.one_pass()
        self.assertLessEqual(p, P_CAP, dict(self.charged))
        self.assertLessEqual(
            self.charged["composer"], M.COMPOSER_BUDGET_S + M.COMPOSER_READ_S
        )
        self.assertLessEqual(
            self.n["send"], 2, "one send: a page is cc-notify then lr-page"
        )
        self.assertLessEqual(self.charged["send"], 55)
        self.assertLessEqual(self.n["draft"], 2, "one draft snapshot (snap + row)")
        self.assertEqual(
            self.charged["lstart-ps"], 0.0, "claims judged in process: no ps"
        )
        self.assertEqual(
            self.spawned, [], "every record is held by a live foreign driver"
        )
        self.assertEqual(
            [k for k in self.charged if k.startswith("other:")], [], dict(self.charged)
        )
        held = [r for r in self.ctx.records.values() if r.substate == "HOLD-DRAFT"]
        self.assertEqual(
            len(held), len(DRAFT_WIDS), "the replay reached the two drafts"
        )
        self.assertGreaterEqual(self.n["place"], 1)

    def test_T22_control_every_switch_off_exceeds_P_cap(self) -> None:
        for name in (
            M.BOUNDED_PASS_OFF,
            M.INPROC_LSTART_OFF,
            M.PAGE_OUTBOX_OFF,
            M.PASS_CAPS_OFF,
        ):
            self.touch(name)
        p = self.one_pass()
        self.assertGreater(p, P_CAP, dict(self.charged))
        self.assertGreater(self.charged["lstart-ps"], 0.0)


if __name__ == "__main__":
    unittest.main()
