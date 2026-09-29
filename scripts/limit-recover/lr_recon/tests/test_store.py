"""store.py: atomic compact writes, quarantine, fence, run-claim interop, locks, logs, requests."""

import json
import os
import shutil
import subprocess
import tempfile
import time
import unittest
from typing import List, Tuple

from lr_recon import store as S
from lr_recon import types as T

SID = "0f1e2d3c-4b5a-6978-8a9b-0c1d2e3f4a5b"
SID2 = "11111111-2222-3333-4444-555555555555"
LSTART = "Tue Sep 29 06:19:17 2026"
LR_LIB = os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.realpath(__file__)))),
    "lr-lib.sh",
)


def dead(pid: int, lstart: str) -> bool:
    return False


def live(pid: int, lstart: str) -> bool:
    return True


def no_argv(pid: int) -> str:
    return ""


class Base(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.mkdtemp(prefix="lr-recon-store-")
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.paths = T.Paths(lr_root=self.tmp, root=os.path.join(self.tmp, "recon"))
        S.ensure_dirs(self.paths)

    def holder(
        self, rid: str = "recon:c1:0f1e2d3c:1", pid: int = 4242
    ) -> T.RunClaimHolder:
        return T.RunClaimHolder(pid=pid, lstart=LSTART, owner=S.BY, record_id=rid)

    def write_holder(self, sid: str, obj: dict) -> str:
        d = S.claim_dir(self.paths, sid)
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, "holder"), "w") as fh:
            fh.write(json.dumps(obj) + "\n")
        return d


class AtomicAndDirs(Base):
    def test_json_is_compact(self) -> None:
        p = os.path.join(self.tmp, "x.json")
        S.atomic_write_json(p, {"pid": 5, "record_id": "r"})
        with open(p) as fh:
            self.assertEqual(fh.read(), '{"pid":5,"record_id":"r"}\n')
        self.assertEqual(
            [n for n in os.listdir(self.tmp) if n.startswith(".x.json")], []
        )

    def test_ensure_dirs_creates_only_reconciler_tree(self) -> None:
        self.assertEqual(sorted(os.listdir(self.tmp)), ["recon"])
        for d in self.paths.reconciler_dirs():
            self.assertTrue(os.path.isdir(d))
            self.assertEqual(os.stat(d).st_mode & 0o777, 0o700)


class Records(Base):
    def test_round_trip_stamps_updated_at(self) -> None:
        rec = T.Record(sid=SID, record_id="recon:c1:0f1e2d3c:1", pane=(3, 4))
        S.save_record(self.paths, rec, now=123.0)
        back = S.load_record(self.paths, SID)
        self.assertIsNotNone(back)
        assert back is not None
        self.assertEqual(back.updated_at, 123.0)
        self.assertEqual(back, rec)
        self.assertIsNone(S.load_record(self.paths, SID2))

    def test_corrupt_records_quarantined_others_load(self) -> None:
        S.save_record(self.paths, T.Record(sid=SID, record_id="r1"))
        with open(os.path.join(self.paths.sessions, "bad-json.json"), "w") as fh:
            fh.write("{not json")
        with open(os.path.join(self.paths.sessions, SID2 + ".json"), "w") as fh:
            fh.write('["a list is not a record"]')
        bad: List[Tuple[str, str]] = []
        got = S.load_all(self.paths, lambda p, r: bad.append((p, r)))
        self.assertEqual(list(got), [SID])
        self.assertEqual(
            sorted(os.path.basename(p) for p, _ in bad),
            sorted(["bad-json.json", SID2 + ".json"]),
        )
        q = sorted(os.listdir(self.paths.quarantine))
        self.assertEqual(
            sorted(n.rsplit(".", 1)[0] for n in q),
            sorted(["bad-json.json", SID2 + ".json"]),
        )
        self.assertTrue(all(n.rsplit(".", 1)[1].isdigit() for n in q))
        self.assertEqual(sorted(os.listdir(self.paths.sessions)), [SID + ".json"])

    def test_load_all_survives_raising_on_bad(self) -> None:
        with open(os.path.join(self.paths.sessions, SID + ".json"), "w") as fh:
            fh.write('{"sid":"%s"}' % SID)  # no record_id ⇒ not a record

        def boom(p: str, r: str) -> None:
            raise RuntimeError("callback bug")

        self.assertEqual(S.load_all(self.paths, boom), {})


class Fence(Base):
    def test_own_update_release(self) -> None:
        f = T.FenceFile("r1", 1)
        self.assertTrue(S.own(self.paths, SID, f))
        self.assertTrue(S.own(self.paths, SID, f))  # owner re-entry is a no-op
        self.assertFalse(S.own(self.paths, SID, T.FenceFile("r2", 1)))
        self.assertFalse(S.update_fence(self.paths, SID, T.FenceFile("r2", 2)))
        procs = [T.ProcRole("actuator", 9, LSTART)]
        self.assertTrue(S.update_fence(self.paths, SID, T.FenceFile("r1", 2, procs)))
        back = S.read_fence(self.paths, SID)
        assert back is not None
        self.assertEqual((back.attempt, back.procs[0].pid), (2, 9))
        self.assertFalse(S.release_fence(self.paths, SID, "r2"))
        self.assertTrue(S.release_fence(self.paths, SID, "r1"))
        self.assertIsNone(S.read_fence(self.paths, SID))
        self.assertEqual(os.listdir(self.paths.owned), [])


class RunClaim(Base):
    def test_taken_then_ours_then_release(self) -> None:
        h = self.holder()
        self.assertEqual(S.claim_take(self.paths, SID, h, dead, no_argv), "taken")
        self.assertEqual(S.claim_take(self.paths, SID, h, dead, no_argv), "ours")
        with open(os.path.join(S.claim_dir(self.paths, SID), "holder")) as fh:
            raw = fh.read()
        self.assertIn('"pid":4242', raw)
        self.assertIn('"record_id":"recon:c1:0f1e2d3c:1"', raw)
        obj = json.loads(raw)
        self.assertEqual((obj["by"], obj["owner"], obj["pane"]), (S.BY, S.BY, "-"))
        self.assertRegex(obj["ts"], r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$")
        self.assertFalse(S.claim_release(self.paths, SID, "other"))
        self.assertTrue(S.claim_release(self.paths, SID, h.record_id))
        self.assertFalse(os.path.exists(S.claim_dir(self.paths, SID)))

    def test_lstart_holder_live_held_dead_stolen(self) -> None:
        self.write_holder(
            SID, {"pid": 77, "lstart": LSTART, "owner": S.BY, "record_id": "x"}
        )
        self.assertEqual(
            S.claim_take(self.paths, SID, self.holder(), live, no_argv), "held"
        )
        self.assertEqual(
            S.claim_take(self.paths, SID, self.holder(), dead, no_argv), "stolen-dead"
        )
        cur = S.read_claim(self.paths, SID)
        assert cur is not None
        self.assertEqual(cur.pid, 4242)

    def test_legacy_holder_rule(self) -> None:
        legacy = {
            "sid": SID,
            "pane": "-",
            "pid": 88,
            "ts": "2026-09-29T00:00:00Z",
            "by": "cc-lr",
        }
        self.write_holder(SID, legacy)
        named = lambda pid: "bash /x/bin/cc-lr switch %s" % SID  # noqa: E731
        self.assertEqual(
            S.claim_take(self.paths, SID, self.holder(), live, named), "held"
        )
        wrong_sid = lambda pid: "bash /x/limit-recover/lr-fleet.sh --one %s" % SID2  # noqa: E731
        self.assertEqual(
            S.claim_take(self.paths, SID, self.holder(), live, wrong_sid),
            "stolen-legacy",
        )
        self.write_holder(SID2, dict(legacy, sid=SID2))
        unrelated = lambda pid: "/usr/bin/vim notes-%s.txt" % SID2  # noqa: E731
        self.assertEqual(
            S.claim_take(self.paths, SID2, self.holder(), live, unrelated),
            "stolen-legacy",
        )

    def test_orphan_grace(self) -> None:
        d = S.claim_dir(self.paths, SID)
        os.makedirs(d)
        self.assertEqual(
            S.claim_take(self.paths, SID, self.holder(), dead, no_argv), "held"
        )
        old = time.time() - 60
        os.utime(d, (old, old))
        self.assertEqual(
            S.claim_take(self.paths, SID, self.holder(), dead, no_argv), "stolen-orphan"
        )

    def test_lost_race_restores_the_peers_claim(self) -> None:
        d = self.write_holder(SID, {"pid": 77, "lstart": LSTART, "record_id": "x"})

        def dead_then_peer_restamps(pid: int, lstart: str) -> bool:
            with open(
                os.path.join(d, "holder"), "w"
            ) as fh:  # a peer steals between judge and act
                fh.write('{"pid":99,"lstart":"%s","record_id":"peer"}' % LSTART)
            return False

        self.assertEqual(
            S.claim_take(
                self.paths, SID, self.holder(), dead_then_peer_restamps, no_argv
            ),
            "lost-race",
        )
        cur = S.read_claim(self.paths, SID)
        assert cur is not None
        self.assertEqual(cur.record_id, "peer")
        self.assertEqual(
            [n for n in os.listdir(self.paths.runs_by_sid) if "stolen" in n], []
        )

    def test_restamp_only_ours(self) -> None:
        h = self.holder()
        S.claim_take(self.paths, SID, h, dead, no_argv)
        self.assertFalse(S.claim_restamp(self.paths, SID, "other", 5, "L"))
        self.assertTrue(S.claim_restamp(self.paths, SID, h.record_id, 5150, "L2"))
        cur = S.read_claim(self.paths, SID)
        assert cur is not None
        self.assertEqual(
            (cur.pid, cur.lstart, cur.record_id), (5150, "L2", h.record_id)
        )

    def _bash(self, script: str) -> subprocess.CompletedProcess:
        env = {"PATH": "/usr/bin:/bin", "HOME": self.tmp, "LR_STATE_DIR": self.tmp}
        try:
            cp = subprocess.run(
                ["bash", "-c", script],
                capture_output=True,
                text=True,
                env=env,
                timeout=30,
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            self.skipTest("bash unavailable: %s" % exc)
        if "LR_SOURCE_FAILED" in cp.stdout:
            self.skipTest("sourcing lr-lib.sh failed: %s" % cp.stderr.strip()[:200])
        return cp

    def test_landed_bash_reader_parses_our_holder(self) -> None:
        if not os.path.isfile(LR_LIB):
            self.skipTest("lr-lib.sh not found at %s" % LR_LIB)
        S.claim_take(self.paths, SID, self.holder(pid=31337), dead, no_argv)
        d = S.claim_dir(self.paths, SID)
        cp = self._bash(
            'source "$1" || { echo LR_SOURCE_FAILED; exit 0; }; lr_claim_holder_pid "$2"'.replace(
                "$1", LR_LIB
            ).replace("$2", d)
        )
        self.assertEqual(cp.stdout.strip(), "31337", cp.stderr)

    def test_we_parse_the_landed_bash_stamp(self) -> None:
        if not os.path.isfile(LR_LIB):
            self.skipTest("lr-lib.sh not found at %s" % LR_LIB)
        d = S.claim_dir(self.paths, SID)
        os.makedirs(d)
        self._bash(
            'source "%s" || { echo LR_SOURCE_FAILED; exit 0; }; lr_claim_stamp "%s" "%s" 2468 cc-lr'
            % (LR_LIB, d, SID)
        )
        cur = S.read_claim(self.paths, SID)
        assert cur is not None
        self.assertEqual((cur.pid, cur.lstart, cur.record_id), (2468, "", ""))


class WriteOrder(Base):
    def rec(self) -> T.Record:
        return T.Record(sid=SID, record_id="recon:c1:0f1e2d3c:1", attempt=1)

    def test_claim_held_writes_nothing_else(self) -> None:
        self.write_holder(SID, {"pid": 77, "lstart": LSTART, "record_id": "other"})
        v = S.take_ownership(
            self.paths, self.rec(), self.holder(), live, no_argv, now=5.0
        )
        self.assertEqual(v, "held")
        self.assertIsNone(S.read_fence(self.paths, SID))
        self.assertFalse(os.path.exists(S.record_path(self.paths, SID)))

    def test_success_writes_claim_owned_and_record_with_intent(self) -> None:
        v = S.take_ownership(
            self.paths, self.rec(), self.holder(rid=""), dead, no_argv, now=5.0
        )
        self.assertEqual(v, "taken")
        cur = S.read_claim(self.paths, SID)
        assert cur is not None
        self.assertEqual(cur.record_id, "recon:c1:0f1e2d3c:1")
        fence = S.read_fence(self.paths, SID)
        assert fence is not None
        self.assertEqual(
            (fence.record_id, fence.attempt, fence.procs), (cur.record_id, 1, [])
        )
        back = S.load_record(self.paths, SID)
        assert back is not None and back.intent is not None
        self.assertEqual((back.intent.at, back.updated_at), (5.0, 5.0))

    def test_owned_by_other_releases_the_claim(self) -> None:
        self.assertTrue(S.own(self.paths, SID, T.FenceFile("someone-else", 1)))
        v = S.take_ownership(
            self.paths, self.rec(), self.holder(), dead, no_argv, now=5.0
        )
        self.assertEqual(v, "owned-by-other")
        self.assertFalse(os.path.exists(S.claim_dir(self.paths, SID)))
        self.assertFalse(os.path.exists(S.record_path(self.paths, SID)))


class Locks(Base):
    def lh(self, rid: str = "r1", pid: int = 10) -> T.LockHolder:
        return T.LockHolder(
            record_id=rid, attempt=1, role="launch", pid=pid, lstart=LSTART, at=1.0
        )

    def test_take_held_steal_release(self) -> None:
        d = S.launch_lock(self.paths, SID)
        self.assertEqual(S.lock_take(d, self.lh(), live), "taken")
        self.assertEqual(S.lock_take(d, self.lh("r2", 11), live), "held")
        self.assertEqual(S.lock_take(d, self.lh("r2", 11), dead), "stolen-dead")
        h = S.lock_holder(d)
        assert h is not None
        self.assertEqual((h.record_id, h.pid), ("r2", 11))
        self.assertFalse(S.lock_release(d, "r1"))
        self.assertTrue(S.lock_release(d, "r2"))
        self.assertFalse(os.path.exists(d))

    def test_lock_paths(self) -> None:
        import hashlib

        sha = hashlib.sha1(b"/tmp/kitty.sock:7").hexdigest()
        self.assertEqual(
            S.recycle_lock(self.paths, "/tmp/kitty.sock", 7),
            os.path.join(self.tmp, "locks", "pane-%s.recycle" % sha),
        )
        self.assertEqual(
            S.lock_path(self.paths, "recycle", "/tmp/kitty.sock:7"),
            S.recycle_lock(self.paths, "/tmp/kitty.sock", 7),
        )
        g = hashlib.sha1(b"/repo/.git").hexdigest()
        self.assertEqual(
            S.git_lock(self.paths, "/repo/.git"),
            os.path.join(self.tmp, "locks", "git-" + g),
        )
        self.assertEqual(
            S.lock_path(self.paths, "launch", SID),
            os.path.join(self.tmp, "locks", SID + ".launch"),
        )

    def test_proc_lstart_seam(self) -> None:
        seen = {}

        class CP:
            def __init__(self, rc: int, out: str) -> None:
                self.returncode, self.stdout = rc, out

        def fake(argv, **kw):  # type: ignore[no-untyped-def]
            seen.update(argv=argv, env=kw["env"])
            return CP(0, " %s \n" % LSTART)

        self.assertEqual(S.proc_lstart(42, run=fake), LSTART)
        self.assertEqual(seen["argv"], ["ps", "-o", "lstart=", "-p", "42"])
        self.assertEqual((seen["env"]["TZ"], seen["env"]["LC_ALL"]), ("UTC", "C"))
        self.assertEqual(S.proc_lstart(42, run=lambda a, **k: CP(1, "")), "")


class Logs(Base):
    def test_rotation_keeps_one_generation(self) -> None:
        p = os.path.join(self.paths.root, "t.log")
        for i in range(200):
            S.append_bounded(p, "line %03d %s" % (i, "x" * 40), 1000)
        self.assertTrue(os.path.exists(p + ".1"))
        self.assertFalse(os.path.exists(p + ".2"))
        self.assertLessEqual(os.path.getsize(p), 1000)
        self.assertLessEqual(os.path.getsize(p + ".1"), 1000)
        with open(p) as fh:
            self.assertIn("line 199", fh.read().splitlines()[-1])

    def test_event_lines_capped_and_valid(self) -> None:
        os.environ["LR_RECON_LOG_MAX_BYTES"] = "4096"
        self.addCleanup(os.environ.pop, "LR_RECON_LOG_MAX_BYTES", None)
        for detail in ("d" * 5000, 'é☃"\\\n' * 900, "short"):
            for _ in range(5):
                S.append_event(
                    self.paths, T.Event(t=1.0, ev="launch", sid=SID, detail=detail)
                )
        self.assertTrue(os.path.exists(self.paths.events + ".1"))
        for f in (self.paths.events, self.paths.events + ".1"):
            with open(f, "rb") as fh:
                for raw in fh.read().splitlines(keepends=True):
                    self.assertLessEqual(len(raw), S.EVENT_LINE_MAX)
                    self.assertEqual(json.loads(raw)["sid"], SID)
        self.assertLessEqual(os.path.getsize(self.paths.events), 4096)

    def test_launch_and_restart_wrappers(self) -> None:
        S.append_launch(self.paths, "fired\nsecond")
        S.append_restart(self.paths, {"pid": 1, "why": "x"})
        with open(self.paths.launch_log) as fh:
            self.assertEqual(fh.read(), "fired second\n")
        with open(self.paths.restarts) as fh:
            self.assertEqual(fh.read(), '{"pid":1,"why":"x"}\n')


class Requests(Base):
    def put(self, name: str, obj: object) -> None:
        with open(os.path.join(self.paths.requests, name), "w") as fh:
            fh.write(json.dumps(obj))

    def test_shape_dispatch_and_claim_moves(self) -> None:
        os.makedirs(self.paths.requests)
        self.put(SID + ".json", {"sid": SID, "at": 7})
        self.put(SID2 + ".cc-lr.json", {"sid": SID2})
        self.put("retire-husk-%s.json" % SID, {"sid": SID})
        self.put(
            "22222222-2222-3333-4444-555555555555.json", {"sid": SID}
        )  # sid mismatch
        self.put("33333333-2222-3333-4444-555555555555.json", ["not", "a", "dict"])
        with open(
            os.path.join(
                self.paths.requests, "44444444-2222-3333-4444-555555555555.json"
            ),
            "w",
        ) as fh:
            fh.write("{torn")
        reqs = S.list_requests(self.paths)
        self.assertEqual(
            [(r.sid, r.origin) for r in reqs], [(SID, "hook"), (SID2, "cc-lr")]
        )
        self.assertEqual(reqs[0].at, 7.0)
        dest = S.claim_request(self.paths, reqs[0], "adopted", "fresh", now=9.0)
        self.assertEqual(dest, os.path.join(self.paths.claimed, SID + ".json"))
        self.assertFalse(os.path.exists(reqs[0].path))
        with open(dest) as fh:
            moved = json.load(fh)
        self.assertEqual(
            moved["recon_outcome"], {"outcome": "adopted", "detail": "fresh", "at": 9.0}
        )
        self.assertEqual(moved["sid"], SID)
        self.assertEqual(S.claim_request(self.paths, reqs[0], "again"), "")
        self.put(
            SID + ".json", {"sid": SID}
        )  # a second request for the same sid never clobbers
        again = S.list_requests(self.paths)[0]
        dest2 = S.claim_request(self.paths, again, "dup", now=10.0)
        self.assertNotEqual(dest2, dest)
        self.assertTrue(os.path.exists(dest))

    def test_no_requests_dir(self) -> None:
        self.assertEqual(S.list_requests(self.paths), [])


if __name__ == "__main__":
    unittest.main()
