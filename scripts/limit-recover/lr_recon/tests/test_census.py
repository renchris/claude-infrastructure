"""census: one bucket per session in order, safe defaults for unruled decisions, records, stale."""

import os
import tempfile
import unittest

from lr_recon import census as C
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
        self.snap.procs[99] = T.ProcRow(
            99, 1, "S", L, "claude --agent-id w@session-abcdef01"
        )
        self.assertEqual(self.b(self._s()).name, "HELD:team")

    def test_focus_default_hold_and_switch(self):
        self.pane.is_focused = True
        self.assertEqual(self.b(self._s()).name, "HOLD-FOCUS")
        self.assertEqual(
            self.b(self._s(), env={"LR_MOVE_FOCUSED": "on"}).name, "LIMITED"
        )

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

    def test_cohort_id_safe(self):
        self.assertEqual(
            C.cohort_id("next3", "model:opus", 12.7), "next3-model_opus-12"
        )

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
