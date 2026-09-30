"""act: adoption by argv --record-id, zombies are dead, the intent nonce blocks a double spawn,
the §4.5 write order, and every kill switch in the gate on its safe side."""

import os
import subprocess
import tempfile
import time
import unittest

from lr_recon import act as A
from lr_recon import store
from lr_recon import types as T

L = "Tue Sep 29 11:19:17 2026"
NOW = 1_790_000_000.0


def _paths():
    tmp = tempfile.mkdtemp()
    p = T.Paths(lr_root=tmp, root=os.path.join(tmp, "recon"))
    store.ensure_dirs(p)
    return p


def _rec(**kw):
    base = dict(
        sid="abcdef01-0000",
        record_id="recon:c:abcdef01:1",
        target_acct="next4",
        substate="PLANNED",
        source_cfg="/c3",
        target_cfg="/c4",
        cwd="/w",
        pane=(5, 7),
    )
    base.update(kw)
    return T.Record(**base)


def _snap(*rows):
    return T.Snapshot(wall=NOW, uptime_raw=0.0, procs={r.pid: r for r in rows})


class ActTests(unittest.TestCase):
    def test_adoption_by_argv_record_id(self):
        rec = _rec()
        row = T.ProcRow(
            42,
            1,
            "S",
            L,
            "/bin/bash -c x lr-recon-act --record-id %s --intent n1 "
            "/bin/bash lr-handoff.sh" % rec.record_id,
        )
        other = T.ProcRow(43, 1, "S", L, "lr-recon-act --record-id recon:c:ffffffff:1")
        found = A.adopt(rec, _snap(row, other))
        self.assertEqual([(p.pid, p.role) for p in found], [(42, "actuator")])
        self.assertEqual(A.adopt(rec, _snap(row, other)), [])  # already recorded

    def test_zombie_is_dead(self):
        rec = _rec(procs=[T.ProcRole("actuator", 42, L)])
        self.assertEqual(A.live_procs(rec, _snap(T.ProcRow(42, 1, "Z", L, "x"))), [])
        self.assertEqual(
            len(A.live_procs(rec, _snap(T.ProcRow(42, 1, "S", L, "x")))), 1
        )
        rec2 = _rec(intent=T.Intent("n", NOW))
        z = T.ProcRow(42, 1, "Z", L, "--record-id %s" % rec2.record_id)
        self.assertEqual(A.settle_intent(rec2, _snap(z)), "cleared")

    def test_intent_nonce_blocks_double_spawn_after_kill9(self):
        """Daemon killed between spawn and the procs write: the record holds only the nonce."""
        paths = _paths()
        open(paths.recon_on, "w").close()
        rec = _rec(intent=T.Intent("n1", NOW, "A"))
        live = T.ProcRow(
            42, 1, "S", L, "lr-recon-act --record-id %s --intent n1" % rec.record_id
        )
        snap = _snap(live)
        self.assertEqual(A.settle_intent(rec, snap), "adopted")
        ok, why = A.may_actuate(paths, "act", rec, "A", snap, NOW, True, 0, 16, env={})
        self.assertEqual((ok, why), (False, "process-live"))

    def test_gate_safe_defaults(self):
        paths = _paths()
        rec, snap = _rec(), _snap()

        def g(mode="act", r=None, a="A", wake=True):
            return A.may_actuate(
                paths, mode, r or rec, a, snap, NOW, wake, 0, 16, env={}
            )

        self.assertEqual(g()[1], "recon-off")
        open(paths.recon_on, "w").close()
        self.assertEqual(g(mode="observe")[1], "mode-observe")
        self.assertEqual(g(mode="plan")[1], "mode-plan")
        self.assertEqual(g(r=_rec(plan_only=True))[1], "plan-only")
        self.assertEqual(g(a="HEAL")[1], "heal-disabled")
        self.assertEqual(g(wake=False)[1], "wake-guard")
        self.assertEqual(
            g(a="C", wake=False), (True, "ok")
        )  # typing a prompt is reversible
        self.assertEqual(g(), (True, "ok"))

    def test_gate_refuses_a_move_while_the_lead_has_live_members(self):
        """D4.4(d): the last line against a flicker — A never runs over a live member."""
        paths = _paths()
        open(paths.recon_on, "w").close()
        rec = _rec()
        member = T.ProcRow(
            77,
            1,
            "S",
            L,
            "claude.exe --agent-id w@session-x --parent-session-id %s" % rec.sid,
        )
        snap = _snap(member)
        self.assertEqual(
            A.may_actuate(paths, "act", rec, "A", snap, NOW, True, 0, 16, env={}),
            (False, "team-live"),
        )
        self.assertEqual(  # typing a continue into the lead is not a move
            A.may_actuate(paths, "act", rec, "C", snap, NOW, True, 0, 16, env={}),
            (True, "ok"),
        )
        self.assertEqual(
            A.may_actuate(paths, "act", rec, "A", _snap(), NOW, True, 0, 16, env={}),
            (True, "ok"),
        )

    def test_a_reboot_parked_record_never_actuates(self):
        """W5b2 cd3bd860: the census parked it, the same pass re-derived PANE-GONE/R, and nothing in
        the gate stopped R from running boot-resume-launch.sh over boot-resume's own posture."""
        paths = _paths()
        open(paths.recon_on, "w").close()
        rec = _rec(phase="PRE-MOVE", substate="PARKED-REBOOT")
        self.assertIsNone(A.choose(T.PhaseResult("PRE-MOVE", "PARKED-REBOOT", ""), rec))
        for a in ("R", "A", "B", "C"):
            self.assertEqual(
                A.may_actuate(paths, "act", rec, a, _snap(), NOW, True, 0, 16, env={}),
                (False, "parked-reboot"),
            )
        rec.phase, rec.substate = "PANE-GONE", "R"  # CONTROL: what the old pass derived
        self.assertEqual(A.choose(T.PhaseResult("PANE-GONE", "R", "R"), rec), "R")
        self.assertEqual(
            A.may_actuate(paths, "act", rec, "R", _snap(), NOW, True, 0, 16, env={}),
            (True, "ok"),
        )

    def test_the_wake_asks_the_focus_gate_before_it_types(self):
        """D4.9 + resolution 1: cmd_wake runs lr_focus_gate first; held ⇒ rc 6, nothing typed; no
        gate at all ⇒ rc 8, nothing typed; otherwise cc_tui_submit's own rc comes back."""
        tmp = tempfile.mkdtemp()
        lr, lib = os.path.join(tmp, "lr"), os.path.join(tmp, "lib")
        os.makedirs(lr)
        os.makedirs(lib)
        typed = os.path.join(tmp, "typed")
        with open(os.path.join(lib, "cc-tui.sh"), "w") as fh:
            fh.write(
                'cc_tui_submit() { cat "$2" > "%s"; echo "$1" >> "%s"; return "${SUBMIT_RC:-0}"; }\n'
                % (typed, typed)
            )
        gate = os.path.join(lr, "lr-lib.sh")
        payload = os.path.join(tmp, "p.txt")
        with open(payload, "w") as fh:
            fh.write("continue\n")
        rec = _rec(pane=(5, 7))

        def run(gate_body, **env):
            if gate_body is None:
                open(gate, "w").close()
            else:
                with open(gate, "w") as fh:
                    fh.write(gate_body)
            if os.path.exists(typed):
                os.unlink(typed)
            orig = (A.LR_DIR, A.SCRIPTS)
            A.LR_DIR, A.SCRIPTS = lr, tmp
            try:
                argv = A.cmd_wake(rec, payload)
            finally:
                A.LR_DIR, A.SCRIPTS = orig
            return subprocess.run(
                argv, capture_output=True, text=True, env=dict(os.environ, **env)
            )

        held = 'lr_focus_gate() { LR_FOCUS_HOLD="HELD:focused"; return 3; }\n'
        cp = run(held)
        self.assertEqual(cp.returncode, A.WAKE_HELD_RC)
        self.assertIn("verdict: HELD:focused", cp.stdout)
        self.assertFalse(os.path.exists(typed))
        cp = run(None)
        self.assertEqual(cp.returncode, A.WAKE_NO_GATE_RC)
        self.assertFalse(os.path.exists(typed))
        cp = run("lr_focus_gate() { return 0; }\n")
        self.assertEqual(cp.returncode, 0)
        with open(typed) as fh:
            self.assertEqual(fh.read(), "continue\n7\n")
        cp = run("lr_focus_gate() { return 0; }\n", SUBMIT_RC="3")
        self.assertEqual(cp.returncode, 3)

    def test_env_forces_bgwork_cancel(self):
        env = A.actuator_env(
            _rec(),
            _paths(),
            "unix:/tmp/kitty-5",
            base={"CC_RECYCLE_BGWORK_ANSWER": "exit"},
        )
        self.assertEqual(env["CC_RECYCLE_BGWORK_ANSWER"], "cancel")
        self.assertEqual(env["CC_TERM_KITTY_TO"], "unix:/tmp/kitty-5")
        self.assertNotIn(
            "LR_BARE_REPAIR", env
        )  # decision 5 SETTLED: the sibling heal stays on

    def test_an_idle_move_proves_its_relaunch_by_process_not_by_a_turn(self):
        # W5b real canary 3: a no-prompt relaunch owes no assistant turn; waiting for one declared
        # a working in-place rescue dead after 180 s and paged recycle-dead
        r = _rec()
        r.kind = "idle"
        self.assertEqual(
            A.actuator_env(r, _paths(), "", base={})["HF_ENGAGE_BY_PROCESS"], "1"
        )
        r.kind = "limited"  # CONTROL: a limited move types its prompt and proves it by the turn
        self.assertNotIn(
            "HF_ENGAGE_BY_PROCESS", A.actuator_env(r, _paths(), "", base={})
        )

    def test_env_never_claims_a_preseed_the_daemon_did_not_run(self):
        # W5b: LR_PRESEED_DONE makes lr-handoff and lr-fire-resume skip the target's folder-trust
        # seed; nothing in lr_recon runs lr-preseed-env.sh, so a real move to an account where
        # the cwd was never trusted stopped at the trust dialog
        env = A.actuator_env(_rec(), _paths(), "", base={})
        self.assertNotIn("LR_PRESEED_DONE", env)

    def test_spawn_write_order(self):
        paths = _paths()
        rec = _rec()
        seen = {}

        class P:
            pid = 4242

        def popen(argv, **kw):
            seen["intent_on_disk"] = store.load_record(paths, rec.sid).intent.nonce
            seen["argv"] = argv
            return P()

        pid = A.spawn(
            paths,
            rec,
            "A",
            ["/usr/bin/true"],
            {},
            NOW,
            popen=popen,
            lstart_of=lambda p: L,
        )
        self.assertEqual(pid, 4242)
        self.assertEqual(seen["intent_on_disk"], rec.intent.nonce)
        self.assertEqual(
            seen["argv"][4:8],
            ["--record-id", rec.record_id, "--intent", rec.intent.nonce],
        )
        self.assertEqual(store.load_record(paths, rec.sid).procs[0].pid, 4242)

    def test_an_actuator_exit_code_survives_other_subprocess_calls(self):
        """A later Popen's subprocess._cleanup reaped a collected Popen first, so waitpid saw
        nothing and the rc read "code unknown" (W5 rig: 32 of 113 exits lost)."""
        paths = _paths()
        pid = A.spawn(
            paths,
            _rec(),
            "A",
            ["/bin/sh", "-c", "sleep 0.2; exit 7"],
            dict(os.environ),
            NOW,
            lstart_of=lambda p: L,
        )
        time.sleep(0.6)
        subprocess.run(["/usr/bin/true"])
        A.reap_children()
        self.assertEqual(A.EXIT_CODES.pop(pid, None), 7)

    def test_wrapper_runs_command_with_token_in_argv(self):
        rec = _rec()
        argv = A.wrap(rec, "n9", ["/bin/sleep", "3"])
        p = subprocess.Popen(argv, start_new_session=True)
        try:
            time.sleep(0.3)
            ps = subprocess.run(
                ["/bin/ps", "-o", "args=", "-p", str(p.pid)],
                capture_output=True,
                text=True,
            ).stdout
            self.assertIn("--record-id %s --intent n9" % rec.record_id, ps)
        finally:
            p.kill()
            p.wait()

    def test_choose(self):
        rec = _rec()
        self.assertEqual(
            A.choose(T.PhaseResult("PRE-MOVE", "PLANNED", "plan"), rec), "A"
        )
        self.assertIsNone(
            A.choose(
                T.PhaseResult("PRE-MOVE", "WAIT_SLOT", "plan"),
                _rec(substate="WAIT_SLOT"),
            )
        )
        self.assertEqual(
            A.choose(T.PhaseResult("RELAUNCHED", "UNPROMPTED", "C"), rec), "C"
        )
        self.assertIsNone(A.choose(T.PhaseResult("RELAUNCHED", "SUBMITTED", "C"), rec))
        self.assertIsNone(A.choose(T.PhaseResult("EXITING", None, "wait"), rec))

    def test_no_launcher_is_no_argv(self):
        """handoff-fire aborts on `--resume-launcher ""`: never build that command (W5 rig)."""
        self.assertEqual(A.cmd_husk(_rec()), [])
        self.assertEqual(A.cmd_relaunch_at_shell(_rec(), "/i.json"), [])
        for argv in (
            A.cmd_husk(_rec(bundle="/b/l.sh")),
            A.cmd_relaunch_at_shell(_rec(bundle="/b/l.sh"), "/i.json"),
        ):
            self.assertEqual(argv[argv.index("--resume-launcher") + 1], "/b/l.sh")


if __name__ == "__main__":
    unittest.main()
