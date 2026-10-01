"""W7f: a limited session that answers again on its SOURCE (nudged in place, the limit
contradicted) leaves the limited path. W5b2 2026-10-01: 3a06361f/46bc0436 on next4 answered at
21:29Z/21:30Z and the reconciler still held them PRE-MOVE/LAUNCHER-ROOTED, records born
LAUNCHER-ROOTED paged RECON-DEFECT every pass, and the DETECTED variant of the same shape was
planned and chosen for A, an /exit and relaunch of a working session.

Driven through the pass stages in order: _census -> _derive -> _plan -> act.choose ->
act.may_actuate -> _invariant."""

import json
import os
import tempfile
import unittest
from unittest import mock

from lr_recon import __main__ as M
from lr_recon import act, plan, settle
from lr_recon import types as T

L = "Thu Oct 1 18:38:57 2026"
SID = "3a06361f-b508-4002-ad3b-e4b476c8c209"
DETECTED, NOW = 1790885780.0, 1790891200.0
ANSWER = 1790890183.0  # 21:29:43Z, the fresh turn after the in-place nudge


class InPlaceTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.env = mock.patch.dict(
            os.environ, {"LR_STATE_DIR": os.path.join(self.tmp, "lr"), "HOME": self.tmp}
        )
        self.env.start()
        self.paths = T.Paths.from_env(root=os.path.join(self.tmp, "lr", "recon"))
        M.store.ensure_dirs(self.paths)
        open(self.paths.recon_on, "w").close()
        self.cfg = os.path.join(self.tmp, "cfg-next4")
        os.makedirs(os.path.join(self.cfg, "projects"))
        self.unassign = mock.patch.object(plan, "unassign", return_value=0)
        self.unassigned = self.unassign.start()

    def tearDown(self):
        self.unassign.stop()
        self.env.stop()

    def world(
        self, substate="LAUNCHER-ROOTED", shape="launcher", answered=True, wait=True
    ):
        tx = os.path.join(self.tmp, "t.jsonl")
        open(tx, "a").close()
        last = (
            {"kind": "ok"}
            if answered
            else {
                "limit": True,
                "kind": "limit",
                "cap": "seven_day",
                "resets_at": 1791104400.0,
            }
        )
        s = T.SessionObs(
            sid=SID,
            acct="next4",
            cfg=self.cfg,
            pid=10,
            lstart=L,
            cwd=self.tmp,
            pane=(5, 13),
            registry_name="p",
            holders=[
                T.HolderObs(
                    pid=10, lstart=L, cfg=self.cfg, src="registry", pane=(5, 13)
                )
            ],
            transcript=T.TranscriptObs(
                path=tx,
                at_rest=True,
                last=last,
                last_assistant_ok_at=ANSWER if answered else DETECTED - 600,
            ),
        )
        pane = T.PaneObs(
            kitty_pid=5,
            window_id=13,
            sock="unix:/tmp/k",
            root_pid=20,
            root_lstart=L,
            root_shape=shape,
            state="claude",
        )
        snap = T.Snapshot(
            wall=NOW,
            uptime_raw=0.0,
            procs={99: T.ProcRow(99, 1, "S+", L, "/x/claude.exe")},
            panes={"5:13": pane},
            sessions={SID: s},
        )
        rec = T.Record(
            sid=SID,
            record_id="recon:next4-7d-1791104400:3a06361f:1",
            kind="limited",
            scope="7d",
            pane=(5, 13),
            source_acct="next4",
            source_cfg=self.cfg,
            cwd=self.tmp,
            cohort_id="next4-7d-1791104400",
            origin="census",
            phase="PRE-MOVE",
            substate=substate,
            root_shape=shape,
        )
        rec.timeline.detected = DETECTED
        rec.close["death"] = "u@2026-10-01T20:16:19.679Z"
        if wait:
            rec.wait = T.Wait(reason=substate, since=DETECTED)
        ctx = M.Ctx(self.paths, None, self.tmp)
        ctx.records[SID] = rec
        fact = T.Fact(
            acct="next4",
            scope="7d",
            resets_at=1791104400.0,
            observed_at=1790884745.0,
            contradicted=answered,
        )
        return ctx, snap, rec, {"next4.7d": fact}

    def run_pass(self, ctx, snap, facts):
        """census -> derive -> plan (a placement on offer) -> choose/may_actuate -> invariant."""
        rec = ctx.records[SID]
        buckets, _ = M._census(ctx, snap, facts, [], "act", NOW)
        M._derive(ctx, snap, NOW, facts)
        offer = {SID: T.Placement(acct="next2", weight=1)}
        with (
            mock.patch.object(plan, "place", return_value=(offer, 0)),
            mock.patch.object(plan, "write_plan"),
            mock.patch.object(M, "_cfg_of", return_value=lambda a: "/cfg/" + a),
        ):
            placed = M._plan(ctx, snap, facts, "act", NOW)
        res = T.PhaseResult(
            phase=rec.phase, substate=rec.substate, action=ctx.actions.get(SID, "")
        )
        which = act.choose(res, rec)
        may = (
            act.may_actuate(ctx.paths, "act", rec, which, snap, NOW, True, 0, 16)
            if which
            else (False, "nothing chosen")
        )
        defects = M._invariant(ctx, snap, NOW)
        return {
            "buckets": [b.name for b in buckets],
            "placed": placed,
            "which": which,
            "may": may,
            "defects": defects,
        }

    def events(self):
        if not os.path.exists(self.paths.events):
            return []
        with open(self.paths.events, encoding="utf-8") as fh:
            return [json.loads(x) for x in fh]

    def assert_closed_in_place(self, rec, out):
        self.assertFalse(rec.open)
        self.assertEqual(rec.terminal.outcome, "CLOSED")
        self.assertEqual(rec.close.get("via"), "IN-PLACE")
        self.assertTrue(rec.close.get("same_window"))
        self.assertEqual((out["placed"], out["which"], out["defects"]), (0, None, 0))
        evs = [e["ev"] for e in self.events()]
        self.assertIn("engaged-in-place", evs)
        self.assertNotIn("RECON-DEFECT", evs)

    # ── the W5b2 shapes ─────────────────────────────────────────────────────────────────────────

    def test_a_launcher_rooted_hold_answered_in_place_closes(self):
        ctx, snap, rec, facts = self.world()
        out = self.run_pass(ctx, snap, facts)
        self.assertEqual(out["buckets"], ["WORKING"])
        self.assert_closed_in_place(rec, out)
        self.assertIn("answered in place on next4", rec.terminal.proof)

    def test_a_record_born_launcher_rooted_without_a_wait_is_no_defect(self):
        """The live flood: census.new_record gives LAUNCHER-ROOTED no wait, so §4.4 paged it."""
        ctx, snap, rec, facts = self.world(wait=False)
        self.assert_closed_in_place(rec, self.run_pass(ctx, snap, facts))

    def test_the_detected_variant_is_never_planned_or_replaced(self):
        """Before W7f this record was placed on next2 and act.choose returned A (may_actuate ok)."""
        ctx, snap, rec, facts = self.world(
            substate="DETECTED", shape="shell", wait=False
        )
        out = self.run_pass(ctx, snap, facts)
        self.assert_closed_in_place(rec, out)
        self.assertFalse(rec.target_acct)

    def test_a_planned_record_answered_in_place_voids_its_phantom(self):
        ctx, snap, rec, facts = self.world(
            substate="PLANNED", shape="shell", wait=False
        )
        rec.target_acct, rec.assign_id = "next2", "assign-1"
        out = self.run_pass(ctx, snap, facts)
        self.assert_closed_in_place(rec, out)
        self.unassigned.assert_called_once_with("assign-1")

    def test_a_closed_in_place_record_is_not_re_recorded_next_pass(self):
        ctx, snap, rec, facts = self.world()
        self.run_pass(ctx, snap, facts)
        out = self.run_pass(ctx, snap, facts)
        self.assertIs(ctx.records[SID], rec)
        self.assertFalse(rec.open)
        self.assertEqual(out["buckets"], ["WORKING"])
        self.assertEqual((out["placed"], out["which"], out["defects"]), (0, None, 0))
        evs = [e["ev"] for e in self.events()]
        self.assertEqual(
            evs.count("engaged-in-place"), 1
        )  # closed once, never re-opened

    # ── controls: what must NOT close ───────────────────────────────────────────────────────────

    def test_control_a_real_limit_on_a_launcher_rooted_pane_stays_open(self):
        """No fresh turn: the census still buckets it LAUNCHER-ROOTED (=> R), the record stays open.
        W7g: it is a mover now (DETECTED; PLAN-ONLY here, so not placed), never a held substate."""
        ctx, snap, rec, facts = self.world(answered=False)
        out = self.run_pass(ctx, snap, facts)
        self.assertEqual(out["buckets"], ["LAUNCHER-ROOTED"])
        self.assertTrue(rec.open)
        self.assertEqual((rec.phase, rec.substate), ("PRE-MOVE", "DETECTED"))
        self.assertNotIn("engaged-in-place", [e["ev"] for e in self.events()])

    def test_control_a_turn_before_detection_does_not_close(self):
        ctx, snap, rec, facts = self.world()
        snap.sessions[SID].transcript.last_assistant_ok_at = DETECTED - 1
        self.assertEqual(settle.engaged_elsewhere(rec, snap, NOW), "")
        self.assertTrue(rec.open)

    def _guarded(self, mutate):
        ctx, snap, rec, facts = self.world(
            substate="DETECTED", shape="shell", wait=False
        )
        mutate(rec)
        self.assertEqual(settle.engaged_elsewhere(rec, snap, NOW), "")
        self.assertTrue(rec.open)

    def test_control_an_idle_record_is_not_closed_in_place(self):
        self._guarded(lambda r: setattr(r, "kind", "idle"))

    def test_control_past_pre_move_the_phase_table_owns_it(self):
        self._guarded(lambda r: setattr(r, "phase", "TRANSPLANTED"))

    def test_control_an_in_flight_relaunch_is_not_closed_in_place(self):
        self._guarded(lambda r: setattr(r, "substate", "IN-FLIGHT"))

    def test_control_a_confirmed_transplant_is_not_closed_in_place(self):
        self._guarded(lambda r: setattr(r.timeline, "confirmed", DETECTED + 1))

    def test_control_a_typed_exit_is_not_closed_in_place(self):
        self._guarded(lambda r: setattr(r.timeline, "exit_typed_by_me", DETECTED + 1))


if __name__ == "__main__":
    unittest.main()
