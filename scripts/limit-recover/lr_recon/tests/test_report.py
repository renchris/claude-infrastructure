"""report.py (§C11, §7.4): latched cohort pages, coalesced deltas, max ages, observe mode, readout."""

import json
import os
import shutil
import tempfile
import time
import unittest
from typing import Any, List, Optional, Tuple

from lr_recon import report as R
from lr_recon import store as S
from lr_recon import types as T

T0 = 1790000000.0


class Clock:
    def __init__(self, t: float = T0) -> None:
        self.t = t

    def __call__(self) -> float:
        return self.t


def rec(n: int, cid: str = "c1", **kw: Any) -> T.Record:
    sid = "%08d-0000-0000-0000-000000000000" % n
    r = T.Record(
        sid=sid,
        record_id=T.make_record_id(cid, sid, 1),
        cohort_id=cid,
        source_acct="next3",
        scope="7d",
        cwd="/tmp/repo%d" % n,
        pane=(12, n),
    )
    r.timeline.detected = T0
    for k, v in kw.items():
        setattr(r, k, v)
    return r


def wait(
    reason: str, since: float = T0, eta: Optional[float] = None, detail: str = ""
) -> T.Wait:
    return T.Wait(reason=reason, since=since, eta=eta, detail=detail)


def done(r: T.Record, outcome: str = "CLOSED", at: float = T0 + 221) -> T.Record:
    r.terminal = T.Terminal(outcome=outcome, proof="p", at=at)
    return r


class ReportTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.mkdtemp(prefix="lr-report-")
        self.paths = T.Paths(lr_root=self.tmp, root=os.path.join(self.tmp, "recon"))
        self.clock = Clock()
        self.pages: List[str] = []
        self.mails: List[Tuple[str, str]] = []
        self.cohort = T.Cohort(
            cid="c1", acct="next3", scope="7d", resets_at=T0 + 3600, opened_at=T0
        )

    def tearDown(self) -> None:
        shutil.rmtree(self.tmp, ignore_errors=True)

    def reporter(self, mode: str = "act") -> R.Reporter:
        return R.Reporter(
            self.paths,
            mode,
            page=self.pages.append,
            mail=lambda p, t: self.mails.append((p, t)),
            now=self.clock,
        )

    # ── OPEN ───────────────────────────────────────────────────────────────────────────────────
    def test_open_latches_across_calls_and_restart(self) -> None:
        recs = [
            rec(1, target_acct="next4", weight=5),
            rec(2, kind="idle"),
            rec(3, wait=wait("WAIT_SLOT", eta=T0 + 600)),
        ]
        pl = {recs[2].sid: T.Placement(acct=None, reason="next=kmax k_work 18")}
        text = self.reporter().open_page(self.cohort, recs, pl)
        assert text is not None
        self.assertIn("next3 LIMITED (7d) until", text)
        self.assertIn("2 blocked, 1 idle", text)
        self.assertIn("next4←1 (weight 5)", text)
        self.assertIn("2 WAITING (next=kmax k_work 18) earliest wake", text)
        self.assertIsNone(self.reporter().open_page(self.cohort, recs, pl))
        rep = self.reporter()
        self.assertIsNone(rep.open_page(self.cohort, recs, pl))
        self.assertEqual(self.pages, [text])

    # ── DELTA ──────────────────────────────────────────────────────────────────────────────────
    def test_delta_silent_when_unchanged(self) -> None:
        rep, recs = self.reporter(), [rec(1), rec(2)]
        rep.open_page(self.cohort, recs, {})
        self.clock.t += 900
        self.assertIsNone(rep.delta_page(self.cohort, recs))
        self.assertEqual(len(self.pages), 1)

    def test_delta_coalesces_within_five_minutes(self) -> None:
        rep, recs = self.reporter(), [rec(1), rec(2)]
        rep.open_page(self.cohort, recs, {})
        self.clock.t += 30
        recs[0].phase, recs[0].substate = "MOVED", None
        first = rep.delta_page(self.cohort, recs)
        self.assertIsNotNone(first)
        self.clock.t += 60
        done(recs[1])
        self.assertIsNone(rep.delta_page(self.cohort, recs))
        self.assertEqual(len(self.pages), 2)  # OPEN + one DELTA
        self.clock.t += R.DELTA_MIN_GAP_S
        later = rep.delta_page(self.cohort, recs)
        assert later is not None
        self.assertIn("next3 7d cohort update: 2 members", later)
        self.assertIsNone(
            self.reporter().delta_page(self.cohort, recs)
        )  # restart: same hash

    # ── CLOSE ──────────────────────────────────────────────────────────────────────────────────
    def test_close_full(self) -> None:
        recs = [done(rec(i)) for i in range(1, 4)]
        text = self.reporter().close_page(self.cohort, recs)
        self.assertEqual(text, "next3 7d cohort closed: 3/3 in 3m41s")
        self.assertIsNone(self.reporter().close_page(self.cohort, recs))

    def test_close_residue_names_each_member(self) -> None:
        recs = [
            done(rec(1)),
            rec(2, wait=wait("HOLD-DRAFT")),
            done(rec(3), "IMPOSSIBLE"),
        ]
        text = self.reporter().close_page(self.cohort, recs)
        assert text is not None
        self.assertIn("1/3", text)
        self.assertIn(
            "session 00000002 (pane 12:2, repo2) — held: an unsent draft", text
        )
        self.assertIn("next: send or clear the draft", text)
        self.assertIn("session 00000003 (pane 12:3, repo3) — outcome impossible", text)
        self.assertNotIn("00000001", text)

    # ── observe ────────────────────────────────────────────────────────────────────────────────
    def test_observe_pages_nothing_and_shadows(self) -> None:
        rep = self.reporter("observe")
        recs = [rec(1, escalated=True)]
        self.assertIsNotNone(rep.open_page(self.cohort, recs, {}))
        self.assertEqual(len(rep.immediate_pages(self.cohort, recs[0])), 1)
        self.assertTrue(rep.mail_requester(self.cohort, "7", "moved"))
        self.assertEqual((self.pages, self.mails), ([], []))
        with open(os.path.join(self.paths.shadow, "pages.jsonl")) as fh:
            rows = [json.loads(line) for line in fh]
        self.assertEqual([r["kind"] for r in rows], ["OPEN", "ESCALATED", "MAIL"])
        dig = rep.digest()
        self.assertTrue(dig.startswith("lr-recon observe: 3 page(s) withheld"))
        self.assertEqual(rep.digest(), "")

    def test_sink_failure_is_counted_not_raised(self) -> None:
        def boom(_t: str) -> None:
            raise OSError("no notifier")

        rep = R.Reporter(
            self.paths, "act", page=boom, mail=lambda p, t: None, now=self.clock
        )
        self.assertIsNotNone(rep.close_page(self.cohort, [done(rec(1))]))
        self.assertEqual(rep.failures, 1)

    def test_mail_once_per_cohort(self) -> None:
        rep = self.reporter()
        self.assertTrue(rep.mail_requester(self.cohort, "7", "3/3 moved"))
        self.assertFalse(rep.mail_requester(self.cohort, "7", "again"))
        self.assertEqual(self.mails, [("7", "next3 7d: 3/3 moved")])

    # ── max ages ───────────────────────────────────────────────────────────────────────────────
    def due(self, r: T.Record, age: float) -> bool:
        return R.max_age_due(r, T0 + age)

    def test_max_age_table(self) -> None:
        self.assertFalse(self.due(rec(1, wait=wait("WAIT_DATA")), 119))
        self.assertTrue(self.due(rec(1, wait=wait("WAIT_DATA")), 120))
        self.assertTrue(self.due(rec(1, wait=wait("WAIT_CAPACITY")), 900))
        self.assertFalse(self.due(rec(1, wait=wait("HOLD-SUBAGENTS")), 1799))
        self.assertTrue(self.due(rec(1, wait=wait("HOLD-MENU")), 0))
        self.assertTrue(self.due(rec(1, wait=wait("HOLD:iterm")), 0))
        self.assertFalse(self.due(rec(1, wait=wait("WAIT_RESET")), 99999))
        self.assertFalse(self.due(done(rec(1, wait=wait("HOLD-MENU"))), 0))

    def test_wait_slot_and_held_team_are_relative_to_eta(self) -> None:
        slot = rec(1, wait=wait("WAIT_SLOT", eta=T0 + 1000))
        self.assertFalse(self.due(slot, 1599))
        self.assertTrue(self.due(slot, 1600))
        team = rec(2, wait=wait("HELD:team", eta=T0 + 3600))
        self.assertFalse(self.due(team, 4199))
        self.assertTrue(self.due(team, 4200))

    def test_bgwork_shipland_sixty_minutes_else_twenty(self) -> None:
        plain = rec(1, wait=wait("HOLD-BGWORK", detail="npm test"))
        ship = rec(2, wait=wait("HOLD-BGWORK", detail="ship-land.sh running"))
        self.assertTrue(self.due(plain, 1200))
        self.assertFalse(self.due(ship, 1200))
        self.assertFalse(self.due(ship, 3599))
        self.assertTrue(self.due(ship, 3600))

    def test_max_age_page_refires_hourly(self) -> None:
        rep, r = self.reporter(), rec(1, wait=wait("WAIT_DATA"))
        self.assertIsNone(rep.max_age_page(self.cohort, r))
        self.clock.t = T0 + 121
        text = rep.max_age_page(self.cohort, r)
        assert text is not None
        self.assertIn("next3 7d: session 00000001", text)
        self.assertIn("waiting for account data for 2m01s, past its maximum age", text)
        self.clock.t += 3599
        self.assertIsNone(self.reporter().max_age_page(self.cohort, r))
        self.clock.t += 1
        self.assertIsNotNone(self.reporter().max_age_page(self.cohort, r))
        self.assertEqual(len(self.pages), 2)

    # ── immediate ──────────────────────────────────────────────────────────────────────────────
    def test_immediate_pages_latch_per_record(self) -> None:
        rep = self.reporter()
        a = rec(1, phase="SPLIT-BRAIN")
        b = rec(2, wait=wait("HELD:team", eta=T0 + 3600))
        c = done(rec(3, escalated=True), "IMPOSSIBLE")
        self.assertEqual(len(rep.immediate_pages(self.cohort, a)), 1)
        held = rep.immediate_pages(self.cohort, b)
        self.assertEqual(len(held), 1)
        self.assertIn("until the reset at", held[0])
        self.assertEqual(len(rep.immediate_pages(self.cohort, c)), 2)
        for r in (a, b, c):
            self.assertEqual(self.reporter().immediate_pages(self.cohort, r), [])
        a2 = rec(1, phase="SPLIT-BRAIN")
        a2.record_id = T.make_record_id(
            "c1", a2.sid, 2
        )  # a new attempt is a new record
        self.assertEqual(len(rep.immediate_pages(self.cohort, a2)), 1)
        self.assertEqual(len(self.pages), 5)
        self.assertTrue(all(p.startswith("next3 7d: ") for p in self.pages))

    # ── SLO ────────────────────────────────────────────────────────────────────────────────────
    def test_slo_page(self) -> None:
        rep = self.reporter()
        recs = [
            done(rec(1)),
            rec(2, phase="EXITING", substate=None),
            rec(3, wait=wait("HOLD-SUBAGENTS")),
        ]
        self.clock.t = T0 + 599
        self.assertIsNone(rep.slo_page(self.cohort, recs))
        self.clock.t = T0 + 600
        text = rep.slo_page(self.cohort, recs)
        assert text is not None
        self.assertIn("00000002", text)
        self.assertNotIn("00000003", text)  # named hold within its max age is fine
        self.assertIsNone(rep.slo_page(self.cohort, recs))

    def test_slo_silent_when_all_within_bounds(self) -> None:
        recs = [done(rec(1)), rec(2, wait=wait("WAIT_RESET"))]
        self.clock.t = T0 + 700
        self.assertIsNone(self.reporter().slo_page(self.cohort, recs))

    # ── status, readout, residue ───────────────────────────────────────────────────────────────
    def test_write_cohort_keeps_cohort_loadable(self) -> None:
        r = rec(
            1,
            wait=wait("WAIT_SLOT", eta=T0 + 60),
            attempt=2,
            last_error=T.LastError(cls="TRANSIENT"),
        )
        R.write_cohort(self.paths, self.cohort, [r, done(rec(2))], T0 + 30)
        with open(os.path.join(self.paths.cohorts, "c1.json")) as fh:
            doc = json.load(fh)
        self.assertEqual(T.from_dict(T.Cohort, doc).acct, "next3")
        m = doc["status"]["members"][0]
        self.assertEqual(
            (m["substate"], m["age_s"], m["attempt"], m["last_error"], m["eta"]),
            ("DETECTED", 30.0, 2, "TRANSIENT", T0 + 60),
        )
        self.assertTrue(m["next_action"].startswith("wakes at "))
        self.assertEqual(doc["status"]["tally"]["done"], 1)

    def test_readout_line(self) -> None:
        self.assertEqual(R.readout_line(self.paths, T0), "")
        S.ensure_dirs(self.paths)
        S.save_record(self.paths, done(rec(9)))
        self.assertEqual(R.readout_line(self.paths, T0), "")
        S.save_record(self.paths, rec(1, phase="MOVED", substate=None))
        S.save_record(self.paths, rec(2, wait=wait("WAIT_SLOT")))
        S.save_record(self.paths, rec(3, "c2", wait=wait("HOLD-DRAFT")))
        S.save_record(self.paths, rec(4, "c2", escalated=True))
        self.assertEqual(
            R.readout_line(self.paths, T0),
            "lr-recon: 2 cohorts open · 1 moving · 1 waiting · 1 held · 1 escalated",
        )

    def test_readout_line_names_bg_held_panes_with_their_page_time(self) -> None:
        # Decision 2 (SETTLED): a ship-land job pages at 60 min, any other background job at 20.
        def hm(t: float) -> str:
            return time.strftime("%H:%M", time.localtime(t))

        ship = rec(1, wait=wait("HOLD-BGWORK", detail="ship-land in flight"))
        other = rec(2, wait=wait("HOLD-BGWORK", since=T0 + 60, detail="bats"))
        line = R.readout_line(self.paths, T0, [ship, other, done(rec(3))])
        self.assertEqual(
            line,
            "lr-recon: 1 cohort open · 0 moving · 0 waiting · 2 held · 0 escalated"
            " · bg-held: %s pages %s (20 min)"
            " · bg-held: %s pages %s (60 min, ship-land)"
            % (R.who(other), hm(T0 + 60 + 1200), R.who(ship), hm(T0 + 3600)),
        )
        self.assertIn("pane 12:2", line)  # the operator finds the pane by its label

    def test_readout_line_caps_bg_held_at_three(self) -> None:
        recs = [rec(n, wait=wait("HOLD-BGWORK", since=T0 + n)) for n in range(1, 6)]
        line = R.readout_line(self.paths, T0, recs)
        self.assertEqual(line.count("bg-held:"), 3)
        self.assertTrue(line.endswith(" · +2 more"), line)
        self.assertNotIn("pane 12:4", line)  # the latest deadlines are the ones counted

    def test_residue_needs(self) -> None:
        draft = rec(1, wait=wait("HOLD-DRAFT"))
        self.assertIsNone(R.residue_needs(draft, T0 + 899))
        line = R.residue_needs(draft, T0 + 900)
        assert line is not None
        self.assertIn(
            "limit-recover on next3 7d: session 00000001 (pane 12:1, repo1)", line
        )
        self.assertIn("send or clear the draft", line)
        ship = rec(2, wait=wait("HOLD-BGWORK", detail="ship-land"))
        self.assertIsNone(R.residue_needs(ship, T0 + 1200))
        self.assertIsNotNone(R.residue_needs(ship, T0 + 3600))
        self.assertIsNone(R.residue_needs(rec(3, wait=wait("HOLD-MENU")), T0 + 9999))



class DodLine(unittest.TestCase):
    """R.dod_line: the two shapes lr-recon-rig derives from its fault matrix (W5)."""

    def setUp(self):
        import tempfile

        self.root = tempfile.mkdtemp()
        self.paths = T.Paths(lr_root=self.root, root=self.root)

    def _rec(self, i, via="ENGAGED", outcome="CLOSED", sub=None, seen=()):
        r = T.Record(sid="%08d-0000-0000-0000-000000000000" % i, record_id="r%d" % i)
        r.timeline.detected = 100.0
        r.close = {"via": via, "at": 130.0 + i, "same_window": True, "same_uuid": True, "seen": list(seen)}
        if outcome:
            r.terminal = T.Terminal(outcome=outcome)
        if sub:
            r.substate, r.wait = sub, T.Wait(reason=sub)
            r.close.pop("via")
        return r

    def test_short_shape(self):
        recs = [self._rec(i) for i in range(5)]
        self.assertEqual(
            R.dod_line(self.paths, recs),
            "ENGAGED 5/5 · same-window 5/5 · same-uuid 5/5 · double-typer 0 · "
            "split-brain 0 · lost-records 0 · p95 detect→engaged <= 120s",
        )

    def test_slow_p95_is_stated_not_hidden(self):
        r = self._rec(1)
        r.close["at"] = 400.0
        self.assertIn("p95 detect→engaged = 300s (> 120s)", R.dod_line(self.paths, [r]))

    def test_tally_shape_with_a_recovered_bgwork(self):
        recs = [self._rec(1), self._rec(2, via="MOVED"), self._rec(3, seen=["HOLD-BGWORK"])]
        recs += [self._rec(4, outcome=None, sub="HOLD-DRAFT"), self._rec(5, outcome=None, sub="HOLD-BGWORK")]
        recs += [self._rec(6, via=None, outcome="REPLACED-NEW-WINDOW"), self._rec(7, via=None, outcome="NOT_NEEDED")]
        self.assertEqual(
            R.dod_line(self.paths, recs),
            "CLOSED 3/7 (ENGAGED 2, MOVED 1) · HOLD named 2/7 (draft 1, bgwork 1 — the 2nd bgwork "
            "recovers after its job ends) · REPLACED-NEW-WINDOW 1 · NOT_NEEDED 1 · double-typer 0 · "
            "split-brain 0 · lost-records 0 · unowned-non-terminal 0",
        )

    def test_double_typer_counts_distinct_pids_per_sid_attempt(self):
        r = self._rec(1)
        with open(self.paths.launch_log, "w") as fh:
            fh.write("1\t%s\tlr-fire-resume\ttaken\tpid=10\tattempt=1\n" % r.sid)
            fh.write("2\t%s\tlr-fire-resume\ttaken\tpid=10\tattempt=1\n" % r.sid)  # a re-take: same pid
            fh.write("3\t%s\tlr-fire-resume\ttaken\tpid=11\tattempt=2\n" % r.sid)  # the next attempt
        self.assertIn("double-typer 0", R.dod_line(self.paths, [r]))
        with open(self.paths.launch_log, "a") as fh:
            fh.write("4\t%s\tcc-resume-debt\ttaken\tpid=12\tattempt=2\n" % r.sid)
        self.assertIn("double-typer 1", R.dod_line(self.paths, [r]))

    def test_a_second_move_spawn_in_one_attempt_is_a_double_typer(self):
        r = self._rec(1)
        with open(self.paths.launch_log, "w") as fh:
            fh.write("1\t%s\trecon-A\tspawn\tpid=20\tattempt=1\n" % r.sid)
            fh.write("2\t%s\tlr-fire-resume\ttaken\tpid=21\tattempt=1\n" % r.sid)
            fh.write("3\t%s\trecon-C-retry\tspawn\tpid=22\tattempt=1\n" % r.sid)
        self.assertIn("double-typer 0", R.dod_line(self.paths, [r]))  # one move, one launch
        with open(self.paths.launch_log, "a") as fh:
            fh.write("4\t%s\trecon-A\tspawn\tpid=23\tattempt=1\n" % r.sid)  # the re-dispatch
        self.assertIn("double-typer 1", R.dod_line(self.paths, [r]))


if __name__ == "__main__":
    unittest.main()
