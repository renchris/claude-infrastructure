"""W7i: a contradicted auth fact admits no idle member, and an idle member it admitted closes.

The store these replay (2026-10-05): facts/next3.auth.json rejected, contradicted, resets_at null,
on an account that was logged in and serving; cohorts/next3-auth-0.json with 19 idle members, five
of them PRE-MOVE/None and paging RECON-DEFECT every pass."""

import json
import os
import tempfile
import time
import unittest
from unittest import mock

from lr_recon import __main__ as M
from lr_recon import census as C
from lr_recon import facts as F
from lr_recon import plan, settle
from lr_recon import types as T
from lr_recon.tests import test_main as TM

SID = "abcdef01-0000-0000-0000-000000000001"


def _auth(now, contradicted=True):
    return T.Fact(
        acct="next3",
        scope="auth",
        resets_at=None,
        observed_at=now - 3600,
        src="census",
        contradicted=contradicted,
    )


def _healthy(snap, now, holders=2, registry_name="p"):
    """The fixture session as a healthy one: its last record is a normal turn, not a limit."""
    s = snap.sessions[SID]
    s.transcript.last = {}
    s.transcript.last_assistant_ok_at = now - 30
    s.registry_name = registry_name
    s.holders = [
        T.HolderObs(pid=10 + i, lstart=TM.L, cfg=s.cfg, src="registry", pane=(5, 7))
        for i in range(holders)
    ]
    return snap


class _Base(unittest.TestCase):
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
            mock.patch.object(M.act, "spawn"),
        ):
            return M.run_pass(ctx)

    def _events(self, name):
        if not os.path.exists(self.paths.events):
            return []
        with open(self.paths.events, encoding="utf-8") as fh:
            rows = [json.loads(x) for x in fh if x.strip()]
        return [e for e in rows if e.get("ev") == name]


class ContradictedAuthAdmitsNoIdleMember(_Base):
    def test_a_healthy_session_on_a_relogged_account_gets_no_record(self):
        """Two holders for one pass (a resume) made it SPLIT-BRAIN, a record type; iTerm2 made it
        HOLD:iterm. Neither is a member of anything on a contradicted auth fact."""
        for kw in ({"holders": 2}, {"holders": 1, "registry_name": "iterm:x"}):
            with self.subTest(**kw):
                F.write_fact(self.paths, _auth(self.now))
                ctx = M.Ctx(self.paths, None, self.home)
                snap = _healthy(TM._snap(self.now, self.tmp), self.now, **kw)
                summary = self._pass(ctx, snap)
                self.assertEqual(ctx.records, {})
                self.assertEqual(summary["open"], 0)
                self.assertEqual(summary["defects"], 0)
                cohorts = os.path.join(self.paths.root, "cohorts")
                listed = os.listdir(cohorts) if os.path.isdir(cohorts) else []
                self.assertEqual([c for c in listed if "auth" in c], [])

    def test_a_closed_record_of_its_own_does_not_readmit_it(self):
        """34ee838d: closed in a 7d cohort two days before, so the census still walked it."""
        F.write_fact(self.paths, _auth(self.now))
        ctx = M.Ctx(self.paths, None, self.home)
        old = T.Record(sid=SID, record_id="recon:next4-7d-1:abcdef01:1")
        old.terminal = T.Terminal(outcome="CLOSED", proof="engaged", at=self.now - 9)
        ctx.records = {SID: old}
        self._pass(ctx, _healthy(TM._snap(self.now, self.tmp), self.now))
        self.assertIs(ctx.records[SID], old)

    def test_an_uncontradicted_7d_fact_still_buckets_an_idle_session(self):
        snap = _healthy(TM._snap(self.now, self.tmp), self.now)
        fact = T.Fact(
            acct="next3", scope="7d", resets_at=self.now + 7200, observed_at=self.now
        )
        facts = {fact.key: fact}
        s = snap.sessions[SID]
        self.assertTrue(C.in_scope(s, facts, self.now))
        self.assertEqual(C.bucket(s, snap, facts, self.now, {}).name, "SPLIT-BRAIN")
        for bad in (_auth(self.now), _auth(self.now, contradicted=False)):
            facts = {bad.key: bad}
            self.assertFalse(C.in_scope(s, facts, self.now))
            self.assertEqual(C.bucket(s, snap, facts, self.now, {}).name, "WORKING")
        facts = {fact.key: T.Fact(**dict(vars(fact), contradicted=True))}
        self.assertEqual(C.bucket(s, snap, facts, self.now, {}).name, "WORKING")

    def test_a_new_limit_is_not_filed_under_a_contradicted_auth_fact(self):
        """Its own 7d death binds, so it has a reset to wake at; a live auth fact still binds."""
        snap = TM._snap(self.now, self.tmp)
        s = snap.sessions[SID]
        fact = _auth(self.now)
        b = C.bucket(s, snap, {fact.key: fact}, self.now, {})
        self.assertEqual((b.scope, b.resets_at), ("7d", self.now + 7200))
        fact = _auth(self.now, contradicted=False)
        b = C.bucket(s, snap, {fact.key: fact}, self.now, {})
        self.assertEqual((b.scope, b.resets_at), ("auth", None))


class AnIdleMemberItsFactCannotMoveCloses(_Base):
    def _rec(self, substate, scope="auth"):
        rec = T.Record(
            sid=SID,
            record_id="recon:next3-%s-0:abcdef01:1" % scope,
            kind="idle",
            scope=scope,
            source_acct="next3",
            source_cfg="/nonexistent-cfg",
            source_pid=10,
            source_lstart=TM.L,
            pane=(5, 7),
            cohort_id="next3-%s-0" % scope,
            origin="fanout",
        )
        rec.substate = substate
        if substate:
            rec.wait = T.Wait(reason=substate, since=self.now - 60)
        rec.timeline.detected = self.now - 60
        return rec

    def test_the_stored_members_close_in_one_pass_and_stop_paging(self):
        """PRE-MOVE/None (5 stored) and HOLD:iterm (14 stored), holder live or not."""
        for substate in (None, "HOLD:iterm"):
            with self.subTest(substate=substate):
                F.write_fact(self.paths, _auth(self.now))
                ctx = M.Ctx(self.paths, None, self.home)
                rec = self._rec(substate)
                ctx.records = {SID: rec}
                snap = _healthy(TM._snap(self.now, self.tmp), self.now, holders=1)
                summary = self._pass(ctx, snap)
                self.assertEqual(rec.terminal.outcome, "NOT_NEEDED")
                self.assertIn("contradicted", rec.terminal.proof)
                self.assertEqual(summary["defects"], 0)
                self.assertEqual(self._pass(ctx, snap)["defects"], 0)
                self.assertEqual(self._events("RECON-DEFECT"), [])

    def test_only_an_idle_record_no_move_began_on(self):
        fact = _auth(self.now)
        facts = {fact.key: fact}
        limited = self._rec("DETECTED")
        limited.kind = "limited"
        planned = self._rec("PLANNED")
        planned.timeline.planned = self.now
        planned.target_acct = "next4"
        live = self._rec("DETECTED", scope="7d")
        ok = T.Fact(acct="next3", scope="7d", resets_at=self.now + 7200)
        for rec in (limited, planned):
            self.assertEqual(settle.idle_unneeded(rec, facts, self.now), "")
            self.assertTrue(rec.open)
        self.assertEqual(settle.idle_unneeded(live, {ok.key: ok}, self.now), "")
        self.assertEqual(settle.idle_unneeded(live, None, self.now), "")
        self.assertIn("gone", settle.idle_unneeded(live, {}, self.now))


if __name__ == "__main__":
    unittest.main()
