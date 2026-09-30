"""working: the reconciler's copy of claude-accounts' working-session rule (D1.8), and its parity
with the original."""

import importlib.machinery
import importlib.util
import json
import os
import shutil
import tempfile
import unittest
from datetime import datetime, timezone
from typing import Any, Dict, List

from lr_recon import plan as P
from lr_recon import types as T
from lr_recon import working as W

NOW = 1_790_000_000.0
WIN = 600.0
REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", ".."))


def iso(t: float) -> str:
    return datetime.fromtimestamp(t, tz=timezone.utc).isoformat().replace("+00:00", "Z")


def user(t: float) -> Dict[str, Any]:
    return {
        "type": "user",
        "timestamp": iso(t),
        "message": {"role": "user", "content": "go"},
    }


def answer(t: float) -> Dict[str, Any]:
    return {
        "type": "assistant",
        "timestamp": iso(t),
        "message": {"content": [{"type": "text", "text": "done"}]},
    }


def tool(t: float) -> Dict[str, Any]:
    return {
        "type": "assistant",
        "timestamp": iso(t),
        "message": {"content": [{"type": "tool_use", "id": "x", "name": "Bash"}]},
    }


class Corpus:
    """One session with a transcript and subagents, every file's mtime pinned to NOW - 60."""

    def __init__(self) -> None:
        self.root = tempfile.mkdtemp(prefix="lr-working-")
        self.sid = "s1"
        self.tx = os.path.join(self.root, "s1.jsonl")
        self.sdir = os.path.join(self.root, "s1")
        os.makedirs(os.path.join(self.sdir, "subagents", "workflows", "wf1"))

    def write(self, path: str, rows: List[Any], raw: str = "") -> str:
        with open(path, "w") as fh:
            for r in rows:
                fh.write(json.dumps(r, separators=(",", ":")) + "\n")
            fh.write(raw)
        os.utime(path, (NOW - 60, NOW - 60))
        return path

    def agent(self, aid: str, rows: List[Any]) -> str:
        return self.write(
            os.path.join(self.sdir, "subagents", "agent-%s.jsonl" % aid), rows
        )

    def cleanup(self) -> None:
        shutil.rmtree(self.root, ignore_errors=True)


class Rule(unittest.TestCase):
    def setUp(self) -> None:
        self.c = Corpus()

    def tearDown(self) -> None:
        self.c.cleanup()

    def working(self, path: str, sub: bool = False) -> bool:
        return W.path_working(
            path, NOW, WIN, sub=sub, settled=lambda: W.session_settled(self.c.sdir, NOW)
        )

    def test_top_level_session(self) -> None:
        c = self.c
        self.assertTrue(self.working(c.write(c.tx, [user(NOW - 30)])))
        # an answered turn 20 min ago is idle, however fresh the file's mtime
        self.assertFalse(self.working(c.write(c.tx, [answer(NOW - 1200)])))
        # waiting on a tool counts up to 30 min, not 10
        self.assertTrue(self.working(c.write(c.tx, [tool(NOW - 1200)])))
        self.assertFalse(self.working(c.write(c.tx, [tool(NOW - 1900)])))
        # records after `now` are ignored (a replayed census)
        self.assertFalse(
            self.working(c.write(c.tx, [answer(NOW - 1200), user(NOW + 5)]))
        )
        # no turn record at all: the old mtime rule
        self.assertTrue(self.working(c.write(c.tx, [{"type": "summary"}])))

    def test_a_subagent_counts_only_while_unfinished(self) -> None:
        c = self.c
        self.assertTrue(self.working(c.agent("live", [tool(NOW - 30)]), sub=True))
        self.assertFalse(self.working(c.agent("done", [answer(NOW - 30)]), sub=True))
        wf = c.agent("wf", [tool(NOW - 30)])
        c.write(
            os.path.join(c.sdir, "subagents", "workflows", "wf1", "journal.jsonl"),
            [{"type": "result", "agentId": "wf", "timestamp": iso(NOW - 20)}],
        )
        self.assertFalse(self.working(wf, sub=True))
        nt = c.agent("nt", [tool(NOW - 40)])
        c.write(
            c.tx,
            [],
            raw='{"type":"queue-operation","content":"<task-notification>\\n<task-id>nt</task-id>'
            '</task-notification>","timestamp":"%s"}\n' % iso(NOW - 10),
        )
        self.assertFalse(self.working(nt, sub=True))

    def test_kwork_counts_the_session_and_its_unfinished_subagents(self) -> None:
        c = self.c
        c.write(c.tx, [user(NOW - 30)])
        c.agent("live", [tool(NOW - 30)])
        c.agent("done", [answer(NOW - 30)])
        # a second session whose file is fresh but whose last turn was answered 20 min ago
        idle_tx = os.path.join(c.root, "s2.jsonl")
        c.write(idle_tx, [answer(NOW - 1200)])
        s = T.SessionObs(sid="s1", acct="next", transcript=T.TranscriptObs(path=c.tx))
        s2 = T.SessionObs(sid="s2", acct="next", transcript=T.TranscriptObs(path=idle_tx))
        snap = T.Snapshot(wall=NOW, uptime_raw=0, sessions={"s1": s, "s2": s2})
        self.assertEqual(P.kwork(snap, ["next"], NOW), {"next": 2})
        os.environ["CC_ROUTE_KWORK_TURNS"] = "off"  # the kill switch: mtime only
        try:
            self.assertEqual(P.kwork(snap, ["next"], NOW), {"next": 4})
        finally:
            del os.environ["CC_ROUTE_KWORK_TURNS"]


def _load_accounts() -> Any:
    path = os.path.join(REPO, "bin", "claude-accounts")
    if not os.path.exists(path):
        return None
    loader = importlib.machinery.SourceFileLoader("claude_accounts_parity", path)
    spec = importlib.util.spec_from_loader(loader.name, loader)
    assert spec is not None
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    return mod if hasattr(mod, "_file_working") else None


class Parity(unittest.TestCase):
    """The reconciler and --place must count one population: every fixture answers the same."""

    def test_same_verdict_as_claude_accounts(self) -> None:
        ca = _load_accounts()
        if ca is None:
            self.skipTest("bin/claude-accounts has no _file_working yet (W6c)")
        c = Corpus()
        try:
            cases = [
                (c.write(c.tx, [user(NOW - 30)]), False),
                (c.agent("a", [answer(NOW - 30)]), True),
                (c.agent("b", [tool(NOW - 1200)]), True),
                (c.agent("d", [tool(NOW - 1900)]), True),
                (c.agent("e", [{"type": "summary"}]), True),
            ]
            c.write(
                os.path.join(c.sdir, "subagents", "workflows", "wf1", "journal.jsonl"),
                [{"type": "result", "agentId": "b", "timestamp": iso(NOW - 20)}],
            )
            for path, sub in cases:
                st = os.stat(path)
                ours = W.file_working(
                    path,
                    st.st_mtime,
                    st.st_size,
                    NOW,
                    WIN,
                    sub=sub,
                    settled=lambda: W.session_settled(c.sdir, NOW),
                )
                theirs = ca._file_working(
                    path,
                    st.st_mtime,
                    st.st_size,
                    NOW,
                    WIN,
                    sub=sub,
                    settled=lambda: ca._session_settled(c.sdir, NOW),
                )
                self.assertEqual(ours, theirs, os.path.basename(path))
        finally:
            c.cleanup()


if __name__ == "__main__":
    unittest.main()
