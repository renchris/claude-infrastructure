"""admit.py: frozen R, wall-clock pace, per-account pacer, drip, boot AIMD (§C6, §6).

Hermetic: the bash library is a fake runner; one optional test probes the real library, read-only."""

import json
import os
import shlex
import shutil
import subprocess
import tempfile
import unittest
from typing import Any, Callable, List, Tuple
from unittest import mock

from lr_recon import admit as A


class FakeRunner:
    def __init__(self, rc: int = 0, out: str = "") -> None:
        self.rc = rc
        self.out = out
        self.calls: List[List[str]] = []

    def __call__(self, argv: List[str]) -> Tuple[int, str]:
        self.calls.append(argv)
        return self.rc, self.out


class Wall:
    """The admission's own clock, set by hand: a test moves it apart from the pass ``now``."""

    def __init__(self, t: float = 0.0) -> None:
        self.t = t

    def __call__(self) -> float:
        return self.t


def active(runner: FakeRunner, wall: "Wall" = None, **kw: float) -> A.Admission:  # type: ignore[assignment]
    adm = A.Admission(runner=runner, repo="/repo", env={}, wall=wall or Wall())
    adm.enter_active(
        5,
        3,
        6,
        load1=kw.get("load1", 1.0),
        load5=kw.get("load5", 1.0),
        ncpu=10,
        now=0.0,
    )
    return adm


class RestoreBudget(unittest.TestCase):
    def test_r_is_frozen_at_entry(self) -> None:
        adm = active(FakeRunner())
        self.assertEqual(adm.restore_r, 8)
        # a later death: one active becomes one corpse; re-entry while ACTIVE changes nothing
        self.assertEqual(adm.enter_active(4, 4, 6), 8)
        self.assertEqual(adm.enter_active(9, 9, 20), 8)

    def test_ceiling_wins_when_larger(self) -> None:
        adm = A.Admission(runner=FakeRunner(), env={})
        self.assertEqual(adm.enter_active(2, 1, 6), 6)

    def test_growth_past_r_refused(self) -> None:
        adm = active(FakeRunner())
        self.assertEqual(
            adm.decide("s1", "a", 1.0, 5, 2, 1.0, 1.0, 10), (True, "admit")
        )
        # 6 active + 1 unredeemed + 1 = 8 <= 8 still restores; an operator's new session makes it 9
        self.assertTrue(adm.restore_ok(6, 1))
        self.assertEqual(
            adm.decide("s2", "b", 2.0, 7, 1, 1.0, 1.0, 10), (False, "restore-r")
        )

    def test_not_active_refuses_and_leave_resets(self) -> None:
        adm = A.Admission(runner=FakeRunner(), env={})
        self.assertEqual(
            adm.decide("s", "a", 0.0, 0, 0, 0.1, 0.1, 8), (False, "restore-r")
        )
        adm.enter_active(5, 3, 6)
        adm.leave_active()
        self.assertIsNone(adm.restore_r)
        self.assertEqual(adm.enter_active(1, 0, 6), 6)


class WallPace(unittest.TestCase):
    """Gate 2 is a wall-clock token bucket with no load term (REPORT §4 A4). It replaced a CPU brake
    that, at the operator's standing 15-40 per core, admitted one first turn per PASS: its load term
    never opened and its 20 s floor read the pass's single ``now``."""

    def test_load_is_not_a_gate(self) -> None:
        """Before: load1 40 on 10 cores, 1 s after ACTIVE entry, read (False, "cpu")."""
        adm = active(FakeRunner())
        self.assertEqual(
            adm.decide("s1", "a", 1.0, 0, 0, 400.0, 400.0, 10), (True, "admit")
        )
        self.assertEqual(
            adm.decide("s2", "b", 1.0, 0, 0, 40.0, 40.0, 10), (True, "admit")
        )

    def test_one_pass_admits_more_than_one(self) -> None:
        """Before: inside one pass (one ``now``) at load 30/core, only the first member passed;
        every later one read "cpu" until the next pass."""
        adm = active(FakeRunner(), wall=Wall(100.0), load1=1.0)
        got = [
            adm.decide("s%d" % i, "acct%d" % i, 50.0, 0, 0, 300.0, 300.0, 10)
            for i in range(4)
        ]
        self.assertEqual(got, [(True, "admit")] * 4)

    def test_paced_by_wall_time_not_by_pass(self) -> None:
        wall = Wall(0.0)
        adm = active(FakeRunner(), wall=wall)
        for i in range(A.PACE_BURST):
            self.assertEqual(
                adm.decide("b%d" % i, "acct%d" % i, 0.0, 0, 0, 1.0, 1.0, 10),
                (True, "admit"),
            )
        # the burst is spent: one pass, one ``now``, refused until wall time refills a token
        self.assertEqual(adm.decide("x", "q", 0.0, 0, 0, 1.0, 1.0, 10), (False, "pace"))
        wall.t = A.PACE_EVERY_S - 0.1
        self.assertEqual(adm.decide("x", "q", 0.0, 0, 0, 1.0, 1.0, 10), (False, "pace"))
        # same pass ``now`` still, but 20 s of wall time went by inside it
        wall.t = A.PACE_EVERY_S
        self.assertEqual(adm.decide("x", "q", 0.0, 0, 0, 1.0, 1.0, 10), (True, "admit"))
        # a later pass whose ``now`` jumped far ahead earns nothing the wall did not
        self.assertEqual(
            adm.decide("y", "r", 9999.0, 0, 0, 1.0, 1.0, 10), (False, "pace")
        )

    def test_the_bucket_never_holds_more_than_the_burst(self) -> None:
        wall = Wall(0.0)
        adm = active(FakeRunner(), wall=wall)
        adm.decide("a", "q", 0.0, 0, 0, 1.0, 1.0, 10)
        wall.t = 3600.0
        self.assertTrue(adm.pace_ok(wall.t))
        self.assertEqual(adm.pace_tokens, float(A.PACE_BURST))

    def test_leave_active_refills(self) -> None:
        adm = active(FakeRunner())
        for i in range(A.PACE_BURST):
            adm.decide("b%d" % i, "acct%d" % i, 0.0, 0, 0, 1.0, 1.0, 10)
        self.assertFalse(adm.pace_ok(0.0))
        adm.leave_active()
        self.assertTrue(adm.pace_ok(0.0))


class Pacer(unittest.TestCase):
    def test_three_per_account_then_release(self) -> None:
        adm = active(FakeRunner())
        for i in range(3):
            self.assertTrue(
                adm.decide("s%d" % i, "acct1", 1.0 + i, 0, 0, 1.0, 1.0, 10)[0]
            )
        self.assertEqual(
            adm.decide("s3", "acct1", 5.0, 0, 0, 1.0, 1.0, 10), (False, "pacer:acct1")
        )
        self.assertTrue(
            adm.decide("x", "acct2", 5.0, 0, 0, 1.0, 1.0, 10)[0]
        )  # other accounts unaffected
        adm.pacer_release("s0")  # ENGAGED
        self.assertTrue(adm.decide("s3", "acct1", 6.0, 0, 0, 1.0, 1.0, 10)[0])
        self.assertEqual(
            adm.decide("s4", "acct1", 7.0, 0, 0, 1.0, 1.0, 10), (False, "pacer:acct1")
        )
        self.assertTrue(
            adm.decide("s4", "acct1", 22.0, 0, 0, 1.0, 1.0, 10)[0]
        )  # s1 submitted at 2.0

    def test_env_override_and_wake_jitter(self) -> None:
        adm = A.Admission(runner=FakeRunner(), env={"LR_PACER_PER_ACCT": "1"})
        self.assertEqual(adm.pace_wake("w1", "a", 0.0), (True, "admit"))
        self.assertEqual(adm.pace_wake("w2", "a", 1.0), (False, "pacer:a"))
        j = A.jitter_s("abc")
        self.assertEqual(j, A.jitter_s("abc"))
        self.assertTrue(
            all(0.0 <= A.jitter_s("sid-%d" % i) <= 60.0 for i in range(200))
        )
        self.assertGreater(len({A.jitter_s("sid-%d" % i) for i in range(200)}), 20)


class Library(unittest.TestCase):
    def test_probe_rc_mapping_and_command(self) -> None:
        r = FakeRunner(rc=0)
        adm = A.Admission(runner=r, repo="/repo x", env={})
        self.assertTrue(adm.library_probe(8))
        cmd = r.calls[0][2]
        self.assertIn("source '/repo x/scripts/lib/capacity-admit.sh'", cmd)
        self.assertIn(
            "CC_ADMIT_RESTORE_R=8 cc_capacity_probe lr-reconciler first-turn", cmd
        )
        self.assertNotIn("cc_capacity_admit", cmd)
        r.rc = 9
        self.assertEqual(adm.probe(8), (False, "capacity"))
        r.rc = 1
        self.assertEqual(adm.probe(8), (False, "probe-error rc=1"))

    def test_a_timeout_is_not_a_probe_error(self) -> None:
        """2026-10-20, next3 cohort: six "probe-error" refusals at load ~259 were the runner's 30 s
        bound firing on a demoted child; by hand the same probe answered 0 or 9 in under 5 s. The
        refusal now says which it was, in the reason the event and the status line carry verbatim."""
        r = FakeRunner(rc=A.RC_TIMEOUT)
        adm = active(r)
        self.assertEqual(adm.probe(8), (False, "probe-timeout"))
        self.assertEqual(
            adm.decide("s", "a", 1.0, 0, 0, 1.0, 1.0, 10), (False, "probe-timeout")
        )
        r.rc = 3
        self.assertEqual(adm.probe(8), (False, "probe-error rc=3"))
        r.rc = A.RC_SPAWN_ERROR
        self.assertEqual(adm.probe(8), (False, "probe-error rc=-1"))
        r.rc = 0
        self.assertEqual(adm.probe(8), (True, "admit"))
        r.rc = 9
        self.assertEqual(adm.probe(8), (False, "capacity"))

    def test_default_runner_keeps_timeout_and_spawn_error_apart(self) -> None:
        def raises(exc: BaseException) -> Callable[..., Any]:
            def run(*_a: Any, **kw: Any) -> Any:
                self.assertEqual(kw["timeout"], 30)  # the bound itself is unchanged
                raise exc

            return run

        with mock.patch.object(
            A, "run_bounded", raises(subprocess.TimeoutExpired("bash", 30))
        ):
            self.assertEqual(A.default_runner(["bash"]), (A.RC_TIMEOUT, ""))
        with mock.patch.object(A, "run_bounded", raises(OSError("no such file"))):
            self.assertEqual(A.default_runner(["bash"]), (A.RC_SPAWN_ERROR, ""))
        self.assertNotEqual(A.RC_TIMEOUT, A.RC_SPAWN_ERROR)

    def test_mint_token(self) -> None:
        r = FakeRunner(rc=0, out="/tmp/tok/s1.abc\n")
        adm = A.Admission(runner=r, env={})
        self.assertEqual(adm.mint_token("s1"), "/tmp/tok/s1.abc")
        self.assertEqual(r.calls[0][-2:], ["s1", "turn"])
        self.assertIn(
            'CC_ADMIT_TOKEN_KIND="$2" cc_capacity_token_mint "$1"', r.calls[0][2]
        )
        # a move that owes no prompt mints a swap token, which the in-flight count leaves out
        self.assertEqual(adm.mint_token("s1", owes_prompt=False), "/tmp/tok/s1.abc")
        self.assertEqual(r.calls[1][-2:], ["s1", "swap"])
        self.assertIsNone(adm.mint_token("bad sid"))
        r.rc = 1
        self.assertIsNone(adm.mint_token("s1"))

    def test_memory_refusal_is_named(self) -> None:
        adm = active(FakeRunner(rc=9))
        self.assertEqual(
            adm.decide("s", "a", 1.0, 0, 0, 1.0, 1.0, 10), (False, "capacity")
        )

    @unittest.skipUnless(
        os.path.isfile(os.path.join(A.REPO_ROOT, A.LIB_REL)) and shutil.which("bash"),
        "library missing",
    )
    def test_real_probe_answers(self) -> None:
        """The probe writes one IDL row per call: point it at a temp one, never the live IDL."""
        tmp = tempfile.mkdtemp(prefix="lr-admit-")
        idl = os.path.join(tmp, "idl.jsonl")
        adm = A.Admission(
            runner=lambda argv: A.default_runner(
                argv[:2]
                + [
                    "export HOME=%s CC_ADMIT_IDL=%s CC_ADMIT_NOTIFY_BIN=/usr/bin/true; %s"
                    % (shlex.quote(tmp), shlex.quote(idl), argv[2])
                ]
            )
        )
        ok, reason = adm.probe(8)
        self.assertIn(reason, ("admit", "capacity"))
        with open(idl, encoding="utf-8") as fh:
            rows = [json.loads(x) for x in fh if x.strip()]
        self.assertTrue(rows, "the probe wrote no row to the temp IDL")
        shutil.rmtree(tmp, ignore_errors=True)

    def test_the_probe_runs_with_the_load_term_off(self) -> None:
        r = FakeRunner(rc=0)
        active(r).probe(8)
        self.assertIn("CC_ADMIT_LOAD_TERM=off", r.calls[-1][2])


class Drip(unittest.TestCase):
    def test_one_per_30s_after_three_refusals(self) -> None:
        r = FakeRunner(rc=9)
        wall = Wall()
        adm = active(r, wall=wall)

        def ask(sid: str, t: float) -> Tuple[bool, str]:
            wall.t = t
            return adm.decide(sid, "a%s" % sid, t, 0, 0, 1.0, 1.0, 10, cohort="c1")

        self.assertEqual(
            [ask("1", 1.0), ask("2", 2.0), ask("3", 3.0)], [(False, "capacity")] * 3
        )
        self.assertFalse(adm.page_due)
        self.assertEqual(ask("4", 4.0), (True, "admit:drip"))
        self.assertTrue(adm.page_due)
        adm.page_due = False
        self.assertEqual(ask("5", 20.0), (False, "drip"))
        self.assertEqual(ask("5", 34.0), (True, "admit:drip"))
        self.assertFalse(adm.page_due)  # paged once per cohort
        r.rc = 0
        self.assertEqual(ask("6", 35.0), (True, "admit"))
        r.rc = 9
        self.assertEqual(
            ask("7", 36.0), (False, "capacity")
        )  # a real admission reset the run

    def test_the_drip_bound_holds_at_load_400_on_10_cores(self) -> None:
        """The guarantee (REPORT §5, operator premise: load never falls). The probe refuses every
        time and load1 is 400 on 10 cores; a member is still admitted after DRIP_AFTER refusals,
        and each later member within DRIP_EVERY_S of wall time. Before: the brake read 40/core
        against a 2.5 limit and refused "cpu" in front of the drip until 20 s after ACTIVE entry,
        and a "cpu" refusal never counted toward the drip's run."""
        for rc in (9, A.RC_TIMEOUT):
            wall = Wall(1000.0)
            adm = active(FakeRunner(rc=rc), wall=wall)  # entry at pass now 0.0
            got = [
                adm.decide("m%d" % i, "q%d" % i, 1.0, 0, 0, 400.0, 400.0, 10, "c1")
                for i in range(A.DRIP_AFTER + 1)
            ]
            self.assertTrue(all(not ok for ok, _ in got[: A.DRIP_AFTER]), got)
            self.assertEqual(got[-1], (True, "admit:drip"))
            # the next member: refused only by the drip's own clock, then admitted on wall time
            # alone, with the pass ``now`` never moving
            wall.t += A.DRIP_EVERY_S - 1
            self.assertEqual(
                adm.decide("n", "r", 1.0, 0, 0, 400.0, 400.0, 10, "c1"), (False, "drip")
            )
            wall.t += 1
            self.assertEqual(
                adm.decide("n", "r", 1.0, 0, 0, 400.0, 400.0, 10, "c1"),
                (True, "admit:drip"),
            )

    def test_cohorts_count_separately(self) -> None:
        adm = active(FakeRunner(rc=9))
        for i in range(3):
            adm.decide("x%d" % i, "q%d" % i, 1.0, 0, 0, 1.0, 1.0, 10, cohort="c1")
        self.assertEqual(
            adm.decide("y", "z", 2.0, 0, 0, 1.0, 1.0, 10, cohort="c2"),
            (False, "capacity"),
        )


class Boots(unittest.TestCase):
    def test_aimd(self) -> None:
        b = A.BootSlots(env={})
        self.assertEqual((b.limit, b.cap, b.workers_cap), (6, 12, 16))
        self.assertEqual(b.on_wave([5.0, 9.0, 15.0]), 8)
        self.assertEqual(
            b.on_wave([5.0, 20.0]), 8
        )  # neither all-fast nor any-slow: hold
        self.assertEqual(b.on_wave([5.0]), 10)
        self.assertEqual(b.on_wave([5.0]), 12)
        self.assertEqual(b.on_wave([5.0]), 12)  # cap
        self.assertEqual(b.on_wave([5.0, 46.0]), 6)
        self.assertEqual(b.on_wave([None]), 3)  # INDETERMINATE
        self.assertEqual(b.on_wave([50.0]), 2)
        self.assertEqual(b.on_wave([50.0]), 2)  # floor
        self.assertEqual(b.on_wave([]), 2)

    def test_env_and_slots(self) -> None:
        b = A.BootSlots(env={"LR_BOOT_MAX": "7", "LR_RECON_WORKERS": "4"})
        self.assertEqual((b.limit, b.cap, b.workers_cap), (6, 7, 4))
        self.assertEqual(b.on_wave([1.0]), 7)
        b = A.BootSlots(env={"LR_BOOT_MAX": "junk"})
        self.assertEqual(b.cap, 12)
        b.limit = 2
        self.assertTrue(b.acquire("a") and b.acquire("b") and b.acquire("a"))
        self.assertFalse(b.acquire("c"))
        b.release("a")
        self.assertTrue(b.acquire("c"))

    def test_shared_store_counts_the_move_lanes_slots(self) -> None:
        """A boot slot is also one of `cc-lr move`'s slot directories, so each dispatcher's width
        counts the other's boots; without a store (the control) the two cannot see each other."""
        import tempfile

        with tempfile.TemporaryDirectory() as root:
            store = os.path.join(root, "locks", "swap-slots")
            os.makedirs(os.path.join(store, "slot-1"))
            # slot-1 is held by a LIVE process of the move lane (this test process stands in for it)
            with open(
                os.path.join(store, "slot-1", "pid"), "w", encoding="utf-8"
            ) as fh:
                fh.write("%d\n" % os.getpid())
            b = A.BootSlots(env={}, store=store)
            b.limit = 2
            self.assertTrue(b.acquire("a"))
            self.assertEqual(os.path.basename(b.disk["a"]), "slot-2")
            self.assertFalse(
                b.acquire("b")
            )  # the lane's slot counts against this width
            control = A.BootSlots(env={})
            control.limit = 2
            self.assertTrue(control.acquire("a") and control.acquire("b"))
            b.release("a")
            self.assertFalse(os.path.exists(os.path.join(store, "slot-2")))
            # a slot whose holder is dead is taken over
            with open(
                os.path.join(store, "slot-1", "pid"), "w", encoding="utf-8"
            ) as fh:
                fh.write("999999\n")
            self.assertTrue(b.acquire("c"))
            self.assertEqual(os.path.basename(b.disk["c"]), "slot-1")


if __name__ == "__main__":
    unittest.main()
