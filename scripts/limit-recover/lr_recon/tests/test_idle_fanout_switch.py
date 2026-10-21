"""W13 D2a (D2-warning-band-shedding.md §6.6, reviews D16 and E9): the at-the-wall idle fan-out switch.

recon/idle-fanout.on, read every pass (absent = off), replaces the env-only LR_IDLE_FANOUT for the
daemon; LR_IDLE_FANOUT=off still wins. Idle records take 0 boot slots while an overdue limited
record waits and at most 1 while any limited record is open; an idle composer verdict is kept 60 s
and at most 4 idle reads start per pass. Every test runs under a /tmp HOME, LR_STATE_DIR and
LR_RECON_ROOT, and never shells out to kitty (observe.composer_state is counted, not run)."""

import os
import shutil
import tempfile
import time
import unittest
from unittest import mock

from lr_recon import __main__ as M
from lr_recon import types as T

L = "Tue Sep 29 11:19:17 2026"


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="lr-idle-fanout-")
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.home = os.path.join(self.tmp, "home")
        os.makedirs(self.home)
        lr = os.path.join(self.tmp, "lr")
        patch = mock.patch.dict(
            os.environ,
            {
                "HOME": self.home,
                "LR_STATE_DIR": os.path.join(self.tmp, "lr"),
                "LR_RECON_ROOT": os.path.join(self.tmp, "lr", "recon"),
                "TMPDIR": self.tmp,
            },
        )
        patch.start()
        self.addCleanup(patch.stop)
        os.environ.pop("LR_IDLE_FANOUT", None)
        self.paths = T.Paths.from_env(root=os.path.join(lr, "recon"))
        M.store.ensure_dirs(self.paths)
        os.makedirs(self.paths.requests, exist_ok=True)
        self.now = time.time()
        self.reads = 0

    def switch(self, on):
        if on:
            open(self.paths.idle_fanout_on, "w").close()
        elif os.path.exists(self.paths.idle_fanout_on):
            os.unlink(self.paths.idle_fanout_on)

    def markers(self):
        for p in (
            self.paths.recon_on,
            self.paths.autorecover_on,
            self.paths.recon_autorecover_on,
        ):
            open(p, "w").close()

    def facts(self):
        f = T.Fact(
            acct="next3",
            scope="7d",
            resets_at=self.now + 7200,
            observed_at=self.now - 60,
        )
        return {"next3.7d": f}

    def snap(self, n=1):
        """n at-rest, unfocused, not-limited sessions on next3 (7d fact up), each in its own pane."""
        sessions, panes = {}, {}
        for i in range(n):
            sid = "1d1e0000-0000-0000-0000-%012d" % i
            pane = T.PaneObs(
                kitty_pid=5,
                window_id=10 + i,
                sock="unix:/tmp/kitty-5",
                root_pid=20 + i,
                root_lstart=L,
                root_shape="shell",
                state="claude",
            )
            panes["5:%d" % (10 + i)] = pane
            h = T.HolderObs(
                pid=100 + i, lstart=L, cfg="/c3", src="registry", pane=(5, 10 + i)
            )
            sessions[sid] = T.SessionObs(
                sid=sid,
                acct="next3",
                cfg="/c3",
                pid=100 + i,
                lstart=L,
                cwd=self.tmp,
                pane=(5, 10 + i),
                registry_name="p%d" % i,
                holders=[h],
                transcript=T.TranscriptObs(
                    path="/t%d.jsonl" % i, last={}, at_rest=True
                ),
            )
        return T.Snapshot(wall=self.now, uptime_raw=0.0, panes=panes, sessions=sessions)

    def composer(self, *_a, **_kw):
        self.reads += 1
        return "empty"

    def census(self, ctx, snap, now=None):
        with mock.patch.object(M.observe, "composer_state", self.composer):
            buckets, _stale = M._census(
                ctx, snap, self.facts(), [], "act", now or self.now
            )
        return {b.sid: b for b in buckets}


class Switch(Base):
    def test_absent_no_idle_record_present_fans_out(self):
        """[RED before W13] the file present and LR_IDLE_FANOUT unset: the at-rest, empty-composer,
        unfocused session under an uncontradicted 7d fact buckets IDLE-ELIGIBLE and opens a fan-out
        record; on ed6f47072 it was WORKING "no idle fan-out" (the daemon read the env only)."""
        self.markers()
        snap, ctx = self.snap(), M.Ctx(self.paths, None, self.home)
        b = next(iter(self.census(ctx, snap).values()))
        self.assertEqual((b.name, b.reason), ("WORKING", "no idle fan-out"))
        self.assertEqual(
            (ctx.records, self.reads), ({}, 0)
        )  # no composer read while off
        self.switch(True)
        b = next(iter(self.census(ctx, snap).values()))
        self.assertEqual(b.name, "IDLE-ELIGIBLE")
        self.assertEqual(self.reads, 1)
        rec = ctx.records[b.sid]
        self.assertEqual(
            (rec.kind, rec.origin, rec.plan_only), ("idle", "fanout", False)
        )
        self.switch(False)  # read every pass: off again with no restart
        ctx2 = M.Ctx(self.paths, None, self.home)
        self.assertEqual(next(iter(self.census(ctx2, snap).values())).name, "WORKING")
        self.assertEqual(ctx2.records, {})

    def test_env_off_beats_the_file_and_env_on_still_works(self):
        self.switch(True)
        with mock.patch.dict(os.environ, {"LR_IDLE_FANOUT": "off"}):
            self.assertIs(M.fanout_env(self.paths), os.environ)
            ctx = M.Ctx(self.paths, None, self.home)
            self.assertEqual(
                next(iter(self.census(ctx, self.snap()).values())).name, "WORKING"
            )
            self.assertEqual(self.reads, 0)
        self.switch(False)
        with mock.patch.dict(os.environ, {"LR_IDLE_FANOUT": "on"}):
            ctx = M.Ctx(self.paths, None, self.home)
            self.assertEqual(
                next(iter(self.census(ctx, self.snap()).values())).name, "IDLE-ELIGIBLE"
            )

    def test_fanout_records_stay_plan_only_without_the_zero_human_markers(self):
        """The zero-human gate is unchanged: the switch alone never makes a fan-out record act."""
        self.switch(True)
        ctx = M.Ctx(self.paths, None, self.home)
        b = next(iter(self.census(ctx, self.snap()).values()))
        self.assertTrue(ctx.records[b.sid].plan_only)


class ComposerBudget(Base):
    def test_ttl_keeps_a_verdict_60s(self):
        self.switch(True)
        snap, ctx = self.snap(), M.Ctx(self.paths, None, self.home)
        self.census(ctx, snap, self.now)
        self.census(ctx, snap, self.now + 30)
        self.assertEqual(self.reads, 1, "re-read inside the TTL")
        self.census(ctx, snap, self.now + M.IDLE_COMPOSER_TTL_S + 1)
        self.assertEqual(self.reads, 2)
        self.assertGreaterEqual(M.IDLE_COMPOSER_TTL_S, 60.0)

    def test_at_most_four_idle_reads_per_pass(self):
        self.switch(True)
        snap, ctx = self.snap(6), M.Ctx(self.paths, None, self.home)
        got = self.census(ctx, snap)
        self.assertEqual(self.reads, M.IDLE_COMPOSER_READS)
        self.assertEqual(M.IDLE_COMPOSER_READS, 4)
        names = sorted(b.name for b in got.values())
        self.assertEqual(names, ["IDLE-ELIGIBLE"] * 4 + ["WORKING"] * 2)
        self.assertEqual(ctx.idle_composer.capped, 2)
        # the next pass inside the TTL reads only the two it could not reach
        got = self.census(ctx, snap, self.now + 5)
        self.assertEqual(self.reads, 6)
        self.assertEqual([b.name for b in got.values()], ["IDLE-ELIGIBLE"] * 6)

    def test_idle_reads_ride_inside_the_w9_composer_gate(self):
        """Each idle read is a ComposerGate read: a spent budget gives "unknown" and no child, and
        that "unknown" is not kept, so the session is read on the next pass."""
        self.switch(True)
        snap, ctx = self.snap(), M.Ctx(self.paths, None, self.home)
        gate = M.ComposerGate(1, {}, [], True, budget_s=0.0)
        ctx.composer_gate = gate
        b = next(iter(self.census(ctx, snap).values()))
        self.assertEqual((b.name, self.reads, gate.skipped), ("WORKING", 0, 1))
        ctx.composer_gate = None
        self.assertEqual(
            next(iter(self.census(ctx, snap, self.now + 1).values())).name,
            "IDLE-ELIGIBLE",
        )


class BootSlots(Base):
    def rec(self, i, kind, **kw):
        r = T.Record(
            sid="%s-%04d" % (kind, i),
            record_id="r-%s-%d" % (kind, i),
            kind=kind,
            source_acct="next3",
            source_cfg="/c3",
            target_acct="next4",
            target_cfg="/c4",
            phase="PRE-MOVE",
            substate="PLANNED",
            pane=(5, 50 + i if kind == "idle" else 80 + i),
            cwd=self.tmp,
        )
        r.timeline.detected = self.now - 60
        for k, v in kw.items():
            setattr(r, k, v)
        return r

    def ctx(self, *recs):
        ctx = M.Ctx(self.paths, None, self.home)
        ctx.boots.store = ""  # memory only: never the shared swap-slots
        ctx.records = {r.sid: r for r in recs}
        return ctx

    def test_overdue_limited_waiting_means_zero_idle_slots(self):
        idle = self.rec(1, "idle")
        late = self.rec(1, "limited", phase="PRE-MOVE", substate="WAIT_SLOT")
        ctx = self.ctx(idle, late)
        with mock.patch.object(M.admit, "overdue", lambda r, now, env=None: r is late):
            self.assertEqual(
                M._admit(ctx, idle, "A", T.Snapshot(0, 0.0), self.now),
                (False, "idle-yields-overdue"),
            )
        self.assertEqual(ctx.boots.held, set())
        ctx.slot_priority_want = (
            "overdue x waits on boot slots"  # W11's own signal, alone
        )
        self.assertEqual(
            M._idle_boot_refusal(ctx, idle, self.now), "idle-yields-overdue"
        )

    def test_one_idle_slot_while_a_limited_record_is_open(self):
        i1, i2, lim = self.rec(1, "idle"), self.rec(2, "idle"), self.rec(1, "limited")
        lim.substate = "WAIT_SLOT"
        ctx = self.ctx(i1, i2, lim)
        snap = T.Snapshot(wall=self.now, uptime_raw=0.0)
        self.assertEqual(
            M._admit(ctx, i1, "A", snap, self.now), (True, "no-first-turn")
        )
        self.assertEqual(
            M._admit(ctx, i2, "A", snap, self.now), (False, "idle-slot-cap")
        )
        self.assertEqual(ctx.boots.held, {i1.sid})
        del ctx.records[
            lim.sid
        ]  # CONTROL: no limited record open, idle may fill the pool
        self.assertEqual(
            M._admit(ctx, i2, "A", snap, self.now), (True, "no-first-turn")
        )

    def test_a_limited_relaunch_never_waits_on_an_idle_boot(self):
        """Pass 1: three idle records ready while one limited record waits on its reset. Pass 2:
        five limited records are PLANNED. With D2a every one gets a slot (D_eff 5 of 6); before
        W13 the idle records held 3 and two limited relaunches waited on idle boots."""
        idle = [self.rec(i, "idle") for i in range(3)]
        lim = [self.rec(i, "limited", substate="WAIT_RESET") for i in range(5)]
        ctx = self.ctx(*(idle + lim))
        seen = []
        orig = M._admit

        def spy(c, r, which, sn, nw):
            out = orig(c, r, which, sn, nw)
            seen.append((r.kind, out[1]))
            return out

        snap = T.Snapshot(wall=self.now, uptime_raw=0.0)
        with (
            mock.patch.object(M, "_admit", spy),
            mock.patch.object(M.act, "may_actuate", return_value=(True, "ok")),
            mock.patch.object(M.act, "hold_claim", return_value=(True, "taken")),
            mock.patch.object(M.act, "spawn", return_value=4242),
            mock.patch.object(M, "_command", return_value=["true"]),
            mock.patch.object(M.store, "append_launch"),
            mock.patch.object(ctx.admission, "decide", return_value=(True, "admit")),
            mock.patch.object(ctx.admission, "mint_token", return_value=None),
        ):
            M._dispatch(ctx, snap, "act", self.now)
            self.assertEqual(sum(1 for s in ctx.boots.held if s.startswith("idle")), 1)
            for r in lim:
                r.substate = "PLANNED"
            seen.clear()
            M._dispatch(ctx, snap, "act", self.now)
        lim_seen = [why for kind, why in seen if kind == "limited"]
        self.assertEqual(len(lim_seen), 5)
        self.assertNotIn("boot-slots", lim_seen, seen)


class HoldClaim(Base):
    def test_a_fanout_record_with_a_live_move_lane_claim_is_refused_at_hold_claim(self):
        """D16: may_actuate has no claim check; the one-driver rule is act.hold_claim, which
        _dispatch calls before any admission. A live cc-lr move claim keeps the session: no token,
        no boot slot, no spawn, and a claim-held event."""
        self.switch(True)
        self.markers()
        with open(self.paths.mode_file, "w") as fh:
            fh.write("act\n")
        snap, ctx = self.snap(), M.Ctx(self.paths, None, self.home)
        ctx.boots.store = ""
        b = next(iter(self.census(ctx, snap).values()))
        rec = ctx.records[b.sid]
        rec.substate, rec.target_acct, rec.target_cfg = "PLANNED", "next4", "/c4"
        mover = T.RunClaimHolder(
            pid=4000, lstart=L, owner="cc-lr-move", record_id="move:b1"
        )
        self.assertEqual(
            M.store.claim_take(
                self.paths, rec.sid, mover, lambda p, l: True, lambda p: ""
            ),
            "taken",
        )
        with (
            mock.patch.object(M, "_alive", lambda pid, ls: pid == 4000),
            mock.patch.object(M.act, "spawn", return_value=4242) as sp,
            mock.patch.object(M, "_command", return_value=["true"]),
        ):
            self.assertEqual(M._dispatch(ctx, snap, "act", self.now), 0)
        sp.assert_not_called()
        self.assertEqual(ctx.boots.held, set())
        self.assertEqual(rec.close.get("claim_held"), "held")
        self.assertEqual(M.store.read_claim(self.paths, rec.sid).owner, "cc-lr-move")


if __name__ == "__main__":
    unittest.main()
