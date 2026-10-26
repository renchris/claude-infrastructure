"""Unit tests for lr_burn.py (the per-session burn meter, account-rotation C2).

Run: python3 -I -m unittest discover -s scripts/limit-recover -p 'test_lr_burn.py' -v
Hermetic: every transcript, sessions dir and utilization log is a fixture under a fresh temp dir.
"""

import json
import os
import subprocess
import sys
import tempfile
import unittest
from datetime import datetime, timezone
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
import lr_burn  # noqa: E402
import idle_gap  # noqa: E402  (on sys.path via lr_burn)

NOW = 1793000000.0


def iso(t):
    return datetime.fromtimestamp(t, timezone.utc).isoformat().replace("+00:00", "Z")


def asst(t, mid, out, cc=0, cr=0, inp=0, stop="end_turn", side=False):
    return {
        "type": "assistant",
        "timestamp": iso(t),
        "isSidechain": side,
        "requestId": "r-" + mid,
        "message": {
            "id": mid,
            "model": "claude-opus-5-5",
            "stop_reason": stop,
            "usage": {
                "input_tokens": inp,
                "output_tokens": out,
                "cache_creation_input_tokens": cc,
                "cache_read_input_tokens": cr,
            },
        },
    }


def user(t, content, meta=False):
    return {
        "type": "user",
        "timestamp": iso(t),
        "isSidechain": False,
        "isMeta": meta,
        "message": {"role": "user", "content": content},
    }


class Fixture(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="lr-burn-test.")
        self.roots = []
        for name, acct in ((".cfg-a", "acctA"), (".cfg-b", "acctB")):
            d = os.path.join(self.tmp, name, "projects")
            os.makedirs(os.path.join(d, "-slug"))
            os.makedirs(os.path.join(self.tmp, name, "sessions"))
            self.roots.append((d, acct))
        self.util = os.path.join(self.tmp, "util.jsonl")

    def tx(self, acct_i, sid, recs, sub=None, mode="a"):
        root = self.roots[acct_i][0]
        if sub:
            d = os.path.join(root, "-slug", sid, "subagents")
            os.makedirs(d, exist_ok=True)
            p = os.path.join(d, "agent-%s.jsonl" % sub)
        else:
            p = os.path.join(root, "-slug", sid + ".jsonl")
        with open(p, mode) as fh:
            for r in recs:
                fh.write(json.dumps(r) + "\n")
        os.utime(p, (NOW, NOW))
        return p

    def util_rows(
        self, acct, pts, reset="2026-11-01T04:00:00Z", h5reset="2026-10-26T16:00:00Z"
    ):
        with open(self.util, "a") as fh:
            for t, wk, h5 in pts:
                fh.write(
                    json.dumps(
                        {
                            "ts": iso(t),
                            "acct": acct,
                            "weekly_pct": wk,
                            "session_pct": h5,
                            "weekly_reset_at": reset,
                            "session_reset_at": h5reset,
                            "stale": False,
                        }
                    )
                    + "\n"
                )

    def run_tick(self, st=None, **kw):
        st = st or lr_burn.new_state()
        kw.setdefault("first_tail", None)
        lr_burn.tick(st, NOW, self.roots, **kw)
        return st


class Pricing(Fixture):
    def test_weights_come_from_idle_gap(self):
        self.assertAlmostEqual(lr_burn.price(0, 1000000, 0, 0), idle_gap.OUT_PP)
        self.assertAlmostEqual(lr_burn.price(0, 0, 1000000, 0), idle_gap.WRITE_PP)
        self.assertAlmostEqual(
            lr_burn.price(0, 0, 0, 1000000), sum(idle_gap.READ_PP) / 2
        )

    def test_dedup_takes_max_output_across_ticks(self):
        # three streamed records of ONE response; the final count arrives in a later tick
        p = self.tx(
            0,
            "s1",
            [asst(NOW - 100, "m1", 3, cc=1000), asst(NOW - 100, "m1", 3, cc=1000)],
        )
        st = self.run_tick()
        self.tx(0, "s1", [asst(NOW - 99, "m1", 800, cc=1000)])
        os.utime(p, (NOW, NOW))
        lr_burn.tick(st, NOW, self.roots, first_tail=None)
        pp = lr_burn.priced(st, NOW)["acctA"]["s1"]
        self.assertAlmostEqual(pp, lr_burn.price(0, 800, 1000, 0))
        self.assertEqual(len(st["msgs"]), 1)

    def test_window_bounds(self):
        self.tx(
            0,
            "s1",
            [
                asst(NOW - 4000, "old", 100),
                asst(NOW - 10, "in", 100),
                asst(NOW + 50, "future", 100),
            ],
        )
        st = self.run_tick()
        self.assertEqual(set(st["msgs"]), {"in"})


class Attribution(Fixture):
    def test_handed_off_copy_is_never_read(self):
        p = self.tx(0, "s1", [asst(NOW - 10, "m1", 100)])
        with open(p) as src, open(p + ".handed-off", "w") as dst:
            dst.write(src.read().replace("m1", "m1-copy"))
        st = self.run_tick()
        self.assertEqual(set(st["msgs"]), {"m1"})

    def test_subagent_burn_goes_to_parent_session(self):
        self.tx(0, "parent", [asst(NOW - 10, "m1", 100)])
        self.tx(0, "parent", [asst(NOW - 5, "m2", 300, side=True)], sub="a1")
        pr = lr_burn.priced(self.run_tick(), NOW)
        self.assertEqual(list(pr["acctA"]), ["parent"])
        self.assertAlmostEqual(pr["acctA"]["parent"], lr_burn.price(0, 400, 0, 0))

    def test_workflow_agents_below_subagents_go_to_parent(self):
        # Workflow agents write one level deeper: <sid>/subagents/workflows/<wf>/agent-*.jsonl
        self.tx(0, "parent", [asst(NOW - 10, "m1", 100)])
        d = os.path.join(self.roots[0][0], "-slug", "parent", "subagents", "workflows", "wf_1")
        os.makedirs(d)
        with open(os.path.join(d, "agent-w.jsonl"), "w") as fh:
            fh.write(json.dumps(asst(NOW - 5, "w1", 500, side=True)) + "\n")
        pr = lr_burn.priced(self.run_tick(), NOW)
        self.assertAlmostEqual(pr["acctA"]["parent"], lr_burn.price(0, 600, 0, 0))

    def test_session_meta(self):
        self.tx(
            0,
            "s1",
            [
                user(NOW - 300, "real prompt"),
                asst(NOW - 290, "m1", 10, cc=5000, cr=100000, inp=3, stop="tool_use"),
                user(NOW - 280, [{"type": "tool_result", "content": "x"}]),
                asst(NOW - 270, "m2", 10, cc=200, cr=105000, inp=2, stop="end_turn"),
                user(NOW - 200, "<task-notification>done</task-notification>"),
                user(
                    NOW - 190,
                    [{"type": "text", "text": "<system-reminder>x</system-reminder>"}],
                ),
                user(NOW - 180, "meta", meta=True),
                asst(NOW - 170, "m3", 10, cc=10, cr=105200, stop="tool_use"),
            ],
        )
        s = self.run_tick()["sess"]["s1"]
        self.assertEqual(s["operator_t"], NOW - 300)
        self.assertEqual(s["last_stop_t"], NOW - 270)
        self.assertEqual(s["ctx"], 105210)


class Incremental(Fixture):
    def recs(self, n):
        return [
            asst(NOW - 3000 + i * 10, "m%d" % i, 50 + i, cc=100 * i, cr=1000)
            for i in range(n)
        ]

    def test_byte_capped_ticks_equal_one_shot(self):
        self.tx(0, "s1", self.recs(60))
        one = lr_burn.priced(self.run_tick(), NOW)
        st, ticks = lr_burn.new_state(), 0
        while lr_burn.tick(st, NOW, self.roots, byte_cap=700, first_tail=None):
            ticks += 1
        self.assertGreater(ticks, 10)
        self.assertAlmostEqual(
            lr_burn.priced(st, NOW)["acctA"]["s1"], one["acctA"]["s1"]
        )

    def test_over_cap_line_is_skipped_and_flagged(self):
        big = user(NOW - 50, "x" * 5000)
        self.tx(0, "s1", [asst(NOW - 60, "m1", 10), big, asst(NOW - 40, "m2", 20)])
        st = lr_burn.new_state()
        for _ in range(40):
            if not lr_burn.tick(st, NOW, self.roots, byte_cap=1024, first_tail=None):
                break
        self.assertEqual(set(st["msgs"]), {"m1", "m2"})
        rows = lr_burn.burn_rows(st, NOW, {"s1": {"pid": 1, "acct": "acctA"}}, {})
        self.assertTrue(rows[0]["partial"])

    def test_first_sight_mid_file_marks_partial(self):
        self.tx(0, "s1", self.recs(60))
        st = lr_burn.new_state()
        lr_burn.tick(st, NOW, self.roots, first_tail=2000)
        self.assertLess(len(st["msgs"]), 60)
        rows = lr_burn.burn_rows(st, NOW, {"s1": {"pid": 1, "acct": "acctA"}}, {})
        self.assertTrue(rows[0]["partial"])

    def test_offset_lands_on_line_starts_after_a_skip(self):
        path = self.tx(0, "s1", self.recs(60))
        with open(path, "rb") as fh:
            data = fh.read()
        start = len(data) - 2000
        st = lr_burn.new_state()
        lr_burn.tick(st, NOW, self.roots, byte_cap=900, first_tail=2000)
        want = start + data[start:start + 900].rfind(b"\n") + 1
        self.assertEqual(st["files"][os.path.realpath(path)]["off"], want)
        while lr_burn.tick(st, NOW, self.roots, byte_cap=900, first_tail=2000):
            pass
        self.assertEqual(len(st["msgs"]), data[start:].count(b"\n") - 1)

    def test_truncated_file_rereads_from_zero(self):
        p = self.tx(0, "s1", self.recs(20))
        st = self.run_tick()
        self.tx(0, "s1", [asst(NOW - 5, "fresh", 7)], mode="w")
        os.utime(p, (NOW, NOW))
        lr_burn.tick(st, NOW, self.roots, first_tail=None)
        self.assertIn("fresh", st["msgs"])

    def test_state_roundtrip_and_version_guard(self):
        self.tx(0, "s1", self.recs(5))
        st = self.run_tick()
        path = os.path.join(self.tmp, "shed", "burn.json")
        lr_burn.save_state(path, st)
        self.assertEqual(lr_burn.load_state(path), json.loads(json.dumps(st)))
        with open(path, "w") as fh:
            json.dump({"v": 0}, fh)
        self.assertEqual(lr_burn.load_state(path), lr_burn.new_state())


class Pace(Fixture):
    def test_least_squares_slope(self):
        self.util_rows(
            "acctA",
            [(NOW - 3600 + i * 400, 10 + i * 400 / 1800.0, 5) for i in range(10)],
        )
        p = lr_burn.paces(NOW, util_path=self.util)["acctA"]
        self.assertAlmostEqual(p["wk"], 2.0, places=6)
        self.assertAlmostEqual(p["5h"], 0.0, places=6)

    def test_stale_rows_and_reset_are_excluded(self):
        self.util_rows(
            "acctA",
            [(NOW - 3500, 90, 50), (NOW - 3000, 95, 60)],
            reset="2026-10-26T00:00:00Z",
        )
        self.util_rows("acctA", [(NOW - 2400 + i * 400, 1 + i, 5) for i in range(6)])
        with open(self.util, "a") as fh:
            fh.write(
                json.dumps(
                    {
                        "ts": iso(NOW - 100),
                        "acct": "acctA",
                        "weekly_pct": 99,
                        "session_pct": 99,
                        "weekly_reset_at": "2026-11-01T04:00:00Z",
                        "session_reset_at": "2026-10-26T16:00:00Z",
                        "stale": True,
                    }
                )
                + "\n"
            )
        p = lr_burn.paces(NOW, util_path=self.util)["acctA"]
        self.assertAlmostEqual(p["wk"], 9.0, places=6)

    def test_short_span_abstains(self):
        self.util_rows("acctA", [(NOW - 300, 10, 1), (NOW - 100, 11, 2)])
        p = lr_burn.paces(NOW, util_path=self.util)["acctA"]
        self.assertIsNone(p["wk"])


class Rows(Fixture):
    def test_shares_sum_to_pace_and_unmeasured_is_none(self):
        self.tx(0, "s1", [asst(NOW - 100, "m1", 1000, cc=50000)])
        self.tx(0, "s2", [asst(NOW - 100, "m2", 3000, cc=10000)])
        self.tx(1, "s3", [asst(NOW - 100, "m3", 3000)])
        live = {
            "s1": {"pid": 1, "acct": "acctA"},
            "s2": {"pid": 2, "acct": "acctA"},
            "s3": {"pid": 3, "acct": "acctB"},
        }
        rows = lr_burn.burn_rows(
            self.run_tick(), NOW, live, {"acctA": {"wk": 1.5, "5h": 12.0}}
        )
        a = [r for r in rows if r["acct"] == "acctA"]
        self.assertAlmostEqual(sum(r["b_wk"] for r in a), 1.5, places=3)
        self.assertAlmostEqual(sum(r["b_5h"] for r in a), 12.0, places=3)
        b = [r for r in rows if r["acct"] == "acctB"][0]
        self.assertIsNone(b["b_wk"])
        self.assertEqual(
            set(a[0]),
            {
                "sid",
                "acct",
                "pid",
                "b_wk",
                "b_5h",
                "last_stop_t",
                "operator_t",
                "ctx",
                "pp_60m",
                "share",
                "partial",
            },
        )

    def test_live_sessions_kill0(self):
        dead = subprocess.Popen([sys.executable, "-c", "pass"])
        dead.wait()
        sd = os.path.join(os.path.dirname(self.roots[0][0]), "sessions")
        for pid, sid in ((os.getpid(), "alive"), (dead.pid, "dead")):
            with open(os.path.join(sd, "%d.json" % pid), "w") as fh:
                json.dump({"pid": pid, "sessionId": sid, "status": "busy"}, fh)
        live = lr_burn.live_sessions(self.roots)
        self.assertEqual(
            live, {"alive": {"pid": os.getpid(), "acct": "acctA", "status": "busy"}}
        )


class Replay(Fixture):
    def setUp(self):
        super().setUp()
        for i in range(
            30
        ):  # each response streamed as three records, the last carrying output
            mid = "m%d" % i
            t = NOW - 3500 + i * 100
            sid = "s%d" % (i % 3)
            self.tx(
                0,
                sid,
                [
                    asst(t, mid, 2, cc=4000, cr=50000),
                    asst(t, mid, 2, cc=4000, cr=50000),
                    asst(t + 1, mid, 900, cc=4000, cr=50000),
                ],
            )
            self.tx(
                0, sid, [asst(t + 2, mid + "sub", 300, cc=2000, side=True)], sub="x"
            )
        self.util_rows(
            "acctA",
            [(NOW - 3600 + i * 400, 40 + i * 400 / 3600.0, 10) for i in range(10)],
        )

    def test_replay_passes(self):
        r = lr_burn.replay(NOW, byte_cap=1024, util_path=self.util, rts=self.roots)
        a = [x for x in r["accounts"] if x["acct"] == "acctA"][0]
        self.assertEqual(r["verdict"], "PASS", lr_burn.render_replay(r))
        self.assertGreater(r["ticks"], 5)
        self.assertLess(a["dev"], 1e-9)
        self.assertIn("verdict=PASS", lr_burn.render_replay(r))

    def test_control_broken_dedup_fails(self):
        # the census is independent: a meter that stops deduping must be caught, not restated
        with mock.patch.object(lr_burn, "_dedup_key", lambda m, d: None):
            r = lr_burn.replay(NOW, byte_cap=1024, util_path=self.util, rts=self.roots)
        self.assertEqual(r["verdict"], "FAIL", lr_burn.render_replay(r))

    def test_no_pace_is_no_verdict(self):
        os.remove(self.util)
        r = lr_burn.replay(NOW, util_path=self.util, rts=self.roots)
        self.assertEqual(r["verdict"], "NO-VERDICT")


if __name__ == "__main__":
    unittest.main()
