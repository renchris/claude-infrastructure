"""W8 of docs/plans/LR_SUSTAINED_LOAD_IMPL.md: the right clock per decision, retry instead of escalate,
no actuator load term, every hold reason mapped (B7 + C2-lite + G1/G5 closure).

Designs: docs/research/lr-sustained-load-2026-10-20/impl/B7-now-audit.md (§1 rules R1-R7, §8 controls,
both reviews' required changes) and impl/C2-socket-prompt.md (efficacy review E2/E5, C2-lite).

Every class here is a control that is RED at the W8 parent unless its docstring says CONTROL or
GUARD. Fixture helpers are borrowed from the suites they come from (test_unprompted_c, test_rollback,
test_holder_gone) as plain functions, never by subclassing, so no inherited test runs twice.
tests/lr-recon-now-audit.bats runs this module and one mutant per new rule.
"""

import functools
import json
import os
import re
import shutil
import tempfile
import time
import unittest
from typing import Any, List, Optional
from unittest import mock

from lr_recon import __main__ as M
from lr_recon import act
from lr_recon import admit as A
from lr_recon import classify as C
from lr_recon import plan, report, settle
from lr_recon import types as T
from lr_recon.tests import test_holder_gone as HG
from lr_recon.tests import test_main as TM
from lr_recon.tests import test_rollback as TR
from lr_recon.tests import test_unprompted_c as TU
from lr_recon.tests.longpass import LongPass
from lr_recon.tests.test_admit import FakeRunner, Wall

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), *([".."] * 4)))
LSTART_FMT = "%a %b %d %H:%M:%S %Y"


def _lstart(epoch: float) -> str:
    return time.strftime(LSTART_FMT, time.gmtime(epoch))


# The kill switches by file name, and the two readers through getattr, so this module also runs
# against the W8 parent and each control fails there on its own assertion, not on a missing name
# (SwitchNames pins these to production's constants).
PASS_CLOCK, C_RC5_OFF = "pass-clock", "c-rc5-transient.off"
HOLD_MAP_OFF, LOAD_TERM_ON = "hold-map.off", "actuator-load-term.on"
C_ACTUATORS = ("C", "C-retry")


def _switches(root: str) -> None:
    getattr(C, "read_switches", lambda _r: None)(root)


def _pass_clock(paths: T.Paths) -> str:
    return getattr(M, "read_pass_clock", lambda _p: "wall")(paths)


class _Sandbox(unittest.TestCase):
    """HOME, LR_STATE_DIR and the recon root under a fresh temp dir; the probe and the token mint
    never shell out; classify's switches are reset after every test."""

    def setUp(self) -> None:
        self.tmp = tempfile.mkdtemp(prefix="lr-w8.")
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
        self.addCleanup(_switches, os.path.join(self.tmp, "no-such-root"))
        self.now = time.time()

    def _touch(self, name: str, text: str = "") -> None:
        with open(os.path.join(self.paths.root, name), "w", encoding="utf-8") as fh:
            fh.write(text)

    def _events(self, ev: Optional[str] = None) -> List[dict]:
        if not os.path.exists(self.paths.events):
            return []
        with open(self.paths.events, encoding="utf-8") as fh:
            rows = [json.loads(x) for x in fh if x.strip()]
        return [e for e in rows if ev is None or e.get("ev") == ev]


# ── C: the relaunched session's owed continue ─────────────────────────────────────────────────────


class _CFixture(_Sandbox):
    """test_unprompted_c's e80b61f4 shape: RELAUNCHED/UNPROMPTED on next, relay alive."""

    _rec = TU.UnpromptedCTests._rec
    _target_tx = TU.UnpromptedCTests._target_tx
    _bundle = TU.UnpromptedCTests._bundle
    _snap = TU.UnpromptedCTests._snap
    _spawned = TU.UnpromptedCTests._spawned

    def setUp(self) -> None:
        super().setUp()
        self.cfg = {a: os.path.join(self.tmp, "cfg-" + a) for a in ("next3", "next")}
        for d in self.cfg.values():
            os.makedirs(os.path.join(d, "projects"), exist_ok=True)
        self.cwd = os.path.join(self.tmp, "wt")
        os.makedirs(self.cwd)

    def _pass(
        self,
        rec: T.Record,
        census: float,
        decide: Optional[float] = None,
        between: Any = None,
        may: Any = None,
        claim: Any = None,
    ) -> mock.Mock:
        """One pass: the census and _derive at ``census``; ``between`` runs after _derive (a record
        landing mid-pass); _dispatch's wall reads ``decide`` (a long pass reaches the record late)."""
        ctx = M.Ctx(self.paths, None, self.home)
        ctx.pass_clock = _pass_clock(self.paths)
        ctx.records = {TU.SID: rec}
        snap = self._snap(census)
        with mock.patch("time.time", lambda: census):
            M._derive(ctx, snap, census)
        if between is not None:
            between()
        wall = census if decide is None else decide
        with (
            mock.patch("time.time", lambda: wall),
            mock.patch.object(
                M.act, "may_actuate", may or mock.Mock(return_value=(True, "ok"))
            ),
            mock.patch.object(
                M.act, "hold_claim", claim or mock.Mock(return_value=(True, "taken"))
            ),
            mock.patch.object(M.act, "spawn", return_value=4242) as sp,
            mock.patch.object(M.store, "append_launch"),
        ):
            M._dispatch(ctx, snap, "act", census)
        return sp

    TYPING = [("relaunch-typed", "expect"), ("submit-token-armed", "inject")]
    DONE = TYPING + [("UNVERIFIED:submit", "submit")]

    def _token_lands(self, rec: T.Record, token: Optional[str] = None) -> Any:
        return lambda: self._target_tx(
            rec, [TU._user("continue " + (token or rec.submit_token))]
        )


class CGraceIsAnEvidenceWait(_CFixture):
    """B7 R4 + both reviews' finding 1: C's 60 s grace runs from the FIRST census that did not see
    the typer, on the census instant, however late the dispatch reaches the record."""

    def test_C_waits_60s_after_the_first_census_that_did_not_see_the_typer(
        self,
    ) -> None:
        """C4 at census+61: red at the parent (last-seen anchor: 300 s of 'quiet') and for the
        t_dec variant (61 s of wall), which types on census-T evidence."""
        rec = self._rec()
        self._bundle(rec, self.TYPING)
        t = self.now
        self.assertEqual(self._spawned(self._pass(rec, t)), [])  # the typer is live
        self._bundle(rec, self.DONE)
        self.assertEqual(self._spawned(self._pass(rec, t + 300, decide=t + 361)), [])

    def test_C_goes_at_the_first_census_60s_after_and_never_earlier(self) -> None:
        """E1': no C in the pass whose census first missed the typer (decision +61 s), none at a
        census 59 s after it however late the decision, and C at the first census 60 s after."""
        rec = self._rec()
        self._bundle(rec, self.TYPING)
        t = self.now
        self._pass(rec, t)
        self._bundle(rec, self.DONE)
        self.assertEqual(self._spawned(self._pass(rec, t + 300, decide=t + 361)), [])
        self.assertEqual(self._spawned(self._pass(rec, t + 359, decide=t + 500)), [])
        self.assertEqual(self._spawned(self._pass(rec, t + 360)), ["C"])

    def test_b7_review_hazard(self) -> None:
        """The launcher's record lands after _derive and before a dispatch at census+61: nothing
        re-reads the transcript before C types, so a t_dec grace typed the second prompt."""
        rec = self._rec()
        self._bundle(rec, self.TYPING)
        t = self.now
        self._pass(rec, t)
        self._bundle(rec, self.DONE)
        sp = self._pass(rec, t + 300, decide=t + 361, between=self._token_lands(rec))
        self.assertEqual(self._spawned(sp), [])

    def test_the_kill_switch_restores_the_last_seen_grace(self) -> None:
        """E4: recon/pass-clock = pass sends C4's C in pass 2, as the parent did."""
        self._touch(PASS_CLOCK, "pass\n")
        rec = self._rec()
        self._bundle(rec, self.TYPING)
        t = self.now
        self._pass(rec, t)
        self._bundle(rec, self.DONE)
        self.assertEqual(self._spawned(self._pass(rec, t + 300, decide=t + 301)), ["C"])


class SubmittedIsReadAfterThisCensus(_CFixture):
    """B7 correctness finding 2 (R5): evidence.build read `submitted` from the previous pass."""

    def test_token_visible_at_census_plus_70_sends_no_C(self) -> None:
        """The record landed 11 s after the first census that missed the typer; the next census
        (+70 s, the grace elapsed) sees it. Red with the grace fix alone: row 7 still said C."""
        rec = self._rec()
        self._bundle(rec, self.TYPING)
        t = self.now
        self._pass(rec, t)
        self._bundle(rec, self.DONE)
        self.assertEqual(self._spawned(self._pass(rec, t + 300)), [])
        self._token_lands(rec)()
        self.assertEqual(self._spawned(self._pass(rec, t + 370)), [])
        self.assertIsNotNone(rec.timeline.submitted)

    def test_control_no_token_still_gets_its_C(self) -> None:
        """CONTROL: the same passes with no record landing do send C at +370 s."""
        rec = self._rec()
        self._bundle(rec, self.TYPING)
        t = self.now
        self._pass(rec, t)
        self._bundle(rec, self.DONE)
        self._pass(rec, t + 300)
        self.assertEqual(self._spawned(self._pass(rec, t + 370)), ["C"])


class DispatchKeepsTheCensusInstant(_CFixture):
    """E2/E3 (designed in B7 §8.3, run here): the two gates that must stay on ``now`` get it."""

    def _ready(self) -> T.Record:
        rec = self._rec()
        self._bundle(rec, [("relaunch-typed", "expect"), ("READY-NOT-SEEN", "inject")])
        self._pass(rec, self.now)
        return rec

    def test_dispatch_hands_may_actuate_the_census_instant(self) -> None:
        """GUARD (E2): t_dec there re-fires R on a census taken before its R_PROOF_S window."""
        rec = self._ready()
        may = mock.Mock(return_value=(True, "ok"))
        census = self.now + 20
        self._pass(rec, census, decide=census + 90, may=may)
        self.assertTrue(may.called)
        self.assertEqual(may.call_args[0][5], census)

    def test_claims_keep_the_census_instant(self) -> None:
        """GUARD (E3): a later instant would shrink the claim's orphan grace."""
        rec = self._ready()
        claim = mock.Mock(return_value=(True, "taken"))
        census = self.now + 20
        self._pass(rec, census, decide=census + 90, claim=claim)
        self.assertTrue(claim.called)
        self.assertEqual(claim.call_args[0][3], census)


RC5 = (
    "cc-tui: submitted, but no user record carrying the payload appeared in "
    "/x/.claude-next/projects/-Users-c-Development-headless-probe/e80b61f4.jsonl within 3 poll(s) "
    "x 1s — CANNOT TELL (this is never 'failed': the session may simply be slow).\n"
)
# the same line with a path no free-text class reads (RC5's `-headless-` slug is IMPOSSIBLE there)
RC5_PLAIN = RC5.replace("headless-probe", "lrsl-w8")
RPC_FAILED = "cc-tui: the send-text RPC failed for window 55\n"
NOT_LISTED = (
    "cc-tui: refusing to type into window 55 — it is not in kitty's window list. kitty's "
    "send-text exits 0 for a nonexistent id, so delivering here would report success while the "
    "text went nowhere.\n"
)


class CRpcUncertaintyIsTransient(_CFixture):
    """C2-lite (C2 efficacy E2): cc-tui's could-not-tell lines retry at <= 300 s, never escalate."""

    def _exit(
        self, rec: T.Record, rc: int, text: str, at: float, who: str = "C"
    ) -> str:
        pr = T.ProcRole(role="actuator", pid=7, lstart="x", argv_hash=who)
        return settle.settle_exit(rec, pr, rc, text, at)

    def test_a_C_rc5_line_is_transient_and_never_reaches_impossible(self) -> None:
        for who in C_ACTUATORS:
            for rc, text in ((5, RC5), (1, RPC_FAILED), (1, NOT_LISTED)):
                rec = self._rec()
                for i in range(8):  # past PAGE_AT, the same fingerprint every time
                    d = self._exit(rec, rc, text, self.now + 400 * i, who)
                    self.assertFalse(rec.escalated, (who, text, i, d))
                self.assertEqual(rec.last_error.cls, "TRANSIENT", (who, text))
                self.assertIsNone(rec.terminal)
                self.assertLessEqual(
                    rec.next_eligible_at - (self.now + 400 * 7), C.BACKOFF_CAP_S
                )

    def test_only_the_last_cc_tui_line_counts(self) -> None:
        """GUARD: the actlog is appended per (attempt, actuator); an earlier run's rc-5 line does
        not classify a later run that failed on a mangled read-back (rc 4)."""
        rec = self._rec()
        mangled = RC5_PLAIN + "cc-tui: MANGLED read-back; the CR was not sent\n"
        self._exit(rec, 4, mangled, self.now)
        self._exit(rec, 4, mangled, self.now + 60)
        self.assertTrue(rec.escalated)

    def test_the_kill_switch_restores_the_deterministic_reading(self) -> None:
        self._touch(C_RC5_OFF)
        _switches(self.paths.root)
        rec = self._rec()
        self._exit(rec, 5, RC5_PLAIN, self.now)
        self._exit(rec, 5, RC5_PLAIN, self.now + 60)
        self.assertTrue(rec.escalated)
        rec = (
            self._rec()
        )  # and the path-bearing line falls back to the free-text IMPOSSIBLE (R6)
        self._exit(rec, 5, RC5, self.now)
        self.assertEqual(rec.terminal.outcome, "IMPOSSIBLE")

    def test_rc5_with_the_token_landing_at_census_plus_70_sends_no_second_C(
        self,
    ) -> None:
        rec = self._rec()
        self._bundle(rec, [("relaunch-typed", "expect"), ("READY-NOT-SEEN", "inject")])
        rec.submit_token = "lrr-c0ffee000005"  # C's own token, minted at its spawn
        self._exit(rec, 5, RC5, self.now)
        self.assertEqual(rec.close.get("c_rc5_token"), "lrr-c0ffee000005")
        self._token_lands(rec)()
        self.assertEqual(self._spawned(self._pass(rec, self.now + 70)), [])

    def test_rc5_with_the_token_landing_during_the_backoff_skips_the_retry(
        self,
    ) -> None:
        """The double-prompt guard: kitty ran the timed-out send late, after this census."""
        rec = self._rec()
        self._bundle(rec, [("relaunch-typed", "expect"), ("READY-NOT-SEEN", "inject")])
        rec.submit_token = "lrr-c0ffee000005"
        self._exit(rec, 5, RC5, self.now)
        sp = self._pass(rec, self.now + 15, between=self._token_lands(rec))
        self.assertEqual(self._spawned(sp), [])
        [ev] = self._events("c-rc5-landed")
        self.assertIn("C skipped", ev["detail"])
        self.assertIsNotNone(rec.timeline.submitted)
        self.assertNotIn("c_rc5_token", rec.close)

    def test_control_rc5_with_no_token_retries(self) -> None:
        """CONTROL: the guard holds only a C whose earlier prompt is visibly there. (Red at the
        parent for another reason: its DETERMINISTIC reading of rc 5 sent no retry at all.)"""
        rec = self._rec()
        self._bundle(rec, [("relaunch-typed", "expect"), ("READY-NOT-SEEN", "inject")])
        rec.submit_token = "lrr-c0ffee000005"
        self._exit(rec, 5, RC5, self.now)
        self.assertEqual(self._spawned(self._pass(rec, self.now + 15)), ["C"])


class UnpromptedPages(_CFixture):
    """C2 E5: a durable unprompted_since and a 1800 s max age (MAX_AGE_S had no UNPROMPTED key)."""

    def test_the_unprompted_page_at_1800s(self) -> None:
        rec = self._rec()
        rec.close["unprompted_since"] = self.now
        rec.updated_at = self.now + 1799  # save_records' restamp is never the anchor
        self.assertFalse(report.max_age_due(rec, self.now + 1799))
        self.assertTrue(report.max_age_due(rec, self.now + 1800))
        self.assertIn("not yet delivered", report.say(rec))

    def test_derive_stamps_it_once_and_clears_it_on_the_way_out(self) -> None:
        rec = self._rec()
        self._bundle(rec, self.TYPING)
        self._pass(rec, self.now)
        self.assertEqual(rec.close.get("unprompted_since"), self.now)
        self._pass(rec, self.now + 30)
        self.assertEqual(
            rec.close.get("unprompted_since"), self.now
        )  # kept, not restamped
        self._target_tx(rec, [TU._user("keep going"), TU._assistant()])
        self._pass(rec, self.now + 60)
        self.assertNotEqual(rec.substate, "UNPROMPTED")
        self.assertNotIn("unprompted_since", rec.close)


class KittyDegradedEvent(_Sandbox):
    """C2 E5 T4: a kitty: degradation while a record owes its continue is an event, once."""

    def _snap(self, degraded: List[str]) -> T.Snapshot:
        return T.Snapshot(wall=self.now, uptime_raw=0.0, degraded=degraded)

    def test_one_event_per_outage_while_a_continue_is_owed(self) -> None:
        ctx = M.Ctx(self.paths, None, self.home)
        rec = T.Record(sid="e80b61f4-0000-0000-0000-000000000001", record_id="r1")
        rec.phase, rec.substate = (
            "PRE-MOVE",
            "UNPROMPTED",
        )  # a deaf kitty leaves it PRE-MOVE (E1)
        ctx.records = {rec.sid: rec}
        deaf = ["kitty:/tmp/kitty-853"]
        M._kitty_degraded(ctx, self._snap(deaf))
        M._kitty_degraded(ctx, self._snap(deaf))
        [ev] = self._events("kitty-degraded")
        self.assertIn("kitty:/tmp/kitty-853", ev["detail"])
        self.assertIn("e80b61f4", ev["detail"])
        M._kitty_degraded(ctx, self._snap([]))
        M._kitty_degraded(ctx, self._snap(deaf))
        self.assertEqual(len(self._events("kitty-degraded")), 2)

    def test_control_no_owed_continue_no_event(self) -> None:
        ctx = M.Ctx(self.paths, None, self.home)
        rec = T.Record(sid="e80b61f4-0000-0000-0000-000000000001", record_id="r1")
        rec.phase, rec.substate = "RELAUNCHED", "SUBMITTED"
        ctx.records = {rec.sid: rec}
        M._kitty_degraded(ctx, self._snap(["kitty:/tmp/kitty-853"]))
        self.assertEqual(self._events("kitty-degraded"), [])


# ── busy: a lane of THIS move ─────────────────────────────────────────────────────────────────────

RELAY = "/bin/bash /x/lr-fire-resume.sh %s /p %s --branch b --model m --prompt x"


class RollbackUnderARelay(_Sandbox):
    """Both reviews' finding 3/2: a rolled-back move whose SOURCE pane is rooted by an earlier
    lr-fire-resume relay (alive as long as the session) was busy in every census: no re-drive, no
    page, zero events. Busy now counts only a relay of this move."""

    _rec = TR.RolledBack._rec
    _log = TR.RolledBack._log

    def _run(
        self,
        gap: float,
        relay_lstart: str,
        relay_until: float = 1e18,
        total: float = 1800.0,
        busy_age: Optional[float] = None,
    ) -> Optional[float]:
        ctx = M.Ctx(self.paths, None, self.home)
        rec = self._rec()
        # the previous census saw the relay, or (busy_age) the db755a94 shape's stale stamp
        rec.close["busy_at"] = self.now - (gap if busy_age is None else busy_age)
        self._log(rec)
        ctx.records = {TR.SID: rec}
        self.rec, k = rec, 0
        before = len(self._events("rolled-back"))
        while k * gap <= total:
            t = self.now + k * gap
            snap = TM._snap(t, self.tmp)
            if k * gap < relay_until:
                snap.procs[24868] = T.ProcRow(
                    24868, 1, "S", relay_lstart, RELAY % ("next3", TR.SID)
                )
            with (
                mock.patch("time.time", lambda: t),
                mock.patch("lr_recon.observe.observe", return_value=snap),
                mock.patch.object(plan, "place", return_value=({}, 0)),
                mock.patch.object(plan, "assign_many", return_value=0),
                mock.patch.object(M.act, "spawn"),
            ):
                M.run_pass(ctx)
            if len(self._events("rolled-back")) > before:
                return k * gap
            k += 1
        return None

    def test_relay_strand_at_120s_and_10s_pass_gaps(self) -> None:
        """The source's own relay (started before the move) never holds the retry: rolled back
        within 60 s + 2 passes at both cadences, and the record is never silent."""
        for gap in (120.0, 10.0):
            fired = self._run(gap, TM.L)
            self.assertIsNotNone(fired, "gap %s: never rolled back" % gap)
            self.assertLessEqual(fired, 60.0 + 2 * gap, gap)
            self.assertTrue(self._events(), gap)
            self.assertEqual(self.rec.attempt, 2)

    def test_a_launcher_started_after_the_move_holds_the_rollback_retry(self) -> None:
        """C5, rebuilt with a launcher that started after the move: held while it lives (no event,
        attempt 1), re-driven within 60 s + 2 passes of its going. The stamp before it is 30 min
        old: the parent read it before stamping this census's sighting and retried at once."""
        after = _lstart(self.now - 60)  # planned at now - 3300 (test_rollback's shape)
        fired = self._run(10.0, after, relay_until=100.0, busy_age=1800.0)
        self.assertIsNotNone(fired)
        self.assertGreaterEqual(fired, 100.0 + 60.0 - 10.0)
        self.assertLessEqual(fired, 100.0 + 60.0 + 20.0)

    def test_an_open_launcher_of_this_attempt_counts_whatever_its_start(self) -> None:
        """GUARD (green at the parent, where every relay counted): the other half of the predicate.
        This attempt's launcher started (relaunch-typed) and has not settled, so its relay is a lane
        of this move even though the move began first."""
        d = os.path.join(
            settle.bundles_dir(self.home, TR.SID), "bundle-20261020T000000Z"
        )
        os.makedirs(d)
        with open(os.path.join(d, "events.jsonl"), "w", encoding="utf-8") as fh:
            fh.write(json.dumps({"state": "relaunch-typed", "attempt": "1"}) + "\n")
        self.assertIsNone(self._run(10.0, TM.L, total=200.0))
        self.assertEqual(self.rec.attempt, 1)


class HolderGoneSeesThisCensus(_Sandbox):
    """C6: holder_gone read the previous pass's busy stamp, so a launcher this census sees booting
    a never-began record's sid was invisible, and the record closed dead-before-claim."""

    _rec = HG.HolderGone._rec

    def _derive(self, procs: dict) -> T.Record:
        ctx = M.Ctx(self.paths, None, self.home)
        rec = self._rec()
        ctx.records = {rec.sid: rec}
        snap = T.Snapshot(wall=self.now, uptime_raw=0.0, procs=procs, sessions={})
        M._derive(ctx, snap, self.now)
        return rec

    def test_a_launcher_booting_the_sid_in_this_census_keeps_the_record_open(
        self,
    ) -> None:
        relay = T.ProcRow(
            31337, 1, "S", _lstart(self.now - 5), RELAY % ("next", HG.SID)
        )
        self.assertTrue(self._derive({31337: relay}).open)

    def test_control_no_launcher_closes_it(self) -> None:
        rec = self._derive({})
        self.assertEqual(rec.terminal.outcome, "NOT_NEEDED")


# ── IN-FLIGHT: paged, never convicted by our own timeout ──────────────────────────────────────────


class InFlightAnchor(_Sandbox):
    SID = "abcdef01-0000-0000-0000-000000000001"
    WATCHER = "/bin/bash /x/handoff-fire.sh --recycle %s __recycle --await 1200" % SID

    def _loop(self, rec: T.Record, until: float, procs: Any = None) -> Optional[float]:
        """5 s passes of _derive + _invariant + save_records; the first RECON-DEFECT's offset."""
        ctx = M.Ctx(self.paths, None, self.home)
        ctx.records = {rec.sid: rec}
        out = {
            "result": T.PhaseResult(phase="PRE-MOVE", action="wait"),
            "evidence": T.Evidence(),
        }
        paged = None
        with mock.patch.object(M.evidence, "derive", return_value=out):
            for k in range(1, int(until / 5) + 1):
                t = self.now + 5.0 * k
                snap = T.Snapshot(
                    wall=t, uptime_raw=0.0, panes={}, sessions={}, procs=procs or {}
                )
                M._derive(ctx, snap, t)
                if M._invariant(ctx, snap, t) and paged is None:
                    paged = t - self.now
                M.store.save_records(self.paths, [rec], t)  # updated_at = t, every pass
        return paged

    def _rec(self) -> T.Record:
        rec = T.Record(sid=self.SID, record_id="r1")
        rec.phase, rec.substate = "PRE-MOVE", "IN-FLIGHT"
        rec.updated_at = self.now
        return rec

    def test_in_flight_without_a_confirm_stamp_is_paged(self) -> None:
        """C7, as limited by the efficacy review: an unconfirmed IN-FLIGHT record sat silent for good
        (its only anchor was updated_at); now _invariant pages it by IN_FLIGHT_MAX_S + one pass, and
        no DETERMINISTIC ladder runs."""
        rec = self._rec()
        paged = self._loop(rec, 700.0)
        self.assertIsNotNone(paged, "IN-FLIGHT with no confirm stamp was never paged")
        self.assertLessEqual(paged, M.IN_FLIGHT_MAX_S + 10)
        self.assertIsNone(rec.last_error)
        self.assertEqual(self._events("in-flight-expired"), [])

    def test_a_watcher_live_for_1195s_is_never_deterministic(self) -> None:
        """The watcher's --await runs to 1,200 s; a 600 s verdict convicted it with our own timeout,
        then escalated and blocked the B/R rescue. Confirmed, so the parent fired at +600 s."""
        rec = self._rec()
        rec.timeline.confirmed = self.now
        watcher = T.ProcRow(4711, 1, "S", _lstart(self.now), self.WATCHER)
        paged = self._loop(rec, 1195.0, {4711: watcher})
        self.assertIsNone(rec.last_error)
        self.assertFalse(rec.escalated)
        self.assertEqual(self._events("in-flight-expired"), [])
        self.assertIsNone(paged)


# ── the pacer and our own action stamps on wall time ──────────────────────────────────────────────


class PacerOnWall(unittest.TestCase):
    def _adm(self, wall: Wall) -> A.Admission:
        adm = A.Admission(runner=FakeRunner(), repo="/repo", env={}, wall=wall)
        adm.enter_active(5, 3, 6, now=0.0)
        return adm

    def test_the_3_per_account_cap_frees_inside_one_long_pass(self) -> None:
        """C1: 3 admissions at wall 100, the same pass ``now``, then 21 s of wall: the 4th goes."""
        wall = Wall(100.0)
        adm = self._adm(wall)
        for i in range(3):
            self.assertTrue(adm.decide("s%d" % i, "acct1", 100.0, 0, 0, 1, 1, 10)[0])
        self.assertEqual(
            adm.decide("s3", "acct1", 100.0, 0, 0, 1, 1, 10), (False, "pacer:acct1")
        )
        wall.t = 100.0 + A.PACER_RELEASE_S + 1
        self.assertEqual(
            adm.decide("s3", "acct1", 100.0, 0, 0, 1, 1, 10), (True, "admit")
        )

    def test_the_slot_is_stamped_after_the_probe(self) -> None:
        """Efficacy 6: a 30 s probe stamped its slot 30 s early, so '3 per 20 s' was not literal."""
        wall = Wall(100.0)
        adm = self._adm(wall)

        def slow_probe(_r: Any) -> Any:
            wall.t += 30.0
            return True, "admit"

        adm.probe = slow_probe  # type: ignore[assignment]
        self.assertTrue(adm.decide("s0", "acct1", 100.0, 0, 0, 1, 1, 10)[0])
        self.assertEqual(adm.pacer["acct1"]["s0"], 130.0)
        self.assertEqual(adm.last_admit_at, 130.0)

    def test_the_kill_switch_keeps_the_pass_scoped_pacer(self) -> None:
        wall = Wall(100.0)
        adm = self._adm(wall)
        adm.pacer_on_wall = False
        for i in range(3):
            adm.decide("s%d" % i, "acct1", 100.0, 0, 0, 1, 1, 10)
        wall.t = 130.0
        self.assertEqual(
            adm.decide("s3", "acct1", 100.0, 0, 0, 1, 1, 10), (False, "pacer:acct1")
        )


class LongPassStamps(_Sandbox):
    """C2 and C3: one pass that runs for minutes stamps each spawn at its own wall time."""

    def _fake_spawn(self, clock: LongPass) -> Any:
        class P:
            pid = 4242

        real = functools.partial(
            M.act.spawn, popen=lambda *a, **k: P(), lstart_of=lambda pid: TM.L
        )

        def spy(*a: Any, **k: Any) -> int:
            clock.mark()
            return real(*a, **k)

        return spy

    def test_a_long_dispatch_stamps_spawns_at_their_own_time(self) -> None:
        """C2: 4 PLANNED records onto one account, a probe at its 30 s bound each: all 4 go (the
        parent's pacer refused the 4th inside the pass), each spawn row at its own wall."""
        open(self.paths.recon_on, "w").close()
        clock = LongPass(1_800_000_000.0)

        def slow_probe(_self: Any, _r: Any) -> Any:
            clock.advance(30.0)
            return True, "admit"

        with mock.patch("time.time", clock):
            ctx = M.Ctx(self.paths, None, self.home)
            now = clock()
            for i in range(4):
                sid = "c%07d-0000-0000-0000-000000000000" % i
                ctx.records[sid] = T.Record(
                    sid=sid,
                    record_id="recon:c:%s:1" % sid[:8],
                    kind="limited",
                    source_acct="next3",
                    source_cfg="/c3",
                    scope="7d",
                    cohort_id="c",
                    target_acct="next",
                    target_cfg="/t",
                    substate="PLANNED",
                )
            with (
                mock.patch.object(A.Admission, "probe", slow_probe),
                mock.patch.object(M.act, "spawn", self._fake_spawn(clock)),
                mock.patch.object(M.act, "wrap", lambda rec, nonce, argv: ["true"]),
                mock.patch.object(M, "_command", lambda ctx, rec, which: ["true"]),
                mock.patch.object(M.act, "hold_claim", return_value=(True, "taken")),
            ):
                n = M._dispatch(ctx, T.Snapshot(wall=now, uptime_raw=0.0), "act", now)
        spawns = self._events("spawn")
        self.assertEqual(n, 4, self._events("admit-refused"))
        self.assertEqual(len(spawns), 4)
        for e, w in zip(spawns, clock.marks):
            self.assertGreaterEqual(e["t"], w)
        self.assertGreater(clock.marks[-1], now)

    def test_a_whole_long_pass_stamps_its_spawn_at_the_spawn(self) -> None:
        """C3, the test that runs a long pass: run_pass in act mode on a cc-lr request, the placer
        at its 120 s bound and the probe at its 30 s bound."""
        open(self.paths.recon_on, "w").close()
        with open(self.paths.mode_file, "w") as fh:
            fh.write("act\n")
        sid = TR.SID
        os.makedirs(self.paths.requests, exist_ok=True)
        with open(os.path.join(self.paths.requests, sid + ".cc-lr.json"), "w") as fh:
            json.dump({"sid": sid}, fh)
        clock = LongPass(1_800_000_000.0)
        placed = {sid: T.Placement(acct="next4", weight=1)}

        def slow_place(*a: Any, **k: Any) -> Any:
            clock.advance(120.0)
            return placed, 0

        def slow_probe(_self: Any, _r: Any) -> Any:
            clock.advance(30.0)
            return True, "admit"

        with mock.patch("time.time", clock):
            ctx = M.Ctx(self.paths, None, self.home)
            with (
                mock.patch(
                    "lr_recon.observe.observe", return_value=TM._snap(clock(), self.tmp)
                ),
                mock.patch.object(plan, "place", slow_place),
                mock.patch.object(plan, "assign_many", return_value=0),
                mock.patch.object(A.Admission, "probe", slow_probe),
                mock.patch.object(M.act, "spawn", self._fake_spawn(clock)),
                mock.patch.object(M, "_command", lambda c, r, w: ["true"]),
                mock.patch.object(M.act, "hold_claim", return_value=(True, "taken")),
            ):
                summary = M.run_pass(ctx)
        self.assertEqual(summary["actuations"], 1, summary)
        [sp] = self._events("spawn")
        self.assertGreaterEqual(clock.marks[0] - 1_800_000_000.0, 150.0)  # it WAS long
        self.assertGreaterEqual(sp["t"], clock.marks[0])

    def test_pass_clock_reader(self) -> None:
        self.assertEqual(M.read_pass_clock(self.paths), "wall")
        self._touch(PASS_CLOCK, "pass\n")
        self.assertEqual(M.read_pass_clock(self.paths), "pass")
        ctx = M.Ctx(self.paths, None, self.home)
        ctx.pass_clock = "pass"
        self.assertEqual(max(5.0, ctx.wall()), 5.0)
        self._touch(PASS_CLOCK, "wall\n")
        self.assertEqual(M.read_pass_clock(self.paths), "wall")


class SwitchNames(unittest.TestCase):
    def test_the_kill_switch_names_are_productions(self) -> None:
        """GUARD: this module names the switch files itself (see PASS_CLOCK above)."""
        self.assertEqual(
            (
                M.PASS_CLOCK,
                C.C_RC5_OFF,
                C.HOLD_MAP_OFF,
                act.LOAD_TERM_ON,
                C.C_ACTUATORS,
            ),
            (PASS_CLOCK, C_RC5_OFF, HOLD_MAP_OFF, LOAD_TERM_ON, C_ACTUATORS),
        )


class ReportAnchors(unittest.TestCase):
    def test_a_hold_with_no_wait_ages_from_detection_not_updated_at(self) -> None:
        """B7 D4b: save_records restamps updated_at every pass, so a max age measured from it
        never came (report.py's three fallbacks)."""
        now = 1_800_000_000.0
        rec = T.Record(sid="abcdef01-0000-0000-0000-000000000001", record_id="r1")
        rec.phase, rec.substate, rec.updated_at = "PRE-MOVE", "HOLD-COMPOSER", now
        rec.timeline.detected = now - 1000
        self.assertTrue(report.max_age_due(rec, now))


# ── G1 and G5 ──────────────────────────────────────────────────────────────────────────────────────


class ActuatorEnvLoadTermOff(_Sandbox):
    """G1 Rule 3: no actuator inherits the capacity library's load term (CC_ADMIT_LOAD_TERM)."""

    def _env(self, base: dict) -> dict:
        rec = T.Record(sid="abcdef01-0000-0000-0000-000000000001", record_id="r1")
        out = {}
        for letter in T.ACTUATORS:
            rec.close["actuator"] = letter
            out[letter] = act.actuator_env(rec, self.paths, "", base=dict(base))
        return out

    def test_actuator_env_sets_the_load_term_off_for_every_actuator_letter(
        self,
    ) -> None:
        for letter, env in self._env({"CC_ADMIT_LOAD_TERM": "on"}).items():
            self.assertEqual(env.get("CC_ADMIT_LOAD_TERM"), "off", letter)
        for letter, env in self._env({}).items():
            self.assertEqual(env.get("CC_ADMIT_LOAD_TERM"), "off", letter)

    def test_the_kill_switch_hands_back_the_environments_own_value(self) -> None:
        self._touch(LOAD_TERM_ON)
        for env in self._env({"CC_ADMIT_LOAD_TERM": "on"}).values():
            self.assertEqual(env.get("CC_ADMIT_LOAD_TERM"), "on")
        for env in self._env({}).values():
            self.assertNotIn("CC_ADMIT_LOAD_TERM", env)


HELD_LITERAL = re.compile(r"HELD:([A-Za-z][A-Za-z:_-]*)")
EMITTERS = ("scripts/handoff-fire.sh", "scripts/limit-recover/lr-handoff.sh")
# A literal that stays DETERMINISTIC, or is not a reason at all, with its reason. Nothing else may.
ALLOWED = {
    "no-shell": "lr-handoff --no-replace over a launcher-rooted pane: no shell survives its /exit and "
    "nothing will make one; it keeps its refusal, paged once per pane (lrh_page_no_shell_once)",
    "pane:": "the family prefix in handoff-fire's comment `HELD:pane:<state>`; its only emitted "
    "member, pane:resolver-unavailable, is a literal of its own and maps TRANSIENT",
}


class EveryHoldReasonIsMapped(_Sandbox):
    """G5 closure (B3 correctness R.3): every actuator hold reason has an explicit row. Before W8
    mid-turn, bg-work:ship-land, wake-guard, launch-lock, holder and load fell to DETERMINISTIC,
    escalated on a repeat and ended IMPOSSIBLE after REARM_CAP re-arms."""

    def _literals(self) -> set:
        out = set()
        for rel in EMITTERS:
            with open(
                os.path.join(REPO, rel), encoding="utf-8", errors="replace"
            ) as fh:
                out |= set(HELD_LITERAL.findall(fh.read()))
        return out

    def test_every_HELD_literal_maps_to_a_non_deterministic_class(self) -> None:
        lits = self._literals()
        self.assertTrue(
            {"mid-turn", "bg-work:ship-land", "wake-guard", "load"} <= lits, lits
        )
        for name in ALLOWED:
            self.assertIn(name, lits, "stale ALLOWED row: %s" % name)
        bad = []
        for lit in sorted(lits - set(ALLOWED)):
            reason = lit + "x" if lit.endswith(":") else lit  # a family: any member
            disp, _sub = C.map_notmoved(reason, "limited")
            if disp == "DETERMINISTIC":
                bad.append(lit)
        self.assertEqual(bad, [], "unmapped HELD reasons (add a classify.HOLD_MAP row)")

    def test_map_notmoved_load_is_hold_load(self) -> None:
        self.assertEqual(C.map_notmoved("load", "limited"), ("HOLD", "HOLD-LOAD"))
        self.assertEqual(C.map_notmoved("no-shell", "limited"), ("DETERMINISTIC", ""))

    def test_the_kill_switch_restores_the_fall_through(self) -> None:
        self._touch(HOLD_MAP_OFF)
        _switches(self.paths.root)
        self.assertEqual(C.map_notmoved("mid-turn", "limited"), ("DETERMINISTIC", ""))
        self.assertEqual(C.map_notmoved("load", "limited"), ("DETERMINISTIC", ""))

    def _pre(self) -> T.Record:
        rec = T.Record(sid="abcdef01-0000-0000-0000-000000000001", record_id="r1")
        rec.phase, rec.substate, rec.kind = "PRE-MOVE", "PLANNED", "limited"
        return rec

    def _score(self, rec: T.Record, text: str, at: float, rc: int = 3) -> str:
        pr = T.ProcRole(role="actuator", pid=7, lstart="x", argv_hash="A")
        return settle.settle_exit(rec, pr, rc, text, at)

    def test_each_emitted_line_reaches_its_row(self) -> None:
        """Verified at the emitting sites: the outcome each actuator log line scores."""
        wake = (
            "lr-handoff: HELD:wake-guard (woke 12s ago) — LR_WAKE_GUARD_S=30; nothing was transplanted\n"
            "lr-handoff abcdef01: verdict=NOTMOVED from=next3 to=next4 proven=no trigger=limit — "
            "HELD:wake-guard (woke 12s ago) — held before the first irreversible step; the source "
            "session is untouched and a retry is safe\n"
        )
        cases = {
            wake: ("TRANSIENT", ""),
            "verdict: HELD:mid-turn\n": ("HOLD", "HOLD-COMPOSER"),
            "verdict: HELD:bg-work:ship-land\n": ("HOLD", "HOLD-BGWORK"),
            "verdict: HELD:bg-work:other\n": ("HOLD", "HOLD-BGWORK"),
            "verdict: HELD:launch-lock\n": ("HOLD", "HOLD-COMPOSER"),
            "verdict: HELD:holder\n": ("HOLD", "HOLD-COMPOSER"),
            "lr-handoff: PRECHECK HELD:load — load 31.0/core\n": ("HOLD", "HOLD-LOAD"),
        }
        for text, want in cases.items():
            self.assertEqual(settle.outcome(self._pre(), 3, text, "A")[:2], want, text)

    def test_a_repeated_hold_never_escalates(self) -> None:
        for text in (
            "verdict: HELD:mid-turn\n",
            "lr-handoff: PRECHECK HELD:load — load 31.0/core\n",
            "lr-handoff: HELD:wake-guard (woke 3s ago) — nothing was transplanted\n",
        ):
            rec = self._pre()
            for i in range(6):
                rec.phase, rec.substate, rec.wait = "PRE-MOVE", "PLANNED", None
                self._score(rec, text, self.now + 300 * i, rc=6)
            self.assertFalse(rec.escalated, text)
            self.assertIsNone(rec.terminal, text)

    def test_held_load_pages_at_900s_and_ship_land_at_3600s(self) -> None:
        rec = self._pre()
        self._score(rec, "lr-handoff: PRECHECK HELD:load — load 31.0/core\n", self.now)
        self.assertEqual(rec.substate, "HOLD-LOAD")
        self.assertEqual(report.max_age_deadline(rec), self.now + 900)
        rec = self._pre()
        self._score(rec, "verdict: HELD:bg-work:ship-land\n", self.now)
        self.assertEqual(rec.wait.detail, "ship-land")
        self.assertEqual(report.max_age_deadline(rec), self.now + 3600)


if __name__ == "__main__":
    unittest.main()
