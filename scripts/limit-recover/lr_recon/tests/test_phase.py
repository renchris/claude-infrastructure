"""derive_phase ordering cases (§4.2 + W0 findings b and d) and the fixture CLI."""

import io
import os
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from typing import Any

from lr_recon import phase
from lr_recon import types as T

FIXTURES = os.path.join(
    os.path.dirname(os.path.realpath(__file__)),
    "..",
    "..",
    "..",
    "..",
    "tests",
    "fixtures",
    "lr-recon",
)


def _ev(**kw: Any) -> T.Evidence:
    ev: T.Evidence = T.from_dict(T.Evidence, kw)
    return ev


TARGET = {"cfg": "target", "pane_bound": True}
# 849-b, the real ENGAGED shape every ordering case perturbs one field of.
ENGAGED = dict(
    kind="limited",
    holders=[TARGET],
    source_alive=False,
    handed_off=True,
    live_watcher=True,
    submitted=True,
    target_last_assistant="ok",
    token_record_offset=1971660,
    token_is_this_attempt=True,
    confirm_len=1903646,
    nonerror_assistant_after_token=True,
    relaunch_substate="SUBMITTED",
)


def _with(**kw: Any) -> T.Evidence:
    base = dict(ENGAGED)
    base.update(kw)
    return _ev(**base)


class DerivePhaseOrder(unittest.TestCase):
    def test_engaged_baseline(self) -> None:
        res = phase.derive_phase(_with())
        self.assertEqual((res.phase, res.action), ("ENGAGED", "sentinel"))
        self.assertTrue(res.reason.startswith("row5:"))

    def test_split_brain_beats_engaged(self) -> None:
        bg = {"cfg": "source", "bg": True, "role": "bg-row"}
        res = phase.derive_phase(_with(holders=[TARGET, bg]))
        self.assertEqual((res.phase, res.action), ("SPLIT-BRAIN", "SPLIT"))
        other = phase.derive_phase(_with(holders=[TARGET, {"cfg": "other"}]))
        self.assertEqual((other.phase, other.action), ("SPLIT-BRAIN", "page"))

    def test_exiting_when_watcher_live_and_source_alive(self) -> None:
        """The fatal misread: a live source under a live watcher is mid-exit, never a husk."""
        ev = _ev(
            holders=[{"cfg": "source", "pane_bound": True}],
            source_alive=True,
            source_at_composer=True,
            handed_off=True,
            live_watcher=True,
            source_retired=True,
            lock_names_target=True,
        )
        self.assertEqual(phase.derive_phase(ev).phase, "EXITING")
        ev.live_watcher = False
        self.assertEqual(phase.derive_phase(ev).phase, "HUSK-RETIRED")

    def test_notification_turn_never_engaged(self) -> None:
        res = phase.derive_phase(
            _with(
                target_last_assistant="notification",
                nonerror_assistant_after_token=False,
            )
        )
        self.assertEqual((res.phase, res.substate), ("RELAUNCHED", "SUBMITTED"))

    def test_offset_must_lie_past_the_confirmed_copy(self) -> None:
        # A record STARTING inside the confirmed bytes is a replay of the source: not engaged.
        for off in (1903645, 1000):
            self.assertEqual(
                phase.derive_phase(_with(token_record_offset=off)).phase, "RELAUNCHED"
            )
        # W5 rig: the first append after the transplant starts AT confirm_len — that IS past it.
        self.assertEqual(
            phase.derive_phase(_with(token_record_offset=1903646)).phase, "ENGAGED"
        )

    def test_confirm_len_none_not_engaged(self) -> None:
        res = phase.derive_phase(_with(confirm_len=None))
        self.assertEqual(res.phase, "RELAUNCHED")
        self.assertIn("offset-unknown", res.reason)

    def test_source_alive_not_engaged(self) -> None:
        self.assertNotEqual(
            phase.derive_phase(_with(source_alive=True)).phase, "ENGAGED"
        )

    def test_target_rows_precede_engaged(self) -> None:
        self.assertEqual(
            phase.derive_phase(_with(target_last_assistant="limit")).phase,
            "TARGET-LIMITED",
        )
        self.assertEqual(
            phase.derive_phase(
                _with(target_last_assistant="authentication_failed")
            ).phase,
            "TARGET-AUTH",
        )
        res = phase.derive_phase(_with(target_last_assistant="network"))
        self.assertEqual((res.phase, res.action), ("TARGET-TRANSIENT", "C-retry"))

    def test_parked_menu_is_hold_menu_even_with_bound_holder(self) -> None:
        for kind in ("idle", "limited"):
            res = phase.derive_phase(
                _ev(
                    kind=kind,
                    holders=[TARGET],
                    readiness="parked-menu",
                    holder_stable_two_samples=True,
                )
            )
            self.assertEqual((res.phase, res.substate), ("PRE-MOVE", "HOLD-MENU"), kind)

    def test_moved_needs_stability_and_readiness(self) -> None:
        ev = _ev(
            kind="idle",
            holders=[TARGET],
            holder_stable_two_samples=True,
            readiness="READY",
        )
        self.assertEqual(phase.derive_phase(ev).phase, "MOVED")
        ev.holder_stable_two_samples = False
        res = phase.derive_phase(ev)
        self.assertEqual((res.phase, res.substate), ("RELAUNCHED", "UNPROMPTED"))

    def test_gap_b_is_pre_move(self) -> None:
        """W0 (b): handed-off, dead source, live watcher, empty H — no table row; PRE-MOVE."""
        ev = _ev(
            holders=[],
            source_alive=False,
            handed_off=True,
            live_watcher=True,
            pane_state="shell",
            identity_match=True,
            lock_names_target=True,
            source_retired=True,
            pre_move="PLANNED",
        )
        res = phase.derive_phase(ev)
        self.assertEqual(
            (res.phase, res.substate, res.action), ("PRE-MOVE", "PLANNED", "plan")
        )
        self.assertIn("gap-b", res.reason)
        self.assertIn("§4.3", res.reason)
        ev.live_watcher = False
        self.assertEqual(phase.derive_phase(ev).phase, "EXITED")

    def test_husk_unconfirm_branch(self) -> None:
        ev = _ev(
            holders=[{"cfg": "source", "pane_bound": True}],
            source_alive=True,
            source_at_composer=True,
            handed_off=True,
            last_error_class="TOCTOU",
        )
        res = phase.derive_phase(ev)
        self.assertEqual(
            (res.phase, res.substate, res.action),
            ("HUSK-RETIRED", "no-stub", "UNCONFIRM"),
        )
        ev.stub_present = True
        self.assertEqual(phase.derive_phase(ev).action, "A-husk")

    def test_pane_gone_substates(self) -> None:
        ev = _ev(
            handed_off=True,
            pane_state="gone",
            pane_absent_observations=2,
            exit_typed_by_me=True,
        )
        self.assertEqual(phase.derive_phase(ev).substate, "R")
        ev.exit_typed_by_me = False
        res = phase.derive_phase(ev)
        self.assertEqual((res.substate, res.action), ("NOT_NEEDED", "none"))
        ev.pane_absent_observations = 1
        self.assertEqual(phase.derive_phase(ev).phase, "PRE-MOVE")

    def test_transplanted(self) -> None:
        ev = _ev(
            holders=[{"cfg": "source", "pane_bound": True}],
            source_alive=True,
            lock_names_target=True,
        )
        self.assertEqual(phase.derive_phase(ev).phase, "TRANSPLANTED")


class FixtureCli(unittest.TestCase):
    def test_real_fixture_dir_passes(self) -> None:
        out = io.StringIO()
        with redirect_stdout(out):
            rc = phase.main(["--fixtures", FIXTURES])
        text = out.getvalue()
        self.assertEqual(rc, 0, text)
        self.assertRegex(text, r"phase fixtures: (\d+) rows, \1 pass, 0 fail")
        self.assertNotIn("FAIL", text)

    def test_empty_dir_exits_2(self) -> None:
        with tempfile.TemporaryDirectory() as d, redirect_stderr(io.StringIO()):
            self.assertEqual(phase.main(["--fixtures", d]), 2)


if __name__ == "__main__":
    unittest.main()
