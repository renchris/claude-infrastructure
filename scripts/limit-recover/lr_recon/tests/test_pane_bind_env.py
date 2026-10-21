"""W14 (B5-R): kitty-free pane binding in the census — hermetic, over tests/fixtures/lr-recon/ps-env.

A record born while its kitty's `kitten @ ls` fails had no pane, so its relaunched target holder was
never pane-bound and the record sat PRE-MOVE/None with nothing dispatched (C2 efficacy E1). In mode
on, observe binds each claude under that kitty from `ps -E` (KITTY_WINDOW_ID/KITTY_PID, last token)
plus its ancestry, by W12's kernel identity rules, above kitty's background band. Shadow logs the
same rows and binds nothing; off runs nothing.
"""

import contextlib
import json
import os
import shutil
import stat
import tempfile
import time
import unittest
from types import SimpleNamespace
from typing import Any, Dict, Iterable, List, Optional, Tuple
from unittest import mock

from lr_recon import __main__ as M
from lr_recon import act, census, evidence, phase
from lr_recon import observe as O
from lr_recon import observe_rows as R
from lr_recon import types as T

FIX = os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    *[".."] * 4,
    "tests",
    "fixtures",
    "lr-recon",
    "ps-env",
)
SID = "aaaa1111-0000-4000-8000-000000000001"
SIDH = "hhhh8888-0000-4000-8000-000000000008"
SOURCE, TARGET = 901, 905
DEAF, HEALTHY = 853, 860


def _fix(name: str) -> str:
    with open(os.path.join(FIX, name), encoding="utf-8") as fh:
        return fh.read()


def _lines(text: str, drop: Iterable[int]) -> str:
    gone = set(drop)
    return "".join(
        ln + "\n"
        for ln in text.splitlines()
        if ln.split() and int(ln.split()[0]) not in gone
    )


class FakeRun:
    """ps, ps -E, ps -M and kitten @ ls over the fixtures; kitty 853's ls fails (rc 1)."""

    def __init__(self, drop: Iterable[int] = (), pri: str = "47T", deaf=(DEAF,)):
        self.drop, self.pri, self.deaf = tuple(drop), pri, tuple(deaf)
        self.calls: List[List[str]] = []

    def __call__(self, argv: List[str], **kw: Any) -> Any:
        self.calls.append(list(argv))
        ok = lambda out, rc=0: SimpleNamespace(returncode=rc, stdout=out)  # noqa: E731
        if argv[:2] == ["/bin/ps", "-E"]:
            want = {int(p) for p in argv[-1].split(",")}
            rows = _lines(_fix("ps-env.txt"), self.drop)
            return ok(
                "".join(
                    ln + "\n" for ln in rows.splitlines() if int(ln.split()[0]) in want
                )
            )
        if argv[:2] == ["/bin/ps", "-M"]:
            if self.pri is None:
                return ok("", 1)
            return ok(
                "USER PID TT %%CPU STAT PRI STIME UTIME COMMAND\n"
                "chrisren %s ?? 4.3 S %s 1:00.00 1:00.00 kitty\n" % (argv[-1], self.pri)
            )
        if argv[0] == "/bin/ps" and "pid=,tty=" in argv:
            return ok(_lines(_fix("ttys.txt"), self.drop))
        if argv[0] == "/bin/ps":
            return ok(_lines(_fix("ps.txt"), self.drop))
        if argv[1:3] == ["@", "--to"]:
            kpid = int(argv[3].rsplit("-", 1)[-1])
            if kpid in self.deaf:
                return ok("", 1)
            return ok(_fix("ls-%d.json" % kpid))
        # not AssertionError: a mutant must die on a test's assertion, never on the fake
        raise RuntimeError("unexpected argv %r" % (argv,))

    def env_calls(self) -> int:
        return sum(1 for a in self.calls if a[:2] == ["/bin/ps", "-E"])


def fake_glob(pattern: str) -> List[str]:
    if pattern.startswith("/tmp/kitty-"):
        return ["/tmp/kitty-%d" % DEAF, "/tmp/kitty-%d" % HEALTHY]
    import glob

    return glob.glob(pattern)


def fake_lstat(path: str) -> Any:
    return SimpleNamespace(st_mode=stat.S_IFSOCK | 0o755)


class Base(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.mkdtemp(prefix="lr-w14.")
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.home = os.path.join(self.tmp, "home")
        env = mock.patch.dict(
            os.environ,
            {
                "HOME": self.home,
                "LR_STATE_DIR": os.path.join(self.tmp, "lr"),
                "LR_RECON_ROOT": os.path.join(self.tmp, "lr", "recon"),
            },
        )
        env.start()
        self.addCleanup(env.stop)
        self.paths = T.Paths.from_env(root=os.path.join(self.tmp, "lr", "recon"))
        M.store.ensure_dirs(self.paths)
        O._HEALTHY_AT[0] = float("-inf")
        self.addCleanup(O._HEALTHY_AT.__setitem__, 0, float("-inf"))
        self._put(
            ".claude/accounts.json",
            {
                "accounts": [
                    {"name": "next2", "config_dir": "~/.claude-secondary"},
                    {"name": "next3", "config_dir": "~/.claude-tertiary"},
                ]
            },
        )
        self.registry(SOURCE, "claude-secondary")
        self._put(
            ".claude/cc-registry/3.json",
            {
                "session_id": SIDH,
                "pid": 931,
                "account": "claude-tertiary",
                "paneUUID": "3",
            },
        )

    def _put(self, rel: str, data: Any) -> None:
        path = os.path.join(self.home, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(data, fh)

    def registry(self, pid: int, account: str) -> None:
        self._put(
            ".claude/cc-registry/7.json",
            {
                "session_id": SID,
                "pid": pid,
                "account": account,
                "cwd": self.home,
                "paneUUID": "7",
            },
        )

    def snap(
        self,
        mode: Optional[str],
        drop: Iterable[int] = (TARGET,),
        run: Optional[FakeRun] = None,
        paths: Optional[T.Paths] = None,
    ) -> T.Snapshot:
        return O.observe(
            paths,
            self.home,
            run=run or FakeRun(drop),
            glob_fn=fake_glob,
            lstat_fn=fake_lstat,
            pane_bind_env=mode,
        )

    def rows(self, snap: T.Snapshot) -> Dict[int, Dict[str, Any]]:
        return {r["pid"]: r for r in snap.pane_bind_env}

    def holder(self, snap: T.Snapshot, sid: str, pid: int) -> T.HolderObs:
        [h] = [h for h in snap.sessions[sid].holders if h.pid == pid]
        return h


# ── red: a record born during the outage, then relaunched in its own window ────────────────────────
class RedBornDuringOutage(Base):
    def run_case(
        self, mode: Optional[str]
    ) -> Tuple[T.PhaseResult, Optional[str], T.Record]:
        birth = self.snap(mode, drop=(TARGET,))
        s = birth.sessions[SID]
        pane = birth.panes.get("%d:%d" % s.pane) if s.pane else None
        b = T.Bucket(sid=SID, name="LIMITED", kind="limited", acct="next2", scope="5h")
        rec = census.new_record(b, s, pane, "cid", "census", True, time.time())
        rec.target_acct = "next3"
        rec.target_cfg = os.path.join(self.home, ".claude-tertiary")
        self.registry(TARGET, "claude-tertiary")
        relaunch = self.snap(mode, drop=(SOURCE,))
        ev = T.Evidence(kind="limited", attempt=1)
        ev.holders = evidence._holders(rec, relaunch.sessions[SID])
        ev.handed_off, ev.source_alive, ev.source_retired = True, False, True
        ev.confirm_len = 100
        ev.pane_state = evidence._pane_state(rec, relaunch)
        res = phase.derive_phase(ev)
        rec.phase, rec.substate = res.phase, res.substate or "UNPROMPTED"
        return res, act.choose(res, rec), rec

    def test_today_off_sits_pre_move_with_nothing_dispatched(self) -> None:
        res, choice, rec = self.run_case("off")
        self.assertEqual((res.phase, res.action), ("PRE-MOVE", "plan"))
        self.assertIsNone(choice)
        self.assertIsNone(rec.pane)

    def test_shadow_binds_nothing(self) -> None:
        res, choice, rec = self.run_case("shadow")
        self.assertEqual(res.phase, "PRE-MOVE")
        self.assertIsNone(choice)
        self.assertIsNone(rec.pane)

    def test_mode_on_relaunched_unprompted_action_c(self) -> None:
        res, choice, rec = self.run_case("on")
        self.assertEqual(
            (res.phase, res.substate, res.action), ("RELAUNCHED", "UNPROMPTED", "C")
        )
        self.assertEqual(choice, "C")
        self.assertEqual(tuple(rec.pane), (DEAF, 7))
        self.assertEqual(
            (rec.identity.root_pid, rec.identity.tty, rec.root_shape),
            (900, "ttys007", "shell"),
        )

    def test_env_pane_is_marked_and_reads_no_foreground(self) -> None:
        snap = self.snap("on")
        p = snap.panes["%d:7" % DEAF]
        self.assertEqual(
            (p.pane_src, p.state, p.sock), ("env", "unknown", "unix:/tmp/kitty-853")
        )
        h = self.holder(snap, SID, SOURCE)
        self.assertEqual((h.pane, h.pane_src), ((DEAF, 7), "env"))
        self.assertEqual(O.untrusted(snap, None), "")


# ── controls ─────────────────────────────────────────────────────────────────────────────────────
class Controls(Base):
    def test_healthy_ls_binding_identical_in_every_mode(self) -> None:
        for mode in ("off", "shadow", "on"):
            O._HEALTHY_AT[0] = float("-inf")
            h = self.holder(self.snap(mode), SIDH, 931)
            self.assertEqual((h.pane, h.pane_src), ((HEALTHY, 3), "ls"), mode)

    def test_shadow_row_agrees_with_ls(self) -> None:
        r = self.rows(self.snap("shadow"))[931]
        self.assertEqual(
            (r["ls_ok"], r["env"], r["ls"], r["agree"]), (True, "860:3", "860:3", "yes")
        )

    def test_kitty_pid_mismatch_is_not_bound(self) -> None:
        snap = self.snap("on")
        r = self.rows(snap)[911]
        self.assertEqual((r["env"], r["bound"]), ("-", False))
        self.assertIn("not an ancestor", r["why"])
        self.assertNotIn("%d:8" % DEAF, snap.panes)

    def test_zombie_root_excluded(self) -> None:
        snap = self.snap("on")
        r = self.rows(snap)[921]
        self.assertEqual((r["env"], r["bound"]), ("-", False))
        self.assertIn("zombie", r["why"])
        self.assertNotIn("%d:9" % DEAF, snap.panes)

    def test_last_env_token_wins_over_a_prompt_in_argv(self) -> None:
        env = O.parse_ps_env(_fix("ps-env.txt"))[SOURCE]
        self.assertEqual((env["KITTY_WINDOW_ID"], env["KITTY_PID"]), ("7", "853"))

    def test_no_env_block_is_unknown_not_no_kitty(self) -> None:
        self.assertEqual(O.parse_ps_env("  42 /x/claude.exe KITTY_WINDOW_ID=3\n"), {})

    def test_headless_claude_is_never_judged(self) -> None:
        self.assertNotIn(950, self.rows(self.snap("on")))

    def test_background_banded_kitty_holds_as_today(self) -> None:
        snap = self.snap("on", run=FakeRun((TARGET,), pri="4T"))
        r = self.rows(snap)[SOURCE]
        self.assertEqual(
            (r["env"], r["held"], r["bound"], r["band"]),
            ("853:7", "banded", False, "4 4 4"),
        )
        self.assertIsNone(self.holder(snap, SID, SOURCE).pane)

    def test_unreadable_band_holds_as_today(self) -> None:
        snap = self.snap("on", run=FakeRun((TARGET,), pri=None))
        r = self.rows(snap)[SOURCE]
        self.assertEqual((r["held"], r["bound"]), ("band-unreadable", False))
        self.assertIsNone(self.holder(snap, SID, SOURCE).pane)

    def test_ls_root_outranks_env_root(self) -> None:
        procs = {
            p: T.ProcRow(p, pp, "S", "L", a)
            for p, pp, a in (
                (500, 1, "kitty"),
                (501, 500, "-zsh"),
                (502, 501, "claude"),
            )
        }
        self.assertEqual(
            R.bind_src(502, procs, {501: (500, 1)}, {502: (500, 9)}), ((500, 1), "ls")
        )
        self.assertEqual(R.bind_src(502, procs, {}, {502: (500, 9)}), ((500, 9), "env"))
        self.assertEqual(R.bind_src(502, procs, {}, None), (None, ""))


# ── the mode file, the kill switch, the shadow log, the healthy throttle ─────────────────────────
class ModeAndLog(Base):
    def _mode(self, text: Optional[str]) -> None:
        path = self.paths.p(O.PANE_BIND_ENV_MODE)
        if text is None:
            if os.path.exists(path):
                os.unlink(path)
            return
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(text)

    def test_default_is_shadow_and_garbage_reads_shadow(self) -> None:
        self.assertEqual(O.pane_bind_env_mode(self.paths), "shadow")
        self._mode("on!\n")
        self.assertEqual(O.pane_bind_env_mode(self.paths), "on")
        self._mode(
            "ON"
        )  # lowercase only, as handoff-fire's tr -dc '[:lower:]' reads its mode files
        self.assertEqual(O.pane_bind_env_mode(self.paths), "shadow")
        self._mode("bogus")
        self.assertEqual(O.pane_bind_env_mode(self.paths), "shadow")
        self.assertEqual(O.pane_bind_env_mode(None), "off")

    def test_kill_switch_off_runs_no_env_read(self) -> None:
        self._mode("off\n")
        run = FakeRun((TARGET,))
        snap = self.snap(None, run=run, paths=self.paths)
        self.assertEqual(
            (run.env_calls(), snap.pane_bind_env, snap.pane_bind_env_mode), (0, [], "")
        )
        self.assertIsNone(self.holder(snap, SID, SOURCE).pane)

    def test_shadow_file_logs_rows_and_binds_nothing(self) -> None:
        snap = self.snap(None, paths=self.paths)
        self.assertEqual(snap.pane_bind_env_mode, "shadow")
        self.assertIsNone(self.holder(snap, SID, SOURCE).pane)
        with open(
            os.path.join(self.paths.shadow, O.PANE_BIND_ENV_LOG), encoding="utf-8"
        ) as fh:
            logged = [json.loads(x) for x in fh if x.strip()]
        by = {r["pid"]: r for r in logged}
        self.assertEqual(sorted(by), [871, SOURCE, 911, 921, 931])
        self.assertEqual((by[SOURCE]["env"], by[SOURCE]["bound"]), ("853:7", False))

    def test_healthy_comparison_is_throttled(self) -> None:
        run = FakeRun((TARGET,), deaf=())
        only_healthy = lambda p: (
            ["/tmp/kitty-%d" % HEALTHY] if p.startswith("/tmp/kitty-") else fake_glob(p)
        )  # noqa: E731
        for _ in range(2):
            snap = O.observe(
                None,
                self.home,
                run=run,
                glob_fn=only_healthy,
                lstat_fn=fake_lstat,
                pane_bind_env="shadow",
            )
            self.assertEqual(snap.degraded, [])
        self.assertEqual(run.env_calls(), 1)

    def test_pid_cap_keeps_the_deaf_kittys_claudes_first(self) -> None:
        with mock.patch.object(O, "PANE_BIND_ENV_PIDS_MAX", 1):
            snap = self.snap("on")
        self.assertEqual([r["pid"] for r in snap.pane_bind_env], [SOURCE])
        self.assertEqual(self.holder(snap, SID, SOURCE).pane, (DEAF, 7))

    def test_deaf_kitty_is_judged_every_pass(self) -> None:
        run = FakeRun((TARGET,))
        self.snap("shadow", run=run)
        self.snap("shadow", run=run)
        self.assertEqual(run.env_calls(), 2)

    def test_env_read_failure_binds_nothing_and_says_why(self) -> None:
        run = FakeRun((TARGET,))
        orig = run.__call__

        def no_env(argv: List[str], **kw: Any) -> Any:
            if argv[:2] == ["/bin/ps", "-E"]:
                return SimpleNamespace(returncode=1, stdout="")
            return orig(argv, **kw)

        snap = self.snap("on", run=no_env)  # type: ignore[arg-type]
        self.assertIn("pane-bind-env", snap.degraded_why)
        self.assertNotIn("pane-bind-env", snap.degraded)
        self.assertIsNone(self.holder(snap, SID, SOURCE).pane)


# ── the W8 kitty-degraded event carries the counts ───────────────────────────────────────────────
class EventCounts(Base):
    def _events(self, ev: str) -> List[dict]:
        if not os.path.exists(self.paths.events):
            return []
        with open(self.paths.events, encoding="utf-8") as fh:
            return [
                e for e in (json.loads(x) for x in fh if x.strip()) if e.get("ev") == ev
            ]

    def check_counts(self) -> None:
        ctx = M.Ctx(self.paths, None, self.home)
        rec = T.Record(sid=SID, record_id="r1")
        rec.phase, rec.substate = "PRE-MOVE", "UNPROMPTED"
        ctx.records = {rec.sid: rec}
        M._kitty_degraded(ctx, self.snap("on"))
        [ev] = self._events("kitty-degraded")
        self.assertIn("kitty:unix:/tmp/kitty-853", ev["detail"])
        self.assertIn(
            "pane-bind-env on: 1 of 3 claude(s) under a deaf kitty bound by env",
            ev["detail"],
        )
        self.assertIn("aaaa1111", ev["detail"])

    def test_event_carries_counts(self) -> None:
        self.check_counts()


# ── every new rule's mutant dies ─────────────────────────────────────────────────────────────────
class MutantsDie(Base):
    def dies(self, check: Any, *patches: Any) -> None:
        with contextlib.ExitStack() as es:
            for p in patches:
                es.enter_context(p)
            with self.assertRaises(AssertionError):
                check()

    def _t(self, cls: Any, name: str) -> Any:
        t = cls(name)
        t.setUp()
        self.addCleanup(t.doCleanups)
        return getattr(t, name)

    def test_no_ancestry_rule_kills_the_mismatch_control(self) -> None:
        def trusting(pid: int, env: Dict[str, str], procs: Any, ttys: Any) -> Any:
            return (int(env["KITTY_PID"]), int(env["KITTY_WINDOW_ID"])), pid, ""

        self.dies(
            self._t(Controls, "test_kitty_pid_mismatch_is_not_bound"),
            mock.patch.object(O, "env_pane", trusting),
        )

    def test_no_zombie_rule_kills_the_zombie_control(self) -> None:
        orig = O.env_pane

        def unzombied(pid: int, env: Dict[str, str], procs: Any, ttys: Any) -> Any:
            alive = {
                k: T.ProcRow(r.pid, r.ppid, "S", r.lstart, r.args)
                for k, r in procs.items()
            }
            return orig(pid, env, alive, ttys)

        self.dies(
            self._t(Controls, "test_zombie_root_excluded"),
            mock.patch.object(O, "env_pane", unzombied),
        )

    def test_first_token_parse_kills_the_red_case(self) -> None:
        def first_wins(out: str) -> Dict[int, Dict[str, str]]:
            res: Dict[int, Dict[str, str]] = {}
            for line in out.splitlines():
                toks = line.split()
                env: Dict[str, str] = {}
                for t in toks[1:]:
                    k, sep, v = t.partition("=")
                    if sep and k in O._ENV_KEYS and k not in env:
                        env[k] = v
                res[int(toks[0])] = env
            return res

        self.dies(
            self._t(RedBornDuringOutage, "test_mode_on_relaunched_unprompted_action_c"),
            mock.patch.object(O, "parse_ps_env", first_wins),
        )

    def test_band_gate_dropped_kills_the_banded_control(self) -> None:
        self.dies(
            self._t(Controls, "test_background_banded_kitty_holds_as_today"),
            mock.patch.object(O, "kitty_band", lambda k, run=None: (0, "4 4 4")),
        )

    def test_unreadable_band_as_proof_kills_the_unreadable_control(self) -> None:
        self.dies(
            self._t(Controls, "test_unreadable_band_holds_as_today"),
            mock.patch.object(O, "kitty_band", lambda k, run=None: (0, "? ? ?")),
        )

    def test_shadow_binding_kills_the_shadow_case(self) -> None:
        orig = O.env_rows

        def binds(
            snap: Any, ttys: Any, roots: Any, failed: Any, mode: str, run: Any = None
        ) -> Any:
            return orig(
                snap, ttys, roots, failed, "on" if mode == "shadow" else mode, run
            )

        self.dies(
            self._t(RedBornDuringOutage, "test_shadow_binds_nothing"),
            mock.patch.object(O, "env_rows", binds),
        )

    def test_kill_switch_ignored_kills_the_off_case(self) -> None:
        self.dies(
            self._t(ModeAndLog, "test_kill_switch_off_runs_no_env_read"),
            mock.patch.object(O, "pane_bind_env_mode", lambda paths: "shadow"),
        )

    def test_env_before_ls_kills_the_precedence_control(self) -> None:
        def env_first(pid: int, procs: Any, roots: Any, env_roots: Any = None) -> Any:
            if env_roots and pid in env_roots:
                return env_roots[pid], "env"
            return (roots.get(pid), "ls") if pid in roots else (None, "")

        self.dies(
            self._t(Controls, "test_ls_root_outranks_env_root"),
            mock.patch.object(R, "bind_src", env_first),
        )

    def test_no_throttle_kills_the_throttle_case(self) -> None:
        self.dies(
            self._t(ModeAndLog, "test_healthy_comparison_is_throttled"),
            mock.patch.object(O, "PANE_BIND_ENV_HEALTHY_EVERY_S", 0.0),
        )

    def test_pid_order_cap_kills_the_cap_case(self) -> None:
        # the cap without its ordering: the lowest pids, healthy or not
        self.dies(
            self._t(ModeAndLog, "test_pid_cap_keeps_the_deaf_kittys_claudes_first"),
            mock.patch.object(
                O,
                "_capped",
                lambda under, failed: sorted(under)[: O.PANE_BIND_ENV_PIDS_MAX],
            ),
        )

    def test_countless_event_kills_the_counts_case(self) -> None:
        self.dies(
            self._t(EventCounts, "check_counts"),
            mock.patch.object(O, "env_counts", lambda snap: ""),
        )


if __name__ == "__main__":
    unittest.main()
