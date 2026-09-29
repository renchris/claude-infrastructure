"""§C10 fence: every predicate branch through the python mirror, then bash-vs-python parity.

Hermetic: every store lives in a temp dir named by LR_STATE_DIR / LR_RECON_ROOT, and the only
process touched is a ``sleep`` this file starts and kills itself.
"""

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from typing import Dict, List, Optional, Tuple

from lr_recon import fence
from lr_recon import types as T

SCRIPT = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "..", "lr-recon-fence.sh")
)
SID = "abcdef0123456789"
RID = "recon:c1:abcdef01:1"
NOW = 1790000500.0
OLD_PW = 1790000000.1  # 499.9 s before NOW: stale


def _compact(obj: object) -> str:
    return json.dumps(obj, separators=(",", ":"))


class _State:
    """A temp state tree plus the knobs one scenario sets."""

    def __init__(self) -> None:
        self.dir = tempfile.mkdtemp(prefix="lr-fence-")
        self.env = {
            "HOME": os.path.join(self.dir, "home"),
            "LR_STATE_DIR": os.path.join(self.dir, "lr"),
            "LR_RECON_ROOT": os.path.join(self.dir, "lr", "recon"),
        }
        self.paths = T.Paths.from_env(env=self.env)
        os.makedirs(self.paths.owned)
        self.record_id_env = ""
        self.now = NOW
        self.wake = 0.0

    def recon_on(self) -> None:
        open(self.paths.recon_on, "w").close()

    def owned(
        self, procs: List[Tuple[str, int, str]], raw: Optional[str] = None
    ) -> None:
        body = raw
        if body is None:
            body = _compact(
                {
                    "record_id": RID,
                    "attempt": 1,
                    "procs": [
                        {"role": r, "pid": p, "lstart": ls, "argv_hash": ""}
                        for r, p, ls in procs
                    ],
                }
            )
        with open(os.path.join(self.paths.owned, SID), "w") as fh:
            fh.write(body)

    def heartbeat(self, progress_wall: float) -> None:
        with open(self.paths.heartbeat, "w") as fh:
            fh.write(
                _compact(
                    {
                        "pid": 1,
                        "lstart": "Tue Sep 29 11:19:17 2026",
                        "progress": 7,
                        "wall": progress_wall,
                        "uptime_raw": 12.0,
                        "progress_wall": progress_wall,
                    }
                )
            )

    def py(self, alive: fence.Alive) -> Tuple[bool, str]:
        return fence.defers(
            self.paths, SID, self.record_id_env, self.now, self.wake, alive
        )

    def bash(self) -> Tuple[bool, str, str]:
        env: Dict[str, str] = {"PATH": "/usr/bin:/bin:/usr/sbin:/sbin"}
        env.update(self.env)
        env.update(
            {
                "LR_RECON_NOW": repr(self.now),
                "LR_RECON_WAKETIME": repr(self.wake),
                "LR_RECORD_ID": self.record_id_env,
            }
        )
        cp = subprocess.run(
            ["/bin/bash", SCRIPT, "defers", SID],
            env=env,
            capture_output=True,
            text=True,
            timeout=30,
            check=False,
        )
        reason = ""
        for tok in cp.stderr.split():
            if tok.startswith("reason="):
                reason = tok[len("reason=") :]
        return cp.returncode == 0, reason, cp.stdout

    def close(self) -> None:
        shutil.rmtree(self.dir, ignore_errors=True)


def _dead(pid: int, lstart: str) -> bool:
    return False


class _Sleeper:
    """A real process of our own, with its real lstart."""

    def __enter__(self) -> "_Sleeper":
        self.proc = subprocess.Popen(["sleep", "30"])
        self.pid = self.proc.pid
        self.lstart = fence.lstart_of(self.pid)
        return self

    def __exit__(self, *exc: object) -> None:
        self.proc.kill()
        self.proc.wait()


# Each scenario: (name, setup(state, sleeper), expected defer, expected reason or reason prefix).
def _s_recon_off(s: _State, z: _Sleeper) -> None:
    s.owned([("actuator", z.pid, z.lstart)])


def _s_not_owned(s: _State, z: _Sleeper) -> None:
    s.recon_on()


def _s_own_actuator(s: _State, z: _Sleeper) -> None:
    s.recon_on()
    s.owned([("actuator", z.pid, z.lstart)])
    s.heartbeat(NOW - 1)
    s.record_id_env = RID


def _s_fresh(s: _State, z: _Sleeper) -> None:
    s.recon_on()
    s.owned([])
    s.heartbeat(NOW - 100)


def _s_stale_live(s: _State, z: _Sleeper) -> None:
    s.recon_on()
    s.owned([("watcher", 1, "never"), ("actuator", z.pid, z.lstart)])
    s.heartbeat(OLD_PW)


def _s_stale_dead(s: _State, z: _Sleeper) -> None:
    s.recon_on()
    s.owned([("actuator", 999999, "Tue Sep 29 11:19:17 2026")])
    s.heartbeat(OLD_PW)


def _s_wake(s: _State, z: _Sleeper) -> None:
    s.recon_on()
    s.owned([])
    s.heartbeat(OLD_PW)
    s.wake = NOW - 60


def _s_pid_reuse(s: _State, z: _Sleeper) -> None:
    s.recon_on()
    s.owned([("actuator", z.pid, "Thu Jan  1 00:00:00 1970")])
    s.heartbeat(OLD_PW)


def _s_malformed(s: _State, z: _Sleeper) -> None:
    s.recon_on()
    s.owned([], raw='{"record_id":"x","procs":[{"role":"a"')
    s.heartbeat(NOW - 1)


def _s_no_heartbeat(s: _State, z: _Sleeper) -> None:
    s.recon_on()
    s.owned([("actuator", 999999, "Tue Sep 29 11:19:17 2026")])


SCENARIOS = [
    ("recon-off", _s_recon_off, False, "recon-off"),
    ("not-owned", _s_not_owned, False, "not-owned"),
    ("own-actuator", _s_own_actuator, False, "own-actuator"),
    ("heartbeat-fresh", _s_fresh, True, "heartbeat-fresh"),
    ("stale+live", _s_stale_live, True, "proc-alive:actuator:"),
    ("stale+dead", _s_stale_dead, False, "lapsed"),
    ("wake-adjusted", _s_wake, True, "heartbeat-fresh"),
    ("pid-reuse", _s_pid_reuse, False, "lapsed"),
    ("malformed", _s_malformed, True, "owned-unreadable"),
    ("no-heartbeat", _s_no_heartbeat, False, "lapsed"),
]


class FenceBranches(unittest.TestCase):
    def _run(self, setup, alive: Optional[fence.Alive] = None) -> Tuple[bool, str]:
        s = _State()
        try:
            with _Sleeper() as z:
                setup(s, z)
                return s.py(alive or fence.proc_alive)
        finally:
            s.close()

    def test_each_branch(self) -> None:
        for name, setup, want_defer, want_reason in SCENARIOS:
            with self.subTest(name=name):
                got_defer, reason = self._run(setup)
                self.assertEqual(got_defer, want_defer, reason)
                self.assertTrue(reason.startswith(want_reason), reason)

    def test_heartbeat_outranks_procs(self) -> None:
        # rule 4 before rule 5: a fresh heartbeat defers even when every proc is dead
        self.assertEqual(self._run(_s_fresh, _dead), (True, "heartbeat-fresh"))

    def test_injected_alive_is_consulted_in_order(self) -> None:
        seen: List[int] = []

        def alive(pid: int, lstart: str) -> bool:
            seen.append(pid)
            return pid != 1

        defer, reason = self._run(_s_stale_live, alive)
        self.assertTrue(defer)
        self.assertEqual(seen[0], 1)
        self.assertTrue(reason.startswith("proc-alive:actuator:"))

    def test_bad_sid_is_not_owned(self) -> None:
        s = _State()
        try:
            s.recon_on()
            for sid in ("", "../heartbeat", "a/b"):
                self.assertEqual(
                    fence.defers(s.paths, sid, "", NOW, 0.0, _dead),
                    (False, "not-owned"),
                )
        finally:
            s.close()


class FenceReaders(unittest.TestCase):
    def test_read_owned_and_heartbeat(self) -> None:
        s = _State()
        try:
            self.assertIsNone(fence.read_owned(s.paths, SID))
            self.assertIsNone(fence.read_heartbeat(s.paths))
            s.owned([("actuator", 123, "Tue Sep 29 11:19:17 2026")])
            s.heartbeat(OLD_PW)
            ff = fence.read_owned(s.paths, SID)
            assert ff is not None
            self.assertEqual(ff.record_id, RID)
            self.assertEqual(ff.attempt, 1)
            self.assertEqual(
                ff.procs, [T.ProcRole("actuator", 123, "Tue Sep 29 11:19:17 2026")]
            )
            hb = fence.read_heartbeat(s.paths)
            assert hb is not None
            self.assertEqual(hb.progress_wall, OLD_PW)
            s.owned([], raw="not json{")
            self.assertIsNone(fence.read_owned(s.paths, SID))
        finally:
            s.close()

    def test_parse_waketime(self) -> None:
        self.assertEqual(
            fence.parse_waketime(
                "{ sec = 1790551947, usec = 990086 } Sun Sep 27 18:32:27 2026"
            ),
            1790551947.0,
        )
        self.assertEqual(fence.parse_waketime(""), 0.0)
        self.assertEqual(fence.parse_waketime("garbage"), 0.0)
        self.assertEqual(fence.read_waketime({"LR_RECON_WAKETIME": "42"}), 42.0)

    def test_lstart_collapsed_form(self) -> None:
        self.assertEqual(
            fence.lstart_norm("Wed Sep  9 01:02:03 2026  "), "Wed Sep 9 01:02:03 2026"
        )
        with _Sleeper() as z:
            self.assertNotIn("  ", z.lstart)
            doubled = z.lstart.replace(" ", "  ", 1)
            self.assertTrue(fence.proc_alive(z.pid, doubled))

    def test_proc_alive_exact(self) -> None:
        with _Sleeper() as z:
            self.assertTrue(fence.proc_alive(z.pid, z.lstart))
            self.assertTrue(fence.proc_alive(z.pid, z.lstart + "  "))
            self.assertFalse(fence.proc_alive(z.pid, "Thu Jan  1 00:00:00 1970"))
            self.assertFalse(fence.proc_alive(z.pid, ""))
        self.assertFalse(fence.proc_alive(0, "x"))


class FenceParity(unittest.TestCase):
    """The bash CLI and the mirror, on the same tree, must give the same verdict and reason."""

    def test_bash_matches_python(self) -> None:
        for name, setup, want_defer, _ in SCENARIOS:
            with self.subTest(name=name):
                s = _State()
                try:
                    with _Sleeper() as z:
                        setup(s, z)
                        py = s.py(fence.proc_alive)
                        b_defer, b_reason, b_out = s.bash()
                    self.assertEqual((b_defer, b_reason), py)
                    self.assertEqual(b_defer, want_defer)
                    self.assertEqual(b_out, "")
                finally:
                    s.close()


if __name__ == "__main__":
    unittest.main()
