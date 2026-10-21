"""W14f: a session or registry row whose pid the OS has REUSED is not a live holder.

guarantee9 cure arms 20261021T120053Zdc2a and 20261021T102850Z9471 both failed H5 on SPLIT-BRAIN:
the source stub was SIGTERMed, its `<cfg>/sessions/<pid>.json` stayed behind, the pid wrapped onto
an unrelated process, and the census counted that row as a second holder beside the relaunched
claude. The row's `procStart` named a different instant than the live pid's lstart all along; the
census never compared them (bin/cc-wake W2 does). Each case here replays that shape through the
real observe() and census.bucket()."""

import dataclasses
import json
import os
import shutil
import tempfile
import unittest
from unittest import mock

from lr_recon import census as C
from lr_recon import observe as O
from lr_recon import observe_rows as R
from lr_recon import types as T
from lr_recon.tests import test_census as TC
from lr_recon.tests import test_observe as TO

L = TO.L  # the live lstart of every fake process ("Tue Sep 29 11:19:17 2026")
DEAD = "Tue Sep 29 10:02:44 2026"  # the start of the session that last held pid 600
L_AMBIENT = "Tue 29 Sep 11:19:17 2026"  # L in the TZ=UTC + ambient-locale order
SIDA = TO.SIDA
REUSER = 600
# The real holder is the pane-bound claude 503 (TO.PROCS); 600 is the recycled pid.
PROCS = TO.PROCS + [(REUSER, 1, "S", L, "/usr/bin/some-unrelated-tool --flag")]


class Reuse(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="lr-reuse-", dir="/tmp")
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.home = os.path.join(self.tmp, "home")
        env = mock.patch.dict(
            os.environ,
            {
                "HOME": self.home,
                "LR_STATE_DIR": os.path.join(self.tmp, "lr"),
                "LR_RECON_ROOT": os.path.join(self.tmp, "lr", "recon"),
                "TMPDIR": self.tmp,
            },
        )
        env.start()
        self.addCleanup(env.stop)
        self.put(
            ".claude/accounts.json",
            {
                "accounts": [
                    {"name": "next", "config_dir": "~/.claude-next"},
                    {"name": "next2", "config_dir": "~/.claude-secondary"},
                ]
            },
        )
        self.put(
            ".claude/cc-registry/1.json",
            {
                "session_id": SIDA,
                "pid": 503,
                "account": "claude-secondary",
                "name": "alpha",
                "cwd": "/w/a",
                "paneUUID": "1",
                "surface": "pane",
                "lstart": L,
            },
        )
        self.put(
            ".claude-secondary/sessions/503.json",
            {"sessionId": SIDA, "pid": 503, "kind": "interactive", "procStart": L},
        )

    def put(self, rel, data):
        path = os.path.join(self.home, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as fh:
            json.dump(data, fh)

    def stale_row(self, **extra):
        """The SIGTERMed source's leftover row, naming pid 600, on the other account."""
        row = {"sessionId": SIDA, "pid": REUSER, "kind": "interactive"}
        row.update(extra)
        self.put(".claude-next/sessions/%d.json" % REUSER, row)

    def stale_registry(self, **extra):
        row = {"session_id": SIDA, "pid": REUSER, "account": "claude-next"}
        row.update(extra)
        self.put(".claude/cc-registry/9.json", row)

    def obs(self):
        snap = O.observe(
            None,
            self.home,
            run=TO.FakeRun(ps=TO.ps_text(PROCS)),
            glob_fn=TO.fake_glob,
            lstat_fn=TO.fake_lstat,
            kitten="k",
            now=1.0,
        )
        return snap.sessions[SIDA]

    def bucket(self, s):
        """census.bucket on the observed session, made a LIMITED candidate so SPLIT-BRAIN is reachable."""
        s = dataclasses.replace(
            s,
            acct="next3",
            transcript=T.TranscriptObs(
                path="/t.jsonl", last=dict(TC.LIMIT), at_rest=True
            ),
        )
        snap = T.Snapshot(wall=TC.NOW, uptime_raw=0.0)
        return C.bucket(s, snap, TC._fact(), TC.NOW, {}).name

    def pids(self, s):
        return sorted({h.pid for h in s.holders})

    # ── session rows (observe_rows.read_session_rows) ─────────────────────────────────────────

    def test_reused_pid_session_row_is_not_a_holder(self):
        self.stale_row(procStart=DEAD)
        s = self.obs()
        self.assertEqual(self.pids(s), [503])
        self.assertNotEqual(self.bucket(s), "SPLIT-BRAIN")

    def test_matching_procstart_is_a_holder(self):
        self.stale_row(procStart=L)
        rows = R.read_session_rows(self.home, TO.procs_of(PROCS))
        self.assertIn(REUSER, [r["pid"] for _, r in rows])

    def test_two_real_holders_still_split_brain(self):
        self.stale_row(procStart=L)
        s = self.obs()
        self.assertEqual(self.pids(s), [503, REUSER])
        self.assertEqual(self.bucket(s), "SPLIT-BRAIN")

    def test_row_without_procstart_keeps_pid_only_answer(self):
        self.stale_row()
        s = self.obs()
        self.assertEqual(self.pids(s), [503, REUSER])
        self.assertEqual(self.bucket(s), "SPLIT-BRAIN")

    def test_empty_procstart_is_absent(self):
        self.stale_row(procStart="  ")
        self.assertEqual(self.pids(self.obs()), [503, REUSER])

    def test_non_string_procstart_is_absent(self):
        self.stale_row(procStart=1789000000)
        self.assertEqual(self.pids(self.obs()), [503, REUSER])

    def test_ambient_order_names_the_same_instant(self):
        self.stale_row(procStart=L_AMBIENT)
        self.assertEqual(self.pids(self.obs()), [503, REUSER])

    def test_whitespace_is_normalised(self):
        self.stale_row(procStart="  Tue Sep  29 11:19:17   2026 ")
        self.assertEqual(self.pids(self.obs()), [503, REUSER])

    def test_unknown_live_lstart_keeps_pid_only_answer(self):
        self.stale_row(procStart=DEAD)
        procs = TO.procs_of(PROCS)
        procs[REUSER] = T.ProcRow(REUSER, 1, "S", "", "/usr/bin/x")
        rows = R.read_session_rows(self.home, procs)
        self.assertIn(REUSER, [r["pid"] for _, r in rows])

    # ── registry rows (observe._sessions) ─────────────────────────────────────────────────────

    def test_reused_pid_registry_row_is_not_a_holder(self):
        self.stale_registry(lstart=DEAD)
        s = self.obs()
        self.assertEqual(self.pids(s), [503])
        self.assertNotEqual(self.bucket(s), "SPLIT-BRAIN")

    def test_matching_registry_lstart_is_a_holder(self):
        self.stale_registry(lstart=L_AMBIENT)
        s = self.obs()
        self.assertEqual(self.pids(s), [503, REUSER])
        self.assertEqual(self.bucket(s), "SPLIT-BRAIN")

    def test_registry_row_without_lstart_keeps_pid_only_answer(self):
        self.stale_registry()
        self.assertEqual(self.pids(self.obs()), [503, REUSER])


if __name__ == "__main__":
    unittest.main()
