"""plan: k_work fail-closed, mover order, the --place driver contract, record transitions."""

import json
import os
import subprocess
import tempfile
import unittest

from lr_recon import plan as P
from lr_recon import types as T

NOW = 1_790_000_000.0


class FakeRun:
    def __init__(self, rc=0, out=""):
        self.rc, self.out, self.argv, self.files = rc, out, None, {}

    def __call__(self, argv, **kw):
        self.argv = argv
        for flag in ("--movers", "--kwork", "--assign-many"):
            if flag in argv:
                with open(argv[argv.index(flag) + 1]) as fh:
                    self.files[flag] = fh.read()
        return subprocess.CompletedProcess(argv, self.rc, self.out, "")


def _rec(sid, kind="limited", detected=NOW, **kw):
    r = T.Record(
        sid=sid,
        record_id="recon:c:%s:1" % sid[:8],
        kind=kind,
        source_acct="next3",
        source_cfg="/c3",
        scope="7d",
        **kw,
    )
    r.timeline.detected = detected
    return r


class PlanTests(unittest.TestCase):
    def test_kwork_unmeasured_when_degraded(self):
        snap = T.Snapshot(wall=NOW, uptime_raw=0, degraded=["ps"])
        self.assertEqual(
            P.kwork(snap, ["next", "next2"], NOW), {"next": None, "next2": None}
        )

    def test_kwork_counts_fresh_transcripts(self):
        tmp = tempfile.mkdtemp()
        tx = os.path.join(tmp, "s1.jsonl")
        open(tx, "w").close()
        sub = os.path.join(tmp, "s1", "subagents", "workflows", "w")
        os.makedirs(sub)
        open(os.path.join(sub, "agent-a.jsonl"), "w").close()
        s = T.SessionObs(sid="s1", acct="next", transcript=T.TranscriptObs(path=tx))
        snap = T.Snapshot(wall=NOW, uptime_raw=0, sessions={"s1": s})
        now = os.stat(tx).st_mtime + 1
        self.assertEqual(P.kwork(snap, ["next", "next2"], now), {"next": 2, "next2": 0})

    def test_movers_limited_first_then_oldest(self):
        recs = [
            _rec("idle0001", kind="idle", detected=NOW - 900),
            _rec("lim00002", detected=NOW - 10),
            _rec("lim00001", detected=NOW - 100),
            _rec("held0001", substate="HOLD-BGWORK"),
        ]
        snap = T.Snapshot(wall=NOW, uptime_raw=0)
        self.assertEqual(
            [m.sid for m in P.movers(recs, snap, NOW)],
            ["lim00001", "lim00002", "idle0001"],
        )

    def test_place_exit3_is_wait_data(self):
        mv = [T.Mover(sid="a", src="/c3")]
        out, rc = P.place("general", mv, "/f", {"next": None}, run=FakeRun(rc=3))
        self.assertEqual((rc, out["a"].reason, out["a"].acct), (3, "wait-data", None))

    def test_place_argv_and_parse(self):
        fr = FakeRun(
            out=json.dumps(
                {"a": {"acct": "next4", "reason": "", "eta_s": None, "weight": 2}}
            )
        )
        out, rc = P.place(
            "general", [T.Mover(sid="a", src="/c3", w=2)], "/f", {"next4": 1}, run=fr
        )
        self.assertEqual((rc, out["a"].acct, out["a"].weight), (0, "next4", 2))
        for flag in ("--place", "--recovery", "--json"):
            self.assertIn(flag, fr.argv)
        self.assertEqual(
            json.loads(fr.files["--movers"]),
            {"sid": "a", "src": "/c3", "kind": "limited", "w": 2},
        )
        self.assertEqual(json.loads(fr.files["--kwork"]), {"next4": 1})

    def test_apply_planned_wait_reset_wait_slot(self):
        recs = {s: _rec(s) for s in ("a", "b", "c")}
        facts = {"next3.7d": T.Fact(acct="next3", scope="7d", resets_at=NOW + 300)}
        placed = {
            "a": T.Placement(acct="next4", weight=3),
            "b": T.Placement(acct=None, reason="floors", eta_s=3600),
            "c": T.Placement(acct=None, reason="wait-data"),
        }
        P.apply(recs, placed, facts, lambda a: "/cfg-" + a, NOW)
        self.assertEqual(
            (recs["a"].substate, recs["a"].target_cfg, recs["a"].weight),
            ("PLANNED", "/cfg-next4", 3),
        )
        self.assertEqual(
            (recs["b"].substate, recs["b"].wait.eta), ("WAIT_RESET", NOW + 300)
        )
        self.assertEqual(recs["c"].substate, "WAIT_RESET")
        facts.clear()
        P.apply(recs, {"c": placed["c"]}, facts, str, NOW)
        self.assertEqual(
            (recs["c"].substate, recs["c"].wait.max_age_s), ("WAIT_DATA", 120)
        )

    def test_auth_hop_no_eligible_waits_for_a_seat_not_a_reset(self):
        """W5 rig target-auth: a hop FROM an auth-failed account with no eligible target stays a
        mover (WAIT_SLOT), never WAIT_RESET on the source's 5h fact — nothing leaves WAIT_RESET
        for an auth-failed session (it never buckets as a record type)."""
        rec = _rec("a")
        rec.scope = "5h"  # the hop keeps the original scope; _rec pins "7d"
        rec.close["hop"] = "auth"
        facts = {
            "next3.5h": T.Fact(acct="next3", scope="5h", resets_at=NOW + 10800),
            "next3.auth": T.Fact(acct="next3", scope="auth", resets_at=None),
        }
        P.apply(
            {"a": rec},
            {"a": T.Placement(acct=None, reason="no-eligible")},
            facts,
            str,
            NOW,
        )
        self.assertEqual((rec.substate, rec.wait.eta), ("WAIT_SLOT", None))
        snap = T.Snapshot(wall=NOW, uptime_raw=0)
        self.assertEqual([m.sid for m in P.movers([rec], snap, NOW)], ["a"])

    def test_wait_reset_is_a_mover_once_its_eta_passes(self):
        """The "reset" wake: a WAIT_RESET record is re-offered to --place after its ETA, so a
        record whose session stops bucketing LIMITED cannot wait forever."""
        rec = _rec("a", substate="WAIT_RESET")
        rec.wait = T.Wait(reason="WAIT_RESET", since=NOW, eta=NOW + 300)
        snap = T.Snapshot(wall=NOW, uptime_raw=0)
        self.assertEqual(P.movers([rec], snap, NOW + 299), [])
        self.assertEqual([m.sid for m in P.movers([rec], snap, NOW + 300)], ["a"])

    def test_phantoms_skip_plan_only_and_waits(self):
        a = _rec("a", target_acct="next4", substate="PLANNED")
        b = _rec("b", target_acct="next4", substate="PLANNED", plan_only=True)
        c = _rec("c", target_acct="next4", substate="WAIT_SLOT")
        d = _rec(
            "d",
            target_acct="next4",
            phase="RELAUNCHED",
            substate="UNPROMPTED",
            weight=2,
        )
        rows = P.phantom_rows([a, b, c, d])
        self.assertEqual(
            [(r["sid"], r["w"], r["ttl_s"]) for r in rows],
            [("a", 1, 1200), ("d", 2, 1200)],
        )
        fr = FakeRun()
        self.assertEqual(P.assign_many(rows, run=fr), 0)
        self.assertEqual(len(fr.files["--assign-many"].splitlines()), 2)

    def test_admit_lock(self):
        tmp = tempfile.mkdtemp()
        paths = T.Paths(lr_root=tmp, root=os.path.join(tmp, "recon"))
        h = T.LockHolder(
            record_id="r1", attempt=1, role="plan", pid=os.getpid(), lstart="x", at=NOW
        )
        self.assertTrue(P.admit_lock_take(paths, h, lambda p, s: True))
        h2 = T.LockHolder(
            record_id="r2", attempt=1, role="plan", pid=1, lstart="y", at=NOW
        )
        self.assertFalse(
            P.admit_lock_take(paths, h2, lambda p, s: True, tries=2, pause=0)
        )
        P.admit_lock_release(paths, "r1")
        self.assertTrue(P.admit_lock_take(paths, h2, lambda p, s: True))


if __name__ == "__main__":
    unittest.main()
