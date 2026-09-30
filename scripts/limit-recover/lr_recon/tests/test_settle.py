"""settle.py: actuator exits reach the record, holds can clear, confirm_len comes from the tombstone.

Each case is a shape the W5 rig produced on its first act-mode runs."""

import json
import os
import shutil
import tempfile
import unittest

from lr_recon import classify, evidence
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


STRANDED = """!! unknown arg: --record-id
  --headless          (usage text: any word may appear here)
lr-handoff 4ac4c35d: verdict=STRANDED from=next to=next4 proven=no trigger=limit — the recycle did not verify (handoff-fire rc=1): the transplant is DONE
lr-handoff: RETRY the recovery (the transplant is idempotent on a same-target re-run):
"""


class Exits(unittest.TestCase):
    def test_a_stranded_move_is_never_terminal(self):
        """W5 rig N=5: a usage dump above lr-handoff's STRANDED verdict said "headless", classify
        read IMPOSSIBLE and closed five records whose sessions had already been transplanted."""
        r = rec()
        d = settle.settle_exit(r, actuator(), 4, STRANDED, 1.0)
        self.assertNotIn("IMPOSSIBLE", d)
        self.assertIn("BACKOFF", d)
        self.assertIsNone(r.terminal)
        self.assertTrue(r.open)

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

    def test_a_late_failed_exit_never_reopens_a_moved_record(self):
        """W5b real canary 3: B's relaunch worked (MOVED), then its watcher's turn wait timed out
        rc 1; scored, it bumped the attempt and re-opened the record to RELAUNCHED."""
        r = rec(phase="MOVED", sub=None)
        r.attempt = 2
        d = settle.settle_exit(
            r, actuator("B"), 1, "!! RECYCLE FAILED — never engaged", 5.0
        )
        self.assertIn("the phase decides", d)
        self.assertEqual((r.attempt, r.last_error), (2, None))
        # CONTROL: the same exit before the move is proven still counts
        r2 = rec(phase="RELAUNCHED", sub="UNPROMPTED")
        settle.settle_exit(
            r2, actuator("B"), 1, "!! RECYCLE FAILED — never engaged", 5.0
        )
        self.assertEqual(r2.attempt, 2)

    def test_a_held_husk_waits_a_reprobe_instead_of_respawning(self):
        """W5b real canary 3: past PRE-MOVE nothing held the phase table, and a held A-husk was
        re-derived and re-spawned every ~4 s — 181 spawns, each held."""
        r = rec(phase="HUSK-RETIRED", sub="stub")
        held = (
            "!! recycle ABORTED before /exit (held: bg-work): HELD:mid-turn — /exit NOT "
            "submitted, watcher disarmed, pane lock released, unconfirm rc n/a. The session "
            "stays alive.\n"
        )
        d = settle.settle_exit(r, actuator("A-husk"), 1, held, 100.0)
        self.assertIn("HOLD", d)
        self.assertEqual(r.next_eligible_at, 100.0 + settle.REPROBE_S)
        self.assertEqual(
            r.phase, "HUSK-RETIRED"
        )  # the phase stays the table's to derive

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
        self.assertFalse(
            settle.mark_in_flight(r)
        )  # no tombstone read yet: still PLANNED
        r.confirm_len = 10
        self.assertTrue(settle.mark_in_flight(r))
        self.assertIsNone(act.choose(T.PhaseResult(phase="PRE-MOVE"), r))

    def test_a_move_derived_transplanted_is_in_flight_when_its_A_exits(self):
        """W5 rig N=5: the pass before A exits derives TRANSPLANTED (row 12), which clears the
        substate; the PRE-MOVE-only test then left the relaunch gap at PRE-MOVE/None, and §4.4 read
        every member of the cohort as unowned for two passes."""
        r = rec(phase="TRANSPLANTED", sub=None)
        r.confirm_len = 10
        self.assertEqual(settle.settle_exit(r, actuator(), 0, "", 1.0), "A rc=0")
        self.assertEqual(r.substate, "IN-FLIGHT")

    def test_the_gap_after_transplanted_is_in_flight_without_an_exit(self):
        r = rec(
            phase="PRE-MOVE", sub=None
        )  # PLANNED → TRANSPLANTED → the gap, A not reaped yet
        r.confirm_len = 10
        self.assertTrue(settle.mark_in_flight(r))
        self.assertEqual(r.substate, "IN-FLIGHT")
        r2 = rec(
            phase="PRE-MOVE", sub=None
        )  # never confirmed: a fresh record, not a move
        self.assertFalse(settle.mark_in_flight(r2))

    def test_a_failed_move_makes_its_retry_a_new_attempt(self):
        r = rec()
        settle.settle_exit(
            r, actuator(), 6, PRECHECK_HELD % ("x", "draft", "draft"), 1.0
        )
        self.assertEqual(r.attempt, 2)
        settle.settle_exit(r, actuator("C"), 1, "cc_tui_submit mangled", 2.0)
        self.assertEqual(r.attempt, 2)  # an engage is not a move

    def test_hop_moves_from_the_failed_target_as_a_new_attempt(self):
        r = rec(phase="TARGET-LIMITED", sub=None)
        r.source_acct, r.source_cfg, r.target_cfg, r.confirm_len = (
            "next",
            "/c/a",
            "/c/b",
            99,
        )
        r.submit_token = "lrr-1"
        h = T.HolderObs(pid=77, lstart="L", cfg="/c/b", src="session-row", pane=(1, 2))
        settle.new_attempt(r, h, "limit", 5.0)
        self.assertEqual(
            (r.source_acct, r.source_cfg, r.source_pid), ("next2", "/c/b", 77)
        )
        self.assertEqual((r.target_acct, r.confirm_len, r.submit_token), ("", None, ""))
        self.assertEqual((r.phase, r.substate, r.attempt), ("PRE-MOVE", "DETECTED", 2))
        self.assertEqual((r.close["hop"], r.close["hops"]), ("limit", 1))

    def test_an_auth_hop_round_trips_through_undo(self):
        """W5 rig r2 target-auth: an auth hop must stay reversible until its attempt confirms."""
        r = rec(phase="TARGET-AUTH", sub=None)
        r.source_acct, r.target_cfg, r.assign_id = "next", "/c2", r.record_id
        r.confirm_len, r.timeline.confirmed = 3724, 50.0
        before = json.dumps(T.to_dict(r.timeline), sort_keys=True)
        settle.new_attempt(r, None, "auth", 100.0)
        r.target_acct = "next4"  # re-placed
        self.assertTrue(settle.undo_hop(r))
        self.assertEqual(
            (r.target_acct, r.target_cfg, r.source_acct), ("next2", "/c2", "next")
        )
        self.assertEqual((r.confirm_len, r.timeline.confirmed), (3724, 50.0))
        self.assertEqual(json.dumps(T.to_dict(r.timeline), sort_keys=True), before)
        self.assertEqual((r.phase, r.attempt), ("TARGET-AUTH", 2))
        self.assertFalse(settle.undo_hop(r))  # once
        # a limit hop stashes nothing, so there is nothing to undo
        r2 = rec(phase="TARGET-LIMITED", sub=None)
        settle.new_attempt(r2, None, "limit", 100.0)
        self.assertNotIn("pre_hop", r2.close)
        self.assertFalse(settle.undo_hop(r2))

    def test_a_wait_is_not_retried_before_its_eligibility_time(self):
        r = rec()
        r.kind = "idle"
        settle.settle_exit(
            r, actuator(), 6, "lr-handoff: PRECHECK REFUSED:not-limited — x", 5.0
        )
        self.assertEqual(
            (r.substate, r.next_eligible_at), ("WAIT_DATA", 5.0 + settle.WAIT_RETRY_S)
        )

    def test_a_capacity_shed_R_waits_its_retry_time(self):
        r = rec(phase="PANE-GONE", sub="R")
        txt = "boot-resume-launch: capacity-admit: REFUSING resume x on next3 — load 54.30 on 10 cores"
        self.assertIn("WAIT", settle.settle_exit(r, actuator("R"), 9, txt, 5.0))
        self.assertEqual(
            (r.next_eligible_at, r.escalated), (5.0 + settle.WAIT_RETRY_S, False)
        )

    def test_a_failed_R_makes_its_retry_a_new_attempt_outside_pre_move(self):
        r = rec(phase="PANE-GONE", sub="R")
        settle.settle_exit(
            r, actuator("R"), 4, "boot-resume-launch: kitty launch failed", 5.0
        )
        self.assertEqual(r.attempt, 2)

    def test_not_limited_on_a_hop_waits_instead_of_closing(self):
        r = rec()
        r.close["hop"] = "auth"
        settle.settle_exit(
            r, actuator(), 6, "lr-handoff: PRECHECK REFUSED:not-limited — x", 5.0
        )
        self.assertIsNone(r.terminal)
        self.assertEqual(r.substate, "WAIT_SLOT")

    def test_unknown_exit_code_is_no_verdict(self):
        r = rec(phase="RELAUNCHED", sub="UNPROMPTED")
        pr = T.ProcRole(role="actuator", pid=7, lstart="x", argv_hash="adopted")
        for _ in range(
            3
        ):  # twice used to ESCALATE: two "identical DETERMINISTIC" rc=-1 exits
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


class Replaced(unittest.TestCase):
    def test_R_closes_once_the_session_is_live_in_another_window(self):
        r = rec(phase="PANE-GONE", sub="R")
        r.pane = (1, 2)
        settle.settle_exit(r, actuator("R"), 0, "", 1.0)
        sess = T.SessionObs(sid=r.sid, holders=[])
        snap = T.Snapshot(wall=2.0, uptime_raw=0.0, sessions={r.sid: sess})
        self.assertFalse(settle.replaced_elsewhere(r, snap, 2.0))  # not up yet
        sess.holders = [
            T.HolderObs(pid=9, lstart="L", cfg="/c", src="session-row", pane=(1, 7))
        ]
        self.assertTrue(settle.replaced_elsewhere(r, snap, 3.0))
        self.assertEqual(r.terminal.outcome, "REPLACED-NEW-WINDOW")
        self.assertEqual((r.close["via"], r.close["same_window"]), ("R", False))
        self.assertFalse(
            settle.replacement_unproven(r, 500.0)
        )  # proven: never consulted

    def test_r_rc0_backs_off_one_window_per_r(self):
        """W5 rig: the pass after an R rc 0 re-derived PANE-GONE/R and opened a second window."""
        from lr_recon import act

        r = rec(phase="PANE-GONE", sub="R")
        settle.settle_exit(r, actuator("R"), 0, "", 100.0)
        self.assertEqual(r.close["replaced_at"], 100.0)
        snap = T.Snapshot(wall=101.0, uptime_raw=0.0)
        p = T.Paths(lr_root=self.tmp, root=self.tmp)
        open(p.recon_on, "w").close()
        got = act.may_actuate(p, "act", r, "R", snap, 101.0, True, 0, 16, env={})
        self.assertEqual(got, (False, "backoff"))

    def test_unproven_r_counts_and_escalates_on_the_second(self):
        """W5 rig: the engine refused inside the new window after R returned 0; one window per
        capacity admit opened forever."""
        r = rec(phase="PANE-GONE", sub="R")
        r.close["replaced_at"] = 100.0
        self.assertFalse(settle.replacement_unproven(r, 150.0))
        self.assertEqual((r.last_error, r.close["replaced_at"]), (None, 100.0))
        self.assertTrue(settle.replacement_unproven(r, 221.0))
        self.assertNotIn("replaced_at", r.close)
        self.assertEqual((r.last_error.cls, r.escalated), ("DETERMINISTIC", False))
        r.close["replaced_at"] = 230.0
        self.assertTrue(settle.replacement_unproven(r, 351.0))
        self.assertTrue(r.escalated)

    def setUp(self):
        self.tmp = tempfile.mkdtemp()

    def tearDown(self):
        shutil.rmtree(self.tmp)


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


class AbortedAdmitHeld(unittest.TestCase):
    """D7.1: lr-handoff's in-place admit, ABORTED before /exit, now ends `verdict: HELD:<reason>`
    with NOTMOVED and exit 6. Every reason is a hold; none escalates as DETERMINISTIC."""

    ABORTED = (
        "handoff-fire: recycle REFUSED after 180s\n"
        "lr-handoff: verdict: HELD:%s\n"
        "lr-handoff 4ac4c35d: verdict=NOTMOVED from=next to=next2 proven=no trigger=limit (rc 6)\n"
    )

    def test_each_reason_maps_to_its_hold(self):
        for reason, sub in (
            ("draft", "HOLD-DRAFT"),
            ("focused", "HOLD-FOCUS"),
            ("busy", "HOLD-COMPOSER"),
            ("team", "HELD:team"),
            ("unknown", "HOLD-COMPOSER"),
        ):
            r = rec(sub="PLANNED")
            self.assertEqual(
                settle.outcome(r, 6, self.ABORTED % reason)[:2], ("HOLD", sub), reason
            )
            r = rec(sub="PLANNED")
            settle.settle_exit(r, actuator(), 6, self.ABORTED % reason, 1.0)
            self.assertFalse(r.escalated, reason)
            self.assertEqual(r.substate, sub, reason)

    def test_recycle_held_rows_name_team_and_busy(self):
        self.assertEqual(settle.RCY_HELD_SUB["team"], "HELD:team")
        self.assertEqual(settle.RCY_HELD_SUB["busy"], "HOLD-COMPOSER")


class TeamFlicker(unittest.TestCase):
    """D4.4: member counts flicker; one pass reading 0 must not release a held lead."""

    @staticmethod
    def bucket(members):
        return "HELD:team" if members else "LIMITED"

    def test_sim_case_a_one_zero_one_stays_held(self):
        r = rec(sub="DETECTED")
        r.target_acct = ""
        for t, m in enumerate((1, 0, 1)):
            settle.rebucket(r, self.bucket(m), float(t), eta=100.0)
            self.assertEqual(r.substate, "HELD:team", "pass %d" % t)
        self.assertEqual(r.wait.eta, 100.0)  # the reset, which the wake keys on

    def test_a_rebucketed_wait_reset_keeps_its_reset(self):
        """D1.11: WAIT_RESET via rebucket had no eta, so it never woke."""
        r = rec(sub="DETECTED")
        self.assertTrue(settle.rebucket(r, "STAY", 1.0, eta=50.0))
        self.assertEqual((r.substate, r.wait.eta), ("WAIT_RESET", 50.0))

    def test_two_member_free_passes_release_it(self):
        r = rec(sub="HELD:team")
        self.assertFalse(settle.rebucket(r, "LIMITED", 1.0))
        self.assertEqual(r.substate, "HELD:team")
        self.assertTrue(settle.rebucket(r, "LIMITED", 2.0))
        self.assertEqual(r.substate, "DETECTED")
        self.assertNotIn("team_zero", r.close)

    def test_sim_case_b_held_team_takes_over_waits_and_plans(self):
        for sub in ("WAIT_SLOT", "WAIT_DATA", "WAIT_CAPACITY", "BACKOFF", "PLANNED"):
            r = rec(sub=sub)
            self.assertTrue(settle.rebucket(r, "HELD:team", 1.0), sub)
            self.assertEqual(r.substate, "HELD:team", sub)
            if sub == "PLANNED":
                self.assertEqual(r.target_acct, "")  # the caller voids its phantom
        # the takeover is HELD:team's alone: another hold still leaves a plan to the settle path
        self.assertFalse(settle.rebucket(rec(sub="WAIT_SLOT"), "HOLD-BGWORK", 1.0))

    def test_a_team_notmoved_is_a_hold_never_deterministic(self):
        self.assertEqual(classify.map_notmoved("team", "limited"), ("HOLD", "HELD:team"))


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

    def test_bundle_launcher_picks_this_records_bundle(self):
        """W5 rig: nothing set rec.bundle, so every A-husk and B ran `--resume-launcher ""`."""
        r = rec()
        home = self.cfg
        for ts, rid in (
            ("20260929T114800Z", r.record_id),
            ("20260929T114900Z", "other"),
        ):
            d = os.path.join(settle.bundles_dir(home, r.sid), "bundle-" + ts)
            os.makedirs(d)
            with open(os.path.join(d, "MANIFEST.json"), "w") as fh:
                json.dump({"record_id": rid, "target": "next2"}, fh)
            open(os.path.join(d, "lr-launch-4ac4c35d-%s.sh" % ts[-4:]), "w").close()
        got = settle.bundle_launcher(home, r)
        self.assertTrue(
            got.endswith("bundle-20260929T114800Z/lr-launch-4ac4c35d-800Z.sh")
        )
        r.target_acct = "next4"  # a different move of the same record: not this bundle
        self.assertEqual(settle.bundle_launcher(home, r), "")

    def _handoffs(self, *rows):
        d = os.path.join(self.cfg, ".claude", "logs")
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, "handoffs.jsonl"), "a") as fh:
            for cls, att, detail in rows:
                fh.write(
                    json.dumps({"class": cls, "attempt": att, "detail": detail}) + "\n"
                )

    def test_watcher_bgwork_row_marks_hold_for_this_attempt_only(self):
        """W5 rig: the watcher Esc'd a bg-work dialog after the confirm, said so only in its handoffs
        row, and row 9 chose A-husk instead of UNCONFIRM."""
        r = rec(phase="HUSK-RETIRED", sub="no-stub")
        det = "background-work dialog at 15s cancelled with Esc; nothing typed; "
        self._handoffs(
            ("recycle-held-bgwork", "recon:c:4ac4c35d:1:3", det + "unconfirm=needed"),
            ("recycle-held-bgwork", "recon:c:4ac4c35d:1:1", det + "unconfirm rc 0"),
        )
        # another attempt's row, and this attempt's row that needs no unconfirm
        self.assertFalse(settle.note_watcher_hold(self.cfg, r, 5.0))
        self._handoffs(
            ("recycle-held-bgwork", "recon:c:4ac4c35d:1:1", det + "unconfirm=needed")
        )
        self.assertTrue(settle.note_watcher_hold(self.cfg, r, 5.0))
        self.assertEqual((r.last_error.cls, r.attempts_by_class["HOLD"]), ("HOLD", 1))
        self.assertFalse(settle.note_watcher_hold(self.cfg, r, 6.0))  # idempotent
        d = settle.settle_exit(r, actuator("UNCONFIRM"), 0, "", 7.0)
        self.assertIn("HOLD-BGWORK", d)
        self.assertEqual((r.attempt, r.confirm_len, r.last_error), (2, None, None))
        self.assertEqual((r.substate, r.wait.reason), ("HOLD-BGWORK", "HOLD-BGWORK"))
        # attempt 2 is a new move: the old attempt's row is not its hold
        self.assertFalse(settle.note_watcher_hold(self.cfg, r, 8.0))
        r.phase = "PRE-MOVE"
        self.assertTrue(settle.rebucket(r, "LIMITED", 9.0))  # the job ended: move again

    def test_a_deterministic_unconfirm_failure_escalates_despite_the_watcher_row(self):
        """W5 rig 0f71c0d5: each pass re-stamped HOLD over the UNCONFIRM's rc 2, so the identical
        second failure never escalated (57 DETERMINISTIC, 58 HOLD, never ESCALATED)."""
        r = rec(phase="HUSK-RETIRED", sub="no-stub")
        self._handoffs(
            (
                "recycle-held-bgwork",
                "recon:c:4ac4c35d:1:1",
                "background-work dialog at 15s cancelled with Esc; unconfirm=needed",
            )
        )
        bad = "lr-transplant: unknown arg --source-pid\n"
        self.assertTrue(settle.note_watcher_hold(self.cfg, r, 5.0))
        settle.settle_exit(r, actuator("UNCONFIRM"), 2, bad, 6.0)
        self.assertFalse(settle.note_watcher_hold(self.cfg, r, 7.0))
        settle.settle_exit(r, actuator("UNCONFIRM"), 2, bad, 8.0)
        self.assertTrue(r.escalated)
        snap = T.Snapshot(wall=9.0, uptime_raw=0.0, procs={})
        paths = T.Paths(lr_root=self.cfg, root=os.path.join(self.cfg, "recon"))
        ev = evidence.build(paths, r, snap, debt_open=lambda s: False)
        self.assertEqual(ev.last_error_class, "HOLD")  # row 9 still picks UNCONFIRM

    def test_no_tombstone_leaves_it_unknown(self):
        r = rec()
        r.source_cfg, r.cwd = self.cfg, "/w/x"
        self.assertFalse(settle.note_confirm(r))
        self.assertIsNone(r.confirm_len)


ABORT = (
    "!! recycle ABORTED before /exit (held: draft): composer: operatordrafttypedafterconfirm"
    " — /exit NOT submitted, watcher disarmed, pane lock released, unconfirm rc 0. The session"
    " stays alive.\n"
)


class Unconfirm(unittest.TestCase):
    """W5 rig draft-after-confirm: lr-transplant --phase unconfirm renamed the tombstone, nothing
    cleared confirm_len, and mark_in_flight kept the record IN-FLIGHT until RECON-DEFECT."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.paths = T.Paths(lr_root=self.tmp, root=os.path.join(self.tmp, "recon"))
        os.makedirs(self.paths.p("actlogs"))
        self.r = rec(sub=None)
        self.r.source_cfg, self.r.cwd = self.tmp, "/w/x"
        self.d = os.path.join(self.tmp, "projects", "-w-x")
        os.makedirs(self.d)
        self.base = os.path.join(self.d, self.r.sid)
        open(self.base + ".jsonl.handed-off", "w").close()
        with open(self.base + ".HANDOFF.json", "w") as fh:
            json.dump({"confirm_len": 3724}, fh)
        self.assertTrue(settle.note_confirm(self.r))

    def tearDown(self):
        shutil.rmtree(self.tmp)

    def _unconfirm(self, actlog=""):
        os.rename(self.base + ".jsonl.handed-off", self.base + ".jsonl")
        os.rename(self.base + ".HANDOFF.json", self.base + ".HANDOFF.json.unconfirmed")
        with open(settle.actlog(self.paths, self.r, "A"), "w") as fh:
            fh.write(actlog)

    def test_an_unconfirmed_move_holds_instead_of_in_flight(self):
        self._unconfirm(ABORT)
        self.assertEqual(settle.note_unconfirm(self.paths, self.r, 100.0), "HOLD-DRAFT")
        self.assertEqual((self.r.confirm_len, self.r.substate), (None, "HOLD-DRAFT"))
        self.assertIsNotNone(self.r.wait.eta)  # REPROBED
        self.assertFalse(settle.mark_in_flight(self.r))

    def test_an_unconfirm_bumps_the_attempt(self):
        """The latched case: the re-probe's A must be a new attempt (one move spawn per attempt)."""
        self._unconfirm(ABORT)
        self.assertEqual(settle.note_unconfirm(self.paths, self.r, 100.0), "HOLD-DRAFT")
        self.assertEqual(self.r.attempt, 2)

    def test_an_unconfirm_the_daemon_never_latched_still_holds(self):
        """W5 rig 398fd593: no pass landed in the confirm→unconfirm window, so confirm_len never
        latched and the record sat at PRE-MOVE/None."""
        self.r.confirm_len, self.r.timeline.confirmed, self.r.substate = (
            None,
            None,
            None,
        )
        self._unconfirm(ABORT)
        self.assertEqual(settle.note_unconfirm(self.paths, self.r, 100.0), "HOLD-DRAFT")
        self.assertEqual((self.r.attempt, self.r.substate), (2, "HOLD-DRAFT"))
        self.assertIsNotNone(self.r.wait.eta)
        self.r.substate = None  # the same rename, seen again: once per inode
        self.assertEqual(settle.note_unconfirm(self.paths, self.r, 101.0), "")
        self.assertEqual(self.r.attempt, 2)

    def test_a_replanned_attempt_is_not_reheld_by_an_old_rename(self):
        self.r.confirm_len, self.r.substate = None, "PLANNED"
        self._unconfirm(ABORT)
        self.assertEqual(settle.note_unconfirm(self.paths, self.r, 100.0), "")
        self.assertEqual((self.r.substate, self.r.attempt), ("PLANNED", 1))

    def test_the_real_relaunch_gap_is_untouched(self):
        self.assertEqual(settle.note_unconfirm(self.paths, self.r, 100.0), "")
        self.assertTrue(settle.mark_in_flight(self.r))

    def test_unconfirm_without_a_named_hold_goes_back_to_detected(self):
        self._unconfirm()
        self.assertEqual(settle.note_unconfirm(self.paths, self.r, 100.0), "DETECTED")
        self.assertEqual(self.r.substate, "DETECTED")

    def test_held_after_confirm_beats_stranded(self):
        r = rec()
        r.confirm_len = 3724
        d = settle.settle_exit(r, actuator(), 4, ABORT + STRANDED, 1.0)
        self.assertIn("HOLD", d)
        self.assertEqual((r.substate, r.confirm_len), ("HOLD-DRAFT", None))

    def test_a_failed_attempt_forgets_its_confirm(self):
        r = rec()
        r.confirm_len = 3724
        settle.settle_exit(
            r, actuator(), 6, PRECHECK_HELD % ("x", "draft", "draft"), 1.0
        )
        self.assertIsNone(r.confirm_len)
        r.substate = "PLANNED"
        self.assertFalse(settle.mark_in_flight(r))


if __name__ == "__main__":
    unittest.main()
