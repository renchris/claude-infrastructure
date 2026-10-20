"""A move that rolled back after its transplant began is re-offered as a counted retry.

The store this replays (2026-10-20, db755a94): R transplanted to next4, the recycle stood down
(HELD:unreachable, the terminal did not answer the pane probe), the admit was aborted and lr-handoff
closed "verdict=NOTMOVED … a retry is safe". The R was reaped with no exit code ("the phase
decides"), the phase table derived PRE-MOVE with substate None, and RECON-DEFECT PRE-MOVE/None was
logged every pass with nothing acting: movers() takes no substate None, and timeline.planned plus
target_acct keep holder_gone off it."""

import json
import os
import shutil
import tempfile
import time
import unittest
from unittest import mock

from lr_recon import __main__ as M
from lr_recon import plan, settle
from lr_recon import types as T
from lr_recon.tests import test_main as TM

SID = "abcdef01-0000-0000-0000-000000000001"

# the actlog's closing lines, as db755a94.1.R.log ended them
ROLLED_BACK = """lr-handoff: transplant ok -> /x/.claude-quaternary/projects/-p/abcdef01.jsonl
lr-handoff abcdef01: verdict=SWITCHED-UNPROVEN from=next3 to=next4 proven=no trigger=limit — armed: the transplant is done and the recycle is firing on pane 7
!! recycle ABORTED: the terminal did not answer the watcher's pane probe for 7 (a failed listing, typically the 10 s bound firing while kitty's socket is stalled) — that is NOT a missing pane. /exit NOT typed, session stays alive.
lr-handoff: verdict: HELD:unreachable — the recycle stood down before any confirm (handoff-fire rc=1); lr-transplant --phase abort rc 0 withdrew the admit
lr-handoff abcdef01: verdict=NOTMOVED from=next3 to=next4 proven=no trigger=limit — HELD:unreachable before the confirm — the admit is aborted (tombstone, lock and target copy withdrawn); the source was never retired and the session is alive in pane 7; a retry is safe
lr-handoff: owed recycle row for pane 7 spent (the move lane settled this hold itself)
"""


class RolledBack(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp, True)
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

    def _rec(self):
        """The stranded shape: PRE-MOVE/None, planned onto next4, nothing confirmed, no procs."""
        rec = T.Record(
            sid=SID,
            record_id="recon:next3-7d-1:abcdef01:1",
            kind="limited",
            scope="7d",
            source_acct="next3",
            source_cfg="/nonexistent-cfg",
            source_pid=10,
            source_lstart=TM.L,
            pane=(5, 7),
            cohort_id="next3-7d-1",
            origin="cc-lr",
            target_acct="next4",
            target_cfg="/nonexistent-target",
        )
        rec.substate = None
        rec.timeline.detected = self.now - 3600
        rec.timeline.planned = self.now - 3300
        rec.close["seen"] = ["PRE-MOVE", "DETECTED", "PLANNED", "TRANSPLANTED"]
        rec.close["busy_at"] = self.now - 1800
        return rec

    def _log(self, rec, text=ROLLED_BACK, actuator="R"):
        os.makedirs(self.paths.p("actlogs"), exist_ok=True)
        with open(settle.actlog(self.paths, rec, actuator), "w") as fh:
            fh.write(text)

    def _pass(self, ctx):
        with (
            mock.patch(
                "lr_recon.observe.observe", return_value=TM._snap(self.now, self.tmp)
            ),
            mock.patch.object(plan, "place", return_value=({}, 0)),
            mock.patch.object(plan, "assign_many", return_value=0),
            mock.patch.object(M.act, "spawn") as spawn,
        ):
            summary = M.run_pass(ctx)
        spawn.assert_not_called()
        return summary

    def _events(self, ev):
        if not os.path.exists(self.paths.events):
            return []
        with open(self.paths.events, encoding="utf-8") as fh:
            rows = [json.loads(x) for x in fh if x.strip()]
        return [e for e in rows if e.get("ev") == ev]

    def test_a_stranded_rollback_is_re_driven_on_the_next_pass(self):
        """Red before the fix: the record stayed PRE-MOVE/None and paged RECON-DEFECT."""
        ctx = M.Ctx(self.paths, None, self.home)
        rec = self._rec()
        self._log(rec)
        ctx.records = {SID: rec}
        summary = self._pass(ctx)
        self.assertEqual(summary["defects"], 0)
        self.assertEqual(self._events("RECON-DEFECT"), [])
        self.assertTrue(rec.open)
        self.assertEqual(
            rec.attempt, 2
        )  # the R spawned under attempt 1; the retry is a new one
        self.assertIsNotNone(rec.substate)
        # HELD:unreachable is TRANSIENT (lr-sustained-load REPORT §4 A3 ii): a deaf terminal retries
        self.assertEqual(rec.last_error.cls, "TRANSIENT")
        [ev] = self._events("rolled-back")
        self.assertIn("R rc=None → BACKOFF", ev["detail"])
        self.assertEqual(rec.last_error.detail, "unreachable")

    def test_the_rolled_back_record_is_a_mover_again(self):
        rec = self._rec()
        self._log(rec)
        self.assertEqual(plan.movers([rec], TM._snap(self.now, self.tmp), self.now), [])
        self.assertIn("BACKOFF/BACKOFF", settle.rolled_back(self.paths, rec, self.now))
        self.assertEqual(rec.substate, "BACKOFF")
        self.assertGreater(rec.next_eligible_at, self.now)
        [m] = plan.movers([rec], TM._snap(self.now, self.tmp), self.now)
        self.assertEqual(m.sid, SID)

    def test_repeated_rollbacks_escalate_through_the_existing_budget(self):
        # a hold that is still DETERMINISTIC (load: A3 iii keeps it out of TRANSIENT)
        held_load = ROLLED_BACK.replace("HELD:unreachable", "HELD:load")
        rec = self._rec()
        self._log(rec, held_load)
        settle.rolled_back(self.paths, rec, self.now)
        # the retry rolls back the same way under attempt 2
        rec.substate, rec.next_eligible_at = None, None
        self._log(rec, held_load)
        self.assertIn("ESCALATED", settle.rolled_back(self.paths, rec, self.now + 60))
        self.assertTrue(rec.escalated)
        self.assertEqual(rec.attempt, 3)

    def test_repeated_unreachable_rollbacks_back_off_and_never_escalate(self):
        """A3 ii: the same deaf-terminal rollback, twice, is a backoff, not ESCALATED → IMPOSSIBLE."""
        rec = self._rec()
        self._log(rec)
        settle.rolled_back(self.paths, rec, self.now)
        rec.substate, rec.next_eligible_at = None, None
        self._log(rec)
        self.assertIn("BACKOFF", settle.rolled_back(self.paths, rec, self.now + 60))
        self.assertFalse(rec.escalated)
        self.assertEqual(rec.last_error.cls, "TRANSIENT")

    def test_an_unknown_code_R_exit_reads_its_notmoved_verdict(self):
        """The fast path: the exit is reaped while the record already derives PRE-MOVE."""
        rec = self._rec()
        r = T.ProcRole(role="actuator", pid=7, lstart="x", argv_hash="R")
        d = settle.settle_exit(rec, r, None, ROLLED_BACK, self.now)
        self.assertNotIn("code unknown", d)
        self.assertEqual((rec.substate, rec.attempt), ("BACKOFF", 2))

    def test_without_a_notmoved_verdict_nothing_is_scored(self):
        """The control: no log, a move that verified, a live owner, or a confirmed transplant."""
        r = T.ProcRole(role="actuator", pid=7, lstart="x", argv_hash="R")
        self.assertIn(
            "code unknown",
            settle.settle_exit(
                self._rec(),
                r,
                None,
                ROLLED_BACK.rsplit("lr-handoff abcdef01: verdict=NOTMOVED", 1)[0],
                self.now,
            ),
        )
        bare = self._rec()
        self.assertEqual(settle.rolled_back(self.paths, bare, self.now), "")
        cases = {
            "busy": dict(close_busy=self.now - 5),
            "eligible": dict(next_eligible_at=self.now + 30),
            "named": dict(substate="DETECTED"),
            "escalated": dict(escalated=True),
        }
        for name, kw in cases.items():
            with self.subTest(name):
                rec = self._rec()
                self._log(rec)
                busy = kw.pop("close_busy", None)
                if busy:
                    rec.close["busy_at"] = busy
                for k, v in kw.items():
                    setattr(rec, k, v)
                self.assertEqual(settle.rolled_back(self.paths, rec, self.now), "")
                self.assertEqual(rec.attempt, 1)
        confirmed = self._rec()
        self._log(confirmed)
        confirmed.timeline.confirmed = self.now - 100
        self.assertEqual(settle.rolled_back(self.paths, confirmed, self.now), "")


if __name__ == "__main__":
    unittest.main()
