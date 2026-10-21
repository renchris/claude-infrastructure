"""B6 telemetry (wave W6 of docs/plans/LR_SUSTAINED_LOAD_IMPL.md; design impl/B6-telemetry.md §9).

Hermetic: tmp roots, injected wall/monotonic/CPU clocks, injected ``read_pri``/``census``/kitty
reads, so no test censuses the live box. The red-before-fix controls R1-R5 read only disk; T3-T16
are the equivalence guards and remaining tests. Run under /usr/bin/python3 (3.9.6, the plist's
interpreter) as well as python3 on PATH: tests/lr-recon-telemetry.bats asserts the count."""

import io
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from contextlib import redirect_stdout
from unittest import mock

from lr_recon import __main__ as M
from lr_recon import act, band, plan, report, store, telemetry
from lr_recon import clock as C
from lr_recon import types as T

HERE = os.path.dirname(os.path.abspath(__file__))
PKG = os.path.dirname(HERE)
LR_DIR = os.path.dirname(PKG)
L = "Tue Sep 29 11:19:17 2026"


class Clk:
    def __init__(self, w: float = 1000.0) -> None:
        self.w, self.m, self.cpu = w, 0.0, 0.0

    def wall(self) -> float:
        return self.w

    def mono(self) -> float:
        return self.m

    def tt(self) -> float:
        return self.cpu

    def adv(self, s: float) -> None:
        self.w += s
        self.m += s


def sid(i: int) -> str:
    return "abcdef01-0000-0000-0000-%012d" % i


def rec(i: int, det: float = 1000.0, sub: str = "DETECTED") -> T.Record:
    r = T.Record(sid=sid(i), record_id="recon:c1:%08d:1" % i, cohort_id="c1")
    r.timeline.detected = det
    r.substate = sub
    return r


class Base(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.mkdtemp(prefix="w6tel.")
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.home = os.path.join(self.tmp, "home")
        os.makedirs(self.home)
        self.env = mock.patch.dict(
            os.environ,
            {
                "HOME": self.home,
                "LR_STATE_DIR": os.path.join(self.tmp, "lr"),
                "LR_RECON_ROOT": os.path.join(self.tmp, "lr", "recon"),
            },
        )
        self.env.start()
        self.addCleanup(self.env.stop)
        self.paths = T.Paths.from_env(root=os.path.join(self.tmp, "lr", "recon"))
        store.ensure_dirs(self.paths)
        self.clk = Clk()

    def tel(self, **kw):
        base = dict(
            env={},
            wall=self.clk.wall,
            mono=self.clk.mono,
            thread_time=self.clk.tt,
            read_pri=lambda pid=None: 31,
            census=lambda: {
                "run": {"31": 3},
                "thr": 10,
                "procs": 2,
                "of": 3,
                "partial": False,
            },
            kitty_pri=lambda pid: (47, 47),
            loadavg=lambda: (150.0, 0.0, 0.0),
            thermal=lambda: 1,
            pressure=lambda: 1,
            kitty_glob=os.path.join(self.tmp, "kitty-*"),
        )
        base.update(kw)
        return telemetry.Telemetry(self.paths, **base)

    def rows(self, k=None):
        try:
            with open(self.paths.p(telemetry.FILE), encoding="utf-8") as fh:
                out = [json.loads(ln) for ln in fh]
        except FileNotFoundError:
            return []
        return [r for r in out if k is None or r["k"] == k]

    def heartbeat(self, now, **kw):
        hb = {
            "pid": 1,
            "lstart": L,
            "progress": 1,
            "wall": now,
            "uptime_raw": 0.0,
            "progress_wall": now,
            "phase": "idle",
            "phase_at": now,
            "pass_seq": 0,
            "pass_at": 0.0,
        }
        hb.update(kw)
        with open(self.paths.heartbeat, "w") as fh:
            json.dump(hb, fh)

    def readout(self, now, **kw):
        return telemetry.readout(self.paths, now, env={}, **kw)

    def one_pass(self, t, records=(), seq=None, dt=1.0, snap=None):
        t.pass_begin(t.seq + 1 if seq is None else seq)
        if snap is not None:
            t.observed(snap)
        t.note_states(list(records), lambda r: report.bucket(r) == "moving")
        self.clk.adv(dt)
        t.pass_end({"mode": "act", "open": len(records)}, None)


# ── R1-R5: red before the fix, because the information was on no disk ──────────────────────────


class RedControls(Base):
    def test_R1_gate_refusals_are_countable(self):
        """Three passes: record 1 refused by admission `pace`, record 2 by may_actuate `backoff`.
        events.jsonl keeps ONE admit-refused row (on change) and none for backoff; the readout
        counts 3 and 3. Mutant M1 (gate counts only on a reason change) reads 1 and 1."""
        r1, r2 = rec(1, sub="PLANNED"), rec(2, sub="PLANNED")
        r1.kind = r2.kind = "limited"
        ctx = M.Ctx(self.paths, None, self.home)
        ctx.records = {r1.sid: r1, r2.sid: r2}
        t = ctx.telem = self.tel()
        t.start(None, [])

        def may(paths, mode, rec_, which, *a):
            return (False, "backoff") if rec_.sid == r2.sid else (True, "")

        now = time.time()
        snap = T.Snapshot(wall=now, uptime_raw=0.0)
        with (
            mock.patch.object(act, "choose", return_value="A"),
            mock.patch.object(act, "may_actuate", side_effect=may),
            mock.patch.object(act, "hold_claim", return_value=(True, "")),
            mock.patch.object(M, "_admit", return_value=(False, "pace")),
            mock.patch.object(act, "running_count", return_value=0),
            mock.patch.object(M, "_admission_period"),
            mock.patch.object(ctx.clock, "wake_guard_ok", return_value=True),
        ):
            for _ in range(3):
                t.pass_begin(t.seq + 1)
                M._dispatch(ctx, snap, "act", now)
                t.note_states(
                    ctx.records.values(), lambda r: report.bucket(r) == "moving"
                )
                self.clk.adv(5)
                t.pass_end({"mode": "act"}, None)
        self.heartbeat(self.clk.w + 1, pass_seq=3)
        d = self.readout(self.clk.w + 1)
        self.assertEqual(d["gates"].get("admit:pace"), 3)
        self.assertEqual(d["gates"].get("may:backoff"), 3)
        with open(self.paths.events) as fh:
            evs = [json.loads(ln) for ln in fh]
        self.assertEqual(
            sum(1 for e in evs if e["ev"] == "admit-refused"), 1
        )  # equivalence guard

    def test_R2_time_in_state_is_on_disk(self):
        """Mutant M2 (dwell measured from timeline.detected) breaks the per-state split."""
        t = self.tel()
        t.start(None, [])
        r = rec(1)
        self.clk.w = 1000.0
        for at, sub in (
            (1000.0, "DETECTED"),
            (1010.0, "PLANNED"),
            (1310.0, "WAIT_SLOT"),
            (1910.0, "PLANNED"),
        ):
            self.clk.w = at
            r.substate = sub
            t.pass_begin(t.seq + 1)
            t.note_states([r], lambda x: True)
            t.pass_end({}, None)
        self.assertEqual(
            r.close["tel"]["dwell"],
            {
                "PRE-MOVE/DETECTED": 10.0,
                "PRE-MOVE/PLANNED": 300.0,
                "PRE-MOVE/WAIT_SLOT": 600.0,
            },
        )
        st = report.cohort_status(
            T.Cohort(cid="c1", acct="next4", scope="5h"), [r], 1950.0
        )
        self.assertEqual(st["members"][0]["in_state_s"], 40.0)
        moves = [x for x in self.rows("rec") if x["from"]]
        self.assertEqual(len(moves), 3)

    def test_R3_pass_splits_into_phases(self):
        """A 0.5 s ps inside observe, through the real run_bounded with the loop bound. Mutant M3
        (the hook called before subprocess.run) reads ~0 for ch.ps:all."""
        ctx = M.Ctx(self.paths, "observe", self.home)
        t = ctx.telem = telemetry.Telemetry(
            self.paths,
            env={},
            read_pri=lambda pid=None: 31,
            census=lambda: None,
            thermal=lambda: 1,
            pressure=lambda: 1,
            kitty_glob=os.path.join(self.tmp, "k-*"),
        )
        hb = C.Heartbeat(self.paths.heartbeat, 1, L, C.Clock(env={}))
        C.bind_steps(hb)
        C.bind_child_hook(t.child)
        self.addCleanup(C.bind_steps, None)
        self.addCleanup(C.bind_child_hook, None)

        def slow_run(*a, **k):
            time.sleep(0.5)
            return subprocess.CompletedProcess(a[0], 0, "", "")

        def fake_observe(paths, home, **kw):
            C.run_bounded(
                ["/bin/ps", "-axww", "-o", "pid="],
                capture_output=True,
                text=True,
                timeout=5,
            )
            return T.Snapshot(
                wall=time.time(),
                uptime_raw=0.0,
                degraded=["ps"],
                degraded_why={"ps": "test"},
            )

        with (
            mock.patch("lr_recon.observe.observe", side_effect=fake_observe),
            mock.patch.object(
                C, "_run_reaped", side_effect=slow_run
            ),  # W9: run_bounded's child
        ):
            M.run_pass(ctx)
        row = self.rows("pass")[-1]
        self.assertGreaterEqual(row["ph"]["observe"], 0.5)
        self.assertGreaterEqual(row["ch"]["ps:all"][2], 0.5)
        self.assertLess(abs(sum(row["ph"].values()) - row["dur"]), 0.05)
        self.assertEqual(hb.snapshot().phase, "idle")
        self.assertEqual(hb.snapshot().pass_seq, 1)

    def test_R4_first_attempt_stamped(self):
        t = self.tel()
        t.start(None, [])
        r = rec(1, det=1000.0, sub="PLANNED")
        self.clk.w = 1050.0
        self.one_pass(t, [r], dt=0)
        self.clk.w = 1100.0
        t.pass_begin(t.seq + 1)
        t.pre_spawn(r, "C")
        t.spawned(r, "C", 4242)
        t.pass_end({}, None)
        self.clk.w = 1300.0
        r.timeline.engaged = 1300.0
        r.terminal = T.Terminal(outcome="CLOSED", proof="engaged", at=1300.0)
        self.one_pass(t, [r], dt=0)
        cl = self.rows("close")[-1]
        self.assertEqual(
            (cl["det"], cl["first"], cl["first_by"], cl["eng"]),
            (1000.0, 1100.0, "C", 1300.0),
        )
        self.heartbeat(1301.0, pass_seq=t.seq)
        d = self.readout(1301.0)
        self.assertEqual(d["closed"]["detect_first"]["p50"], 100.0)

    def test_R5_rail_band_seen(self):
        t = self.tel(read_pri=lambda pid=None: 20 if pid == 41234 else 31)
        t.start(None, [])
        snap = T.Snapshot(
            wall=0.0,
            uptime_raw=0.0,
            procs={
                41234: T.ProcRow(
                    41234,
                    1,
                    "S",
                    L,
                    "/bin/bash /Users/x/.claude/scripts/limit-recover/lr-move-worker.sh --sid s",
                )
            },
        )
        self.one_pass(t, [], snap=snap)
        self.assertEqual(
            self.rows("pass")[-1]["band"]["low"], [["move-worker", 41234, 20]]
        )
        self.assertEqual(t.last_alert, "move-worker 41234 pri 20")
        self.heartbeat(self.clk.w, pass_seq=t.seq)
        d = self.readout(self.clk.w)
        self.assertEqual(d["verdict"], "WARN")
        self.assertTrue(any("move-worker 41234" in x for x in d["reasons"]))


# ── roles from the measured shapes (RC-6) ───────────────────────────────────────────────────────


class Roles(Base):
    def snap(self, rows):
        return T.Snapshot(wall=0.0, uptime_raw=0.0, procs={r.pid: r for r in rows})

    def roles(self, rows):
        s = self.snap(rows)
        kids = {}
        for r in rows:
            kids.setdefault(r.ppid, []).append(r.pid)
        return {r.pid: telemetry.role_of(r, s.procs, kids) for r in rows}

    def test_measured_shapes(self):
        prompt = "x" * 1647 + " see scripts/handoff-fire.sh"
        wrap = " ".join(act.wrap(rec(1), "ab12", ["/bin/bash", "/x/lr-handoff.sh"]))
        rows = [
            T.ProcRow(
                10,
                1,
                "S",
                L,
                "/Users/x/.local/bin/claude --settings=/x/handoff-fire.sh " + prompt,
            ),
            T.ProcRow(
                11,
                1,
                "S",
                L,
                "cc-close-attrib next claude --settings=x handoff-fire.sh",
            ),
            T.ProcRow(
                12,
                1,
                "S",
                L,
                "bash /opt/homebrew/libexec/bats-core/bats tests/cc-dispatch.bats",
            ),
            T.ProcRow(13, 1, "S", L, "jq -n 'cc-dispatch' --arg x lr-move-worker.sh"),
            T.ProcRow(14, 1, "S", L, "ugrep -n lr-recon-act --record-id"),
            T.ProcRow(
                15, 1, "S", L, "ugrep -rn lr-move-worker.sh scripts/limit-recover"
            ),
            T.ProcRow(20, 1, "S", L, "/bin/bash /x/lr-fire-resume.sh next /w e80b61f4"),
            T.ProcRow(21, 20, "S", L, "expect -c set timeout 240"),
            T.ProcRow(22, 21, "S", L, "cc-close-attrib next4 claude --resume e80b61f4"),
            T.ProcRow(30, 1, "S", L, "/bin/bash /x/lr-fire-resume.sh next /w 7aae55e1"),
            T.ProcRow(40, 1, "S", L, wrap),
            T.ProcRow(
                50,
                1,
                "S",
                L,
                "bash /opt/homebrew/libexec/bats-core/bats-exec-test tests/lr-move-worker.bats",
            ),
            T.ProcRow(
                51,
                50,
                "S",
                L,
                "/bin/bash /w/scripts/limit-recover/lr-move-worker.sh --sid s",
            ),
            T.ProcRow(
                60, 1, "S", L, "/bin/bash /Users/x/.claude/bin/cc-dispatch --fire"
            ),
            T.ProcRow(
                70,
                1,
                "S",
                L,
                "/bin/bash /Users/x/.claude/scripts/limit-recover/lr-reset-poller.sh",
            ),
        ]
        got = self.roles(rows)
        self.assertEqual(
            got,
            {
                10: None,
                11: None,
                12: None,
                13: None,
                14: None,
                15: None,
                20: "session-parent",
                21: None,
                22: None,
                30: "resume",
                40: "actuator",
                50: None,
                51: None,
                60: "dispatch",
                70: "poller",
            },
        )

    def test_dispatch_at_base_11_is_adjacent_never_low(self):
        rows = [T.ProcRow(60, 1, "S", L, "/bin/bash /x/cc-dispatch --fire")]
        t = self.tel(read_pri=lambda pid=None: 11 if pid == 60 else 31)
        t.start(None, [])
        self.one_pass(t, [], snap=self.snap(rows))
        b = self.rows("pass")[-1]["band"]
        self.assertEqual(b["low"], [])
        self.assertEqual(b["roles"]["dispatch"], [1, 11])


# ── G instrument de-biased (RC-1..RC-4, RC-12) ───────────────────────────────────────────────────


class Instrument(Base):
    def test_T4_restart_pre_b6_and_bracket(self):
        """5 pre-B6 terminal records: 0 rows and no write. Mutant M6 (the skip removed) writes 5.
        A record's tel round-trips through a save and dwell continues; the wall moves INSIDE one
        pass, so a rec row is bracketed [p0, t] with p0 < t (RC-12)."""
        old = [rec(i) for i in range(5)]
        for r in old:
            r.terminal = T.Terminal(outcome="CLOSED", at=900.0)
        t = self.tel()
        t.start(None, old)
        saved = dict(store._SAVED)
        self.one_pass(t, old)
        self.assertEqual(self.rows("rec") + self.rows("close"), [])
        self.assertTrue(all("tel" not in r.close for r in old))
        self.assertEqual(store._SAVED, saved)
        live = rec(9, sub="PLANNED")
        self.one_pass(t, [live], dt=10)
        store.save_record(self.paths, live, self.clk.w)
        back = store.load_record(self.paths, live.sid)
        t2 = self.tel()
        t2.start(None, [back])
        t2.pass_begin(1)
        p0 = self.clk.w
        self.clk.adv(30)  # the pass `now` would be p0; the stamp is wall-at-write
        back.substate = "WAIT_SLOT"
        t2.note_states([back], lambda x: True)
        t2.pass_end({}, None)
        row = [x for x in self.rows("rec") if x["from"]][-1]
        self.assertEqual(row["p0"], round(p0, 1))
        self.assertGreater(row["t"], row["p0"])
        self.assertEqual(row["dwell"], 40.0)
        self.assertNotIn("pre", back.close["tel"])

    def test_born_terminal_close_row_and_censored_counts(self):
        t = self.tel()
        t.start(None, [])
        born = rec(1)
        born.terminal = T.Terminal(outcome="NOT_NEEDED", at=1000.0)
        waiting = rec(2, det=self.clk.w - 100, sub="PLANNED")
        self.one_pass(t, [born, waiting])
        cl = self.rows("close")
        self.assertEqual(len(cl), 1)
        self.assertTrue(cl[0]["born_terminal"])
        self.assertIsNone(cl[0]["first"])
        store.save_record(self.paths, waiting, self.clk.w)
        self.heartbeat(self.clk.w, pass_seq=t.seq)
        d = self.readout(self.clk.w)
        df = d["closed"]["detect_first"]
        self.assertEqual(df["n_censored"], 1)
        self.assertEqual(df["n_closed_unattempted"], {"NOT_NEEDED": 1})
        self.assertEqual(d["closed"]["born_terminal"], 1)

    def test_held_pre_nets_hard_hold_time(self):
        t = self.tel()
        t.start(None, [])
        r = rec(1, det=1000.0, sub="WAIT_RESET")
        self.clk.w = 1000.0
        self.one_pass(t, [r], dt=0)
        self.clk.w = 1500.0
        r.substate = "PLANNED"
        self.one_pass(t, [r], dt=0)
        self.clk.w = 1600.0
        t.pass_begin(t.seq + 1)
        t.pre_spawn(r, "A")
        t.pass_end({}, None)
        self.assertEqual(r.close["tel"]["held_pre"], 500.0)
        r.terminal = T.Terminal(outcome="CLOSED", at=1700.0)
        self.clk.w = 1700.0
        self.one_pass(t, [r], dt=0)
        self.heartbeat(1700.0, pass_seq=t.seq)
        d = self.readout(1700.0)
        self.assertEqual(d["closed"]["detect_first"]["p50"], 600.0)
        self.assertEqual(d["closed"]["detect_first_net"]["p50"], 100.0)

    def test_act_exit_is_exit_based_and_counts_noops(self):
        t = self.tel()
        t.start(None, [])
        r = rec(1, sub="PLANNED")
        log = os.path.join(self.tmp, "a.log")
        open(log, "w").close()
        os.utime(log, (1004.0, 1004.0))
        self.clk.w = 1000.0
        t.pass_begin(1)
        t.pre_spawn(r, "A")
        t.spawned(r, "A", 777)
        self.clk.w = 1030.0
        t.act_exit(
            r,
            T.ProcRole(role="actuator", pid=777, lstart=L, argv_hash="A"),
            3,
            "refused: busy",
            log,
        )
        t.pass_end({}, None)
        a = self.rows("act")[-1]
        self.assertEqual(
            (a["wall"], a["end"], a["seen_lag"], a["detail"]),
            (4.0, "log", 26.0, "refused: busy"),
        )
        self.heartbeat(1030.0, pass_seq=1)
        self.assertEqual(self.readout(1030.0)["closed"]["actuator_wall"]["noop"], 1)
        self.assertEqual(r.close["tel"]["lx"], 1030.0)

    def test_spawn_row_carries_gap_since_last_exit(self):
        t = self.tel()
        t.start(None, [])
        r = rec(1, sub="PLANNED")
        r.close["tel"] = {"st": "PRE-MOVE/PLANNED", "at": 900.0, "lx": 1000.0}
        self.clk.w = 1240.0
        t.pass_begin(1)
        t.pre_spawn(r, "R")
        t.spawned(r, "R", 5)
        t.pass_end({}, None)
        self.assertEqual(self.rows("spawn")[-1]["gap"], 240.0)

    def test_T5_flaps_coalesce_and_dwell_is_exact(self):
        t = self.tel()
        t.start(None, [])
        r = rec(1, sub="PLANNED")
        self.one_pass(t, [r], dt=0)
        for i in range(50):
            self.clk.w += 1.0
            r.substate = "WAIT_DATA" if i % 2 == 0 else "PLANNED"
            self.one_pass(t, [r], dt=0)
        moves = [x for x in self.rows("rec") if x["from"]]
        self.assertLessEqual(len(moves), 2)
        suppressed = 50 - len(moves)
        self.assertEqual(
            sum(x.get("flaps", 0) for x in moves) + t.flaps[r.sid]["n"], suppressed
        )
        self.assertEqual(round(sum(r.close["tel"]["dwell"].values()), 1), 50.0)

    def test_T6_a_day_of_waiting_is_quiet(self):
        """24 h of 3 s passes over a WAIT_RESET record, driven by method (not 28,800 run_pass):
        ≤ 288 quiet rows + box rows, and no full row after the first. Mutant M8 (quiet rule
        removed) writes 28,800 rows."""
        t = self.tel()
        t.start(None, [])
        r = rec(1, sub="WAIT_RESET")
        for _ in range(28800):
            self.one_pass(t, [r], dt=3.0)
            t.box()
        full = self.rows("pass")
        self.assertEqual([x["seq"] for x in full], [1])
        self.assertLessEqual(len(self.rows("quiet")), 289)
        self.assertLessEqual(len(self.rows("box")), 289)

    def test_T7_unknown_band_is_never_ok(self):
        """Mutant M4 (None read as 31) hides the unknown."""
        rows = {5: T.ProcRow(5, 1, "S", L, "/bin/bash /x/lr-reset-poller.sh")}
        t = self.tel(read_pri=lambda pid=None: None if pid == 5 else 31)
        t.start(None, [])
        self.one_pass(t, [], snap=T.Snapshot(wall=0.0, uptime_raw=0.0, procs=rows))
        self.assertEqual(self.rows("pass")[-1]["band"]["unk"], 1)
        self.heartbeat(self.clk.w, pass_seq=t.seq)
        d = self.readout(self.clk.w)
        self.assertNotEqual(d["verdict"], "ok")
        self.assertIn("band unknown for 1 rail processes", d["reasons"])

    def test_ps_degraded_band_is_named(self):
        t = self.tel()
        t.start(None, [])
        self.one_pass(t, [], snap=T.Snapshot(wall=0.0, uptime_raw=0.0, degraded=["ps"]))
        self.heartbeat(self.clk.w, pass_seq=t.seq)
        lines = telemetry.render(self.readout(self.clk.w))
        self.assertTrue(any("ps degraded" in x for x in lines))


# ── box, census, kitty ──────────────────────────────────────────────────────────────────────────


class Box(Base):
    def test_T8_throttle_keys_on_census_cpu(self):
        def costly():
            self.clk.cpu += 2.5
            return {"run": {}, "thr": 1, "procs": 1, "of": 1}

        t = self.tel(census=costly)
        t.last_active = 1
        t.box()
        self.assertEqual(t.next_box - self.clk.m, 150.0)
        self.assertEqual(len(self.rows("box")), 1)
        off = self.tel(env={"LR_RECON_TELEMETRY_BOX": "off"})
        off.box()
        self.assertEqual(len(self.rows("box")), 1)

    def test_census_deadline_returns_partial(self):
        ticks = iter([0.0, 0.1, 5.0, 6.0, 7.0, 8.0])
        got = band.runnable_by_base(
            pids=[os.getpid()] * 4, deadline_s=2.0, mono=lambda: next(ticks)
        )
        self.assertTrue(got["partial"])
        self.assertEqual(got["procs"], 1)

    def test_own_thread_census_reads_threads(self):
        """Handles pinned to c_uint64: a plain int handle read 0 threads (measured)."""
        self.assertGreater(len(band._threads(os.getpid())), 0)
        self.assertGreater(band.runnable_by_base(pids=[os.getpid()])["thr"], 0)
        self.assertIsNotNone(band.main_thread(os.getpid()))
        t = self.tel(census=lambda: band.runnable_by_base(pids=[os.getpid()]))
        t.box()
        row = self.rows("box")[-1]
        self.assertGreater(row["thr"], 0)
        self.assertFalse(row["partial"])

    def test_stuck_census_is_not_stacked_and_reads_partial(self):
        gate = threading.Event()
        self.addCleanup(gate.set)
        t = self.tel(census=lambda: gate.wait(10) and {})
        with mock.patch.object(telemetry, "CENSUS_JOIN_S", 0.05):
            t.box()
            self.assertTrue(self.rows("box")[-1]["stalled"])
            self.clk.adv(1000)
            t.box()
        self.assertEqual(len(self.rows("box")), 1)

    def test_kitty_from_socket_names_and_unknown(self):
        for n in ("kitty-4242", "kitty-999", "kitty-x"):
            open(os.path.join(self.tmp, n), "w").close()
        t = self.tel(read_pri=lambda pid=None: None if pid == 999 else 31)
        t.box()
        self.assertEqual(self.rows("box")[-1]["kitty"], {"4242": [31, 47, 47]})
        empty = self.tel(kitty_glob=os.path.join(self.tmp, "none-*"))
        empty.next_box = 0
        empty.box()
        self.assertIsNone(self.rows("box")[-1]["kitty"])
        self.heartbeat(self.clk.w)
        self.assertIn("kitty band unknown", self.readout(self.clk.w)["reasons"])

    def test_thermal_and_memory_per_pass(self):
        t = self.tel(thermal=lambda: 2, pressure=lambda: 4)
        t.start(None, [])
        self.one_pass(t, [])
        row = self.rows("pass")[-1]
        self.assertEqual((row["therm"], row["mem"]), (2, 4))
        self.assertIsNotNone(band.pressure_level())


# ── guards, bounds, equivalence ─────────────────────────────────────────────────────────────────


class Guards(Base):
    def test_T9_equivalence_with_telemetry_on_and_off(self):
        from lr_recon.tests.test_main import _snap

        def arm(root, on):
            paths = T.Paths.from_env(root=root)
            ctx = M.Ctx(paths, "observe", self.home)
            if on:
                ctx.telem = telemetry.Telemetry(
                    paths,
                    env={},
                    wall=lambda: 1792314000.0,
                    read_pri=lambda pid=None: 31,
                    census=lambda: None,
                    thermal=lambda: 1,
                    pressure=lambda: 1,
                    kitty_glob=os.path.join(self.tmp, "k-*"),
                )
                ctx.telem.start(None, [])
            placed = {sid(1): T.Placement(acct="next4", weight=1)}
            outs = []
            for i in range(3):
                now = 1792314000.0 + 10 * i
                with (
                    mock.patch("time.time", return_value=now),
                    mock.patch(
                        "lr_recon.observe.observe", return_value=_snap(now, self.tmp)
                    ),
                    mock.patch.object(plan, "place", return_value=(placed, 0)),
                    mock.patch.object(plan, "assign_many", return_value=0),
                    mock.patch.object(M.act, "spawn"),
                    mock.patch(
                        "lr_recon.admit.Admission.probe", return_value=(True, "admit")
                    ),
                    mock.patch(
                        "lr_recon.admit.Admission.mint_token", return_value=None
                    ),
                ):
                    outs.append(M.run_pass(ctx))
            recs = {}
            for n in sorted(os.listdir(paths.sessions)):
                with open(os.path.join(paths.sessions, n)) as fh:
                    d = json.load(fh)
                d["close"].pop("tel", None)
                recs[n] = d
            with open(paths.events) as fh:
                evs = fh.read()
            with open(paths.p("readout.line")) as fh:
                line = fh.read()
            return outs, recs, evs, line, paths

        a = arm(os.path.join(self.tmp, "a", "recon"), False)
        b = arm(os.path.join(self.tmp, "b", "recon"), True)
        self.assertEqual(a[0], b[0])
        self.assertEqual(a[1], b[1])
        self.assertEqual(a[2], b[2])
        self.assertEqual(a[3], b[3])
        self.assertFalse(
            os.path.exists(a[4].p(telemetry.FILE))
        )  # T3: no telem, no file
        self.assertTrue(os.path.exists(b[4].p(telemetry.FILE)))

    def test_T9_faults_turn_it_off_then_rearm(self):
        """A census that raises: the loop goes on; 20 faults ⇒ off + one telemetry-off event;
        after REARM_S it re-arms (RC-10). Mutant M5 (_guard removed) raises into the loop."""

        def boom():
            raise RuntimeError("libproc gone")

        t = self.tel(census=boom)
        for _ in range(25):
            t.next_box = 0
            t.box()  # never raises
        self.assertTrue(t.off)
        with open(self.paths.events) as fh:
            evs = [json.loads(ln)["ev"] for ln in fh]
        self.assertEqual(evs.count("telemetry-off"), 1)
        self.clk.adv(telemetry.REARM_S + 1)
        t.pass_begin(99)
        self.assertFalse(t.off)
        with open(self.paths.events) as fh:
            self.assertIn("telemetry-on", fh.read())

    def test_no_pass_no_count(self):
        """RC-10: with cur None the pass methods return without counting a fault."""
        t = self.tel()
        t.phase("x")
        t.gate("may", "backoff")
        t.note_states([rec(1)], lambda r: True)
        t.pass_end({}, None)
        self.assertEqual(t.faults, 0)

    def test_T10_row_bounds_and_write_errors(self):
        t = self.tel()
        t.start(None, [])
        t.pass_begin(2)
        for i in range(200):
            t.gate("admit", "reason-%03d-%s" % (i, "x" * 20))
        self.clk.adv(40)
        t.pass_end({}, None)
        with open(self.paths.p(telemetry.FILE), "rb") as fh:
            last = fh.read().splitlines()[-1]
        self.assertLessEqual(len(last) + 1, telemetry.LINE_MAX)
        self.assertEqual(len(json.loads(last)["gates"]), 16)
        with mock.patch.object(store, "append_bounded", side_effect=OSError("ENOSPC")):
            t.pass_begin(3)
            self.clk.adv(40)
            t.pass_end({}, None)
        self.assertEqual(t.werr, 1)
        t.pass_begin(4)
        self.clk.adv(40)
        t.pass_end({}, None)
        self.assertEqual(self.rows("pass")[-1]["werr"], 1)

    def test_T11_no_decision_reads_telemetry(self):
        names = sorted(n for n in os.listdir(PKG) if n.endswith(".py"))
        decision = [
            n for n in names if n not in ("telemetry.py", "report.py", "__main__.py")
        ]
        self.assertGreater(len(decision), 20)
        pat = re.compile(r'telemetry|"tel"|last_alert')
        for n in decision:
            with open(os.path.join(PKG, n), encoding="utf-8") as fh:
                self.assertIsNone(pat.search(fh.read()), n)
        import inspect

        paging = [f for n, f in vars(report.Reporter).items() if callable(f)]
        paging += [
            f
            for n, f in vars(report).items()
            if callable(f)
            and "page" in n
            and getattr(f, "__module__", "") == report.__name__
        ]
        for f in paging:
            self.assertIsNone(pat.search(inspect.getsource(f)), f.__name__)
        with open(os.path.join(PKG, "__main__.py"), encoding="utf-8") as fh:
            src = fh.read()
        self.assertNotIn('close["tel"]', src)
        self.assertNotIn('close.get("tel")', src)

    def test_first_is_derived_from_the_move_actuators(self):
        self.assertEqual(telemetry.FIRST, M.FIRST_TURN)

    def test_T12_watchdog_and_fence_read_the_same_heartbeat(self):
        """The watchdog's own hb_num sed and the fence's awk, run over a heartbeat with the new
        keys, read the same values as without them. Mutant M7 (a nested {"pid":…}) is caught."""
        with open(os.path.join(LR_DIR, "lr-recon-watchdog.sh"), encoding="utf-8") as fh:
            wd = fh.read()
        with open(os.path.join(LR_DIR, "lr-recon-fence.sh"), encoding="utf-8") as fh:
            fe = fh.read()
        hb_num = re.search(r"^hb_num\(\) \{.*?^\}", wd, re.M | re.S).group(0)
        lst = re.search(r'^HB_LSTART="\$\((.*)\)"$', wd, re.M).group(1)
        pw = re.search(r"^_lr_recon_progress_wall\(\) \{.*?^\}", fe, re.M | re.S).group(
            0
        )
        keys = ("pid", "progress", "wall", "progress_wall", "step_due", "child_bound_s")

        def read(text):
            f = os.path.join(self.tmp, "hb")
            with open(f, "w") as fh:
                fh.write(text)
            script = (
                "%s\n%s\nHB=%s\nfor k in %s; do printf '%%s=%%s\\n' $k \"$(hb_num $k)\"; done\n"
                "printf 'lstart=%%s\\n' \"$(%s)\"\nprintf 'pw=%%s\\n' \"$(_lr_recon_progress_wall %s)\"\n"
                % (hb_num, pw, f, " ".join(keys), lst, f)
            )
            out = subprocess.run(
                ["/bin/bash", "-c", script], capture_output=True, text=True, timeout=30
            ).stdout
            return dict(ln.split("=", 1) for ln in out.splitlines())

        clk = C.Clock(wall=lambda: 1792314000.5, uptime=lambda: 5.0, env={})
        hb = C.Heartbeat(os.path.join(self.tmp, "x"), 4321, L, clk)
        hb.declare_child(40.0)
        hb.set_phase("begin", 7)
        hb.set_phase("dispatch", 7)
        new = hb.render()
        d = json.loads(new)
        self.assertEqual((d["phase"], d["pass_seq"]), ("dispatch", 7))
        old = dict(d)
        for k in ("phase", "phase_at", "pass_seq", "pass_at"):
            old.pop(k)
        base = read(json.dumps(old, separators=(",", ":")) + "\n")
        self.assertEqual(read(new), base)
        self.assertEqual(base["pid"], "4321")
        self.assertEqual(
            read(new)["pid"], "4321"
        )  # the real render, whatever keys it gained
        d["x"] = {"pid": 9}
        self.assertNotEqual(
            read(json.dumps(d, separators=(",", ":")) + "\n")["pid"], base["pid"]
        )

    def test_T13_unimportable_telemetry_runs_without_it(self):
        """A telemetry.py that raises SyntaxError at import: __main__ still imports, the daemon's
        setup writes one telemetry-off event and a pass runs with ctx.telem None."""
        pkg = os.path.join(self.tmp, "pkg")
        shutil.copytree(
            PKG,
            os.path.join(pkg, "lr_recon"),
            ignore=shutil.ignore_patterns("tests", "__pycache__"),
        )
        shutil.copy(
            os.path.join(LR_DIR, "lr_predicate.py"), pkg
        )  # transcript.py's sibling
        with open(os.path.join(pkg, "lr_recon", "telemetry.py"), "w") as fh:
            fh.write("def broken(:\n")
        prog = (
            "import os\nfrom unittest import mock\nfrom lr_recon import __main__ as M\nfrom lr_recon import types as T\n"
            "assert M.telemetry is None\npaths = T.Paths.from_env()\nctx = M.Ctx(paths, 'observe', os.environ['HOME'])\n"
            "assert M._make_telemetry(ctx, '', {}) is None\n"
            "snap = T.Snapshot(wall=0.0, uptime_raw=0.0, degraded=['ps'], degraded_why={'ps': 't'})\n"
            "with mock.patch('lr_recon.observe.observe', return_value=snap):\n    s = M.run_pass(ctx)\n"
            "print('abstain' in s, ctx.telem)\n"
        )
        env = dict(
            os.environ, PYTHONPATH=pkg, LR_KITTEN_BIN="/usr/bin/false", TMPDIR=self.tmp
        )
        cp = subprocess.run(
            [sys.executable, "-c", prog],
            capture_output=True,
            text=True,
            env=env,
            timeout=120,
            cwd=self.tmp,  # -c puts the cwd first on sys.path: never the real package
        )
        self.assertEqual(cp.returncode, 0, cp.stderr)
        self.assertEqual(cp.stdout.strip(), "True None")
        with open(self.paths.events) as fh:
            evs = [json.loads(ln) for ln in fh]
        off = [e for e in evs if e["ev"] == "telemetry-off"]
        self.assertEqual(len(off), 1)
        self.assertIn("SyntaxError", off[0]["detail"])

    def test_unguarded_constructor_would_kill_the_start(self):
        ctx = M.Ctx(self.paths, None, self.home)
        with mock.patch.object(
            telemetry, "Telemetry", side_effect=AttributeError("no _max_bytes_env")
        ):
            self.assertIsNone(M._make_telemetry(ctx, "", {}))
        with open(self.paths.events) as fh:
            self.assertIn("constructor:", fh.read())
        with mock.patch.dict(os.environ, {"LR_RECON_TELEMETRY": "off"}):
            self.assertIsNone(M._make_telemetry(ctx, "", {}))

    def test_run_bounded_hook_never_breaks_the_child(self):
        hb = C.Heartbeat(self.paths.heartbeat, 1, L, C.Clock(env={}))
        C.bind_steps(hb)
        self.addCleanup(C.bind_steps, None)
        C.bind_child_hook(lambda *a: 1 / 0)
        self.addCleanup(C.bind_child_hook, None)
        cp = C.run_bounded(["/usr/bin/true"], timeout=10)
        self.assertEqual(cp.returncode, 0)
        self.assertEqual(hb.progress, 1)

    def test_child_labels_split_cost_classes(self):
        cases = {
            ("/bin/ps", "-axww", "-o", "pid="): "ps:all",
            ("ps", "-o", "lstart=", "-p", "5"): "ps:pid",
            ("bash", "-c", "x; cc_capacity_probe 3"): "probe",
            ("bash", "-c", "cc_capacity_token_mint a"): "mint",
            (
                "/bin/bash",
                "/x/lib/lr-composer-snapshot.sh",
                "--sock",
                "s",
            ): "lr-composer-snapshot.sh",
            ("/x/bin/claude-accounts", "--place", "general"): "claude-accounts --place",
            ("/x/kitten", "@", "ls"): "kitten",
            ("/usr/sbin/sysctl", "-n", "kern.waketime"): "sysctl",
        }
        for argv, want in cases.items():
            self.assertEqual(C.child_label(list(argv)), want)

    def test_first_rides_spawns_own_save(self):
        """Item 10: ``first`` is on the record BEFORE act.spawn, whose own saves then carry it, so
        a restart before the end-of-pass save cannot lose it."""
        r = rec(1, sub="PLANNED")
        ctx = M.Ctx(self.paths, None, self.home)
        ctx.records = {r.sid: r}
        ctx.telem = t = self.tel()
        t.start(None, [])
        seen = {}

        def spawn(paths, rec_, which, argv, env, now):
            seen.update(rec_.close.get("tel") or {})
            return 4242

        now = time.time()
        with (
            mock.patch.object(act, "choose", return_value="C"),
            mock.patch.object(act, "may_actuate", return_value=(True, "")),
            mock.patch.object(act, "hold_claim", return_value=(True, "")),
            mock.patch.object(M, "_admit", return_value=(True, "admit")),
            mock.patch.object(act, "running_count", return_value=0),
            mock.patch.object(M, "_admission_period"),
            mock.patch.object(ctx.clock, "wake_guard_ok", return_value=True),
            mock.patch.object(M, "_command", return_value=["/usr/bin/true"]),
            mock.patch.object(act, "actuator_env", return_value={}),
            mock.patch.object(act, "spawn", side_effect=spawn),
        ):
            t.pass_begin(1)
            self.assertEqual(
                M._dispatch(ctx, T.Snapshot(wall=now, uptime_raw=0.0), "act", now), 1
            )
            t.pass_end({}, None)
        self.assertEqual(seen.get("first_by"), "C")
        self.assertEqual(self.rows("pass")[-1]["admits"], {"admit": 1})
        self.assertEqual(self.rows("spawn")[-1]["a"], "C")

    def test_in_state_is_right_on_the_pass_of_the_change(self):
        """Item 8: note_states runs before _report, so the cohort file's in_state_s reads THIS
        pass's stamp, not the previous state's."""
        from lr_recon.tests.test_main import _snap

        now = 1792314000.0
        self.clk.w = now
        ctx = M.Ctx(self.paths, "observe", self.home)
        ctx.telem = self.tel()
        ctx.telem.start(None, [])
        with (
            mock.patch("time.time", return_value=now),
            mock.patch("lr_recon.observe.observe", return_value=_snap(now, self.tmp)),
            mock.patch.object(plan, "place", return_value=({}, 0)),
            mock.patch("lr_recon.admit.Admission.probe", return_value=(True, "admit")),
            mock.patch("lr_recon.admit.Admission.mint_token", return_value=None),
        ):
            M.run_pass(ctx)
        members = []
        for n in os.listdir(self.paths.cohorts):
            with open(os.path.join(self.paths.cohorts, n)) as fh:
                members += (json.load(fh).get("status") or {}).get("members") or []
        self.assertEqual([m["in_state_s"] for m in members], [0.0])

    def test_T16_readout_line_pointer(self):
        ctx = M.Ctx(self.paths, None, self.home)
        ctx.reporter = mock.MagicMock()
        with mock.patch.object(report, "readout_line", return_value="lr-recon: 1 open"):
            M._report(ctx, "observe", 1000.0)
            with open(self.paths.p("readout.line")) as fh:
                self.assertEqual(fh.read(), "lr-recon: 1 open")
            ctx.telem = mock.MagicMock(last_alert="")
            M._report(ctx, "observe", 1000.0)
            with open(self.paths.p("readout.line")) as fh:
                self.assertEqual(fh.read(), "lr-recon: 1 open")
            ctx.telem.last_alert = "move-worker 41234 pri 20"
            M._report(ctx, "observe", 1000.0)
            with open(self.paths.p("readout.line")) as fh:
                self.assertEqual(
                    fh.read(),
                    "lr-recon: 1 open · ⚠ rail: move-worker 41234 pri 20 → cc-lr status --rail",
                )

    def test_off_file_pauses(self):
        t = self.tel()
        open(self.paths.p(telemetry.OFF_FILE), "w").close()
        t.check_switch()
        t.pass_begin(1)
        t.pass_end({}, None)
        self.assertEqual(self.rows(), [])


# ── the readout follows the watchdog (RC-5, RC-11, T15) ─────────────────────────────────────────


class Readout(Base):
    def seed(self, t, n=2):
        t.start(None, [])
        for _ in range(n):
            self.one_pass(t, [], dt=2.0)

    def test_T15_empty_root_is_no_data_rc1(self):
        buf = io.StringIO()
        with redirect_stdout(buf):
            rc = telemetry.main(["readout", "--root", os.path.join(self.tmp, "empty")])
        self.assertEqual(rc, 1)
        self.assertTrue(buf.getvalue().startswith("reconciler: NO DATA"))

    def test_daemon_down_is_no_data(self):
        self.seed(self.tel())
        self.heartbeat(self.clk.w - 61)
        d = self.readout(self.clk.w)
        self.assertEqual(d["verdict"], "NO DATA")
        self.assertIn("daemon down", d["reasons"][0])

    def test_telemetry_stopped_needs_pass_seq_to_advance(self):
        t = self.tel()
        self.seed(t)
        now = self.clk.w + 2000
        self.heartbeat(now, pass_seq=t.seq + 1, phase="dispatch", pass_at=now - 1900)
        self.assertNotEqual(self.readout(now, since_s=7200)["verdict"], "NO DATA")
        self.heartbeat(now, pass_seq=t.seq + 3)
        open(self.paths.p(telemetry.OFF_FILE), "w").close()
        d = self.readout(now, since_s=7200)
        self.assertEqual(d["verdict"], "NO DATA")
        self.assertIn("telemetry stopped", d["reasons"][0])
        self.assertIn("telemetry.off", d["reasons"][0])

    def test_14_minute_pass_in_progress_is_warn_not_no_data(self):
        t = self.tel()
        self.seed(t)
        now = self.clk.w + 840
        self.heartbeat(
            now,
            pass_seq=t.seq + 1,
            phase="dispatch",
            phase_at=now - 300,
            pass_at=now - 840,
            child_bound_s=120.0,
            step_due=now + 60,
        )
        d = self.readout(now)
        self.assertEqual(d["verdict"], "WARN")
        self.assertTrue(
            d["reasons"][0].startswith(
                "pass %d running 14m00s, phase dispatch" % (t.seq + 1)
            ),
            d["reasons"],
        )

    def test_flap_proof_stuck_warn(self):
        """A PLANNED↔WAIT_DATA loop keeps resetting time-in-state; the stuck rule keys on
        detection and the last exit, so the loop still trips it (RC-3)."""
        t = self.tel()
        t.start(None, [])
        r = rec(1, det=self.clk.w, sub="PLANNED")
        for i in range(80):
            r.substate = "WAIT_DATA" if i % 2 else "PLANNED"
            self.one_pass(t, [r], dt=10.0)
        store.save_record(self.paths, r, self.clk.w)
        self.heartbeat(self.clk.w, pass_seq=t.seq)
        d = self.readout(self.clk.w)
        self.assertLess(d["open"][0]["in_state_s"], 60)
        self.assertTrue(any("not attempted" in x for x in d["reasons"]), d["reasons"])
        r.close["tel"]["ls"], r.close["tel"]["lx"] = self.clk.w - 700, self.clk.w - 650
        store.save_record(self.paths, r, self.clk.w)
        d = self.readout(self.clk.w)
        self.assertTrue(any("no retry" in x for x in d["reasons"]), d["reasons"])
        r.substate = "WAIT_RESET"  # a hard hold: never stuck
        store.save_record(self.paths, r, self.clk.w)
        self.assertFalse(
            any(sid(1)[:8] in x for x in self.readout(self.clk.w)["reasons"])
        )

    def test_other_lane_and_pre_b6_are_named_not_warned(self):
        parked = rec(1, det=self.clk.w - 1600000, sub="PARKED-REBOOT")
        old = rec(2, det=self.clk.w - 100000, sub="PLANNED")
        t = self.tel()
        t.start(None, [parked, old])
        self.one_pass(t, [parked, old])
        for r in (parked, old):
            store.save_record(self.paths, r, self.clk.w)
        self.heartbeat(self.clk.w, pass_seq=t.seq)
        d = self.readout(self.clk.w)
        self.assertEqual(d["verdict"], "ok", d["reasons"])
        self.assertEqual(d["other_lane"][0]["owner"], "boot-resume")
        self.assertEqual(d["open"][0]["first"], "unknown")
        lines = telemetry.render(d)
        self.assertTrue(lines[0].startswith("reconciler: ok"))
        self.assertFalse(any(ln.startswith("rail: ok") for ln in lines))
        self.assertIn("not covered: move lane, boot-resume", lines[1])

    def test_child_timeouts_alone_are_not_warn(self):
        t = self.tel()
        t.start(None, [])
        t.pass_begin(1)
        t.child("claude-accounts --place", 120.0, True)
        t.pass_end({}, None)
        self.heartbeat(self.clk.w, pass_seq=1)
        d = self.readout(self.clk.w)
        self.assertEqual(d["verdict"], "ok", d["reasons"])
        self.assertEqual(d["children"]["claude-accounts --place"][3], 1)

    def test_counters_from_events(self):
        self.seed(self.tel())
        for ev, detail in (
            ("exit", "R: HELD:load after confirm"),
            ("deadline-held", "pacer:next4 (x)"),
            ("deadline-held", "pacer:next4 (y)"),
        ):
            store.append_event(self.paths, T.Event(t=self.clk.w, ev=ev, detail=detail))
        self.heartbeat(self.clk.w)
        c = self.readout(self.clk.w)["counters"]
        self.assertEqual((c["held_load"], c["deadline_held"]), (1, {"pacer:next4": 2}))

    def test_json_keys_are_stable(self):
        self.seed(self.tel())
        self.heartbeat(self.clk.w)
        d = self.readout(self.clk.w)
        for k in (
            "verdict",
            "reasons",
            "window_s",
            "daemon",
            "band",
            "box",
            "passes",
            "phases",
            "children",
            "gates",
            "admits",
            "spawns",
            "open",
            "closed",
            "telemetry",
            "counters",
            "other_lane",
            "not_covered",
            "scope",
        ):
            self.assertIn(k, d)


if __name__ == "__main__":
    unittest.main()
