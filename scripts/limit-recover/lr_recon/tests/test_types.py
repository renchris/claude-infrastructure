"""The frozen interface round-trips through JSON and tolerates old/new records."""

import json
import unittest

from lr_recon import types as T


class TypesRoundTrip(unittest.TestCase):
    def test_record_round_trip(self):
        rec = T.Record(sid="abc", record_id=T.make_record_id("c1", "abcdef012345", 2),
                       pane=(123, 4), procs=[T.ProcRole("actuator", 9, "Tue Sep 29 06:19:17 2026")],
                       intent=T.Intent("n1", 1.0), wait=T.Wait("WAIT_SLOT", wakes=["reset"]),
                       last_error=T.LastError("TRANSIENT", "fp"))
        back = T.from_dict(T.Record, json.loads(json.dumps(T.to_dict(rec))))
        self.assertEqual(back.record_id, "recon:c1:abcdef01:2")
        self.assertEqual(back.pane, (123, 4))
        self.assertIsInstance(back.procs[0], T.ProcRole)
        self.assertIsInstance(back.wait, T.Wait)
        self.assertIsInstance(back.timeline, T.Timeline)
        self.assertEqual(back, rec)

    def test_unknown_and_missing_keys(self):
        back = T.from_dict(T.Record, {"sid": "s", "record_id": "r", "future_field": 1})
        self.assertEqual(back.phase, "PRE-MOVE")
        self.assertIsNone(back.terminal)

    def test_evidence_from_fixture_shape(self):
        ev = T.from_dict(T.Evidence, {"holders": [{"cfg": "target", "pane_bound": True}],
                                      "handed_off": True})
        self.assertIsInstance(ev.holders[0], T.EvHolder)
        self.assertTrue(ev.handed_off)

    def test_paths_root_override(self):
        p = T.Paths.from_env(env={"HOME": "/h", "LR_RECON_ROOT": "/tmp/x"})
        self.assertEqual(p.root, "/tmp/x")
        self.assertEqual(p.requests, "/h/.reso/limit-recover/requests")
        self.assertTrue(all(d.startswith("/tmp/x/") for d in p.reconciler_dirs()))

    def test_snapshot_alive_zombie(self):
        s = T.Snapshot(wall=0, uptime_raw=0, procs={5: T.ProcRow(5, 1, "Z", "L", "x")})
        self.assertFalse(s.alive(5, "L"))


if __name__ == "__main__":
    unittest.main()
