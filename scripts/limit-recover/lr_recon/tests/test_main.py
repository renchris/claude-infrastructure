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
        # admission's probe and token mint shell out to capacity-admit.sh: never from a unit test
        self.probe = mock.patch(
            "lr_recon.admit.Admission.probe", return_value=(True, "admit")
        )
        self.mint = mock.patch(
            "lr_recon.admit.Admission.mint_token", return_value=None
        )
        self.probe.start()
        self.mint.start()
        self.paths = T.Paths.from_env(root=os.path.join(self.tmp, "lr", "recon"))
        os.makedirs(self.paths.requests)
        self.req = os.path.join(
            self.paths.requests, "abcdef01-0000-0000-0000-000000000001.json"
        )
        with open(self.req, "w") as fh:
            json.dump({"sid": "abcdef01-0000-0000-0000-000000000001"}, fh)

    def tearDown(self):
        self.mint.stop()
        self.probe.stop()
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

    def _pass(self, mode_cap, mode_file=None, ctx=None):
        import time

        now = time.time()
        ctx = ctx or M.Ctx(self.paths, mode_cap, self.home)
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

    def test_mode_flip_reaches_the_page_sink_without_a_restart(self):
        """D6.4: one daemon process, observe then act — the act pass must page."""
        from lr_recon import report

        pages = []
        ctx = M.Ctx(self.paths, None, self.home)
        ctx.reporter = report.Reporter(
            self.paths, "observe", page=pages.append, mail=lambda p, t: None
        )
        self._pass(None, ctx=ctx)
        self.assertEqual(pages, [])
        self._pass(None, mode_file="act\n", ctx=ctx)
        self.assertEqual(ctx.reporter.mode, "act")
        self.assertTrue(pages, "the act pass never reached the sink")

    def test_every_pass_with_a_limited_session_appends_a_focus_row(self):
        """D7.5: focus is logged per pass, append-only (last-pass.json is overwritten)."""
        path = os.path.join(self.paths.shadow, "focus.jsonl")
        for _ in range(2):
            self._pass("observe")
        with open(path, encoding="utf-8") as fh:
            rows = [json.loads(x) for x in fh]
        self.assertEqual(len(rows), 2)
        self.assertEqual(
            (rows[0]["limited"], rows[0]["focused"], rows[0]["held_focus"]), (1, 0, 0)
        )
        snap = _snap(1.0, self.tmp)
        snap.panes["5:7"].is_focused = True
        b = T.Bucket(sid=next(iter(snap.sessions)), name="HOLD-FOCUS")
        row = M._focus_ledger(self.paths, snap, [b], "act", 1.0)
        self.assertEqual((row["focused"], row["held_focus"]), (1, 1))
        idle = T.Bucket(sid=b.sid, name="IDLE-ELIGIBLE", kind="idle")
        self.assertIsNone(M._focus_ledger(self.paths, snap, [idle], "act", 2.0))

    # ── D1.12: admission caps the act path ────────────────────────────────────────────────────
    def _cohort(self, n, accts):
        import time

        now = time.time()
        M.store.ensure_dirs(self.paths)
        open(self.paths.recon_on, "w").close()
        ctx = M.Ctx(self.paths, None, self.home)
        for i in range(n):
            sid = "c%07d-0000-0000-0000-000000000000" % i
            r = T.Record(
                sid=sid,
                record_id="recon:c:%s:1" % sid[:8],
                kind="limited",
                source_acct="next3",
                source_cfg="/c3",
                scope="7d",
                cohort_id="c",
                target_acct=accts[i % len(accts)],
                target_cfg="/t",
                substate="PLANNED",
            )
            ctx.records[sid] = r
        snap = T.Snapshot(wall=now, uptime_raw=0.0)
        return ctx, snap, now

    def _spawned(self, ctx, snap, now):
        with mock.patch.object(M.act, "spawn", return_value=4242) as sp:
            n = M._dispatch(ctx, snap, "act", now)
        return n, [c.args[1] for c in sp.call_args_list]

    def test_a_30_record_cohort_takes_3_first_turns_per_account(self):
        ctx, snap, now = self._cohort(30, ["next"])
        n, recs = self._spawned(ctx, snap, now)
        self.assertEqual(n, 3)  # the pacer: 3 first turns per target account
        self.assertEqual({r.target_acct for r in recs}, {"next"})
        ev = [json.loads(x) for x in open(self.paths.events)]
        self.assertTrue(
            any(e["ev"] == "admit-refused" and "pacer" in e.get("detail", "") for e in ev)
        )

    def test_boot_slots_cap_relaunches_across_accounts(self):
        ctx, snap, now = self._cohort(30, ["a1", "a2", "a3", "a4"])
        n, _recs = self._spawned(ctx, snap, now)
        self.assertEqual(n, M.BootSlots.START)  # 12 pacer slots, 6 boots

    def test_the_frozen_restore_budget_binds(self):
        ctx, snap, now = self._cohort(30, ["a1", "a2", "a3", "a4"])
        # R frozen at 2 before this pass; L_open high so the CPU brake is not what binds
        ctx.admission.enter_active(0, 2, 0, load1=1e6, now=now)
        with mock.patch(
            "lr_recon.admit.Admission.mint_token", side_effect=lambda sid: "/tok/" + sid
        ):
            n, recs = self._spawned(ctx, snap, now)
        self.assertEqual(n, 2)
        self.assertTrue(all(r.admit_token.startswith("/tok/") for r in recs))

    def test_an_engaged_record_frees_its_pacer_slot(self):
        ctx, snap, now = self._cohort(3, ["next"])
        for r in ctx.records.values():
            ctx.admission.pacer_take(r.sid, "next", now)
            r.phase = "ENGAGED"
        M._admission_period(ctx, snap, now)
        self.assertTrue(ctx.admission.pacer_ok("next", now))

    def test_an_idle_move_needs_no_first_turn_admission(self):
        ctx, snap, now = self._cohort(4, ["next"])
        for r in ctx.records.values():
            r.kind = "idle"
        n, _recs = self._spawned(ctx, snap, now)
        self.assertEqual(n, 4)  # no pacer on a relaunch with no prompt

    # ── D1.11 / D4.9 / D4.13: the in-place reset wake ─────────────────────────────────────────
    LEAD = "abcdef01-0000-0000-0000-000000000001"

    def _held(self, sub="HELD:team", eta=1000.0, detail=""):
        import time

        M.store.ensure_dirs(self.paths)
        open(self.paths.recon_on, "w").close()
        ctx = M.Ctx(self.paths, None, self.home)
        snap = _snap(time.time(), self.tmp)
        s = snap.sessions[self.LEAD]
        s.transcript.last_assistant_ok_at = eta - 600  # the last turn before the limit
        snap.procs[77] = T.ProcRow(
            77, 1, "S", L, "claude.exe --agent-id w@session-x --parent-session-id %s" % self.LEAD
        )
        r = T.Record(
            sid=self.LEAD,
            record_id="recon:c:abcdef01:1",
            kind="limited",
            source_acct="next3",
            scope="7d",
            pane=(5, 7),
            substate=sub,
        )
        r.wait = T.Wait(reason=sub, since=0.0, eta=eta, detail=detail)
        ctx.records[self.LEAD] = r
        return ctx, snap, r

    def _due(self, eta=1000.0):
        return eta + M.WAKE_AFTER_S + M.jitter_s(self.LEAD)

    def test_a_held_lead_past_its_reset_is_woken_in_its_own_pane(self):
        ctx, snap, r = self._held()
        self.assertEqual(M._wakes(ctx, snap, {}, self._due() - 1), 0)  # not yet
        self.assertEqual(M._wakes(ctx, snap, {}, self._due()), 1)
        self.assertEqual(ctx.actions[self.LEAD], "wake")
        with mock.patch.object(M.act, "spawn", return_value=4242) as sp:
            self.assertEqual(M._dispatch(ctx, snap, "act", self._due()), 1)
        which, argv = sp.call_args.args[2], sp.call_args.args[3]
        self.assertEqual(which, "C")
        self.assertEqual(argv[3], "lr-recon-wake")
        self.assertEqual(argv[4], "7")  # the lead's OWN pane; nothing else is touched
        self.assertIn("lr_focus_gate", argv[2])
        with open(argv[5], encoding="utf-8") as fh:
            text = fh.read()
        self.assertTrue(text.startswith("continue"))
        self.assertIn("teammate", text)
        self.assertNotIn("/limit-recover", text)
        self.assertNotIn("/exit", text)
        # typed once for this reset: the next pass waits for the turn instead of retyping
        ctx.actions.clear()
        self.assertEqual(M._wakes(ctx, snap, {}, self._due() + 30), 0)

    def test_a_wake_refused_by_admission_is_tried_again(self):
        """W6d rig: a CPU-brake refusal marked the wake typed, so it never came back."""
        ctx, snap, r = self._held()
        self.assertEqual(M._wakes(ctx, snap, {}, self._due()), 1)
        with mock.patch.object(M, "_admit", return_value=(False, "cpu")):
            with mock.patch.object(M.act, "spawn", return_value=4242) as sp:
                self.assertEqual(M._dispatch(ctx, snap, "act", self._due()), 0)
        sp.assert_not_called()
        self.assertNotIn("wake_eta", r.close)
        ctx.actions.clear()
        self.assertEqual(M._wakes(ctx, snap, {}, self._due() + 5), 1)

    def test_a_fresh_turn_after_the_reset_closes_it_as_continued_in_place(self):
        ctx, snap, r = self._held()
        snap.sessions[self.LEAD].transcript.last_assistant_ok_at = 1001.0
        self.assertEqual(M._wakes(ctx, snap, {}, self._due()), 0)
        self.assertEqual(r.terminal.outcome, "CLOSED")
        self.assertIn("continued in place", r.terminal.proof)
        line = M.report.dod_line(self.paths, [r])
        self.assertIn("CLOSED 1/1 (ENGAGED 0, MOVED 0, IN-PLACE 1)", line)

    def test_a_lead_continued_in_place_is_not_re_recorded_as_held(self):
        """W6d rig: after the wake closed a lead IN-PLACE, its members were still live, and the next
        pass opened a fresh idle HELD:team record with no reset to wake at, held and paged forever."""
        ctx, snap, r = self._held()
        r.terminal = T.Terminal(outcome="CLOSED", proof="continued in place", at=1.0)
        s = snap.sessions[self.LEAD]
        s.transcript.last = {"kind": "ok"}  # the lead answered: no longer limited
        M.store.ensure_dirs(self.paths)
        M._census(ctx, snap, {}, [], "observe", 2000.0)
        self.assertIs(ctx.records[self.LEAD], r)
        # CONTROL: a lead still LIMITED with live members is recorded HELD:team, as before
        ctx2, snap2, _r = self._held()
        del ctx2.records[self.LEAD]
        M._census(ctx2, snap2, {}, [], "observe", 2000.0)
        self.assertEqual(ctx2.records[self.LEAD].substate, "HELD:team")

    def test_the_wake_chooses_nothing_without_members_or_headroom(self):
        ctx, snap, r = self._held()
        del snap.procs[77]  # members gone: the census releases it to an ordinary move
        self.assertEqual(M._wakes(ctx, snap, {}, self._due()), 0)
        ctx, snap, r = self._held()
        later = {"next3.7d": T.Fact(acct="next3", scope="7d", resets_at=9e9)}
        self.assertEqual(M._wakes(ctx, snap, later, self._due()), 0)  # limited again
        ctx, snap, r = self._held()
        r.close["wake_failed"] = "the composer holds a draft (rc 3)"
        self.assertEqual(M._wakes(ctx, snap, {}, self._due()), 0)  # paged, never retyped

    def test_a_stay_is_woken_at_once_with_a_plain_continue(self):
        ctx, snap, r = self._held(sub="WAIT_RESET", eta=500.0, detail="stay")
        del snap.procs[77]
        self.assertEqual(M._wakes(ctx, snap, {}, 500.0), 1)
        with mock.patch.object(M.act, "spawn", return_value=4242) as sp:
            M._dispatch(ctx, snap, "act", 500.0)
        with open(sp.call_args.args[3][5], encoding="utf-8") as fh:
            self.assertEqual(fh.read(), "continue\n")

    # ── D6.7: the held draft is snapshotted (a read) and quoted in the page ───────────────────
    def _snapper(self, snap_rc=0):
        """snap is stubbed (no kitty in a unit test); row runs W6b's REAL parser on W0's frame."""
        repo = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", ".."))
        real = os.path.join(repo, "scripts", "lib", "lr-composer-snapshot.sh")
        frame = os.path.join(repo, "tests", "fixtures", "lr-recon", "screens", "composer-draft-2.1.284.txt")
        if not os.path.exists(real):
            self.skipTest("lr-composer-snapshot.sh not on this tree")
        stub = os.path.join(self.tmp, "snapper")
        with open(stub, "w") as fh:
            fh.write(
                '#!/bin/bash\necho "$*" >> "%s/snap.argv"\n'
                'case "$1" in snap) echo "%s"; exit %d ;; '  # a failure may still print
                'row) exec /bin/bash "%s" row "$2" ;; esac\n'
                % (self.tmp, frame, snap_rc, real)
            )
        os.chmod(stub, 0o755)
        return stub

    def test_a_held_draft_is_snapshotted_once_per_attempt_and_quoted(self):
        M.store.ensure_dirs(self.paths)
        ctx = M.Ctx(self.paths, None, self.home)
        snap = _snap(1.0, self.tmp)
        r = T.Record(sid=self.LEAD, record_id="r1", kind="limited", pane=(5, 7), substate="HOLD-DRAFT")
        ctx.records[self.LEAD] = r
        with mock.patch.dict(os.environ, {"LR_COMPOSER_SNAP_BIN": self._snapper()}):
            self.assertEqual(M._draft_snapshots(ctx, snap), 1)
            self.assertEqual(M._draft_snapshots(ctx, snap), 0)  # once per attempt
            r.attempt += 1
            self.assertEqual(M._draft_snapshots(ctx, snap), 1)
        with open(os.path.join(self.tmp, "snap.argv")) as fh:
            first = fh.readline().split()
        self.assertEqual(first[:4], ["snap", "7", self.LEAD, "HOLD-DRAFT"])
        self.assertEqual(first[4:], ["--focused", "0", "--limited", "1"])
        self.assertTrue(r.close["draft_text"].startswith("Use the Bash tool with run_in_background"))
        r.wait = T.Wait(reason="HOLD-DRAFT", since=0.0, max_age_s=900)
        from lr_recon import report

        line = report.residue_needs(r, 2000.0)
        self.assertIn('the draft reads: "Use the Bash tool', line)
        pages = []
        rep = report.Reporter(self.paths, "act", page=pages.append, now=lambda: 2000.0)
        cohort = T.Cohort(cid="c", acct="next3", scope="7d")
        self.assertIn('the draft reads: "Use the Bash tool', rep.max_age_page(cohort, r))

    def test_every_pass_takes_the_draft_snapshots(self):
        with mock.patch.object(M, "_draft_snapshots", return_value=0) as ds:
            self._pass("observe")
        ds.assert_called_once()

    def test_a_failed_snapshot_records_nothing_and_says_so(self):
        M.store.ensure_dirs(self.paths)
        ctx = M.Ctx(self.paths, None, self.home)
        r = T.Record(sid=self.LEAD, record_id="r1", kind="limited", pane=(5, 7), substate="HOLD-DRAFT")
        ctx.records[self.LEAD] = r
        with mock.patch.dict(os.environ, {"LR_COMPOSER_SNAP_BIN": self._snapper(snap_rc=1)}):
            self.assertEqual(M._draft_snapshots(ctx, _snap(1.0, self.tmp)), 0)
        self.assertNotIn("draft_text", r.close)
        self.assertIn("draft-snap-none", [e["ev"] for e in self._events()])

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

    # ── D1.10: ownership ends with the record ─────────────────────────────────────────────────
    def _own(self, rec):
        M.store.ensure_dirs(self.paths)
        me = T.RunClaimHolder(pid=os.getpid(), lstart="x", owner="lr-reconciler")
        me.record_id = rec.record_id
        v = M.store.take_ownership(
            self.paths, rec, me, lambda pid, ls: True, lambda pid: "", 1.0
        )
        self.assertNotEqual(v, "owned-by-other")

    def _defers(self, sid):
        from lr_recon import fence

        open(self.paths.recon_on, "w").close()
        return fence.defers(self.paths, sid, "", 1e12, 0.0, lambda p, l: False)

    def test_a_closed_records_sid_is_not_owned(self):
        sid = "abcdef01-0000-0000-0000-000000000009"
        ctx = M.Ctx(self.paths, None, self.home)
        r = T.Record(sid=sid, record_id="r9")
        ctx.records[sid] = r
        self._own(r)
        self.assertEqual(M._release_terminal(ctx), 0)  # open: kept
        self.assertEqual(self._defers(sid)[1], "lapsed")
        r.terminal = T.Terminal(outcome="CLOSED", at=2.0)
        self.assertEqual(M._release_terminal(ctx), 1)
        self.assertEqual(self._defers(sid), (False, "not-owned"))
        self.assertIsNone(M.store.read_claim(self.paths, sid))

    def test_every_pass_releases_a_closed_records_fence(self):
        sid = "abcdef01-0000-0000-0000-000000000009"
        ctx = M.Ctx(self.paths, None, self.home)
        r = T.Record(sid=sid, record_id="r9")
        r.terminal = T.Terminal(outcome="CLOSED", at=1.0)
        self._own(r)
        ctx.records[sid] = r
        self._pass("observe", ctx=ctx)
        self.assertEqual(self._defers(sid), (False, "not-owned"))

    def test_abandon_closes_and_releases(self):
        sid = "abcdef01-0000-0000-0000-000000000009"
        ctx = M.Ctx(self.paths, None, self.home)
        r = T.Record(sid=sid, record_id="r9", escalated=True)
        ctx.records[sid] = r
        self._own(r)
        path = M.request_abandon(self.paths, sid)
        self.assertTrue(path.endswith(sid + ".abandon.json"))
        self.assertEqual(M._abandon(ctx, 5.0), 1)
        self.assertEqual(
            (r.terminal.outcome, r.terminal.proof), ("IMPOSSIBLE", "abandoned by operator")
        )
        M._release_terminal(ctx)
        self.assertEqual(self._defers(sid), (False, "not-owned"))
        self.assertFalse(os.path.exists(path))
        self.assertEqual(M._abandon(ctx, 6.0), 0)  # consumed once

    def test_abandon_cli_writes_the_ctl_file(self):
        with redirect_stdout(io.StringIO()) as out:
            self.assertEqual(M.main(["--abandon", "abcdef01-x"]), 0)
        self.assertTrue(os.path.exists(out.getvalue().strip()))
        self.assertEqual(M.main(["--abandon", "../x"]), 2)

    def test_rearms_are_capped_then_released(self):
        from lr_recon import classify

        sid = "abcdef01-0000-0000-0000-000000000009"
        M.store.ensure_dirs(self.paths)
        ctx = M.Ctx(self.paths, None, self.home)
        r = T.Record(sid=sid, record_id="r9")
        ctx.records[sid] = r
        snap = T.Snapshot(wall=0.0, uptime_raw=0.0)
        t = 0.0
        for i in range(classify.REARM_CAP + 1):
            r.escalated = True
            r.last_error = T.LastError(cls="DETERMINISTIC", fingerprint="f", detail="d", at=t)
            t += classify.REARM_S
            M._derive(ctx, snap, t)
            if i < classify.REARM_CAP:
                self.assertTrue(r.open, "re-arm %d" % (i + 1))
                self.assertFalse(r.escalated)
        self.assertEqual(r.terminal.outcome, "IMPOSSIBLE")
        self.assertIn("re-arms", r.terminal.proof)
        # an operator refire resets the automatic count
        r2 = T.Record(sid="s2", record_id="r2", escalated=True)
        r2.close["rearms"] = classify.REARM_CAP
        ctx.records["s2"] = r2
        self._ctl("s2")
        M._refire(ctx, t)
        self.assertNotIn("rearms", r2.close)

    def test_own_takes_over_a_fence_left_by_a_finished_record(self):
        sid = "abcdef01-0000-0000-0000-000000000009"
        old = T.Record(sid=sid, record_id="old-1")
        self._own(old)
        ctx = M.Ctx(self.paths, None, self.home)
        new = T.Record(sid=sid, record_id="new-2", substate="PLANNED", target_acct="next4")
        ctx.records[sid] = new
        with mock.patch.object(plan, "assign_many", return_value=0):
            M._own_and_charge(ctx, 3.0)
        self.assertEqual(M.store.read_fence(self.paths, sid).record_id, "new-2")

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

    def _flags(self, recon_on=False, autorecover=False, recon_marker=False):
        os.makedirs(self.paths.root, exist_ok=True)
        for path, want in (
            (self.paths.recon_on, recon_on),
            (self.paths.autorecover_on, autorecover),
            (self.paths.recon_autorecover_on, recon_marker),
        ):
            if want:
                open(path, "w").close()
            elif os.path.exists(path):
                os.unlink(path)

    def test_zero_human_scope_needs_both_markers(self):
        """D1.9: a hook-origin record acts (plan_only False) only with autorecover.on AND the
        reconciler's own recon/autorecover.on — all four states."""
        for autorecover in (False, True):
            for marker in (False, True):
                self._flags(autorecover=autorecover, recon_marker=marker)
                ctx, _s, _am, _popen = self._pass("observe")
                rec = next(iter(ctx.records.values()))
                self.assertEqual(
                    rec.plan_only,
                    not (autorecover and marker),
                    (autorecover, marker),
                )
        self._flags()
        self._pass(None, mode_file="act\n")
        self.assertFalse(
            os.path.exists(self.paths.recon_autorecover_on),
            "the daemon must never create its own zero-human marker",
        )

    def test_act_mode_never_claims_a_hook_request_it_may_not_act_on(self):
        """D1.9: the stale NOT_NEEDED claim drains the request from the poller too, so it needs
        recon.on AND acting scope. A hook request survives act mode without either."""
        import time

        now = time.time()
        snap = _snap(now, self.tmp)
        s = next(iter(snap.sessions.values()))
        s.holders, s.pid, s.pane = [], 0, None  # dead ⇒ the stale reconcile says NOT_NEEDED
        M.store.ensure_dirs(self.paths)
        for flags in (
            {},  # recon.on absent: act mode is not acting
            {"recon_on": True},  # acting, but a hook request is outside its scope
            {"recon_on": True, "autorecover": True},  # the poller's switch alone
            {"autorecover": True, "recon_marker": True},  # scope, but not acting
        ):
            self._flags(**flags)
            ctx = M.Ctx(self.paths, None, self.home)
            M._census(ctx, snap, {}, M.store.list_requests(self.paths), "act", now)
            self.assertTrue(os.path.exists(self.req), flags)
            self.assertNotIn(s.sid, ctx.records, flags)
        self._flags(recon_on=True, autorecover=True, recon_marker=True)
        ctx = M.Ctx(self.paths, None, self.home)
        M._census(ctx, snap, {}, M.store.list_requests(self.paths), "act", now)
        self.assertFalse(os.path.exists(self.req), "both markers + recon.on: claimed")

    def test_a_stale_request_leaves_a_terminal_not_needed_member(self):
        """W5 rig: a request for a dead session was claimed NOT_NEEDED and left no cohort member."""
        import time

        now = time.time()
        snap = _snap(now, self.tmp)
        s = next(iter(snap.sessions.values()))
        s.holders, s.pid, s.pane = [], 0, None  # the session is dead: no live holder
        ctx = M.Ctx(self.paths, None, self.home)
        M.store.ensure_dirs(self.paths)
        self._flags(recon_on=True, autorecover=True, recon_marker=True)
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

    def test_a_record_with_a_live_watcher_this_pass_is_not_a_defect(self):
        """W5 rig 0f71c0d5: EXITING/None was paged while the move's own watcher was live."""
        import time

        now = time.time()
        ctx = M.Ctx(self.paths, None, self.home)
        M.store.ensure_dirs(self.paths)
        snap = T.Snapshot(wall=now, uptime_raw=0.0, panes={}, sessions={})
        for phase in ("EXITING", "PRE-MOVE"):
            rec = T.Record(sid="abcdef01-0000-0000-0000-000000000001", record_id="r1")
            rec.phase, rec.substate = phase, None
            ctx.records = {rec.sid: rec}
            rec.close["busy_at"] = now  # this pass's derive saw a live watcher/launcher
            self.assertEqual(M._invariant(ctx, snap, now), 0, phase)
            rec.close["busy_at"] = now - 30  # CONTROL: an earlier pass's is no alibi
            self.assertEqual(M._invariant(ctx, snap, now), 1, phase)

    def _in_flight_pass(self, rec, now):
        ctx = M.Ctx(self.paths, None, self.home)
        M.store.ensure_dirs(self.paths)
        ctx.records = {rec.sid: rec}
        snap = T.Snapshot(wall=now, uptime_raw=0.0, panes={}, sessions={})
        out = {
            "result": T.PhaseResult(phase="PRE-MOVE", action="wait"),
            "evidence": T.Evidence(),
        }
        with mock.patch.object(M.evidence, "derive", return_value=out):
            M._derive(ctx, snap, now)
        return ctx, snap

    def test_in_flight_past_its_bound_fails_then_escalates(self):
        """W5 rig 0c95685d: IN-FLIGHT past IN_FLIGHT_MAX_S with no holder was only flagged, every
        pass, while the lr-fire-resume relay kept live_launcher true; nothing acted."""
        import time

        now = time.time()
        rec = T.Record(sid="abcdef01-0000-0000-0000-000000000001", record_id="r1")
        rec.phase, rec.substate = "PRE-MOVE", "IN-FLIGHT"
        rec.timeline.confirmed = now - 601
        ctx, snap = self._in_flight_pass(rec, now)
        self.assertEqual(rec.last_error.cls, "DETERMINISTIC")
        self.assertIsNotNone(rec.next_eligible_at)
        self.assertFalse(rec.escalated)
        self.assertEqual(M._invariant(ctx, snap, now), 0)
        self.assertIn("in-flight-expired", [e["ev"] for e in self._events()])
        self._in_flight_pass(rec, now)  # the identical failure again
        self.assertTrue(rec.escalated)

    def test_in_flight_inside_its_bound_is_left_alone(self):
        """CONTROL: at 599 s the relaunch gap is still owned."""
        import time

        now = time.time()
        rec = T.Record(sid="abcdef01-0000-0000-0000-000000000001", record_id="r1")
        rec.phase, rec.substate = "PRE-MOVE", "IN-FLIGHT"
        rec.timeline.confirmed = now - 599
        self._in_flight_pass(rec, now)
        self.assertEqual(
            (rec.last_error, rec.next_eligible_at, rec.escalated), (None, None, False)
        )

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

    def test_a_dead_sessions_stale_request_joins_its_accounts_cohort(self):
        """W5 rig N=30: the stale reconcile was never given the account stores, so a dead session's
        NOT_NEEDED member was filed under the orphan cohort unknown-none-0 and the run's cohort
        counted 29 of 30."""
        import shutil
        import time

        now = time.time()
        sid = "abcdef01-0000-0000-0000-000000000009"
        cfg = os.path.join(self.home, ".claude-next")
        proj = os.path.join(cfg, "projects", "-x")
        os.makedirs(proj)
        fx = os.path.join(
            os.path.dirname(__file__),
            "..",
            "..",
            "..",
            "..",
            "tests",
            "fixtures",
            "lr-recon",
            "jsonl",
            "death-quota-limits.jsonl",
        )
        shutil.copy(os.path.realpath(fx), os.path.join(proj, sid + ".jsonl"))
        os.makedirs(os.path.join(self.home, ".claude"), exist_ok=True)
        with open(os.path.join(self.home, ".claude", "accounts.json"), "w") as fh:
            json.dump({"accounts": [{"name": "next", "config_dir": cfg}]}, fh)
        ctx = M.Ctx(self.paths, None, self.home)
        M.store.ensure_dirs(self.paths)
        snap = T.Snapshot(wall=now, uptime_raw=0.0, panes={}, sessions={})
        req = T.Request(sid=sid, origin="cc-lr", path="", raw={})
        self._flags(recon_on=True)  # a cc-lr request needs no zero-human marker, only recon.on
        with mock.patch.object(M.store, "claim_request"):
            M._census(ctx, snap, {}, [req], "act", now)
        rec = ctx.records[sid]
        self.assertEqual(rec.terminal.outcome, "NOT_NEEDED")
        self.assertEqual(rec.source_acct, "next")
        self.assertTrue(rec.cohort_id.startswith("next-"), rec.cohort_id)

    def test_a_second_move_spawn_in_one_attempt_opens_a_new_attempt(self):
        """W5 rig N=30: A's /exit closed the pane, its exit code was unknown, and R went out under
        A's attempt, which the launch-log audit counts as a double typer."""
        import time

        now = time.time()
        rec = T.Record(sid="abcdef01-0000-0000-0000-000000000001", record_id="r1")
        rec.phase, rec.pane, rec.attempt = "PANE-GONE", (5, 7), 1
        rec.close["move_attempt"] = 1  # A already spawned under attempt 1
        ctx = M.Ctx(self.paths, None, self.home)
        ctx.records = {rec.sid: rec}
        snap = _snap(now, self.tmp)
        with (
            mock.patch.object(M.act, "choose", return_value="R"),
            mock.patch.object(M.act, "may_actuate", return_value=(True, "ok")),
            mock.patch.object(M, "_command", return_value=["true"]),
            mock.patch.object(M.act, "spawn", return_value=4242),
            mock.patch.object(M.store, "append_launch") as al,
        ):
            self.assertEqual(M._dispatch(ctx, snap, "act", now), 1)
            self.assertEqual(rec.attempt, 2)
            self.assertIn("attempt=2", al.call_args[0][1])
            self.assertEqual(rec.close["move_attempt"], 2)
            # CONTROL: a first move spawn in a fresh attempt keeps its number
            rec.attempt = 3
            self.assertEqual(M._dispatch(ctx, snap, "act", now), 1)
            self.assertEqual(rec.attempt, 3)

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
