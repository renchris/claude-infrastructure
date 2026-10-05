"""W7g: a LIMITED session in a launcher-rooted pane is recovered by R (§C8 R row, §7.2
IMPOSSIBLE-IN-PLACE, invariant 27). Before W7g the census bucketed it LAUNCHER-ROOTED, plan.movers
never offered that substate to --place, act.choose returned None, and a record born with it paged
RECON-DEFECT every pass: in act mode the reconciler never recovered 16 of 25 recorded sessions.

Driven through the pass stages in order (_census -> _derive -> _plan -> act.choose ->
act.may_actuate -> _dispatch -> _invariant) on the W7f world: sid 3a06361f on next4, pane 5:13."""

import os
import unittest
from unittest import mock

from lr_recon import __main__ as M
from lr_recon import act, plan, settle
from lr_recon import types as T
from lr_recon.tests import test_in_place as W

SID, NOW, L = W.SID, W.NOW, W.L


class LauncherRootedTests(unittest.TestCase):
    setUp_world = W.InPlaceTests.setUp
    tearDown = W.InPlaceTests.tearDown
    world = W.InPlaceTests.world
    events = W.InPlaceTests.events

    def setUp(self):
        self.setUp_world()
        # zero-human scope (D1.9): without both markers every census record is PLAN-ONLY
        for p in (self.paths.autorecover_on, self.paths.recon_autorecover_on):
            os.makedirs(os.path.dirname(p), exist_ok=True)
            open(p, "w").close()

    def limited(self, born=True, **kw):
        ctx, snap, rec, facts = self.world(answered=False, **kw)
        if born:
            del ctx.records[SID]  # the census writes the record itself
        return ctx, snap, facts

    def run_pass(self, ctx, snap, facts, dispatch=False):
        buckets, _ = M._census(ctx, snap, facts, [], "act", NOW)
        M._derive(ctx, snap, NOW, facts)
        offer = {SID: T.Placement(acct="next2", weight=1)}
        with (
            mock.patch.object(plan, "place", return_value=(offer, 0)),
            mock.patch.object(plan, "write_plan"),
            mock.patch.object(M, "_cfg_of", return_value=lambda a: "/cfg/" + a),
        ):
            placed = M._plan(ctx, snap, facts, "act", NOW)
        rec = ctx.records[SID]
        res = T.PhaseResult(
            phase=rec.phase, substate=rec.substate, action=ctx.actions.get(SID, "")
        )
        which = act.choose(res, rec)
        may = (
            act.may_actuate(ctx.paths, "act", rec, which, snap, NOW, True, 0, 16)
            if which
            else (False, "nothing chosen")
        )
        spawned = []
        if dispatch:
            with (
                mock.patch.object(M.act, "spawn", return_value=4242) as sp,
                mock.patch.object(M.os, "getloadavg", return_value=(0.0, 0.0, 0.0)),
            ):
                M._dispatch(ctx, snap, "act", NOW)
            spawned = [(c.args[2], c.args[3]) for c in sp.call_args_list]
        return {
            "buckets": [b.name for b in buckets],
            "placed": placed,
            "rec": rec,
            "which": which,
            "may": may,
            "spawned": spawned,
            "defects": M._invariant(ctx, snap, NOW),
        }

    def member(self, snap):
        args = "/x/claude --parent-session-id %s" % SID
        snap.procs[77] = T.ProcRow(77, 1, "S+", L, args)

    # ── the gap: planned, R chosen, dispatched ──────────────────────────────────────────────────

    def test_a_limited_launcher_rooted_session_is_planned_and_replaced(self):
        ctx, snap, facts = self.limited()
        out = self.run_pass(ctx, snap, facts, dispatch=True)
        rec = out["rec"]
        self.assertEqual(out["buckets"], ["LAUNCHER-ROOTED"])
        self.assertEqual((rec.phase, rec.substate), ("PRE-MOVE", "PLANNED"))
        self.assertEqual((out["placed"], rec.target_acct), (1, "next2"))
        self.assertEqual((out["which"], out["may"]), ("R", (True, "ok")))
        self.assertEqual(len(out["spawned"]), 1)
        which, argv = out["spawned"][0]
        self.assertEqual(which, "R")
        # the existing REPLACE inside lr-handoff, onto the placed account, from this pane
        self.assertTrue(argv[1].endswith("lr-handoff.sh"))
        self.assertEqual(argv[argv.index("--target") + 1], "next2")
        self.assertEqual(argv[argv.index("--source-pane") + 1], "13")
        self.assertTrue(rec.submit_token.startswith("lrr-"))
        self.assertEqual(rec.close.get("move_attempt"), rec.attempt)
        self.assertEqual(out["defects"], 0)
        self.assertNotIn("RECON-DEFECT", [e["ev"] for e in self.events()])
        # PANE-GONE's R stays the new-window resume of a dead source
        rec.phase = "PANE-GONE"
        argv = M._command(ctx, rec, "R")
        self.assertTrue(argv[1].endswith("boot-resume-launch.sh"))

    def test_an_old_launcher_rooted_hold_becomes_a_mover(self):
        """A record written before W7g holds substate LAUNCHER-ROOTED with a named wait."""
        ctx, snap, facts = self.limited(born=False)
        out = self.run_pass(ctx, snap, facts)
        self.assertEqual((out["rec"].substate, out["which"]), ("PLANNED", "R"))

    def test_a_record_seen_shell_rooted_takes_the_pane_it_is_in_now(self):
        ctx, snap, facts = self.limited(born=False)
        ctx.records[SID].root_shape = "shell"
        out = self.run_pass(ctx, snap, facts)
        self.assertEqual((out["rec"].root_shape, out["which"]), ("launcher", "R"))

    def test_row_12_re_drives_a_launcher_rooted_move_as_r(self):
        ctx, snap, facts = self.limited(born=False)
        rec = ctx.records[SID]
        res = T.PhaseResult(phase="TRANSPLANTED", action="A")
        self.assertEqual(act.choose(res, rec), "R")
        rec.root_shape = "shell"
        self.assertEqual(act.choose(res, rec), "A")
        rec.root_shape, rec.kind = "launcher", "idle"  # an idle move stays A
        self.assertEqual(act.choose(res, rec), "A")

    # ── what comes before R ─────────────────────────────────────────────────────────────────────

    def test_stay_precedes_r(self):
        ctx, snap, facts = self.limited()
        facts["next4.7d"].resets_at = NOW + 600  # inside the 15-min stay rule
        out = self.run_pass(ctx, snap, facts)
        self.assertEqual(out["buckets"], ["STAY"])
        self.assertEqual((out["rec"].substate, out["which"]), ("WAIT_RESET", None))
        self.assertEqual((out["placed"], out["defects"]), (0, 0))

    def test_a_draft_holds_a_limited_session_before_any_move(self):
        """W7h defect 2: the death path never read the composer, so the lead's limited session
        762a6daa, with unsent text in its prompt, was recorded PLANNED to next2 (2026-10-04)."""
        ctx, snap, facts = self.limited()
        with mock.patch.object(M.observe, "composer_state", return_value="draft"):
            out = self.run_pass(ctx, snap, facts)
        rec = out["rec"]
        self.assertEqual(out["buckets"], ["HOLD-DRAFT"])
        self.assertEqual(
            (rec.substate, rec.target_acct, out["which"]), ("HOLD-DRAFT", "", None)
        )
        self.assertEqual((rec.wait.max_age_s, rec.wait.eta), (900, None))
        self.assertEqual((out["placed"], out["defects"]), (0, 0))
        # sent or cleared: the next pass moves it as before
        with mock.patch.object(M.observe, "composer_state", return_value="empty"):
            out = self.run_pass(ctx, snap, facts)
        self.assertEqual((out["rec"].substate, out["which"]), ("PLANNED", "R"))
        # a draft typed after the plan takes the record back and voids its target
        with mock.patch.object(M.observe, "composer_state", return_value="draft"):
            out = self.run_pass(ctx, snap, facts)
        self.assertEqual(
            (out["rec"].substate, out["rec"].target_acct), ("HOLD-DRAFT", "")
        )

    def test_the_composer_is_not_read_under_a_live_actuator_or_a_reset_wait(self):
        ctx, snap, facts = self.limited(born=False)
        rec = ctx.records[SID]
        with mock.patch.object(M.observe, "composer_state", return_value="draft") as cs:
            rec.substate = "WAIT_RESET"
            M._census(ctx, snap, facts, [], "act", NOW)
            rec.substate = "PLANNED"
            with mock.patch.object(M.act, "live_procs", return_value=[object()]):
                M._census(ctx, snap, facts, [], "act", NOW)
            self.assertEqual(cs.call_count, 0)
            M._census(ctx, snap, facts, [], "act", NOW)
            self.assertEqual((cs.call_count, rec.substate), (1, "HOLD-DRAFT"))

    def _headless(self, snap):
        s = snap.sessions[SID]  # d425afab's shape: a session row is its only holder
        s.pane, s.registry_name = None, ""
        s.holders = [T.HolderObs(pid=10, lstart=L, cfg=self.cfg, src="session-row")]

    def test_a_limited_headless_session_is_an_impossible_member_not_a_silent_drop(self):
        """W7h defect 3: d425afab sat limited for 56 minutes (2026-10-04 07:59:47Z to legacy's
        08:55Z bundle) in the IMPOSSIBLE bucket, which kept no record and logged no event."""
        ctx, snap, facts = self.limited()
        self._headless(snap)
        buckets, _ = M._census(ctx, snap, facts, [], "observe", NOW)
        self.assertEqual(
            [(b.name, b.reason) for b in buckets], [("IMPOSSIBLE", "headless")]
        )
        rec = ctx.records[SID]
        self.assertEqual(
            (rec.terminal.outcome, rec.terminal.proof),
            ("IMPOSSIBLE", "census: headless"),
        )
        self.assertEqual(
            (rec.kind, rec.cohort_id, rec.source_acct),
            ("limited", "next4-7d-1791104400", "next4"),
        )
        # one record and one event per death, however many passes see it
        M._census(ctx, snap, facts, [], "observe", NOW + 5)
        self.assertIs(ctx.records[SID], rec)
        evs = [e for e in self.events() if e["ev"] == "impossible"]
        self.assertEqual([(e["sid"], e["detail"]) for e in evs], [(SID, "headless")])

    def test_an_idle_headless_session_or_an_open_record_is_left_alone(self):
        ctx, snap, _rec, facts = self.world(answered=True)
        del ctx.records[SID]
        self._headless(snap)
        M._census(ctx, snap, facts, [], "observe", NOW)
        self.assertNotIn(
            SID, ctx.records
        )  # not limited: nothing to recover, nothing to page
        ctx, snap, facts = self.limited(born=False)
        self._headless(snap)
        M._census(ctx, snap, facts, [], "observe", NOW)
        self.assertTrue(
            ctx.records[SID].open
        )  # mid-recovery: its phase machine decides
        self.assertNotIn("impossible", [e["ev"] for e in self.events()])

    def test_background_work_precedes_r(self):
        ctx, snap, facts = self.limited()
        snap.sessions[SID].bg_work = [T.BgWork(kind="shell", pid=3)]
        out = self.run_pass(ctx, snap, facts)
        self.assertEqual(out["buckets"], ["HOLD-BGWORK"])
        self.assertEqual((out["rec"].substate, out["which"]), ("HOLD-BGWORK", None))

    def test_a_team_lead_is_held_not_replaced(self):
        ctx, snap, facts = self.limited()
        self.assertEqual(self.run_pass(ctx, snap, facts)["which"], "R")
        rec = ctx.records[SID]
        rec.assign_id = "assign-1"
        self.member(snap)
        # the gate alone, in case a member appears between the census and the dispatch
        self.assertEqual(
            act.may_actuate(ctx.paths, "act", rec, "R", snap, NOW, True, 0, 16),
            (False, "team-live"),
        )
        out = self.run_pass(ctx, snap, facts)
        self.assertEqual(out["buckets"], ["HELD:team"])
        self.assertEqual(
            (rec.substate, rec.target_acct, out["which"]), ("HELD:team", "", None)
        )
        self.unassigned.assert_called_with("assign-1")

    def test_answering_in_place_closes_before_r(self):
        """The W7f shape after W7g planned it: nudged in place, so it closes, and R never runs."""
        ctx, snap, facts = self.limited(born=False)
        out = self.run_pass(ctx, snap, facts)
        rec = out["rec"]
        self.assertEqual(out["which"], "R")
        rec.assign_id = "assign-1"
        tx = snap.sessions[SID].transcript
        tx.last, tx.last_assistant_ok_at = {"kind": "ok"}, W.ANSWER
        facts["next4.7d"].contradicted = True
        out = self.run_pass(ctx, snap, facts, dispatch=True)
        self.assertFalse(rec.open)
        self.assertEqual(
            (rec.terminal.outcome, rec.close.get("via")), ("CLOSED", "IN-PLACE")
        )
        self.assertEqual((out["which"], out["spawned"]), (None, []))
        self.unassigned.assert_called_once_with("assign-1")

    # ── invariant 27: never a duplicate over a live pane ────────────────────────────────────────

    def test_a_live_holder_outside_the_pane_refuses_r(self):
        ctx, snap, facts = self.limited()
        self.assertEqual(self.run_pass(ctx, snap, facts)["may"], (True, "ok"))
        rec, s = ctx.records[SID], snap.sessions[SID]
        target = T.HolderObs(
            pid=11, lstart=L, cfg="/cfg/next2", src="resume-argv", pane=(5, 14)
        )
        for h in (
            target,  # live at the target in another window
            T.HolderObs(  # a background row, even one bound to this very pane
                pid=12, lstart=L, cfg=self.cfg, src="session-row", bg=True, pane=(5, 13)
            ),
            T.HolderObs(
                pid=13, lstart=L, cfg="/cfg/next2", src="resume-argv"
            ),  # pane unknown
        ):
            s.holders = [s.holders[0], h]
            self.assertEqual(
                act.may_actuate(ctx.paths, "act", rec, "R", snap, NOW, True, 0, 16),
                (False, "duplicate-risk"),
                h,
            )
        # PANE-GONE: the source is dead, so any holder at all is a live copy
        rec.phase, s.holders = "PANE-GONE", [target]
        self.assertEqual(
            act.may_actuate(ctx.paths, "act", rec, "R", snap, NOW, True, 0, 16),
            (False, "duplicate-risk"),
        )

    # ── settling R ──────────────────────────────────────────────────────────────────────────────

    def test_a_failed_r_is_retried_never_impossible(self):
        """lr-handoff's REPLACE names its subject ("is launcher-rooted"), which classify reads as
        IMPOSSIBLE: a transient R failure must not end the record there."""
        ctx, snap, facts = self.limited()
        rec = self.run_pass(ctx, snap, facts)["rec"]
        text = (
            "lr-handoff: pane 13 is launcher-rooted (no shell survives its /exit) — REPLACING "
            "in place: successor beside it, then the source is retired\n"
            "!! kitty RPC timed out after 10s\n"
        )
        pr = T.ProcRole(role="actuator", pid=4242, lstart=L, argv_hash="R")
        settle.settle_exit(rec, pr, 1, text, NOW)
        self.assertTrue(rec.open)
        self.assertEqual(rec.last_error.cls, "TRANSIENT")


if __name__ == "__main__":
    unittest.main()
