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


if __name__ == "__main__":
    unittest.main()
