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


if __name__ == "__main__":
    unittest.main()
