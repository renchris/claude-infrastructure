"""lr-wake 2026-10-18, Wave G: one driver per session, the cohort exit, the stranded tombstone and
the reset-aware drain (docs/research/lr-wake-incident-2026-10-18/REPORT.md §4 Wave G, h defects 3
and 5). Driven per case by the tests/lr-recon-*.bats wrappers; each class names its incident."""

import json
import os
import shutil
import subprocess
import tempfile
import time
import unittest
from unittest import mock

from lr_recon import __main__ as M
from lr_recon import capped, census, drain, settle, store
from lr_recon import types as T

L = "Tue Sep 29 11:19:17 2026"
SID = "3e929a81-0000-4000-8000-000000000001"
HERE = os.path.dirname(os.path.abspath(__file__))
LR = os.path.dirname(os.path.dirname(HERE))  # scripts/limit-recover


def _iso(t):
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(t))


class _Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.home = os.path.join(self.tmp, "home")
        os.makedirs(self.home)
        self.usage = os.path.join(self.tmp, "usage.jsonl")
        env = mock.patch.dict(
            os.environ,
            {
                "LR_STATE_DIR": os.path.join(self.tmp, "lr"),
                "HOME": self.home,
                "LR_RECON_USAGE_FILE": self.usage,
                "LR_PAGE_BIN": "/nonexistent-page-bin",
                "LR_NOTIFY_BIN": "/nonexistent-notify-bin",
            },
        )
        env.start()
        self.addCleanup(env.stop)
        for target, rv in (("probe", (True, "admit")), ("mint_token", None)):
            p = mock.patch("lr_recon.admit.Admission." + target, return_value=rv)
            setattr(self, target, p.start())
            self.addCleanup(p.stop)
        self.paths = T.Paths.from_env(root=os.path.join(self.tmp, "lr", "recon"))
        store.ensure_dirs(self.paths)
        open(self.paths.recon_on, "w").close()
        self.now = time.time()

    def _events(self, name):
        if not os.path.exists(self.paths.events):
            return []
        with open(self.paths.events, encoding="utf-8") as fh:
            return [e for e in map(json.loads, filter(None, fh)) if e.get("ev") == name]

    def _usage(self, acct, weekly, at=None, wire=None):
        with open(self.usage, "a", encoding="utf-8") as fh:
            fh.write(
                json.dumps(
                    {
                        "ts": _iso(self.now if at is None else at),
                        "acct": acct,
                        "session_pct": 1,
                        "weekly_pct": weekly,
                        "weekly_reset_at": _iso(self.now + 6 * 86400),
                        "wire_7d_status": wire,
                        "stale": False,
                    }
                )
                + "\n"
            )


# ── one driver per session (REPORT §4 Wave G "One driver per session") ─────────────────────────


class OneDriverPerSession(_Base):
    """3e929a81, 2026-10-18: a drain batch (`cc-lr move`, which takes runs/by-sid/<sid>.active), the
    poller and the reconciler cohort all drove it; the reconciler logged its claim `held` and
    dispatched anyway. Two lr-handoff runs on one session, 2 s apart: the second gets claim-held."""

    def _planned(self):
        ctx = M.Ctx(self.paths, None, self.home)
        r = T.Record(
            sid=SID,
            record_id="recon:next4-7d:%s:1" % SID[:8],
            kind="limited",
            source_acct="next4",
            source_cfg="/c4",
            scope="7d",
            cohort_id="next4-7d-1792314000",
            target_acct="next2",
            target_cfg="/c2",
            substate="PLANNED",
        )
        ctx.records[SID] = r
        return ctx, r, T.Snapshot(wall=self.now, uptime_raw=0.0)

    def _bash_lane_holds(self):
        """The first run: a live process stamped as the holder, the way lr-lib.sh lr_claim_stamp does."""
        p = subprocess.Popen(["sleep", "60"])
        self.addCleanup(p.wait)
        self.addCleanup(p.kill)
        d = store.claim_dir(self.paths, SID)
        os.makedirs(d)
        with open(os.path.join(d, "holder"), "w") as fh:
            json.dump(
                {
                    "sid": SID,
                    "pane": "23",
                    "pid": p.pid,
                    "ts": _iso(self.now),
                    "by": "cc-lr-move",
                    "lstart": store.proc_lstart(p.pid),
                },
                fh,
            )
        return p

    def _dispatch(self, ctx, snap, now):
        with mock.patch.object(M.act, "spawn", return_value=4242) as sp:
            n = M._dispatch(ctx, snap, "act", now)
        return n, sp

    def test_a_second_driver_2s_later_gets_claim_held_and_no_token(self):
        holder = self._bash_lane_holds()
        ctx, r, snap = self._planned()
        n, sp = self._dispatch(ctx, snap, self.now + 2)
        self.assertEqual(n, 0)
        sp.assert_not_called()
        self.mint_token.assert_not_called()
        ev = self._events("claim-held")
        self.assertEqual(len(ev), 1, ev)
        self.assertIn("pid %d" % holder.pid, ev[0]["detail"])
        # the same standing hold is recorded once, not every pass
        self._dispatch(ctx, snap, self.now + 4)
        self.assertEqual(len(self._events("claim-held")), 1)

    def test_once_the_first_driver_is_gone_the_reconciler_takes_the_claim(self):
        holder = self._bash_lane_holds()
        holder.kill()
        holder.wait()
        ctx, r, snap = self._planned()
        n, sp = self._dispatch(ctx, snap, self.now + 2)
        self.assertEqual(n, 1)
        self.assertEqual(store.read_claim(self.paths, SID).record_id, r.record_id)

    def test_a_bash_lane_two_seconds_after_the_reconciler_is_refused(self):
        ctx, r, snap = self._planned()
        self.assertEqual(self._dispatch(ctx, snap, self.now)[0], 1)
        cp = subprocess.run(
            [
                "/bin/bash",
                "-c",
                '. "$1/lr-lib.sh"; lr_claim_take "$2" "$3" cc-lr-move 23 $$',
                "_",
                LR,
                self.paths.runs_by_sid,
                SID,
            ],
            capture_output=True,
            text=True,
            timeout=60,
        )
        self.assertEqual(cp.returncode, 1, cp.stdout + cp.stderr)


# ── the cohort exit (h defect 3) ────────────────────────────────────────────────────────────────


class CohortExit(_Base):
    """Cohort next4-7d-1792314000 held 3e929a81 PRE-MOVE 11 h after it formed, with next4 back at
    5% weekly. A member whose source is under its caps, or past the cohort's reset, is NOT_NEEDED and
    is continued in place; no move."""

    def _world(self, resets, weekly, holder_in_pane=True):
        ctx = M.Ctx(self.paths, None, self.home)
        r = T.Record(
            sid=SID,
            record_id="recon:next4-7d:%s:1" % SID[:8],
            kind="limited",
            source_acct="next4",
            source_cfg="/c4",
            scope="7d",
            cohort_id=census.cohort_id("next4", "7d", resets),
            target_acct="next2",
            target_cfg="/c2",
            substate="PLANNED",
            pane=(5, 7),
        )
        r.timeline.detected = self.now - 11 * 3600
        r.timeline.planned = self.now - 11 * 3600
        ctx.records[SID] = r
        holders = (
            [T.HolderObs(pid=10, lstart=L, cfg="/c4", src="registry", pane=(5, 7))]
            if holder_in_pane
            else []
        )
        s = T.SessionObs(
            sid=SID,
            acct="next4",
            cfg="/c4",
            pid=10,
            lstart=L,
            pane=(5, 7),
            holders=holders,
            transcript=T.TranscriptObs(
                at_rest=True, last={"limit": True, "kind": "limit", "cap": "seven_day"}
            ),
        )
        pane = T.PaneObs(
            kitty_pid=5,
            window_id=7,
            sock="unix:/tmp/kitty-5",
            root_shape="shell",
            state="claude",
        )
        snap = T.Snapshot(
            wall=self.now,
            uptime_raw=0.0,
            panes={"5:7": pane},
            sessions={SID: s},
        )
        facts = {
            "next4.7d": T.Fact(
                acct="next4",
                scope="7d",
                window="seven_day",
                resets_at=resets,
                observed_at=self.now - 11 * 3600,
                src="hook",
            )
        }
        if weekly is not None:
            self._usage("next4", weekly)
        return ctx, r, snap, facts

    def _derive(self, ctx, snap, facts):
        with mock.patch.object(M.plan, "unassign", return_value=0) as un:
            M._derive(
                ctx, snap, self.now, facts, capped.latest_usage(self.home, self.now)
            )
        return un

    def test_next4_at_5pct_weekly_member_is_not_needed_and_continued_in_place(self):
        ctx, r, snap, facts = self._world(self.now + 6 * 86400, 5)
        un = self._derive(ctx, snap, facts)
        un.assert_called_once()  # its seat on next2 is voided
        self.assertEqual(r.target_acct, "")
        self.assertEqual((r.substate, r.wait.detail), ("WAIT_RESET", "stay"))
        self.assertIn("weekly_pct 5%", self._events("cohort-exit-resume")[0]["detail"])
        # the census reads it LIMITED until the continue lands: it is not re-planned as a move
        self.assertFalse(settle.rebucket(r, "LIMITED", self.now))
        # the wake continues it in its OWN pane, through the one-driver claim
        self.assertEqual(M._wakes(ctx, snap, facts, self.now), 1)
        with mock.patch.object(M.act, "spawn", return_value=4242) as sp:
            self.assertEqual(M._dispatch(ctx, snap, "act", self.now), 1)
        self.assertEqual(sp.call_args.args[2], "C")
        self.assertEqual(sp.call_args.args[3][4], "7")
        # the fresh turn closes it NOT_NEEDED, never as a move
        s = snap.sessions[SID]
        s.transcript.last, s.transcript.last_assistant_ok_at = (
            {"kind": "ok"},
            self.now + 30,
        )
        self._derive(ctx, snap, facts)
        self.assertEqual(r.terminal.outcome, "NOT_NEEDED")
        self.assertIn("cohort exit", r.terminal.proof)

    def test_past_the_cohort_reset_with_nothing_in_the_pane_closes_at_once(self):
        ctx, r, snap, facts = self._world(
            self.now - 4 * 3600, None, holder_in_pane=False
        )
        snap.sessions[SID].holders = [
            T.HolderObs(pid=11, lstart=L, cfg="/c4", src="resume-argv", pane=None)
        ]
        self._derive(ctx, snap, facts)
        self.assertEqual(r.terminal.outcome, "NOT_NEEDED")
        self.assertIn("past the reset", r.terminal.proof)

    def test_control_a_source_still_at_100pct_keeps_its_move(self):
        ctx, r, snap, facts = self._world(self.now + 6 * 86400, 100)
        self._derive(ctx, snap, facts)
        self.assertEqual((r.substate, r.target_acct), ("PLANNED", "next2"))
        self.assertIsNone(r.terminal)

    def test_control_no_usage_reading_is_not_recovery(self):
        ctx, r, snap, facts = self._world(self.now + 6 * 86400, None)
        self._derive(ctx, snap, facts)
        self.assertEqual(r.substate, "PLANNED")

    def test_control_a_confirmed_transplant_is_the_phase_tables(self):
        ctx, r, snap, facts = self._world(self.now - 4 * 3600, 5)
        r.timeline.confirmed = self.now - 3600
        self.assertEqual(
            settle.cohort_exit(
                r, facts, capped.latest_usage(self.home), snap, self.now
            ),
            ("", False),
        )


# ── the stranded tombstone (h defect 5) ─────────────────────────────────────────────────────────


class StrandedTombstone(_Base):
    """3e929a81 at 03:03Z: the next4→next3 transplant tombstoned the source, the next3 copy never
    gained a byte, and the old process stayed in pane 23 behind the handed-off guard."""

    def _stores(self, age_s=1200, grew=False, live_target=False):
        src = os.path.join(self.home, ".claude-quaternary")
        dst = os.path.join(self.home, ".claude-tertiary")
        for d in (src, dst):
            os.makedirs(os.path.join(d, "projects", "-x"))
        os.makedirs(os.path.join(self.home, ".claude"), exist_ok=True)
        with open(os.path.join(self.home, ".claude", "accounts.json"), "w") as fh:
            json.dump(
                {
                    "accounts": [
                        {"name": "next4", "config_dir": src},
                        {"name": "next3", "config_dir": dst},
                    ]
                },
                fh,
            )
        body = (
            b'{"type":"assistant","isApiErrorMessage":true,"error":"rate_limit"}\n' * 40
        )
        succ = os.path.join(dst, "projects", "-x", SID + ".jsonl")
        with open(succ, "wb") as fh:
            fh.write(body + (b'{"type":"user"}\n' if grew else b""))
        with open(
            os.path.join(src, "projects", "-x", SID + ".jsonl.handed-off"), "wb"
        ) as fh:
            fh.write(body)
        ts = self.now - age_s
        os.utime(succ, (ts - 420, ts - 420 if not grew else self.now - 5))
        with open(
            os.path.join(src, "projects", "-x", SID + ".HANDOFF.json"), "w"
        ) as fh:
            json.dump(
                {
                    "handed_off_to": dst,
                    "target_transcript": succ,
                    "ts": _iso(ts),
                    "confirm_len": len(body),
                },
                fh,
            )
        holders = [T.HolderObs(pid=10, lstart=L, cfg=src, src="registry", pane=(5, 23))]
        if live_target:
            holders.append(T.HolderObs(pid=12, lstart=L, cfg=dst, src="resume-argv"))
        s = T.SessionObs(sid=SID, acct="next4", cfg=src, cwd=self.tmp, holders=holders)
        return src, dst, s

    def test_a_quiet_tombstone_with_its_old_process_in_a_pane_is_stranded(self):
        src, dst, s = self._stores()
        plan_ = census.stranded_tombstone(
            SID, src, s, self.now, amap={"next4": src, "next3": dst}
        )
        self.assertIsNotNone(plan_)
        self.assertEqual((plan_["pane"], plan_["target_acct"]), ("5:23", "next3"))
        self.assertIn("lr-unstrand.sh --sid " + SID, plan_["command"])

    def test_controls_a_young_a_grown_or_a_live_successor_is_not_stranded(self):
        src, _dst, s = self._stores(age_s=120)
        self.assertIsNone(census.stranded_tombstone(SID, src, s, self.now))
        shutil.rmtree(self.home)
        os.makedirs(self.home)
        src, _dst, s = self._stores(grew=True)
        self.assertIsNone(census.stranded_tombstone(SID, src, s, self.now))
        shutil.rmtree(self.home)
        os.makedirs(self.home)
        src, _dst, s = self._stores(live_target=True)
        self.assertIsNone(census.stranded_tombstone(SID, src, s, self.now))

    def test_the_pass_records_and_pages_it_once(self):
        src, _dst, s = self._stores()
        ctx = M.Ctx(self.paths, None, self.home)
        snap = T.Snapshot(wall=self.now, uptime_raw=0.0, sessions={SID: s})
        pages = []
        ctx.reporter = M.report.Reporter(self.paths, "act", page=pages.append)
        self.assertEqual(M._stranded(ctx, snap, "act", self.now), 1)
        self.assertEqual(M._stranded(ctx, snap, "act", self.now + 60), 1)
        self.assertEqual(len(pages), 1, pages)
        self.assertIn("STRANDED 3e929a81", pages[0])
        self.assertIn("lr-unstrand.sh --sid " + SID, pages[0])
        self.assertEqual(len(self._events("stranded-tombstone")), 1)


# ── the drain, reset-aware (RC7) ────────────────────────────────────────────────────────────────


class ResetAwareDrain(_Base):
    """drain-v2.sh rotated next4 "past its weekly reset": every ~10 min from 18:37Z on 10-18 it
    re-rotated healthy sessions, rc=1 each time."""

    def _fact(self, resets, contradicted=False):
        return {
            "next4.7d": T.Fact(
                acct="next4",
                scope="7d",
                resets_at=resets,
                observed_at=self.now - 3600,
                contradicted=contradicted,
            )
        }

    def test_past_the_reset_is_not_capped(self):
        go, why, _w = drain.decide(
            "next4", "7d", self._fact(self.now - 3600), {}, {}, self.now
        )
        self.assertFalse(go)
        self.assertIn("not capped", why)

    def test_a_capped_window_drains_until_its_first_rc_1_then_stops(self):
        resets = self.now + 3600
        go, _why, w = drain.decide("next4", "7d", self._fact(resets), {}, {}, self.now)
        self.assertTrue(go)
        latch = {"window": w, "rc": 1, "stopped": True, "at_utc": "x"}
        go, why, _w = drain.decide(
            "next4", "7d", self._fact(resets), {}, latch, self.now
        )
        self.assertFalse(go)
        self.assertIn("stopped until a new window", why)
        # a new capped window (a later reset) drains again
        go, _why, _w = drain.decide(
            "next4", "7d", self._fact(resets + 7 * 86400), {}, latch, self.now
        )
        self.assertTrue(go)

    def test_a_fresh_usage_row_under_100_outranks_an_old_fact(self):
        self._usage("next4", 5)
        usage = capped.latest_usage(self.home, self.now)
        go, why, _w = drain.decide(
            "next4", "7d", self._fact(self.now + 3600), usage, {}, self.now
        )
        self.assertFalse(go)
        self.assertIn("under its caps", why)

    def test_the_cli_runs_nothing_without_act_and_latches_rc_1_with_it(self):
        stub = os.path.join(self.tmp, "cc-lr")
        with open(stub, "w") as fh:
            fh.write('#!/bin/bash\necho "$*" >> "%s/cclr.log"\nexit 1\n' % self.tmp)
        os.chmod(stub, 0o755)
        self._usage("next4", 100, wire="rejected")
        with mock.patch.dict(os.environ, {"LR_DRAIN_CCLR_BIN": stub}):
            self.assertEqual(drain.run(["--from", "next4", "--to", "next2"]), 0)
            self.assertFalse(os.path.exists(os.path.join(self.tmp, "cclr.log")))
            self.assertEqual(
                drain.run(["--from", "next4", "--to", "next2", "--act"]), 0
            )
            self.assertEqual(
                drain.run(["--from", "next4", "--to", "next2", "--act"]), 0
            )
        with open(os.path.join(self.tmp, "cclr.log")) as fh:
            self.assertEqual(len(fh.readlines()), 1)  # stopped after the first rc=1
        self.assertTrue(drain.read_latch(self.paths, "next4", "7d")["stopped"])


class ProvenanceReach(_Base):
    """The reconciler daemon runs from ~/.claude/scripts/limit-recover, a farm of per-file
    symlinks with no scripts/checks/ beside it: the hourly provenance check must still be found."""

    def test_the_check_is_found_through_a_symlink_farm(self):
        farm = os.path.join(self.tmp, "farm", "scripts", "limit-recover", "lr_recon")
        os.makedirs(farm)
        link = os.path.join(farm, "act.py")
        os.symlink(os.path.realpath(M.act.__file__), link)
        path = M.provenance_check(link)
        self.assertTrue(os.path.isfile(path), path)
        self.assertFalse(path.startswith(os.path.join(self.tmp, "farm")), path)


if __name__ == "__main__":
    unittest.main()
