"""The per-pass projects/ index (transcript.ProjectsIndex): the globs' answers at O(dirs) cost.

2026-10-19: every sid lookup globbed ``<cfg>/projects/*/<sid><suffix>``, an lstat per project dir;
with ~18,300 dirs per store and ~1,500 lookups a pass, the live reconciler sat ~80 min per pass in
lstat. The index must answer every lookup the globs answered (same paths, same order) and pay one
directory read per project dir per store per pass, however many sessions it is asked about."""

import glob
import os
import shutil
import tempfile
import threading
import unittest
from unittest import mock

from lr_recon import __main__ as M
from lr_recon import census, evidence
from lr_recon import transcript as X

SIDS = ["00000000-0000-4000-8000-%012d" % i for i in range(1, 7)]
SUFFIXES = (".jsonl", ".jsonl.handed-off", ".HANDOFF.json")


def old_glob(cfg, name, escape=True):
    """The expression every call site used before the index."""
    base = glob.escape(cfg) if escape else cfg
    return sorted(glob.glob(os.path.join(base, "projects", "*", name)))


class Tree(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.a = os.path.join(self.tmp, ".claude")
        self.b = os.path.join(self.tmp, ".claude-next")  # projects/ is a symlink to a's
        self.c = os.path.join(self.tmp, ".claude-tertiary")
        os.makedirs(self.b)
        os.symlink(os.path.join(self.a, "projects"), os.path.join(self.b, "projects"))

    def put(self, cfg, project, name, body="{}\n"):
        d = os.path.join(cfg, "projects", project)
        os.makedirs(d, exist_ok=True)
        p = os.path.join(d, name)
        with open(p, "w") as fh:
            fh.write(body)
        return p

    def build(self):
        s1, s2, s3, s4, s5, _ = SIDS
        for proj in (
            "-w-zzz",
            "-w-aaa",
            "-w-mmm",
        ):  # one sid in three dirs: order matters
            self.put(self.a, proj, s1 + ".jsonl")
        self.put(self.a, "-w-aaa", s2 + ".jsonl.handed-off")
        self.put(
            self.a, "-w-aaa", s2 + ".HANDOFF.json", '{"handed_off_to": "%s"}' % self.c
        )
        self.put(self.a, "-w-bbb", s2 + ".HANDOFF.json", "{}")
        self.put(self.c, "-w-ccc", s2 + ".jsonl")
        self.put(self.a, ".hidden", s3 + ".jsonl")  # glob's * skips dot-dirs
        self.put(self.a, "-w-aaa", s3 + ".txt")  # not an indexed suffix
        with open(os.path.join(self.a, "projects", s4 + ".jsonl"), "w"):
            pass  # a FILE directly under projects/: * matches it, but it is not a dir
        os.symlink(  # a dangling symlink: glob's lexists counts it
            os.path.join(self.tmp, "gone"),
            os.path.join(self.a, "projects", "-w-mmm", s4 + ".jsonl"),
        )
        os.makedirs(os.path.join(self.tmp, "real-proj"))
        with open(os.path.join(self.tmp, "real-proj", s5 + ".jsonl"), "w"):
            pass
        os.symlink(  # a symlinked project dir: * follows it
            os.path.join(self.tmp, "real-proj"),
            os.path.join(self.a, "projects", "-w-link"),
        )
        locked = os.path.dirname(
            self.put(self.a, "-w-locked", s5 + ".HANDOFF.json", "{}")
        )
        os.chmod(locked, 0o100)  # searchable, not listable: glob still lstats into it
        self.addCleanup(os.chmod, locked, 0o700)

    def names(self):
        return [sid + suf for sid in SIDS for suf in SUFFIXES]


class Equivalence(Tree):
    def test_index_answers_every_lookup_the_glob_answered(self):
        self.build()
        cfgs = [
            self.a,
            self.b,
            self.c,
            self.a + "/",
            os.path.join(self.tmp, "absent"),
            "",
        ]
        want = {(c, n): old_glob(c, n) for c in cfgs for n in self.names()}
        self.assertTrue(
            any(len(v) == 3 for v in want.values())
        )  # the fixture has teeth
        self.assertTrue(any("-w-locked" in p for v in want.values() for p in v))
        self.assertTrue(any("/.claude-next/" in p for v in want.values() for p in v))
        with X.pass_index():
            got = {(c, n): X.in_projects(c, n) for c in cfgs for n in self.names()}
        self.assertEqual(got, want)

    def test_call_sites_agree_inside_and_outside_a_pass(self):
        self.build()

        def answers():
            out = []
            for sid in SIDS:
                for cfgs in ([self.a], [self.b], [self.c], [self.c, self.a]):
                    out.append(X.find_transcript(cfgs, "/w/none", sid))
                    out.append(X.locate(cfgs, "/w/none", sid))
                for cfg in (self.a, self.b, self.c, ""):
                    out.append(evidence.transcript_path(cfg, "/w/none", sid))
                    out.append(census._has_copy(cfg, sid))
                    out.append(census.successor_state(sid, cfg, None, {}))
            return out

        outside = answers()
        self.assertIn(
            os.path.join(self.a, "projects", "-w-aaa", SIDS[0] + ".jsonl"), outside
        )
        with X.pass_index():
            inside = answers()
        self.assertEqual(inside, outside)

    def test_a_hit_removed_after_the_sweep_is_not_served(self):
        self.build()
        with X.pass_index():
            first = X.in_projects(self.a, SIDS[0] + ".jsonl")
            os.unlink(first[0])
            self.assertEqual(X.in_projects(self.a, SIDS[0] + ".jsonl"), first[1:])

    def test_the_index_serves_only_the_thread_that_opened_it(self):
        self.build()
        seen = []
        idx = X.ProjectsIndex(scandir_fn=lambda p: self.fail("swept off-thread"))
        with X.pass_index(idx):
            t = threading.Thread(
                target=lambda: seen.append(X.in_projects(self.a, SIDS[0] + ".jsonl"))
            )
            t.start()
            t.join()
        self.assertEqual(seen, [old_glob(self.a, SIDS[0] + ".jsonl")])

    def test_run_pass_opens_one_index_and_closes_it(self):
        seen = []
        with mock.patch.object(
            M, "_run_pass", lambda ctx, fo: seen.append(X._ACTIVE) or {}
        ):
            M.run_pass(None)
        self.assertIsInstance(seen[0][0], X.ProjectsIndex)
        self.assertIsNone(X._ACTIVE)


class Cost(Tree):
    M_DIRS = 600

    def test_n_sessions_over_m_dirs_cost_m_directory_reads(self):
        for i in range(self.M_DIRS):
            os.makedirs(os.path.join(self.a, "projects", "-w-%04d" % i))
        self.put(self.a, "-w-0007", SIDS[0] + ".jsonl")
        reads, probes, steps = [], [], []

        def scandir(p):
            reads.append(p)
            return os.scandir(p)

        def lexists(p):
            probes.append(p)
            return os.path.lexists(p)

        idx = X.ProjectsIndex(scandir, lexists, lambda: steps.append(1))
        nope = AssertionError("glob inside a pass")
        with X.pass_index(idx), mock.patch.object(glob, "glob", side_effect=nope):
            # N = 30 lookups per name, through both spellings of one store
            for sid in SIDS * 5:
                for cfg in (self.a, self.b):
                    for suf in SUFFIXES:
                        X.in_projects(cfg, sid + suf)
        self.assertEqual(len(reads), self.M_DIRS + 1)  # projects/ once, each dir once
        self.assertEqual(len(probes), 2 * 5)  # only the one hit, re-checked per lookup
        self.assertEqual(len(steps), self.M_DIRS // X.SWEEP_STEP_DIRS + 1)


class Kept(Tree):
    """The daemon keeps one index across passes (2026-10-20): a later pass re-reads only project
    dirs whose mtime moved, and every case where that could lag the full walk is bounded."""

    M_DIRS = 120
    ROLL = 6

    def setUp(self):
        super().setUp()
        for i in range(self.M_DIRS):
            os.makedirs(os.path.join(self.a, "projects", "-w-%04d" % i))
        self.reads, self.stats = [], []

        def scandir(p):
            self.reads.append(p)
            return os.scandir(p)

        def stat(p):
            self.stats.append(p)
            return os.stat(p)

        self.idx = X.ProjectsIndex(
            scandir, step_fn=lambda: None, stat_fn=stat, roll_passes=self.ROLL
        )

    def look(self, name, cfg=None):
        """One pass that asks for ``name``; the cost counters are reset at its start."""
        del self.reads[:], self.stats[:]
        with X.pass_index(self.idx):
            return X.in_projects(cfg or self.a, name)

    def bump(self, d):
        """Move a dir's mtime past the cached one, whatever the filesystem's timestamp grain."""
        st = os.stat(d)
        os.utime(d, ns=(st.st_atime_ns, st.st_mtime_ns + 10**9))

    def test_a_quiet_pass_reads_no_dir_and_stats_a_slice(self):
        self.put(self.a, "-w-0007", SIDS[0] + ".jsonl")
        self.look(SIDS[0] + ".jsonl")
        self.assertEqual(len(self.reads), self.M_DIRS + 1)  # the first pass sweeps
        got = self.look(SIDS[0] + ".jsonl")
        self.assertEqual(got, old_glob(self.a, SIDS[0] + ".jsonl"))
        self.assertEqual(self.reads, [])
        # projects/ + the touched dir + a 1/ROLL slice
        self.assertLessEqual(len(self.stats), 1 + 1 + self.M_DIRS // self.ROLL)

    def test_a_new_project_dir_is_seen_the_next_pass(self):
        """A brand-new session in a new cwd, no holder yet: projects/ moved, so it is relisted."""
        self.look(SIDS[1] + ".jsonl")
        self.put(self.a, "-w-new", SIDS[1] + ".jsonl")
        self.bump(os.path.join(self.a, "projects"))
        got = self.look(SIDS[1] + ".jsonl")
        self.assertEqual(got, old_glob(self.a, SIDS[1] + ".jsonl"))
        self.assertEqual(len(got), 1)
        real = os.path.realpath(os.path.join(self.a, "projects"))
        self.assertEqual(self.reads, [real, os.path.join(real, "-w-new")])

    def test_a_tombstone_beside_a_looked_up_transcript_is_seen_the_next_pass(self):
        """Mid-move: the sid's dir was touched by a lookup, so its rename is caught by mtime."""
        p = self.put(self.a, "-w-0050", SIDS[2] + ".jsonl")
        self.look(SIDS[2] + ".jsonl")
        os.rename(p, p + ".handed-off")
        self.put(self.a, "-w-0050", SIDS[2] + ".HANDOFF.json")
        self.bump(os.path.dirname(p))
        self.assertEqual(self.look(SIDS[2] + ".jsonl.handed-off"), [p + ".handed-off"])
        self.assertEqual(self.reads, [os.path.realpath(os.path.dirname(p))])
        self.assertEqual(self.look(SIDS[2] + ".jsonl"), [])

    def test_a_slug_direct_hit_marks_its_dir_for_the_next_pass(self):
        cwd = "/w/9999"
        d = os.path.join(self.a, "projects", X.slug(cwd))
        self.put(self.a, X.slug(cwd), "seed.jsonl")
        self.look(SIDS[3] + ".jsonl")
        p = self.put(self.a, X.slug(cwd), SIDS[3] + ".jsonl")
        self.bump(d)
        with X.pass_index(
            self.idx
        ):  # this pass finds it slug-direct, not through the index
            self.assertEqual(X.find_transcript([self.a], cwd, SIDS[3]), p)
        os.rename(p, p + ".handed-off")
        self.bump(d)
        self.assertEqual(self.look(SIDS[3] + ".jsonl.handed-off"), [p + ".handed-off"])

    def test_a_new_transcript_in_an_old_untouched_dir_is_seen_within_roll_passes(self):
        """The one rule that lags the full walk: a new file where no lookup looks. The rolling
        slice is the bounded full walk: it is seen within ROLL passes, never later."""
        name = SIDS[4] + ".HANDOFF.json"
        self.look(name)
        self.put(self.a, "-w-0099", name)
        self.bump(os.path.join(self.a, "projects", "-w-0099"))
        seen_at = None
        for n in range(1, self.ROLL + 1):
            if self.look(name):
                seen_at = n
                break
        self.assertIsNotNone(seen_at, "not seen within %d passes" % self.ROLL)
        self.assertEqual(self.look(name), old_glob(self.a, name))

    def test_a_live_sessions_transcript_never_waits_for_the_slice(self):
        """transcript.observe: a live session's slug-direct miss rechecks the whole store once."""
        self.look(SIDS[5] + ".jsonl")
        p = self.put(self.a, "-w-0099", SIDS[5] + ".jsonl")
        self.bump(os.path.dirname(p))
        with X.pass_index(self.idx):
            obs = X.observe(self.a, "/w/elsewhere", SIDS[5])
            X.observe(self.a, "/w/elsewhere", SIDS[4])  # a warm session with no transcript yet
        self.assertEqual(obs.path, p)
        del self.stats[:]
        with X.pass_index(self.idx):  # asked again every pass: no second whole-store recheck
            X.observe(self.a, "/w/elsewhere", SIDS[4])
        self.assertLess(len(self.stats), self.M_DIRS)

    def test_removed_dirs_and_files_drop_out(self):
        p = self.put(self.a, "-w-0003", SIDS[0] + ".jsonl")
        self.assertEqual(self.look(SIDS[0] + ".jsonl"), [p])
        os.unlink(p)
        os.rmdir(os.path.dirname(p))
        self.bump(os.path.join(self.a, "projects"))
        self.assertEqual(self.look(SIDS[0] + ".jsonl"), [])
        self.assertNotIn(
            "-w-0003",
            self.idx._stores[os.path.realpath(os.path.join(self.a, "projects"))].mtimes,
        )

    def test_after_roll_passes_every_answer_equals_the_glob(self):
        self.build()
        cfgs = [self.a, self.b, self.c, os.path.join(self.tmp, "absent")]
        with X.pass_index(self.idx):
            for c in cfgs:
                X.in_projects(c, SIDS[0] + ".jsonl")
        # churn everywhere, then let the slice come round once
        self.put(self.a, "-w-0042", SIDS[1] + ".jsonl")
        self.put(self.c, "-w-ccc", SIDS[3] + ".HANDOFF.json")
        os.unlink(os.path.join(self.a, "projects", "-w-zzz", SIDS[0] + ".jsonl"))
        for d in ("-w-0042", "-w-zzz"):
            self.bump(os.path.join(self.a, "projects", d))
        self.bump(os.path.join(self.c, "projects", "-w-ccc"))
        for _ in range(self.ROLL):
            with X.pass_index(self.idx):
                for c in cfgs:
                    X.in_projects(c, SIDS[0] + ".jsonl")
        want = {(c, n): old_glob(c, n) for c in cfgs for n in self.names()}
        with X.pass_index(self.idx):
            got = {(c, n): X.in_projects(c, n) for c in cfgs for n in self.names()}
        self.assertEqual(got, want)

    def test_the_daemon_keeps_one_index_across_passes(self):
        seen = []
        ctx = mock.Mock(projects=self.idx)
        with mock.patch.object(
            M, "_run_pass", lambda c, fo: seen.append(X._ACTIVE[0]) or {}
        ):
            M.run_pass(ctx)
            M.run_pass(ctx)
        self.assertEqual(seen, [self.idx, self.idx])
        self.assertEqual(self.idx._pass, 2)


if __name__ == "__main__":
    unittest.main()
