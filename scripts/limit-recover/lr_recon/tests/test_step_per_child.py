"""Every child the loop thread waits on steps progress and declares its bound, so the watchdog's
CPU floor cannot convict a reconciler that is inside a bounded unit (2026-10-19).

The measured failure: 4cdf10f34 stepped once per stage/record/lane, but one unit chains several
bounded children, so a unit of two children (each blocking on a LIVE child, whose CPU `ps -S` does
not count) froze progress past STALL_AGE_S and recon/watchdog.log 01:19:58Z reads
`KILL -TERM pid=1416: progress=55711 unchanged 186s; CPU +0.02s ... under the 0.50s floor`.

The replay drives the real call sites (plan.unassign, the admission default_runner) through a fake
wall clock that charges each child its full bound, and samples the heartbeat every 30 s inside
the child, the watchdog's launchd interval. ``floor_kill`` is the watchdog's CPU-floor branch
(lr-recon-watchdog.sh, the final `else`) with the self CPU taken as ~0, its thresholds read from
the script so a retuned watchdog re-checks this test instead of drifting from it."""

import ast
import os
import re
import subprocess
import unittest
from typing import Any, List, Tuple
from unittest import mock

from lr_recon import admit
from lr_recon import clock as C
from lr_recon import plan

L = "Sun Oct 18 23:00:00 2026"
PKG = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WATCHDOG = os.path.join(PKG, "..", "lr-recon-watchdog.sh")


def _watchdog_const(name: str) -> int:
    with open(WATCHDOG, encoding="utf-8") as fh:
        m = re.search(r"^%s=([0-9]+)" % name, fh.read(), re.M)
    assert m is not None, "%s not found in %s" % (name, WATCHDOG)
    return int(m.group(1))


STALL_AGE_S = _watchdog_const("STALL_AGE_S")
STEP_MARGIN_S = _watchdog_const("STEP_MARGIN_S")
WATCHDOG_TICK_S = 30


def floor_kill(hb: Any, now: float) -> bool:
    """The watchdog's no-CPU verdict for a holder whose own CPU is ~0 (it sits on live children)."""
    stalled = now - hb.progress_wall
    inside_child = int(hb.step_due) > 0 and now < int(hb.step_due) + STEP_MARGIN_S
    return stalled >= STALL_AGE_S and not inside_child


class FakeWall:
    def __init__(self) -> None:
        self.w = 1792371598.0
        self.t0 = self.w

    def clock(self) -> C.Clock:
        return C.Clock(wall=lambda: self.w, uptime=lambda: self.w - self.t0, env={})


class StepPerChild(unittest.TestCase):
    def setUp(self) -> None:
        self.ft = FakeWall()
        self.hb = C.Heartbeat("/nonexistent/heartbeat", 1416, L, self.ft.clock())
        C.bind_steps(self.hb)
        self.addCleanup(C.bind_steps, None)
        self.kills: List[
            Tuple[float, float]
        ] = []  # (now, stalled) at every floor-kill read

    def sample(self) -> None:
        snap = self.hb.snapshot()
        if floor_kill(snap, self.ft.w):
            self.kills.append((self.ft.w, self.ft.w - snap.progress_wall))

    def child(self, *args: Any, **kw: Any) -> "subprocess.CompletedProcess[str]":
        """A live child that uses its whole bound: the wall moves, the loop's CPU does not."""
        bound = float(kw["timeout"])
        end = self.ft.w + bound
        while self.ft.w < end:
            self.ft.w = min(end, self.ft.w + WATCHDOG_TICK_S)
            self.sample()
        return subprocess.CompletedProcess(args[0], 0, "", "")

    def unit(self) -> None:
        """One unit of the 2026-10-19 shape: an admission probe chained into a phantom void —
        sequential bounded children (two 30 s admission probes, a 120 s --place, a 30 s void) and no step between
        them in 4cdf10f34, whose steps sat per stage/record/lane."""
        admit.default_runner(["/usr/bin/true"])
        admit.default_runner(["/usr/bin/true"])
        plan.place(
            "next3",
            [mock.Mock(sid="s1", w=1)],
            "/nonexistent",
            {},
            timeout=plan.PLACE_TIMEOUT_MAX_S,
        )
        plan.unassign("a1")

    def run_unit(self, run_fn: Any) -> None:
        with (
            mock.patch.object(C.subprocess, "run", side_effect=run_fn),
            mock.patch("lr_recon.plan.T.to_dict", return_value={"sid": "s1"}),
        ):
            self.unit()

    def test_the_replayed_unit_outlasts_the_floor(self) -> None:
        self.assertGreater(30 + 30 + plan.PLACE_TIMEOUT_MAX_S + 30, STALL_AGE_S)

    def test_prefix_shape_is_killed(self) -> None:
        # control: the same unit with the children run bare (no declare, no step) — 4cdf10f34
        C.bind_steps(None)
        self.run_unit(self.child)
        self.assertTrue(self.kills, "pre-fix, the unit reads as a wedge")
        self.assertGreaterEqual(max(s for _, s in self.kills), STALL_AGE_S)

    def test_a_unit_of_chained_bounded_children_is_never_floor_killed(self) -> None:
        self.run_unit(self.child)
        self.assertEqual(self.kills, [])
        self.assertEqual(self.hb.progress, 4, "one step per child")
        self.assertEqual(self.hb.step_due, 0.0, "nothing in flight after the last step")
        self.assertEqual(self.hb.max_step_gap_s, plan.PLACE_TIMEOUT_MAX_S)
        self.assertEqual(self.hb.max_step_gap_bound_s, plan.PLACE_TIMEOUT_MAX_S)

    def test_a_child_bound_past_the_floor_is_waited_out(self) -> None:
        # one child whose own bound exceeds STALL_AGE_S (a load-scaled bound, or spawn latency
        # under load eating the gap): only step_due tells the watchdog it is still inside it
        bound = STALL_AGE_S + 60.0
        C.bind_steps(None)
        with mock.patch.object(C.subprocess, "run", side_effect=self.child):
            C.run_bounded(["/usr/bin/true"], timeout=bound)
        self.assertTrue(
            self.kills, "control: with no declared bound it reads as a wedge"
        )
        self.kills.clear()
        C.bind_steps(self.hb)
        self.hb.advance()
        with mock.patch.object(C.subprocess, "run", side_effect=self.child):
            C.run_bounded(["/usr/bin/true"], timeout=bound)
        self.assertEqual(self.kills, [])

    def test_a_child_that_overruns_its_bound_still_dies(self) -> None:
        # wedged inside the child: timeout never fires (an uninterruptible wait), no step comes
        def wedged(*args: Any, **kw: Any) -> Any:
            bound = float(kw["timeout"])
            self.ft.w += bound + STEP_MARGIN_S + STALL_AGE_S
            self.sample()
            raise subprocess.TimeoutExpired(args[0], bound)

        with mock.patch.object(C.subprocess, "run", side_effect=wedged):
            self.assertEqual(plan.unassign("a1"), 124)
        self.assertTrue(
            self.kills, "a loop past its own declared bound + margin is a wedge"
        )

    def test_a_wedged_loop_with_no_child_dies_at_the_floor(self) -> None:
        self.ft.w += STALL_AGE_S
        self.sample()
        self.assertEqual(len(self.kills), 1)

    def test_steps_even_when_the_child_raises(self) -> None:
        def boom(*args: Any, **kw: Any) -> Any:
            raise subprocess.TimeoutExpired(args[0], kw["timeout"])

        with mock.patch.object(C.subprocess, "run", side_effect=boom):
            self.assertEqual(plan.assign_many([{"sid": "x"}]), 124)
        self.assertEqual(self.hb.progress, 1)

    def test_timeout_is_required(self) -> None:
        with self.assertRaises(TypeError):
            C.run_bounded(["/usr/bin/true"])
        self.assertEqual(self.hb.progress, 0)

    def test_heartbeat_publishes_the_promise(self) -> None:
        self.hb.declare_child(120.0)
        snap = self.hb.snapshot()
        self.assertEqual(snap.step_due, self.ft.w + 120.0)
        self.assertEqual(snap.child_bound_s, 120.0)
        self.assertIn('"step_due":', self.hb.render())

    def test_off_the_loop_thread_nothing_is_declared(self) -> None:
        C.bind_steps(None)
        C.declare_child(120.0)
        self.assertEqual(self.hb.step_due, 0.0)


class EveryLoopChildIsBounded(unittest.TestCase):
    def test_subprocess_run_is_called_only_inside_run_bounded(self) -> None:
        """A bare ``subprocess.run`` (call or default argument) anywhere else in the package is a
        child the loop could wait on with no step and no declared bound."""
        bad = []
        for name in sorted(os.listdir(PKG)):
            if not name.endswith(".py"):
                continue
            with open(os.path.join(PKG, name), encoding="utf-8") as fh:
                tree = ast.parse(fh.read(), name)
            allowed = set()
            for n in ast.walk(tree):
                if (
                    name == "clock.py"
                    and isinstance(n, ast.FunctionDef)
                    and n.name == "run_bounded"
                ):
                    allowed |= {id(x) for x in ast.walk(n)}
            for n in ast.walk(tree):
                if (
                    isinstance(n, ast.Attribute)
                    and n.attr == "run"
                    and isinstance(n.value, ast.Name)
                    and n.value.id == "subprocess"
                    and id(n) not in allowed
                ):
                    bad.append("%s:%d" % (name, n.lineno))
        self.assertEqual(bad, [])


if __name__ == "__main__":
    unittest.main()
