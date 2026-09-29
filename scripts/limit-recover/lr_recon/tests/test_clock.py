"""clock.py: sleep accounting, deadline shifting, wake guard, heartbeat file, caffeinate hold.

Hermetic: every time source, sysctl, load reading and process spawn is a fake."""

import json
import os
import re
import shutil
import tempfile
import time
import unittest
from typing import Any, Dict, List, Optional

from lr_recon import clock as C
from lr_recon import types as T

WAKE = "{ sec = %d, usec = 500000 } Tue Sep 29 06:00:00 2026\n"


class FakeTime:
    def __init__(self, w: float = 1_790_000_000.0, u: float = 1000.0) -> None:
        self.w = w
        self.u = u
        self.sysctl_out: Dict[str, str] = {}
        self.sysctl_calls: List[str] = []

    def wall(self) -> float:
        return self.w

    def uptime(self) -> float:
        return self.u

    def sysctl(self, name: str) -> str:
        self.sysctl_calls.append(name)
        return self.sysctl_out.get(name, "")

    def clock(self, env: Optional[Dict[str, str]] = None, **kw: Any) -> C.Clock:
        return C.Clock(
            wall=self.wall,
            uptime=self.uptime,
            sysctl=self.sysctl,
            env={} if env is None else env,
            **kw,
        )


def record() -> T.Record:
    rec = T.Record(sid="s1", record_id="recon:c:s1:1")
    rec.next_eligible_at = 100.0
    rec.sentinel_until = 200.0
    rec.wait = T.Wait("WAIT_SLOT", since=50.0, eta=300.0)
    rec.timeline.detected = 10.0
    rec.timeline.planned = 20.0
    return rec


class SleepAccounting(unittest.TestCase):
    def test_simulated_sleep_shifts_deadlines_and_observes_once(self) -> None:
        ft = FakeTime()
        clk = ft.clock()
        self.assertEqual(clk.tick(), 0.0)  # first tick has no baseline
        ft.w += 600
        ft.u += 1
        slept = clk.tick()
        self.assertAlmostEqual(slept, 599.0)
        self.assertAlmostEqual(clk.total_slept, 599.0)
        self.assertTrue(clk.take_observe_only())
        self.assertFalse(clk.take_observe_only())
        rec = record()
        C.shift_record(rec, slept)
        self.assertAlmostEqual(rec.next_eligible_at or 0, 699.0)
        self.assertAlmostEqual(rec.sentinel_until or 0, 799.0)
        assert rec.wait is not None
        self.assertAlmostEqual(rec.wait.since, 649.0)
        self.assertAlmostEqual(rec.wait.eta or 0, 899.0)
        self.assertEqual((rec.timeline.detected, rec.timeline.planned), (10.0, 20.0))

    def test_normal_drift_is_not_sleep(self) -> None:
        ft = FakeTime()
        clk = ft.clock()
        clk.tick()
        ft.w += 64.0
        ft.u += 60.0  # 4 s drift < 5 s threshold
        self.assertEqual(clk.tick(), 0.0)
        self.assertFalse(clk.take_observe_only())
        self.assertEqual(clk.total_slept, 0.0)
        self.assertFalse(C.pause_is_sleep(4.9))
        self.assertTrue(C.pause_is_sleep(5.1))

    def test_threshold_env_override(self) -> None:
        ft = FakeTime()
        clk = ft.clock(env={"LR_SLEEP_THRESHOLD_S": "2"})
        clk.tick()
        ft.w += 3
        self.assertAlmostEqual(clk.tick(), 3.0)

    def test_shift_leaves_none_and_ignores_nonpositive(self) -> None:
        rec = T.Record(sid="s", record_id="r")
        C.shift_record(rec, 30.0)
        self.assertIsNone(rec.next_eligible_at)
        self.assertIsNone(rec.sentinel_until)
        self.assertIsNone(rec.wait)
        rec = record()
        C.shift_record(rec, 0.0)
        self.assertEqual(rec.next_eligible_at, 100.0)
        rec.wait = T.Wait("WAIT_SLOT")  # since unset (0.0), eta None
        C.shift_record(rec, 10.0)
        self.assertEqual(rec.wait.since, 0.0)
        self.assertIsNone(rec.wait.eta)


class Sysctl(unittest.TestCase):
    def test_parse_both_forms_and_garbage(self) -> None:
        self.assertAlmostEqual(C.parse_timeval(WAKE % 1790664000) or 0, 1790664000.5)
        pref = "kern.boottime: { sec = 1789594110, usec = 498724 } Wed Sep 16 16:28:30 2026"
        self.assertAlmostEqual(C.parse_timeval(pref) or 0, 1789594110.498724)
        for junk in ("", "garbage", "{ sec = , usec = 1 }", "sysctl: unknown oid"):
            self.assertIsNone(C.parse_timeval(junk))

    def test_waketime_and_cached_boottime(self) -> None:
        ft = FakeTime()
        ft.sysctl_out = {
            "kern.waketime": WAKE % 1790000100,
            "kern.boottime": WAKE % 1789000000,
        }
        clk = ft.clock()
        self.assertAlmostEqual(clk.waketime() or 0, 1790000100.5)
        self.assertAlmostEqual(clk.boottime() or 0, 1789000000.5)
        clk.boottime()
        self.assertEqual(ft.sysctl_calls.count("kern.boottime"), 1)
        ft.sysctl_out = {}
        self.assertIsNone(ft.clock().waketime())
        self.assertIsNone(ft.clock().boottime())

    def test_default_sysctl_failure_is_empty(self) -> None:
        self.assertEqual(C._run_sysctl("kern.no.such.oid.lr_recon"), "")


class WakeGuard(unittest.TestCase):
    def test_recent_wake_blocks_older_wake_passes(self) -> None:
        ft = FakeTime()
        clk = ft.clock()
        ft.sysctl_out["kern.waketime"] = WAKE % int(ft.w - 10)
        self.assertFalse(clk.wake_guard_ok())
        ft.sysctl_out["kern.waketime"] = WAKE % int(ft.w - 40)
        self.assertTrue(clk.wake_guard_ok())
        self.assertFalse(clk.wake_guard_ok(guard_s=60))

    def test_env_override(self) -> None:
        ft = FakeTime()
        ft.sysctl_out["kern.waketime"] = WAKE % int(ft.w - 40)
        self.assertFalse(ft.clock(env={"LR_WAKE_GUARD_S": "120"}).wake_guard_ok())
        self.assertTrue(ft.clock(env={"LR_WAKE_GUARD_S": "junk"}).wake_guard_ok())

    def test_unreadable_waketime_falls_back_to_construction_age(self) -> None:
        ft = FakeTime()
        clk = ft.clock()
        self.assertFalse(clk.wake_guard_ok())  # no evidence at startup ⇒ do not pass
        ft.w += 31
        ft.u += 31
        self.assertTrue(clk.wake_guard_ok())
        clk.tick()
        ft.w += 600  # a sleep tick() observes restarts the fallback clock
        clk.tick()
        self.assertFalse(clk.wake_guard_ok())
        ft.w += 30
        self.assertTrue(clk.wake_guard_ok())


class LoadMultiplier(unittest.TestCase):
    def test_floor_and_scale(self) -> None:
        ft = FakeTime()
        idle = ft.clock(getloadavg=lambda: (0.5, 0.0, 0.0), cpu_count=lambda: 8)
        self.assertEqual(idle.load_multiplier(), 1.0)
        busy = ft.clock(getloadavg=lambda: (48.0, 0.0, 0.0), cpu_count=lambda: 8)
        self.assertAlmostEqual(busy.load_multiplier(), 3.0)
        nocpu = ft.clock(getloadavg=lambda: (4.0, 0.0, 0.0), cpu_count=lambda: None)
        self.assertAlmostEqual(nocpu.load_multiplier(), 2.0)

        def boom() -> Any:
            raise OSError("no loadavg")

        self.assertEqual(ft.clock(getloadavg=boom).load_multiplier(), 1.0)


class HeartbeatFile(unittest.TestCase):
    def setUp(self) -> None:
        self.dir = tempfile.mkdtemp(prefix="lr-clock-test.")
        self.path = os.path.join(self.dir, "recon", "heartbeat")

    def tearDown(self) -> None:
        shutil.rmtree(self.dir, ignore_errors=True)

    def read(self) -> str:
        with open(self.path) as fh:
            return fh.read()

    def test_write_now_then_advance(self) -> None:
        ft = FakeTime()
        hb = C.Heartbeat(self.path, 4242, "Tue Sep 29 06:19:17 2026", ft.clock())
        self.assertTrue(hb.write_now())
        first = json.loads(self.read())
        self.assertEqual((first["pid"], first["progress"]), (4242, 0))
        ft.w += 12.5
        hb.advance()
        hb.write_now()
        raw = self.read()
        self.assertNotIn(": ", raw)
        self.assertNotIn(", ", raw)
        m = re.search(r'"progress_wall":[0-9.]*', raw)
        assert m is not None
        self.assertAlmostEqual(float(m.group(0).split(":")[1]), ft.w)
        back = T.from_dict(T.Heartbeat, json.loads(raw))
        self.assertEqual(back.progress, 1)
        self.assertAlmostEqual(back.uptime_raw, ft.u)
        self.assertEqual(
            os.listdir(os.path.dirname(self.path)), ["heartbeat"]
        )  # no tmp litter

    def test_write_error_is_counted_not_raised(self) -> None:
        def fail(path: str, data: str) -> None:
            raise OSError("disk full")

        hb = C.Heartbeat(self.path, 1, "x", FakeTime().clock(), write=fail)
        self.assertFalse(hb.write_now())
        self.assertEqual(hb.write_errors, 1)

    def test_thread_start_stop(self) -> None:
        writes: List[str] = []

        def counting(path: str, data: str) -> None:
            writes.append(data)
            C.atomic_write(path, data)

        hb = C.Heartbeat(
            self.path, 7, "x", C.Clock(env={}), interval_s=0.05, write=counting
        )
        hb.start()
        hb.start()  # idempotent
        deadline = time.monotonic() + 0.2
        while len(writes) < 3 and time.monotonic() < deadline:
            time.sleep(0.01)
        hb.stop(timeout=1)
        self.assertGreaterEqual(len(writes), 2)
        n = len(writes)
        time.sleep(0.08)
        self.assertEqual(len(writes), n)  # stopped means stopped
        self.assertTrue(os.path.exists(self.path))


class FakeChild:
    def __init__(self, argv: List[str]) -> None:
        self.argv = argv
        self.rc: Optional[int] = None
        self.terminated = False

    def poll(self) -> Optional[int]:
        return self.rc

    def terminate(self) -> None:
        self.terminated = True
        self.rc = -15

    def kill(self) -> None:
        self.rc = -9

    def wait(self, timeout: Optional[float] = None) -> Optional[int]:
        return self.rc


class CaffeinateHold(unittest.TestCase):
    def setUp(self) -> None:
        self.children: List[FakeChild] = []

    def popen(self, argv: List[str], **kw: Any) -> FakeChild:
        child = FakeChild(argv)
        self.children.append(child)
        return child

    def test_idempotent_hold_release_and_respawn(self) -> None:
        caf = C.Caffeinate(999, popen=self.popen)
        self.assertTrue(caf.set_hold(True))
        self.assertTrue(caf.set_hold(True))
        self.assertEqual(len(self.children), 1)
        self.assertEqual(self.children[0].argv, [C.CAFFEINATE, "-i", "-s", "-w", "999"])
        self.children[0].rc = 0  # child died while wanted
        self.assertTrue(caf.set_hold(True))
        self.assertEqual(len(self.children), 2)
        self.assertFalse(caf.set_hold(False))
        self.assertTrue(self.children[1].terminated)
        self.assertFalse(caf.set_hold(False))
        caf.close()
        self.assertEqual(caf.spawns, 2)

    def test_spawn_failure_reports_no_hold(self) -> None:
        def broken(argv: List[str], **kw: Any) -> Any:
            raise OSError("no caffeinate")

        caf = C.Caffeinate(1, popen=broken)
        self.assertFalse(caf.set_hold(True))
        caf.close()


if __name__ == "__main__":
    unittest.main()
