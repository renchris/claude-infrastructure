"""The restore budget cannot hold a limited session until its reset (2026-10-13, pane 113).

THE ARTIFACT. Session 14233392-334a-45c6-af56-d6aecd4a098c, cohort next3-7d-1791892800, in
~/.reso/limit-recover/recon/events.jsonl:

    1791856395.878551  admit-refused  restore-r
    1791861522.420150  refire         by=cc-lr
    (nothing after it; the record stayed PRE-MOVE/PLANNED with close.admit_refused = restore-r)

MEASURED at 1791866810 with the daemon's own observer (one read-only census pass): 36 live sessions,
12 of them mid-turn, the member itself at rest and so not among the 12, and no other record holding
an admission token. So the gate read active 12 + in flight 0 + 1 = 13 against an R frozen at ACTIVE
entry near its floor of 8. The member WAS re-offered on every pass (_dispatch asks the gate each
time and logs only a changed reason); what never changed was the answer, because `active` counts
every session on the machine and nothing bounded this refusal the way the probe's is bounded."""

import os
import shutil
import tempfile
import unittest
from typing import List, Tuple
from unittest import mock

from lr_recon import __main__ as M
from lr_recon import admit as A
from lr_recon import report as R
from lr_recon import types as T

SID = "14233392-334a-45c6-af56-d6aecd4a098c"
COHORT = "next3-7d-1791892800"
REFUSED_AT = 1791856395.878551
ACTIVE, IN_FLIGHT, CEILING = 12, 0, 8
PASS_S = 15.0


def probe_ok(_argv: List[str]) -> Tuple[int, str]:
    return 0, "/tmp/token\n"


class Wall:
    def __init__(self, t: float) -> None:
        self.t = t

    def __call__(self) -> float:
        return self.t


def entered(wall: "Wall" = None) -> A.Admission:  # type: ignore[assignment]
    adm = A.Admission(
        runner=probe_ok, repo="/repo", env={}, wall=wall or Wall(REFUSED_AT)
    )
    # one corpse and a fleet quieter than the ceiling at entry: R is the floor
    adm.enter_active(4, 1, CEILING, load1=1.0, load5=1.0, ncpu=10, now=REFUSED_AT - 60)
    return adm


class RestoreBudgetIsBounded(unittest.TestCase):
    def test_the_measured_terms_are_admitted_after_the_refusal_run(self) -> None:
        adm = entered()
        self.assertEqual(adm.restore_r, CEILING)
        seen = []
        for i in range(A.DRIP_AFTER + 1):
            seen.append(
                adm.decide(
                    SID,
                    "next",
                    REFUSED_AT + i * PASS_S,
                    ACTIVE,
                    IN_FLIGHT,
                    1.0,
                    1.0,
                    10,
                    COHORT,
                )
            )
        self.assertEqual(seen[: A.DRIP_AFTER], [(False, "restore-r")] * A.DRIP_AFTER)
        self.assertEqual(seen[-1], (True, "admit:drip"))
        self.assertTrue(
            adm.page_due
        )  # an admission past the budget pages, as the drip always has
        self.assertEqual(adm.last_terms, "active 12 + in flight 0 + 1 vs R 8")

    def test_past_the_run_the_pace_the_pacer_and_the_drip_clock_still_decide(
        self,
    ) -> None:
        wall = Wall(REFUSED_AT)
        adm = entered(wall)
        for i in range(A.DRIP_AFTER):
            adm.decide(SID, "next", REFUSED_AT + i, ACTIVE, 0, 1.0, 1.0, 10, COHORT)
        t = REFUSED_AT + 10
        wall.t = t
        # load far over the pre-limit operating point no longer refuses (REPORT §4 A4)
        self.assertEqual(
            adm.decide(SID, "next", t, ACTIVE, 0, 400.0, 1.0, 10, COHORT),
            (True, "admit:drip"),
        )
        # a second member of the cohort waits out the drip's wall clock, then is admitted too
        other = "5dd11e6c-ed1d-4adb-b79d-3d417ba638e1"
        wall.t = t + 1
        self.assertEqual(
            adm.decide(other, "next2", t + 1, ACTIVE, 1, 1.0, 1.0, 10, COHORT),
            (False, "drip"),
        )
        wall.t = t + A.DRIP_EVERY_S
        self.assertEqual(
            adm.decide(
                other, "next2", t + A.DRIP_EVERY_S, ACTIVE, 1, 1.0, 1.0, 10, COHORT
            ),
            (True, "admit:drip"),
        )
        # the pace still binds past the run: spend the bucket, and the next member waits on it
        adm.pace_tokens = 0.0
        third = "6ee22f7d-fe2e-5bec-c8a0-4e528cb749f2"
        wall.t = t + 2 * A.DRIP_EVERY_S
        adm.pace_at = wall.t
        self.assertEqual(
            adm.decide(third, "next4", wall.t, ACTIVE, 2, 1.0, 1.0, 10, COHORT),
            (False, "pace"),
        )

    def test_inside_the_budget_nothing_changed_and_dormant_still_refuses(self) -> None:
        adm = entered()
        self.assertEqual(
            adm.decide(SID, "next", REFUSED_AT, 7, 0, 1.0, 1.0, 10, COHORT),
            (True, "admit"),
        )
        self.assertFalse(adm.page_due)
        dormant = A.Admission(runner=probe_ok, repo="/repo", env={})
        for i in range(A.DRIP_AFTER + 3):
            self.assertEqual(
                dormant.decide(SID, "next", float(i * 60), 0, 0, 0.1, 0.1, 8, COHORT),
                (False, "restore-r"),
            )


class StandingRefusalIsVisible(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.mkdtemp(prefix="lr-recon-restore-")
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.home = os.path.join(self.tmp, "home")
        os.makedirs(self.home)
        self.paths = T.Paths.from_env(root=os.path.join(self.tmp, "lr", "recon"))
        M.store.ensure_dirs(self.paths)
        open(self.paths.recon_on, "w").close()
        self.ctx = M.Ctx(self.paths, None, self.home)
        self.ctx.admission.runner = probe_ok
        self.rec = T.Record(
            sid=SID,
            record_id="recon:%s:14233392:1" % COHORT,
            kind="limited",
            source_acct="next3",
            source_cfg="/c3",
            scope="7d",
            cohort_id=COHORT,
            target_acct="next",
            target_cfg="/t",
            substate="PLANNED",
            pane=(64211, 113),
            cwd="/tmp/reso-landing-design-research",
        )
        self.ctx.records[SID] = self.rec

    def _pass(self, now: float) -> int:
        snap = T.Snapshot(wall=now, uptime_raw=0.0)
        with (
            mock.patch.object(M, "_active_now", return_value=ACTIVE),
            mock.patch.object(M, "_ceiling", return_value=CEILING),
            mock.patch.object(M.os, "getloadavg", return_value=(1.0, 1.0, 1.0)),
            mock.patch.object(M.act, "may_actuate", return_value=(True, "")),
            mock.patch.object(M.act, "spawn", return_value=4242) as sp,
        ):
            M._dispatch(self.ctx, snap, "act", now)
        return sp.call_count

    def test_the_refused_member_is_dispatched_and_its_refusal_is_named_until_then(
        self,
    ) -> None:
        # ACTIVE entry froze R while the fleet was quieter than it is now
        self.ctx.admission.enter_active(
            4, 1, CEILING, load1=1.0, load5=1.0, ncpu=10, now=REFUSED_AT - 60
        )
        self.assertEqual(self._pass(REFUSED_AT), 0)
        self.assertEqual(self.rec.close.get("admit_refused"), "restore-r")
        line = R.next_action(self.rec)
        self.assertIn("admission gate restore-r", line)
        self.assertIn("active 12 + in flight 0 + 1 vs R 8", line)
        self.assertIn("re-offered every pass", line)
        self.assertNotIn("the reconciler continues", line)
        spawned = 0
        for i in range(1, A.DRIP_AFTER + 1):
            spawned += self._pass(REFUSED_AT + i * PASS_S)
            if spawned:
                break
        self.assertEqual(spawned, 1, "the member was never dispatched")
        for k in ("admit_refused", "admit_terms", "admit_refused_at"):
            self.assertNotIn(k, self.rec.close)


if __name__ == "__main__":
    unittest.main()
