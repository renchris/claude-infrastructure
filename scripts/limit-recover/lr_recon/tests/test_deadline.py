"""W11 (B3, rescoped): the per-record deadline (docs/plans/LR_SUSTAINED_LOAD_IMPL.md § W11).

A LIMITED record carries deadline_at = timeline.detected + 600 s. Past it the record is OVERDUE and
its first turn skips the soft gates (restore-r, pace and pacer, which are still charged, the probe
and its drip) inside a lane of D = 6 un-ENGAGED deadline first turns, at most 3 per target account,
while the in-process hard stop reads clear. Every hard gate runs before it and is untouched.

Labels: [RED] fails on the parent tree for the behavioural reason (the red proof runs this file on
``git archive <W11 parent>`` in /tmp; cases that need a new API error there instead and are UNIT).
CONTROL passes in both arms and names the mutation it catches; MutantsDie proves each one dies.
Isolation: every case runs with HOME, LR_STATE_DIR, LR_RECON_ROOT and TMPDIR under a tempdir, and
the hard stop reads injected sources, never this machine's sentinel, sysctl or thermal state.
"""

import json
import math
import os
import shutil
import tempfile
import time
import unittest
from typing import Any, Dict, List, Optional, Tuple
from unittest import mock

from lr_recon import __main__ as M
from lr_recon import act, clock, classify, plan, report, settle, store
from lr_recon import admit as A
from lr_recon import types as T

REAL_PROBE = A.Admission.probe  # before any case patches it

L = "Tue Sep 29 11:19:17 2026"
D_ACC = getattr(A, "DEADLINE_PER_ACCT", 3)
WIDTH = getattr(A, "DEADLINE_WIDTH", 6)


def _quiet_hard(tmp: str, pressure: Any = 1, thermal: Any = 1) -> Any:
    if not hasattr(A, "HardStop"):
        return None
    return A.HardStop(
        sentinel_log=os.path.join(tmp, "no-sentinel.jsonl"),
        pressure=lambda: pressure,
        thermal=lambda: thermal,
    )


class Base(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.mkdtemp(prefix="w11-")
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.home = os.path.join(self.tmp, "home")
        os.makedirs(self.home)
        lr = os.path.join(self.tmp, "lr")
        env = mock.patch.dict(
            os.environ,
            {
                "HOME": self.home,
                "LR_STATE_DIR": lr,
                "LR_RECON_ROOT": os.path.join(lr, "recon"),
                "TMPDIR": os.path.join(self.tmp, "t"),
            },
        )
        env.start()
        self.addCleanup(env.stop)
        os.makedirs(os.path.join(self.tmp, "t"))
        self.probe = mock.patch(
            "lr_recon.admit.Admission.probe", return_value=(True, "admit")
        )
        self.probe_m = self.probe.start()
        self.addCleanup(self.probe.stop)
        self.mint = mock.patch(
            "lr_recon.admit.Admission.mint_token",
            side_effect=lambda sid, owes_prompt=True: "/tok/" + sid,
        )
        self.mint.start()
        self.addCleanup(self.mint.stop)
        self.paths = T.Paths.from_env(root=os.path.join(lr, "recon"))
        store.ensure_dirs(self.paths)
        open(self.paths.recon_on, "w").close()

    def ctx(self, mode: str = "on") -> M.Ctx:
        ctx = M.Ctx(self.paths, None, self.home)
        hard = _quiet_hard(self.tmp)
        if hard is not None:
            ctx.admission.hard = hard
        ctx.deadline = mode
        return ctx

    def rec(
        self,
        i: int,
        acct: str,
        detected: Optional[float],
        phase: str = "PRE-MOVE",
        substate: Optional[str] = "PLANNED",
        cid: str = "c",
    ) -> T.Record:
        sid = "d%07d-0000-0000-0000-000000000000" % i
        r = T.Record(
            sid=sid,
            record_id="recon:%s:%s:1" % (cid, sid[:8]),
            kind="limited",
            source_acct="next3",
            source_cfg="/c3",
            scope="7d",
            cohort_id=cid,
            target_acct=acct,
            target_cfg="/t",
            phase=phase,
            substate=substate,
        )
        r.timeline.detected = detected
        return r

    def dispatch(
        self, ctx: M.Ctx, now: float, snap: Optional[T.Snapshot] = None
    ) -> Tuple[int, List[Tuple[str, str, bool, str]]]:
        """One _dispatch; returns (spawned, [(sid, which, ok, why)] for every admission asked)."""
        seen: List[Tuple[str, str, bool, str]] = []
        orig = M._admit

        def spy(c: Any, rec: T.Record, which: str, sn: Any, nw: float) -> Any:
            ok, why = orig(c, rec, which, sn, nw)
            seen.append((rec.sid, which, ok, why))
            return ok, why

        with (
            mock.patch.object(M, "_admit", spy),
            mock.patch.object(M.act, "spawn", return_value=4242),
            mock.patch.object(M, "_command", return_value=["true"]),
        ):
            ctx.pass_mints = 0  # each call is a pass (_run_pass resets W9's mint cap)
            n = M._dispatch(
                ctx, snap or T.Snapshot(wall=now, uptime_raw=0.0), "act", now
            )
        return n, seen

    def events(self, ev: str) -> List[Dict[str, Any]]:
        try:
            with open(self.paths.events, encoding="utf-8") as fh:
                rows = [json.loads(x) for x in fh if x.strip()]
        except OSError:
            return []
        return [r for r in rows if r.get("ev") == ev]

    def cohort(
        self, n: int, accts: List[str], age: float, now: float, **kw: Any
    ) -> M.Ctx:
        ctx = self.ctx(kw.pop("mode", "on"))
        for i in range(n):
            r = self.rec(i, accts[i % len(accts)], now - age, **kw)
            ctx.records[r.sid] = r
        return ctx


# ── D: the deadline lane ──────────────────────────────────────────────────────────────────────────
class Lane(Base):
    def check_d1(self) -> None:
        now = time.time()
        ctx = self.cohort(30, ["next"], 1200.0, now)
        n, seen = self.dispatch(ctx, now)
        whys = [w for _s, _x, ok, w in seen if ok]
        self.assertEqual(n, D_ACC, seen)
        self.assertEqual(whys, ["admit:deadline"] * D_ACC)

    def test_d1_overdue_cohort_on_one_account_is_admitted_by_the_deadline_lane(
        self,
    ) -> None:
        """[RED] 30 PLANNED limited records on one account, detected now-1200: spawns = the
        per-account cap (3), every one admit:deadline (today: 3 through the pacer, "admit")."""
        self.check_d1()

    def check_d2(self) -> None:
        now = time.time()
        ctx = self.cohort(30, ["next"], 0.0, now)
        n, seen = self.dispatch(ctx, now)
        self.assertEqual(n, 3)
        self.assertEqual([w for _s, _x, ok, w in seen if ok], ["admit"] * 3)

    def test_d2_control_a_fresh_cohort_takes_todays_gates(self) -> None:
        """CONTROL: the same records detected now → 3 through the pacer, never admit:deadline.
        Mutation caught: overdue() always True."""
        self.check_d2()

    def check_d3(self) -> None:
        now = time.time()
        self.probe_m.return_value = (False, "capacity")
        self.probe_m.reset_mock()
        ctx = self.cohort(
            10,
            ["a0", "a1", "a2", "a3"],
            1200.0,
            now,
            phase="RELAUNCHED",
            substate="UNPROMPTED",
        )
        for sid in ctx.records:
            ctx.actions[sid] = "C"
        n, seen = self.dispatch(ctx, now)
        self.assertEqual(n, WIDTH, seen)
        self.assertEqual(self.probe_m.call_count, 0)

    def test_d3_standing_probe_refusal_does_not_hold_overdue_first_turns(self) -> None:
        """[RED] the probe standing at rc 9; 10 overdue C records over 4 accounts → 6 admitted in
        one pass (the lane), and the probe never called for them (today: refused "capacity")."""
        self.check_d3()

    def test_d4_decide_overdue_skips_the_probe(self) -> None:
        """UNIT: an overdue member with lane room is admitted without a probe call."""
        adm = A.Admission(runner=lambda argv: (9, ""), wall=lambda: 1000.0)
        adm.hard = _quiet_hard(self.tmp)
        adm.enter_active(0, 1, 8, now=1000.0)
        with mock.patch.object(A.Admission, "probe", wraps=adm.probe) as pr:
            ok, why = adm.decide(
                "s", "a", 1000.0, 0, 0, 1.0, 1.0, 10, "c", overdue=True, lane_room=True
            )
        self.assertEqual((ok, why), (True, "admit:deadline"))
        self.assertEqual(pr.call_count, 0)

    def test_d5_a_24_member_cohort_is_admitted_from_its_deadline(self) -> None:
        """UNIT (decide-level fact, cited only as such): 24 members on 8 accounts, a fake wall, 10 s
        passes, the probe standing on rc 9. Each lane member ENGAGES one pass after admission.
        Through the drip (1 per 30 s) most are in before the deadline; every member's first
        admission is by deadline + one pass (today: the last at +690 s, which this case re-measures
        in its own arm)."""
        self.probe_m.return_value = (False, "capacity")  # the probe standing on rc 9
        cure, deadline = self.d5_arm(True)
        today, _d = self.d5_arm(False)
        self.assertEqual(len(cure), 24)
        self.assertLessEqual(max(cure.values()), deadline + 10.0, sorted(cure.values()))
        self.assertGreater(
            max(today.values()), deadline + 10.0
        )  # the arm's own red value

    def d5_arm(self, on: bool) -> Tuple[Dict[int, float], float]:
        t0 = 10000.0
        wall = [t0]
        adm = A.Admission(runner=lambda argv: (9, ""), wall=lambda: wall[0])
        adm.hard = _quiet_hard(self.tmp)
        adm.enter_active(0, 24, 8, now=t0)
        deadline = t0 + 600.0
        first: Dict[int, float] = {}
        lane: Dict[int, float] = {}
        for p in range(80):
            now = t0 + 10.0 * p
            wall[0] = now
            adm.begin_pass(now)
            for k in [k for k, at in lane.items() if at < now]:
                del lane[k]  # ENGAGED by the next pass
            for i in range(24):
                if i in first:
                    continue
                acct = "a%d" % (i % 8)
                per = sum(1 for k in lane if "a%d" % (k % 8) == acct)
                room = len(lane) < WIDTH and per < D_ACC
                ok, why = adm.decide(
                    str(i),
                    acct,
                    now,
                    0,
                    0,
                    1.0,
                    1.0,
                    10,
                    "c",
                    overdue=on and now >= deadline,
                    lane_room=room,
                )
                if ok:
                    first[i] = now
                    if why == "admit:deadline":
                        lane[i] = now
        return first, deadline

    def lane_on(self, ctx: M.Ctx, acct: str) -> int:
        return sum(
            1
            for r in ctx.records.values()
            if r.close.get("deadline_admitted_at") is not None
            and r.phase not in ("ENGAGED", "MOVED")
            and (r.close.get("deadline_acct") or r.target_acct) == acct
        )

    def check_d6(self) -> None:
        now = time.time()
        self.probe_m.return_value = (False, "capacity")
        ctx = self.cohort(
            30, ["next"], 1200.0, now, phase="RELAUNCHED", substate="UNPROMPTED"
        )
        peak = 0
        for p in range(5):
            for sid in ctx.records:
                ctx.actions[sid] = "C"
            t = now + 10.0 * p
            _n, seen = self.dispatch(ctx, t)  # the C is gone by the next snapshot
            for sid, _w, ok, _why in seen:
                if ok:  # its prompt is typed: C's 60 s quiet grace keeps it out (as a census would)
                    ctx.records[sid].close["typer_at"] = t
            peak = max(peak, self.lane_on(ctx, "next"))
        self.assertGreater(peak, 0)
        self.assertLessEqual(peak, D_ACC)

    def test_d6_thirty_overdue_c_records_on_one_account_stay_within_the_cap(
        self,
    ) -> None:
        """30 overdue C records on one account over 5 passes, each C dead by the next snapshot: at
        every pass <= 3 un-ENGAGED deadline first turns on that account (F-A). Mutation caught:
        the lane counted live actuator processes."""
        self.check_d6()

    def test_d7_a_first_turn_that_never_engages_leaves_the_lane_after_t_att(
        self,
    ) -> None:
        now = time.time()
        ctx = self.ctx()
        r = self.rec(1, "next", now - 3000, phase="RELAUNCHED", substate="SUBMITTED")
        ctx.records[r.sid] = r
        r.close["deadline_admitted_at"] = now - (A.T_ATT_S - 1)
        M._deadline_lane(ctx, now)
        self.assertEqual(ctx.deadline_used, 1)
        r.close["deadline_admitted_at"] = now - (A.T_ATT_S + 1)
        M._deadline_lane(ctx, now)
        self.assertEqual(ctx.deadline_used, 0)

    def test_mint_failure_spawns_no_move_and_keeps_the_charges(self) -> None:
        """Lever 6: admit:deadline with no token minted → no A, a deadline-mint-failed event, the
        pacer charge kept, and the next pass tries again."""
        now = time.time()
        ctx = self.cohort(1, ["next"], 1200.0, now)
        with mock.patch("lr_recon.admit.Admission.mint_token", return_value=None):
            n, seen = self.dispatch(ctx, now)
        self.assertEqual(n, 0)
        self.assertEqual(seen[0][3], "deadline-mint-failed")
        self.assertEqual(len(self.events("deadline-mint-failed")), 1)
        sid = next(iter(ctx.records))
        self.assertIn(sid, ctx.admission.pacer.get("next", {}))
        self.assertNotIn(sid, ctx.boots.held)  # the boot slot went back
        n, _seen = self.dispatch(ctx, now + 30)
        self.assertEqual(n, 1)

    def test_one_probe_call_for_two_candidates(self) -> None:
        """Lever 5: a refusing reading is read once per pass and reused; it counts once toward
        DRIP_AFTER. An admitting reading admits one member, and the next one reads again."""
        calls = []

        def runner(argv: List[str]) -> Tuple[int, str]:
            calls.append(argv)
            return rc[0], ""

        rc = [9]
        adm = A.Admission(runner=runner, wall=lambda: 1000.0)
        adm.enter_active(0, 4, 8, now=1000.0)
        with mock.patch.object(A.Admission, "probe", REAL_PROBE):
            adm.begin_pass(1000.0)
            a = adm.decide("s1", "x", 1000.0, 0, 0, 1.0, 1.0, 10, "c")
            b = adm.decide("s2", "y", 1000.0, 0, 0, 1.0, 1.0, 10, "c")
            self.assertEqual((a, b), ((False, "capacity"), (False, "capacity")))
            self.assertEqual(len(calls), 1)
            self.assertEqual(adm.refusals["c"], 1)
            rc[0] = 0
            adm.begin_pass(1010.0)
            self.assertEqual(
                adm.decide("s1", "x", 1010.0, 0, 0, 1.0, 1.0, 10, "c")[1], "admit"
            )
            self.assertEqual(
                adm.decide("s2", "y", 1010.0, 0, 0, 1.0, 1.0, 10, "c")[1], "admit"
            )
            self.assertEqual(len(calls), 3)

    def test_workers_cap_is_a_named_wait_for_an_overdue_retry(self) -> None:
        """The retry bound counts the workers-cap (act.py may_actuate) as a named wait."""
        now = time.time()
        ctx = self.cohort(1, ["next"], 1200.0, now)
        with mock.patch.object(M.act, "workers_cap", return_value=0):
            n, _seen = self.dispatch(ctx, now)
        self.assertEqual(n, 0)
        r = next(iter(ctx.records.values()))
        self.assertEqual(r.close.get("deadline_hold"), "may:workers-cap")
        self.assertEqual(len(self.events("deadline-held")), 1)

    def test_a_reoffered_reset_wait_does_not_jump_a_fresh_detection(self) -> None:
        """Efficacy 8: a weekly-reset strand detected 3 days ago, re-offered after its wake, takes
        max(deadline_at, wake_due + W_wake) and sorts after a fresh detection whose deadline passed."""
        now = time.time()
        ctx = self.ctx()
        old = self.rec(1, "next", now - 3 * 86400, substate="WAIT_RESET")
        old.wait = T.Wait(reason="WAIT_RESET", since=now - 86400, eta=now - 1000)
        fresh = self.rec(2, "next", now - 1300)
        ctx.records = {old.sid: old, fresh.sid: fresh}
        snap = T.Snapshot(wall=now, uptime_raw=0.0)
        M._deadline_derive(ctx, old, now)  # waiting: the wake's due time is remembered
        old.substate, old.wait = (
            "PLANNED",
            None,
        )  # plan.movers re-offered it, apply placed it
        n, seen = self.dispatch(ctx, now, snap)
        self.assertGreaterEqual(
            old.deadline_at, now - 1000 + A.WAKE_AFTER_S + A.DEADLINE_WAKE_S
        )
        self.assertEqual([s for s, *_ in seen][:2], [fresh.sid, old.sid])


# ── the multi-pass bound: live actuators hold boot slots, the move lane holds 0 or 4 ────────────
class Bound(Base):
    T_ATT = 900.0
    P = 10.0
    MOVE_PID = os.getppid()

    def lease_until(self) -> float:
        try:
            with open(os.path.join(self.paths.lr_root, "locks", "slot-priority")) as fh:
                for ln in fh:
                    if ln.startswith("until="):
                        return float(ln[6:])
        except OSError:
            pass
        return 0.0

    def run_bound(
        self, held: int, k: int = 12
    ) -> Tuple[Dict[str, float], float, List[str]]:
        """k overdue limited records (deadline = t0) over 3 accounts; each actuator lives T_ATT and
        holds its boot slot. The move lane holds `held` of the 6 slots for T_ATT, then re-takes up
        to 4 by lr-move-lib.sh's rule: 1 while the slot-priority lease stands, else its width."""
        t = [1.9e9]
        t0 = t[0]
        slots = os.path.join(self.paths.lr_root, "locks", "swap-slots")
        os.makedirs(slots, exist_ok=True)
        move: Dict[int, float] = {}  # slot index -> release time

        def move_take(i: int, until: float) -> None:
            d = os.path.join(slots, "slot-%d" % i)
            os.makedirs(d, exist_ok=True)
            with open(os.path.join(d, "pid"), "w") as fh:
                fh.write("%d\n" % self.MOVE_PID)
            with open(os.path.join(d, "lstart"), "w") as fh:
                fh.write("MOVE\n")
            move[i] = until

        for i in range(1, held + 1):
            move_take(i, t0 + self.T_ATT)
        live: Dict[int, Tuple[str, float]] = {}  # pid -> (sid, dies)
        pid_seq = [50000]
        first: Dict[str, float] = {}
        with mock.patch.object(time, "time", lambda: t[0]):
            ctx = self.ctx()
            ctx.admission.wall = lambda: t[0]
            ctx.boots = M.BootSlots(store=slots)
            ctx.last_pass_s = self.P
            for i in range(k):
                r = self.rec(i, "a%d" % (i % 3), t0 - 600.0)
                ctx.records[r.sid] = r

            def spawn(paths: Any, rec: T.Record, which: str, *a: Any, **kw: Any) -> int:
                pid_seq[0] += 1
                live[pid_seq[0]] = (rec.sid, t[0] + self.T_ATT)
                rec.procs.append(
                    T.ProcRole("actuator", pid_seq[0], "SIM", which, "n%d" % pid_seq[0])
                )
                rec.substate = "IN-FLIGHT"
                first.setdefault(rec.sid, t[0])
                return pid_seq[0]

            def lstart(pid: int, unknown: str = "") -> str:
                return "MOVE" if pid == self.MOVE_PID else unknown

            with (
                mock.patch.object(M.act, "spawn", spawn),
                mock.patch.object(M, "_command", return_value=["true"]),
                mock.patch.object(M.store, "proc_lstart", lstart),
                mock.patch.object(M.act, "hold_claim", return_value=(True, "ours")),
                mock.patch.object(M.store, "append_launch"),
            ):
                while len(first) < k and t[0] < t0 + 20 * self.T_ATT:
                    now = t[0]
                    for pid in [p for p, (_s, dies) in live.items() if dies <= now]:
                        sid, _d = live.pop(pid)
                        ctx.records[sid].phase = "ENGAGED"
                    for i in [i for i, until in move.items() if until <= now]:
                        del move[i]
                        shutil.rmtree(os.path.join(slots, "slot-%d" % i), True)
                    if held:  # the move lane re-takes, by the bash rule
                        cap = 1 if self.lease_until() > now else 4
                        for i in range(1, 5):
                            if len(move) >= cap:
                                break
                            if i not in move and not os.path.isdir(
                                os.path.join(slots, "slot-%d" % i)
                            ):
                                move_take(i, now + self.T_ATT)
                    procs = {
                        p: T.ProcRow(p, 1, "S", "SIM", "lr-recon-act") for p in live
                    }
                    snap = T.Snapshot(wall=now, uptime_raw=0.0, procs=procs)
                    ctx.pass_mints = 0  # _run_pass's reset of W9's per-pass mint cap
                    M._dispatch(ctx, snap, "act", now)
                    t[0] += self.P
        order = sorted(first, key=lambda s: (first[s], s))
        return first, t0, order

    def check_bound(self, held: int) -> None:
        first, t0, order = self.run_bound(held)
        self.assertEqual(len(first), 12, "not every member was attempted")
        d_eff = 6 - min(held, 1)  # the lane yields to 1 slot once its own holds end
        t_hold = (
            self.T_ATT if held else 0.0
        )  # holds taken before the deadline are not preempted
        for k_r, sid in enumerate(order):
            bound = t0 + self.P + t_hold + math.ceil(k_r / d_eff) * self.T_ATT
            self.assertLessEqual(
                first[sid],
                bound,
                "member %d first at +%ds > +%ds" % (k_r, first[sid] - t0, bound - t0),
            )

    def test_bound_with_no_move_lane_slots_held(self) -> None:
        """Every t_first <= deadline + P + ceil(k_r/D_eff)·T_att, D_eff = 6."""
        self.check_bound(0)

    def test_bound_with_four_move_lane_slots_held(self) -> None:
        """[RED] with the move lane holding 4 of 6 slots, the slot-priority lease caps its re-take
        at 1, so D_eff = 5 after its own holds end (today it re-takes 4: D_eff 2, and member 11 is
        first attempted at +4500 s against a +3610 s bound)."""
        self.check_bound(4)


# ── H: hard gates are untouched, and the hard stop ──────────────────────────────────────────────
class HardGates(Base):
    def held(
        self, rec: T.Record, snap: T.Snapshot, now: float, action: str = ""
    ) -> None:
        ctx = self.ctx()
        ctx.records[rec.sid] = rec
        if action:
            ctx.actions[rec.sid] = action
        with (
            mock.patch.object(M.act, "spawn", return_value=4242) as sp,
            mock.patch.object(M, "_command", return_value=["true"]),
        ):
            M._dispatch(ctx, snap, "act", now)
        self.assertEqual(sp.call_count, 0)
        if not hasattr(M, "_deadline_note"):
            raise unittest.SkipTest("held on the parent tree; deadline_hold is W11's")
        self.assertTrue(rec.close.get("deadline_hold"), rec.close)
        return rec.close["deadline_hold"]

    def test_h1_team_live(self) -> None:
        now = time.time()
        r = self.rec(1, "next", now - 1200)
        snap = T.Snapshot(
            wall=now,
            uptime_raw=0.0,
            procs={
                77: T.ProcRow(
                    77,
                    1,
                    "S",
                    L,
                    "claude.exe --agent-id w@x --parent-session-id %s" % r.sid,
                )
            },
        )
        self.assertEqual(self.held(r, snap, now), "may:team-live")

    def test_h2_duplicate_risk(self) -> None:
        now = time.time()
        r = self.rec(1, "next", now - 1200)
        with (
            mock.patch.object(M.act, "replaces", return_value=True),
            mock.patch.object(
                M.act, "duplicate_risk", return_value="holder outside its pane"
            ),
        ):
            self.assertEqual(
                self.held(r, T.Snapshot(wall=now, uptime_raw=0.0), now),
                "may:duplicate-risk",
            )

    def test_h3_claim_held_by_a_live_driver(self) -> None:
        now = time.time()
        r = self.rec(1, "next", now - 1200)
        with mock.patch.object(M.act, "hold_claim", return_value=(False, "held")):
            self.assertEqual(
                self.held(r, T.Snapshot(wall=now, uptime_raw=0.0), now), "claim:held"
            )
        self.assertEqual(self.events("deadline-admit"), [])

    def test_h4_process_live(self) -> None:
        now = time.time()
        r = self.rec(1, "next", now - 1200)
        r.procs.append(T.ProcRole("actuator", 88, L, "A", "n"))
        snap = T.Snapshot(
            wall=now, uptime_raw=0.0, procs={88: T.ProcRow(88, 1, "S", L, "x")}
        )
        self.assertEqual(self.held(r, snap, now), "may:process-live")

    def test_h5_plan_only(self) -> None:
        now = time.time()
        r = self.rec(1, "next", now - 1200)
        r.plan_only = True
        self.assertEqual(
            self.held(r, T.Snapshot(wall=now, uptime_raw=0.0), now), "may:plan-only"
        )

    def test_h6_c_inside_its_quiet_grace(self) -> None:
        now = time.time()
        r = self.rec(1, "next", now - 1200, phase="RELAUNCHED", substate="UNPROMPTED")
        r.close["typer_at"] = now - 10
        self.assertEqual(
            self.held(r, T.Snapshot(wall=now, uptime_raw=0.0), now, action="C"),
            "grace:C",
        )

    def test_h7_census_holds_are_never_movers(self) -> None:
        now = time.time()
        recs = []
        for i, sub in enumerate(
            ("HOLD-DRAFT", "HOLD-BGWORK", "TEAMMATE", "SPLIT-BRAIN")
        ):
            r = self.rec(i, "", now - 5000, substate=sub)
            r.deadline_at = now - 4400
            recs.append(r)
        self.assertEqual(
            plan.movers(recs, T.Snapshot(wall=now, uptime_raw=0.0), now), []
        )

    def test_h8_env_and_argv_of_an_overdue_record_equal_a_fresh_ones(self) -> None:
        """CONTROL: the deadline passes nothing to the actuator. Mutation caught: any env flag or
        argument added for an overdue record."""
        now = time.time()
        ctx = self.ctx()
        a, b = self.rec(1, "next", now - 1200), self.rec(1, "next", now)
        a.deadline_at = now - 600
        self.assertEqual(
            act.actuator_env(a, self.paths, "s"), act.actuator_env(b, self.paths, "s")
        )
        self.assertEqual(M._command(ctx, a, "A"), M._command(ctx, b, "A"))

    # the hard stop
    def sentinel(self, **row: Any) -> str:
        p = os.path.join(self.tmp, "sentinel.jsonl")
        row.setdefault("ts", time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()))
        with open(p, "w") as fh:
            fh.write('{"ts":"old","pct":1}\n' + json.dumps(row) + "\n")
        return p

    def adm(self, hard: Any) -> A.Admission:
        adm = A.Admission(runner=lambda argv: (0, ""), wall=lambda: 1000.0)
        adm.hard = hard
        adm.enter_active(0, 1, 8, now=1000.0)
        return adm

    def overdue_decide(self, hard: Any) -> Tuple[bool, str, int]:
        adm = self.adm(hard)
        with mock.patch.object(
            A.Admission, "probe", return_value=(True, "admit")
        ) as pr:
            ok, why = adm.decide(
                "s", "a", 1000.0, 0, 0, 1.0, 1.0, 10, "c", overdue=True, lane_room=True
            )
        return ok, why, pr.call_count

    def test_h9_positive_evidence_trips_and_thermal_two_does_not(self) -> None:
        cases = [
            (dict(log=self.sentinel(pct=10, strk=1)), True),
            (dict(log=self.sentinel(pct=61, strk=0)), True),
            (dict(pressure=4), True),
            (dict(thermal=1), False),
            (dict(thermal=2), False),
            (dict(thermal=3), True),
        ]
        for kw, trips in cases:
            hard = A.HardStop(
                sentinel_log=kw.get("log", os.path.join(self.tmp, "absent")),
                pressure=lambda v=kw.get("pressure", 1): v,
                thermal=lambda v=kw.get("thermal", 1): v,
            )
            ok, why, probes = self.overdue_decide(hard)
            if trips:
                self.assertNotEqual(why, "admit:deadline", kw)
                self.assertEqual(probes, 1, kw)  # fell through to today's path
            else:
                self.assertEqual(why, "admit:deadline", kw)

    def test_h10_unknown_is_not_a_stop_and_says_unknown(self) -> None:
        hard = A.HardStop(
            sentinel_log=os.path.join(self.tmp, "absent"),
            pressure=lambda: None,
            thermal=lambda: None,
        )
        adm = self.adm(hard)
        self.assertEqual(
            adm.decide(
                "s", "a", 1000.0, 0, 0, 1.0, 1.0, 10, "c", overdue=True, lane_room=True
            )[1],
            "admit:deadline",
        )
        self.assertEqual(adm.last_terms, "deadline (memory unknown)")

    def test_h10b_torn_blank_string_and_stale_rows_never_raise(self) -> None:
        p = os.path.join(self.tmp, "s.jsonl")
        now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        for body, want in (
            ('{"ts":"%s","pct":' % now, ""),  # torn last line
            ('{"ts":"%s","pct":"","strk":""}' % now, ""),  # blank fields
            (
                '{"ts":"%s","pct":"61","strk":"0"}' % now,
                "compressor 61.0%",
            ),  # string fields
            ('{"ts":"2020-01-01T00:00:00Z","pct":99}', ""),  # stale
            ("[1,2]", ""),
        ):
            with open(p, "w") as fh:
                fh.write(body + "\n")
            hard = A.HardStop(
                sentinel_log=p, pressure=lambda: None, thermal=lambda: None
            )
            self.assertEqual(hard.check(), want, body)

        def boom() -> int:
            raise OSError("sysctl")

        hard = A.HardStop(sentinel_log=p, pressure=boom, thermal=boom)
        self.assertEqual(hard.check(), "")
        self.assertEqual(hard.state, "unknown")

    def test_h11_release_needs_two_clear_reads_30s_apart(self) -> None:
        wall = [1000.0]
        lvl = [4]
        hard = A.HardStop(
            sentinel_log=os.path.join(self.tmp, "absent"),
            pressure=lambda: lvl[0],
            thermal=lambda: 1,
            wall=lambda: wall[0],
        )
        self.assertTrue(hard.check())
        lvl[0] = 1
        wall[0] += 10
        self.assertTrue(hard.check())  # one clear read
        wall[0] += 20
        self.assertTrue(hard.check())  # 20 s after it: not yet
        wall[0] += 10
        self.assertEqual(hard.check(), "")  # 30 s after the first clear read
        self.assertIn("hardstop-release", [e for e, _d in hard.events])

    def test_h11b_tripped_then_unknown_releases_at_300s(self) -> None:
        wall = [1000.0]
        lvl: List[Optional[int]] = [4]
        hard = A.HardStop(
            sentinel_log=os.path.join(self.tmp, "absent"),
            pressure=lambda: lvl[0],
            thermal=lambda: None,
            wall=lambda: wall[0],
        )
        self.assertTrue(hard.check())
        lvl[0] = None
        wall[0] += 10
        self.assertTrue(hard.check())  # unknown from here
        wall[0] += (
            300 - 1
        )  # the stated bound, not the constant (its mutant must not move the clock)
        self.assertTrue(hard.check())
        wall[0] += 1
        self.assertEqual(hard.check(), "")
        self.assertIn("hardstop-unknown-release", [e for e, _d in hard.events])


# ── W: reset wakes ──────────────────────────────────────────────────────────────────────────────
class Wakes(Base):
    def stay(self, eta_ago: float) -> Tuple[M.Ctx, T.Snapshot, T.Record, float]:
        now = time.time()
        ctx = self.ctx()
        r = self.rec(1, "", now - 90000, substate="WAIT_RESET")
        r.pane = (5, 7)
        r.wait = T.Wait(
            reason="WAIT_RESET", since=now - 90000, eta=now - eta_ago, detail="stay"
        )
        ctx.records[r.sid] = r
        for i in range(3):
            ctx.admission.pacer_take("other%d" % i, "next3", now)
        pane = T.PaneObs(
            kitty_pid=5,
            window_id=7,
            sock="unix:/tmp/x",
            root_pid=20,
            root_lstart=L,
            root_shape="shell",
            state="claude",
        )
        return ctx, T.Snapshot(wall=now, uptime_raw=0.0, panes={"5:7": pane}), r, now

    def test_w1_an_overdue_wake_skips_the_pacer(self) -> None:
        """[RED] a stay whose wake deadline (eta + 300) passed 100 s ago, the source pacer full."""
        ctx, snap, r, now = self.stay(400)
        self.assertEqual(M._wakes(ctx, snap, {}, now), 1)
        self.assertEqual(ctx.actions[r.sid], "wake")
        self.assertIn(r.sid, ctx.admission.pacer["next3"])  # still charged

    def test_w2_control_inside_its_window_it_waits_on_the_pacer(self) -> None:
        """CONTROL: the same wake 100 s after due waits. Mutation caught: the pacer bypass at due."""
        ctx, snap, _r, now = self.stay(100)
        self.assertEqual(M._wakes(ctx, snap, {}, now), 0)


# ── C: the deadline is durable ──────────────────────────────────────────────────────────────────
class Durable(Base):
    def test_c1_a_sleep_shifts_the_deadline(self) -> None:
        """[RED] shift_record moves deadline_at (setattr, so the pre-fix tree fails on the value)."""
        r = self.rec(1, "next", 1000.0)
        setattr(r, "deadline_at", 1600.0)
        clock.shift_record(r, 3600.0)
        self.assertEqual(r.deadline_at, 5200.0)
        self.assertEqual(r.timeline.detected, 1000.0)

    def test_c2_a_restart_keeps_the_deadline(self) -> None:
        """[RED] save → load_all keeps deadline_at (restart neutrality, G6)."""
        r = self.rec(1, "next", 1000.0)
        setattr(r, "deadline_at", 1600.0)
        store.save_record(self.paths, r, 2000.0)
        got = store.load_all(self.paths, lambda *a: None)[r.sid]
        self.assertEqual(getattr(got, "deadline_at", None), 1600.0)

    def test_c3_set_once_kept_across_a_hop_and_lanes(self) -> None:
        r = self.rec(1, "next", 1000.0)
        self.assertTrue(A.ensure_deadline(r))
        self.assertEqual(r.deadline_at, 1600.0)
        r.timeline.detected = 5000.0
        self.assertFalse(A.ensure_deadline(r))  # never reset
        settle.new_attempt(r, None, "limit", 6000.0)
        self.assertEqual(r.deadline_at, 1600.0)
        settle.undo_hop(r)
        self.assertEqual(r.deadline_at, 1600.0)
        w = self.rec(2, "", 1000.0, substate="WAIT_RESET")
        w.wait = T.Wait(reason="WAIT_RESET", since=1000.0, eta=9000.0, detail="stay")
        self.assertEqual(A.deadline_of(w), 9000.0 + A.DEADLINE_WAKE_S)
        idle = self.rec(3, "next", 1000.0)
        idle.kind = "idle"
        self.assertFalse(A.ensure_deadline(idle))
        self.assertIsNone(A.deadline_of(idle))

    def test_env_none_resolves_to_the_process_environment(self) -> None:
        r = self.rec(1, "next", 1000.0)
        with mock.patch.dict(os.environ, {"LR_DEADLINE_SOFT_S": "100"}):
            A.ensure_deadline(r)
        self.assertEqual(r.deadline_at, 1100.0)
        broken = self.rec(2, "next", 1000.0)
        broken.timeline = None  # type: ignore[assignment]
        self.assertFalse(A.overdue(broken, 9e9))


# ── P: pages ────────────────────────────────────────────────────────────────────────────────────
class Pages(Base):
    def reporter(self, now: List[float]) -> Tuple[report.Reporter, List[str]]:
        sent: List[str] = []
        rep = report.Reporter(
            self.paths,
            "act",
            page=sent.append,
            mail=lambda p, t: None,
            now=lambda: now[0],
        )
        return rep, sent

    def cohort_of(self, recs: List[T.Record]) -> T.Cohort:
        return M._cohort(self.ctx(), "c", recs, recs[0].timeline.detected or 0.0)

    def backoff_rec(self, now: float) -> T.Record:
        r = self.rec(1, "next4", now - 2000, substate="BACKOFF")
        for i in range(8):
            classify.apply_failure(
                r, "TRANSIENT", "fp", "kitty rpc timeout %d" % i, now - 100
            )
        setattr(r, "deadline_at", now - 2000 + 600)
        return r

    def deadline_pages(self, sent: List[str]) -> List[str]:
        return [s for s in sent if "past their deadline" in s]

    def test_p1_one_deadline_page_then_hourly(self) -> None:
        """[RED] an overdue BACKOFF loop with no live actuator pages once at deadline + 900 s,
        naming its last error; nothing 60 s later; again an hour later. Through _report, the
        pre-existing entry point (today: BACKOFF_PAGE had no reader and nothing pages)."""
        t = time.time()
        r = self.backoff_rec(t)
        d = t - 2000 + 600
        now = [d + 901]
        rep, sent = self.reporter(now)
        ctx = self.ctx()
        ctx.records[r.sid] = r
        ctx.reporter, ctx.page_outbox, ctx.pass_caps = rep, False, False
        snap = T.Snapshot(wall=t, uptime_raw=0.0)

        def report_at(when: float) -> int:
            now[0] = when
            with mock.patch.object(M.report, "write_cohort"):
                M._report(ctx, "act", when, snap)
            return len(self.deadline_pages(sent))

        self.assertEqual(report_at(d + 901), 1)
        self.assertIn("kitty rpc timeout 7", self.deadline_pages(sent)[0])
        self.assertEqual(report_at(d + 961), 1)
        self.assertEqual(report_at(d + 961 + 3601), 2)

    def test_p1b_a_cohort_pages_once_for_twenty_members(self) -> None:
        """F-D: 20 members crossing W_hard in one pass → one sink call."""
        t = time.time()
        recs = []
        for i in range(20):
            r = self.rec(i, "next4", t - 2000, substate="BACKOFF")
            r.deadline_at = t - 1400
            recs.append(r)
        rep, sent = self.reporter([t])
        rep.deadline_page(self.cohort_of(recs), recs, set())
        self.assertEqual(len(sent), 1)
        self.assertIn("20 limited session(s)", sent[0])

    def check_p2(self) -> None:
        t = time.time()
        r = self.rec(1, "next4", t - 5000, substate="HOLD-DRAFT")
        r.wait = T.Wait(reason="HOLD-DRAFT", since=t - 4000)
        r.close["hold_since"] = {"HOLD-DRAFT": t - 4000}
        r.deadline_at = t - 4400
        rep, sent = self.reporter([t])
        cohort = self.cohort_of([r])
        page = getattr(
            rep, "deadline_page", lambda *a: None
        )  # the parent tree has none
        rep.max_age_page(cohort, r)
        page(cohort, [r], set())
        # reprobed: back to DETECTED → PLANNED with its hold history, still never a DEADLINE page
        r.substate, r.wait = "PLANNED", None
        page(cohort, [r], set())
        self.assertEqual(len([s for s in sent if "past its maximum age" in s]), 1)
        self.assertEqual(self.deadline_pages(sent), [])

    def test_p2_control_a_cycling_hold_pages_max_age_only(self) -> None:
        """CONTROL: a HOLD that cycles through reprobe → PLANNED pages MAX-AGE, never DEADLINE.
        Mutation caught: dropping the hold_since / age-latch exclusion (F-E)."""
        self.check_p2()

    def test_p2b_parked_wake_failed_plan_only_and_cohort_exit_are_excluded(
        self,
    ) -> None:
        t = time.time()
        recs = []
        for i, how in enumerate(("parked", "wake_failed", "plan_only", "cohort_exit")):
            r = self.rec(
                i,
                "next4",
                t - 5000,
                substate="PARKED-REBOOT" if how == "parked" else "BACKOFF",
            )
            r.deadline_at = t - 4400
            if how == "wake_failed":
                r.close["wake_failed"] = "x"
            if how == "plan_only":
                r.plan_only = True
            if how == "cohort_exit":
                r.close["cohort_exit"] = "x"
            recs.append(r)
        rep, sent = self.reporter([t])
        self.assertIsNone(rep.deadline_page(self.cohort_of(recs), recs, set()))
        self.assertEqual(sent, [])

    def test_p3_a_drip_opening_pages_once_per_cohort(self) -> None:
        """[RED] page_due had no reader: the drip's opening now pages DRIP, once per cohort."""
        now = time.time()
        self.probe_m.return_value = (False, "capacity")
        ctx = self.cohort(4, ["a", "b", "c2", "d"], 0.0, now)
        sent: List[str] = []
        ctx.reporter = report.Reporter(
            self.paths, "act", page=sent.append, mail=lambda p, t: None
        )
        for p in range(6):
            self.dispatch(ctx, now + 10 * p)
            with mock.patch.object(M.report, "write_cohort"):
                M._report(
                    ctx, "act", now + 10 * p, T.Snapshot(wall=now, uptime_raw=0.0)
                )
        self.assertEqual(len([s for s in sent if "drip" in s.lower()]), 1, sent)

    def test_backoff_page_is_wired(self) -> None:
        t = time.time()
        r = self.rec(1, "next4", t, substate="BACKOFF")
        for i in range(6):
            classify.apply_failure(r, "TRANSIENT", "fp", "x", t)
        rep, sent = self.reporter([t])
        cohort = self.cohort_of([r])
        rep.backoff_page(cohort, r)
        rep.backoff_page(cohort, r)
        self.assertEqual(len(sent), 1)
        self.assertIn("6 transient failures", sent[0])

    def test_an_actuator_past_t_att_pages_once_and_is_not_killed(self) -> None:
        t = time.time()
        old = time.strftime("%a %b %d %H:%M:%S %Y", time.localtime(t - A.T_ATT_S - 60))
        r = self.rec(1, "next4", t - 3000, phase="RELAUNCHED", substate="SUBMITTED")
        r.procs = [
            T.ProcRole("actuator", 91, old, "A", "n1"),
            T.ProcRole("actuator", 92, old, "adopted", ""),
        ]
        snap = T.Snapshot(
            wall=t,
            uptime_raw=0.0,
            procs={
                91: T.ProcRow(91, 1, "S", old, "x"),
                92: T.ProcRow(92, 1, "S", old, "y"),
            },
        )
        rep, sent = self.reporter([t])
        ctx = self.ctx()
        cohort = self.cohort_of([r])
        with mock.patch("os.kill") as kill:
            M._w11_record_pages(ctx, rep, cohort, r, snap, t)
            M._w11_record_pages(ctx, rep, cohort, r, snap, t)
        self.assertEqual(len(sent), 1)
        self.assertIn("pid 91", sent[0])
        self.assertEqual(kill.call_count, 0)

    def test_next_action_has_no_prefix_without_now(self) -> None:
        """F-C: no ``now``, no clock in the text; the DEADLINE page passes now and gets the prefix."""
        t = time.time()
        r = self.rec(1, "next4", t - 5000, substate="BACKOFF")
        r.deadline_at = t - 4400
        self.assertFalse(report.next_action(r).startswith("overdue"))
        self.assertTrue(report.next_action(r, t).startswith("overdue since "))

    def test_hard_stop_trip_past_w_hard_pages_once(self) -> None:
        t = time.time()
        ctx = self.ctx()
        r = self.rec(1, "next4", t - 3000)
        ctx.records[r.sid] = r
        wall = [t - A.DEADLINE_HARD_S - 1]
        ctx.admission.hard = A.HardStop(
            sentinel_log=os.path.join(self.tmp, "absent"),
            pressure=lambda: 4,
            thermal=lambda: 1,
            wall=lambda: wall[0],
        )
        ctx.admission.hard.check()
        sent: List[str] = []
        rep = report.Reporter(
            self.paths, "act", page=sent.append, mail=lambda p, x: None
        )
        M._hard_stop_report(ctx, rep, t)
        M._hard_stop_report(ctx, rep, t)
        self.assertEqual(len(sent), 1)
        self.assertIn("deadline bypass off: memory pressure level 4", sent[0])
        self.assertEqual(len(self.events("hardstop-trip")), 1)


# ── S: the switches ─────────────────────────────────────────────────────────────────────────────
class Switches(Base):
    def check_s1(self) -> None:
        now = time.time()
        open(self.paths.p("deadline.off"), "w").close()
        ctx = self.cohort(30, ["next"], 1200.0, now)
        if hasattr(
            A, "deadline_mode"
        ):  # the parent tree has no switch: its gates are today's
            ctx.deadline = A.deadline_mode(
                self.paths.p("deadline.off"), self.paths.p("deadline.shadow")
            )
        n, seen = self.dispatch(ctx, now)
        self.assertEqual(n, 3)
        self.assertEqual([w for _s, _x, ok, w in seen if ok], ["admit"] * 3)
        self.assertEqual(self.events("deadline-held"), [])

    def test_s1_control_deadline_off_is_todays_gates(self) -> None:
        """CONTROL: recon/deadline.off → D1's scenario spawns 3 through the pacer, no deadline
        event. Mutation caught: the switch ignored."""
        self.check_s1()

    def test_s2_shadow_logs_would_admit_only(self) -> None:
        now = time.time()
        open(self.paths.p("deadline.shadow"), "w").close()
        ctx = self.cohort(30, ["next"], 1200.0, now)
        ctx.deadline = A.deadline_mode(
            self.paths.p("deadline.off"), self.paths.p("deadline.shadow")
        )
        self.assertEqual(ctx.deadline, "shadow")
        n, seen = self.dispatch(ctx, now)
        self.assertEqual(n, 3)
        self.assertEqual([w for _s, _x, ok, w in seen if ok], ["admit"] * 3)
        self.assertEqual(len(self.events("deadline-shadow")), 27)

    def test_s2b_the_switch_gates_the_sort_and_the_lease(self) -> None:
        now = time.time()
        ctx = self.cohort(8, ["a1"], 1200.0, now)
        ctx.deadline = "off"
        with mock.patch.object(
            M.admit, "deadline_of", side_effect=AssertionError("read")
        ):
            self.dispatch(ctx, now)
        self.assertFalse(os.path.exists(A.slot_priority_path(self.paths.lr_root)))


# ── the slot-priority writer ────────────────────────────────────────────────────────────────────
class SlotPriority(Base):
    def test_an_overdue_move_refused_a_boot_slot_leases_priority_and_frees_it(
        self,
    ) -> None:
        now = time.time()
        ctx = self.cohort(8, ["a1", "a2", "a3"], 1200.0, now)
        ctx.last_pass_s = 120.0
        self.dispatch(ctx, now)  # 6 boots, then boot-slots refusals for the rest
        until = A.slot_priority_until(self.paths.lr_root)
        self.assertIsNotNone(until)
        self.assertGreaterEqual(until, now + 2 * 120.0 - 1)
        for r in ctx.records.values():
            r.substate = "IN-FLIGHT"  # nothing waits any more
        self.dispatch(ctx, now + 10)
        self.assertIsNone(A.slot_priority_until(self.paths.lr_root))


# ── lever 10: unknown-exit resolution ───────────────────────────────────────────────────────────
class UnknownExit(Base):
    def stuck(self, now: float, quiet: float) -> T.Record:
        r = self.rec(1, "next4", now - 3000, substate=None)
        r.close["exit_unknown"] = "A"
        r.close["busy_quiet_at"] = now - quiet
        r.timeline.planned = now - 2000
        return r

    def test_past_its_window_it_is_re_offered_as_a_counted_transient(self) -> None:
        now = time.time()
        r = self.stuck(now, settle.HOLDER_GONE_QUIET_S + 1)
        detail = settle.unknown_exit(self.paths, r, now)
        self.assertIn("re-offered", detail)
        self.assertEqual((r.phase, r.substate), ("PRE-MOVE", "BACKOFF"))
        self.assertEqual(r.attempt, 2)
        self.assertEqual(r.last_error.cls, "TRANSIENT")
        self.assertEqual(r.close["unknown_exit_retries"], 1)
        self.assertNotIn("exit_unknown", r.close)
        rep = report.Reporter(
            self.paths, "act", page=(sent := []).append, mail=lambda p, x: None
        )
        cohort = M._cohort(self.ctx(), "c", [r], now)
        rep.unknown_exit_page(cohort, r)
        rep.unknown_exit_page(cohort, r)
        self.assertEqual(len(sent), 1)

    def test_inside_its_window_or_after_a_confirm_it_waits(self) -> None:
        now = time.time()
        r = self.stuck(now, 10)
        self.assertEqual(settle.unknown_exit(self.paths, r, now), "")
        self.assertEqual(r.close.get("exit_unknown"), "A")
        ctx = self.ctx()
        ctx.records[r.sid] = r
        self.assertEqual(
            M._invariant(ctx, T.Snapshot(wall=now, uptime_raw=0.0), now), 0
        )
        r.timeline.confirmed = now
        self.assertEqual(settle.unknown_exit(self.paths, r, now + 100), "")
        self.assertNotIn("exit_unknown", r.close)

    def test_a_notmoved_log_is_rolled_backs_not_this(self) -> None:
        now = time.time()
        r = self.stuck(now, 120)
        log = settle.actlog(self.paths, r, "A")
        os.makedirs(os.path.dirname(log), exist_ok=True)
        with open(log, "w") as fh:
            fh.write("lr-handoff x: verdict=NOTMOVED\n")
        self.assertEqual(settle.unknown_exit(self.paths, r, now), "")

    def test_settle_exit_marks_a_codeless_move_exit(self) -> None:
        r = self.rec(1, "next4", 1000.0, substate=None)
        settle.settle_exit(r, T.ProcRole("actuator", 9, L, "A", "n"), None, "", 2000.0)
        self.assertEqual(r.close.get("exit_unknown"), "A")


# ── every new rule's mutant dies ────────────────────────────────────────────────────────────────
class MutantsDie(Base):
    def dies(self, check: Any, *patches: Any) -> None:
        import contextlib

        with contextlib.ExitStack() as es:
            for p in patches:
                es.enter_context(p)
            with self.assertRaises(AssertionError):
                check()

    def test_overdue_always_true_kills_d2(self) -> None:
        self.dies(
            Lane("check_d2").check_d2_in(self),
            mock.patch.object(M.admit, "overdue", return_value=True),
        )

    def test_lane_counting_live_procs_kills_d6(self) -> None:
        def by_procs(ctx: Any, now: float) -> None:
            ctx.deadline_used, ctx.deadline_per_acct = 0, {}

        self.dies(
            Lane("check_d6").check_d6_in(self),
            mock.patch.object(M, "_deadline_lane", by_procs),
        )

    def test_no_per_account_cap_kills_d1(self) -> None:
        self.dies(
            Lane("check_d1").check_d1_in(self),
            mock.patch.object(A, "DEADLINE_PER_ACCT", 99),
        )

    def test_switch_ignored_kills_s1(self) -> None:
        self.dies(
            Switches("check_s1").check_s1_in(self),
            mock.patch.object(A, "deadline_mode", return_value="on"),
        )

    def test_hold_exclusion_dropped_kills_p2(self) -> None:
        orig = report.Reporter.deadline_page

        def no_exclusion(rep: Any, cohort: Any, records: Any, live: Any) -> Any:
            for r in records:
                r.close.pop("hold_since", None)
            with mock.patch.object(report.Reporter, "_latch", lambda s, c: {}):
                return orig(rep, cohort, records, live)

        self.dies(
            Pages("check_p2").check_p2_in(self),
            mock.patch.object(report.Reporter, "deadline_page", no_exclusion),
        )

    def test_mint_rule_off_kills_the_mint_failure_case(self) -> None:
        t = Lane("test_mint_failure_spawns_no_move_and_keeps_the_charges")
        self.dies(
            lambda: Lane.test_mint_failure_spawns_no_move_and_keeps_the_charges(self),
            mock.patch.object(M.settle, "MOVE_ACTUATORS", ()),
        )
        del t

    def test_probe_memo_off_kills_one_probe_per_pass(self) -> None:
        def every_call(adm: Any, restore_r: int) -> Any:
            return adm.probe(restore_r)

        self.dies(
            lambda: Lane.test_one_probe_call_for_two_candidates(self),
            mock.patch.object(A.Admission, "_probe_pass", every_call),
        )

    def test_thermal_two_as_hard_kills_h9(self) -> None:
        self.dies(
            lambda: HardGates.test_h9_positive_evidence_trips_and_thermal_two_does_not(
                self
            ),
            mock.patch.object(A, "THERMAL_HARD", 2),
        )

    def test_no_unknown_release_kills_h11b(self) -> None:
        self.dies(
            lambda: HardGates.test_h11b_tripped_then_unknown_releases_at_300s(self),
            mock.patch.object(A, "UNKNOWN_RELEASE_S", 1e9),
        )

    def test_no_reoffer_rebase_kills_the_sort_case(self) -> None:
        self.dies(
            lambda: Lane.test_a_reoffered_reset_wait_does_not_jump_a_fresh_detection(
                self
            ),
            mock.patch.object(A, "sync_deadline", return_value=False),
        )

    def test_no_wake_bypass_kills_w1(self) -> None:
        self.dies(
            lambda: Wakes.test_w1_an_overdue_wake_skips_the_pacer(self),
            mock.patch.object(M.admit, "overdue", return_value=False),
        )

    def test_no_lease_kills_the_four_slot_bound(self) -> None:
        self.dies(
            lambda: Bound.check_bound(self, 4),
            mock.patch.object(A, "write_slot_priority", return_value=0.0),
        )


# MutantsDie runs another class's check on its own fixture (self): bind each by name.
for _cls in (Lane, Switches, Pages):
    for _name in [n for n in vars(_cls) if n.startswith("check_")]:
        setattr(
            _cls,
            _name + "_in",
            (lambda fn: lambda _self, other: lambda: fn(other))(vars(_cls)[_name]),
        )
for _name in (
    "stay",
    "held",
    "sentinel",
    "adm",
    "overdue_decide",
    "run_bound",
    "lease_until",
    "lane_on",
    "reporter",
    "cohort_of",
    "deadline_pages",
):
    for _cls in (Wakes, HardGates, Bound, Lane, Pages):
        if _name in vars(_cls):
            setattr(MutantsDie, _name, vars(_cls)[_name])
MutantsDie.T_ATT, MutantsDie.P, MutantsDie.MOVE_PID = (
    Bound.T_ATT,
    Bound.P,
    Bound.MOVE_PID,
)
del (
    _cls,
    _name,
)  # a module-level TestCase name would be collected, and run, a second time


if __name__ == "__main__":
    unittest.main()
