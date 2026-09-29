"""__main__: mode resolution only lowers, and a full pass over a fake census never actuates or
claims without recon.on + mode act (the W3 'daemon NOT loaded, 0 actuations' guarantee)."""

import io
import json
import os
import tempfile
import unittest
from contextlib import redirect_stdout
from unittest import mock

from lr_recon import __main__ as M
from lr_recon import plan
from lr_recon import types as T

L = "Tue Sep 29 11:19:17 2026"


def _tx(cwd):
    p = os.path.join(cwd, "t.jsonl")
    open(p, "a").close()
    return p


def _snap(now, cwd):
    s = T.SessionObs(
        sid="abcdef01-0000-0000-0000-000000000001",
        acct="next3",
        cfg="/nonexistent-cfg",
        pid=10,
        lstart=L,
        cwd=cwd,
        pane=(5, 7),
        registry_name="p",
        holders=[
            T.HolderObs(
                pid=10, lstart=L, cfg="/nonexistent-cfg", src="registry", pane=(5, 7)
            )
        ],
        transcript=T.TranscriptObs(
            path=_tx(cwd),
            at_rest=True,
            last={
                "limit": True,
                "kind": "limit",
                "cap": "seven_day",
                "resets_at": now + 7200,
            },
        ),
    )
    pane = T.PaneObs(
        kitty_pid=5,
        window_id=7,
        sock="unix:/tmp/kitty-5",
        root_pid=20,
        root_lstart=L,
        root_shape="shell",
        state="claude",
    )
    return T.Snapshot(
        wall=now, uptime_raw=0.0, panes={"5:7": pane}, sessions={s.sid: s}
    )


class MainTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.home = os.path.join(self.tmp, "home")
        os.makedirs(self.home)
        self.env = mock.patch.dict(
            os.environ,
            {"LR_STATE_DIR": os.path.join(self.tmp, "lr"), "HOME": self.home},
        )
        self.env.start()
        self.paths = T.Paths.from_env(root=os.path.join(self.tmp, "lr", "recon"))
        os.makedirs(self.paths.requests)
        self.req = os.path.join(
            self.paths.requests, "abcdef01-0000-0000-0000-000000000001.json"
        )
        with open(self.req, "w") as fh:
            json.dump({"sid": "abcdef01-0000-0000-0000-000000000001"}, fh)

    def tearDown(self):
        self.env.stop()

    def test_mode_cap_only_lowers(self):
        os.makedirs(self.paths.root, exist_ok=True)
        self.assertEqual(M.read_mode(self.paths, None), "observe")
        with open(self.paths.mode_file, "w") as fh:
            fh.write("act\n")
        self.assertEqual(M.read_mode(self.paths, None), "act")
        self.assertEqual(M.read_mode(self.paths, "observe"), "observe")
        with open(self.paths.mode_file, "w") as fh:
            fh.write("plan\n")
        self.assertEqual(M.read_mode(self.paths, "act"), "plan")
        with open(self.paths.mode_file, "w") as fh:
            fh.write("garbage\n")
        self.assertEqual(M.read_mode(self.paths, None), "observe")

    def _pass(self, mode_cap, mode_file=None):
        import time

        now = time.time()
        ctx = M.Ctx(self.paths, mode_cap, self.home)
        if mode_file:
            os.makedirs(self.paths.root, exist_ok=True)
            with open(self.paths.mode_file, "w") as fh:
                fh.write(mode_file)
        placed = {
            "abcdef01-0000-0000-0000-000000000001": T.Placement(acct="next4", weight=1)
        }
        with (
            mock.patch("lr_recon.observe.observe", return_value=_snap(now, self.tmp)),
            mock.patch.object(plan, "place", return_value=(placed, 0)),
            mock.patch.object(plan, "assign_many", return_value=0) as am,
            mock.patch.object(M.act, "spawn") as popen,
        ):
            summary = M.run_pass(ctx)
        return ctx, summary, am, popen

    def test_observe_pass_counts_and_never_acts(self):
        ctx, s, am, popen = self._pass("observe")
        self.assertEqual((s["mode"], s["actuations"]), ("observe", 0))
        self.assertEqual(s["buckets"].get("LIMITED"), 1)
        self.assertEqual(s["open"], 1)
        popen.assert_not_called()
        am.assert_not_called()
        self.assertTrue(os.path.exists(self.req), "observe never claims a request")
        self.assertFalse(os.listdir(self.paths.owned))
        rec = next(iter(ctx.records.values()))
        self.assertTrue(rec.plan_only)  # hook origin without autorecover.on
        self.assertTrue(
            os.path.exists(os.path.join(self.paths.shadow, "last-pass.json"))
        )

    def test_act_mode_without_recon_on_never_acts(self):
        _ctx, s, am, popen = self._pass(None, mode_file="act\n")
        self.assertEqual((s["mode"], s["actuations"]), ("act", 0))
        popen.assert_not_called()
        am.assert_not_called()

    def test_pass_writes_the_readout_line(self):
        ctx, _s, _am, _popen = self._pass("observe")
        with open(self.paths.p("readout.line"), encoding="utf-8") as fh:
            line = fh.read()
        self.assertTrue(line.startswith("lr-recon: 1 cohort open · "), line)
        # nothing open ⇒ the file is emptied, not left holding the last open line
        for r in ctx.records.values():
            r.terminal = T.Terminal(outcome="CLOSED", at=1.0)
        M._report(ctx, "observe", 2.0)
        self.assertEqual(os.path.getsize(self.paths.p("readout.line")), 0)

    # ── cc-lr cohort refire: the ctl consumer ─────────────────────────────────────────────────
    def _ctl(self, sid, by="cc-lr"):
        os.makedirs(self.paths.ctl, exist_ok=True)
        p = os.path.join(self.paths.ctl, sid + ".refire.json")
        with open(p, "w") as fh:
            json.dump({"sid": sid, "at": 1, "by": by}, fh)
        return p

    def _events(self):
        with open(self.paths.events, encoding="utf-8") as fh:
            return [json.loads(x) for x in fh if x.strip()]

    def test_refire_rearms_an_open_member_and_moves_the_file(self):
        sid = "abcdef01-0000-0000-0000-000000000009"
        ctx = M.Ctx(self.paths, None, self.home)
        r = T.Record(sid=sid, record_id="r9", escalated=True, next_eligible_at=None)
        r.attempts_by_class = {"TRANSIENT": 7, "DETERMINISTIC": 2}
        ctx.records[sid] = r
        src = self._ctl(sid)
        self.assertEqual(M._refire(ctx, 100.0), 1)
        # classify.rearm's contract: escalation cleared, counted classes reset, eligible now
        self.assertEqual(
            (r.escalated, r.attempts_by_class, r.next_eligible_at), (False, {}, 100.0)
        )
        self.assertFalse(os.path.exists(src))
        self.assertTrue(
            os.path.exists(os.path.join(self.paths.ctl, "done", sid + ".refire.json"))
        )
        ev = self._events()[-1]
        self.assertEqual((ev["ev"], ev["sid"]), ("refire", sid))
        self.assertEqual(M._refire(ctx, 200.0), 0)  # consumed once, never re-applied

    def test_refire_for_unknown_or_closed_sid_is_moved_and_logged(self):
        ctx = M.Ctx(self.paths, None, self.home)
        closed = T.Record(sid="closed01", record_id="rc", escalated=True)
        closed.terminal = T.Terminal(outcome="CLOSED", at=1.0)
        ctx.records["closed01"] = closed
        for sid in ("nosuch01", "closed01"):
            self._ctl(sid)
        self.assertEqual(M._refire(ctx, 100.0), 0)
        self.assertTrue(closed.escalated, "a closed record is never re-armed")
        self.assertEqual(
            sorted(os.listdir(os.path.join(self.paths.ctl, "done"))),
            ["closed01.refire.json", "nosuch01.refire.json"],
        )
        self.assertEqual(
            [e["ev"] for e in self._events()], ["refire-unknown", "refire-unknown"]
        )

    def test_refire_is_consumed_inside_a_pass(self):
        src = self._ctl("abcdef01-0000-0000-0000-000000000001")
        self._pass("observe")
        self.assertFalse(os.path.exists(src))
        self.assertIn("refire", [e["ev"] for e in self._events()])

    def test_once_prints_census_and_zero_actuations(self):
        import time

        buf = io.StringIO()
        with (
            mock.patch(
                "lr_recon.observe.observe", return_value=_snap(time.time(), self.tmp)
            ),
            mock.patch.object(plan, "place", return_value=({}, 3)),
            mock.patch.object(M.act, "spawn") as popen,
            redirect_stdout(buf),
        ):
            rc = M.main(["--mode", "observe", "--once", "--root", self.paths.root])
        out = buf.getvalue()
        self.assertEqual(rc, 0)
        self.assertIn("census:", out)
        self.assertIn("mode=observe actuations=0 recon.on=absent", out)
        popen.assert_not_called()  # no background --fresh sweep in shadow mode

    def test_a_stale_request_leaves_a_terminal_not_needed_member(self):
        """W5 rig: a request for a dead session was claimed NOT_NEEDED and left no cohort member."""
        import time

        now = time.time()
        snap = _snap(now, self.tmp)
        s = next(iter(snap.sessions.values()))
        s.holders, s.pid, s.pane = [], 0, None  # the session is dead: no live holder
        ctx = M.Ctx(self.paths, None, self.home)
        M.store.ensure_dirs(self.paths)
        reqs = M.store.list_requests(self.paths)
        M._census(ctx, snap, {}, reqs, "act", now)
        rec = ctx.records[s.sid]
        self.assertEqual(rec.terminal.outcome, "NOT_NEEDED")
        self.assertIn("dead-before-claim", rec.terminal.proof)
        self.assertEqual(rec.cohort_id, "next3-7d-%d" % int(now + 7200))

    def test_an_auth_cliff_writes_an_auth_fact(self):
        """W5 rig: a TARGET-AUTH hop found no <acct>.auth.json — the census wrote limit facts only."""
        import time

        now = time.time()
        snap = _snap(now, self.tmp)
        s = next(iter(snap.sessions.values()))
        s.transcript.last = {
            "limit": False,
            "kind": "auth_cliff",
            "raw_error": "authentication_failed",
        }
        ctx = M.Ctx(self.paths, None, self.home)
        facts = M._facts(ctx, snap, now)
        self.assertIn("next3.auth", facts)
        self.assertTrue(
            os.path.exists(os.path.join(self.paths.facts, "next3.auth.json"))
        )

    def test_a_move_target_is_not_blamed_for_the_sources_death(self):
        """W5 rig: a moved session's copied transcript ends in the source's limit record, and the
        census wrote it as a phantom fact on the TARGET until the move engaged."""
        import time

        now = time.time()
        snap = _snap(now, self.tmp)  # acct next3, last record a limit
        ctx = M.Ctx(self.paths, None, self.home)
        rec = self._rec("RELAUNCHED", target="next3")
        ctx.records[rec.sid] = rec
        self.assertNotIn("next3.7d", M._facts(ctx, snap, now))
        rec.timeline.submitted = (
            now  # the target served this move's prompt: its death now
        )
        self.assertIn("next3.7d", M._facts(ctx, snap, now))

    def _recovered(self, ts):
        import time

        now = time.time()
        snap = _snap(now, self.tmp)  # on next3, last record a limit
        s = next(iter(snap.sessions.values()))
        s.transcript.last.update(uuid="u", ts=ts)
        ctx = M.Ctx(self.paths, None, self.home)
        M.store.ensure_dirs(self.paths)
        rec = T.Record(sid=s.sid, record_id="r1", source_acct="next")
        rec.terminal = T.Terminal(outcome="REPLACED-NEW-WINDOW", at=now)
        rec.close["death"] = "u@t"
        ctx.records[s.sid] = rec
        M._census(ctx, snap, {}, [], "act", now)
        return rec, ctx, M._facts(ctx, snap, now)

    def test_a_recovered_death_is_not_re_recorded(self):
        """W5 rig 80294ba4: R resumes without typing, so the copied limit record re-opened the sid
        as a new LAUNCHER-ROOTED record over REPLACED-NEW-WINDOW and wrote a false next2 fact."""
        rec, ctx, facts = self._recovered("t")
        self.assertIs(ctx.records[rec.sid], rec)
        self.assertEqual(rec.terminal.outcome, "REPLACED-NEW-WINDOW")
        self.assertNotIn("next3.7d", facts)

    def test_a_new_death_after_recovery_is_a_new_record(self):
        """CONTROL: a later death on the target has a new ts, so it is recovered too."""
        rec, ctx, facts = self._recovered("t2")
        new = ctx.records[rec.sid]
        self.assertIsNot(new, rec)
        self.assertTrue(new.open)
        self.assertEqual(new.close.get("death"), "u@t2")
        self.assertIn("next3.7d", facts)

    def _hop_pass(self, phase, facts=None, live_watcher=False):
        import time

        now = time.time()
        rec = self._rec(phase, target="next3")
        ctx = M.Ctx(self.paths, None, self.home)
        M.store.ensure_dirs(self.paths)
        ctx.records = {rec.sid: rec}
        out = {
            "result": T.PhaseResult(phase=phase, action="wait"),
            "evidence": T.Evidence(live_watcher=live_watcher),
        }
        with mock.patch.object(M.evidence, "derive", return_value=out):
            M._derive(ctx, _snap(now, self.tmp), now, facts)
        return rec, ctx

    def test_a_contradicted_target_auth_retries_in_place(self):
        """W5 rig: the auth fact on the target was contradicted (another session served a turn),
        so the account serves; a hop moved it anyway and A refused the contradicted evidence."""
        bad = T.Fact(acct="next3", scope="auth", contradicted=True)
        rec, ctx = self._hop_pass("TARGET-AUTH", {"next3.auth": bad})
        self.assertEqual((rec.attempt, ctx.actions[rec.sid]), (1, "C-retry"))
        rec, ctx = self._hop_pass(
            "TARGET-AUTH", {"next3.auth": T.Fact("next3", "auth")}
        )
        self.assertEqual(
            (rec.attempt, ctx.actions[rec.sid]), (2, "plan")
        )  # CONTROL: hops

    def _unhop_pass(self, rec, ctx, facts):
        import time

        now = time.time()
        out = {
            "result": T.PhaseResult(phase="PRE-MOVE", action="plan"),
            "evidence": T.Evidence(),
        }
        with (
            mock.patch.object(M.evidence, "derive", return_value=out),
            mock.patch.object(plan, "unassign", return_value=0) as un,
        ):
            M._derive(ctx, _snap(now, self.tmp), now, facts)
        return un

    def test_an_auth_hop_contradicted_before_confirm_is_undone(self):
        """W5 rig r2 target-auth: the hop fired on a clean auth fact; ~1.3 s later another session
        served on that account (contradicted), and A refused the dead evidence to ESCALATED."""
        rec, ctx = self._hop_pass(
            "TARGET-AUTH", {"next3.auth": T.Fact("next3", "auth")}
        )
        self.assertEqual(
            (rec.attempt, rec.source_acct, rec.close.get("hop")), (2, "next3", "auth")
        )
        rec.target_acct, rec.assign_id = "next4", "r1"  # the hop was placed on next4
        rec.escalated = True
        bad = T.Fact(acct="next3", scope="auth", contradicted=True)
        un = self._unhop_pass(rec, ctx, {"next3.auth": bad})
        self.assertEqual(ctx.actions[rec.sid], "C-retry")
        self.assertEqual((rec.target_acct, rec.phase), ("next3", "TARGET-AUTH"))
        self.assertNotIn("hop", rec.close)
        self.assertFalse(rec.escalated)
        un.assert_called_once_with("r1")
        self.assertIn("unhop", [e["ev"] for e in self._events()])

    def test_a_confirmed_auth_hop_is_not_undone(self):
        """CONTROL: once the new attempt confirmed, the hop is committed."""
        import time

        rec, ctx = self._hop_pass(
            "TARGET-AUTH", {"next3.auth": T.Fact("next3", "auth")}
        )
        rec.target_acct = "next4"
        rec.timeline.confirmed = time.time()
        bad = T.Fact(acct="next3", scope="auth", contradicted=True)
        un = self._unhop_pass(rec, ctx, {"next3.auth": bad})
        self.assertNotEqual(ctx.actions[rec.sid], "C-retry")
        self.assertEqual((rec.close.get("hop"), rec.target_acct), ("auth", "next4"))
        un.assert_not_called()

    def test_no_hop_while_the_previous_moves_watcher_lives(self):
        """W5 rig target-limited: the hop ran under the old watcher's pane lock and STRANDED."""
        rec, ctx = self._hop_pass("TARGET-LIMITED", live_watcher=True)
        self.assertEqual((rec.attempt, rec.target_acct), (1, "next3"))
        self.assertNotIn("hop", [e.get("ev") for e in self._events_or_none()])
        rec, _ctx = self._hop_pass("TARGET-LIMITED")  # CONTROL: the watcher is gone
        self.assertEqual((rec.attempt, rec.close.get("hop")), (2, "limit"))

    def _events_or_none(self):
        return self._events() if os.path.exists(self.paths.events) else []

    def test_C_waits_until_the_move_chain_is_quiet(self):
        """W5 rig: C typed a second prompt while lr-fire-resume's own was still landing."""
        import time

        now = time.time()
        rec = T.Record(sid="abcdef01-0000-0000-0000-000000000001", record_id="r1")
        rec.phase, rec.substate, rec.pane = "RELAUNCHED", "UNPROMPTED", (5, 7)
        ctx = M.Ctx(self.paths, None, self.home)
        ctx.records = {rec.sid: rec}
        ctx.actions = {rec.sid: "C"}
        snap = _snap(now, self.tmp)
        with (
            mock.patch.object(M.act, "may_actuate", return_value=(True, "ok")),
            mock.patch.object(M.act, "spawn", return_value=4242) as sp,
            mock.patch.object(M.store, "append_launch"),
        ):
            rec.close["busy_at"] = now - 5  # the launcher was live 5 s ago
            self.assertEqual(M._dispatch(ctx, snap, "act", now), 0)
            sp.assert_not_called()
            rec.close["busy_at"] = now - M.C_GRACE_S - 1
            self.assertEqual(M._dispatch(ctx, snap, "act", now), 1)
            self.assertEqual(sp.call_args[0][2], "C")

    def test_an_escalated_record_rearms_after_15_minutes(self):
        """should_rearm existed and nothing called it: an escalation was permanent (W5 rig)."""
        import time

        now = time.time()
        rec = T.Record(sid="abcdef01-0000-0000-0000-000000000001", record_id="r1")
        rec.phase, rec.substate, rec.escalated = "PANE-GONE", "R", True
        rec.last_error = T.LastError(cls="DETERMINISTIC", fingerprint="f", at=now - 60)
        ctx = M.Ctx(self.paths, None, self.home)
        M.store.ensure_dirs(self.paths)
        ctx.records = {rec.sid: rec}
        snap = _snap(now, self.tmp)
        M._derive(ctx, snap, now)
        self.assertTrue(rec.escalated)  # a minute in: still escalated
        rec.last_error.at = now - 901
        M._derive(ctx, snap, now)
        self.assertFalse(rec.escalated)
        self.assertIn("rearm", [e["ev"] for e in self._events()])

    def test_a_move_in_its_relaunch_gap_is_owned_for_a_bounded_time(self):
        """W5 rig N=5: every confirmed move read as an unowned §4.4 defect in its relaunch gap (no
        live process, no wait). IN-FLIGHT is owned for IN_FLIGHT_MAX_S after confirm, then not."""
        import time

        now = time.time()
        rec = T.Record(sid="abcdef01-0000-0000-0000-000000000001", record_id="r1")
        rec.phase, rec.substate = "PRE-MOVE", "IN-FLIGHT"
        rec.timeline.confirmed = now - 30
        ctx = M.Ctx(self.paths, None, self.home)
        M.store.ensure_dirs(self.paths)
        ctx.records = {rec.sid: rec}
        snap = T.Snapshot(wall=now, uptime_raw=0.0, panes={}, sessions={})
        self.assertEqual(M._invariant(ctx, snap, now), 0)
        self.assertNotIn("defect", rec.close)
        rec.timeline.confirmed = now - M.IN_FLIGHT_MAX_S - 1
        self.assertEqual(M._invariant(ctx, snap, now), 1)
        self.assertTrue(rec.close.get("defect"))
        rec.substate = (
            None  # CONTROL: the gap before the fix (PRE-MOVE/None) is a defect at once
        )
        rec.timeline.confirmed = now - 30
        self.assertEqual(M._invariant(ctx, snap, now), 1)

    def _rec(self, phase, target="next4"):
        rec = T.Record(sid="abcdef01-0000-0000-0000-000000000001", record_id="r1")
        rec.phase, rec.target_acct, rec.pane = phase, target, (5, 7)
        return rec

    def test_command_a_husk_never_emits_an_empty_launcher(self):
        """W5 rig: rec.bundle was never set, so A-husk and B always died DETERMINISTIC."""
        ctx = M.Ctx(self.paths, None, self.home)
        M.store.ensure_dirs(self.paths)
        rec = self._rec("HUSK-RETIRED")
        self.assertEqual(
            M._command(ctx, rec, "A-husk"), []
        )  # no bundle: a wait, no spawn
        self.assertIsNotNone(rec.next_eligible_at)
        self.assertIn("no-launcher", [e["ev"] for e in self._events()])
        d = os.path.join(self.home, ".reso", "limit-recover", rec.sid, "bundle-1")
        os.makedirs(d)
        with open(os.path.join(d, "MANIFEST.json"), "w") as fh:
            json.dump({"record_id": "r1", "target": "next4"}, fh)
        launcher = os.path.join(d, "lr-launch-abcdef01-x.sh")
        open(launcher, "w").close()
        argv = M._command(ctx, rec, "A-husk")
        self.assertEqual(argv[argv.index("--resume-launcher") + 1], launcher)

    def test_daemon_loop_starts_and_runs_a_pass(self):
        """W5 rig: the long-running path had never started (Caffeinate() without its pid)."""

        class Stop(Exception):
            pass

        ctx = M.Ctx(self.paths, None, self.home)
        summary = {"open": 0}
        with (
            mock.patch.object(M, "run_pass", return_value=summary) as rp,
            mock.patch.object(M, "wait_for_change", side_effect=Stop),
        ):
            with self.assertRaises(Stop):
                M.daemon(ctx)
        rp.assert_called_once()
        self.assertTrue(os.path.exists(self.paths.heartbeat))


if __name__ == "__main__":
    unittest.main()
