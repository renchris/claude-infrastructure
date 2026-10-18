"""The watchdog must not convict a reconciler that is mid-pass on bounded children, and must still
convict a wedged one (2026-10-18: three KILLs in an hour of a working daemon, lr-recon-watchdog.sh).

Replays the measured shape: a pass over 12 limited records whose units each block on a LIVE child
(a real `sleep` subprocess) while a fake wall clock charges each unit its bound — 120 s for the
--place probe at load 265, 80 s per record — so the records alone run past the watchdog's
STALL_MAX_S, whether or not the pass has movers to place.
The child holds the time, so the reconciler's own CPU (what `ps -S` counts) stays near zero and
only ``progress`` can tell working from wedged. The watchdog's thresholds are read from the script
itself, so a retuned watchdog re-checks these bounds instead of drifting from them."""

import json
import os
import re
import shutil
import subprocess
import tempfile
import threading
import unittest
from typing import List
from unittest import mock

from lr_recon import __main__ as M
from lr_recon import clock as C
from lr_recon import plan
from lr_recon import types as T

L = "Tue Sep 29 11:19:17 2026"
N_RECORDS = 12
PLACE_S = (
    120.0  # the --place bound at load 265 (plan.place_timeout), the 10:02:47Z event
)
UNIT_S = (
    80.0  # one record's bounded child work (composer read, admission probe, kitty RC)
)
WATCHDOG = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", "..", "lr-recon-watchdog.sh"
)


def _watchdog_const(name: str) -> int:
    with open(WATCHDOG, encoding="utf-8") as fh:
        m = re.search(r"^%s=([0-9]+)" % name, fh.read(), re.M)
    assert m is not None, "%s not found in %s" % (name, WATCHDOG)
    return int(m.group(1))


STALL_AGE_S = _watchdog_const("STALL_AGE_S")  # frozen this long + no CPU ⇒ KILL
STALL_MAX_S = _watchdog_const("STALL_MAX_S")  # frozen this long, no CPU evidence ⇒ KILL


class FakeTime:
    def __init__(self) -> None:
        self.w = 1792314000.0

    def clock(self) -> C.Clock:
        return C.Clock(wall=lambda: self.w, uptime=lambda: 0.0, env={})


def _session(i: int, now: float, cwd: str) -> T.SessionObs:
    sid = "abcdef01-0000-0000-0000-%012d" % i
    tx = os.path.join(cwd, "t%d.jsonl" % i)
    open(tx, "a").close()
    return T.SessionObs(
        sid=sid,
        acct="next4",
        cfg="/nonexistent-cfg",
        pid=1000 + i,
        lstart=L,
        cwd=cwd,
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
        transcript=T.TranscriptObs(
            path=tx,
            at_rest=True,
            last={
                "limit": True,
                "kind": "limit",
                "cap": "seven_day",
                "resets_at": now + 7200,
            },
        ),
    )


def _snap(now: float, cwd: str) -> T.Snapshot:
    sessions = {}
    panes = {}
    procs = {}
    for i in range(N_RECORDS):
        s = _session(i, now, cwd)
        sessions[s.sid] = s
        panes["5:%d" % (100 + i)] = T.PaneObs(
            kitty_pid=5,
            window_id=100 + i,
            sock="unix:/tmp/kitty-5",
            root_pid=2000 + i,
            root_lstart=L,
            root_shape="shell",
            state="claude",
        )
        # every claude pane needs a claude proc in ps, or the pass abstains (W7a)
        procs[3000 + i] = T.ProcRow(3000 + i, 1, "S+", L, "/x/claude.exe")
    return T.Snapshot(
        wall=now, uptime_raw=0.0, procs=procs, panes=panes, sessions=sessions
    )


class MidPassProgress(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.mkdtemp(prefix="lr-midpass.")
        self.addCleanup(shutil.rmtree, self.tmp, True)
        home = os.path.join(self.tmp, "home")
        os.makedirs(home)
        env = mock.patch.dict(
            os.environ, {"LR_STATE_DIR": os.path.join(self.tmp, "lr"), "HOME": home}
        )
        env.start()
        self.addCleanup(env.stop)
        for p in (
            mock.patch("lr_recon.admit.Admission.probe", return_value=(True, "admit")),
            mock.patch("lr_recon.admit.Admission.mint_token", return_value=None),
        ):
            p.start()
            self.addCleanup(p.stop)
        self.paths = T.Paths.from_env(root=os.path.join(self.tmp, "lr", "recon"))
        os.makedirs(self.paths.requests)
        self.ft = FakeTime()
        self.ctx = M.Ctx(self.paths, "observe", home)
        self.hb = C.Heartbeat(
            os.path.join(self.paths.root, "heartbeat"), 1, L, self.ft.clock()
        )
        self.stalls: List[
            float
        ] = []  # (now - progress_wall) at every instant a watchdog could read
        C.bind_steps(self.hb)
        self.addCleanup(C.bind_steps, None)

    def child(self, bound_s: float) -> None:
        """Block on a live child the way the daemon does, and charge the unit its bound."""
        subprocess.run(["/bin/sleep", "0.01"], check=True, timeout=5)
        self.ft.w += bound_s
        self.stalls.append(self.ft.w - self.hb.snapshot().progress_wall)

    def run_pass(self, unit=None) -> None:
        now = self.ft.w
        unit = unit or (lambda i: UNIT_S)
        seen = {"n": 0}

        def per_record(rec, snap):
            self.child(unit(seen["n"]))
            seen["n"] += 1
            return []

        def place(lane, mvs, facts_dir, kw, timeout):
            self.child(PLACE_S)
            return {}, 124

        with (
            mock.patch("lr_recon.observe.observe", return_value=_snap(now, self.tmp)),
            mock.patch.object(plan, "place", side_effect=place),
            mock.patch.object(M.act, "adopt", side_effect=per_record),
            mock.patch.object(M.act, "spawn") as spawn,
        ):
            M.run_pass(self.ctx)
        spawn.assert_not_called()
        self.stalls.append(self.ft.w - self.hb.snapshot().progress_wall)
        self.assertEqual(seen["n"], N_RECORDS, "every record ran its unit")

    def test_the_bounds_fit_the_watchdog(self) -> None:
        # the gap between two steps is one unit; the largest unit is the --place bound
        self.assertLess(plan.PLACE_TIMEOUT_MAX_S, STALL_AGE_S)
        self.assertGreater(N_RECORDS * UNIT_S, STALL_MAX_S)

    def test_pass_of_bounded_children_past_stall_max_never_reads_stalled(self) -> None:
        start = self.ft.w
        self.run_pass()
        self.assertGreater(
            self.ft.w - start, STALL_MAX_S, "the pass outlasts the old ceiling"
        )
        # pre-fix: progress moved only after run_pass, so the watchdog read the whole pass as one
        # frozen stretch (>= STALL_MAX_S with no CPU of its own) and killed it mid-pass
        self.assertLess(max(self.stalls), STALL_AGE_S, self.stalls)
        self.assertLessEqual(max(self.stalls), PLACE_S)
        self.assertGreater(self.hb.progress, N_RECORDS)

    def test_a_wedged_unit_still_freezes_progress(self) -> None:
        wedged_s = (
            2 * STALL_MAX_S
        )  # a child with no bound: returns only long after any ceiling

        self.run_pass(unit=lambda i: wedged_s if i == 3 else UNIT_S)
        self.assertGreaterEqual(max(self.stalls), wedged_s)
        self.assertGreaterEqual(max(self.stalls), STALL_MAX_S)

    def test_only_the_bound_thread_steps(self) -> None:
        C.step()
        self.assertEqual(self.hb.progress, 1)
        t = threading.Thread(target=C.step)
        t.start()
        t.join()
        self.assertEqual(self.hb.progress, 1, "another thread cannot fake progress")
        C.bind_steps(None)
        C.step()
        self.assertEqual(self.hb.progress, 1, "unbound (--once, tests) is a no-op")

    def test_heartbeat_thread_writes_never_advance(self) -> None:
        self.hb.write_now()
        self.hb.write_now()
        with open(self.hb.path) as fh:
            self.assertEqual(json.load(fh)["progress"], 0)


if __name__ == "__main__":
    unittest.main()
