"""A background job does not hold a session on an account the server is rejecting (2026-10-13).

THE ARTIFACTS, in tests/fixtures/lr-rejected-source-moves/ (ps rows captured from the live panes,
home path neutralised): pane 12 (c56c729c, claude pid 78979) ran a mailbox watcher and a polling
loop in Bash-tool shells whose argv carries NO `shell-snapshots` (the session never wrote a shell
snapshot, so the harness starts them `zsh -c -l …`); pane 16 (4fe9935f, claude pid 80475) ran a
watcher and a `zprint -d` that never ends, in the usual `source …shell-snapshots…` shape.

Operator ruling 2026-10-13: when the source account is server-rejected no hold may leave a session
there. A healthy source keeps every hold, and so does a ship-land job."""

import os
import unittest
from typing import Dict

from lr_recon import census as C
from lr_recon import observe_rows as R
from lr_recon import types as T

FX = os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    *([os.pardir] * 4),
    "tests",
    "fixtures",
    "lr-rejected-source-moves",
)
NOW = 1_791_866_810.0
LIMIT = {"limit": True, "kind": "limit", "cap": "seven_day", "resets_at": NOW + 7200}


def procs(name: str) -> Dict[int, T.ProcRow]:
    """The fixture's `pid ppid lstart(5) args` rows as the observer's own ProcRow map."""
    out: Dict[int, T.ProcRow] = {}
    with open(os.path.join(FX, name), encoding="utf-8") as fh:
        for line in fh:
            f = line.rstrip("\n").split(" ", 7)
            if len(f) < 8:
                continue
            out[int(f[0])] = T.ProcRow(
                pid=int(f[0]),
                ppid=int(f[1]),
                stat="S",
                lstart=" ".join(f[2:7]),
                args=f[7],
            )
    return out


def fact(**kw: object) -> Dict[str, T.Fact]:
    f = T.Fact(
        acct="next3",
        scope="7d",
        status="rejected",
        resets_at=1791892800.0,
        observed_at=1791855942.705208,
        src="hook",
        first_sid="14233392-334a-45c6-af56-d6aecd4a098c",
    )
    for k, v in kw.items():
        setattr(f, k, v)
    return {"next3.7d": f}


class BashToolShellHasTwoShapes(unittest.TestCase):
    def test_pane_12s_no_snapshot_shells_are_jobs(self) -> None:
        p = procs("pane12.ps.txt")
        bw = R.bg_work_for([78979], p, R.children_map(p), [])
        self.assertEqual(sorted(b.pid for b in bw), [54057, 95607])
        by = {b.pid: b for b in bw}
        self.assertTrue(by[54057].watcher_only)  # cc-await-ping and nothing else
        self.assertFalse(
            by[95607].watcher_only
        )  # the `until grep …; do sleep 120` loop

    def test_pane_16s_snapshot_shells_read_as_before(self) -> None:
        p = procs("pane16.ps.txt")
        bw = R.bg_work_for([80475], p, R.children_map(p), [])
        by = {b.pid: b for b in bw}
        self.assertEqual(sorted(by), [10476, 88781])
        self.assertTrue(by[10476].watcher_only)
        self.assertFalse(by[88781].watcher_only)  # zprint -d

    def test_a_shell_that_is_not_the_harnesss_is_still_not_a_job(self) -> None:
        p = {
            1: T.ProcRow(pid=1, ppid=0, stat="S", lstart="x", args="claude"),
            2: T.ProcRow(
                pid=2,
                ppid=1,
                stat="S",
                lstart="x",
                args="/bin/bash /x/hooks/stop-hook.sh",
            ),
        }
        self.assertEqual(R.bg_work_for([1], p, R.children_map(p), []), [])


class RejectedSourceIsNotHeldForAJob(unittest.TestCase):
    def setUp(self) -> None:
        self.pane = T.PaneObs(
            kitty_pid=64211,
            window_id=16,
            sock="s",
            root_pid=20,
            root_lstart="x",
            root_shape="shell",
            state="claude",
        )
        self.snap = T.Snapshot(wall=NOW, uptime_raw=0.0, panes={"64211:16": self.pane})
        p = procs("pane16.ps.txt")
        self.work = R.bg_work_for([80475], p, R.children_map(p), [])

    def s(self, **kw: object) -> T.SessionObs:
        base = dict(
            sid="4fe9935f-ca5f-4a48-803c-5e569b08f1b7",
            acct="next3",
            cfg="/c3",
            cwd=os.getcwd(),
            pane=(64211, 16),
            holders=[
                T.HolderObs(
                    pid=80475, lstart="x", cfg="/c3", src="registry", pane=(64211, 16)
                )
            ],
            transcript=T.TranscriptObs(path="/t.jsonl", last=dict(LIMIT), at_rest=True),
            registry_name="claude-infrastructure-16",
            bg_work=list(self.work),
        )
        base.update(kw)
        return T.SessionObs(**base)

    def b(self, s: T.SessionObs, facts: Dict[str, T.Fact]) -> str:
        return C.bucket(s, self.snap, facts, NOW, {}).name

    def test_the_never_ending_job_does_not_hold_a_limited_session_on_a_rejected_account(
        self,
    ) -> None:
        self.assertEqual(self.b(self.s(), fact()), "LIMITED")

    def test_the_hold_stands_for_a_healthy_source_and_for_a_ship_land(self) -> None:
        # no fact, a contradicted fact (a healthy turn after it), a status that is not `rejected`
        self.assertEqual(self.b(self.s(), {}), "HOLD-BGWORK")
        self.assertEqual(self.b(self.s(), fact(contradicted=True)), "HOLD-BGWORK")
        self.assertEqual(
            self.b(self.s(), fact(status="allowed_warning")), "HOLD-BGWORK"
        )
        # a land is never killed: it ends by itself, so its hold cannot strand the session
        ship = [T.BgWork(kind="shell", pid=3, ship_land=True)]
        self.assertEqual(self.b(self.s(bg_work=ship), fact()), "HOLD-BGWORK")

    def test_a_lead_with_live_members_is_still_held_on_a_rejected_account(self) -> None:
        sid = "4fe9935f-ca5f-4a48-803c-5e569b08f1b7"
        self.snap.procs = {
            9: T.ProcRow(
                pid=9,
                ppid=1,
                stat="S",
                lstart="x",
                args="claude --agent-id w@t --parent-session-id %s" % sid,
            )
        }
        self.assertEqual(self.b(self.s(), fact()), "HELD:team")


if __name__ == "__main__":
    unittest.main()
