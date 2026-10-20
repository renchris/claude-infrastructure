"""A6 restart safety (W2 of docs/plans/LR_SUSTAINED_LOAD_IMPL.md): a restart loses no exit code,
never re-stamps an in-flight claim to the new daemon, and replays a killed pass exactly once.

Numbered as docs/research/lr-sustained-load-2026-10-20/impl/A6-restart-safety.md §6 (py1-py18),
plus the cases its two reviews added (F-A, F-B, F-G/S-3, S-1, S-2, S-5, S-6, S-9, S-11, py8b).
Nonces are 12-hex, as act.spawn mints them: a non-hex fixture nonce writes no file and matches no
wrapper row (S-10). Records are built through T.from_dict from JSON that carries "nonce", so on a
tree without the field each RED case fails by assertion, not with a TypeError. Every root, HOME and
TMPDIR is under the test's own mkdtemp."""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock

from lr_recon import __main__ as M
from lr_recon import act, plan, settle, store
from lr_recon import types as T
from lr_recon.tests import test_in_place as W
from lr_recon.tests import test_main as TM

SID = "abcdef01-0000-0000-0000-000000000001"
RID = "recon:next3-7d-1:abcdef01:1"
N1 = "0123456789ab"
N2 = "fedcba987654"
LW = "Tue Oct 20 03:08:24 2026"  # the inherited wrapper's lstart
LOLD = "Tue Oct 20 01:00:00 2026"  # the old daemon's
LME = "Tue Oct 20 04:00:00 2026"  # this daemon's, as its census row reads it
OLD, WPID = 777, 4300
LR_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# an R precheck hold whose log has NO NOTMOVED line: only an exit code can score it (test 1)
HELD_BUSY = """lr-handoff: precheck composer: busy
lr-handoff: precheck verdict: HELD:busy
lr-handoff: PRECHECK HELD:busy — NOTHING has been transplanted, no lock and no tombstone were written.
"""


def proc(pid, lstart, name="R", nonce=N1, role="actuator"):
    return T.from_dict(
        T.ProcRole,
        {
            "role": role,
            "pid": pid,
            "lstart": lstart,
            "argv_hash": name,
            "nonce": nonce,
        },
    )


def wrapper_row(pid=WPID, nonce=N1, ppid=1, lstart=LW):
    args = (
        "/bin/bash -c %s lr-recon-act --record-id %s --intent %s /bin/bash /x/lr-handoff.sh "
        "--sid %s --record-id %s" % (act.WRAPPER, RID, nonce, SID, RID)
    )
    return T.ProcRow(pid, ppid, "S", lstart, args)


def descendant_row(pid=4301, ppid=WPID):
    return T.ProcRow(
        pid,
        ppid,
        "S",
        LW,
        "/bin/bash /x/lr-handoff.sh --sid %s --record-id %s" % (SID, RID),
    )


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.home = os.path.join(self.tmp, "home")
        os.makedirs(self.home)
        lr = os.path.join(self.tmp, "lr")
        env = mock.patch.dict(
            os.environ,
            {
                "LR_STATE_DIR": lr,
                "LR_RECON_ROOT": os.path.join(lr, "recon"),
                "HOME": self.home,
            },
        )
        env.start()
        self.addCleanup(env.stop)
        for target, value in (("probe", (True, "admit")), ("mint_token", None)):
            p = mock.patch("lr_recon.admit.Admission." + target, return_value=value)
            p.start()
            self.addCleanup(p.stop)
        # the act module's process-wide maps: each test starts empty and leaves them as found
        # (getattr: the red control runs this file against the pre-A6 tree, which has no _SPAWNED)
        # self_ident caches this process's lstart from a census row, and these censuses are fake
        saved_ident = act._SELF_LSTART
        self.addCleanup(setattr, act, "_SELF_LSTART", saved_ident)
        for d in (act.EXIT_CODES, getattr(act, "_SPAWNED", {})):
            saved = dict(d)
            d.clear()
            self.addCleanup(lambda d=d, s=saved: (d.clear(), d.update(s)))
        self.paths = T.Paths.from_env(root=os.path.join(lr, "recon"))
        store.ensure_dirs(self.paths)
        self.exits_dir = os.path.join(self.paths.root, "exits")
        os.makedirs(self.exits_dir, exist_ok=True)
        self.now = time.time()

    # ── fixtures ────────────────────────────────────────────────────────────────────────────────

    def rec(self, procs=(), intent=None, **kw):
        """test_rollback's world: PRE-MOVE, planned onto next4, attempt 1, pane 5:7."""
        data = {
            "sid": SID,
            "record_id": RID,
            "kind": "limited",
            "scope": "7d",
            "source_acct": "next3",
            "source_cfg": "/nonexistent-cfg",
            "source_pid": 10,
            "source_lstart": TM.L,
            "pane": [5, 7],
            "cohort_id": "next3-7d-1",
            "origin": "cc-lr",
            "target_acct": "next4",
            "target_cfg": "/nonexistent-target",
            "procs": [T.to_dict(p) for p in procs],
        }
        if intent:
            data["intent"] = {
                "nonce": intent[0],
                "at": self.now - 60,
                "actuator": intent[1],
            }
        data.update(kw)
        rec = T.from_dict(T.Record, data)
        rec.substate = kw.get("substate")
        rec.timeline.detected = self.now - 3600
        rec.timeline.planned = self.now - 3300
        rec.close["busy_at"] = self.now - 1800
        return rec

    def ctx(self, *recs, keeper=False):
        """On disk too: _startup reloads ctx.records from the store, as a restarted daemon does."""
        for r in recs:
            store.save_record(self.paths, r, self.now)
        ctx = M.Ctx(self.paths, None, self.home)
        ctx.records = {r.sid: r for r in recs}
        ctx.keeper = keeper
        return ctx

    def snap(self, *rows, me=True):
        s = TM._snap(self.now, self.tmp)
        if me:  # the daemon's own census row (act.self_ident reads it; no second ps)
            s.procs[os.getpid()] = T.ProcRow(
                os.getpid(), 1, "S", LME, "python3 -m lr_recon"
            )
        for r in rows:
            s.procs[r.pid] = r
        return s

    def startup(self, ctx, prev=None):
        """M._startup as daemon() runs it, with this daemon's lstart read as LME. ``prev`` is the
        previous daemon's heartbeat file ({} = none). Through the store, not new arguments, so the
        red control runs on the pre-A6 tree and fails by assertion."""
        if prev is not None:
            store._unlink(self.paths.heartbeat)
            if prev:
                with open(self.paths.heartbeat, "w") as fh:
                    json.dump(prev, fh)
        with mock.patch.object(store, "proc_lstart", return_value=LME):
            M._startup(ctx)

    def exit_file(self, nonce, rc, age=0.0):
        p = os.path.join(self.exits_dir, nonce + ".rc")
        with open(p, "w") as fh:
            fh.write("%d\n" % rc)
        if age:
            os.utime(p, (self.now - age, self.now - age))
        return p

    def log(self, rec, text=HELD_BUSY, actuator="R"):
        os.makedirs(self.paths.p("actlogs"), exist_ok=True)
        with open(settle.actlog(self.paths, rec, actuator), "w") as fh:
            fh.write(text)

    def claim(self, pid, lstart, record_id=RID):
        d = store.claim_dir(self.paths, SID)
        os.makedirs(d, exist_ok=True)
        h = T.RunClaimHolder(
            pid=pid, lstart=lstart, owner="lr-reconciler", record_id=record_id
        )
        store._claim_stamp(d, SID, h, self.now)

    def holder(self):
        h = store.read_claim(self.paths, SID)
        return None if h is None else (h.pid, h.lstart)

    def events(self, ev=None):
        if not os.path.exists(self.paths.events):
            return []
        with open(self.paths.events, encoding="utf-8") as fh:
            rows = [json.loads(x) for x in fh if x.strip()]
        return [e for e in rows if ev is None or e.get("ev") == ev]

    def one_pass(self, ctx, snap=None, act_mode=False, dispatch=None):
        """One real run_pass over a fixed census. act_mode: recon.on + mode act, with _dispatch
        replaced by ``dispatch`` (it sees the claim at the moment the pass reaches it)."""
        if act_mode:
            open(self.paths.recon_on, "w").close()
            with open(self.paths.mode_file, "w") as fh:
                fh.write("act\n")
        with (
            mock.patch("lr_recon.observe.observe", return_value=snap or self.snap()),
            mock.patch.object(plan, "place", return_value=({}, 0)),
            mock.patch.object(plan, "assign_many", return_value=0),
            mock.patch.object(M.act, "spawn") as spawn,
            mock.patch.object(M, "_dispatch", side_effect=dispatch or (lambda *a: 0)),
        ):
            summary = M.run_pass(ctx)
        spawn.assert_not_called()
        return summary

    def exits(self, prefix="R rc="):
        return [
            e["detail"] for e in self.events("exit") if e["detail"].startswith(prefix)
        ]


# ── (a) durable exit capture, (b) adoption, (d) replay and bookkeeping: tests 1-7, 14-18 ──────


class ExitCodes(Base):
    def test_01_an_inherited_actuator_is_scored_from_its_exit_file(self):
        """RED: today `R exited, code unknown` — the wrapper was reaped by launchd."""
        rec = self.rec([proc(4242, LW)], intent=(N1, "R"))
        self.log(rec)
        self.exit_file(N1, 6)
        self.one_pass(self.ctx(rec))
        [d] = self.exits()
        self.assertTrue(d.startswith("R rc=6 → HOLD/"), d)
        self.assertEqual(rec.attempt, 2)
        self.assertEqual(rec.substate, "HOLD-COMPOSER")

    def _killed_pass(self, ctx):
        class Killed(Exception):
            pass

        with mock.patch.object(M.store, "save_records", side_effect=Killed):
            with self.assertRaises(Killed):
                self.one_pass(ctx)

    def _reload(self):
        return self.ctx(*store.load_all(self.paths, lambda p, r: None).values())

    def test_02_a_killed_pass_is_replayed_exactly_once(self):
        """RED (code unknown). Pass 1 settles, then dies before save_records: the record on disk
        still lists the dead proc, so pass 2 replays it from the file; pass 3 sees it pruned."""
        rec = self.rec([proc(4242, LW)], intent=(N1, "R"))
        self.log(rec)
        store.save_record(self.paths, rec, self.now)
        self.exit_file(N1, 6)
        self._killed_pass(self._reload())
        self.one_pass(self._reload())
        ctx = self._reload()
        self.one_pass(ctx)
        on_disk = store.load_record(self.paths, SID)
        self.assertEqual(on_disk.attempt, 2)
        self.assertEqual(on_disk.attempts_by_class.get("HOLD"), 1)
        self.assertEqual(on_disk.procs, [])

    def test_03_a_saved_settle_is_not_replayed(self):
        """CONTROL (green both). Mutant: prune_dead keeps the dead procs → a second bump."""
        rec = self.rec([proc(4242, LW)], intent=(N1, "R"))
        self.log(rec)
        store.save_record(self.paths, rec, self.now)
        self.exit_file(N1, 6)
        self.one_pass(self._reload())
        self.one_pass(self._reload())
        on_disk = store.load_record(self.paths, SID)
        self.assertEqual(on_disk.attempt, 2)
        self.assertEqual(on_disk.attempts_by_class.get("HOLD"), 1)
        self.assertEqual(on_disk.procs, [])

    def test_04_the_wrapper_of_a_recorded_intent_is_adopted_under_its_actuator_name(
        self,
    ):
        """RED: today both rows are `adopted`."""
        rec = self.rec(intent=(N1, "R"))
        act.adopt(rec, self.snap(wrapper_row(), descendant_row()))
        got = {p.pid: (p.argv_hash, p.nonce) for p in rec.procs}
        self.assertEqual(got, {WPID: ("R", N1), 4301: ("adopted", "")})

    def test_04b_a_grep_row_quoting_the_token_is_no_wrapper(self):
        """S-11 hygiene: the wrapper token is anchored on /bin/bash -c."""
        rec = self.rec(intent=(N1, "R"))
        row = T.ProcRow(
            5000, 1, "S", LW, "grep lr-recon-act --record-id %s --intent %s" % (RID, N1)
        )
        act.adopt(rec, self.snap(row))
        self.assertEqual([(p.argv_hash, p.nonce) for p in rec.procs], [("adopted", "")])

    def test_05_a_descendant_never_takes_a_reaped_code(self):
        """RED: today _score("adopted", 6) → last_error DETERMINISTIC."""
        rec = self.rec([proc(4301, LW, name="adopted", nonce="")])
        act.EXIT_CODES[4301] = 6
        self.one_pass(self.ctx(rec))
        self.assertIsNone(rec.last_error)
        self.assertEqual(rec.attempt, 1)
        self.assertNotIn(4301, act.EXIT_CODES)
        # the rule itself, without the nonce gate behind it (the legacy pairing, spawned=None)
        d = proc(4301, LW, name="adopted", nonce="")
        self.assertEqual(settle.dead_actuators([d], {4301: 6}), [(d, None)])

    def test_06_an_inherited_pid_never_takes_a_strangers_code(self):
        """RED: today `R rc=0` (IN-FLIGHT) from a code reaped off some other child of ours."""
        rec = self.rec([proc(4242, LW)], intent=(N1, "R"))
        act.EXIT_CODES[4242] = 0  # reaped from a child this process never spawned as R
        self.one_pass(self.ctx(rec))
        self.assertEqual(self.exits("R rc=0"), [])
        self.assertNotEqual(rec.substate, "IN-FLIGHT")
        [(_, rc)] = settle.dead_actuators(
            [proc(4242, LW)], {4242: 0}, lambda p: None, {}, [], N1
        )
        self.assertIsNone(rc)

    def test_06b_an_own_code_is_accepted_under_its_nonce_and_popped_once(self):
        spawned, codes = {4242: N1}, {4242: 0}
        [(_, rc)] = settle.dead_actuators(
            [proc(4242, LW)], codes, None, spawned, [], N1
        )
        self.assertEqual((rc, codes, spawned), (0, {}, {}))
        [(_, rc)] = settle.dead_actuators(
            [proc(4242, LW, nonce=N2)], {4242: 0}, None, {4242: N1}, [], N2
        )
        self.assertIsNone(rc)  # the same pid under another spawn's nonce: not ours

    def test_07_reap_children_keeps_codes_only_for_spawned_pids(self):
        """RED: the waitpid(-1) loop filed every reaped child's code under its pid."""
        p = subprocess.Popen(["/usr/bin/true"])  # not via act.spawn; never polled
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            act.reap_children()
            try:
                os.kill(p.pid, 0)
            except ProcessLookupError:
                break
            time.sleep(0.05)
        self.assertNotIn(p.pid, act.EXIT_CODES)
        p.returncode = 0  # reaped by waitpid(-1); keep Popen.__del__ quiet

    def test_15_exit_files_older_than_7d_are_reaped_at_startup(self):
        fresh_root = T.Paths(lr_root=self.tmp, root=os.path.join(self.tmp, "fresh"))
        store.ensure_dirs(fresh_root)  # the wrapper writes only into an existing exits/
        self.assertTrue(os.path.isdir(os.path.join(fresh_root.root, "exits")))
        old = self.exit_file(N1, 0, age=act.ACTLOG_MAX_AGE_S + 3600)
        fresh = self.exit_file(N2, 6, age=60)
        self.startup(self.ctx())
        self.assertFalse(os.path.exists(old))
        self.assertTrue(os.path.exists(fresh))

    def test_17_real_wrapper_writes_the_childs_code(self):
        """RED (no file). The real /bin/bash 3.2 wrapper, as spawn runs it."""
        env = {k: v for k, v in os.environ.items() if k != "LR_RECON_ROOT"}
        env["LR_RECON_ROOT"] = self.paths.root
        rec = self.rec()
        for child, want in (("exit 0", 0), ("exit 6", 6), ("kill -TERM $$", 143)):
            with self.subTest(child):
                nonce = os.urandom(6).hex()
                p = subprocess.Popen(
                    act.wrap(rec, nonce, ["/bin/sh", "-c", child]),
                    env=env,
                    start_new_session=True,
                )
                self.assertEqual(p.wait(timeout=60), want)
                with open(os.path.join(self.exits_dir, nonce + ".rc")) as fh:
                    self.assertEqual(fh.read(), "%d\n" % want)
                self.assertEqual(
                    act.read_exit(self.paths, proc(1, "", nonce=nonce)), want
                )

    def test_17b_no_exits_dir_or_a_non_hex_nonce_writes_nothing(self):
        env = dict(os.environ, LR_RECON_ROOT=os.path.join(self.tmp, "no-such-root"))
        p = subprocess.Popen(
            act.wrap(self.rec(), "n1", ["/bin/sh", "-c", "exit 6"]), env=env
        )
        self.assertEqual(p.wait(timeout=60), 6)
        env["LR_RECON_ROOT"] = self.paths.root
        p = subprocess.Popen(
            act.wrap(self.rec(), "../x", ["/bin/sh", "-c", "exit 6"]), env=env
        )
        self.assertEqual(p.wait(timeout=60), 6)
        self.assertEqual(os.listdir(self.exits_dir), [])
        self.assertFalse(os.path.exists(os.path.join(self.paths.root, "x.rc")))

    def test_17c_read_exit_refuses_a_non_hex_nonce(self):
        """S-11 hygiene: the nonce comes from a record file and is checked before it is a path."""
        self.exit_file(N1, 6)
        sneaky = proc(1, "", nonce="../exits/" + N1)
        self.assertIsNone(act.read_exit(self.paths, sneaky))
        self.assertEqual(act.read_exit(self.paths, proc(1, "")), 6)

    def test_18_a_real_orphaned_wrapper_is_scored_by_the_next_daemon(self):
        """RED: `code unknown`. The §1.3 reproduction: a daemon spawns R and dies; launchd (here:
        pid 1) reaps the wrapper; this process, the next daemon, settles it from the file."""
        rec = self.rec(intent=None)
        self.log(rec)
        store.save_record(self.paths, rec, self.now)
        code = (
            "import os,sys; sys.path.insert(0, %r)\n"
            "from lr_recon import act, store, types as T\n"
            "p = T.Paths.from_env(root=%r)\n"
            "rec = store.load_record(p, %r)\n"
            "env = dict(os.environ, LR_RECON_ROOT=p.root)\n"
            "pid = act.spawn(p, rec, 'R', ['/bin/sh', '-c', 'sleep 2; exit 6'], env, 0.0)\n"
            "print(pid, flush=True)\n"
            "os._exit(0)\n" % (LR_DIR, self.paths.root, SID)
        )
        out = subprocess.run(
            ["/usr/bin/python3", "-B", "-c", code],
            capture_output=True,
            text=True,
            timeout=120,
        )
        self.assertEqual(out.returncode, 0, out.stderr)
        wpid = int(out.stdout.split()[0])
        ppid = subprocess.run(
            ["/bin/ps", "-o", "ppid=", "-p", str(wpid)], capture_output=True, text=True
        ).stdout.strip()
        deadline = time.monotonic() + 120
        while time.monotonic() < deadline:
            try:
                os.kill(wpid, 0)
            except ProcessLookupError:
                break
            time.sleep(0.1)
        self.assertIn(
            ppid, ("1", ""), "the dead daemon's wrapper is reparented to launchd"
        )
        ctx = self.ctx(*store.load_all(self.paths, lambda p, r: None).values())
        self.one_pass(ctx)
        [d] = self.exits()
        self.assertTrue(d.startswith("R rc=6 → "), d)
        self.assertEqual(ctx.records[SID].attempt, 2)


class WakeBookkeeping(unittest.TestCase):
    """A6 (d): wake_eta stays after spawn (it is set only once the wake was really typed) and is
    saved right there, not at the pass end. On test_main's held-lead world."""

    LEAD = TM.MainTests.LEAD
    _held = TM.MainTests._held
    _due = TM.MainTests._due
    tearDown = TM.MainTests.tearDown

    def setUp(self):
        TM.MainTests.setUp(self)
        env = mock.patch.dict(os.environ, {"LR_RECON_ROOT": self.paths.root})
        env.start()
        self.addCleanup(env.stop)

    def test_14b_the_wake_eta_is_on_disk_before_the_pass_ends(self):
        """Mutant: drop the save after the wake_eta block → the disk lacks it."""
        ctx, snap, r = self._held()
        self.assertEqual(M._wakes(ctx, snap, {}, self._due()), 1)
        real, fake = act.spawn, mock.Mock(pid=4243, spec=["pid"])

        def spawn(paths, rec, which, argv, env, now):
            return real(
                paths,
                rec,
                which,
                argv,
                env,
                now,
                popen=lambda *a, **k: fake,
                lstart_of=lambda p: LW,
            )

        with mock.patch.object(M.act, "spawn", side_effect=spawn):
            self.assertEqual(M._dispatch(ctx, snap, "act", self._due()), 1)
        act._SPAWNED.pop(4243, None)
        self.assertEqual(r.close.get("wake_eta"), 1000.0)
        self.assertEqual(
            store.load_record(self.paths, self.LEAD).close.get("wake_eta"), 1000.0
        )


class SpawnBookkeeping(unittest.TestCase):
    """test 14 on test_launcher_rooted's world, where a real R is planned and dispatched."""

    world = W.InPlaceTests.world
    tearDown = W.InPlaceTests.tearDown

    def setUp(self):
        W.InPlaceTests.setUp(self)
        env = mock.patch.dict(os.environ, {"LR_RECON_ROOT": self.paths.root})
        env.start()
        self.addCleanup(env.stop)
        for target, value in (("probe", (True, "admit")), ("mint_token", None)):
            p = mock.patch("lr_recon.admit.Admission." + target, return_value=value)
            p.start()
            self.addCleanup(p.stop)
        for p in (self.paths.autorecover_on, self.paths.recon_autorecover_on):
            os.makedirs(os.path.dirname(p), exist_ok=True)
            open(p, "w").close()

    def test_14_spawn_bookkeeping_is_on_disk_before_the_pass_ends(self):
        """RED: move_attempt was set after spawn and reached disk only at save_records, so a pass
        killed in between let the next move re-use the attempt (S-8). Mutant: set it after spawn."""
        ctx, snap, _rec, facts = self.world(answered=False)
        del ctx.records[W.SID]  # the census writes the record itself
        M._census(ctx, snap, facts, [], "act", W.NOW)
        M._derive(ctx, snap, W.NOW, facts)
        offer = {W.SID: T.Placement(acct="next2", weight=1)}
        with (
            mock.patch.object(plan, "place", return_value=(offer, 0)),
            mock.patch.object(plan, "write_plan"),
            mock.patch.object(M, "_cfg_of", return_value=lambda a: "/cfg/" + a),
        ):
            M._plan(ctx, snap, facts, "act", W.NOW)
        real, fake = act.spawn, mock.Mock(pid=4242, spec=["pid"])

        def spawn(paths, rec, which, argv, env, now):
            return real(
                paths,
                rec,
                which,
                argv,
                env,
                now,
                popen=lambda *a, **k: fake,
                lstart_of=lambda p: LW,
            )

        with (
            mock.patch.object(M.act, "spawn", side_effect=spawn),
            mock.patch.object(M.os, "getloadavg", return_value=(0.0, 0.0, 0.0)),
        ):
            self.assertEqual(M._dispatch(ctx, snap, "act", W.NOW), 1)
        act._SPAWNED.pop(4242, None)
        rec = ctx.records[W.SID]
        on_disk = store.load_record(self.paths, W.SID)
        self.assertEqual(on_disk.close.get("move_attempt"), rec.attempt)
        self.assertEqual(on_disk.procs[0].nonce, on_disk.intent.nonce)


# ── (c) the claim keeper and the startup stamp: tests 8-13 and the review cases ────────────────


class ClaimKeeper(Base):
    def test_08_restart_with_a_live_inherited_actuator_hands_it_the_claim(self):
        """RED: today the startup re-stamps every open claim to the new daemon."""
        rec = self.rec([proc(WPID, LW)], intent=(N1, "R"))
        self.claim(OLD, LOLD)
        ctx = self.ctx(rec)
        self.startup(ctx)
        self.assertEqual(self.holder(), (WPID, LW))
        [ev] = self.events("claim-inherited")
        self.assertIn("started by the last daemon", ev["detail"])
        ctx = self.ctx(store.load_record(self.paths, SID) or rec, keeper=True)
        ctx.records[SID].procs = [proc(WPID, LW)]
        self.one_pass(ctx, self.snap(wrapper_row(ppid=1)))
        self.assertEqual(self.holder(), (WPID, LW))

    def test_08b_a_slow_first_census_still_restamps_before_dispatch(self):
        """py8b (F-I): `ps` takes 35 s (inside PS_BOUND_MAX_S) and the first pass must still hand
        the claim over before _dispatch. The keeper reads its own identity off the census row, so
        it pays no second ps: _keep_claims, run with the shim first on PATH and no cached identity,
        must finish well under 35 s. The shim is scoped to the keeper's call: the pass's only other
        PATH ps is _own_and_charge's, after the keeper (measured: one call, 35 s of suite time)."""
        shim = os.path.join(self.tmp, "bin")
        os.makedirs(shim)
        with open(os.path.join(shim, "ps"), "w") as fh:
            fh.write('#!/bin/bash\nsleep 35\nexec /bin/ps "$@"\n')
        os.chmod(os.path.join(shim, "ps"), 0o755)
        rec = self.rec(
            intent=(N1, "R")
        )  # intent-only: the wrapper's pid is unknown to startup
        self.claim(OLD, LOLD)
        self.startup(self.ctx(rec))
        self.assertEqual(
            self.holder(), (OLD, LOLD), "intent-only: left for the first pass"
        )
        seen, took = [], []
        real = M._keep_claims

        def timed(ctx, snap):
            t0 = time.monotonic()
            with (
                mock.patch.dict(
                    os.environ, {"PATH": shim + ":" + os.environ.get("PATH", "")}
                ),
                mock.patch.object(act, "_SELF_LSTART", (0, "")),
            ):
                real(ctx, snap)
            took.append(time.monotonic() - t0)

        ctx = self.ctx(rec, keeper=True)
        with mock.patch.object(M, "_keep_claims", side_effect=timed):
            self.one_pass(
                ctx,
                self.snap(wrapper_row(ppid=1)),
                act_mode=True,
                dispatch=lambda *a: seen.append(self.holder()) or 0,
            )
        self.assertEqual(seen, [(WPID, LW)])
        self.assertLess(took[0], 20.0)
        self.assertEqual(
            [p.argv_hash for p in ctx.records[SID].procs], ["R"], "adopted by its nonce"
        )

    def test_09_the_claim_returns_to_the_daemon_when_the_wrapper_dies(self):
        """RED (no keeper): in the pass the wrapper's death is seen, before _dispatch."""
        rec = self.rec([proc(WPID, LW)], intent=(N1, "R"))
        self.log(rec)
        self.claim(WPID, LW)
        self.exit_file(N1, 6)
        seen = []
        ctx = self.ctx(rec, keeper=True)
        self.one_pass(
            ctx,
            self.snap(),
            act_mode=True,
            dispatch=lambda *a: seen.append(self.holder()) or 0,
        )
        self.assertEqual(seen, [(os.getpid(), LME)])
        self.assertEqual(len(self.exits()), 1)  # and the exit settled in the same pass
        [ev] = self.events("claim-restamp")
        self.assertIn("this daemon", ev["detail"])

    def test_10_own_child_keeps_the_daemon_as_holder(self):
        """CONTROL (green both). Mutant: drop the ppid test in claim_holder_for → fails."""
        rec = self.rec([proc(WPID, LW)], intent=(N1, "R"))
        self.claim(os.getpid(), LME)
        self.one_pass(
            self.ctx(rec, keeper=True), self.snap(wrapper_row(ppid=os.getpid()))
        )
        self.assertEqual(self.holder(), (os.getpid(), LME))
        self.assertEqual(self.events("claim-restamp"), [])

    def test_10b_an_adopted_descendant_never_gets_the_claim(self):
        """CONTROL on the 4fe9935f shape (F-A): no restart, W dead, an adopted descendant D alive
        whose ppid is not the daemon → the claim is unchanged. Mutant: allow adopted → fails."""
        rec = self.rec(
            [proc(WPID, LW), proc(4301, LW, name="adopted", nonce="")],
            intent=(N1, "R"),
        )
        self.claim(os.getpid(), LME)
        self.one_pass(self.ctx(rec, keeper=True), self.snap(descendant_row(ppid=1)))
        self.assertEqual(self.holder(), (os.getpid(), LME))

    def test_11_keeper_never_writes_another_records_or_an_absent_claim(self):
        """CONTROL. Mutants: an absent claim is taken; the on-disk record_id is trusted."""
        rec = self.rec([proc(WPID, LW)], intent=(N1, "R"))
        snap = self.snap(wrapper_row(ppid=1))
        me = (os.getpid(), LME)
        self.assertEqual(act.keep_claim(self.paths, rec, snap, me), ("", ""))
        self.assertIsNone(store.read_claim(self.paths, SID), "absent stays absent")
        self.claim(OLD, LOLD, record_id="lane:cc-lr:abcdef01")
        self.assertEqual(act.keep_claim(self.paths, rec, snap, me), ("", ""))
        self.assertEqual(self.holder(), (OLD, LOLD))
        self.assertEqual(
            store.read_claim(self.paths, SID).record_id, "lane:cc-lr:abcdef01"
        )

    def test_11b_keep_claim_never_raises_and_reports_a_lost_race(self):
        """S-6: a steal renames the claim dir mid-write → unknown, retried; a re-read naming
        someone else → claim-race. Mutant: drop the OSError guard → the pass would crash."""
        rec = self.rec([proc(WPID, LW)], intent=(N1, "R"))
        self.claim(OLD, LOLD)
        snap, me = self.snap(wrapper_row(ppid=1)), (os.getpid(), LME)
        with mock.patch.object(
            act.store, "claim_restamp", side_effect=FileNotFoundError
        ):
            self.assertEqual(act.keep_claim(self.paths, rec, snap, me), ("", ""))
        thief = T.RunClaimHolder(pid=9, lstart="x", owner="lr-fleet", record_id=RID)
        real = store.read_claim
        calls = []

        def reads(paths, sid):
            calls.append(1)
            return real(paths, sid) if len(calls) == 1 else thief

        with mock.patch.object(act.store, "read_claim", side_effect=reads):
            ev, detail = act.keep_claim(self.paths, rec, snap, me)
        self.assertEqual(ev, "claim-race")
        self.assertIn("9 by lr-fleet", detail)

    def test_12_idle_record_is_restamped_at_startup_as_before(self):
        """CONTROL (green both): no procs, no intent → the new daemon."""
        self.claim(OLD, LOLD)
        self.startup(self.ctx(self.rec()))
        self.assertEqual(self.holder(), (os.getpid(), LME))
        self.assertEqual(self.events("claim-inherited"), [])

    def test_12b_an_intent_only_record_is_not_restamped_to_the_new_daemon(self):
        """RED (F-B): killed between Popen and the procs save, its wrapper may be live; the claim
        is left for the first pass. An lstart-less old claim is never left (S-1)."""
        self.claim(OLD, LOLD)
        self.startup(self.ctx(self.rec(intent=(N1, "R"))))
        self.assertEqual(self.holder(), (OLD, LOLD))
        self.claim(OLD, "")
        self.startup(self.ctx(self.rec(intent=(N1, "R"))))
        self.assertEqual(self.holder(), (os.getpid(), LME))

    def test_12c_an_unfenced_record_with_a_live_inherited_wrapper_reads_held(self):
        """S-1: a C record has a claim but no owned/<sid> fence, and lr-unstrand takes the claim
        without the fence. With a LIVE inherited wrapper named in the claim, a taker reads held."""
        live = subprocess.Popen(["/bin/sleep", "60"], start_new_session=True)
        self.addCleanup(lambda: (live.kill(), live.wait()))
        lw = store.proc_lstart(live.pid)
        self.assertTrue(lw, "a live process has an lstart")
        rec = self.rec(
            [proc(live.pid, lw, name="C")], intent=(N1, "C"), substate="UNPROMPTED"
        )
        self.assertIsNone(store.read_fence(self.paths, SID))
        self.claim(OLD, LOLD)
        self.startup(self.ctx(rec))
        self.assertEqual(self.holder(), (live.pid, lw))
        taker = T.RunClaimHolder(
            pid=os.getpid(), lstart=LME, owner="lr-unstrand", record_id="x"
        )
        verdict = store.claim_take(
            self.paths, SID, taker, M._alive, act._argv_of, self.now
        )
        self.assertEqual(verdict, "held")

    def test_12d_a_claim_stolen_mid_restamp_never_crashes_startup(self):
        """S-6 at startup: a steal renamed the claim dir under the re-stamp; the daemon starts."""
        self.claim(OLD, LOLD)
        with mock.patch.object(M.store, "claim_restamp", side_effect=FileNotFoundError):
            self.startup(self.ctx(self.rec([proc(WPID, LW)], intent=(N1, "R"))))
            self.startup(self.ctx(self.rec()))
        self.assertEqual(self.holder(), (OLD, LOLD))

    def test_13_kill_switches(self):
        """claim-keeper.off: the holder is always the daemon — startup re-stamps to itself, and a
        claim naming a live W is handed BACK (S-7), never to W. exit-files.off: the reader is off."""
        open(self.paths.p(act.KEEPER_OFF), "w").close()
        rec = self.rec([proc(WPID, LW)], intent=(N1, "R"))
        self.claim(OLD, LOLD)
        self.startup(self.ctx(rec))
        self.assertEqual(self.holder(), (os.getpid(), LME))
        self.claim(WPID, LW)
        self.one_pass(self.ctx(rec, keeper=True), self.snap(wrapper_row(ppid=1)))
        self.assertEqual(self.holder(), (os.getpid(), LME))
        self.exit_file(N1, 6)
        self.assertEqual(act.read_exit(self.paths, proc(1, "")), 6)
        open(self.paths.p(act.EXITS_OFF), "w").close()
        self.assertIsNone(act.read_exit(self.paths, proc(1, "")))

    def test_13b_once_and_test_passes_never_run_the_keeper(self):
        """S-2: only daemon() sets ctx.keeper, after its flock. Mutant: default it on → fails."""
        rec = self.rec([proc(WPID, LW)], intent=(N1, "R"))
        self.claim(OLD, LOLD)
        ctx = M.Ctx(self.paths, None, self.home)
        ctx.records = {SID: rec}
        self.one_pass(ctx, self.snap(wrapper_row(ppid=1)))
        self.assertEqual(self.holder(), (OLD, LOLD))

    def test_13c_the_daemon_writes_its_heartbeat_before_the_startup_claim_loop(self):
        """F-E ii: the new heartbeat is on disk when _startup runs, and the keeper is on after."""

        class Stop(Exception):
            pass

        with open(self.paths.heartbeat, "w") as fh:
            json.dump(
                {"pid": OLD, "lstart": LOLD, "progress_wall": self.now - 1000}, fh
            )
        at_startup = []
        real = M._startup

        def startup(ctx, me=None, prev=None):
            with open(self.paths.heartbeat) as fh:
                at_startup.append((json.load(fh).get("pid"), (prev or {}).get("pid")))
            real(ctx, me, prev)

        ctx = M.Ctx(self.paths, None, self.home)
        with (
            mock.patch.object(M, "_startup", side_effect=startup),
            mock.patch.object(M, "run_pass", return_value={"open": 0}),
            mock.patch.object(M, "wait_for_change", side_effect=Stop),
        ):
            with self.assertRaises(Stop):
                M.daemon(ctx)
        self.assertEqual(at_startup, [(os.getpid(), OLD)])
        self.assertTrue(ctx.keeper)
        with open(self.paths.restarts) as fh:
            row = json.loads(fh.readlines()[-1])
        self.assertEqual(row["prev_pid"], OLD)


# ── exactly-once under the review's shapes: F10/S-3, S-5, S-9, S-11 ────────────────────────────


class ExactlyOnce(Base):
    def test_f10_an_lstart_less_spawn_is_repaired_not_duplicated(self):
        """RED (S-3): spawn's lstart read timed out, so the entry has lstart "". The argv scan
        repairs that entry in place; it does not append a second one carrying the same nonce."""
        rec = self.rec([proc(WPID, "")], intent=(N1, "R"))
        act.adopt(rec, self.snap(wrapper_row(ppid=os.getpid())))
        self.assertEqual(
            [(p.pid, p.lstart, p.nonce) for p in rec.procs], [(WPID, LW, N1)]
        )

    def test_f10_the_duplicate_shape_is_scored_exactly_once(self):
        """RED (S-3 model: attempt 3 after one spawn and one exit). W exits between the census
        and _derive: pass 1's census still shows it, its file already exists."""
        rec = self.rec([proc(WPID, "")], intent=(N1, "R"))
        self.log(rec)
        self.exit_file(N1, 6)
        ctx = self.ctx(rec)
        self.one_pass(ctx, self.snap(wrapper_row(ppid=os.getpid())))
        self.one_pass(ctx, self.snap())
        self.assertEqual(len(self.exits()), 1)
        self.assertEqual(rec.attempt, 2)

    def test_a_dead_entry_whose_nonce_a_live_entry_carries_is_not_settled(self):
        """S-3 reader half. Mutant: drop the duplicate rule in settle.superseded → scored."""
        rec = self.rec([proc(WPID, ""), proc(WPID, LW)], intent=(N1, "R"))
        self.log(rec)
        self.exit_file(N1, 6)
        self.one_pass(self.ctx(rec), self.snap(wrapper_row(ppid=os.getpid())))
        self.assertEqual(self.exits(), [])
        self.assertEqual(rec.attempt, 1)
        [ev] = self.events("stale-exit")
        self.assertIn("duplicate", ev["detail"])

    def test_a_stale_spawns_exit_is_never_scored_against_the_newer_one(self):
        """RED in effect (S-5): an old R died on a pass that `continue`d before the settle, and a
        new A was spawned under a new intent. The old file must not bump the new attempt.
        Mutant: drop the stale rule (want) in settle.superseded → `R rc=6` is scored."""
        rec = self.rec(
            [proc(4242, LW), proc(4400, LME, name="A", nonce=N2)], intent=(N2, "A")
        )
        self.log(rec)
        self.exit_file(N1, 6)
        row = wrapper_row(pid=4400, nonce=N2, ppid=os.getpid(), lstart=LME)
        self.one_pass(self.ctx(rec), self.snap(row))
        self.assertEqual(self.exits(), [])
        self.assertEqual(rec.attempt, 1)
        [ev] = self.events("stale-exit")
        self.assertIn("stale", ev["detail"])
        self.assertEqual([p.pid for p in rec.procs], [4400])

    def test_an_intent_only_exit_is_settled_once_under_the_intents_actuator(self):
        """RED (S-9): killed between Popen and the procs save, and the wrapper ended before any
        census saw it. Mutant: drop the intent_only_exit call → the exit is lost."""
        rec = self.rec(intent=(N1, "R"))
        self.log(rec)
        self.exit_file(N1, 6)
        ctx = self.ctx(rec)
        self.one_pass(ctx)
        self.one_pass(ctx)
        [d] = self.exits()
        self.assertTrue(d.startswith("R rc=6 → "), d)
        self.assertEqual(rec.attempt, 2)
        self.assertIsNone(rec.intent)

    def test_s11_an_old_exit_after_a_move_that_proved_moved_stays_open(self):
        """S-11 stale phase (a pin; green at HEAD too, where the code was unknown): the old daemon
        last saved MOVED, and its R's exit file says 1. The phase decides; nothing escalates."""
        rec = self.rec([proc(4242, LW)], intent=(N1, "R"))
        rec.phase = "MOVED"
        self.log(rec, "lr-handoff: watcher engagement wait timed out\n")
        self.exit_file(N1, 1)
        self.one_pass(self.ctx(rec))
        self.assertTrue(rec.open)
        self.assertFalse(rec.escalated)
        self.assertEqual(rec.attempt, 1)
        self.assertIn("R rc=1 after MOVED — the phase decides", self.exits("R rc=1"))


# ── (e) forensics and (f) the pass-boundary restart request ────────────────────────────────────


class Restarts(Base):
    def _rows(self):
        with open(self.paths.restarts, encoding="utf-8") as fh:
            return [json.loads(x) for x in fh if x.strip()]

    def test_16_restart_row_names_previous_daemon_and_inflight(self):
        rec = self.rec([proc(WPID, LW)], intent=(N1, "R"))
        self.claim(OLD, LOLD)
        prev = {
            "pid": OLD,
            "lstart": "Thu Jan 1 00:00:00 2026",
            "progress_wall": self.now - 100,
        }
        self.startup(self.ctx(rec), prev)
        row = self._rows()[-1]
        self.assertEqual((row["inflight"], row["inherited"]), (1, ["abcdef01:R"]))
        self.assertEqual(row["prev_phase"], {"abcdef01": "PRE-MOVE"})
        self.assertEqual(row["prev_pid"], OLD)
        self.assertGreaterEqual(row["prev_progress_age_s"], 99)
        self.assertIs(row["code_newer_than_prev"], True)
        self.assertIsInstance(row["code_mtime"], int)
        self.startup(self.ctx(), {"pid": OLD, "lstart": "Fri Jan 1 00:00:00 2100"})
        self.assertIs(self._rows()[-1]["code_newer_than_prev"], False)
        self.startup(self.ctx(), {})  # no heartbeat: never raises
        self.assertEqual(self._rows()[-1]["prev_pid"], 0)
        self.assertNotIn("code_newer_than_prev", self._rows()[-1])

    def test_restart_request_is_inert_until_ruled(self):
        req = os.path.join(self.paths.ctl, M.RESTART_REQUEST)
        open(req, "w").close()
        self.assertFalse(M._restart_requested(self.paths))
        self.assertTrue(os.path.exists(req))
        open(self.paths.p(M.RESTART_REQUEST_ON), "w").close()
        self.assertTrue(M._restart_requested(self.paths))
        self.assertFalse(os.path.exists(req))
        self.assertEqual(self._rows()[-1]["cause"], "requested")
        self.assertFalse(M._restart_requested(self.paths), "one request, one restart")

    def test_a_requested_restart_and_its_startup_row_never_page(self):
        """S-11: both rows are exempt. Mutant: drop the exemption → it pages."""
        rows = [
            {"t": self.now - 100, "pid": 1},
            {"t": self.now - 60, "pid": 1, "cause": "requested"},
            {"t": self.now - 50, "pid": 2},
        ]
        with open(self.paths.restarts, "w") as fh:
            fh.write("".join(json.dumps(r) + "\n" for r in rows))
        self.assertFalse(M._restart_loop(self.paths, self.now))
        with open(self.paths.restarts, "a") as fh:
            fh.write(json.dumps({"t": self.now - 20, "pid": 3}) + "\n")
        self.assertFalse(
            M._restart_loop(self.paths, self.now), "one unexplained restart"
        )
        with open(self.paths.restarts, "a") as fh:
            fh.write(json.dumps({"t": self.now - 10, "pid": 4}) + "\n")
        self.assertTrue(
            M._restart_loop(self.paths, self.now), "a real loop still pages"
        )


if __name__ == "__main__":
    unittest.main()
