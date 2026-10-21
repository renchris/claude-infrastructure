"""B4 R1 (W10): the reconciler hands ``--place`` the holds map from its kept ProjectsIndex.

``--place`` globbed ``<cfg>/projects/*/<sid>.jsonl`` per mover per account with room: an lstat in
each of ~18,300 project dirs per store, ~64% of its CPU (B4 §1.2). The reconciler already keeps an
index that gives the glob's answer, so ``plan.with_holds`` ships ``{acct: [config_dir, bool]}`` and
``--place`` trusts an entry whose config_dir realpath matches its own (W3, c79df708d).

The map must be the glob's answer (R1), absent rather than wrong whenever it cannot be computed on
the loop thread (R2, R3, the SSOT cases), exact on every pass (R4: no different-slug lag), honest
about its one window (R4b: a copy written after the pass's walk reads False until the next pass),
and cheap: at most one walk per store per pass however many movers (R5)."""

import contextlib
import json
import os
import subprocess
import threading
from unittest import mock

from lr_recon import plan as P
from lr_recon import transcript as X
from lr_recon import types as T
from lr_recon.tests.test_projects_index import SIDS, Tree, old_glob


def _noop():
    return None


class FakeRun:
    """Captures the --movers file plan.place writes (test_plan.FakeRun's shape)."""

    def __init__(self, out="{}"):
        self.out, self.movers = out, ""

    def __call__(self, argv, **kw):
        with open(argv[argv.index("--movers") + 1]) as fh:
            self.movers = fh.read()
        return subprocess.CompletedProcess(argv, 0, self.out, "")


class Holds(Tree):
    def setUp(self):
        super().setUp()
        self.home = os.path.join(self.tmp, "home")
        os.makedirs(os.path.join(self.home, ".claude"))
        self.acj = os.path.join(self.tmp, "accounts.json")
        self.env = mock.patch.dict(
            os.environ,
            {
                "HOME": self.home,
                "LR_STATE_DIR": os.path.join(self.tmp, "lr"),
                "CLAUDE_ACCOUNTS_JSON": self.acj,
            },
        )
        self.env.start()
        self.addCleanup(self.env.stop)
        os.environ.pop("LR_RECON_PLACE_HOLDS", None)
        self.amap = {"one": self.a, "two": self.b, "three": self.c}

    def write_accounts(self, path, amap):
        with open(path, "w") as fh:
            json.dump(
                {"accounts": [{"name": n, "config_dir": c} for n, c in amap.items()]},
                fh,
            )

    def mvs(self, sids):
        return [T.Mover(sid=s, src="one") for s in sids]

    def want(self, sid):
        return {a: [c, bool(old_glob(c, sid + ".jsonl"))] for a, c in self.amap.items()}

    def idx(self, **kw):
        kw.setdefault("step_fn", _noop)
        return X.ProjectsIndex(**kw)


class R1TheMapIsTheGlobs(Holds):
    def test_every_sid_and_store(self):
        self.build()
        with X.pass_index(self.idx()):
            got = P.with_holds(self.mvs(SIDS), self.amap)
        for m in got:
            self.assertEqual(m.holds, self.want(m.sid), m.sid)
        flat = [v[1] for m in got for v in m.holds.values()]
        self.assertTrue(any(flat) and not all(flat), "the fixture has both answers")
        # the shared store (.claude-next's projects/ IS .claude's) answers alike under both names
        self.assertTrue(all(m.holds["one"][1] == m.holds["two"][1] for m in got))
        self.assertEqual([m.sid for m in got], SIDS, "order and every other field kept")


class R2NoIndexNoMap(Holds):
    def test_a_bare_call_returns_the_movers_unchanged(self):
        self.build()
        mvs = self.mvs(SIDS[:2])
        got = P.with_holds(mvs, self.amap)
        self.assertEqual(got, mvs)
        self.assertTrue(all(m.holds is None for m in got))
        fr = FakeRun()
        P.place("general", got, "/f", {}, run=fr)
        for line in fr.movers.splitlines():
            self.assertNotIn("holds", json.loads(line))

    def test_off_its_thread_it_returns_none_and_raises_nothing(self):
        """R7's mutant in miniature: the index belongs to the thread that opened the pass."""
        self.build()
        box = {}

        def worker():
            try:
                box["got"] = P.with_holds(self.mvs(SIDS[:2]), self.amap)
            except BaseException as e:  # noqa: BLE001 - the property is "raises nothing"
                box["exc"] = e

        with X.pass_index(self.idx()):
            t = threading.Thread(target=worker)
            t.start()
            t.join(10)
        self.assertNotIn("exc", box)
        self.assertTrue(all(m.holds is None for m in box["got"]))


class R3KillSwitches(Holds):
    def test_env_off_file_off_and_an_empty_map_leave_movers_unchanged(self):
        self.build()
        mvs = self.mvs(SIDS[:2])
        with X.pass_index(self.idx()):
            self.assertEqual(P.with_holds(mvs, {}), mvs)
            self.assertEqual(P.with_holds(mvs, self.amap, off=True), mvs)
            with mock.patch.dict(os.environ, {"LR_RECON_PLACE_HOLDS": "off"}):
                self.assertEqual(P.with_holds(mvs, self.amap), mvs)
            on = P.with_holds(
                mvs, self.amap
            )  # control: the same call with every switch on
        self.assertTrue(all(m.holds is not None for m in on))


class SsotAccounts(Holds):
    """The map is keyed over the accounts.json --place itself reads (B4 review F5)."""

    def test_claude_accounts_json_first_then_home(self):
        self.write_accounts(self.acj, {"one": self.a})
        self.write_accounts(
            os.path.join(self.home, ".claude", "accounts.json"), {"zz": self.c}
        )
        self.assertEqual(P.holds_amap(), {"one": self.a})
        os.environ.pop("CLAUDE_ACCOUNTS_JSON")
        self.assertEqual(P.holds_amap(), {"zz": self.c})

    def test_unreadable_accounts_json_means_no_holds_key(self):
        self.build()
        with open(self.acj, "w") as fh:
            fh.write("{not json")
        self.assertEqual(P.holds_amap(), {})
        with X.pass_index(self.idx()):
            got = P.with_holds(self.mvs(SIDS[:2]), P.holds_amap())
        fr = FakeRun()
        P.place("general", got, "/f", {}, run=fr)
        self.assertTrue(fr.movers)
        for line in fr.movers.splitlines():
            self.assertNotIn("holds", json.loads(line))


class R6RoundTrip(Holds):
    def test_a_mover_with_holds_reaches_the_movers_file_in_w3s_shape(self):
        self.build()
        with X.pass_index(self.idx()):
            got = P.with_holds(self.mvs(SIDS[:1]), self.amap)
        fr = FakeRun()
        P.place("general", got, "/f", {}, run=fr)
        [row] = [json.loads(x) for x in fr.movers.splitlines()]
        self.assertEqual(row["holds"], self.want(SIDS[0]))
        for ent in row["holds"].values():  # bin/claude-accounts cmd_place's trust test
            self.assertTrue(isinstance(ent[0], str) and isinstance(ent[1], bool))


class R4ExactEveryPass(Holds):
    def test_a_copy_at_the_source_slug_in_another_store_is_true_next_pass(self):
        self.build()
        sid = SIDS[5]
        self.put(self.a, "-w-src", sid + ".jsonl")
        idx = self.idx()
        with X.pass_index(idx):
            [m] = P.with_holds(self.mvs([sid]), self.amap)
        self.assertEqual(m.holds["three"][1], False)
        self.put(self.c, "-w-src", sid + ".jsonl")
        with X.pass_index(idx):
            [m] = P.with_holds(self.mvs([sid]), self.amap)
        self.assertEqual(m.holds, self.want(sid))
        self.assertEqual(m.holds["three"][1], True)

    def test_a_copy_in_an_old_untouched_dir_is_true_next_pass_not_within_roll_passes(
        self,
    ):
        """The index's one documented lag (a different-slug copy, seen only by the 1/ROLL_PASSES
        slice) is gone for the holds map: every pass with movers re-walks each store once."""
        self.build()
        sid = SIDS[5]
        self.put(
            self.c, "-w-old", "unrelated.jsonl"
        )  # an old dir, never touched by a lookup
        for i in range(3):
            self.put(self.c, "-w-pad%d" % i, "x.jsonl")

        @contextlib.contextmanager
        def scan(path):
            """-w-old listed last, so the slice (one dir a pass at a million passes, cursor 0
            then 1) provably never reaches it in two passes; only a full walk does."""
            with os.scandir(path) as it:
                ents = list(it)
            if os.path.basename(path) == "projects":
                ents.sort(key=lambda e: (e.name == "-w-old", e.name))
            yield iter(ents)

        idx = self.idx(roll_passes=10**6, scandir_fn=scan)
        with X.pass_index(idx):
            [m] = P.with_holds(self.mvs([sid]), self.amap)
        self.assertEqual(m.holds["three"][1], False)
        self.put(self.c, "-w-old", sid + ".jsonl")
        with X.pass_index(idx):
            [m] = P.with_holds(self.mvs([sid]), self.amap)
        self.assertEqual(m.holds["three"], [self.c, True])


class R4bTheIntraPassWindow(Holds):
    def test_a_copy_after_the_pass_walk_reads_false_then_true_with_no_observe_call(
        self,
    ):
        """The map answers as of each store's walk in the pass, not as of --place (B4 review F1).
        No find_transcript, observe or touch is made: the next pass's walk alone turns it True."""
        self.build()
        sid = SIDS[5]
        idx = self.idx(roll_passes=10**6)
        with X.pass_index(idx):
            P.with_holds(
                self.mvs([SIDS[0]]), self.amap
            )  # this pass's walk of every store
            self.put(self.c, "-w-later", sid + ".jsonl")  # a new dir, after the walk
            self.put(
                self.a, "-w-zzz", sid + ".jsonl"
            )  # an existing dir, after the walk
            [m] = P.with_holds(self.mvs([sid]), self.amap)
            self.assertEqual(
                (m.holds["one"][1], m.holds["three"][1]), (False, False), "the window"
            )
        with X.pass_index(idx):
            [m] = P.with_holds(self.mvs([sid]), self.amap)
        self.assertEqual(m.holds, self.want(sid))
        self.assertEqual((m.holds["one"][1], m.holds["three"][1]), (True, True))


class R5OneWalkPerStorePerPass(Holds):
    def counted(self):
        seen = []

        def stat(p):
            seen.append(p)
            return os.stat(p)

        return seen, self.idx(stat_fn=stat)

    def test_40_new_names_make_at_most_one_walk_per_store(self):
        self.build()
        for i in range(30):  # enough dirs that a second walk is unmistakable
            self.put(self.c, "-w-pad%02d" % i, "x.jsonl")
        new = ["00000000-0000-4000-9000-%012d" % i for i in range(40)]
        seen, idx = self.counted()
        with X.pass_index(idx):  # pass 1: the sweep the daemon already pays at start
            for cfg in (self.a, self.c):
                X.in_projects(cfg, SIDS[0] + ".jsonl")
        for n in (
            2,
            3,
        ):  # pass 3 asks the same names again: still exactly one walk, no more
            del seen[:]
            with X.pass_index(idx):
                got = P.with_holds(self.mvs(new), self.amap)
            self.assertTrue(all(m.holds for m in got))
            per = {}
            for p in seen:
                per[p] = per.get(p, 0) + 1
            dirs = {
                p: k for p, k in per.items() if os.path.dirname(p).endswith("/projects")
            }
            self.assertGreaterEqual(len(dirs), 30, "pass %d walked every store" % n)
            # 1 stat from the walk, +1 for the dirs the refresh already visited (hot set and the
            # 1/ROLL_PASSES slice). A walk per mover (40) or per lookup (120 over 3 accounts) is
            # far above it, and so is a second walk of the store.
            self.assertLessEqual(max(dirs.values()), 2, "pass %d" % n)
            self.assertGreater(
                sum(1 for k in dirs.values() if k == 1),
                len(dirs) // 2,
                "one walk, not two",
            )
