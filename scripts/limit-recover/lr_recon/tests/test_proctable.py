"""W1 (ZERO_HITL_ROTATION): the ps-free census — proctable.py and its observe/store/fence wiring.

Hermetic: the kernel, the argv reader, the tty map and ps are seams; every state tree is a temp
dir. The one live block (``LiveKernel``) reads only this test process's own row and argv.
"""

import json
import os
import shutil
import struct
import sys
import tempfile
import threading
import unittest
from dataclasses import replace as dc_replace
from types import SimpleNamespace
from typing import Dict, List
from unittest import mock

from lr_recon import fence
from lr_recon import observe as O
from lr_recon import observe_rows as R
from lr_recon import proctable as P
from lr_recon import store as S
from lr_recon import types as T

ME = 501
SEC = 1792998640  # Mon Oct 26 07:10:40 2026 UTC
LSTART = "Mon Oct 26 07:10:40 2026"


def kinfo(pid, ppid, comm, sec=SEC, usec=0, stat=2, tdev=-1, uid=ME) -> bytes:
    """One 648-byte kinfo_proc row at the offsets proctable reads."""
    b = bytearray(P.KINFO_SIZE)
    struct.pack_into("<qi", b, 0, sec, usec)
    b[36] = stat
    struct.pack_into("<i", b, 40, pid)
    c = comm.encode()[:16]
    b[243 : 243 + len(c)] = c
    struct.pack_into("<I", b, 420, uid)
    struct.pack_into("<i", b, 560, ppid)
    struct.pack_into("<i", b, 572, tdev)
    return bytes(b)


def snapshot(**kw) -> T.Snapshot:
    return T.Snapshot(wall=0.0, uptime_raw=0.0, **kw)


def krow(pid, ppid, comm, stat=2, tdev=-1, uid=ME, sec=SEC, usec=0) -> P.KRow:
    return P.KRow(pid, ppid, stat, sec, usec, tdev, uid, comm)


# a kitty with one pane: root-owned login → zsh → claude → bash (a tool) → sleep
TABLE = {
    1: krow(1, 0, "launchd", uid=0),
    100: krow(100, 1, "kitty"),
    200: krow(200, 100, "login", tdev=0x10000003, uid=0),
    300: krow(300, 200, "zsh", tdev=0x10000003),
    400: krow(400, 300, "claude.exe", tdev=0x10000003),
    500: krow(500, 400, "bash"),
    600: krow(600, 500, "sleep"),
    700: krow(700, 1, "postgres"),
    800: krow(800, 100, "zsh", stat=P.SZOMB),
}
ARGV = {
    100: [b"/Applications/kitty.app/Contents/MacOS/kitty"],
    300: [b"-zsh"],
    400: [b"claude", b"--resume", b"0123abcd-0000-4000-8000-0123456789ab"],
    500: [b"/bin/bash", b"-c", b"make test"],
    600: [b"sleep", b"30"],
    700: [b"postgres:", b"writer", b"   "],
}


def fake_reader(argv=ARGV, refuse=()):
    calls: List[int] = []

    def read(pid, keys):
        calls.append(pid)
        if pid in refuse or pid not in argv:
            return None
        return list(argv[pid]), {}

    read.calls = calls  # type: ignore[attr-defined]
    return read


def ttys_fn(tdevs):
    return (
        {0x10000003: "ttys003"} if 0x10000003 in {t & 0xFFFFFFFF for t in tdevs} else {}
    )


def table(reader=None, kern=None, recheck=None, **kw):
    return P.read_table(
        reader=P.ArgsReader(reader or fake_reader(), **kw),
        kern=kern or (lambda: dict(TABLE)),
        ttys_fn=ttys_fn,
        my_uid=ME,
        recheck=recheck or (lambda pid: TABLE.get(pid)),
    )


class Base(unittest.TestCase):
    def setUp(self) -> None:
        P._ARGS_CACHE.clear()
        P._STUCK.clear()
        self.dir = tempfile.mkdtemp(prefix="lr-proctable-")
        self.paths = T.Paths(lr_root=self.dir, root=os.path.join(self.dir, "recon"))

    def tearDown(self) -> None:
        shutil.rmtree(self.dir, ignore_errors=True)

    def shadow_rows(self) -> List[dict]:
        path = os.path.join(self.paths.shadow, P.SHADOW_LOG)
        if not os.path.exists(path):
            return []
        with open(path) as fh:
            return [json.loads(x) for x in fh]


class Parse(Base):
    def test_kinfo_fields_at_the_measured_offsets(self) -> None:
        raw = kinfo(42, 7, "claude.exe", usec=5, stat=P.SZOMB, tdev=0x10000003, uid=0)
        raw += kinfo(43, 42, "zsh")[:100]  # a torn trailing row is ignored
        rows = P.parse_kinfo(raw)
        self.assertEqual(list(rows), [42])
        r = rows[42]
        self.assertEqual(
            (r.pid, r.ppid, r.p_stat, r.sec, r.usec, r.tdev, r.uid, r.comm),
            (42, 7, P.SZOMB, SEC, 5, 0x10000003, 0, "claude.exe"),
        )

    def test_stat_letter_reads_only_zombie_and_stopped(self) -> None:
        self.assertEqual(
            [P.stat_letter(s) for s in (1, 2, 3, 4, 5)], ["S", "S", "S", "T", "Z"]
        )
        self.assertTrue(T.ProcRow(1, 0, P.stat_letter(P.SZOMB), "", "").zombie)

    def test_procargs2_keeps_only_the_env_keys_asked_for(self) -> None:
        raw = struct.pack("<i", 2) + b"/usr/bin/claude\0\0\0\0claude\0--resume\0"
        raw += b"HOME=/Users/x\0ANTHROPIC_API_KEY=secret\0KITTY_PID=100\0KITTY_WINDOW_ID=7\0\0"
        argv, env = P.parse_procargs2(raw, ("KITTY_PID", "KITTY_WINDOW_ID"))  # type: ignore[misc]
        self.assertEqual(argv, [b"claude", b"--resume"])
        self.assertEqual(env, {"KITTY_PID": "100", "KITTY_WINDOW_ID": "7"})
        argv2, env2 = P.parse_procargs2(raw)  # type: ignore[misc]
        self.assertEqual(env2, {})
        self.assertIsNone(P.parse_procargs2(b"\x01"))

    def test_render_follows_ps(self) -> None:
        self.assertEqual(P.render_args(None, "zsh", True), "<defunct>")
        self.assertEqual(P.render_args(None, "login", False), "(login)")
        self.assertEqual(
            P.render_args([b"  postgres:", b"writer", b"  "], "p", False),
            "postgres: writer",
        )

    def test_a_newline_in_an_owed_prompt_cannot_surface_a_resume_token(self) -> None:
        # ps vis-encodes TAB and NL, so prompt text stays glued to its token under args.split()
        argv = [b"claude", b"fix it\n--resume\t0123abcd-0000-4000-8000-0123456789ab"]
        for vis in (P.render_args, lambda a, c, z: P._strvis_py(b" ".join(a))):
            args = vis(argv, "claude", False)
            self.assertNotIn("\n", args)
            self.assertNotIn("\t", args)
            self.assertEqual(R.resume_sid(args), "", args)
        self.assertEqual(P._strvis_py(b"a\tb"), "a\\011b")


@unittest.skipUnless(
    sys.platform == "darwin", "uselocale/strvis are darwin libc's here"
)
class LocaleIsRestored(Base):
    """strvis runs in the C locale for its own call only: a caller left in C reads its codeset as
    ASCII, and every text open() and subprocess decode after it breaks (the whole suite, 32 errors,
    when the first version pinned the main thread)."""

    def test_the_callers_thread_locale_survives_a_render(self) -> None:
        import ctypes
        import locale

        lib = P._libc()
        lib.newlocale.restype = ctypes.c_void_p
        lib.newlocale.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_void_p]
        lib.uselocale.restype = ctypes.c_void_p
        lib.uselocale.argtypes = [ctypes.c_void_p]
        utf8 = lib.newlocale(63, b"en_US.UTF-8", None)
        if not utf8:
            self.skipTest("no en_US.UTF-8 locale here")
        old = lib.uselocale(utf8)
        try:
            self.assertEqual(locale.nl_langinfo(locale.CODESET), "UTF-8")
            self.assertEqual(P.render_args([b"a\tb"], "x", False), "a\\011b")
            self.assertEqual(locale.nl_langinfo(locale.CODESET), "UTF-8")
        finally:
            lib.uselocale(old)


class Ttys(Base):
    def test_cache_rescans_on_an_unknown_device_and_nodev_maps_nothing(self) -> None:
        P._TTY_CACHE.clear()
        listing = [("ttys003", 0x10000003), ("console", 0x0), ("disk0", 0x1000000)]
        scans: List[int] = []

        def scandir(_):
            scans.append(1)
            return [
                SimpleNamespace(
                    name=n,
                    stat=lambda follow_symlinks=False, r=r: SimpleNamespace(st_rdev=r),
                )
                for n, r in listing
            ]

        self.assertEqual(
            P.tty_map([0x10000003, P.NODEV], scandir), {0x10000003: "ttys003"}
        )
        self.assertEqual(P.tty_map([0x10000003], scandir), {0x10000003: "ttys003"})
        self.assertEqual(len(scans), 1)
        listing.append(("ttys004", 0x10000004))
        self.assertEqual(P.tty_map([0x10000004], scandir), {0x10000004: "ttys004"})
        self.assertEqual(len(scans), 2)
        self.assertNotIn(0x1000000, P._TTY_CACHE)


class Order(Base):
    def test_claude_first_and_critical_covers_pane_and_descendants(self) -> None:
        always, cacheable, critical = P.args_order(TABLE, ME)
        self.assertEqual(always[0], 400)
        self.assertEqual(set(always), {100, 300, 400, 500, 600})
        self.assertEqual(cacheable, [700])
        self.assertEqual(
            critical, {100, 300, 400, 500, 600, 800}
        )  # 800: a zombie pane shell, never read
        self.assertNotIn(200, always)  # root-owned: KERN_PROCARGS2 is EINVAL by design
        self.assertNotIn(800, always)  # a zombie has no argv to read


class Reader(Base):
    def test_a_stuck_call_is_abandoned_and_the_rest_still_read(self) -> None:
        gate = threading.Event()

        def read(pid, keys):
            if pid == 2:
                gate.wait(5)
            return [b"x%d" % pid], {}

        try:
            got, unread, st = P.ArgsReader(read, call_s=0.05, budget_s=2.0).read(
                [1, 2, 3]
            )
            self.assertEqual(unread, [2])
            self.assertEqual(sorted(got), [1, 3])
            self.assertEqual((st["deadline"], st["stuck"]), (1, 1))
        finally:
            gate.set()

    def test_at_stuck_max_no_new_reader_starts(self) -> None:
        gate = threading.Event()

        def read(pid, keys):
            gate.wait(5)
            return None

        try:
            got, unread, st = P.ArgsReader(
                read, call_s=0.02, budget_s=2.0, stuck_max=2
            ).read([1, 2, 3, 4])
            self.assertEqual(got, {})
            self.assertEqual(unread, [1, 2, 3, 4])
            self.assertEqual((st["calls"], st["skipped"]), (2, 2))
        finally:
            gate.set()

    def test_the_pass_budget_bounds_the_reads(self) -> None:
        t = [0.0]

        def read(pid, keys):
            t[0] += 1.0
            return [b"a"], {}

        got, unread, st = P.ArgsReader(
            read, call_s=5, budget_s=2.5, mono=lambda: t[0]
        ).read([1, 2, 3, 4, 5])
        self.assertEqual(sorted(got), [1, 2, 3])
        self.assertEqual(unread, [4, 5])


class Table(Base):
    def test_rows_match_the_ps_census_shape(self) -> None:
        procs, ttys, info = table()
        self.assertEqual(
            procs[400],
            T.ProcRow(
                400,
                300,
                "S",
                LSTART,
                "claude --resume 0123abcd-0000-4000-8000-0123456789ab",
            ),
        )
        self.assertEqual(
            procs[200].args, "(login)"
        )  # root row: lstart and tty still read
        self.assertEqual(procs[200].lstart, LSTART)
        self.assertEqual(ttys, {200: "ttys003", 300: "ttys003", 400: "ttys003"})
        self.assertTrue(procs[800].zombie)
        self.assertEqual(procs[800].args, "<defunct>")
        self.assertEqual(procs[700].args, "postgres: writer")
        self.assertEqual(info["critical_unread"], [])
        self.assertEqual(
            R.resume_leaves(procs), {"0123abcd-0000-4000-8000-0123456789ab": [400]}
        )

    def test_an_unread_claude_argv_is_named_never_trusted_as_comm(self) -> None:
        gate = threading.Event()
        inner = fake_reader()

        def read(pid, keys):
            if pid == 400:
                gate.wait(5)
            return inner(pid, keys)

        try:
            procs, _, info = table(reader=read, call_s=0.05)
        finally:
            gate.set()
        self.assertEqual(info["critical_unread"], [400])
        self.assertEqual(procs[400].args, "(claude.exe)")

    def test_a_refused_critical_row_that_exited_is_dropped_one_still_alive_is_named(
        self,
    ) -> None:
        procs, _, info = table(
            reader=fake_reader(refuse=(600,)), recheck=lambda pid: None
        )
        self.assertNotIn(600, procs)
        self.assertEqual((info["exited"], info["critical_unread"]), (1, []))
        procs, _, info = table(reader=fake_reader(refuse=(600,)))
        self.assertEqual(info["critical_unread"], [600])
        reused = lambda pid: TABLE[pid]._replace(sec=SEC + 9)  # noqa: E731
        procs, _, info = table(reader=fake_reader(refuse=(600,)), recheck=reused)
        self.assertNotIn(600, procs)

    def test_a_failed_recheck_is_not_proof_of_exit(self) -> None:
        def boom(pid):
            raise OSError(5, "EIO")

        procs, _, info = table(reader=fake_reader(refuse=(600,)), recheck=boom)
        self.assertIn(600, procs)
        self.assertEqual(info["critical_unread"], [600])

    def test_tier_four_is_cached_tiers_one_to_three_are_always_read(self) -> None:
        r1 = fake_reader()
        table(reader=r1)
        self.assertIn(700, r1.calls)  # type: ignore[attr-defined]
        r2 = fake_reader()
        procs, _, info = table(reader=r2)
        self.assertNotIn(700, r2.calls)  # type: ignore[attr-defined]
        self.assertIn(400, r2.calls)  # type: ignore[attr-defined]
        self.assertEqual(
            (procs[700].args, info["args_cached"]), ("postgres: writer", 1)
        )
        moved = dict(TABLE)
        moved[700] = TABLE[700]._replace(sec=SEC + 1)  # same pid, new start: re-read
        r3 = fake_reader()
        table(reader=r3, kern=lambda: dict(moved))
        self.assertIn(700, r3.calls)  # type: ignore[attr-defined]

    def test_an_empty_kernel_read_raises_for_the_ps_fallback(self) -> None:
        with self.assertRaises(RuntimeError):
            table(kern=lambda: {})


def ps_view(procs, ttys):
    return dict(procs), dict(ttys)


class Compare(Base):
    def test_identical_censuses_read_zero_on_every_field(self) -> None:
        procs, ttys, _ = table()
        c = P.compare(procs, ttys, procs, ttys, pre=dict(TABLE))
        self.assertEqual(set(c["mismatch"].values()), {0})
        self.assertEqual(c["rows"]["common"], len(TABLE))

    def test_mismatches_are_counted_by_field_and_carry_no_argv_text(self) -> None:
        procs, ttys, _ = table()
        ps = dict(procs)
        ps[500] = dc_replace(ps[500], ppid=1)
        ps[400] = dc_replace(ps[400], args="claude --resume other-session-id")
        ps_t = dict(ttys)
        ps_t[300] = "ttys009"
        c = P.compare(ps, ps_t, procs, ttys)
        self.assertEqual(
            (c["mismatch"]["ppid"], c["mismatch"]["args_claude"], c["mismatch"]["tty"]),
            (1, 1, 1),
        )
        self.assertEqual(c["pids"]["ppid"], [500])
        blob = json.dumps(c)
        self.assertNotIn("other-session-id", blob)
        self.assertNotIn("0123abcd", blob)
        self.assertEqual(len(c["claude_tokens"][0]["ps"]), 12)

    def test_a_difference_ps_shares_with_the_pre_read_is_churn(self) -> None:
        procs, ttys, _ = table()
        pre = dict(TABLE)
        pre[500] = TABLE[500]._replace(ppid=1)  # reparented while ps ran
        ps = dict(procs)
        ps[500] = dc_replace(ps[500], ppid=1)
        c = P.compare(ps, ttys, procs, ttys, pre=pre)
        self.assertEqual((c["mismatch"]["ppid"], c["churn"]), (0, 1))

    def test_a_young_process_args_are_churn(self) -> None:
        procs, ttys, _ = table()
        ps = dict(procs)
        ps[400] = dc_replace(ps[400], args="claude")
        c = P.compare(ps, ttys, procs, ttys, pre=dict(TABLE), young_after=SEC - 1)
        self.assertEqual((c["mismatch"]["args_claude"], c["churn"]), (0, 1))


class Mode(Base):
    def test_off_file_wins_env_decides_default_is_off(self) -> None:
        self.assertEqual(P.mode(self.paths, {}), "off")
        self.assertEqual(P.mode(self.paths, {"LR_RECON_PSFREE": "shadow"}), "shadow")
        self.assertEqual(P.mode(self.paths, {"LR_RECON_PSFREE": " ON "}), "on")
        self.assertEqual(P.mode(self.paths, {"LR_RECON_PSFREE": "yes"}), "off")
        os.makedirs(self.paths.root)
        open(self.paths.p(P.OFF_FILE), "w").close()
        self.assertEqual(P.mode(self.paths, {"LR_RECON_PSFREE": "on"}), "off")

    def test_mode_file_sits_below_the_env_and_below_the_off_file(self) -> None:
        os.makedirs(self.paths.root)
        with open(self.paths.p(P.MODE_FILE), "w") as fh:
            fh.write("shadow\n")
        self.assertEqual(P.mode(self.paths, {}), "shadow")
        self.assertEqual(P.mode(self.paths, {"LR_RECON_PSFREE": "off"}), "off")
        self.assertEqual(P.mode(self.paths, {"LR_RECON_PSFREE": "bogus"}), "shadow")
        with open(self.paths.p(P.MODE_FILE), "w") as fh:
            fh.write("sideways")
        self.assertEqual(P.mode(self.paths, {}), "off")
        with open(self.paths.p(P.MODE_FILE), "w") as fh:
            fh.write("on")
        open(self.paths.p(P.OFF_FILE), "w").close()
        self.assertEqual(P.mode(self.paths, {}), "off")

    def test_no_paths_resolves_the_tree_from_env(self) -> None:
        env = {"HOME": self.dir, "LR_STATE_DIR": self.dir, "LR_RECON_PSFREE": "on"}
        self.assertEqual(P.mode(None, env), "on")
        os.makedirs(self.paths.root)
        open(self.paths.p(P.OFF_FILE), "w").close()
        self.assertEqual(P.mode(None, env), "off")


class Shadow(Base):
    def test_log_drops_private_keys_and_rotates(self) -> None:
        P.shadow_log(self.paths, {"a": 1, "_krows": {1: 2}})
        self.assertEqual(self.shadow_rows(), [{"a": 1}])
        with mock.patch.object(P, "SHADOW_LOG_MAX_BYTES", 1):
            P.shadow_log(self.paths, {"b": 2})
        self.assertEqual(self.shadow_rows(), [{"b": 2}])
        self.assertTrue(
            os.path.exists(os.path.join(self.paths.shadow, P.SHADOW_LOG + ".1"))
        )
        P.shadow_log(None, {"c": 3})  # no tree: nothing, no raise

    def test_parity_counts_the_trailing_clean_run(self) -> None:
        def row(ok=True, **m):
            mm = {
                f: 0
                for f in (
                    "ppid",
                    "zombie",
                    "lstart",
                    "tty",
                    "args_claude",
                    "args_other",
                )
            }
            mm.update(m)
            return json.dumps(
                {
                    "ps_ok": ok,
                    "pf_ok": True,
                    "cmp": {"mismatch": mm},
                    "pf": {"ms": {"table": 4}},
                }
            )

        lines = [
            row(),
            row(lstart=1),
            row(),
            row(args_other=5),
            row(ok=False),
            row(),
            "torn{",
        ]
        s = P.parity_summary(lines)
        self.assertEqual((s["passes"], s["clean_run"], s["ps_blind_pf_ok"]), (5, 3, 1))
        self.assertEqual(s["mismatch_totals"]["args_other"], 5)
        s = P.parity_summary(
            lines + [json.dumps({"point": "fence.stat", "agree": False}), row()]
        )
        self.assertEqual((s["clean_run"], s["point_disagree"]), (1, 1))

    def test_shadow_point_logs_only_a_real_disagreement(self) -> None:
        env = {"HOME": self.dir, "LR_STATE_DIR": self.dir}
        with mock.patch.dict(os.environ, env):
            P.shadow_point("x", 1, LSTART, LSTART)
            P.shadow_point("x", 1, LSTART, None)
            P.shadow_point("x", 1, LSTART, "")
            self.assertEqual(self.shadow_rows(), [])
            P.shadow_point("x", 1, LSTART, "Tue Oct 27 00:00:00 2026")
        self.assertEqual(self.shadow_rows()[0]["point"], "x")


PS_PROCS = {
    400: T.ProcRow(
        400, 300, "S", LSTART, "claude --resume 0123abcd-0000-4000-8000-0123456789ab"
    )
}


class Census(Base):
    """observe.read_census: the mode decides who reads; shadow never changes the decider."""

    def pf(self):
        return table()

    def test_off_is_the_ps_path_alone(self) -> None:
        snap = snapshot()
        boom = mock.Mock(side_effect=AssertionError("ps-free read in off mode"))
        got = O.read_census(
            snap, "off", paths=self.paths, pf_read=boom, ps_read=lambda: (PS_PROCS, {})
        )
        self.assertEqual(got, (PS_PROCS, {}))
        self.assertEqual(self.shadow_rows(), [])

    def test_shadow_returns_ps_and_logs_parity(self) -> None:
        snap = snapshot()
        got = O.read_census(
            snap, "shadow", paths=self.paths, pf_read=self.pf, pre_read=lambda: dict(TABLE),
            ps_read=lambda: (PS_PROCS, {400: "ttys003"}),
        )  # fmt: skip
        self.assertIs(got[0], PS_PROCS)
        (row,) = self.shadow_rows()
        self.assertTrue(row["ps_ok"] and row["pf_ok"])
        self.assertEqual(row["cmp"]["rows"]["common"], 1)
        self.assertEqual(set(row["cmp"]["mismatch"].values()), {0})
        self.assertNotIn("_krows", row["pf"])
        self.assertEqual(snap.degraded, [])

    def test_shadow_with_ps_blind_logs_then_raises(self) -> None:
        def ps():
            raise RuntimeError("/bin/ps pid=: timed out at 42s")

        with self.assertRaises(RuntimeError):
            O.read_census(
                snapshot(),
                "shadow",
                paths=self.paths,
                pf_read=self.pf,
                ps_read=ps,
            )
        (row,) = self.shadow_rows()
        self.assertEqual((row["ps_ok"], row["pf_ok"]), (False, True))
        self.assertIn("timed out", row["ps_err"])

    def test_shadow_survives_a_failed_ps_free_read(self) -> None:
        def pf():
            raise OSError(12, "ENOMEM")

        got = O.read_census(snapshot(), "shadow", paths=self.paths, pf_read=pf,
                            pre_read=pf, ps_read=lambda: (PS_PROCS, {}))  # fmt: skip
        self.assertIs(got[0], PS_PROCS)
        self.assertFalse(self.shadow_rows()[0]["pf_ok"])

    def test_on_reads_in_process_and_falls_back_to_ps(self) -> None:
        snap = snapshot()
        ps = mock.Mock(return_value=(PS_PROCS, {}))
        procs, ttys = O.read_census(
            snap, "on", paths=self.paths, pf_read=self.pf, ps_read=ps
        )
        ps.assert_not_called()
        self.assertEqual(len(procs), len(TABLE))
        self.assertEqual(O.untrusted(snapshot(procs=procs), None), "")

        def pf():
            raise OSError(1, "EPERM")

        snap = snapshot()
        self.assertIs(
            O.read_census(snap, "on", paths=self.paths, pf_read=pf, ps_read=ps)[0],
            PS_PROCS,
        )
        self.assertIn("EPERM", snap.degraded_why["ps-free"])
        self.assertNotIn("ps", snap.degraded)

    def test_on_with_an_unread_holder_argv_abstains(self) -> None:
        def pf():
            procs, ttys, info = table()
            info["critical_unread"] = [400]
            return procs, ttys, info

        snap = snapshot()
        snap.procs, _ = O.read_census(snap, "on", paths=self.paths, pf_read=pf)
        self.assertIn("ps-args", snap.degraded)
        self.assertIn("400", O.untrusted(snap, None))

    def test_observe_with_an_injected_run_keeps_ps_whatever_the_env_says(self) -> None:
        calls: List[List[str]] = []

        def run(argv, **kw):
            calls.append(argv)
            raise RuntimeError("no ps here")

        with (
            mock.patch.dict(os.environ, {"LR_RECON_PSFREE": "on"}),
            mock.patch.object(
                P,
                "read_table",
                side_effect=AssertionError("ps-free read under an injected run"),
            ),
        ):
            snap = O.observe(None, self.dir, run=run)
        self.assertIn("ps", snap.degraded)
        self.assertEqual(calls[0][0], "/bin/ps")


class EnvRead(Base):
    def test_on_reads_the_env_block_and_falls_back_to_ps_when_it_reads_nothing(
        self,
    ) -> None:
        ps_env = mock.Mock(return_value={1: {"KITTY_PID": "9"}})
        with mock.patch.object(O, "read_ps_env", ps_env):
            got = O._env_read(
                None, [1], "on", env_read=lambda pids: {1: {"KITTY_PID": "100"}}
            )
            self.assertEqual(got, {1: {"KITTY_PID": "100"}})
            ps_env.assert_not_called()
            self.assertEqual(
                O._env_read(None, [1], "on", env_read=lambda pids: {}),
                {1: {"KITTY_PID": "9"}},
            )
            self.assertEqual(
                O._env_read(None, [1], "shadow", env_read=lambda pids: {}),
                {1: {"KITTY_PID": "9"}},
            )


class StoreAndFence(Base):
    def env(self, mode: str) -> Dict[str, str]:
        return {"HOME": self.dir, "LR_STATE_DIR": self.dir, "LR_RECON_PSFREE": mode}

    def test_store_on_reads_kern_proc_pid_first(self) -> None:
        with (
            mock.patch.dict(os.environ, self.env("on")),
            mock.patch.object(P, "proc_lstart", return_value=LSTART),
            mock.patch.object(
                S, "_proc_lstart_classic", side_effect=AssertionError("classic read")
            ),
        ):
            self.assertEqual(S.proc_lstart(4242), LSTART)

    def test_store_shadow_keeps_the_classic_answer_and_logs_a_disagreement(
        self,
    ) -> None:
        with (
            mock.patch.dict(os.environ, self.env("shadow")),
            mock.patch.object(
                P, "proc_lstart", return_value="Tue Oct 27 00:00:00 2026"
            ),
            mock.patch.object(S, "_proc_lstart_classic", return_value=LSTART),
        ):
            self.assertEqual(S.proc_lstart(4242), LSTART)
        self.assertEqual(self.shadow_rows()[0]["point"], "store.proc_lstart")

    def test_store_off_and_an_injected_run_never_read_in_process(self) -> None:
        with mock.patch.object(
            P, "proc_lstart", side_effect=AssertionError("ps-free read")
        ):
            with (
                mock.patch.dict(os.environ, self.env("off")),
                mock.patch.object(S, "_proc_lstart_classic", return_value=LSTART),
            ):
                self.assertEqual(S.proc_lstart(4242), LSTART)
            with mock.patch.dict(os.environ, self.env("on")):

                def fake(argv, **kw):
                    return SimpleNamespace(
                        returncode=0, stdout="Mon Oct 26  07:10:40 2026\n"
                    )

                self.assertEqual(S.proc_lstart(4242, run=fake), LSTART)

    def test_fence_on_reads_in_process_shadow_lets_ps_decide(self) -> None:
        with (
            mock.patch.dict(os.environ, self.env("on")),
            mock.patch.object(fence, "_ps", side_effect=AssertionError("ps")),
            mock.patch.object(P, "proc_lstart", return_value=LSTART),
            mock.patch.object(P, "proc_stat", return_value="S"),
        ):
            self.assertTrue(fence.proc_alive(4242, "Mon Oct 26  07:10:40 2026"))
        with (
            mock.patch.dict(os.environ, self.env("on")),
            mock.patch.object(P, "proc_lstart", return_value=LSTART),
            mock.patch.object(P, "proc_stat", return_value="Z"),
        ):
            self.assertFalse(fence.proc_alive(4242, LSTART))
        ps = {"lstart": "Mon Oct 26 07:10:40 2026", "stat": "Ss"}
        with (
            mock.patch.dict(os.environ, self.env("shadow")),
            mock.patch.object(fence, "_ps", side_effect=lambda f, pid: ps[f]),
            mock.patch.object(P, "proc_lstart", return_value=LSTART),
            mock.patch.object(P, "proc_stat", return_value="Z"),
        ):
            self.assertTrue(fence.proc_alive(4242, LSTART))
        self.assertEqual([r["point"] for r in self.shadow_rows()], ["fence.stat"])

    def test_fence_on_falls_back_to_ps_when_the_kernel_read_fails(self) -> None:
        with (
            mock.patch.dict(os.environ, self.env("on")),
            mock.patch.object(
                fence,
                "_ps",
                side_effect=lambda f, pid: {"lstart": LSTART, "stat": "S"}[f],
            ),
            mock.patch.object(P, "proc_lstart", return_value=None),
            mock.patch.object(P, "proc_stat", return_value=None),
        ):
            self.assertTrue(fence.proc_alive(4242, LSTART))


@unittest.skipUnless(sys.platform == "darwin", "KERN_PROC_ALL is darwin's")
class LiveKernel(Base):
    """The real sysctl, read for this process only (no other target's VM is touched)."""

    def test_own_row_matches_proc_pidinfo_and_own_argv_reads(self) -> None:
        me = os.getpid()
        rows = P.kern_proc_all()
        self.assertIn(me, rows)
        self.assertEqual(rows[me].ppid, os.getppid())
        self.assertEqual(rows[me].uid, os.geteuid())
        want = S.inproc_lstart(me)
        self.assertEqual(P.proc_lstart(me), want)
        self.assertEqual(P.proc_stat(me), "S")
        self.assertEqual(P.proc_lstart(2**30), "")
        argv, _ = P.procargs2(me)  # type: ignore[misc]
        self.assertTrue(
            argv and b"python" in argv[0].lower() or b"unittest" in b" ".join(argv)
        )
        self.assertEqual(
            rows[1].comm, "launchd"
        )  # a root row, refused by proc_pidinfo, is here


if __name__ == "__main__":
    unittest.main()
