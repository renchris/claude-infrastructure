"""band.py and the two plists: the recovery rail runs at priority 31 and says so (REPORT lever A1).

docs/research/lr-sustained-load-2026-10-20/REPORT.md §3.1: the reconciler read `20T` in `ps -M`
because its plist set no ProcessType, and every child it started inherited 20 while the sessions it
competes with ran at 31. Hermetic: the band reader is injected except in the one test that reads
this process's own band through the real call."""

import os
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
from typing import List, Optional
from unittest import mock

from lr_recon import __main__ as M
from lr_recon import band
from lr_recon import report as R
from lr_recon import store
from lr_recon import types as T

HERE = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


class PlistsSetTheInteractiveBand(unittest.TestCase):
    def test_both_rail_jobs_declare_processtype_interactive(self) -> None:
        """Before: neither plist had the key, so launchd applied its default light limits (PRI 20)."""
        for name in ("com.reso.lr-reconciler.plist", "com.reso.lr-reset-poller.plist"):
            with open(os.path.join(HERE, name), "rb") as fh:
                pl = plistlib.load(fh)
            self.assertEqual(pl.get("ProcessType"), "Interactive", name)

    def test_the_staged_move_kick_keeps_the_same_band(self) -> None:
        path = os.path.join(
            HERE, "..", "..", "launchd", "staged", "com.reso.lr-move-kick.plist"
        )
        if not os.path.isfile(path):
            self.skipTest("staged move-kick plist absent")
        with open(path, "rb") as fh:
            self.assertEqual(plistlib.load(fh).get("ProcessType"), "Interactive")


class BasePriority(unittest.TestCase):
    def _child_band(self, prefix: List[str]) -> Optional[int]:
        code = "from lr_recon import band; print(band.base_priority())"
        try:
            cp = subprocess.run(
                prefix + [sys.executable, "-c", code],
                capture_output=True,
                text=True,
                timeout=60,
                env=dict(os.environ, PYTHONPATH=HERE),
            )
        except (OSError, subprocess.TimeoutExpired):
            self.skipTest("child did not answer in 60 s under load")
        out = cp.stdout.strip()
        return int(out) if out.isdigit() else None

    @unittest.skipUnless(sys.platform == "darwin", "darwin only")
    def test_reads_the_band_a_child_inherits_and_a_utility_clamp(self) -> None:
        """The reader tells the two bands apart: a plain child (start_new_session too) reads its
        parent's band, and a child under `taskpolicy -c utility` reads 20, launchd's default."""
        mine = band.base_priority()
        self.assertIsInstance(mine, int)
        self.assertEqual(self._child_band([]), mine)
        if not os.access("/usr/sbin/taskpolicy", os.X_OK):
            self.skipTest("taskpolicy absent")
        clamped = self._child_band(["/usr/sbin/taskpolicy", "-c", "utility"])
        self.assertEqual(clamped, 20)
        self.assertTrue(band.below_floor(clamped))

    def test_a_gone_pid_reads_none(self) -> None:
        self.assertIsNone(band.base_priority(2**30))

    @unittest.skipUnless(sys.platform == "darwin", "darwin only")
    def test_run_as_a_file_it_prints_the_named_pids_band(self) -> None:
        """bin/cc-dispatch's band self-check runs ``python3 -I band.py <its pid>``: the same read,
        as a number on stdout; an unreadable pid prints ``?`` and exits 1."""
        path = os.path.join(HERE, "lr_recon", "band.py")
        try:
            cp = subprocess.run(
                [sys.executable, "-I", path, str(os.getpid())],
                capture_output=True,
                text=True,
                timeout=60,
            )
            gone = subprocess.run(
                [sys.executable, "-I", path, str(2**30)],
                capture_output=True,
                text=True,
                timeout=60,
            )
        except (OSError, subprocess.TimeoutExpired):
            self.skipTest("child did not answer in 60 s under load")
        self.assertEqual(
            (cp.returncode, cp.stdout.strip()), (0, str(band.base_priority()))
        )
        self.assertEqual((gone.returncode, gone.stdout.strip()), (1, "?"))

    def test_the_dispatcher_plist_declares_processtype_interactive(self) -> None:
        """Wave 5: the dispatcher shipped as Background (PRI 4); its rank read timed out every pass."""
        # plutil, not plistlib: the plist's long-standing header comment carries `--` sequences,
        # which expat rejects inside an XML comment and launchd's own parser accepts.
        path = os.path.join(HERE, "..", "..", "launchd", "com.claude.dispatcher.plist")
        if not os.access("/usr/bin/plutil", os.X_OK):
            self.skipTest("plutil absent")
        cp = subprocess.run(
            ["/usr/bin/plutil", "-extract", "ProcessType", "raw", path],
            capture_output=True,
            text=True,
            timeout=60,
        )
        self.assertEqual((cp.returncode, cp.stdout.strip()), (0, "Interactive"))


class Check(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.mkdtemp(prefix="lr-band-")
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.log = os.path.join(self.tmp, "band.log")
        self.pages: List[str] = []

    def run_check(self, pri: Optional[int], paged: bool = False) -> bool:
        return band.check(
            self.log,
            1000.0,
            paged,
            self.pages.append,
            store.append_bounded,
            read=lambda: pri,
            pid=4242,
        )

    def lines(self) -> List[str]:
        with open(self.log, encoding="utf-8") as fh:
            return fh.read().splitlines()

    def test_below_31_logs_and_pages_once(self) -> None:
        self.assertTrue(self.run_check(20))
        self.assertTrue(self.run_check(20, paged=True))
        self.assertEqual(len(self.pages), 1)
        self.assertIn("priority 20", self.pages[0])
        self.assertIn("ProcessType Interactive", self.pages[0])
        self.assertEqual(
            self.lines(), ["1000 pid=4242 pri=20 floor=31 low"] * 2
        )  # logged every pass, paged once

    def test_at_or_above_31_logs_ok_and_never_pages(self) -> None:
        for pri in (31, 37, 46):
            self.assertFalse(self.run_check(pri))
        self.assertEqual(self.pages, [])
        self.assertTrue(all(ln.endswith(" ok") for ln in self.lines()))

    def test_an_unreadable_band_is_unknown_not_low(self) -> None:
        self.assertFalse(self.run_check(None))
        self.assertEqual(self.pages, [])
        self.assertEqual(self.lines(), ["1000 pid=4242 pri=? floor=31 unknown"])

    def test_a_failed_page_is_retried_next_pass(self) -> None:
        def boom(_t: str) -> None:
            raise RuntimeError("no channel")

        self.assertFalse(
            band.check(
                self.log, 1.0, False, boom, store.append_bounded, read=lambda: 20
            )
        )


class DaemonWiring(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.mkdtemp(prefix="lr-band-main-")
        self.addCleanup(shutil.rmtree, self.tmp, True)
        env = mock.patch.dict(
            os.environ,
            {
                "LR_STATE_DIR": os.path.join(self.tmp, "lr"),
                "HOME": os.path.join(self.tmp, "home"),
            },
        )
        env.start()
        self.addCleanup(env.stop)
        self.paths = T.Paths.from_env(root=os.path.join(self.tmp, "lr", "recon"))
        store.ensure_dirs(self.paths)
        self.ctx = M.Ctx(self.paths, None, os.path.join(self.tmp, "home"))
        self.pages: List[str] = []

    def test_the_ctx_tree_is_under_tmp(self) -> None:
        """Ctx's boot-slot store lives under lr_root, not root: from_env(root=tmp) alone left it
        on the live ~/.reso/limit-recover (W1 hermetic lint, the W0b leak class)."""
        for p in (self.paths.lr_root, self.ctx.boots.store):
            self.assertTrue(p.startswith(self.tmp), p)

    def _band(self, mode: str, pri: int) -> None:
        self.ctx.reporter = R.Reporter(self.paths, mode, page=self.pages.append)
        with mock.patch.object(band, "base_priority", return_value=pri):
            M._band(self.ctx, 1000.0)

    def test_act_mode_pages_once_and_records_an_event(self) -> None:
        self._band("act", 20)
        self._band("act", 20)
        self.assertEqual(len(self.pages), 1)
        with open(self.paths.events, encoding="utf-8") as fh:
            self.assertEqual(sum('"band-low"' in ln for ln in fh), 1)
        with open(self.paths.p("band.log"), encoding="utf-8") as fh:
            self.assertEqual(len(fh.read().splitlines()), 2)

    def test_observe_mode_shadows_the_page(self) -> None:
        self._band("observe", 20)
        self.assertEqual(self.pages, [])
        with open(
            os.path.join(self.paths.shadow, "pages.jsonl"), encoding="utf-8"
        ) as fh:
            self.assertIn('"BAND"', fh.read())

    def test_kill_switch(self) -> None:
        with mock.patch.dict(os.environ, {"LR_RECON_BAND_CHECK": "off"}):
            self._band("act", 20)
        self.assertEqual(self.pages, [])
        self.assertFalse(os.path.exists(self.paths.p("band.log")))


if __name__ == "__main__":
    unittest.main()
