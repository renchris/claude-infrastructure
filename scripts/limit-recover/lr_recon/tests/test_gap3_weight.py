"""gap-3 E4.1/E4.2/E4.3: a mover's weight is bounded at its death, clamped below the placer's cap,
and carries its own phantom's id so --place does not charge the mover its own seats."""

import json
import os
import shutil
import tempfile
import unittest

from lr_recon import plan as P
from lr_recon import types as T

DEATH = 1_790_000_000.0


def _rec(sid, **kw):
    r = T.Record(
        sid=sid,
        record_id="recon:c:%s:1" % sid[:8],
        kind="limited",
        source_acct="next3",
        source_cfg="/c3",
        scope="7d",
        **kw,
    )
    r.timeline.detected = DEATH
    return r


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.tx = os.path.join(self.tmp, "s1.jsonl")
        open(self.tx, "w").close()
        self.sub = os.path.join(self.tmp, "s1", "subagents")
        os.makedirs(self.sub)
        self.ssot(24)

    def ssot(self, kmax):
        p = os.path.join(self.tmp, "accounts.json")
        with open(p, "w") as fh:
            json.dump({"router": {"KMAX": kmax}}, fh)
        old = os.environ.get("CLAUDE_ACCOUNTS_JSON")
        os.environ["CLAUDE_ACCOUNTS_JSON"] = p
        self.addCleanup(
            lambda: (
                os.environ.pop("CLAUDE_ACCOUNTS_JSON", None)
                if old is None
                else os.environ.__setitem__("CLAUDE_ACCOUNTS_JSON", old)
            )
        )

    def agent(self, name, mtime):
        p = os.path.join(self.sub, name)
        open(p, "w").close()
        os.utime(p, (mtime, mtime))

    def mover(self, rec=None, with_session=True):
        s = T.SessionObs(
            sid="s1", acct="next3", transcript=T.TranscriptObs(path=self.tx)
        )
        snap = T.Snapshot(
            wall=DEATH, uptime_raw=0, sessions={"s1": s} if with_session else {}
        )
        [m] = P.movers([rec or _rec("s1")], snap, DEATH + 3600)
        return m


class WindowEndsAtTheDeath(Base):
    def test_subagents_written_after_the_death_do_not_weigh(self):
        """7046d8d0 was charged 1 + 59 + 5 post-death files; 5507881f 20 against 8 in-window."""
        self.agent("agent-in.jsonl", DEATH - 300)
        self.agent("agent-edge.jsonl", DEATH)
        self.agent("agent-after.jsonl", DEATH + 120)
        self.agent("agent-old.jsonl", DEATH - 900)
        self.assertEqual(self.mover().w, 3)  # 1 + in + edge

    def test_the_window_bounds_are_inclusive_and_ten_minutes(self):
        self.agent("agent-a.jsonl", DEATH - P.KWORK_WINDOW_S)
        self.assertEqual(P.subagents_written(self.tx, "s1", DEATH), 1)
        self.assertEqual(P.subagents_written(self.tx, "s1", DEATH - 1), 1)
        self.assertEqual(
            P.subagents_written(self.tx, "s1", DEATH - P.KWORK_WINDOW_S - 1), 0
        )


class ClampedBelowTheCap(Base):
    def test_a_heavy_mover_is_clamped_to_kmax_minus_one(self):
        """w > KMAX was never placeable: --place refuses cap - placed < w, and cap <= KMAX."""
        self.ssot(8)
        for i in range(20):
            self.agent("agent-%02d.jsonl" % i, DEATH - 60)
        self.assertEqual(self.mover().w, 7)

    def test_a_record_with_no_session_has_its_stored_weight_clamped_too(self):
        self.ssot(24)
        self.assertEqual(self.mover(_rec("s1", weight=65), with_session=False).w, 23)

    def test_a_light_mover_is_unchanged(self):
        self.agent("agent-a.jsonl", DEATH - 60)
        self.assertEqual(self.mover().w, 2)

    def test_kmax_is_read_from_the_placers_ssot(self):
        self.ssot(13)
        self.assertEqual(P.kmax(), 13)
        os.environ["CLAUDE_ACCOUNTS_JSON"] = os.path.join(self.tmp, "missing.json")
        self.assertIsNone(P.kmax())
        self.assertEqual(
            P.clamp_weight(40, None), 40
        )  # no SSOT: --place cannot run either
        self.assertEqual(P.clamp_weight(0, 8), 1)


class CarriesItsOwnPhantom(Base):
    def test_the_mover_row_names_the_id_its_phantom_is_charged_under(self):
        m = self.mover(_rec("s1", assign_id="recon:c:s1:0"))
        self.assertEqual(m.assign_id, "recon:c:s1:0")
        self.assertEqual(
            self.mover().assign_id, "recon:c:s1:1"
        )  # phantom_rows' fallback
        self.assertEqual(T.to_dict(m)["assign_id"], "recon:c:s1:0")


if __name__ == "__main__":
    unittest.main()
