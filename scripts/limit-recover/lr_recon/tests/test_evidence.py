"""evidence.build: holder classification, fail-closed pane/identity, tombstone files, history."""

import json
import os
import tempfile
import unittest

from lr_recon import evidence as E
from lr_recon import types as T

L = "Tue Sep 29 11:19:17 2026"


def _snap(procs=(), panes=None, sessions=None, degraded=(), wall=1000.0):
    return T.Snapshot(
        wall=wall,
        uptime_raw=0.0,
        procs={p.pid: p for p in procs},
        panes=panes or {},
        sessions=sessions or {},
        degraded=list(degraded),
    )


class EvidenceTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.src = os.path.join(self.tmp, "src")
        self.tgt = os.path.join(self.tmp, "tgt")
        self.cwd = "/w/x"
        for c in (self.src, self.tgt):
            os.makedirs(os.path.join(c, "projects", "-w-x"))
        self.paths = T.Paths(
            lr_root=os.path.join(self.tmp, "lr"),
            root=os.path.join(self.tmp, "lr", "recon"),
        )
        self.rec = T.Record(
            sid="sid1",
            record_id="r1",
            source_cfg=self.src,
            target_cfg=self.tgt,
            source_pid=10,
            source_lstart=L,
            pane=(5, 7),
            cwd=self.cwd,
            identity=T.Identity(kitty_pid=5, window_id=7, root_pid=20, root_lstart=L),
        )

    def _tx(self, cfg, suffix=""):
        p = os.path.join(cfg, "projects", "-w-x", "sid1.jsonl" + suffix)
        with open(p, "w") as fh:
            fh.write("")
        return p

    def _build(self, snap):
        return E.build(self.paths, self.rec, snap, debt_open=lambda s: False)

    def test_holders_classified_by_cfg_and_pane(self):
        s = T.SessionObs(
            sid="sid1",
            holders=[
                T.HolderObs(pid=10, lstart=L, cfg="", src="resume-argv", pane=(5, 7)),
                T.HolderObs(
                    pid=11, lstart=L, cfg=self.tgt, src="session-row", pane=(5, 7)
                ),
                T.HolderObs(
                    pid=12,
                    lstart=L,
                    cfg=self.src,
                    src="session-row",
                    kind="bg",
                    bg=True,
                ),
            ],
        )
        ev = self._build(_snap(sessions={"sid1": s}))
        self.assertEqual(
            [(h.cfg, h.pane_bound, h.role) for h in ev.holders],
            [
                ("source", True, "claude"),
                ("target", True, "claude"),
                ("source", False, "bg-row"),
            ],
        )

    def test_tombstone_and_stub(self):
        self._tx(self.src, ".handed-off")
        ev = self._build(_snap())
        self.assertTrue(ev.handed_off and ev.source_retired)
        self.assertFalse(ev.stub_present)
        self._tx(self.src)
        self.assertTrue(self._build(_snap()).stub_present)

    def test_pane_gone_only_when_kitty_read(self):
        self.assertEqual(self._build(_snap()).pane_state, "gone")
        self.assertEqual(
            self._build(_snap(degraded=["kitty:unix:/tmp/kitty-5"])).pane_state,
            "unknown",
        )

    def test_tty_present_follows_the_pane_root_process(self):
        """W5 rig: the node outlives the window, and a freed tty number is re-used within seconds
        by another session's expect pty; only the pane root's (pid, lstart) answers the question."""
        self.rec.identity.tty = "ttys022"
        snap = _snap()
        snap.ttys = ["ttys022"]  # re-used by someone else
        self.assertFalse(self._build(snap).tty_present)  # root 20 is not in this snapshot
        snap.procs[20] = T.ProcRow(20, 1, "Ss", L, "-zsh")
        self.assertTrue(self._build(snap).tty_present)
        self.rec.identity.root_pid = 0  # no recorded root: the held-by-any-process fallback
        self.assertTrue(self._build(snap).tty_present)
        snap.ttys = ["ttys001"]
        self.assertFalse(self._build(snap).tty_present)

    def test_identity_fail_closed(self):
        pane = T.PaneObs(
            kitty_pid=5,
            window_id=7,
            sock="s",
            root_pid=20,
            root_lstart=L,
            state="shell",
        )
        self.assertTrue(self._build(_snap(panes={"5:7": pane})).identity_match)
        self.rec.identity = T.Identity()
        self.assertFalse(self._build(_snap(panes={"5:7": pane})).identity_match)

    def test_live_watcher_by_argv_and_zombie_is_dead(self):
        w = T.ProcRow(30, 1, "S", L, "bash handoff-fire.sh __recycle w1 ttys1 f d sid1")
        self.assertTrue(self._build(_snap(procs=[w])).live_watcher)
        z = T.ProcRow(30, 1, "Z", L, w.args)
        self.assertFalse(self._build(_snap(procs=[z])).live_watcher)

    def test_lock_names_target(self):
        os.makedirs(self.paths.locks)
        with open(os.path.join(self.paths.locks, "sid1.lock"), "w") as fh:
            json.dump({"sid": "sid1", "to": self.tgt}, fh, separators=(",", ":"))
        self.assertTrue(self._build(_snap()).lock_names_target)

    def test_source_alive_exact_lstart(self):
        p = T.ProcRow(10, 1, "S", L, "claude")
        self.assertTrue(self._build(_snap(procs=[p])).source_alive)
        p2 = T.ProcRow(10, 1, "S", "Wed Sep 30 00:00:00 2026", "claude")
        self.assertFalse(self._build(_snap(procs=[p2])).source_alive)

    def test_target_token_reads(self):
        self.rec.submit_token = "tok-abc"
        self.rec.confirm_len = 0
        tgt = self._tx(self.tgt)
        with open(tgt, "w") as fh:
            fh.write(json.dumps({"type": "summary", "summary": "meta"}) + "\n")
            fh.write(
                json.dumps(
                    {
                        "type": "user",
                        "message": {
                            "role": "user",
                            "content": "continue (submit tok-abc)",
                        },
                    }
                )
                + "\n"
            )
            fh.write(
                json.dumps(
                    {
                        "type": "assistant",
                        "message": {
                            "role": "assistant",
                            "content": [{"type": "text", "text": "working"}],
                        },
                    }
                )
                + "\n"
            )
        ev = self._build(_snap())
        self.assertTrue(ev.token_is_this_attempt)
        self.assertGreater(ev.token_record_offset, 0)
        self.assertTrue(ev.nonerror_assistant_after_token)

    def test_history_pane_absent_and_sample(self):
        snap = _snap()
        ev = self._build(snap)
        E.advance_history(self.rec, ev, snap)
        self.assertEqual(self.rec.pane_absent_obs, 1)
        self.assertEqual(self._build(snap).pane_absent_observations, 2)
        h = T.HolderObs(pid=11, lstart=L, cfg=self.tgt, src="session-row", pane=(5, 7))
        s1 = _snap(
            sessions={"sid1": T.SessionObs(sid="sid1", holders=[h])}, wall=1000.0
        )
        E.advance_history(self.rec, self._build(s1), s1)
        s2 = _snap(
            sessions={"sid1": T.SessionObs(sid="sid1", holders=[h])}, wall=1010.0
        )
        self.assertFalse(self._build(s2).holder_stable_two_samples)
        s3 = _snap(
            sessions={"sid1": T.SessionObs(sid="sid1", holders=[h])}, wall=1016.0
        )
        self.assertTrue(self._build(s3).holder_stable_two_samples)


if __name__ == "__main__":
    unittest.main()
