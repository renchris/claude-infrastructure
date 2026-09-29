"""settle.py: actuator exits reach the record, holds can clear, confirm_len comes from the tombstone.

Each case is a shape the W5 rig produced on its first act-mode runs."""

import json
import os
import shutil
import tempfile
import unittest

from lr_recon import settle
from lr_recon import types as T

PRECHECK_HELD = """lr-handoff: precheck composer: %s
lr-handoff: precheck verdict: HELD:%s
lr-handoff: PRECHECK HELD:%s — NOTHING has been transplanted, no lock and no tombstone were written.
lr-handoff 4ac4c35d: verdict=NOTMOVED from=next to=next2 proven=no trigger=limit — the precheck refused (rc 6)
"""


def rec(phase="PRE-MOVE", sub="PLANNED"):
    r = T.Record(
        sid="4ac4c35d-c26e-44c0-9f08-996681462ce0", record_id="recon:c:4ac4c35d:1"
    )
    r.phase, r.substate, r.target_acct = phase, sub, "next2"
    return r


def actuator(name="A"):
    return T.ProcRole(role="actuator", pid=4242, lstart="x", argv_hash=name)


class Exits(unittest.TestCase):
    def test_unreadable_composer_backs_off_instead_of_respawning(self):
        r = rec()
        d = settle.settle_exit(
            r,
            actuator(),
            6,
            PRECHECK_HELD
            % ("unreadable", "composer-unreadable", "composer-unreadable"),
            100.0,
        )
        self.assertIn("BACKOFF", d)
        self.assertEqual(r.substate, "BACKOFF")
        self.assertEqual(r.next_eligible_at, 110.0)
        self.assertEqual(r.last_error.cls, "TRANSIENT")

    def test_draft_holds_and_is_reprobed_later(self):
        r = rec()
        settle.settle_exit(
            r, actuator(), 6, PRECHECK_HELD % ("held:x", "draft", "draft"), 100.0
        )
        self.assertEqual((r.substate, r.last_error.cls), ("HOLD-DRAFT", "HOLD"))
        self.assertFalse(settle.reprobe(r, 100.0 + settle.REPROBE_S - 1))
        self.assertTrue(settle.reprobe(r, 100.0 + settle.REPROBE_S))
        self.assertEqual((r.substate, r.wait), ("DETECTED", None))

    def test_a_successful_move_is_never_dispatched_again_in_the_relaunch_gap(self):
        """W5 rig: after A returned 0 the gap (source dead, target not up) derived PRE-MOVE, the
        record still read PLANNED, and a SECOND A ran over the transplanted session."""
        from lr_recon import act

        r = rec()
        self.assertEqual(settle.settle_exit(r, actuator(), 0, "", 1.0), "A rc=0")
        self.assertEqual((r.substate, r.last_error, r.attempt), ("IN-FLIGHT", None, 1))
        gap = T.PhaseResult(phase="PRE-MOVE", substate=None, action="plan")
        self.assertIsNone(act.choose(gap, r))

    def test_a_confirmed_transplant_is_in_flight_even_before_A_exits(self):
        from lr_recon import act

        r = rec()
        self.assertFalse(settle.mark_in_flight(r))  # no tombstone read yet: still PLANNED
        r.confirm_len = 10
        self.assertTrue(settle.mark_in_flight(r))
        self.assertIsNone(act.choose(T.PhaseResult(phase="PRE-MOVE"), r))

    def test_a_failed_move_makes_its_retry_a_new_attempt(self):
        r = rec()
        settle.settle_exit(r, actuator(), 6, PRECHECK_HELD % ("x", "draft", "draft"), 1.0)
        self.assertEqual(r.attempt, 2)
        settle.settle_exit(r, actuator("C"), 1, "cc_tui_submit mangled", 2.0)
        self.assertEqual(r.attempt, 2)  # an engage is not a move

    def test_hop_moves_from_the_failed_target_as_a_new_attempt(self):
        r = rec(phase="TARGET-LIMITED", sub=None)
        r.source_acct, r.source_cfg, r.target_cfg, r.confirm_len = "next", "/c/a", "/c/b", 99
        r.submit_token = "lrr-1"
        h = T.HolderObs(pid=77, lstart="L", cfg="/c/b", src="session-row", pane=(1, 2))
        settle.new_attempt(r, h, "limit", 5.0)
        self.assertEqual((r.source_acct, r.source_cfg, r.source_pid), ("next2", "/c/b", 77))
        self.assertEqual((r.target_acct, r.confirm_len, r.submit_token), ("", None, ""))
        self.assertEqual((r.phase, r.substate, r.attempt), ("PRE-MOVE", "DETECTED", 2))
        self.assertEqual((r.close["hop"], r.close["hops"]), ("limit", 1))

    def test_not_limited_on_a_hop_waits_instead_of_closing(self):
        r = rec()
        r.close["hop"] = "auth"
        settle.settle_exit(r, actuator(), 6, "lr-handoff: PRECHECK REFUSED:not-limited — x", 5.0)
        self.assertIsNone(r.terminal)
        self.assertEqual(r.substate, "WAIT_SLOT")

    def test_unknown_exit_code_is_no_verdict(self):
        r = rec(phase="RELAUNCHED", sub="UNPROMPTED")
        pr = T.ProcRole(role="actuator", pid=7, lstart="x", argv_hash="adopted")
        for _ in range(3):  # twice used to ESCALATE: two "identical DETERMINISTIC" rc=-1 exits
            self.assertIn("code unknown", settle.settle_exit(r, pr, None, "", 1.0))
        self.assertEqual((r.escalated, r.last_error), (False, None))

    def test_a_watcher_exit_is_not_an_actuator_verdict(self):
        r = rec()
        w = T.ProcRole(role="watcher", pid=1, lstart="x")
        self.assertEqual(settle.settle_exit(r, w, 1, "draft", 1.0), "")

    def test_after_the_move_a_hold_marks_last_error_and_leaves_the_phase_to_derive(
        self,
    ):
        r = rec(phase="HUSK-RETIRED", sub="no-stub")
        settle.settle_exit(
            r,
            actuator(),
            1,
            "recycle: background work is running — answered cancel",
            5.0,
        )
        self.assertEqual(r.last_error.cls, "HOLD")
        self.assertEqual(r.substate, "no-stub")

    def test_not_limited_is_not_needed(self):
        r = rec()
        settle.settle_exit(
            r,
            actuator(),
            6,
            "lr-handoff: PRECHECK REFUSED:not-limited — nothing done",
            5.0,
        )
        self.assertEqual(r.terminal.outcome, "NOT_NEEDED")

    def test_dead_actuators_pairs_exit_codes_once(self):
        ex = {4242: 6}
        got = settle.dead_actuators(
            [actuator(), T.ProcRole(role="watcher", pid=9, lstart="")], ex
        )
        self.assertEqual([(p.pid, rc) for p, rc in got], [(4242, 6)])
        self.assertEqual(ex, {})


class Rebucket(unittest.TestCase):
    def test_bgwork_clears_when_the_census_sees_limited_again(self):
        r = rec(sub="HOLD-BGWORK")
        self.assertTrue(settle.rebucket(r, "LIMITED", 1.0))
        self.assertEqual(r.substate, "DETECTED")

    def test_focus_becomes_bgwork_and_keeps_waiting(self):
        r = rec(sub="HOLD-FOCUS")
        self.assertTrue(settle.rebucket(r, "HOLD-BGWORK", 1.0))
        self.assertEqual((r.substate, r.wait.reason), ("HOLD-BGWORK", "HOLD-BGWORK"))

    def test_planned_and_moving_records_are_not_the_census_s(self):
        self.assertFalse(settle.rebucket(rec(sub="PLANNED"), "HOLD-BGWORK", 1.0))
        self.assertFalse(
            settle.rebucket(rec(phase="EXITING", sub="HOLD-BGWORK"), "LIMITED", 1.0)
        )
        self.assertFalse(settle.rebucket(rec(sub="HOLD-DRAFT"), "LIMITED", 1.0))


class Confirm(unittest.TestCase):
    def setUp(self):
        self.cfg = tempfile.mkdtemp()

    def tearDown(self):
        shutil.rmtree(self.cfg)

    def test_confirm_len_is_read_from_the_tombstone_once(self):
        r = rec(phase="EXITING")
        r.source_cfg, r.cwd = self.cfg, "/w/x"
        d = os.path.join(self.cfg, "projects", "-w-x")
        os.makedirs(d)
        with open(os.path.join(d, r.sid + ".jsonl.handed-off"), "w") as fh:
            fh.write("{}\n")
        with open(os.path.join(d, r.sid + ".HANDOFF.json"), "w") as fh:
            json.dump({"handed_off_to": "x", "confirm_len": 4096}, fh)
        self.assertTrue(settle.note_confirm(r))
        self.assertEqual(r.confirm_len, 4096)
        self.assertIsNotNone(r.timeline.confirmed)
        self.assertFalse(settle.note_confirm(r))

    def test_no_tombstone_leaves_it_unknown(self):
        r = rec()
        r.source_cfg, r.cwd = self.cfg, "/w/x"
        self.assertFalse(settle.note_confirm(r))
        self.assertIsNone(r.confirm_len)


if __name__ == "__main__":
    unittest.main()
