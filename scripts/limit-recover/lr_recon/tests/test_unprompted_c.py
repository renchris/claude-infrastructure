"""RELAUNCHED/UNPROMPTED owes C (cohort next3-7d-1792497600, 2026-10-20).

e80b61f4 and 7aae55e1 were relaunched by R; lr-fire-resume logged READY-NOT-SEEN and typed nothing,
then stayed alive as the session's pty relay. Every pass saw that relay as a live launcher, stamped
busy_at with the pass's own clock, and the C grace (now - busy_at < 60 s) read 0 on the same pass:
no admission, no C, for 45 minutes. These tests replay that shape through _derive and _dispatch, and
the already-resumed shape (a prompt typed by hand and answered) through row 5."""

import json
import os
import shutil
import tempfile
import time
import unittest
from unittest import mock

from lr_recon import __main__ as M
from lr_recon import phase, tokens
from lr_recon import types as T
from lr_recon.evidence import slug

SID = "e80b61f4-d03f-464f-ab04-36d24f1a179b"
HOLDER_L = "Tue Oct 20 04:03:57 2026"
RELAY_L = "Tue Oct 20 04:03:49 2026"
JSONL = os.path.join(
    os.path.dirname(os.path.realpath(__file__)),
    *([".."] * 4),
    "tests",
    "fixtures",
    "lr-recon",
    "jsonl",
)
NOTIF = "<task-notification>\n<task-id>bp1xfgj4w</task-id>\n<status>completed</status>\n</task-notification>"


def _assistant() -> str:
    with open(os.path.join(JSONL, "assistant-turn.jsonl"), encoding="utf-8") as fh:
        return fh.readline().strip()


def _user(text: str) -> str:
    return json.dumps(
        {
            "type": "user",
            "isSidechain": False,
            "message": {"role": "user", "content": text},
        }
    )


class UnpromptedCTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.home = os.path.join(self.tmp, "home")
        os.makedirs(self.home)
        env = mock.patch.dict(
            os.environ,
            {"LR_STATE_DIR": os.path.join(self.tmp, "lr"), "HOME": self.home},
        )
        env.start()
        self.addCleanup(env.stop)
        for p in (
            mock.patch("lr_recon.admit.Admission.probe", return_value=(True, "admit")),
            mock.patch("lr_recon.admit.Admission.mint_token", return_value=None),
        ):
            p.start()
            self.addCleanup(p.stop)
        self.paths = T.Paths.from_env(root=os.path.join(self.tmp, "lr", "recon"))
        M.store.ensure_dirs(self.paths)
        self.cfg = {a: os.path.join(self.tmp, "cfg-" + a) for a in ("next3", "next")}
        for d in self.cfg.values():
            os.makedirs(os.path.join(d, "projects"), exist_ok=True)
        self.cwd = os.path.join(self.tmp, "wt")
        os.makedirs(self.cwd)

    def _rec(self) -> T.Record:
        rec = T.Record(sid=SID, record_id="recon:next3-7d-1792497600:e80b61f4:1")
        rec.kind, rec.pane, rec.root_shape = "limited", (853, 55), "launcher"
        rec.source_acct, rec.source_cfg = "next3", self.cfg["next3"]
        rec.source_pid, rec.source_lstart = 2248, "Tue Oct 20 00:01:38 2026"
        rec.target_acct, rec.target_cfg = "next", self.cfg["next"]
        rec.cwd, rec.submit_token, rec.attempt = self.cwd, "lrr-1714c778690b", 2
        rec.phase, rec.substate = "RELAUNCHED", "UNPROMPTED"
        rec.timeline.detected = time.time() - 4000
        rec.close["move_attempt"] = 2
        return rec

    def _target_tx(self, rec: T.Record, after: list) -> None:
        """A transplanted copy (confirm_len bytes) plus what the relaunched session appended."""
        d = os.path.join(self.cfg["next"], "projects", slug(self.cwd))
        os.makedirs(d, exist_ok=True)
        head = json.dumps({"type": "last-prompt", "lastPrompt": "x"}) + "\n"
        with open(os.path.join(d, SID + ".jsonl"), "w", encoding="utf-8") as fh:
            fh.write(head + "".join(line + "\n" for line in after))
        rec.confirm_len = len(head.encode("utf-8"))

    def _bundle(self, rec: T.Record, states: list) -> None:
        d = os.path.join(
            self.home, ".reso", "limit-recover", SID, "bundle-20261020T035635Z"
        )
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, "events.jsonl"), "w", encoding="utf-8") as fh:
            for st, stage in states:
                fh.write(
                    json.dumps(
                        {"state": st, "stage": stage, "attempt": str(rec.attempt)}
                    )
                    + "\n"
                )

    def _snap(self, now: float) -> T.Snapshot:
        h = T.HolderObs(
            30197, HOLDER_L, self.cfg["next"], "session-row", pane=(853, 55)
        )
        s = T.SessionObs(
            sid=SID,
            acct="next",
            cfg=self.cfg["next"],
            holders=[h],
            transcript=T.TranscriptObs(path="/t.jsonl"),
            pane=(853, 55),
        )
        relay = T.ProcRow(
            24868,
            1,
            "S",
            RELAY_L,
            "/bin/bash lr-fire-resume.sh next %s %s --prompt x" % (self.cwd, SID),
        )
        claude = T.ProcRow(30197, 29964, "S+", HOLDER_L, "claude --resume " + SID)
        return T.Snapshot(
            wall=now,
            uptime_raw=0.0,
            procs={24868: relay, 30197: claude},
            sessions={SID: s},
        )

    def _pass(self, rec: T.Record, now: float) -> mock.Mock:
        ctx = M.Ctx(self.paths, None, self.home)
        ctx.records = {SID: rec}
        snap = self._snap(now)
        M._derive(ctx, snap, now)
        with (
            mock.patch.object(M.act, "may_actuate", return_value=(True, "ok")),
            mock.patch.object(M.act, "spawn", return_value=4242) as sp,
            mock.patch.object(M.store, "append_launch"),
        ):
            M._dispatch(ctx, snap, "act", now)
        return sp

    def _spawned(self, sp: mock.Mock) -> list:
        return [c[0][2] for c in sp.call_args_list]

    # ── the stall ────────────────────────────────────────────────────────────────────────────

    def test_a_relay_whose_launcher_typed_nothing_does_not_hold_C(self):
        """The live shape: relay alive, READY-NOT-SEEN in this attempt's bundle. C goes out on the
        second pass (the first stamps the target sample), through admission."""
        rec = self._rec()
        self._bundle(rec, [("relaunch-typed", "expect"), ("READY-NOT-SEEN", "inject")])
        now = time.time()
        for n in range(3):
            sp = self._pass(rec, now + 20 * n)
            if self._spawned(sp):
                break
        self.assertEqual((rec.phase, rec.substate), ("RELAUNCHED", "UNPROMPTED"))
        self.assertEqual(self._spawned(sp), ["C"])
        self.assertLess(n, 2)  # bounded: no pass after the first holds it
        self.assertEqual(rec.close.get("typer_at"), 0.0)
        self.assertGreaterEqual(
            rec.close.get("busy_at", 0), now
        )  # busy_at keeps its meaning

    def test_a_launcher_still_typing_holds_C(self):
        """CONTROL: no verdict yet after relaunch-typed, so the launcher may still type."""
        rec = self._rec()
        self._bundle(
            rec, [("relaunch-typed", "expect"), ("submit-token-armed", "inject")]
        )
        now = time.time()
        for n in range(3):
            self.assertEqual(self._spawned(self._pass(rec, now + 20 * n)), [])
        self.assertGreaterEqual(rec.close["typer_at"], now)

    def test_a_silent_launcher_is_released_after_the_chain_bound(self):
        """No verdict ever written: the target holder's age bounds the launcher's typing."""
        rec = self._rec()
        self._bundle(rec, [("relaunch-typed", "expect")])
        now = time.time()
        self.assertEqual(self._spawned(self._pass(rec, now)), [])
        inside = now + M.settle.LAUNCHER_CHAIN_MAX_S - 1
        self.assertEqual(self._spawned(self._pass(rec, inside)), [])
        late = now + M.settle.LAUNCHER_CHAIN_MAX_S + 1
        self.assertEqual(self._spawned(self._pass(rec, late)), [])  # inside's stamp
        self.assertEqual(self._spawned(self._pass(rec, late + M.C_GRACE_S)), ["C"])

    def test_an_older_bundles_verdict_does_not_settle_a_new_run(self):
        """CONTROL: a relaunch-typed with no verdict after it re-opens the chain."""
        rec = self._rec()
        self._bundle(
            rec,
            [
                ("relaunch-typed", "expect"),
                ("READY-NOT-SEEN", "inject"),
                ("relaunch-typed", "expect"),
            ],
        )
        self.assertEqual(M.settle.launcher_settled(self.home, rec, time.time()), "")

    # ── the prompt went on the spawn argv (gap 1 lever 1) ─────────────────────────────────────

    def test_an_argv_prompt_holds_C_past_a_failed_verdict_until_the_chain_bound(self):
        """The relay passed the prompt on argv and its probe gave up (a boot slower than the poll):
        the CLI still holds the prompt, so C would be a second copy. Only the chain bound frees C."""
        rec = self._rec()
        self._bundle(
            rec,
            [
                ("gate-admitted", "gate"),
                ("relaunch-typed", "expect"),
                ("prompt-argv", "inject"),
                ("FAILED:submit", "submit"),
            ],
        )
        now = time.time()
        for n in range(3):
            self.assertEqual(self._spawned(self._pass(rec, now + 20 * n)), [])
        self.assertEqual(M.settle.launcher_settled(self.home, rec, now + 40), "")
        inside = now + M.settle.LAUNCHER_CHAIN_MAX_S - 1
        self.assertEqual(self._spawned(self._pass(rec, inside)), [])
        late = now + M.settle.LAUNCHER_CHAIN_MAX_S + 1
        self.assertEqual(self._spawned(self._pass(rec, late)), [])  # inside stamp
        self.assertEqual(self._spawned(self._pass(rec, late + M.C_GRACE_S)), ["C"])

    def test_an_argv_prompt_whose_record_landed_settles_the_launcher(self):
        rec = self._rec()
        self._bundle(
            rec,
            [
                ("relaunch-typed", "expect"),
                ("prompt-argv", "inject"),
                ("submitted", "submit"),
            ],
        )
        self.assertEqual(
            M.settle.launcher_settled(self.home, rec, time.time()),
            "launcher verdict submitted",
        )

    def test_a_typed_run_after_an_argv_run_reads_its_own_verdict(self):
        """CONTROL: prompt-argv belongs to the run it follows; a later relaunch-typed resets it."""
        rec = self._rec()
        self._bundle(
            rec,
            [
                ("relaunch-typed", "expect"),
                ("prompt-argv", "inject"),
                ("relaunch-typed", "expect"),
                ("READY-NOT-SEEN", "inject"),
            ],
        )
        self.assertEqual(
            M.settle.launcher_settled(self.home, rec, time.time()),
            "launcher verdict READY-NOT-SEEN",
        )

    # ── C is not charged a second first-turn admission (gap 1 lever 3) ────────────────────────

    def _refusing_admission(self):
        p = mock.patch(
            "lr_recon.admit.Admission.decide", return_value=(False, "cpu-brake")
        )
        p.start()
        self.addCleanup(p.stop)

    def test_C_rides_the_launchers_admission(self):
        """The launcher redeemed an admission for this first turn and typed nothing: C goes out
        even while a fresh admission would be refused."""
        self._refusing_admission()
        rec = self._rec()
        self._bundle(
            rec,
            [
                ("gate-admitted", "gate"),
                ("relaunch-typed", "expect"),
                ("READY-NOT-SEEN", "inject"),
            ],
        )
        now = time.time()
        spawned = []
        for n in range(3):
            spawned = self._spawned(self._pass(rec, now + 20 * n))
            if spawned:
                break
        self.assertEqual(spawned, ["C"])

    def test_C_without_a_launcher_admission_is_still_gated(self):
        """CONTROL: no gate-admitted in this attempt (an ungated or by-hand launch), so C pays."""
        self._refusing_admission()
        rec = self._rec()
        self._bundle(
            rec,
            [
                ("gate-absent", "gate"),
                ("relaunch-typed", "expect"),
                ("READY-NOT-SEEN", "inject"),
            ],
        )
        now = time.time()
        for n in range(3):
            self.assertEqual(self._spawned(self._pass(rec, now + 20 * n)), [])

    # ── the already-resumed shape ────────────────────────────────────────────────────────────

    def test_a_prompt_answered_after_the_relaunch_closes_engaged(self):
        """Somebody typed the continue by hand (what READY-NOT-SEEN asks for): row 5 closes it and
        C does not type a second one."""
        rec = self._rec()
        self._bundle(rec, [("relaunch-typed", "expect"), ("READY-NOT-SEEN", "inject")])
        self._target_tx(
            rec, [_user(NOTIF), _assistant(), _user("keep going"), _assistant()]
        )
        now = time.time()
        sp = self._pass(rec, now)
        self.assertEqual(rec.phase, "ENGAGED")
        self.assertEqual(self._spawned(sp), [])

    def test_a_notification_turn_after_the_relaunch_is_not_engagement(self):
        """CONTROL: the dead process's queued task-notification, answered 4 s after the relaunch,
        proves nothing (the 751/815 shape): it stays UNPROMPTED and gets its C."""
        rec = self._rec()
        self._bundle(rec, [("relaunch-typed", "expect"), ("READY-NOT-SEEN", "inject")])
        self._target_tx(rec, [_user(NOTIF), _assistant()])
        now = time.time()
        self._pass(rec, now)
        self.assertEqual((rec.phase, rec.substate), ("RELAUNCHED", "UNPROMPTED"))
        self.assertEqual(self._spawned(self._pass(rec, now + 20)), ["C"])

    def test_prompt_answered_after_opens_no_turn_at_the_boundary(self):
        lines = [_user(NOTIF), _assistant()]
        fd, path = tempfile.mkstemp(suffix=".jsonl")
        with os.fdopen(fd, "w") as fh:
            fh.write("\n".join(lines) + "\n")
        self.addCleanup(os.unlink, path)
        self.assertTrue(tokens.nonerror_after(path, -1))  # the submit-anchored reading
        self.assertFalse(tokens.prompt_answered_after(path, -1))
        with open(path, "a") as fh:
            fh.write(_user("continue") + "\n" + _assistant() + "\n")
        self.assertTrue(tokens.prompt_answered_after(path, -1))

    def test_row5_reason_names_the_proof(self):
        ev = T.Evidence(
            kind="limited",
            holders=[T.EvHolder(cfg="target", pane_bound=True)],
            confirm_len=100,
            prompt_answered_after_confirm=True,
        )
        res = phase.derive_phase(ev)
        self.assertEqual(
            (res.phase, res.reason), ("ENGAGED", "row5:prompt-answered>=confirm_len")
        )
        ev.prompt_answered_after_confirm = False
        self.assertEqual(phase.derive_phase(ev).phase, "RELAUNCHED")


if __name__ == "__main__":
    unittest.main()
