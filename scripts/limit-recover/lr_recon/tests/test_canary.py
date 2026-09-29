"""W5b canary scope (``LR_RECON_CANARY``): a real-session canary daemon acts on its listed sids
only, from its own tree, and never reads or moves another session's state.

Hermetic: every store lives in a temp dir; nothing here starts a process.
"""

import io
import json
import os
import shutil
import tempfile
import unittest
from contextlib import redirect_stderr
from unittest import mock

from lr_recon import __main__ as M
from lr_recon import act, fence, store
from lr_recon import types as T

SIDA = "aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa"
SIDB = "bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb"
NOW = 1790000500.0


class Paths(unittest.TestCase):
    def test_parse_drops_junk_and_lowercases(self):
        got = T.parse_canary("%s, %s  not-a-sid ../x" % (SIDA.upper(), SIDB))
        self.assertEqual(got, frozenset({SIDA, SIDB}))
        self.assertEqual(T.parse_canary(""), frozenset())

    def test_canary_has_its_own_root_and_switch(self):
        p = T.Paths.from_env(env={"HOME": "/h", "LR_RECON_CANARY": SIDA})
        lr = "/h/.reso/limit-recover"
        self.assertEqual(p.root, lr + "/recon-canary")
        self.assertEqual(p.recon_on, lr + "/recon-canary/canary.on")
        self.assertEqual(p.autorecover_on, lr + "/recon-canary/canary.on")
        # the shared tree stays shared: locks and requests are the legacy actors' own
        self.assertEqual(p.locks, lr + "/locks")
        self.assertEqual(p.requests, lr + "/requests")
        self.assertFalse(p.canary_in_live_root)
        # CONTROL: no canary ⇒ today's paths, byte for byte
        q = T.Paths.from_env(env={"HOME": "/h"})
        self.assertEqual(
            (q.root, q.recon_on, q.autorecover_on),
            (lr + "/recon", lr + "/recon.on", lr + "/autorecover.on"),
        )

    def test_canary_in_the_live_root_is_flagged(self):
        env = {"HOME": "/h", "LR_RECON_CANARY": SIDA}
        env["LR_RECON_ROOT"] = "/h/.reso/limit-recover/recon"
        self.assertTrue(T.Paths.from_env(env=env).canary_in_live_root)


class Tree(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp(prefix="lr-canary-")
        self.lr = os.path.join(self.dir, "lr")
        self.env = {"HOME": self.dir, "LR_STATE_DIR": self.lr, "LR_RECON_CANARY": SIDA}
        self.paths = T.Paths.from_env(env=self.env)
        store.ensure_dirs(self.paths)

    def tearDown(self):
        shutil.rmtree(self.dir, ignore_errors=True)

    def _req(self, sid, suffix=".json"):
        os.makedirs(self.paths.requests, exist_ok=True)
        with open(os.path.join(self.paths.requests, sid + suffix), "w") as fh:
            json.dump({"sid": sid, "at": NOW}, fh)

    def test_requests_of_other_sessions_are_invisible(self):
        self._req(SIDA)
        self._req(SIDB)
        self._req(SIDB, ".cc-lr.json")
        self.assertEqual([r.sid for r in store.list_requests(self.paths)], [SIDA])
        live = T.Paths.from_env(env={"HOME": self.dir, "LR_STATE_DIR": self.lr})
        self.assertEqual(len(store.list_requests(live)), 3)  # CONTROL

    def test_actuator_env_names_the_canary_trees_and_no_preseed_skip(self):
        rec = T.Record(sid=SIDA, record_id="recon:c:aaaaaaaa:1", cohort_id="c")
        env = act.actuator_env(rec, self.paths, "", base={"LR_PRESEED_DONE": "stale"})
        self.assertEqual(env["LR_RECON_ROOT"], self.paths.root)
        self.assertEqual(env["LR_STATE_DIR"], self.lr)
        # the daemon never preseeded, so it must not tell the move it did (W5b)
        self.assertEqual(env.get("LR_PRESEED_DONE"), "stale")
        self.assertNotIn(
            "LR_PRESEED_DONE", act.actuator_env(rec, self.paths, "", base={})
        )

    def _owned(self, root):
        os.makedirs(os.path.join(root, "owned"), exist_ok=True)
        with open(os.path.join(root, "owned", SIDA), "w") as fh:
            fh.write('{"record_id":"R1","attempt":1,"procs":[]}')
        with open(os.path.join(root, "heartbeat"), "w") as fh:
            fh.write(
                '{"pid":1,"lstart":"x","progress":1,"wall":%f,"uptime_raw":1.0,'
                '"progress_wall":%f}' % (NOW - 5, NOW - 5)
            )

    def test_live_fence_defers_to_a_canary_owned_sid(self):
        live = T.Paths.from_env(env={"HOME": self.dir, "LR_STATE_DIR": self.lr})
        croot = os.path.join(self.lr, T.CANARY_ROOT)
        self._owned(croot)
        dead = lambda pid, ls: False  # noqa: E731
        # no canary.on: the operator's recon.on alone decides, as before
        self.assertEqual(
            fence.defers(live, SIDA, "", NOW, 0.0, dead), (False, "recon-off")
        )
        open(os.path.join(croot, "canary.on"), "w").close()
        self.assertEqual(
            fence.defers(live, SIDA, "", NOW, 0.0, dead), (True, "heartbeat-fresh")
        )
        self.assertEqual(
            fence.defers(live, SIDA, "R1", NOW, 0.0, dead), (False, "own-actuator")
        )
        # a sid the canary does not own is untouched
        self.assertEqual(
            fence.defers(live, SIDB, "", NOW, 0.0, dead), (False, "recon-off")
        )

    def test_main_refuses_a_canary_in_the_live_root_or_an_empty_list(self):
        live_root = os.path.join(self.lr, "recon")
        err = io.StringIO()
        with mock.patch.dict(os.environ, self.env, clear=False), redirect_stderr(err):
            rc = M.main(["--once", "--root", live_root])
        self.assertEqual(rc, 2)
        self.assertIn("REFUSED", err.getvalue())
        self.assertFalse(os.path.exists(os.path.join(live_root, "heartbeat")))
        env = dict(self.env, LR_RECON_CANARY="junk")
        with (
            mock.patch.dict(os.environ, env, clear=False),
            redirect_stderr(io.StringIO()),
        ):
            self.assertEqual(M.main(["--once"]), 2)


if __name__ == "__main__":
    unittest.main()
