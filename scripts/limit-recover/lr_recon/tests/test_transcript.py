"""Transcript lookup and bounded reads (§C3.6-7), on the recorded fixture shapes."""

import datetime
import json
import os
import tempfile
import time
import unittest

from lr_recon import facts as F
from lr_recon import transcript as X

FIX = os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    *[".."] * 4,
    "tests",
    "fixtures",
    "lr-recon",
    "jsonl",
)
SID = "00000000-0000-4000-8000-000000000001"


def fixture(name):
    with open(os.path.join(FIX, name)) as fh:
        return fh.read().rstrip("\n") + "\n"


def epoch(iso):
    return datetime.datetime.fromisoformat(iso.replace("Z", "+00:00")).timestamp()


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.cfg = os.path.join(self.tmp.name, "cfg")

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, project, body, sid=SID):
        d = os.path.join(self.cfg, "projects", project)
        os.makedirs(d, exist_ok=True)
        p = os.path.join(d, sid + ".jsonl")
        with open(p, "w") as fh:
            fh.write(body)
        return p


class Lookup(Base):
    def test_slug(self):
        self.assertEqual(X.slug("/a/.w/x"), "-a--w-x")
        self.assertEqual(
            X.slug("/h/Development/.worktrees/lr-fv2"),
            "-h-Development--worktrees-lr-fv2",
        )

    def test_slug_direct_then_glob(self):
        direct = self.write(X.slug("/w/repo"), "{}\n")
        self.write("-aaa-elsewhere", "{}\n")  # sorts first: the glob would pick it
        self.assertEqual(X.find_transcript([self.cfg], "/w/repo", SID), direct)
        moved = X.find_transcript([self.cfg], "/w/other", SID)
        self.assertTrue(moved.endswith("-aaa-elsewhere/%s.jsonl" % SID))
        self.assertIsNone(X.find_transcript([self.cfg], "/w/repo", "nope"))
        self.assertEqual(X.handed_off_path(direct), direct + ".handed-off")

    def test_observe_wrapper_empty_when_missing(self):
        obs = X.observe(self.cfg, "/w/repo", SID)
        self.assertEqual((obs.path, obs.size, obs.last), ("", 0, {}))


class Observe(Base):
    def test_limit_death_after_ok_turn(self):
        body = (
            fixture("user-prompt.jsonl")
            + fixture("assistant-turn.jsonl")
            + fixture("death-quota-limits.jsonl")
        )
        p = self.write(X.slug("/w/repo"), body)
        obs = X.observe(self.cfg, "/w/repo", SID)
        self.assertEqual(obs.path, p)
        self.assertEqual(obs.size, len(body.encode()))
        self.assertTrue(obs.last["limit"])
        self.assertEqual(obs.last["cap"], "five_hour")
        self.assertEqual(F.scope_of(obs.last), "5h")
        self.assertEqual(obs.last_assistant_ok_at, epoch("2026-09-29T03:12:27.139Z"))
        self.assertTrue(obs.at_rest)
        self.assertFalse(obs.teammate)
        self.assertEqual(obs.live_subagents, 0)

    def test_errors_are_not_ok_turns(self):
        for name in (
            "api-error-529.jsonl",
            "authentication-failed.jsonl",
            "death-quota-limits-seven-day.jsonl",
        ):
            p = self.write("-p", fixture(name))
            obs = X.observe_transcript(p)
            self.assertIsNone(obs.last_assistant_ok_at, name)
            self.assertTrue(obs.at_rest, name)

    def test_seven_day_scope(self):
        p = self.write("-p", fixture("death-quota-limits-seven-day.jsonl"))
        self.assertEqual(F.scope_of(X.observe_transcript(p).last), "7d")

    def test_trailing_user_or_tool_use_is_not_at_rest(self):
        turn = json.loads(fixture("assistant-turn.jsonl"))
        p = self.write(
            "-p", fixture("assistant-turn.jsonl") + fixture("user-prompt.jsonl")
        )
        self.assertFalse(X.observe_transcript(p).at_rest)
        turn["message"]["stop_reason"] = "tool_use"
        turn["message"]["content"] = [
            {"type": "tool_use", "id": "t", "name": "Bash", "input": {}}
        ]
        p = self.write("-p", json.dumps(turn) + "\n")
        self.assertFalse(X.observe_transcript(p).at_rest)

    def test_stub_after_handoff_has_no_verdict(self):
        p = self.write("-p", fixture("stub-after-handoff.jsonl"))
        obs = X.observe_transcript(p)
        self.assertFalse(obs.last["limit"])
        self.assertFalse(obs.at_rest)
        self.assertIsNone(obs.last_assistant_ok_at)

    def test_live_subagents_counts_fresh_incl_workflows(self):
        p = self.write("-p", fixture("assistant-turn.jsonl"))
        base = p[: -len(".jsonl")]
        now = time.time()
        files = {
            "subagents/agent-a.jsonl": now - 10,
            "subagents/workflows/w1/agent-b.jsonl": now - 60,
            "subagents/agent-old.jsonl": now - 500,
            "subagents/agent-c.meta.json": now,
            "subagents/workflows/w2/notes.jsonl": now,
        }
        for rel, mt in files.items():
            fp = os.path.join(base, rel)
            os.makedirs(os.path.dirname(fp), exist_ok=True)
            with open(fp, "w") as fh:
                fh.write("{}\n")
            os.utime(fp, (mt, mt))
        self.assertEqual(X.live_subagents(p, now), 2)
        self.assertEqual(X.observe_transcript(p, now=now).live_subagents, 2)

    def test_ok_turns_since(self):
        t1 = json.loads(fixture("assistant-turn.jsonl"))
        t2 = dict(t1, timestamp="2026-09-29T04:00:00.000Z")
        body = (
            json.dumps(t1)
            + "\n"
            + fixture("api-error-529.jsonl")
            + json.dumps(t2)
            + "\n"
        )
        p = self.write("-p", body)
        first, second = epoch(t1["timestamp"]), epoch(t2["timestamp"])
        self.assertEqual(X.ok_turns_since(p, 0), [first, second])
        self.assertEqual(X.ok_turns_since(p, first), [second])
        self.assertEqual(
            X.ok_turns_since(os.path.join(self.tmp.name, "missing"), 0), []
        )


if __name__ == "__main__":
    unittest.main()
