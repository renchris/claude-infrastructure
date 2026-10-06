"""W7i Q2: a PRE-MOVE record with no holder, plan, wait or eligibility is closed, not paged forever.

The store this replays (2026-10-05): five records in PRE-MOVE with substate null, procs [],
next_eligible_at null, wait null, every source_pid dead, each logged RECON-DEFECT "PRE-MOVE/None"
on every pass (about 1,400 an hour)."""

import json
import os
import tempfile
import time
import unittest
from unittest import mock

from lr_recon import __main__ as M
from lr_recon import facts as F
from lr_recon import plan, settle
from lr_recon import types as T
from lr_recon.tests import test_main as TM

SID = "abcdef01-0000-0000-0000-000000000001"


class HolderGone(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.home = os.path.join(self.tmp, "home")
        os.makedirs(self.home)
        self.env = mock.patch.dict(
            os.environ,
            {"LR_STATE_DIR": os.path.join(self.tmp, "lr"), "HOME": self.home},
        )
        self.env.start()
        self.addCleanup(self.env.stop)
        for target in ("probe", "mint_token"):
            p = mock.patch("lr_recon.admit.Admission." + target, return_value=None)
            p.start()
            self.addCleanup(p.stop)
        self.paths = T.Paths.from_env(root=os.path.join(self.tmp, "lr", "recon"))
        M.store.ensure_dirs(self.paths)
        self.now = time.time()

    def _pass(self, ctx, snap):
        with (
            mock.patch("lr_recon.observe.observe", return_value=snap),
            mock.patch.object(plan, "place", return_value=({}, 0)),
            mock.patch.object(plan, "assign_many", return_value=0),
            mock.patch.object(M.act, "spawn") as spawn,
        ):
            summary = M.run_pass(ctx)
        spawn.assert_not_called()
        return summary

    def _defects(self):
        if not os.path.exists(self.paths.events):
            return []
        with open(self.paths.events, encoding="utf-8") as fh:
            rows = [json.loads(x) for x in fh if x.strip()]
        return [e for e in rows if e.get("ev") == "RECON-DEFECT"]

    def _rec(self, kind="limited"):
        """A stored member: back from SPLIT-BRAIN, so PRE-MOVE with nothing naming its owner."""
        rec = T.Record(
            sid=SID,
            record_id="recon:next3-7d-1:abcdef01:1",
            kind=kind,
            scope="7d",
            source_acct="next3",
            source_cfg="/nonexistent-cfg",
            source_pid=10,
            source_lstart=TM.L,
            pane=(5, 7),
            cohort_id="next3-7d-1",
            origin="fanout" if kind == "idle" else "census",
        )
        rec.substate = None
        rec.timeline.detected = self.now - 3600
        rec.close["seen"] = ["SPLIT-BRAIN", "PRE-MOVE"]
        return rec

    def _gone(self):
        """The census of a pass after the session's process died: no row for the sid at all."""
        snap = TM._snap(self.now, self.tmp)
        snap.sessions = {}
        return snap

    def test_a_holderless_unowned_record_closes_in_one_pass_and_stops_paging(self):
        # the 7d fact is live and uncontradicted, so the idle member is not closed on its fact
        fact = T.Fact(
            acct="next3", scope="7d", resets_at=self.now + 7200, observed_at=self.now
        )
        for kind in ("limited", "idle"):
            with self.subTest(kind=kind):
                F.write_fact(self.paths, fact)
                ctx = M.Ctx(self.paths, None, self.home)
                rec = self._rec(kind)
                ctx.records = {SID: rec}
                summary = self._pass(ctx, self._gone())
                self.assertEqual(summary["defects"], 0)
                self.assertEqual(rec.terminal.outcome, "NOT_NEEDED")
                self.assertIn("dead-before-claim", rec.terminal.proof)
                self.assertEqual(self._pass(ctx, self._gone())["defects"], 0)
                self.assertEqual(self._defects(), [])

    def test_a_live_holder_keeps_todays_behavior(self):
        """Still open, still PRE-MOVE/None, still one RECON-DEFECT a pass: the census owns it."""
        ctx = M.Ctx(self.paths, None, self.home)
        rec = self._rec()
        ctx.records = {SID: rec}
        summary = self._pass(ctx, TM._snap(self.now, self.tmp))
        self.assertTrue(rec.open)
        self.assertEqual((rec.phase, rec.substate), ("PRE-MOVE", None))
        self.assertEqual(summary["defects"], 1)
        self.assertEqual([e["detail"] for e in self._defects()], ["PRE-MOVE/None"])

    def test_anything_that_names_an_owner_keeps_the_record_open(self):
        snap = self._gone()

        def held(**kw):
            rec = self._rec()
            for k, v in kw.items():
                setattr(rec, k, v)
            return rec

        waiting = held(wait=T.Wait(reason="HOLD:iterm", since=self.now))
        named = held(substate="DETECTED")
        eligible = held(next_eligible_at=self.now + 30)
        planned = held()
        planned.timeline.planned = self.now - 5
        busy = held()
        busy.close["busy_at"] = self.now - 5  # a watcher or launcher seen 5 s ago
        for rec in (waiting, named, eligible, planned, busy):
            self.assertEqual(settle.holder_gone(rec, snap, self.now), "")
            self.assertTrue(rec.open)
        # the source process is alive although no session row names the sid this pass
        alive = self._gone()
        alive.procs[10] = T.ProcRow(10, 1, "S+", TM.L, "/x/claude.exe")
        rec = self._rec()
        self.assertEqual(settle.holder_gone(rec, alive, self.now), "")
        self.assertIn("dead-before-claim", settle.holder_gone(rec, snap, self.now))
        self.assertFalse(rec.open)


if __name__ == "__main__":
    unittest.main()
