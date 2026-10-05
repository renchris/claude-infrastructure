"""The fact ledger: per-window expiry, contradiction, model scope, auth, merge (§C4)."""

import json
import os
import tempfile
import unittest

from lr_recon import facts as F
from lr_recon import types as T

NOW = 1_790_000_000.0


def fact(scope, resets_at=None, observed_at=NOW - 600, acct="next2", **kw):
    return T.Fact(
        acct=acct, scope=scope, resets_at=resets_at, observed_at=observed_at, **kw
    )


def wire_row(acct="next2", read_at=None, auth="ok", **status):
    wire = {k.replace("s5h", "5h").replace("s7d", "7d"): v for k, v in status.items()}
    if read_at is not None:
        wire["read_at"] = read_at
    return {"name": acct, "auth": auth, "wire": wire}


class Expiry(unittest.TestCase):
    def test_5h_at_resets_plus_60(self):
        f = fact("5h", resets_at=NOW - 60)
        self.assertEqual(F.expire({f.key: f}, NOW, [], []), [])
        self.assertEqual(F.expire({f.key: f}, NOW + 1, [], []), [f.key])

    def test_7d_wire_allowed_with_read_at_expires(self):
        f = fact("7d", resets_at=NOW + 86400)
        row = wire_row(s7d_status="allowed", read_at=f.observed_at + 61)
        self.assertEqual(F.expire({f.key: f}, NOW, [row], []), [f.key])

    def test_7d_wire_without_read_at_never_expires(self):
        f = fact("7d", resets_at=NOW + 86400)
        row = wire_row(s7d_status="allowed")
        self.assertEqual(F.expire({f.key: f}, NOW, [row], []), [])

    def test_wire_read_too_close_or_other_window_does_not_expire(self):
        f = fact("7d", resets_at=NOW + 86400)
        close = wire_row(s7d_status="allowed", read_at=f.observed_at + 30)
        other = wire_row(s5h_status="allowed", s7d_status="rejected", read_at=NOW)
        self.assertEqual(F.expire({f.key: f}, NOW, [close, other], []), [])

    def test_wire_for_another_account_does_not_expire(self):
        f = fact("5h", resets_at=None)
        row = wire_row(acct="next3", s5h_status="allowed", read_at=NOW)
        self.assertEqual(F.expire({f.key: f}, NOW, [row], []), [])

    def test_contradiction_does_not_expire(self):
        f = fact("5h", resets_at=NOW + 3600)
        facts = {f.key: f}
        turns = [("next2", "claude-opus-5-5", "general", NOW - 10)]
        self.assertEqual(F.contradict(facts, turns), [f.key])
        self.assertTrue(facts[f.key].contradicted)
        self.assertEqual(F.expire(facts, NOW, [], turns), [])

    def test_iso_read_at_accepted(self):
        f = fact("5h", observed_at=0.0)
        row = wire_row(s5h_status="allowed_warning", read_at="2026-09-29T03:59:20.821Z")
        self.assertEqual(F.expire({f.key: f}, NOW, [row], []), [f.key])


class ModelScope(unittest.TestCase):
    def test_covers_only_that_model(self):
        f = fact("model:opus")
        self.assertTrue(F.covers(f, "general", "claude-opus-5-5"))
        self.assertFalse(F.covers(f, "general", "claude-haiku-4-5-20251001"))
        self.assertFalse(F.covers(f, "fable", "claude-fable-5-1"))

    def test_haiku_wire_cannot_expire_model_fact(self):
        f = fact("model:opus", resets_at=None)
        row = wire_row(s5h_status="allowed", s7d_status="allowed", read_at=NOW)
        self.assertEqual(F.expire({f.key: f}, NOW, [row], []), [])
        g = fact("model:opus", resets_at=NOW - 61)
        self.assertEqual(F.expire({g.key: g}, NOW, [row], []), [g.key])

    def test_fable_scope_and_blocking(self):
        f = fact("fable", resets_at=NOW + 100)
        self.assertTrue(F.covers(f, "fable", ""))
        self.assertFalse(F.covers(f, "general", "claude-opus-5-5"))
        self.assertIsNone(
            F.blocking({f.key: f}, "next2", "general", "claude-opus-5-5", NOW)
        )
        self.assertEqual(
            F.blocking({f.key: f}, "next2", "fable", "claude-fable-5-1", NOW), f
        )

    def test_blocking_returns_the_fact_that_binds_latest(self):
        """W7h: ranked on scope first, an older 7d fact was returned over a later-resetting 5h."""
        d7, h5 = fact("7d", resets_at=NOW + 3600), fact("5h", resets_at=NOW + 6000)
        both = {d7.key: d7, h5.key: h5}
        self.assertEqual(F.blocking(both, "next2", "general", "m", NOW), h5)
        d7 = fact("7d", resets_at=NOW + 9000)
        both[d7.key] = d7
        self.assertEqual(F.blocking(both, "next2", "general", "m", NOW), d7)
        # no known reset ranks after a known one; auth, which no reset frees, before both
        unk = fact("7d", resets_at=None)
        both[unk.key] = unk
        self.assertEqual(F.blocking(both, "next2", "general", "m", NOW), h5)
        au = fact("auth", resets_at=None)
        both[au.key] = au
        self.assertEqual(F.blocking(both, "next2", "general", "m", NOW), au)

    def test_other_model_turn_does_not_contradict(self):
        f = fact("model:opus")
        facts = {f.key: f}
        self.assertEqual(
            F.contradict(facts, [("next2", "claude-haiku-4-5", "x", NOW)]), []
        )


class Auth(unittest.TestCase):
    def test_auth_needs_both_read_and_turn(self):
        f = fact("auth")
        ok_row = wire_row(auth="ok", read_at=NOW - 5)
        turn = [("next2", "claude-opus-5-5", "general", NOW - 5)]
        self.assertEqual(F.expire({f.key: f}, NOW, [ok_row], []), [])
        self.assertEqual(F.expire({f.key: f}, NOW, [], turn), [])
        stale = wire_row(auth="ok", read_at=f.observed_at - 1)
        self.assertEqual(F.expire({f.key: f}, NOW, [stale], turn), [])
        self.assertEqual(F.expire({f.key: f}, NOW, [ok_row], turn), [f.key])

    def test_auth_always_blocks(self):
        f = fact("auth")
        self.assertEqual(F.blocking({f.key: f}, "next2", "fable", "m", NOW), f)
        self.assertIsNone(F.blocking({f.key: f}, "next3", "fable", "m", NOW))


class MergeAndStore(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.paths = T.Paths(
            lr_root=self.tmp.name, root=os.path.join(self.tmp.name, "recon")
        )

    def tearDown(self):
        self.tmp.cleanup()

    def test_merge_rule(self):
        first = fact(
            "5h", resets_at=NOW + 100, observed_at=NOW - 50, first_sid="a", src="hook"
        )
        F.write_fact(self.paths, first)
        later = fact(
            "5h",
            resets_at=NOW + 50,
            observed_at=NOW,
            first_sid="b",
            src="wire",
            contradicted=True,
        )
        m = F.write_fact(self.paths, later)
        self.assertEqual(
            (m.observed_at, m.first_sid, m.resets_at), (NOW - 50, "a", NOW + 100)
        )
        self.assertTrue(m.contradicted)
        m = F.write_fact(self.paths, fact("5h", resets_at=NOW + 900, observed_at=NOW))
        self.assertEqual(m.resets_at, NOW + 900)
        self.assertTrue(m.contradicted)  # sticky
        self.assertEqual(F.load_facts(self.paths)["next2.5h"], m)

    def test_load_skips_bad_and_reap(self):
        F.write_fact(self.paths, fact("model:opus"))
        with open(os.path.join(self.paths.facts, "next3.5h.json"), "w") as fh:
            fh.write("{not json")
        bad = []
        facts = F.load_facts(self.paths, on_bad=lambda p, e: bad.append(p))
        self.assertEqual(list(facts), ["next2.model:opus"])
        self.assertEqual(len(bad), 1)
        self.assertTrue(
            os.path.exists(os.path.join(self.paths.facts, "next2.model:opus.json"))
        )
        self.assertEqual(F.reap(self.paths, ["next2.model:opus", "gone.5h"]), 1)
        self.assertEqual(F.load_facts(self.paths), {})

    def test_compact_json(self):
        F.write_fact(self.paths, fact("7d"))
        with open(os.path.join(self.paths.facts, "next2.7d.json")) as fh:
            raw = fh.read()
        self.assertNotIn(" ", raw)
        self.assertEqual(json.loads(raw)["scope"], "7d")


class Producers(unittest.TestCase):
    def v(self, cap, limit=True, kind="limit", resets_at=None):
        return {"limit": limit, "kind": kind, "cap": cap, "resets_at": resets_at}

    def test_scope_of(self):
        self.assertEqual(F.scope_of(self.v("five_hour")), "5h")
        self.assertEqual(F.scope_of(self.v("seven_day")), "7d")
        self.assertEqual(F.scope_of(self.v("model_scoped:Opus")), "model:opus")
        self.assertEqual(F.scope_of(self.v("model_scoped:Fable")), "fable")
        self.assertIsNone(F.scope_of(self.v("monthly_spend")))
        self.assertIsNone(F.scope_of(self.v(None)))
        self.assertIsNone(F.scope_of(self.v(None, limit=False, kind="server_529")))
        self.assertEqual(
            F.scope_of(self.v(None, limit=False, kind="auth_cliff")), "auth"
        )

    def test_fact_from_death(self):
        f = F.fact_from_death(
            "next", "sid1", self.v("five_hour", resets_at=1790663400), NOW, "hook"
        )
        self.assertEqual(
            (f.key, f.window, f.resets_at, f.src),
            ("next.5h", "five_hour", 1790663400.0, "hook"),
        )
        fb = F.fact_from_death(
            "next", "sid1", self.v("model_scoped:Fable"), NOW, "census"
        )
        self.assertTrue(fb.untested)
        self.assertIsNone(
            F.fact_from_death("next", "s", self.v("monthly_spend"), NOW, "hook")
        )

    def test_facts_from_wire_only_adds_rejections(self):
        rows = [
            wire_row(acct="next", s5h_status="rejected", s7d_status="allowed"),
            wire_row(acct="next4", s5h_status="allowed_warning", s7d_status="rejected"),
            {"name": "next3", "wire": None},
        ]
        got = sorted(f.key for f in F.facts_from_wire(rows, NOW))
        self.assertEqual(got, ["next.5h", "next4.7d"])

    def test_limited_rows_sorted_and_filtered(self):
        a = fact("7d", acct="next3", resets_at=NOW + 10)
        b = fact("5h", acct="next", resets_at=NOW - 100)  # reset passed
        c = fact("5h", acct="next3", resets_at=None, src="wire")
        rows = F.limited_rows({x.key: x for x in (a, b, c)}, NOW)
        self.assertEqual(
            [(r["acct"], r["scope"]) for r in rows], [("next3", "5h"), ("next3", "7d")]
        )
        self.assertEqual(rows[0]["src"], "wire")


if __name__ == "__main__":
    unittest.main()
