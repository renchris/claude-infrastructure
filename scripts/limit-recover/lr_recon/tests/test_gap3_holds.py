"""gap-3 E2: a re-probed hold keeps its age across the re-probe cycle and pages at its max age, and
a load hold after the confirm is named as one rather than as a composer hold."""

import unittest

from lr_recon import report, settle
from lr_recon import types as T

T0 = 1_790_000_000.0

PRECHECK_BUSY = """lr-handoff: precheck composer: empty
lr-handoff: precheck verdict: HELD:busy
lr-handoff: PRECHECK HELD:busy — NOTHING has been transplanted, no lock and no tombstone were written.
lr-handoff 4ac4c35d: verdict=NOTMOVED from=next to=next2 proven=no trigger=limit — the precheck refused (rc 6)
"""

LOAD_HELD = (
    "!! recycle ABORTED before /exit (held: load): load 23.1/core over 8/core — /exit NOT "
    "submitted, watcher disarmed, pane lock released, unconfirm rc 0. Re-run: x\n"
)


def rec():
    r = T.Record(
        sid="4ac4c35d-c26e-44c0-9f08-996681462ce0", record_id="recon:c:4ac4c35d:1"
    )
    r.phase, r.substate, r.target_acct = "PRE-MOVE", "PLANNED", "next2"
    return r


def actuator(name="A"):
    return T.ProcRole(role="actuator", pid=4242, lstart="x", argv_hash=name)


class ComposerHoldAges(unittest.TestCase):
    def cycle(self, r, t):
        """One 769b7294 cycle: the precheck holds, the re-probe frees it, the plan places it."""
        settle.settle_exit(r, actuator(), 6, PRECHECK_BUSY, t)
        self.assertEqual(r.substate, "HOLD-COMPOSER")
        self.assertTrue(settle.reprobe(r, t + settle.REPROBE_S))
        r.substate, r.wait = "PLANNED", None  # plan.apply on the next pass

    def test_the_age_survives_reprobe_and_replanning_and_pages(self):
        r = rec()
        for k in range(6):
            self.cycle(r, T0 + k * 150)
        settle.settle_exit(r, actuator(), 6, PRECHECK_BUSY, T0 + 900)
        self.assertEqual(r.wait.since, T0)
        self.assertEqual(report.max_age_deadline(r), T0 + 900)
        self.assertTrue(report.max_age_due(r, T0 + 900))
        self.assertIn("turn in flight", report.say(r))

    def test_a_non_hold_outcome_restarts_the_clock(self):
        r = rec()
        self.cycle(r, T0)
        settle.settle_exit(r, actuator(), 0, "", T0 + 300)  # the move went ahead
        r.phase, r.substate, r.wait = "PRE-MOVE", "PLANNED", None
        settle.settle_exit(r, actuator(), 6, PRECHECK_BUSY, T0 + 2000)
        self.assertEqual(r.wait.since, T0 + 2000)
        self.assertFalse(report.max_age_due(r, T0 + 2000 + 899))


class LoadIsNotAComposerHold(unittest.TestCase):
    def test_a_load_hold_after_the_confirm_is_hold_load(self):
        self.assertEqual(settle._held_after_confirm(LOAD_HELD), "HOLD-LOAD")
        r = rec()
        disp, sub, _ = settle.outcome(r, 1, LOAD_HELD, "A")
        self.assertEqual((disp, sub), ("HOLD", "HOLD-LOAD"))
        settle.settle_exit(r, actuator(), 1, LOAD_HELD, T0)
        self.assertEqual(r.substate, "HOLD-LOAD")
        self.assertIn(r.substate, T.PRE_MOVE_SUBSTATES)
        self.assertEqual(report.max_age_deadline(r), T0 + T.MAX_AGE_S["HOLD-LOAD"])
        self.assertIn("load", report.say(r))

    def test_busy_and_unreachable_stay_composer_holds(self):
        for why in ("busy", "unreachable", "exit-readback"):
            text = LOAD_HELD.replace("(held: load)", "(held: %s)" % why)
            self.assertEqual(settle._held_after_confirm(text), "HOLD-COMPOSER", why)


if __name__ == "__main__":
    unittest.main()
