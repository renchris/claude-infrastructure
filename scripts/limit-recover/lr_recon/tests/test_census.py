"""census: one bucket per session in order, the ruled defaults and their switches, records, stale."""

import os
import tempfile
import unittest

from lr_recon import census as C
from lr_recon import plan
from lr_recon import types as T

L = "Tue Sep 29 11:19:17 2026"
NOW = 1_790_000_000.0
LIMIT = {"limit": True, "kind": "limit", "cap": "seven_day", "resets_at": NOW + 7200}


def _fact(scope="7d", resets=NOW + 7200, contradicted=False):
    return {
        "next3.%s" % scope: T.Fact(
            acct="next3",
            scope=scope,
            resets_at=resets,
            observed_at=NOW - 60,
            contradicted=contradicted,
        )
    }


class CensusBuckets(unittest.TestCase):
    def setUp(self):
        self.cwd = tempfile.mkdtemp()
        self.pane = T.PaneObs(
            kitty_pid=5,
            window_id=7,
            sock="s",
            root_pid=20,
            root_lstart=L,
            root_shape="shell",
            state="claude",
        )
        self.snap = T.Snapshot(wall=NOW, uptime_raw=0.0, panes={"5:7": self.pane})

    def _s(self, last=None, **kw):
        base = dict(
            sid="abcdef01-x",
            acct="next3",
            cfg="/c",
            cwd=self.cwd,
            pane=(5, 7),
            holders=[
                T.HolderObs(pid=10, lstart=L, cfg="/c", src="registry", pane=(5, 7))
            ],
            transcript=T.TranscriptObs(
                path="/t.jsonl",
                last=dict(LIMIT if last is None else last),
                at_rest=True,
            ),
            registry_name="p",
        )
        base.update(kw)
        return T.SessionObs(**base)

    def b(self, s, facts=None, env=None):
        return C.bucket(
            s, self.snap, _fact() if facts is None else facts, NOW, env or {}
        )

    def test_limited(self):
        self.assertEqual(self.b(self._s()).name, "LIMITED")

    def test_teammate_and_splitbrain_beat_limited(self):
        s = self._s(transcript=T.TranscriptObs(path="/t", last=LIMIT, teammate=True))
        self.assertEqual(self.b(s).name, "TEAMMATE")
        s = self._s(
            holders=[
                T.HolderObs(10, L, "/c", "registry"),
                T.HolderObs(11, L, "/c", "session-row", bg=True),
            ]
        )
        self.assertEqual(self.b(s).name, "SPLIT-BRAIN")

    def test_iterm_impossible_team(self):
        self.assertEqual(self.b(self._s(registry_name="iterm:x")).name, "HOLD:iterm")
        self.assertEqual(
            self.b(self._s(transcript=T.TranscriptObs())).name, "IMPOSSIBLE"
        )
        self.assertEqual(self.b(self._s(cwd="/nonexistent/gone")).reason, "cwd-gone")
        # a brief that merely names the lead's '@session-<sid8>' tag is not a member (D4.1)
        self.snap.procs[98] = T.ProcRow(
            98, 1, "S", L, "claude -p ping w@session-abcdef01"
        )
        self.assertNotEqual(self.b(self._s()).name, "HELD:team")
        member = "claude --agent-id w@session-abcdef01 --parent-session-id abcdef01-x"
        self.snap.procs[97] = T.ProcRow(97, 1, "Z", L, member)  # a zombie is not live
        self.assertNotEqual(self.b(self._s()).name, "HELD:team")
        self.assertFalse(
            C.is_member_argv(member, "abcdef01")
        )  # a sid prefix is not the sid
        self.snap.procs[99] = T.ProcRow(
            99,
            1,
            "S",
            L,
            "claude --agent-id w@session-abcdef01 --parent-session-id abcdef01-x",
        )
        self.assertEqual(self.b(self._s()).name, "HELD:team")
        self.assertNotIn(
            "unruled", self.b(self._s()).reason
        )  # D4.10: decision 4 is ruled

    def test_focus_default_moves_and_off_holds(self):
        # Decision 7, ruled 2026-09-30: a focused pane moves by default; =off is the kill switch.
        self.pane.is_focused = True
        self.assertEqual(self.b(self._s()).name, "LIMITED")
        for v in ("on", "yes", ""):
            self.assertEqual(
                self.b(self._s(), env={"LR_MOVE_FOCUSED": v}).name, "LIMITED", v
            )
        held = self.b(self._s(), env={"LR_MOVE_FOCUSED": "off"})
        self.assertEqual(held.name, "HOLD-FOCUS")
        self.assertNotIn("unruled", held.reason)

    def test_bgwork(self):
        ship = T.BgWork(kind="shell", pid=3, ship_land=True)
        b = self.b(self._s(bg_work=[ship]))
        self.assertEqual((b.name, b.detail), ("HOLD-BGWORK", "ship-land"))
        watcher = T.BgWork(kind="shell", pid=3, watcher_only=True)
        self.assertEqual(self.b(self._s(bg_work=[watcher])).name, "LIMITED")

    def test_stay_and_launcher(self):
        self.assertEqual(self.b(self._s(), facts=_fact(resets=NOW + 600)).name, "STAY")
        self.pane.root_shape = "launcher"
        self.assertEqual(self.b(self._s()).name, "LAUNCHER-ROOTED")

    # ── W7h defect 1: the block ends at the LATEST reset, of the facts and the death record ──────

    def _five_hour(self, resets):
        return self._s(last=dict(LIMIT, cap="five_hour", resets_at=resets))

    def test_a_new_5h_limit_is_not_filed_under_an_older_7d_fact(self):
        """next4, 2026-10-04: the Oct-1 7d fact (resets 09:00Z) was still unexpired when the 5h cap
        (resets 09:40Z) hit; 14 sessions were filed scope 7d in the older 7d cohort."""
        s = self._five_hour(NOW + 6000)
        for facts in (
            _fact("7d", NOW + 3600),  # the death record alone names the 5h reset
            dict(_fact("7d", NOW + 3600), **_fact("5h", NOW + 6000)),
        ):
            b = self.b(s, facts=facts)
            self.assertEqual(
                (b.name, b.scope, b.resets_at), ("LIMITED", "5h", NOW + 6000)
            )
            cid = C.cohort_id(b.acct, b.scope, b.resets_at)
            self.assertEqual(cid, "next3-5h-%d" % (NOW + 6000))
            rec = C.new_record(b, s, self.pane, cid, "census", True, NOW)
            self.assertEqual((rec.scope, rec.cohort_id), ("5h", cid))

    def test_the_wake_is_at_the_5h_reset_not_the_older_7d_one(self):
        # the 7d fact resets inside the 15-min stay rule; the 5h cap does not: no in-place stay
        s = self._five_hour(NOW + 3000)
        self.assertEqual(self.b(s, facts=_fact("7d", NOW + 300)).name, "LIMITED")
        # both inside it: the stay's wake is the 5h reset, the later one
        s = self._five_hour(NOW + 800)
        b = self.b(s, facts=_fact("7d", NOW + 300))
        self.assertEqual((b.name, b.scope, b.resets_at), ("STAY", "5h", NOW + 800))
        rec = C.new_record(b, s, self.pane, "c", "census", True, NOW)
        self.assertEqual((rec.substate, rec.wait.eta), ("WAIT_RESET", NOW + 800))

    def test_a_later_7d_fact_binds_over_a_5h_death(self):
        s = self._five_hour(NOW + 3000)
        b = self.b(s, facts=_fact("7d", NOW + 7200))
        self.assertEqual((b.scope, b.resets_at), ("7d", NOW + 7200))
        self.assertEqual(
            C.cohort_id(b.acct, b.scope, b.resets_at), "next3-7d-%d" % (NOW + 7200)
        )
        # a death whose own reset has passed binds nothing, and auth has no reset to outlast
        b = self.b(self._five_hour(NOW - 600), facts=_fact("7d", None))
        self.assertEqual((b.scope, b.resets_at), ("7d", None))
        # with no reset on the fact, a death reset still ahead is the one known end of the block
        b = self.b(self._five_hour(NOW + 600), facts=_fact("7d", None))
        self.assertEqual((b.scope, b.resets_at), ("5h", NOW + 600))
        b = self.b(self._five_hour(NOW + 3000), facts=_fact("auth", None))
        self.assertEqual((b.scope, b.resets_at), ("auth", None))

    # ── W7h defect 2: a limited session with an operator draft is held, never a mover ──────────

    def test_a_limited_session_with_a_draft_is_held(self):
        s = self._s(composer="draft")
        b = self.b(s)
        self.assertEqual((b.name, b.kind), ("HOLD-DRAFT", "limited"))
        rec = C.new_record(b, s, self.pane, "c", "census", True, NOW)
        self.assertEqual((rec.substate, rec.wait.reason), ("HOLD-DRAFT", "HOLD-DRAFT"))
        self.assertEqual((rec.wait.max_age_s, rec.wait.eta), (900, None))
        self.assertEqual(plan.movers([rec], self.snap, NOW), [])
        # it holds before the in-place stay too: the wake types into the same composer
        stay = _fact(resets=NOW + 600)
        self.assertEqual(self.b(s, facts=stay).name, "HOLD-DRAFT")
        # background work is the earlier hold
        s.bg_work = [T.BgWork(kind="shell", pid=3)]
        self.assertEqual(self.b(s).name, "HOLD-BGWORK")

    def test_a_limited_session_with_no_affirmative_draft_moves_as_before(self):
        for composer in ("empty", "", "unknown"):
            s = self._s(composer=composer)
            self.assertEqual(self.b(s).name, "LIMITED", composer)
            rec = C.new_record(self.b(s), s, self.pane, "c", "census", True, NOW)
            self.assertEqual(len(plan.movers([rec], self.snap, NOW)), 1)

    def test_idle(self):
        idle = dict(last={}, composer="empty")
        on = {"LR_IDLE_FANOUT": "on"}
        self.assertEqual(self.b(self._s(**idle)).name, "WORKING")
        self.assertEqual(self.b(self._s(**idle), env=on).name, "IDLE-ELIGIBLE")
        self.assertEqual(
            self.b(self._s(**idle), facts=_fact(contradicted=True), env=on).name,
            "WORKING",
        )
        self.assertEqual(
            self.b(self._s(last={}, composer="draft"), env=on).name, "HOLD-DRAFT"
        )
        self.assertEqual(
            self.b(self._s(**idle), facts=_fact(resets=NOW + 1200), env=on).name,
            "WORKING",
        )


class CensusRecords(unittest.TestCase):
    def test_origin_sticky_and_plan_only(self):
        s = T.SessionObs(sid="abcdef01-x", acct="next3", cfg="/c", pid=10, lstart=L)
        b = T.Bucket(sid=s.sid, name="LIMITED", acct="next3", scope="7d", resets_at=NOW)
        recs = {}
        rec, created = C.upsert(recs, b, s, None, "hook", "c1", False, NOW)
        self.assertTrue(created and rec.plan_only)
        rec2, created2 = C.upsert(recs, b, s, None, "cc-lr", "c1", False, NOW)
        self.assertIs(rec2, rec)
        self.assertFalse(created2 or rec.plan_only)
        C.upsert(recs, b, s, None, "hook", "c1", False, NOW)
        self.assertEqual((rec.origin, rec.plan_only), ("cc-lr", False))
        self.assertEqual(rec.record_id, "recon:c1:abcdef01:1")

    def test_pre_move_source_cfg_follows_the_observed_session(self):
        # W5b canary 1: a record made while the census read a `next` row through the ~/.claude
        # alias kept source_cfg ~/.claude, and every later move of it was refused before planning
        s = T.SessionObs(
            sid="abcdef01-x", acct="next", cfg="/h/.claude", pid=10, lstart=L
        )
        b = T.Bucket(
            sid=s.sid, name="IDLE-ELIGIBLE", acct="next", scope="5h", resets_at=NOW
        )
        recs = {}
        rec, _ = C.upsert(recs, b, s, None, "fanout", "c1", True, NOW)
        self.assertEqual(rec.source_cfg, "/h/.claude")
        s2 = T.SessionObs(
            sid=s.sid, acct="next", cfg="/h/.claude-next", pid=10, lstart=L
        )
        C.upsert(recs, b, s2, None, "fanout", "c1", True, NOW)
        self.assertEqual(rec.source_cfg, "/h/.claude-next")
        # past PRE-MOVE the swap is settle's: an observation on the target never rewrites it
        rec.phase = "RELAUNCHED"
        s3 = T.SessionObs(
            sid=s.sid, acct="next4", cfg="/h/.claude-quaternary", pid=11, lstart=L
        )
        C.upsert(recs, b, s3, None, "fanout", "c1", True, NOW)
        self.assertEqual(rec.source_cfg, "/h/.claude-next")
        # and never across accounts while PRE-MOVE either
        rec.phase = "PRE-MOVE"
        C.upsert(recs, b, s3, None, "fanout", "c1", True, NOW)
        self.assertEqual(rec.source_cfg, "/h/.claude-next")

    def test_new_record_carries_its_death_key(self):
        """W5 rig 80294ba4: a closed record must know which death it recovered (handled_death)."""
        last = dict(limit=True, kind="limit", uuid="u", ts="t")
        s = T.SessionObs(
            sid="abcdef01-x",
            acct="next3",
            cfg="/c",
            pid=10,
            lstart=L,
            transcript=T.TranscriptObs(path="/t.jsonl", last=last),
        )
        b = T.Bucket(sid=s.sid, name="LIMITED", acct="next3", scope="7d", resets_at=NOW)
        rec, _created = C.upsert({}, b, s, None, "census", "c1", False, NOW)
        self.assertEqual(rec.close["death"], "u@t")
        rec.terminal = T.Terminal(outcome="CLOSED", at=NOW)
        self.assertTrue(C.handled_death(rec, s))
        s.transcript.last = dict(last, ts="t2")
        self.assertFalse(C.handled_death(rec, s))

    def test_cohort_id_safe(self):
        self.assertEqual(
            C.cohort_id("next3", "model:opus", 12.7), "next3-model_opus-12"
        )

    def test_cohort_resets_reads_the_cid_back(self):
        """The reset is the cohort's key, so a rebuilt cohort takes it from its own id (defect A)."""
        for scope, resets in (
            ("7d", 1791025200.0),
            ("model:claude-opus-5-5", 1790000000.0),
        ):
            self.assertEqual(
                C.cohort_resets(C.cohort_id("next2", scope, resets)), resets
            )
        self.assertIsNone(C.cohort_resets(C.cohort_id("next2", "7d", None)))

    def test_stale_reconcile(self):
        tmp = tempfile.mkdtemp()
        tp = os.path.join(tmp, "s.jsonl")
        open(tp + ".handed-off", "w").close()
        snap = T.Snapshot(wall=NOW, uptime_raw=0.0)
        reqs = [
            T.Request(sid="a", origin="hook", raw={"transcript_path": tp}),
            T.Request(sid="b", origin="hook", raw={}),
            T.Request(
                sid="c",
                origin="hook",
                raw={"transcript_path": os.path.join(tmp, "c.jsonl")},
            ),
        ]
        open(os.path.join(tmp, "c.jsonl"), "w").close()
        rec = T.Record(sid="d", record_id="r")
        rec.timeline.detected = NOW - 100
        out = C.stale_reconcile({"d": rec}, reqs, snap, NOW - 50, NOW)
        got = {sid: reason for sid, _v, reason in out}
        self.assertIn("tombstoned", got["a"])
        self.assertIn("no transcript", got["b"])
        self.assertEqual(got["c"], "dead-before-claim")
        self.assertEqual(rec.substate, "PARKED-REBOOT")

    def test_a_reboot_park_is_a_named_pre_move_wait_set_once(self):
        """A record parked in a moving phase kept its phantom seat, and one an older daemon parked
        kept its HOLD:iterm wait; a correct park is left alone, so its event fires once."""
        rec = T.Record(sid="p", record_id="r", phase="RELAUNCHED", target_acct="next3")
        rec.substate, rec.timeline.planned = "UNPROMPTED", NOW - 100
        self.assertEqual(len(plan.phantom_rows([rec])), 1)
        old = T.Record(sid="q", record_id="r2", substate="PARKED-REBOOT")
        old.wait, old.timeline.detected = T.Wait(reason="HOLD:iterm"), NOW - 100
        recs, snap = {"p": rec, "q": old}, T.Snapshot(wall=NOW, uptime_raw=0.0)
        out = C.stale_reconcile(recs, [], snap, NOW - 50, NOW)
        self.assertEqual(sorted(sid for sid, _v, _r in out), ["p", "q"])
        for r in (rec, old):
            self.assertEqual(
                (r.phase, r.substate, r.wait.reason),
                ("PRE-MOVE", "PARKED-REBOOT", "PARKED-REBOOT"),
            )
        self.assertEqual(plan.phantom_rows([rec]), [])
        self.assertEqual(C.stale_reconcile(recs, [], snap, NOW - 50, NOW), [])

    def _stores(self):
        """cfg-a holds only the source tombstone, cfg-b the target copy (a confirmed move)."""
        tmp = tempfile.mkdtemp()
        a, b = os.path.join(tmp, "cfg-a"), os.path.join(tmp, "cfg-b")
        for cfg, name in ((a, "m.jsonl.handed-off"), (b, "m.jsonl")):
            os.makedirs(os.path.join(cfg, "projects", "-w"))
            open(os.path.join(cfg, "projects", "-w", name), "w").close()
        holder = T.HolderObs(pid=1, lstart="x", cfg=a, src="registry")
        s = T.SessionObs(sid="m", cfg=a, acct="next", holders=[holder])
        return a, b, T.Snapshot(wall=NOW, uptime_raw=0.0, sessions={"m": s})

    def test_mid_transplant_open_record_is_not_judged(self):
        a, b, snap = self._stores()
        rec = T.Record(sid="m", record_id="r", substate="IN-FLIGHT")
        rec.timeline.planned = NOW - 30
        reqs = [T.Request(sid="m", origin="cc-lr", raw={})]
        out = C.stale_reconcile({"m": rec}, reqs, snap, None, NOW, stores=[a, b])
        self.assertEqual(out, [])

    def test_tombstone_found_across_stores(self):
        a, b, snap = self._stores()
        reqs = [T.Request(sid="m", origin="cc-lr", raw={})]
        out = C.stale_reconcile({}, reqs, snap, None, NOW, stores=[a, b])
        self.assertEqual(
            out,
            [("m", "NOT_NEEDED", "transplanted — the source transcript is tombstoned")],
        )

    def _dead(self):
        """A holderless session as observe returns it, its limit death in cfg-a."""
        cfg = os.path.join(tempfile.mkdtemp(), "cfg-a")
        os.makedirs(os.path.join(cfg, "projects", "-w"))
        fix = os.path.join(
            os.path.dirname(os.path.realpath(__file__)),
            *[".."] * 4,
            "tests",
            "fixtures",
            "lr-recon",
            "jsonl",
            "death-quota-limits.jsonl",
        )
        dst = os.path.join(cfg, "projects", "-w", "d.jsonl")
        with open(fix) as fin, open(dst, "w") as fout:
            fout.write(fin.read())
        return cfg, T.SessionObs(sid="d")

    def test_dead_session_found_in_another_store_is_dead_before_claim(self):
        cfg, s = self._dead()
        snap = T.Snapshot(wall=NOW, uptime_raw=0.0, sessions={"d": s})
        reqs = [T.Request(sid="d", origin="cc-lr", raw={})]
        out = C.stale_reconcile({}, reqs, snap, None, NOW, stores=[cfg])
        self.assertEqual(out, [("d", "NOT_NEEDED", "dead-before-claim")])

    def test_dead_session_not_needed_record_joins_its_real_cohort(self):
        cfg, s = self._dead()
        rec = C.not_needed_record(
            "d", s, {}, "cc-lr", "dead-before-claim", NOW, [cfg], {"next": cfg}
        )
        self.assertEqual(
            (rec.source_acct, rec.source_cfg, rec.scope), ("next", cfg, "5h")
        )
        self.assertTrue(rec.cohort_id.startswith("next-5h-"), rec.cohort_id)

    def test_stale_reason_not_limited(self):
        s = T.SessionObs(
            sid="x", transcript=T.TranscriptObs(path="", last={"limit": False})
        )
        self.assertIn("no longer LIMITED", C.stale_reason("x", s, "/p", False))


if __name__ == "__main__":
    unittest.main()
